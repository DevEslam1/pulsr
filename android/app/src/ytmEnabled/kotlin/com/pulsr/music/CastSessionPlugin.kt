package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
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
    private var observedMediaClient: RemoteMediaClient? = null

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            lastError = null
            attachMediaClient(session)
            emitSession(session)
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            lastError = null
            attachMediaClient(session)
            emitSession(session)
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            selectedRouteId = null
            detachMediaClient()
            mediaServer.stop()
            emitSession(null)
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            lastError = "session_start_failed_$error"
            detachMediaClient()
            emitSession(null)
        }
        override fun onSessionStarting(session: CastSession) = emitSession(session)
        override fun onSessionEnding(session: CastSession) = emitSession(session)
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            lastError = "session_resume_failed_$error"
            emitSession(null)
        }
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionSuspended(session: CastSession, reason: Int) = emitSession(session)
    }

    private val mediaClientCallback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = emitSession(currentSession())
        override fun onMetadataUpdated() = emitSession(currentSession())
        override fun onQueueStatusUpdated() = emitSession(currentSession())
        override fun onPreloadStatusUpdated() {}
        override fun onSendingRemoteMediaRequest() {}
        override fun onAdBreakStatusUpdated() {}
    }

    private fun attachMediaClient(session: CastSession?) {
        val client = session?.remoteMediaClient
        if (observedMediaClient === client) return
        detachMediaClient()
        if (client != null) {
            try {
                client.registerCallback(mediaClientCallback)
                observedMediaClient = client
            } catch (_: Exception) {}
        }
    }

    private fun detachMediaClient() {
        val prev = observedMediaClient ?: return
        observedMediaClient = null
        try {
            prev.unregisterCallback(mediaClientCallback)
        } catch (_: Exception) {}
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
        detachMediaClient()
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
                "getStatus" -> ensureCast { available ->
                    if (!available) {
                        result.success(mapOf("available" to false, "connected" to false))
                    } else {
                        val session = currentSession()
                        attachMediaClient(session)
                        result.success(buildSessionPayload(session))
                    }
                }
                "connect" -> {
                    val routeId = call.argument<String>("routeId")
                    result.success(connect(routeId))
                }
                "disconnect" -> {
                    ensureCast {
                        try {
                            castContext?.sessionManager?.endCurrentSession(true)
                        } catch (_: Exception) {}
                        selectedRouteId = null
                        detachMediaClient()
                        mediaServer.stop()
                        emitSession(null)
                        result.success(true)
                    }
                }
                "castLocalFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime")
                    val url = if (path != null) mediaServer.preBufferFile(path, mime) else null
                    if (url == null) {
                        result.success(notConfigured("local media could not be served"))
                    } else {
                        loadOnSession(url, call, result)
                    }
                }
                "preBufferFile" -> {
                    val path = call.argument<String>("path")
                    val mime = call.argument<String>("mime")
                    val url = if (path != null) mediaServer.preBufferFile(path, mime) else null
                    if (url == null) {
                        result.success(mapOf("success" to false))
                    } else {
                        result.success(mapOf("success" to true, "url" to url))
                    }
                }
                "castUrl" -> {
                    val rawUrl = call.argument<String>("url")?.trim()
                    val mime = call.argument<String>("mime")
                    if (rawUrl.isNullOrBlank()) {
                        result.success(notConfigured("missing url"))
                    } else {
                        val scheme = try { android.net.Uri.parse(rawUrl).scheme?.lowercase() } catch (_: Exception) { null }
                        if (scheme != "http" && scheme != "https") {
                            result.success(notConfigured("invalid stream url scheme"))
                        } else {
                            val resolvedUrl = if (mediaServer.isLoopbackUrl(rawUrl)) {
                                mediaServer.serveProxyUrl(rawUrl, mime)
                            } else {
                                rawUrl
                            }
                            if (resolvedUrl == null) {
                                result.success(notConfigured("loopback stream could not be proxied"))
                            } else {
                                loadOnSession(resolvedUrl, call, result)
                            }
                        }
                    }
                }
                "castQueue" -> loadQueueOnSession(call, result)
                "setPlaybackState" -> {
                    val action = call.argument<String>("action")
                    val positionMs = call.argument<Number>("positionMs")?.toLong()
                    handlePlaybackState(action, positionMs, result)
                }
                "getVolume" -> {
                    val session = currentSession()
                    val volume = try { session?.volume } catch (_: Exception) { null }
                    result.success(
                        if (session == null || volume == null) {
                            mapOf("success" to false)
                        } else {
                            mapOf("success" to true, "volume" to volume)
                        }
                    )
                }
                "setVolume" -> {
                    val requested = call.argument<Number>("volume")?.toDouble()
                    val session = currentSession()
                    if (session == null || requested == null) {
                        result.success(mapOf("success" to false))
                    } else {
                        try {
                            session.volume = requested.coerceIn(0.0, 1.0)
                            result.success(
                                mapOf("success" to true, "volume" to session.volume)
                            )
                        } catch (_: Exception) {
                            result.success(mapOf("success" to false))
                        }
                    }
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
            attachMediaClient(currentSession())
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
            attachMediaClient(currentSession())
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
            val info = buildMediaInfo(
                url = url,
                title = call.argument<String>("title") ?: "",
                artist = call.argument<String>("artist") ?: "",
                album = call.argument<String>("album") ?: "",
                artwork = call.argument<String>("artwork"),
                mime = call.argument<String>("mime") ?: "audio/mpeg",
                durationMs = call.argument<Number>("durationMs")?.toLong(),
            )
            try {
                val pending = client.load(info, true)
                awaitMediaResult(pending, result)
            } catch (e: Exception) {
                lastError = e.message
                result.success(notConfigured("load failed: ${e.message}"))
            }
        }
    }

    private fun loadQueueOnSession(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val rawItems = call.argument<List<Map<String, Any?>>>("items")
        if (rawItems.isNullOrEmpty()) {
            result.success(notConfigured("queue is empty"))
            return
        }
        val startIndex = (call.argument<Number>("startIndex")?.toInt() ?: 0)
            .coerceIn(0, rawItems.size - 1)
        val startPositionMs = (call.argument<Number>("startPositionMs")?.toLong() ?: 0L)
            .coerceAtLeast(0L)
        val repeat = call.argument<Boolean>("repeat") == true

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

            val queueItems = mutableListOf<MediaQueueItem>()
            for ((index, raw) in rawItems.withIndex()) {
                val mime = (raw["mime"] as? String)?.takeIf { it.isNotBlank() } ?: "audio/mpeg"
                val rawUrl = (raw["url"] as? String)?.trim()
                val rawPath = (raw["path"] as? String)?.trim()
                val resolvedUrl = when {
                    !rawUrl.isNullOrBlank() -> {
                        val scheme = try { android.net.Uri.parse(rawUrl).scheme?.lowercase() } catch (_: Exception) { null }
                        if (scheme != "http" && scheme != "https") null
                        else if (mediaServer.isLoopbackUrl(rawUrl)) mediaServer.serveProxyUrl(rawUrl, mime)
                        else rawUrl
                    }
                    !rawPath.isNullOrBlank() -> {
                        if (index == startIndex) mediaServer.preBufferFile(rawPath, mime)
                        else mediaServer.serveFile(rawPath, mime)
                    }
                    else -> null
                } ?: continue

                val mediaInfo = buildMediaInfo(
                    url = resolvedUrl,
                    title = raw["title"] as? String ?: "",
                    artist = raw["artist"] as? String ?: "",
                    album = raw["album"] as? String ?: "",
                    artwork = raw["artwork"] as? String,
                    mime = mime,
                    durationMs = (raw["durationMs"] as? Number)?.toLong(),
                )
                queueItems.add(MediaQueueItem.Builder(mediaInfo).build())
            }

            if (queueItems.isEmpty()) {
                result.success(notConfigured("no castable queue items"))
                return@ensureCast
            }

            val safeStartIndex = startIndex.coerceIn(0, queueItems.size - 1)
            val repeatMode = if (repeat) {
                MediaStatus.REPEAT_MODE_REPEAT_ALL
            } else {
                MediaStatus.REPEAT_MODE_REPEAT_OFF
            }
            try {
                val pending = client.queueLoad(
                    queueItems.toTypedArray(),
                    safeStartIndex,
                    repeatMode,
                    startPositionMs,
                    null,
                )
                awaitMediaResult(pending, result)
            } catch (e: Exception) {
                lastError = e.message
                result.success(notConfigured("queue load failed: ${e.message}"))
            }
        }
    }

    private fun buildMediaInfo(
        url: String,
        title: String,
        artist: String,
        album: String,
        artwork: String?,
        mime: String,
        durationMs: Long? = null,
    ): MediaInfo {
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
            putString(MediaMetadata.KEY_TITLE, title)
            putString(MediaMetadata.KEY_ARTIST, artist)
            putString(MediaMetadata.KEY_ALBUM_TITLE, album)
            if (!artwork.isNullOrBlank()) {
                addImage(
                    com.google.android.gms.common.images.WebImage(
                        android.net.Uri.parse(artwork)
                    )
                )
            }
        }
        val builder = MediaInfo.Builder(url)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(mime)
            .setMetadata(metadata)
        if (durationMs != null && durationMs > 0L) {
            builder.setStreamDuration(durationMs)
        }
        return builder.build()
    }

    private fun awaitMediaResult(
        pending: com.google.android.gms.common.api.PendingResult<RemoteMediaClient.MediaChannelResult>,
        result: MethodChannel.Result,
    ) {
        val responded = java.util.concurrent.atomic.AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        val timeoutRunnable = Runnable {
            if (responded.compareAndSet(false, true)) {
                lastError = "load timed out waiting for receiver"
                result.success(mapOf("success" to false, "error" to "load timed out waiting for receiver"))
            }
        }
        handler.postDelayed(timeoutRunnable, 10_000L)
        pending.setResultCallback { channelResult ->
            handler.removeCallbacks(timeoutRunnable)
            if (responded.compareAndSet(false, true)) {
                val status = channelResult.status
                if (status.isSuccess) {
                    lastError = null
                    emitSession(currentSession())
                    result.success(mapOf("success" to true))
                } else {
                    lastError = "load rejected by receiver: status ${status.statusCode}"
                    result.success(
                        mapOf(
                            "success" to false,
                            "error" to "load rejected by receiver",
                            "statusCode" to status.statusCode
                        )
                    )
                }
            }
        }
    }

    private fun handlePlaybackState(
        action: String?,
        positionMs: Long?,
        result: MethodChannel.Result,
    ) {
        val client = currentSession()?.remoteMediaClient
        if (client == null) {
            result.success(notConfigured("no active Cast session"))
            return
        }
        try {
            val pending = when (action) {
                "play" -> client.play()
                "pause" -> client.pause()
                "stop" -> client.stop()
                "next" -> client.queueNext(null)
                "previous" -> client.queuePrev(null)
                "seek" -> {
                    val pos = (positionMs ?: 0L).coerceAtLeast(0L)
                    client.seek(MediaSeekOptions.Builder().setPosition(pos).build())
                }
                else -> {
                    result.success(notConfigured("unknown action: $action"))
                    return
                }
            }
            awaitMediaResult(pending, result)
        } catch (e: Exception) {
            lastError = e.message
            result.success(notConfigured("control failed: ${e.message}"))
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

    private fun buildSessionPayload(session: CastSession?): Map<String, Any?> {
        val client = session?.remoteMediaClient
        val playing = try { client?.isPlaying ?: false } catch (_: Exception) { false }
        val paused = try { client?.isPaused ?: false } catch (_: Exception) { false }
        val buffering = try { client?.isBuffering ?: false } catch (_: Exception) { false }
        val position = try { client?.approximateStreamPosition ?: 0L } catch (_: Exception) { 0L }
        val duration = try { client?.streamDuration ?: 0L } catch (_: Exception) { 0L }
        val stateInt = try { client?.playerState ?: MediaStatus.PLAYER_STATE_UNKNOWN } catch (_: Exception) { MediaStatus.PLAYER_STATE_UNKNOWN }
        val playerState = when (stateInt) {
            MediaStatus.PLAYER_STATE_PLAYING -> "playing"
            MediaStatus.PLAYER_STATE_PAUSED -> "paused"
            MediaStatus.PLAYER_STATE_BUFFERING -> "buffering"
            MediaStatus.PLAYER_STATE_LOADING -> "loading"
            MediaStatus.PLAYER_STATE_IDLE -> "idle"
            else -> if (playing) "playing" else if (paused) "paused" else "idle"
        }
        val mediaMeta = try { client?.mediaInfo?.metadata } catch (_: Exception) { null }
        val title = try { mediaMeta?.getString(MediaMetadata.KEY_TITLE) } catch (_: Exception) { null }
        val artist = try { mediaMeta?.getString(MediaMetadata.KEY_ARTIST) } catch (_: Exception) { null }
        val volume = try { session?.volume } catch (_: Exception) { null }
        return mapOf(
            "type" to "session",
            "available" to true,
            "connected" to (session != null),
            "deviceName" to session?.castDevice?.friendlyName,
            "playing" to playing,
            "paused" to paused,
            "buffering" to buffering,
            "playerState" to playerState,
            "positionMs" to position,
            "durationMs" to duration.coerceAtLeast(0L),
            "title" to title,
            "artist" to artist,
            "volume" to volume,
            "error" to lastError,
        )
    }

    private fun emitSession(session: CastSession?) {
        val sink = eventSink ?: return
        val payload = buildSessionPayload(session)
        mainHandler.post {
            try {
                sink.success(payload)
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
