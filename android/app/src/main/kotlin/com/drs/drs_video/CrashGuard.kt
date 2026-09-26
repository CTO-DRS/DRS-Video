package com.drs.drs_video

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Process-wide crash capture installed at the EARLIEST possible moment:
 * Application.attachBaseContext — which runs BEFORE any ContentProvider,
 * plugin initializer or Activity code can execute.
 *
 * Why this matters: crashes during the pre-Flutter phase (ContentProvider
 * init, plugin registration, native lib loading) kill the process before
 * any Dart handler or widget can ever exist — the user just sees the app
 * close with zero information. This guard persists the full stack trace +
 * device context to filesDir, and the Dart layer reads it back on the next
 * launch (boot screen card + Settings > Diagnostics).
 *
 * The handler is deliberately defensive: if writing the log itself fails,
 * it silently delegates to the previous handler — it must never make the
 * crash worse.
 */
object CrashGuard {
    private const val FILE_NAME = "drs_native_crash.txt"
    private const val MAX_STACK_LINES = 80

    @Volatile
    private var installed = false

    /** Idempotent: safe to call from both Application and Activity. */
    fun install(context: Context) {
        if (installed) return
        installed = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                write(context.applicationContext, thread, throwable)
            } catch (_: Throwable) {
                // Never let the forensic writer mask or worsen a crash.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    fun read(context: Context): String? = try {
        val f = File(context.filesDir, FILE_NAME)
        if (f.exists() && f.length() > 0) f.readText() else null
    } catch (_: Throwable) {
        null
    }

    fun clear(context: Context) {
        try {
            File(context.filesDir, FILE_NAME).delete()
        } catch (_: Throwable) {
        }
    }

    private fun write(context: Context, thread: Thread, t: Throwable) {
        val sw = StringWriter()
        t.printStackTrace(PrintWriter(sw))
        val stack = sw.toString().split('\n').take(MAX_STACK_LINES).joinToString("\n")

        val text = buildString {
            appendLine("=== NATIVE / JVM CRASH (pre-Flutter phase) ===")
            appendLine("time: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())}")
            appendLine("device: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
            appendLine("android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
            appendLine("app: ${appVersion(context)}")
            appendLine("thread: ${thread.name}")
            appendLine("exception: ${t.javaClass.name}: ${t.message ?: ""}")
            appendLine("causedBy: ${t.cause?.javaClass?.name ?: "-"}")
            appendLine("stack:")
            appendLine(stack)
        }

        val dir = context.filesDir
        if (dir != null) {
            dir.mkdirs()
            File(dir, FILE_NAME).writeText(text)
        }
    }

    private fun appVersion(context: Context): String = try {
        val pm = context.packageManager
        val pi = pm.getPackageInfo(context.packageName, 0)
        "${pi.packageName} ${pi.versionName} (${pi.longVersionCode})"
    } catch (_: Throwable) {
        context.packageName
    }
}
