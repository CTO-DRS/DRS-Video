package com.drs.drs_video

import android.app.Application
import android.content.Context
import androidx.work.Configuration
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
 * WorkManager now initializes ON DEMAND: the first WorkManager
 *.getInstance() call — which happens on the first real download
 * operation — triggers initialization through the Configuration.Provider
 * below. If that ever fails, the Dart download service degrades to an
 * honest retry state; it can never crash the app at startup.
 */
class DrsApplication : Application(), Configuration.Provider {

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // Must be the very first thing that runs, before any provider.
        CrashGuard.install(this)
    }

    override fun onCreate() {
        super.onCreate()
        // Intentionally empty: no WorkManager, no notifications, no media
        // engine, no I/O. Everything optional is lazy in the Dart layer.
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
