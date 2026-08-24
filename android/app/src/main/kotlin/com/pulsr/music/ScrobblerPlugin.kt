package com.pulsr.music

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ScrobblerPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    companion object {
        private const val CHANNEL_NAME = "com.pulsr.music/scrobbler"

        fun registerWith(flutterEngine: FlutterEngine, context: Context): ScrobblerPlugin {
            val plugin = ScrobblerPlugin(context)
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "broadcastPlaybackState") {
            val artist = call.argument<String>("artist") ?: ""
            val track = call.argument<String>("track") ?: ""
            val album = call.argument<String>("album") ?: ""
            val duration = (call.argument<Number>("duration"))?.toLong() ?: 0L
            val position = (call.argument<Number>("position"))?.toLong() ?: 0L
            val isPlaying = call.argument<Boolean>("isPlaying") ?: false
            val id = (call.argument<Number>("id"))?.toLong() ?: 0L

            sendScrobbleBroadcasts(id, artist, track, album, duration, position, isPlaying)
            result.success(true)
        } else {
            result.notImplemented()
        }
    }

    private fun sendScrobbleBroadcasts(
        id: Long,
        artist: String,
        track: String,
        album: String,
        duration: Long,
        position: Long,
        isPlaying: Boolean
    ) {
        try {
            val actions = arrayOf(
                "com.android.music.metachanged",
                "com.android.music.playstatechanged",
                "fm.last.android.metachanged",
                "com.adam.aslfms.notify.playstatechanged",
                "net.jjc1138.android.scrobbler.action.MUSIC_STATUS"
            )

            for (action in actions) {
                val intent = Intent(action).apply {
                    putExtra("id", id)
                    putExtra("artist", artist)
                    putExtra("track", track)
                    putExtra("album", album)
                    putExtra("duration", duration)
                    putExtra("position", position)
                    putExtra("playing", isPlaying)
                    putExtra("state", if (isPlaying) "playing" else "paused")
                    putExtra("package", context.packageName)
                    putExtra("app-name", "Pulsr")
                }
                context.sendBroadcast(intent)
            }
        } catch (_: Throwable) {
            // Ignore broadcast failures in restricted environments
        }
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
