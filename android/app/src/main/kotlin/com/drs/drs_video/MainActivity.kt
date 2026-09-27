package com.drs.drs_video

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.MediaStore
import android.util.Rational
import android.util.Size
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Native bridge for DRS Video:
///  - MediaStore video queries + thumbnails + system delete dialog
///  - MediaScanner integration for downloaded files
///  - Storage stats (StatFs)
///  - Picture-in-Picture (manual + auto-enter on Android 12+)
///  - Window brightness (gesture control)
class MainActivity : AudioServiceActivity() {

    private val channelName = "drs.video/native"
    private var autoPip = false
    private var pendingDeleteResult: MethodChannel.Result? = null

    // Incoming share/view intents (v1.3.0). The URL from the launching
    // intent is held here until Flutter pulls it (intent/initial); once
    // the Dart listener is registered, later intents are pushed directly.
    private var pendingIntentUrl: String? = null
    private var flutterChannel: MethodChannel? = null

    companion object {
        const val REQ_DELETE = 4242
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Idempotent; already active since Application.attachBaseContext,
        // re-installed here defensively for process-restored activities.
        CrashGuard.install(applicationContext)
        super.onCreate(savedInstanceState)
        pendingIntentUrl = extractSharedUrl(intent)
    }

    private fun extractSharedUrl(intent: Intent?): String? {
        if (intent == null) return null
        val raw = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }?.trim().takeUnless { it.isNullOrEmpty() } ?: return null
        // Accept only schemes the player really supports — never hijack
        // arbitrary content URIs.
        val lower = raw.lowercase()
        val ok = lower.startsWith("http://") || lower.startsWith("https://") ||
            lower.startsWith("rtsp://") || lower.startsWith("rtmp://") ||
            lower.startsWith("rtmps://") || lower.startsWith("mms://") ||
            lower.startsWith("ftp://") || lower.startsWith("ftps://") ||
            lower.startsWith("sftp://")
        return if (ok) raw else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val url = extractSharedUrl(intent) ?: return
        val ch = flutterChannel
        if (ch != null) {
            try {
                ch.invokeMethod("intent/url", url)
            } catch (_: IllegalStateException) {
                // Engine tearing down — nothing to deliver to.
            }
        } else {
            pendingIntentUrl = url
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        flutterChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                handleCall(call, result)
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        flutterChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "crash/nativeLog" -> result.success(CrashGuard.read(applicationContext))
            "crash/clearAll" -> {
                CrashGuard.clear(applicationContext)
                result.success(null)
            }
            "media/videos" -> queryVideos(result)
            "media/thumbnail" -> thumbnail(call, result)
            "media/delete" -> deleteVideos(call, result)
            "media/scan" -> {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                }
                result.success(null)
            }
            "storage/free" -> {
                val path = call.argument<String>("path")
                val stat = StatFs(path ?: filesDir.path)
                result.success(stat.availableBytes)
            }
            "storage/total" -> {
                val path = call.argument<String>("path")
                val stat = StatFs(path ?: filesDir.path)
                result.success(stat.totalBytes)
            }
            "pip/start" -> startPip(call, result)
            "pip/auto" -> {
                autoPip = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }
            "pip/supported" -> result.success(
                // PictureInPictureParams exists only on API 26+; touching
                // the feature flag alone is NOT enough on Android 7.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
            )
            "intent/initial" -> {
                result.success(pendingIntentUrl)
                pendingIntentUrl = null
            }
            "window/brightness" -> {
                val value = call.argument<Double>("value")
                val lp = window.attributes
                lp.screenBrightness = value?.toFloat()
                    ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                window.attributes = lp
                result.success(null)
            }
            "window/secure" -> {
                // FLAG_SECURE (v1.10.0 private vault): blocks screenshots,
                // screen recording and the recents thumbnail while active.
                val secure = call.argument<Boolean>("secure") ?: false
                if (secure) {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            "settings/allFiles" -> {
                // The all-files-access settings screen exists on Android 11+.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.error("UNSUPPORTED", "all-files access requires Android 11+", null)
                    return
                }
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(null)
            }
            "open/external" -> {
                // Escape hatch when the in-app WebView is unavailable or a
                // site refuses to render: hand the URL to the system.
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("BAD_ARGS", "url required", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // No external browser/handler installed.
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun queryVideos(result: MethodChannel.Result) {
        val videos = ArrayList<Map<String, Any?>>()
        val projection = mutableListOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.DATA
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.Video.Media.DURATION)
        }
        val collection: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

        val cursor = contentResolver.query(collection, projection.toTypedArray(), null, null, sortOrder)
        if (cursor != null) {
            cursor.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val widthCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
                val heightCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
                val dateCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_ADDED)
                val pathCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                val durationCol =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                    } else -1

                while (c.moveToNext()) {
                    val map = HashMap<String, Any?>()
                    map["id"] = c.getLong(idCol)
                    map["title"] = c.getString(nameCol) ?: "video"
                    map["sizeBytes"] = c.getLong(sizeCol)
                    map["width"] = c.getInt(widthCol)
                    map["height"] = c.getInt(heightCol)
                    map["addedAt"] = c.getLong(dateCol) * 1000L
                    map["path"] = c.getString(pathCol) ?: ""
                    if (durationCol >= 0) map["durationMs"] = c.getLong(durationCol)
                    videos.add(map)
                }
            }
        }
        result.success(videos)
    }

    private fun thumbnail(call: MethodCall, result: MethodChannel.Result) {
        val id: Int = call.argument<Int>("id") ?: run {
            result.success(null)
            return
        }
        val dir = File(cacheDir, "thumbs")
        if (!dir.exists()) dir.mkdirs()
        val outFile = File(dir, "ms$id.jpg")

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val uri = ContentUris.withAppendedId(
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id.toLong()
                )
                val bitmap = contentResolver.loadThumbnail(uri, Size(320, 320), null)
                val fos = FileOutputStream(outFile)
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, fos)
                fos.close()
            } else {
                @Suppress("DEPRECATION")
                val bitmap = MediaStore.Video.Thumbnails.getThumbnail(
                    contentResolver, id.toLong(),
                    MediaStore.Video.Thumbnails.MINI_KIND, null
                )
                if (bitmap == null) {
                    result.success(null)
                    return
                }
                val fos = FileOutputStream(outFile)
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, fos)
                fos.close()
            }
            result.success(outFile.path)
        } catch (e: Exception) {
            result.success(null)
        }
    }

    private fun deleteVideos(call: MethodCall, result: MethodChannel.Result) {
        val paths: List<String> = call.argument<List<String>>("paths") ?: emptyList()
        if (paths.isEmpty()) {
            result.success(false)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val uris = ArrayList<Uri>()
            for (path in paths) {
                val uri = lookupVideoUri(path)
                if (uri != null) uris.add(uri)
            }
            if (uris.isEmpty()) {
                result.success(false)
                return
            }
            try {
                val pi: PendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                pendingDeleteResult = result
                startIntentSenderForResult(pi.intentSender, REQ_DELETE, null, 0, 0, 0)
            } catch (e: Exception) {
                result.success(false)
            }
        } else {
            var allOk = true
            for (path in paths) {
                val f = File(path)
                val deleted = if (f.exists()) f.delete() else false
                if (!deleted) {
                    val n = contentResolver.delete(
                        MediaStore.Files.getContentUri("external"),
                        "${MediaStore.MediaColumns.DATA}=?", arrayOf(path)
                    )
                    if (n <= 0) allOk = false
                }
            }
            result.success(allOk)
        }
    }

    private fun lookupVideoUri(path: String): Uri? {
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val cursor = contentResolver.query(
            collection,
            arrayOf(MediaStore.Video.Media._ID),
            "${MediaStore.MediaColumns.DATA}=?",
            arrayOf(path),
            null
        )
        var found: Uri? = null
        if (cursor != null) {
            cursor.use { c ->
                if (c.moveToFirst()) {
                    found = ContentUris.withAppendedId(collection, c.getLong(0))
                }
            }
        }
        return found
    }

    private fun startPip(call: MethodCall, result: MethodChannel.Result) {
        // Guard BEFORE any reference to API-26+ classes (Android 7 safe).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            result.error("PIP_UNSUPPORTED", "PiP requires Android 8+", null)
            return
        }
        val width = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
        val height = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
        val ratio = sanitizeRatio(width, height)
        val params: PictureInPictureParams.Builder =
            PictureInPictureParams.Builder().setAspectRatio(ratio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setAutoEnterEnabled(autoPip)
        }
        enterPictureInPictureMode(params.build())
        result.success(null)
    }

    private fun sanitizeRatio(w: Int, h: Int): Rational {
        var width = w.coerceAtLeast(1)
        var height = h.coerceAtLeast(1)
        val raw = width.toDouble() / height.toDouble()
        if (raw > 2.39) {
            width = 239
            height = 100
        }
        if (raw < 1.0 / 2.39) {
            width = 100
            height = 239
        }
        return Rational(width, height)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // PiP requires API 26+ (PictureInPictureParams); auto-enter requires S.
        if (autoPip &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9)).build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_DELETE) {
            val ok = resultCode == RESULT_OK
            pendingDeleteResult?.success(ok)
            pendingDeleteResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
