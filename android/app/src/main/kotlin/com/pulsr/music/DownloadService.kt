package com.pulsr.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * B-07 fix: Foreground Service for downloads (dataSync / mediaProcessing).
 *
 * Keeps YouTube downloads alive when the app is backgrounded, screen-off, or under
 * Doze/App Standby. Without this, WAKE_LOCK alone does not prevent the Android 12+
 * freezer from stalling the Dart HttpClient. Uses typed FGS: Android 14 (API 34)
 * -> dataSync; Android 15+ (API 35) -> mediaProcessing (preferred for heavy media
 * work and no longer subject to the dataSync 6h/24h cap semantics); below API 29
 * -> untyped startForeground.
 *
 * Features:
 * - Persistent notification with progress, pause & cancel actions
 * - Ongoing grouping for concurrent downloads (max 3)
 * - Auto-stop when queue drains or after idle timeout
 * - Integrates with DownloadRepositoryImpl via YtDownloadPlugin MethodChannel calls
 */
class DownloadService : Service() {

    companion object {
        private const val CHANNEL_ID = "pulsr_downloads"
        private const val NOTIFICATION_ID = 9401
        const val ACTION_START = "com.pulsr.music.download.START"
        const val ACTION_UPDATE = "com.pulsr.music.download.UPDATE"
        const val ACTION_PAUSE = "com.pulsr.music.download.PAUSE"
        const val ACTION_RESUME = "com.pulsr.music.download.RESUME"
        const val ACTION_CANCEL = "com.pulsr.music.download.CANCEL"
        const val ACTION_STOP = "com.pulsr.music.download.STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_VIDEO_ID = "videoId"

        private const val REQUEST_CODE_OPEN = 1001
        private const val REQUEST_CODE_CANCEL = 1002
        private const val REQUEST_CODE_PAUSE = 1003

        fun start(context: Context, videoId: String, title: String) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_VIDEO_ID, videoId)
                putExtra(EXTRA_TITLE, title)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException on Android 12+ background start
                android.util.Log.w("DownloadService", "Foreground service start restricted: ${e.message}")
            }
        }

        fun updateProgress(context: Context, videoId: String, title: String, progress: Int) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_VIDEO_ID, videoId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PROGRESS, progress)
            }
            try {
                // For progress updates the service is already in foreground (started via ACTION_START).
                // Use startService for delivery to avoid ForegroundServiceStartNotAllowedException on Android 14 background.
                // Fallback to startForegroundService only if startService fails.
                try {
                    context.startService(intent)
                } catch (_: Exception) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("DownloadService", "updateProgress start restricted: ${e.message}")
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                android.util.Log.w("DownloadService", "stop start restricted: ${e.message}")
                // Fallback to legacy startService for pre-O or when FGS not allowed
                try { context.startService(intent) } catch (_: Exception) {}
            }
        }
    }

    private var activeDownloads = mutableMapOf<String, Int>() // videoId -> progress 0..100
    private var foregroundStarted = false
    private var lastNotificationTimeMs = 0L
    private var lastEmittedAvgProgress = -1
    private val sessionStartTimeMs = System.currentTimeMillis()

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID) ?: return START_NOT_STICKY
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Downloading"
                activeDownloads[vid] = 0
                ensureForeground(title, 0, force = true)
            }
            ACTION_UPDATE -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID) ?: return START_NOT_STICKY
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Downloading"
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
                activeDownloads[vid] = progress
                // Remove completed ones
                if (progress >= 100) activeDownloads.remove(vid)
                if (activeDownloads.isEmpty()) {
                    stopForegroundAndSelf()
                } else {
                    val display = if (activeDownloads.size == 1) title else "${activeDownloads.size} downloads"
                    val avg = if (activeDownloads.isNotEmpty()) activeDownloads.values.average().toInt() else 0
                    val now = System.currentTimeMillis()

                    // DL-25: Coalesce notification updates: only update if >=1s elapsed or progress delta >= 1%
                    val timeDelta = now - lastNotificationTimeMs
                    val progressDelta = Math.abs(avg - lastEmittedAvgProgress)
                    if (timeDelta >= 1000L || progressDelta >= 1 || avg == 0 || avg == 100) {
                        ensureForeground(display, avg)
                        lastNotificationTimeMs = now
                        lastEmittedAvgProgress = avg
                    }
                }
            }
            ACTION_PAUSE -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (vid != null) activeDownloads.remove(vid)
                if (activeDownloads.isEmpty()) stopForegroundAndSelf() else {
                    val n = notificationFor(activeDownloads.keys.firstOrNull() ?: "Downloads",
                        activeDownloads.values.firstOrNull() ?: 0)
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .notify(NOTIFICATION_ID, n)
                }
            }
            ACTION_CANCEL -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (vid != null) activeDownloads.remove(vid)
                if (activeDownloads.isEmpty()) stopForegroundAndSelf() else {
                    val n = notificationFor(activeDownloads.keys.firstOrNull() ?: "Downloads",
                        activeDownloads.values.firstOrNull() ?: 0)
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .notify(NOTIFICATION_ID, n)
                }
            }
            ACTION_STOP -> {
                activeDownloads.clear()
                stopForegroundAndSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun ensureForeground(title: String, progress: Int, force: Boolean = false) {
        val n = notificationFor(title, progress)
        if (!foregroundStarted) {
            try {
                ServiceCompat.startForeground(this, NOTIFICATION_ID, n, foregroundServiceType())
                foregroundStarted = true
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException on Android 14+ (API 34+) if started while backgrounded
                android.util.Log.w("DownloadService", "Foreground service start restricted: ${e.message}")
            }
        } else {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, n)
        }
    }

    /**
     * Runtime-selected FGS type, matching the manifest's
     * `dataSync|mediaProcessing` declaration:
     *  - API 35+ (Android 15): mediaProcessing — the preferred type for heavy
     *    media work (download → tag/publish); dataSync on 15 is subject to the
     *    6h/24h system-wide cap.
     *  - API 29..34: dataSync — previous behavior kept (typed enforcement with
     *    mediaProcessing starts at API 35; dataSync is required at API 34).
     *  - API < 29: 0 — ServiceCompat.startForeground falls back to the
     *    two-arg startForeground, exactly as before.
     */
    private fun foregroundServiceType(): Int {
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else -> 0
        }
    }



    private fun stopForegroundAndSelf() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        foregroundStarted = false
        activeDownloads.clear()
    }

    private fun notificationFor(title: String, progress: Int): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { base ->
            PendingIntent.getActivity(this, REQUEST_CODE_OPEN, base,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val currentVid = activeDownloads.keys.firstOrNull()
        // Use per-video requestCode to avoid PendingIntent collision with concurrent downloads
        val cancelRequestCode = currentVid?.hashCode()?.let { (REQUEST_CODE_CANCEL * 31 + it) and 0x7FFFFFFF } ?: REQUEST_CODE_CANCEL
        val pauseRequestCode = currentVid?.hashCode()?.let { (REQUEST_CODE_PAUSE * 31 + it) and 0x7FFFFFFF } ?: REQUEST_CODE_PAUSE
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_VIDEO_ID, currentVid)
        }
        val cancelPending = PendingIntent.getService(this, cancelRequestCode, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val pauseIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_PAUSE
            putExtra(EXTRA_VIDEO_ID, currentVid)
        }
        val pausePending = PendingIntent.getService(this, pauseRequestCode, pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(if (progress > 0) "$progress% • Downloading" else "Preparing download…")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, progress == 0)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_media_pause, "Pause", pausePending)
            .addAction(android.R.drawable.ic_delete, "Cancel", cancelPending)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Shows progress for YouTube downloads"
                    setShowBadge(false)
                }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // B1 (c): When task is removed with stopWithTask=false, keep foreground running if active downloads exist
        if (activeDownloads.isEmpty()) {
            stopForegroundAndSelf()
        }
    }

    private val timeoutHandler = DownloadTimeoutHandler(this)

    // C-04 (N-06): API 35+ Foreground Service timeout handling (Android 15 6h FGS limit)
    override fun onTimeout(startId: Int) {
        handleServiceTimeout()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        handleServiceTimeout()
    }

    private fun handleServiceTimeout() {
        timeoutHandler.handleTimeout(activeDownloads)
        stopForeground(STOP_FOREGROUND_REMOVE)
        postTimeoutNotification()
        stopSelf()
        foregroundStarted = false
        activeDownloads.clear()
    }

    private fun postTimeoutNotification() {
        try {
            createChannel()
            val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { base ->
                PendingIntent.getActivity(this, REQUEST_CODE_OPEN, base,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }
            val builder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("Downloads paused")
                .setContentText("Background downloads paused due to system time limit. Tap to resume.")
                .setOngoing(false)
                .setAutoCancel(true)
                .setContentIntent(openIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {}
    }

    private fun Iterable<Int>.average(): Double = if (none()) 0.0 else sum().toDouble() / count()
}
