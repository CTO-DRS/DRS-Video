package com.drs.drs_video

import android.app.Application
import android.content.Context
import androidx.work.Configuration
import androidx.work.WorkManager
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.Executors

/**
 * DRS Video application class.
 *
 * Startup contract (the fix for the critical pre-Flutter startup crash):
 *
 *   BOOT
 *    -> attachBaseContext: CrashGuard (earliest possible capture)
 *    -> ContentProviders: only safe ones remain — the manual
 *       FlutterDownloaderInitializer and the androidx.startup
 *       WorkManagerInitializer were both REMOVED from the manifest.
 *       (Previously both ran before any UI and double-initialized
 *       WorkManager -> IllegalStateException -> instant close with no
 *       screen at all, on every launch.)
 *    -> MainActivity -> Flutter engine -> Dart main -> runApp -> UI
 *    -> optional services (player engine / downloader / notifications)
 *       initialize lazily, each with its own error state.
 *
 * WorkManager initializes ON DEMAND: the first WorkManager.getInstance()
 * call — which happens on the first real download operation — triggers
 * initialization through the Configuration.Provider below. If that ever
 * fails, the Dart download service degrades to an honest retry state; it
 * can never crash the app at startup.
 */
class DrsApplication : Application(), Configuration.Provider {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // Must be the very first thing that runs, before any provider.
        CrashGuard.install(this)
    }

    override fun onCreate() {
        super.onCreate()
        prewarmWorkManager()
    }

    /**
     * Field-failure fix ("Bad state: enqueue returned null", XOS 15 report):
     *
     * flutter_downloader's native enqueue() has NO try/catch. Any exception
     * inside the on-demand WorkManager init below reaches Dart as a
     * PlatformException that the plugin SWALLOWS and converts to a bare
     * null — which the download service then records as the opaque
     * "Bad state: enqueue returned null", with the real root cause lost.
     *
     * Exercise the exact same initialization ONCE at startup, where a
     * failure is captured verbatim into a diagnostics file (Settings >
     * Diagnostics can surface it) instead of being laundered into null
     * later. This is cheap: no disk I/O beyond what the first download
     * would trigger anyway, and the call is identical to the one the
     * downloader makes. On success, any stale error file from a previous
     * run is cleared so diagnostics always reflect the current build.
     */
    private fun prewarmWorkManager() {
        val marker = File(filesDir, "drs_workmanager_error.txt")
        try {
            WorkManager.getInstance(this)
            if (marker.exists()) marker.delete()
        } catch (t: Throwable) {
            try {
                val sw = StringWriter()
                t.printStackTrace(PrintWriter(sw))
                marker.writeText(
                    "WorkManager on-demand init failed — this is the real "
                        + "reason downloads fail with \"enqueue returned null\":\n\n"
                        + sw.toString()
                )
            } catch (_: Throwable) {
                // The forensic writer must never worsen the failure.
            }
        }
    }

    /**
     * Used by WorkManager.getInstance(context) on first real use.
     * 4 worker threads == the previous MAX_CONCURRENT_TASKS=4 contract.
     */
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setExecutor(Executors.newFixedThreadPool(4))
            .setMinimumLoggingLevel(android.util.Log.WARN)
            .build()
}
