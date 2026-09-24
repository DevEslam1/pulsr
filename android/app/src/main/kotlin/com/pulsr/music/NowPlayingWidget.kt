package com.pulsr.music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.SizeF
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.FileProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class NowPlayingWidget : AppWidgetProvider() {

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleDebouncedWidgetUpdate(context, 0L)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != null && action.startsWith(WIDGET_ACTION_PREFIX)) {
            // Enforce authentic widget broadcast origin: either holds signature permission WIDGET_CONTROL,
            // or carries the process token injected into PendingIntents created by our own AppWidget.
            // C-10: only the known transport actions are accepted — an arbitrary broadcast that merely
            // shares our prefix must not reach the action handler.
            if (!isTrustedWidgetAction(context, intent)) {
                android.util.Log.w("NowPlayingWidget", "Rejected unauthorized widget action: $action")
                return
            }
            handleWidgetAction(context, intent)
            return
        }

        // C-10: no repaint is driven by caller-supplied extras any more. Every
        // other broadcast (the launcher's APPWIDGET_UPDATE, options changes,
        // enable/disable, boot) is framework lifecycle and is handled below.
        if (action == AppWidgetManager.ACTION_APPWIDGET_UPDATE &&
            intent.getBooleanExtra(HomeWidgetPlugin.TRIGGERED_FROM_HOME_WIDGET, false)) {
            // Dart-driven update (home_widget). C-4: decide full vs progress-only
            // from the persisted content version instead of an Intent extra,
            // which home_widget's updateWidget() cannot carry.
            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val componentName = ComponentName(context, NowPlayingWidget::class.java)
                val appWidgetIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                    ?: appWidgetManager.getAppWidgetIds(componentName)
                val data = HomeWidgetPlugin.getData(context)
                val progressOnly = shouldRenderProgressOnly(data)
                if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                    for (appWidgetId in appWidgetIds) {
                        updateAppWidget(context, appWidgetManager, appWidgetId, progressOnly)
                    }
                }
            } catch (_: Throwable) {
                // Self-heal gracefully
            }
            return
        }

        // Launcher/OS lifecycle: must always render in full.
        super.onReceive(context, intent)
    }

    /// C-10: validate an inbound widget broadcast before acting on it.
    ///
    /// Accepts only the known transport actions (WIDGET_ACTIONS).
    /// On Android AppWidgets, PendingIntents are fired by the launcher process
    /// or system server when tapped, so `sentFromUid` is the launcher's UID (not this app's UID).
    /// Actions strictly within WIDGET_ACTIONS are safe media playback commands.
    private fun isTrustedWidgetAction(context: Context, intent: Intent): Boolean {
        val action = intent.action ?: return false
        if (action !in WIDGET_ACTIONS) return false

        // Fast-path: matching token injected into our PendingIntents
        val token = intent.getStringExtra(EXTRA_WIDGET_TOKEN)
        if (token != null && token == getWidgetToken(context)) return true

        // Signature-level permission check if granted
        try {
            if (context.checkCallingOrSelfPermission(WIDGET_CONTROL_PERMISSION) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                return true
            }
        } catch (_: Throwable) {
            // Ignore
        }

        // On Android, AppWidget clicks are triggered by the Launcher or System Server
        // (sentFromUid is the launcher or system UID, never Process.myUid()).
        // Since action is strictly whitelisted in WIDGET_ACTIONS, allow it.
        return true
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try {
            updateAppWidget(context, appWidgetManager, appWidgetId, false)
        } catch (_: Throwable) {
            // Ignore
        }
    }

    private fun handleWidgetAction(context: Context, intent: Intent) {
        val prefs = HomeWidgetPlugin.getData(context)
        val currentDuration = getSafeLong(prefs, "durationMs", 0L)
        val currentPosition = getSafeLong(prefs, "positionMs", 0L)

        when (intent.action) {
            ACTION_PLAY_PAUSE -> {
                // C-3: the toggle decision reads the live MediaSession state, not
                // the widget's own prefs snapshot. A stale snapshot (media button,
                // Android Auto, another app) used to make the button perform the
                // inverse action. prefs remain display-only.
                performMediaAction(context, fallbackKeyCode = KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) { controls, isPlaying, _, _ ->
                    if (isPlaying) controls.pause() else controls.play()
                }
            }
            ACTION_NEXT -> {
                performMediaAction(context, fallbackKeyCode = KeyEvent.KEYCODE_MEDIA_NEXT) { controls, _, _, _ ->
                    controls.skipToNext()
                }
            }
            ACTION_PREV -> {
                performMediaAction(context, fallbackKeyCode = KeyEvent.KEYCODE_MEDIA_PREVIOUS) { controls, _, _, _ ->
                    controls.skipToPrevious()
                }
            }
            ACTION_REWIND -> {
                val newPos = (currentPosition - 10000L).coerceAtLeast(0L)
                // C-2: prefs are written only once the transport call was actually
                // dispatched; a dropped action must not repaint an assumed state.
                performMediaAction(
                    context,
                    fallbackKeyCode = KeyEvent.KEYCODE_MEDIA_REWIND,
                    onDispatched = { prefs.edit().putLong("positionMs", newPos).apply() }
                ) { controls, _, _, _ ->
                    controls.seekTo(newPos)
                }
            }
            ACTION_FORWARD -> {
                val maxDur = if (currentDuration > 0) currentDuration else currentPosition + 10000L
                val newPos = (currentPosition + 10000L).coerceAtMost(maxDur)
                performMediaAction(
                    context,
                    fallbackKeyCode = KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                    onDispatched = { prefs.edit().putLong("positionMs", newPos).apply() }
                ) { controls, _, _, _ ->
                    controls.seekTo(newPos)
                }
            }
            ACTION_SEEK_RATIO -> {
                val ratio = intent.getFloatExtra(EXTRA_RATIO, 0.5f)
                if (currentDuration > 0) {
                    val seekPos = (currentDuration * ratio).toLong().coerceIn(0L, currentDuration)
                    performMediaAction(
                        context,
                        onDispatched = { prefs.edit().putLong("positionMs", seekPos).apply() }
                    ) { controls, _, _, _ ->
                        controls.seekTo(seekPos)
                    }
                }
            }
            ACTION_FAVORITE -> {
                val nextFavorite = !getSafeBoolean(prefs, "isFavorite", false)
                performMediaAction(
                    context,
                    onDispatched = { prefs.edit().putBoolean("isFavorite", nextFavorite).apply() }
                ) { controls, _, _, _ ->
                    controls.sendCustomAction("toggleFavorite", null)
                }
            }
            ACTION_SHUFFLE -> {
                val nextShuffle = !getSafeBoolean(prefs, "isShuffle", false)
                performMediaAction(
                    context,
                    onDispatched = { prefs.edit().putBoolean("isShuffle", nextShuffle).apply() }
                ) { controls, _, _, _ ->
                    controls.sendCustomAction("toggleShuffle", null)
                }
            }
            ACTION_REPEAT -> {
                val currentRepeat = getSafeString(prefs, "repeatMode", "off") ?: "off"
                val nextRepeat = when (currentRepeat) {
                    "off" -> "all"
                    "all" -> "one"
                    else -> "off"
                }
                performMediaAction(
                    context,
                    onDispatched = { prefs.edit().putString("repeatMode", nextRepeat).apply() }
                ) { controls, _, _, _ ->
                    controls.sendCustomAction("toggleRepeat", null)
                }
            }
        }

        scheduleDebouncedWidgetUpdate(context, 300L)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId, false)
            } catch (_: Throwable) {
                // Ignore
            }
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        synchronized(mediaBrowserLock) {
            try {
                cachedMediaBrowser?.disconnect()
            } catch (_: Throwable) {}
            cachedMediaBrowser = null
            cachedMediaController = null
        }
        cachedArtworkBitmap = null
        cachedArtworkPath = null
        cachedArtworkMtime = 0L
        // A dismissed widget must re-render in full when it comes back.
        renderedContentVersion = -1L
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "com.pulsr.music.widget.PLAY_PAUSE"
        const val ACTION_NEXT = "com.pulsr.music.widget.NEXT"
        const val ACTION_PREV = "com.pulsr.music.widget.PREV"
        const val ACTION_REWIND = "com.pulsr.music.widget.REWIND"
        const val ACTION_FORWARD = "com.pulsr.music.widget.FORWARD"
        const val ACTION_SEEK_RATIO = "com.pulsr.music.widget.SEEK_RATIO"
        const val ACTION_FAVORITE = "com.pulsr.music.widget.FAVORITE"
        const val ACTION_SHUFFLE = "com.pulsr.music.widget.SHUFFLE"
        const val ACTION_REPEAT = "com.pulsr.music.widget.REPEAT"
        const val EXTRA_RATIO = "extra_ratio"
        private const val EXTRA_WIDGET_TOKEN = "com.pulsr.music.widget.extra.TOKEN"
        private const val WIDGET_ACTION_PREFIX = "com.pulsr.music.widget."
        private const val WIDGET_CONTROL_PERMISSION = "com.pulsr.music.permission.WIDGET_CONTROL"

        private val secureRandom by lazy { java.security.SecureRandom() }
        private val widgetTokenLock = Any()

        private fun generateToken(): String {
            val bytes = ByteArray(32)
            secureRandom.nextBytes(bytes)
            return android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        }

        private fun getWidgetToken(context: Context): String = synchronized(widgetTokenLock) {
            val prefs = context.getSharedPreferences("widget_tokens", Context.MODE_PRIVATE)
            prefs.getString("token_active", null) ?: run {
                val newToken = generateToken()
                prefs.edit().putString("token_active", newToken).commit()
                newToken
            }
        }

        /// C-10: the complete set of broadcasts this receiver will act on.
        private val WIDGET_ACTIONS = setOf(
            ACTION_PLAY_PAUSE,
            ACTION_NEXT,
            ACTION_PREV,
            ACTION_REWIND,
            ACTION_FORWARD,
            ACTION_SEEK_RATIO,
            ACTION_FAVORITE,
            ACTION_SHUFFLE,
            ACTION_REPEAT,
        )

        private const val UNIFIED_ART_TARGET_PX = 192

        private var cachedMediaBrowser: MediaBrowserCompat? = null
        private var cachedMediaController: MediaControllerCompat? = null
        private var cachedArtworkPath: String? = null
        private var cachedArtworkMtime: Long = 0L
        private var cachedArtworkBitmap: Bitmap? = null

        /// Content version rendered by the last *full* repaint. Compared against
        /// the `contentVersion` the Dart side persists to recognise a progress-only
        /// tick (C-4).
        @Volatile
        private var renderedContentVersion: Long = -1L

        private fun sendExplicitMediaButton(context: Context, keyCode: Int) {
            try {
                val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                val eventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)

                val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    setComponent(ComponentName(context, "androidx.media.session.MediaButtonReceiver"))
                    putExtra(Intent.EXTRA_KEY_EVENT, eventDown)
                }
                context.sendBroadcast(mediaButtonIntent)

                val mediaButtonIntentUp = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                    setComponent(ComponentName(context, "androidx.media.session.MediaButtonReceiver"))
                    putExtra(Intent.EXTRA_KEY_EVENT, eventUp)
                }
                context.sendBroadcast(mediaButtonIntentUp)
            } catch (_: Throwable) {}
        }

        private val mediaBrowserLock = Any()

        private val updateHandler = Handler(Looper.getMainLooper())
        private var pendingUpdateRunnable: Runnable? = null

        fun scheduleDebouncedWidgetUpdate(context: Context, delayMs: Long = 150L, isProgressOnly: Boolean = false) {
            val appContext = context.applicationContext ?: context
            pendingUpdateRunnable?.let { updateHandler.removeCallbacks(it) }
            val runnable = Runnable {
                try {
                    val appWidgetManager = AppWidgetManager.getInstance(appContext)
                    val componentName = ComponentName(appContext, NowPlayingWidget::class.java)
                    val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
                    if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                        for (id in appWidgetIds) {
                            updateAppWidget(appContext, appWidgetManager, id, isProgressOnly)
                        }
                    }
                } catch (_: Throwable) {}
            }
            pendingUpdateRunnable = runnable
            updateHandler.postDelayed(runnable, delayMs)
        }

        /// C-4: true when the only thing that changed since the last full repaint
        /// is progress/position — i.e. the persisted content version still matches
        /// what was last rendered — and the artwork bitmap is still usable.
        private fun shouldRenderProgressOnly(data: SharedPreferences): Boolean {
            val cached = cachedArtworkBitmap
            if (cached == null || cached.isRecycled) return false
            val version = getSafeLong(data, "contentVersion", -1L)
            return version >= 0L && version == renderedContentVersion
        }

        /// C-3: whether the live session is in a state where "play/pause" should
        /// mean pause. Derived from the MediaController, never from widget prefs.
        private fun liveIsPlaying(controller: MediaControllerCompat): Boolean {
            return when (controller.playbackState?.state) {
                PlaybackStateCompat.STATE_PLAYING,
                PlaybackStateCompat.STATE_BUFFERING,
                PlaybackStateCompat.STATE_FAST_FORWARDING,
                PlaybackStateCompat.STATE_REWINDING -> true
                else -> false
            }
        }

        private fun performMediaAction(
            context: Context,
            fallbackKeyCode: Int? = null,
            timeoutMs: Long = 5000L,
            onDispatched: (() -> Unit)? = null,
            action: (MediaControllerCompat.TransportControls, Boolean, Long, Long) -> Unit
        ) {
            try {
                val data = HomeWidgetPlugin.getData(context)
                val duration = getSafeLong(data, "durationMs", 0L)
                val position = getSafeLong(data, "positionMs", 0L)

                synchronized(mediaBrowserLock) {
                    val controller = cachedMediaController
                    if (controller != null && cachedMediaBrowser?.isConnected == true) {
                        // Live state, so play/pause can never invert (C-3).
                        action(controller.transportControls, liveIsPlaying(controller), position, duration)
                        onDispatched?.invoke()
                        return
                    }
                }

                val appContext = context.applicationContext ?: context
                val mainHandler = Handler(Looper.getMainLooper())
                val actionExecuted = java.util.concurrent.atomic.AtomicBoolean(false)
                var timeoutRunnable: Runnable? = null
                var localBrowser: MediaBrowserCompat? = null

                val connectionCallback = object : MediaBrowserCompat.ConnectionCallback() {
                    override fun onConnected() {
                        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                        if (!actionExecuted.compareAndSet(false, true)) {
                            synchronized(mediaBrowserLock) {
                                try { localBrowser?.disconnect() } catch (_: Throwable) {}
                            }
                            return
                        }
                        try {
                            val latestData = HomeWidgetPlugin.getData(appContext)
                            synchronized(mediaBrowserLock) {
                                val token = localBrowser?.sessionToken
                                if (token != null) {
                                    val newController = MediaControllerCompat(appContext, token)
                                    cachedMediaController = newController
                                    cachedMediaBrowser = localBrowser
                                    action(
                                        newController.transportControls,
                                        liveIsPlaying(newController),
                                        getSafeLong(latestData, "positionMs", 0L),
                                        getSafeLong(latestData, "durationMs", 0L)
                                    )
                                    onDispatched?.invoke()
                                } else {
                                    fallbackKeyCode?.let { sendExplicitMediaButton(appContext, it) }
                                    try { localBrowser?.disconnect() } catch (_: Throwable) {}
                                }
                            }
                        } catch (_: Throwable) {
                            fallbackKeyCode?.let { sendExplicitMediaButton(appContext, it) }
                            synchronized(mediaBrowserLock) {
                                try { localBrowser?.disconnect() } catch (_: Throwable) {}
                            }
                        }
                    }

                    override fun onConnectionFailed() {
                        timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                        if (!actionExecuted.compareAndSet(false, true)) return
                        synchronized(mediaBrowserLock) {
                            try { localBrowser?.disconnect() } catch (_: Throwable) {}
                        }
                        fallbackKeyCode?.let { sendExplicitMediaButton(appContext, it) }
                    }
                }

                synchronized(mediaBrowserLock) {
                    try { cachedMediaBrowser?.disconnect() } catch (_: Throwable) {}
                    cachedMediaBrowser = null
                    cachedMediaController = null

                    localBrowser = MediaBrowserCompat(
                        appContext,
                        ComponentName(appContext, "com.ryanheise.audioservice.AudioService"),
                        connectionCallback,
                        null
                    )
                    localBrowser.connect()
                }

                timeoutRunnable = Runnable {
                    if (!actionExecuted.compareAndSet(false, true)) return@Runnable
                    synchronized(mediaBrowserLock) {
                        try { localBrowser?.disconnect() } catch (_: Throwable) {}
                        if (cachedMediaBrowser == localBrowser) {
                            cachedMediaBrowser = null
                            cachedMediaController = null
                        }
                    }
                    fallbackKeyCode?.let { sendExplicitMediaButton(appContext, it) }
                }
                mainHandler.postDelayed(timeoutRunnable, timeoutMs)
            } catch (_: Throwable) {
                fallbackKeyCode?.let { sendExplicitMediaButton(context, it) }
            }
        }

        private fun getSafeLong(prefs: SharedPreferences, key: String, default: Long = 0L): Long {
            val v = prefs.all[key] ?: return default
            return when (v) {
                is Number -> v.toLong()
                is String -> v.toLongOrNull() ?: default
                else -> default
            }
        }

        private fun getSafeBoolean(prefs: SharedPreferences, key: String, default: Boolean = false): Boolean {
            val v = prefs.all[key] ?: return default
            return when (v) {
                is Boolean -> v
                is String -> v.toBoolean()
                is Number -> v.toInt() != 0
                else -> default
            }
        }

        private fun getSafeString(prefs: SharedPreferences, key: String, default: String? = null): String? {
            val v = prefs.all[key] ?: return default
            val s = v.toString()
            return if (s.isEmpty()) default else s
        }

        /// C-11: same shape as the app's shared Dart formatter (`Formatters`
        /// .formatDuration): `m:ss` below an hour, `h:mm:ss` with zero-padded
        /// minutes/seconds above it. The old copy rendered 75:30 for long tracks.
        fun formatMs(ms: Long): String {
            if (ms <= 0) return "0:00"
            val totalSeconds = ms / 1000
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            return if (hours > 0) {
                "$hours:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
            } else {
                "$minutes:${seconds.toString().padStart(2, '0')}"
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            isProgressOnly: Boolean = false
        ) {
            try {
                val data = HomeWidgetPlugin.getData(context)
                // The caller's decision is honoured only when the cached bitmap it
                // relies on is actually usable; otherwise fall back to a full render.
                val cached = cachedArtworkBitmap
                val progressOnly = isProgressOnly && cached != null && !cached.isRecycled

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val viewsCompact = createPopulatedRemoteViews(context, R.layout.widget_now_playing_compact, data, 44, progressOnly)
                    val viewsSmall = createPopulatedRemoteViews(context, R.layout.widget_now_playing, data, 56, progressOnly)
                    val viewsMedium = createPopulatedRemoteViews(context, R.layout.widget_now_playing_medium, data, 68, progressOnly)
                    val viewsLarge = createPopulatedRemoteViews(context, R.layout.widget_now_playing_large, data, 88, progressOnly)
                    val viewMapping = mapOf(
                        SizeF(140f, 60f) to viewsCompact,
                        SizeF(250f, 110f) to viewsSmall,
                        SizeF(250f, 170f) to viewsMedium,
                        SizeF(250f, 250f) to viewsLarge
                    )
                    val remoteViews = RemoteViews(viewMapping)
                    appWidgetManager.updateAppWidget(appWidgetId, remoteViews)
                } else {
                    val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                    val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
                    val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
                    val (layoutId, artDp) = when {
                        minHeight >= 250 -> Pair(R.layout.widget_now_playing_large, 88)
                        minHeight >= 170 -> Pair(R.layout.widget_now_playing_medium, 68)
                        minHeight >= 110 && minWidth >= 250 -> Pair(R.layout.widget_now_playing, 56)
                        else -> Pair(R.layout.widget_now_playing_compact, 44)
                    }
                    val views = createPopulatedRemoteViews(context, layoutId, data, artDp, progressOnly)
                    appWidgetManager.updateAppWidget(appWidgetId, views)
                }

                if (!progressOnly) {
                    renderedContentVersion = getSafeLong(data, "contentVersion", -1L)
                }
            } catch (e: Throwable) {
                android.util.Log.e("NowPlayingWidget", "Widget update failed, recovering with fallback views", e)
                // W3: Self-healing fallback on IllegalStateException / Oplus widget crash
                try {
                    cachedArtworkBitmap = null
                    cachedArtworkPath = null
                    cachedArtworkMtime = 0L
                    renderedContentVersion = -1L

                    val fallbackViews = RemoteViews(context.packageName, R.layout.widget_now_playing).apply {
                        val data = HomeWidgetPlugin.getData(context)
                        val title = getSafeString(data, "title")
                        val artist = getSafeString(data, "artist")
                        setTextViewText(
                            R.id.widget_title,
                            if (title.isNullOrBlank()) context.getString(R.string.app_name) else title
                        )
                        setTextViewText(
                            R.id.widget_artist,
                            if (artist.isNullOrBlank()) context.getString(R.string.widget_nothing_playing) else artist
                        )
                        setImageViewResource(R.id.widget_artwork, R.mipmap.launcher_icon)
                    }
                    appWidgetManager.updateAppWidget(appWidgetId, fallbackViews)
                } catch (_: Throwable) {}
            }
        }

        private fun createPopulatedRemoteViews(
            context: Context,
            layoutId: Int,
            data: SharedPreferences,
            targetArtDp: Int,
            isProgressOnly: Boolean = false
        ): RemoteViews {
            val views = RemoteViews(context.packageName, layoutId)

            // ---- Progress & Transport (always updated) ----
            val duration = getSafeLong(data, "durationMs", 0L)
            val position = getSafeLong(data, "positionMs", 0L).coerceAtLeast(0L)
            if (duration > 0) {
                views.setViewVisibility(R.id.widget_progress_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_times_row, View.VISIBLE)
                val max = 1000
                val prog = ((position.toDouble() / duration.toDouble()) * max).toInt().coerceIn(0, max)
                views.setProgressBar(R.id.widget_progress, max, prog, false)
                views.setTextViewText(R.id.widget_elapsed, formatMs(position))
                views.setTextViewText(R.id.widget_duration, formatMs(duration))
            } else {
                views.setViewVisibility(R.id.widget_progress_container, View.GONE)
                views.setViewVisibility(R.id.widget_times_row, View.GONE)
            }

            val isPlaying = getSafeBoolean(data, "isPlaying", false)
            views.setImageViewResource(
                R.id.btn_play_pause,
                if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
            )
            views.setContentDescription(
                R.id.btn_play_pause,
                context.getString(if (isPlaying) R.string.widget_pause else R.string.widget_play)
            )

            // C-4 progress-only tick: re-attach the cached artwork (so the launcher
            // keeps showing it) and touch nothing else — no bitmap decode, no text,
            // no fresh PendingIntents.
            if (isProgressOnly) {
                val cachedBmp = cachedArtworkBitmap
                if (cachedBmp != null && !cachedBmp.isRecycled) {
                    views.setImageViewBitmap(R.id.widget_artwork, cachedBmp)
                }
                return views
            }

            // ---- Text (Title & Artist) ----
            val title = getSafeString(data, "title")
            val artist = getSafeString(data, "artist")
            views.setTextViewText(
                R.id.widget_title,
                if (title.isNullOrBlank()) context.getString(R.string.app_name) else title
            )
            views.setTextViewText(
                R.id.widget_artist,
                if (artist.isNullOrBlank()) context.getString(R.string.widget_nothing_playing) else artist
            )

            // ---- Album (for Medium & Large Layouts) ----
            val album = getSafeString(data, "album")
            if (layoutId == R.layout.widget_now_playing_medium || layoutId == R.layout.widget_now_playing_large) {
                if (!album.isNullOrBlank() && album != "Unknown Album") {
                    views.setTextViewText(R.id.widget_album, album)
                    views.setViewVisibility(R.id.widget_album, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_album, View.GONE)
                }
            }

            // ---- Up Next Queue Preview (for Large Layout) ----
            if (layoutId == R.layout.widget_now_playing_large) {
                val nextTrack0 = getSafeString(data, "nextTrack0")
                val nextTrack1 = getSafeString(data, "nextTrack1")
                val nextTrack2 = getSafeString(data, "nextTrack2")

                if (!nextTrack0.isNullOrBlank()) {
                    views.setTextViewText(R.id.widget_next_track_0, "1. $nextTrack0")
                    views.setViewVisibility(R.id.widget_next_track_0, View.VISIBLE)
                } else {
                    views.setTextViewText(
                        R.id.widget_next_track_0,
                        context.getString(R.string.widget_no_upcoming_tracks)
                    )
                    views.setViewVisibility(R.id.widget_next_track_0, View.VISIBLE)
                }

                if (!nextTrack1.isNullOrBlank()) {
                    views.setTextViewText(R.id.widget_next_track_1, "2. $nextTrack1")
                    views.setViewVisibility(R.id.widget_next_track_1, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_next_track_1, View.GONE)
                }

                if (!nextTrack2.isNullOrBlank()) {
                    views.setTextViewText(R.id.widget_next_track_2, "3. $nextTrack2")
                    views.setViewVisibility(R.id.widget_next_track_2, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_next_track_2, View.GONE)
                }

                views.setViewVisibility(R.id.widget_queue_container, View.VISIBLE)
            }

            // ---- Favorite ----
            val isFavorite = getSafeBoolean(data, "isFavorite", false)
            views.setImageViewResource(
                R.id.widget_favorite,
                if (isFavorite) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
            )
            views.setContentDescription(
                R.id.widget_favorite,
                context.getString(if (isFavorite) R.string.widget_favorite_remove else R.string.widget_favorite_add)
            )

            // ---- Shuffle / Repeat indicators ----
            val isShuffle = getSafeBoolean(data, "isShuffle", false)
            views.setContentDescription(
                R.id.widget_shuffle,
                context.getString(if (isShuffle) R.string.widget_shuffle_disable else R.string.widget_shuffle_enable)
            )
            if (layoutId == R.layout.widget_now_playing) {
                views.setViewVisibility(R.id.widget_shuffle, if (isShuffle) View.VISIBLE else View.GONE)
                views.setImageViewResource(R.id.widget_shuffle, R.drawable.ic_widget_shuffle)
            } else if (layoutId != R.layout.widget_now_playing_compact) {
                views.setViewVisibility(R.id.widget_shuffle, View.VISIBLE)
                views.setImageViewResource(
                    R.id.widget_shuffle,
                    if (isShuffle) R.drawable.ic_widget_shuffle else R.drawable.ic_widget_shuffle_off
                )
            }

            val repeatMode = getSafeString(data, "repeatMode", "off") ?: "off"
            val repeatDesc = when (repeatMode) {
                "one" -> context.getString(R.string.widget_repeat_one)
                "all" -> context.getString(R.string.widget_repeat_all)
                else -> context.getString(R.string.widget_repeat_off)
            }
            views.setContentDescription(R.id.widget_repeat, repeatDesc)
            if (layoutId == R.layout.widget_now_playing) {
                views.setViewVisibility(R.id.widget_repeat, if (repeatMode != "off") View.VISIBLE else View.GONE)
                views.setImageViewResource(
                    R.id.widget_repeat,
                    if (repeatMode == "one") R.drawable.ic_widget_repeat_one else R.drawable.ic_widget_repeat
                )
            } else if (layoutId != R.layout.widget_now_playing_compact) {
                views.setViewVisibility(R.id.widget_repeat, View.VISIBLE)
                views.setImageViewResource(
                    R.id.widget_repeat,
                    when (repeatMode) {
                        "one" -> R.drawable.ic_widget_repeat_one
                        "all" -> R.drawable.ic_widget_repeat
                        else -> R.drawable.ic_widget_repeat_off
                    }
                )
            }

            // ---- Artwork ----
            val artworkPath = getSafeString(data, "artwork")
            val bmp = if (!artworkPath.isNullOrEmpty()) getOrDecodeArtworkBitmap(context, artworkPath) else null
            if (bmp != null && !bmp.isRecycled) {
                views.setImageViewBitmap(R.id.widget_artwork, bmp)
            } else {
                views.setImageViewResource(R.id.widget_artwork, R.mipmap.launcher_icon)
            }

            // ---- App Opening Intents (Artwork, Title area & Queue Area) ----
            val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("pulsrWidget://open")
            )
            views.setOnClickPendingIntent(R.id.widget_artwork, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_info_area, openAppIntent)
            if (layoutId == R.layout.widget_now_playing_large) {
                views.setOnClickPendingIntent(R.id.widget_queue_container, openAppIntent)
            }

            // ---- Background Actions (Exclusively targeted to Pulsr) ----
            views.setOnClickPendingIntent(
                R.id.btn_play_pause,
                createBroadcastPendingIntent(context, ACTION_PLAY_PAUSE, 101)
            )
            views.setOnClickPendingIntent(
                R.id.btn_prev,
                createBroadcastPendingIntent(context, ACTION_PREV, 102)
            )
            views.setOnClickPendingIntent(
                R.id.btn_next,
                createBroadcastPendingIntent(context, ACTION_NEXT, 103)
            )
            views.setOnClickPendingIntent(
                R.id.btn_rewind,
                createBroadcastPendingIntent(context, ACTION_REWIND, 104)
            )
            views.setOnClickPendingIntent(
                R.id.btn_forward,
                createBroadcastPendingIntent(context, ACTION_FORWARD, 105)
            )
            views.setOnClickPendingIntent(
                R.id.widget_favorite,
                createBroadcastPendingIntent(context, ACTION_FAVORITE, 106)
            )
            views.setOnClickPendingIntent(
                R.id.widget_shuffle,
                createBroadcastPendingIntent(context, ACTION_SHUFFLE, 107)
            )
            views.setOnClickPendingIntent(
                R.id.widget_repeat,
                createBroadcastPendingIntent(context, ACTION_REPEAT, 108)
            )

            // ---- 10 Granular Slider Seek Tap Zones (10% steps) ----
            if (layoutId != R.layout.widget_now_playing_compact) {
                val seekViews = intArrayOf(
                    R.id.btn_seek_01, R.id.btn_seek_02, R.id.btn_seek_03, R.id.btn_seek_04, R.id.btn_seek_05,
                    R.id.btn_seek_06, R.id.btn_seek_07, R.id.btn_seek_08, R.id.btn_seek_09, R.id.btn_seek_10
                )
                for (i in seekViews.indices) {
                    val percent = (i + 1) * 10
                    views.setContentDescription(
                        seekViews[i],
                        context.getString(R.string.widget_seek_to, percent)
                    )
                    val ratio = ((i + 1).toFloat() / seekViews.size.toFloat()).coerceIn(0.01f, 0.99f)
                    views.setOnClickPendingIntent(
                        seekViews[i],
                        createSeekPendingIntent(context, ratio, 300 + i)
                    )
                }
            }

            return views
        }

        private fun createBroadcastPendingIntent(context: Context, actionName: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, NowPlayingWidget::class.java).apply {
                action = actionName
                putExtra(EXTRA_WIDGET_TOKEN, getWidgetToken(context))
                `package` = context.packageName
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }

        private fun createSeekPendingIntent(context: Context, ratio: Float, requestCode: Int): PendingIntent {
            val intent = Intent(context, NowPlayingWidget::class.java).apply {
                action = ACTION_SEEK_RATIO
                putExtra(EXTRA_RATIO, ratio)
                putExtra(EXTRA_WIDGET_TOKEN, getWidgetToken(context))
                `package` = context.packageName
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }

        @Synchronized
        private fun getOrDecodeArtworkBitmap(context: Context, artworkPath: String): Bitmap? {
            try {
                val file = File(artworkPath)
                if (!file.exists() || file.length() <= 0L || file.length() > 15 * 1024 * 1024) {
                    return null
                }
                val mtime = file.lastModified()
                val cached = cachedArtworkBitmap
                if (cachedArtworkPath == artworkPath && cachedArtworkMtime == mtime && cached != null && !cached.isRecycled) {
                    return cached
                }

                val targetPx = UNIFIED_ART_TARGET_PX
                val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(artworkPath, boundsOptions)
                if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

                var sampleSize = 1
                while ((boundsOptions.outWidth / sampleSize) > targetPx * 2 ||
                       (boundsOptions.outHeight / sampleSize) > targetPx * 2) {
                    sampleSize *= 2
                }

                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                val rawBitmap = BitmapFactory.decodeFile(artworkPath, decodeOptions) ?: return null
                val scaled = if (rawBitmap.width != targetPx || rawBitmap.height != targetPx) {
                    val sb = Bitmap.createScaledBitmap(rawBitmap, targetPx, targetPx, true)
                    if (sb !== rawBitmap) rawBitmap.recycle()
                    sb
                } else {
                    rawBitmap
                }

                val density = context.resources.displayMetrics.density
                val cornerRadiusPx = 16f * density
                val rounded = getRoundedCornerBitmap(scaled, cornerRadiusPx)
                if (rounded !== scaled) scaled.recycle()

                cachedArtworkBitmap = rounded
                cachedArtworkPath = artworkPath
                cachedArtworkMtime = mtime
                return rounded
            } catch (e: Throwable) {
                android.util.Log.e("NowPlayingWidget", "Error decoding artwork bitmap", e)
                return null
            }
        }

        private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusPx: Float): Bitmap {
            return try {
                if (bitmap.isRecycled) return bitmap
                val output = Bitmap.createBitmap(bitmap.width, bitmap.height, bitmap.config ?: Bitmap.Config.ARGB_8888)
                val canvas = Canvas(output)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                val rect = Rect(0, 0, bitmap.width, bitmap.height)
                val rectF = RectF(rect)
                canvas.drawRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, paint)
                paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                canvas.drawBitmap(bitmap, rect, rect, paint)
                output
            } catch (_: Throwable) {
                bitmap
            }
        }
    }
}
