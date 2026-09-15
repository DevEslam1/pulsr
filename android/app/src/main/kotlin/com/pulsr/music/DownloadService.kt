package com.pulsr.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * B-07 fix: Foreground Service for downloads (dataSync).
 *
 * Keeps YouTube downloads alive when the app is backgrounded, screen-off, or under
 * Doze/App Standby. Without this, WAKE_LOCK alone does not prevent the Android 12+
 * freezer from stalling the Dart HttpClient. Uses typed FGS dataSync (Android 14+).
 *
 * Features:
 * - Persistent notification with progress, pause/resume & cancel actions
 * - Ongoing grouping for concurrent downloads (max 3)
 * - Auto-stop when queue drains or after idle timeout
 * - Integrates with DownloadRepositoryImpl via YtDownloadPlugin MethodChannel calls
 */
class DownloadService : Service() {

    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL_ID = "pulsr_downloads"
        private const val NOTIFICATION_ID = 9401
        const val ACTION_START = "com.pulsr.music.download.START"
        const val ACTION_UPDATE = "com.pulsr.music.download.UPDATE"
        const val ACTION_CANCEL = "com.pulsr.music.download.CANCEL"
        const val ACTION_STOP = "com.pulsr.music.download.STOP"

        /** Notification-initiated pause/resume: invoke the Dart listeners (C-7). */
        const val ACTION_PAUSE = "com.pulsr.music.download.PAUSE"
        const val ACTION_RESUME = "com.pulsr.music.download.RESUME"

        /**
         * Dart-initiated pause/resume: refresh the notification only. Kept apart
         * from ACTION_PAUSE/ACTION_RESUME so mirroring the state back from Dart
         * cannot re-enter the Dart listeners.
         */
        const val ACTION_SET_PAUSED = "com.pulsr.music.download.SET_PAUSED"

        const val EXTRA_TITLE = "title"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_VIDEO_ID = "videoId"
        const val EXTRA_PAUSED = "paused"

        private const val REQUEST_CODE_OPEN = 1001
        private const val REQUEST_CODE_CANCEL = 1002
        private const val REQUEST_CODE_PAUSE = 1003
        private const val REQUEST_CODE_RESUME = 1004
        private const val TIMEOUT_NOTIFICATION_ID = 9402

        var onDownloadCancelledListener: ((String) -> Unit)? = null
        var onDownloadPausedListener: ((String) -> Unit)? = null
        var onDownloadResumedListener: ((String) -> Unit)? = null

        /**
         * C-9: raised when foreground coverage could not be obtained or kept, so
         * the transfer continues without FGS protection. Forwarded by
         * YtDownloadPlugin to Dart, which surfaces it to the user.
         */
        var onDownloadDegradedListener: ((String) -> Unit)? = null

        /**
         * Timeout-paused ids that survive [stopForegroundAndSelf]/[onDestroy].
         * onTimeout() must stop the service (Android 15 dataSync budget), which
         * wipes instance maps — without this, the "paused" mark fired to Dart
         * would be lost to any later native read. Dart remains the owner of
         * pause state; this only lets the next service instance know the job
         * was timeout-paused. Guarded by its own monitor (synchronizedSet).
         */
        val timeoutPausedIds: MutableSet<String> =
            java.util.Collections.synchronizedSet(mutableSetOf<String>())

        private fun notifyDegraded(context: Context, stage: String, cause: Throwable?) {
            android.util.Log.w(TAG, "Download continues without foreground protection ($stage)", cause)
            try {
                onDownloadDegradedListener?.invoke(stage)
            } catch (_: Exception) {}
        }

