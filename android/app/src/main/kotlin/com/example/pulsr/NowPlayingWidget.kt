package com.example.pulsr

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class NowPlayingWidget : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != null && action.startsWith("com.example.pulsr.widget.")) {
            handleWidgetAction(context, intent)
            return
        }

        super.onReceive(context, intent)
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, NowPlayingWidget::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                for (appWidgetId in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, appWidgetId)
                }
            }
        } catch (_: Throwable) {
            // Ignore
        }
    }

    private fun handleWidgetAction(context: Context, intent: Intent) {
        val prefs = HomeWidgetPlugin.getData(context)
        val currentDuration = getSafeLong(prefs, "durationMs", 0L)
        val currentPosition = getSafeLong(prefs, "positionMs", 0L)
        val currentIsPlaying = getSafeBoolean(prefs, "isPlaying", false)

        when (intent.action) {
            ACTION_PLAY_PAUSE -> {
                val newPlaying = !currentIsPlaying
                prefs.edit().putBoolean("isPlaying", newPlaying).apply()
                sendExplicitMediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                performMediaAction(context) { controls, isPlaying, _, _ ->
                    if (isPlaying) controls.pause() else controls.play()
                }
            }
            ACTION_NEXT -> {
                sendExplicitMediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT)
                performMediaAction(context) { controls, _, _, _ ->
                    controls.skipToNext()
                }
            }
            ACTION_PREV -> {
                sendExplicitMediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                performMediaAction(context) { controls, _, _, _ ->
                    controls.skipToPrevious()
                }
            }
            ACTION_REWIND -> {
                val newPos = (currentPosition - 10000L).coerceAtLeast(0L)
                prefs.edit().putLong("positionMs", newPos).apply()
                performMediaAction(context) { controls, _, _, _ ->
                    controls.seekTo(newPos)
                }
            }
            ACTION_FORWARD -> {
                val maxDur = if (currentDuration > 0) currentDuration else currentPosition + 10000L
                val newPos = (currentPosition + 10000L).coerceAtMost(maxDur)
                prefs.edit().putLong("positionMs", newPos).apply()
                performMediaAction(context) { controls, _, _, _ ->
                    controls.seekTo(newPos)
                }
            }
            ACTION_SEEK_RATIO -> {
                val ratio = intent.getFloatExtra(EXTRA_RATIO, 0.5f)
                if (currentDuration > 0) {
                    val seekPos = (currentDuration * ratio).toLong().coerceIn(0L, currentDuration)
                    prefs.edit().putLong("positionMs", seekPos).apply()
                    performMediaAction(context) { controls, _, _, _ ->
                        controls.seekTo(seekPos)
                    }
                }
            }
            ACTION_FAVORITE -> {
                val isFav = getSafeBoolean(prefs, "isFavorite", false)
                prefs.edit().putBoolean("isFavorite", !isFav).apply()
                performMediaAction(context) { controls, _, _, _ ->
                    controls.sendCustomAction("toggleFavorite", null)
                }
            }
        }

        // Immediately re-render all widget instances with optimistic state
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, NowPlayingWidget::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                for (id in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, id)
                }
            }
        } catch (_: Throwable) {}
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            } catch (_: Throwable) {
                // Ignore
            }
        }
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "com.example.pulsr.widget.PLAY_PAUSE"
        const val ACTION_NEXT = "com.example.pulsr.widget.NEXT"
        const val ACTION_PREV = "com.example.pulsr.widget.PREV"
        const val ACTION_REWIND = "com.example.pulsr.widget.REWIND"
        const val ACTION_FORWARD = "com.example.pulsr.widget.FORWARD"
        const val ACTION_SEEK_RATIO = "com.example.pulsr.widget.SEEK_RATIO"
        const val ACTION_FAVORITE = "com.example.pulsr.widget.FAVORITE"
        const val EXTRA_RATIO = "extra_ratio"

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

        private fun performMediaAction(
            context: Context,
            action: (MediaControllerCompat.TransportControls, Boolean, Long, Long) -> Unit
        ) {
            try {
                val data = HomeWidgetPlugin.getData(context)
                val duration = getSafeLong(data, "durationMs", 0L)
                val position = getSafeLong(data, "positionMs", 0L)
                val isPlaying = getSafeBoolean(data, "isPlaying", false)

                val component = ComponentName(context, "com.ryanheise.audioservice.AudioService")
                val appContext = context.applicationContext ?: context
                val handler = Handler(Looper.getMainLooper())

                var browser: MediaBrowserCompat? = null
                val connectionCallback = object : MediaBrowserCompat.ConnectionCallback() {
                    override fun onConnected() {
                        try {
                            val token = browser?.sessionToken
                            if (token != null) {
                                val controller = MediaControllerCompat(appContext, token)
                                action(controller.transportControls, isPlaying, position, duration)
                            }
                        } catch (_: Throwable) {
                        } finally {
                            handler.postDelayed({
                                try { browser?.disconnect() } catch (_: Throwable) {}
                            }, 500)
                        }
                    }

                    override fun onConnectionFailed() {
                        try { browser?.disconnect() } catch (_: Throwable) {}
                    }
                }
                browser = MediaBrowserCompat(appContext, component, connectionCallback, null)
                browser.connect()
            } catch (_: Throwable) {}
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

        fun formatMs(ms: Long): String {
            if (ms <= 0) return "0:00"
            val totalSeconds = ms / 1000
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            return "$minutes:${seconds.toString().padStart(2, '0')}"
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                val data = HomeWidgetPlugin.getData(context)
                val views = RemoteViews(context.packageName, R.layout.widget_now_playing)

                // ---- Text ----
                val title = getSafeString(data, "title")
                val artist = getSafeString(data, "artist")
                views.setTextViewText(R.id.widget_title, if (title.isNullOrBlank()) "Pulsr Music" else title)
                views.setTextViewText(R.id.widget_artist, if (artist.isNullOrBlank()) "Nothing playing" else artist)

                // ---- Progress ----
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

                // ---- Favorite ----
                val isFavorite = getSafeBoolean(data, "isFavorite", false)
                views.setImageViewResource(
                    R.id.widget_favorite,
                    if (isFavorite) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
                )

                // ---- Shuffle / Repeat indicators ----
                val isShuffle = getSafeBoolean(data, "isShuffle", false)
                views.setViewVisibility(R.id.widget_shuffle, if (isShuffle) View.VISIBLE else View.GONE)

                val repeatMode = getSafeString(data, "repeatMode", "off") ?: "off"
                views.setViewVisibility(R.id.widget_repeat, if (repeatMode != "off") View.VISIBLE else View.GONE)
                views.setImageViewResource(
                    R.id.widget_repeat,
                    if (repeatMode == "one") R.drawable.ic_widget_repeat_one else R.drawable.ic_widget_repeat
                )

                // ---- Play / Pause ----
                val isPlaying = getSafeBoolean(data, "isPlaying", false)
                views.setImageViewResource(
                    R.id.btn_play_pause,
                    if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
                )

                // ---- Artwork ----
                val artworkPath = getSafeString(data, "artwork")
                var bitmapSet = false
                if (!artworkPath.isNullOrEmpty()) {
                    try {
                        val file = File(artworkPath)
                        if (file.exists() && file.length() > 0) {
                            val bitmap = BitmapFactory.decodeFile(artworkPath)
                            if (bitmap != null) {
                                views.setImageViewBitmap(R.id.widget_artwork, bitmap)
                                bitmapSet = true
                            }
                        }
                    } catch (e: Throwable) {
                        bitmapSet = false
                    }
                }
                if (!bitmapSet) {
                    views.setImageViewResource(R.id.widget_artwork, R.mipmap.launcher_icon)
                }

                // ---- App Opening Intents (Artwork & Title area ONLY) ----
                val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("pulsrWidget://open")
                )
                views.setOnClickPendingIntent(R.id.widget_artwork, openAppIntent)
                views.setOnClickPendingIntent(R.id.widget_info_area, openAppIntent)

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

                // ---- 20 Granular Slider Seek Tap Zones (5% steps) ----
                val seekViews = intArrayOf(
                    R.id.btn_seek_01, R.id.btn_seek_02, R.id.btn_seek_03, R.id.btn_seek_04, R.id.btn_seek_05,
                    R.id.btn_seek_06, R.id.btn_seek_07, R.id.btn_seek_08, R.id.btn_seek_09, R.id.btn_seek_10,
                    R.id.btn_seek_11, R.id.btn_seek_12, R.id.btn_seek_13, R.id.btn_seek_14, R.id.btn_seek_15,
                    R.id.btn_seek_16, R.id.btn_seek_17, R.id.btn_seek_18, R.id.btn_seek_19, R.id.btn_seek_20
                )
                for (i in seekViews.indices) {
                    val ratio = ((i + 1) * 0.05f).coerceIn(0.02f, 0.99f)
                    views.setOnClickPendingIntent(
                        seekViews[i],
                        createSeekPendingIntent(context, ratio, 300 + i)
                    )
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (_: Throwable) {
                // Ignore
            }
        }

        private fun createBroadcastPendingIntent(context: Context, actionName: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, NowPlayingWidget::class.java).apply {
                action = actionName
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
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }
    }
}
