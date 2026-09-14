package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Google Cast session support (dev/ytm flavors).
 *
 * Uses the Cast framework with Google's public Default Media Receiver. Local
 * files are bridged through [CastMediaServer] so a receiver can fetch them over
 * HTTP; remote URLs are cast directly.
 *
 * Device discovery here uses the Cast/MediaRouter route table (the SDK's own
 * discovery). The mDNS [CastDiscoveryPlugin] remains as a fallback when the SDK
 * is unavailable (prod flavor).
 */
class CastSessionPlugin(
    private val context: Context,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "CastSessionPlugin"
        const val METHOD_CHANNEL = "com.pulsr.music/cast_session"
        const val EVENT_CHANNEL = "com.pulsr.music/cast_session_events"

        fun registerWith(
            flutterEngine: io.flutter.embedding.engine.FlutterEngine,
            context: Context? = null,
        ): CastSessionPlugin {
            val ctx = requireNotNull(context) {
                "CastSessionPlugin requires an application context"
            }
            return CastSessionPlugin(ctx, flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    private var eventSink: EventChannel.EventSink? = null

    private var castContext: CastContext? = null
    private var mediaRouter: MediaRouter? = null
    private var routeSelector: MediaRouteSelector? = null
    private var discovering = false
    private var selectedRouteId: String? = null

    private val mediaServer = CastMediaServer()

    private var lastError: String? = null

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) = emitSession(session)
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = emitSession(session)
        override fun onSessionEnded(session: CastSession, error: Int) {
            selectedRouteId = null
            emitSession(null)
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            lastError = "session_start_failed_$error"
            emitSession(null)
        }
        override fun onSessionStarting(session: CastSession) = emitSession(session)
        override fun onSessionEnding(session: CastSession) = emitSession(session)
        override fun onSessionResumeFailed(session: CastSession, error: Int) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }

    private val mediaClientListener = object : RemoteMediaClient.Listener {
        override fun onStatusUpdated() = emitSession(currentSession())
        override fun onMetadataUpdated() = emitSession(currentSession())
        override fun onQueueStatusUpdated() {}
        override fun onPreloadStatusUpdated() {}
        override fun onSendingRemoteMediaRequest() {}
        override fun onAdBreakStatusUpdated() {}
    }

    private val routeCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
        override fun onRouteSelected(router: MediaRouter, route: MediaRouter.RouteInfo) {
            selectedRouteId = route.id
            emitRoutes()
        }
        override fun onRouteUnselected(
            router: MediaRouter,
            route: MediaRouter.RouteInfo,
            reason: Int,
        ) {
            if (route.id == selectedRouteId) selectedRouteId = null
            emitRoutes()
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        ensureCast { available ->
            if (available) {
                registerRouteCallback()
                emitRoutes()
                emitSession(currentSession())
            } else {
                emitError("cast_unavailable")
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopDiscovery()
    }

    fun dispose() {
        stopDiscovery()
        try {
            castContext?.sessionManager?.removeSessionManagerListener(
                sessionListener, CastSession::class.java,
            )
        } catch (_: Exception) {}
        mediaServer.stop()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    /** Uniform teardown hook matching the prod stub. */
    fun cleanup() = dispose()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isAvailable" -> ensureCast { result.success(it) }
                "startDiscovery" -> ensureCast { available ->
                    if (available) {
                        registerRouteCallback()
                        startDiscovery()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "stopDiscovery" -> {
                    stopDiscovery()
                    result.success(true)
                }
                "getRoutes" -> result.success(routeList())
                "connect" -> {
                    val routeId = call.argument<String>("routeId")
                    result.success(connect(routeId))
                }
                "disconnect" -> {
                    ensureCast {
                        try {
                            castContext?.sessionManager?.endCurrentSession(true)
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                }
                "castLocalFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime")
                    val url = if (path != null) mediaServer.serveFile(path, mime) else null
                    if (url == null) {
                        result.success(notConfigured("local media could not be served"))
                    } else {
                        loadOnSession(url, call, result)
                    }
                }
                "castUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.success(notConfigured("missing url"))
                    } else {
                        loadOnSession(url, call, result)
                    }
                }
                "setPlaybackState" -> {
                    val action = call.argument<String>("action")
                    val positionMs = call.argument<Number>("positionMs")?.toLong()
                    result.success(setPlaybackState(action, positionMs))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MethodChannel error handling ${call.method}: ${e.message}", e)
            result.error("CAST_SESSION_ERROR", e.message, null)
        }
    }

    // ---- CastContext / routes ----

    private fun ensureCast(cont: (Boolean) -> Unit) {
        val existing = castContext
        if (existing != null) {
            cont(true)
            return
        }
        try {
            // Synchronous in the current Cast framework; throws when the options
            // provider is missing or Play Services is unavailable.
            val ctx = CastContext.getSharedInstance(appContext)
            castContext = ctx
            mediaRouter = MediaRouter.getInstance(appContext)
            routeSelector = ctx.mergedSelector
            ctx.sessionManager.addSessionManagerListener(
                sessionListener, CastSession::class.java,
            )
            cont(true)
        } catch (e: Exception) {
            lastError = e.message
            cont(false)
        }
    }

    private fun registerRouteCallback() {
        val router = mediaRouter ?: return
        val selector = routeSelector ?: return
        router.addCallback(
            selector,
            routeCallback,
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY,
        )
    }

    private fun startDiscovery() {
        discovering = true
        emitRoutes()
    }

    private fun stopDiscovery() {
        discovering = false
        val router = mediaRouter ?: return
        try { router.removeCallback(routeCallback) } catch (_: Exception) {}
    }

    private fun routeList(): List<Map<String, Any?>> {
        val router = mediaRouter ?: return emptyList()
        val selector = routeSelector ?: return emptyList()
        return try {
            router.routes
                .filter { it.matchesSelector(selector) && !it.isDefault }
                .map { route ->
                    mapOf(
                        "id" to route.id,
                        "name" to route.name,
                        "connected" to
                            (route.connectionState ==
                                MediaRouter.RouteInfo.CONNECTION_STATE_CONNECTED),
                        "selected" to (route.id == selectedRouteId),
                    )
                }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun connect(routeId: String?): Boolean {
        if (routeId == null) return false
        val router = mediaRouter ?: return false
        val selector = routeSelector ?: return false
        val route = try {
            router.routes.firstOrNull { it.id == routeId && it.matchesSelector(selector) }
        } catch (_: Exception) {
            null
        } ?: return false
        return try {
            router.selectRoute(route)
            selectedRouteId = route.id
            true
        } catch (e: Exception) {
            lastError = e.message
            false
        }
    }

    private fun currentSession(): CastSession? =
        try { castContext?.sessionManager?.currentCastSession } catch (_: Exception) { null }

    // ---- media load / control ----

    private fun loadOnSession(
        url: String,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        ensureCast { available ->
            if (!available) {
                result.success(notConfigured("Cast is unavailable on this build"))
                return@ensureCast
            }
            val session = currentSession()
            val client = session?.remoteMediaClient
            if (client == null) {
                result.success(notConfigured("no active Cast session"))
                return@ensureCast
            }
            val title = call.argument<String>("title") ?: ""
            val artist = call.argument<String>("artist") ?: ""
            val album = call.argument<String>("album") ?: ""
            val artwork = call.argument<String>("artwork")
            val mime = call.argument<String>("mime") ?: "audio/mpeg"
            val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
                putString(MediaMetadata.KEY_TITLE, title)
                putString(MediaMetadata.KEY_ARTIST, artist)
                putString(MediaMetadata.KEY_ALBUM_TITLE, album)
                if (!artwork.isNullOrBlank()) {
                    addImage(com.google.android.gms.common.images.WebImage(
                        android.net.Uri.parse(artwork)))
                }
            }
            val info = MediaInfo.Builder(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(mime)
                .setMetadata(metadata)
                .build()
            try {
                client.load(info, true)
                result.success(mapOf("success" to true))
            } catch (e: Exception) {
                lastError = e.message
                result.success(notConfigured("load failed: ${e.message}"))
            }
        }
    }

    private fun setPlaybackState(action: String?, positionMs: Long?): Map<String, Any?> {
        val client = currentSession()?.remoteMediaClient
            ?: return notConfigured("no active Cast session")
        return try {
            when (action) {
                "play" -> client.play()
                "pause" -> client.pause()
                "seek" -> {
                    val pos = positionMs ?: 0L
                    client.seek(MediaSeekOptions.Builder().setPosition(pos).build())
                }
                else -> return notConfigured("unknown action")
            }
            mapOf("success" to true)
        } catch (e: Exception) {
            lastError = e.message
            notConfigured("control failed: ${e.message}")
        }
    }

    // ---- events ----

    private fun emitRoutes() {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(
                    mapOf(
                        "type" to "routes",
                        "discovering" to discovering,
                        "routes" to routeList(),
                    )
                )
            } catch (_: Exception) {}
        }
    }

    private fun emitSession(session: CastSession?) {
        val sink = eventSink ?: return
        val client = session?.remoteMediaClient
        val playing = try { client?.isPlaying ?: false } catch (_: Exception) { false }
        val position = try { client?.approximateStreamPosition ?: 0L } catch (_: Exception) { 0L }
        mainHandler.post {
            try {
                sink.success(
                    mapOf(
                        "type" to "session",
                        "connected" to (session != null),
                        "deviceName" to session?.castDevice?.friendlyName,
                        "playing" to playing,
                        "positionMs" to position,
                        "error" to lastError,
                    )
                )
            } catch (_: Exception) {}
        }
    }

    private fun emitError(code: String) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(mapOf("type" to "error", "error" to code))
            } catch (_: Exception) {}
        }
    }

    private fun notConfigured(reason: String): Map<String, Any?> =
        mapOf("success" to false, "error" to reason)
}