        fun start(context: Context, videoId: String, title: String) {
            val appContext = context.applicationContext ?: context
            val intent = Intent(appContext, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_VIDEO_ID, videoId)
                putExtra(EXTRA_TITLE, title)
            }
            // Android 12+ throws ForegroundServiceStartNotAllowedException when
            // starting an FGS from the background. Never let that crash the app;
            // the Dart side falls back to a WorkManager-safe path.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(intent)
                } else {
                    appContext.startService(intent)
                }
            } catch (e: Exception) {
                // C-9: the old code swallowed both failures, so a download could
                // run (or die) with no foreground coverage and no indication.
                notifyDegraded(appContext, "start", e)
                try {
                    appContext.startService(intent)
                } catch (e2: Exception) {
                    notifyDegraded(appContext, "service", e2)
                }
            }
        }

        fun updateProgress(context: Context, videoId: String, title: String, progress: Int) {
            val appContext = context.applicationContext ?: context
            val intent = Intent(appContext, DownloadService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_VIDEO_ID, videoId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PROGRESS, progress)
            }
            try {
                appContext.startService(intent)
            } catch (_: IllegalStateException) {
                // Background start blocked (Android 8+ background execution limits) — drop the update.
            } catch (_: SecurityException) {
            }
        }

        /** C-7: mirror an in-app pause/resume into the ongoing notification. */
        fun setPaused(context: Context, videoId: String, paused: Boolean) {
            val appContext = context.applicationContext ?: context
            val intent = Intent(appContext, DownloadService::class.java).apply {
                action = ACTION_SET_PAUSED
                putExtra(EXTRA_VIDEO_ID, videoId)
                putExtra(EXTRA_PAUSED, paused)
            }
            try {
                appContext.startService(intent)
            } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            val appContext = context.applicationContext ?: context
            val intent = Intent(appContext, DownloadService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                appContext.startService(intent)
            } catch (_: Exception) {}
        }
    }

    // Concurrent collections: onStartCommand is normally serialized on the main
    // thread, but binder/background callers and listener re-entry must never
    // throw ConcurrentModificationException during iteration (render/timeout).
    private var activeDownloads = java.util.concurrent.ConcurrentHashMap<String, Int>() // videoId -> progress 0..100
    private var downloadTitles = java.util.concurrent.ConcurrentHashMap<String, String>() // videoId -> title
    private val pausedDownloads: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet<String>() // videoId
    private var foregroundStarted = false
    private var degraded = false

    override fun onCreate() {
        super.onCreate()
        createChannel()
        // Restore timeout-paused marks wiped with the previous instance.
        pausedDownloads.addAll(timeoutPausedIds)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID) ?: return START_NOT_STICKY
                val title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
                    ?: getString(R.string.download_notification_default_title)
                activeDownloads[vid] = 0
                downloadTitles[vid] = title
                pausedDownloads.remove(vid)
                timeoutPausedIds.remove(vid)
                renderCurrentNotification(vid)
            }
            ACTION_UPDATE -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID) ?: return START_NOT_STICKY
                val title = intent.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() }
                    ?: getString(R.string.download_notification_default_title)
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
                activeDownloads[vid] = progress
                downloadTitles[vid] = title
                // Remove completed ones
                if (progress >= 100) {
                    activeDownloads.remove(vid)
                    downloadTitles.remove(vid)
                    pausedDownloads.remove(vid)
                    timeoutPausedIds.remove(vid)
                }
                if (activeDownloads.isEmpty()) {
                    stopForegroundAndSelf()
                } else {
                    renderCurrentNotification(vid)
                }
            }
            ACTION_CANCEL -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (vid != null) {
                    activeDownloads.remove(vid)
                    downloadTitles.remove(vid)
                    pausedDownloads.remove(vid)
                    timeoutPausedIds.remove(vid)
                    try { onDownloadCancelledListener?.invoke(vid) } catch (_: Exception) {}
                }
                renderCurrentNotification(activeDownloads.keys.firstOrNull())
            }
            ACTION_PAUSE -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (vid != null) {
                    pausedDownloads.add(vid)
                    renderCurrentNotification(vid)
                    // C-7: the Dart engine owns the transfer; it performs the pause.
                    try { onDownloadPausedListener?.invoke(vid) } catch (_: Exception) {}
                }
            }
            ACTION_RESUME -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                if (vid != null) {
                    pausedDownloads.remove(vid)
                    timeoutPausedIds.remove(vid)
                    renderCurrentNotification(vid)
                    try { onDownloadResumedListener?.invoke(vid) } catch (_: Exception) {}
                }
            }
            ACTION_SET_PAUSED -> {
                val vid = intent.getStringExtra(EXTRA_VIDEO_ID)
                val paused = intent.getBooleanExtra(EXTRA_PAUSED, false)
                if (vid != null) {
                    if (paused) pausedDownloads.add(vid) else {
                        pausedDownloads.remove(vid)
                        timeoutPausedIds.remove(vid)
                    }
                    renderCurrentNotification(vid)
                }
            }
            ACTION_STOP -> {
                activeDownloads.clear()
                downloadTitles.clear()
                pausedDownloads.clear()
                stopForegroundAndSelf()
            }
        }
        return START_NOT_STICKY
    }

    /**
     * Rebuilds the ongoing notification from the current maps and either promotes
     * the service to the foreground or refreshes the existing notification.
     */
    private fun renderCurrentNotification(preferredVid: String?) {
        if (activeDownloads.isEmpty()) {
            stopForegroundAndSelf()
            return
        }
        val vid = if (preferredVid != null && activeDownloads.containsKey(preferredVid)) {
            preferredVid
        } else {
            activeDownloads.keys.first()
        }
        val single = activeDownloads.size == 1
        val title = if (single) {
            downloadTitles[vid] ?: getString(R.string.download_notification_downloads)
        } else {
            getString(R.string.download_notification_count, activeDownloads.size)
        }
        // A single job reports its own progress; several report their average.
        val progress = if (single) {
            activeDownloads[vid] ?: 0
        } else {
            activeDownloads.values.average().toInt()
        }
        // Pause/resume only makes sense for one identifiable download.
        postNotification(title, progress, vid, pausedDownloads.contains(vid), single)
    }

    private fun postNotification(
        title: String,
        progress: Int,
        targetVideoId: String?,
        paused: Boolean,
        showTransport: Boolean
    ) {
        val n = notificationFor(title, progress, targetVideoId, paused, showTransport)
        try {
            if (!foregroundStarted) {
                // FOREGROUND_SERVICE_TYPE_DATA_SYNC exists only on API 34+. Passing
                // it on API 29-33 throws IllegalArgumentException -> crash.
                if (Build.VERSION.SDK_INT >= 34) {
                    startForeground(NOTIFICATION_ID, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                } else {
                    startForeground(NOTIFICATION_ID, n)
                }
                foregroundStarted = true
            } else {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            // C-9: surface the degradation instead of swallowing it. The download
            // itself is not aborted — only its protection is gone.
            degraded = true
            notifyDegraded(this, "foreground", e)
            try {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(NOTIFICATION_ID, notificationFor(title, progress, targetVideoId, paused, showTransport))
            } catch (_: Exception) {}
        }
    }

    private fun stopForegroundAndSelf() {
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        stopSelf()
        foregroundStarted = false
        activeDownloads.clear()
        downloadTitles.clear()
        pausedDownloads.clear()
    }

    private fun transportAction(
        requestCode: Int,
        action: String,
        targetVideoId: String?
    ): PendingIntent {
        val intent = Intent(this, DownloadService::class.java).apply {
            this.action = action
            putExtra(EXTRA_VIDEO_ID, targetVideoId)
            `package` = packageName
        }
        return PendingIntent.getService(this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun notificationFor(
        title: String,
        progress: Int,
        targetVideoId: String?,
        paused: Boolean,
        showTransport: Boolean
    ): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { base ->
            PendingIntent.getActivity(this, REQUEST_CODE_OPEN, base,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_VIDEO_ID, targetVideoId)
            `package` = packageName
        }
        val cancelPending = PendingIntent.getService(this, REQUEST_CODE_CANCEL, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(
                when {
                    paused -> getString(R.string.download_notification_paused, progress)
                    progress > 0 -> getString(R.string.download_notification_progress, progress)
                    else -> getString(R.string.download_notification_preparing)
                }
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, progress == 0 && !paused)
            .setContentIntent(openIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (degraded) {
            builder.setSubText(getString(R.string.download_notification_degraded))
        }

        if (showTransport && targetVideoId != null) {
            if (paused) {
                builder.addAction(
                    android.R.drawable.ic_media_play,
                    getString(R.string.download_notification_action_resume),
                    transportAction(REQUEST_CODE_RESUME, ACTION_RESUME, targetVideoId)
                )
            } else {
                builder.addAction(
                    android.R.drawable.ic_media_pause,
                    getString(R.string.download_notification_action_pause),
                    transportAction(REQUEST_CODE_PAUSE, ACTION_PAUSE, targetVideoId)
                )
            }
        }

        builder.addAction(
            android.R.drawable.ic_delete,
            getString(R.string.download_notification_action_cancel),
            cancelPending
        )

        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.download_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = getString(R.string.download_channel_description)
                    setShowBadge(false)
                }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        activeDownloads.clear()
        downloadTitles.clear()
        pausedDownloads.clear()
        foregroundStarted = false
        // C-8: these are process-global statics. Holding them past the service's
        // life keeps a detached Flutter plugin/channel reachable; clear them here.
        // YtDownloadPlugin re-registers before every startDownloadForeground call.
        onDownloadCancelledListener = null
        onDownloadPausedListener = null
        onDownloadResumedListener = null
        onDownloadDegradedListener = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * B-6: Android 15 (API 35+) applies a cumulative dataSync foreground-time cap
     * and then calls this. An app that does not stop the service inside the grace
     * window is ANR'd or killed, which is how a long download queue used to end on
     * Android 15. Stop the foreground service gracefully, pause the queue and tell
     * the user why, instead of being killed.
     *
     * super.onTimeout is intentionally not relied on: the service is stopped
     * explicitly right here, which is what the platform requires of us.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        android.util.Log.w(TAG, "dataSync foreground-time budget exhausted; pausing downloads")
        // Snapshot before stopForegroundAndSelf() wipes instance maps below —
        // listeners and the timeout notice must see consistent state, and the
        // paused mark must survive the stop via timeoutPausedIds (Dart owns it
        // from the callback onward; native keeps a copy for the next instance).
        val snapshotIds = activeDownloads.keys.toList()
        val target = snapshotIds.firstOrNull()
        val snapshotTitles = snapshotIds.mapNotNull { id ->
            downloadTitles[id]?.let { id to it }
        }.toMap()
        if (target != null) {
            pausedDownloads.add(target)
            timeoutPausedIds.add(target)
            try { onDownloadPausedListener?.invoke(target) } catch (_: Exception) {}
        }
        degraded = true
        notifyDegraded(this, "timeout", null)
        val title = snapshotTitles.values.firstOrNull()
            ?: getString(R.string.download_notification_downloads)
        // Stop the FGS first so its ongoing notification cannot come back, then
        // leave a dismissible notice (separate id) explaining the pause.
        stopForegroundAndSelf()
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(TIMEOUT_NOTIFICATION_ID, timeoutNotification(title))
        } catch (_: Exception) {}
    }

    private fun timeoutNotification(title: String): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.let { base ->
            PendingIntent.getActivity(this, REQUEST_CODE_OPEN, base,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val text = getString(R.string.download_notification_timeout)
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        if (openIntent != null) builder.setContentIntent(openIntent)
        return builder.build()
    }
}
