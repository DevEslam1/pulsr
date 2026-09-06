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

    private var isScrobblerChecked = false
    private var isScrobblerPresent = false

    private val knownScrobblerPackages = arrayOf(
        "com.adam.aslfms",
        "fm.last.android",
        "com.simplecity.amp_scrobbler",
        "net.jjc1138.android.scrobbler",
        "com.softartstudio.scrobble"
    )

    private fun isScrobblerAvailable(): Boolean {
        if (isScrobblerChecked) return isScrobblerPresent
        try {
            val intent = Intent("com.android.music.metachanged")
            val receivers = context.packageManager.queryBroadcastReceivers(intent, 0)
            if (receivers.isNotEmpty()) {
                isScrobblerPresent = true
            } else {
                for (pkg in knownScrobblerPackages) {
                    val pkgIntent = Intent("com.android.music.metachanged").setPackage(pkg)
                    if (context.packageManager.queryBroadcastReceivers(pkgIntent, 0).isNotEmpty()) {
                        isScrobblerPresent = true
                        break
                    }
                }
            }
        } catch (_: Throwable) {
            isScrobblerPresent = false
        }
        isScrobblerChecked = true
        return isScrobblerPresent
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
        if (!isScrobblerAvailable()) return
        try {
            val actions = arrayOf(
                "com.android.music.metachanged",
                "com.android.music.playstatechanged",
                "fm.last.android.metachanged",
                "com.adam.aslfms.notify.playstatechanged",
                "net.jjc1138.android.scrobbler.action.MUSIC_STATUS"
            )

            for (action in actions) {
                val baseIntent = Intent(action).apply {
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
                try { context.sendBroadcast(baseIntent) } catch (_: Throwable) {}

                // Send explicit broadcasts to known scrobbler packages on Android 8+
                for (pkg in knownScrobblerPackages) {
                    try {
                        val explicitIntent = Intent(baseIntent).setPackage(pkg)
                        context.sendBroadcast(explicitIntent)
                    } catch (_: Throwable) {}
                }
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
