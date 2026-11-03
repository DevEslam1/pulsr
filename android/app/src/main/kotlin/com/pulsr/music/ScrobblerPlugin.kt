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

    private var lastScrobblerCheckMs = 0L
    private var isScrobblerPresent = false
    private val scrobblerCheckTtlMs = 60_000L // Re-check every 60s if not present

    private var lastTrackKey: String? = null
    private var lastPlaying: Boolean? = null
    private var lastPosition: Long = -1L
    private var lastSentAtMs = 0L
    private val positionThrottleMs = 5_000L

    private val knownScrobblerPackages = arrayOf(
        "com.adam.aslfms",
        "fm.last.android",
        "com.simplecity.amp_scrobbler",
        "net.jjc1138.android.scrobbler",
        "com.softartstudio.scrobble"
    )

    private fun isScrobblerAvailable(): Boolean {
        val now = System.currentTimeMillis()
        if (isScrobblerPresent && (now - lastScrobblerCheckMs) < 10 * 60_000L) {
            return true
        }
        if (!isScrobblerPresent && (now - lastScrobblerCheckMs) < scrobblerCheckTtlMs) {
            return false
        }
        lastScrobblerCheckMs = now
        var found = false
        try {
            val pm = context.packageManager
            val intent = Intent("com.android.music.metachanged")
            val receivers = if (android.os.Build.VERSION.SDK_INT >= 33) {
                pm.queryBroadcastReceivers(intent, android.content.pm.PackageManager.ResolveInfoFlags.of(android.content.pm.PackageManager.MATCH_ALL.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.queryBroadcastReceivers(intent, android.content.pm.PackageManager.MATCH_ALL)
            }
            if (receivers.isNotEmpty()) {
                found = true
            } else {
                for (pkg in knownScrobblerPackages) {
                    val pkgIntent = Intent("com.android.music.metachanged").setPackage(pkg)
                    val pkgReceivers = if (android.os.Build.VERSION.SDK_INT >= 33) {
                        pm.queryBroadcastReceivers(pkgIntent, android.content.pm.PackageManager.ResolveInfoFlags.of(android.content.pm.PackageManager.MATCH_ALL.toLong()))
                    } else {
                        @Suppress("DEPRECATION")
                        pm.queryBroadcastReceivers(pkgIntent, android.content.pm.PackageManager.MATCH_ALL)
                    }
                    if (pkgReceivers.isNotEmpty()) {
                        found = true
                        break
                    }
                }
            }
        } catch (_: Throwable) {
            found = false
        }
        isScrobblerPresent = found
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
        // Track/state transitions are scrobbled immediately; position-only
        // updates are throttled to one per 5 s (players publish position at a
        // much higher rate, which woke every scrobbler receiver constantly).
        val key = "$id|$artist|$track|$album"
        val sameTrackAndState = key == lastTrackKey && isPlaying == lastPlaying
        val now = System.currentTimeMillis()
        if (sameTrackAndState) {
            if (position == lastPosition) return
            if (now - lastSentAtMs < positionThrottleMs) return
        }
        lastTrackKey = key
        lastPlaying = isPlaying
        lastPosition = position
        lastSentAtMs = now

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
                // Implicit broadcasts no longer reach manifest receivers on
                // Android 8+, and the system treats them as a blind fan-out.
                // Deliver only to receivers the package manager actually sees.
                for (pkg in resolveReceivers(action)) {
                    try {
                        context.sendBroadcast(Intent(baseIntent).setPackage(pkg))
                    } catch (_: Throwable) {
                    }
                }
            }
        } catch (_: Throwable) {
            // Ignore broadcast failures in restricted environments
        }
    }

    private fun resolveReceivers(action: String): Set<String> {
        val packages = LinkedHashSet<String>()
        val pm = context.packageManager
        try {
            val intent = Intent(action)
            val receivers = if (android.os.Build.VERSION.SDK_INT >= 33) {
                pm.queryBroadcastReceivers(
                    intent,
                    android.content.pm.PackageManager.ResolveInfoFlags.of(
                        android.content.pm.PackageManager.MATCH_ALL.toLong()
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryBroadcastReceivers(intent, android.content.pm.PackageManager.MATCH_ALL)
            }
            for (info in receivers) {
                val pkg = info.activityInfo?.packageName
                    ?: info.resolvePackageName
                    ?: info.serviceInfo?.packageName
                if (!pkg.isNullOrEmpty() && pkg != context.packageName) {
                    packages.add(pkg)
                }
            }
        } catch (_: Throwable) {
        }
        // Some scrobblers do not advertise their receiver in <queries>; add the
        // curated list when the package is actually installed.
        for (pkg in knownScrobblerPackages) {
            if (isPackageInstalled(pkg)) packages.add(pkg)
        }
        return packages
    }

    private fun isPackageInstalled(pkg: String): Boolean = try {
        context.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: Throwable) {
        false
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
