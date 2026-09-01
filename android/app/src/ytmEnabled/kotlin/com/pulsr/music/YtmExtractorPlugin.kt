package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.schabi.newpipe.extractor.Image
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.ExtractionException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.extractors.YoutubeStreamExtractor
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import java.io.IOException
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * YouTube Music search, playlist extraction, and multi-client stream resolution.
 *
 * Hardened with:
 * - Proactive PoTokenManager attestation
 * - Multi-client stream resolution fallback (NewPipe -> Innertube WEB_REMIX -> ANDROID -> IOS -> TV)
 * - Continuation pagination for long playlists
 * - Multi-filter search fallback & deduplication
 * - Centralized YtmCookieStore integration
 */
class YtmExtractorPlugin : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    // TTFA (Item: plugin executor width): acquirePermit parks a pool thread
    // per blocked caller, so a 3-thread pool starves whenever >3 YTM calls
    // overlap (e.g. play resolve + search + pre-resolution + rate-limited
    // browse calls). 6 threads = the OkHttp Dispatcher maxRequestsPerHost
    // budget; each parked waiter is a parked semaphore await (no spinning),
    // so the extra threads cost idle-time only.
    private val executor: ExecutorService = Executors.newFixedThreadPool(6)

    companion object {
        private const val TAG = "YtmExtractorPlugin"
        private const val CHANNEL_NAME = "com.pulsr.music/ytm"
        private const val DEFAULT_SEARCH_LIMIT = 30

        private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")

        @Volatile
        private var extractorReady = false

        fun registerWith(flutterEngine: FlutterEngine, context: Context? = null): YtmExtractorPlugin {
            val plugin = YtmExtractorPlugin()
            plugin.context = context
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            context?.let { PoTokenManager.init(it) }
            // TTFA telemetry: one-way relay of key native timings to Dart
            // (attached to the Sentry playback transaction). Non-blocking.
            YtmMetricsRegistry.timingRelay = plugin::relayTiming
            return plugin
        }
    }

    @Volatile
    private var pendingCountry: String? = null
    @Volatile
    private var pendingLang: String? = null

    private fun ensureExtractorReady() {
        if (extractorReady) return
        synchronized(Companion) {
            if (extractorReady) return
            val appContext = context?.applicationContext
            val locale = resolveLocale()
            val countryCode = (pendingCountry?.takeIf { it.isNotBlank() }
                ?: locale.country).ifBlank { "US" }

            NewPipe.init(
                PulsrDownloader(appContext),
                Localization.fromLocale(locale),
                ContentCountry(countryCode),
            )

            if (appContext != null) {
                PoTokenManager.init(appContext)
                YoutubeStreamExtractor.setPoTokenProvider(PoTokenProviderImpl(appContext))
            } else {
                Log.w(TAG, "No context available during NewPipe initialization")
            }
            extractorReady = true
        }
    }

    private fun resolveLocale(): Locale {
        val lang = pendingLang?.takeIf { it.isNotBlank() }
        val country = pendingCountry?.takeIf { it.isNotBlank() }
        if (lang != null) {
            return if (country != null) Locale(lang, country) else Locale(lang)
        }
        val ctx = context
        if (ctx != null) {
            val config = ctx.resources.configuration
            val loc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                config.locales[0]
            } else {
                @Suppress("DEPRECATION")
                config.locale
            }
            if (loc != null) return loc
        }
        return Locale.getDefault()
    }

    private fun captureLocale(call: MethodCall) {
        if (extractorReady) return
        call.argument<String>("country")?.let { pendingCountry = it }
        call.argument<String>("lang")?.let { pendingLang = it }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "isWifiConnected" -> result.success(isWifiConnected())
            "ensurePoTokenReady" -> {
                runOffMainThread(result) {
                    val appContext = context?.applicationContext
                    if (appContext != null) {
                        PoTokenManager.init(appContext)
                        PoTokenManager.ensureReadySync()
                    } else {
                        false
                    }
                }
            }
            "invalidatePoToken" -> {
                PoTokenManager.invalidate()
                result.success(true)
            }
            "isVpnConnected" -> {
                val ctx = context?.applicationContext
                val isVpn = if (ctx != null) CellularFailoverHelper.isVpnActive(ctx) else false
                result.success(isVpn)
            }
            "preWarm" -> {
                val ctx = context?.applicationContext
                if (ctx != null) {
                    ClientCapabilityMatrix.init(ctx)
                    PoTokenManager.preWarm(ctx)
                }
                result.success(true)
            }
            "resetIdentities" -> {
                val ctx = context?.applicationContext
                if (ctx != null) {
                    PoTokenManager.invalidate()
                    FingerprintStore.resetFingerprint(ctx)
                    YtmCookieStore.getInstance(ctx).clearCookies()
                }
                result.success(true)
            }
            "getLimitedMode" -> {
                result.success(PoTokenManager.isLimitedMode)
            }
            "acquirePermit" -> {
                val bucketName = call.argument<String>("bucket") ?: "BROWSE"
                val bucket = runCatching { RateLimiter.Bucket.valueOf(bucketName) }.getOrDefault(RateLimiter.Bucket.BROWSE)
                runOffMainThread(result) {
                    RateLimiter.shared.acquirePermit(bucket)
                    true
                }
            }
            "releasePermit" -> {
                RateLimiter.shared.releasePermit()
                result.success(true)
            }
            "onRateLimited" -> {
                val retryAfter = call.argument<Number>("retryAfter")?.toLong()
                val backoff = RateLimiter.shared.onRateLimited(retryAfter)
                result.success(backoff)
            }
            "onSuccess" -> {
                RateLimiter.shared.onSuccess()
                result.success(true)
            }
            "getMetrics" -> {
                result.success(YtmMetricsRegistry.snapshotAll())
            }
            "recordMetric" -> {
                val operation = call.argument<String>("operation") ?: "unknown"
                val latencyMs = (call.argument<Number>("latencyMs") ?: 0).toLong()
                val isError = call.argument<Boolean>("isError") ?: false
                YtmMetricsRegistry.record(operation, latencyMs, isError)
                result.success(true)
            }
            "resetMetrics" -> {
                YtmMetricsRegistry.resetAll()
                result.success(true)
            }
            "getPoTokenState" -> {
                result.success(
                    mapOf(
                        "isReady" to PoTokenManager.isReady,
                        "isExpired" to PoTokenManager.isExpired(),
                        "isExpiringSoon" to PoTokenManager.isExpiringSoon(),
                        "visitorData" to PoTokenManager.visitorData,
                        "streamingPoToken" to PoTokenManager.streamingPoToken,
                        "webViewBroken" to PoTokenManager.webViewBroken,
                        "isLimitedMode" to PoTokenManager.isLimitedMode,
                    )
                )
            }
            "getAccountPoToken" -> {
                val dataSyncId = call.argument<String>("dataSyncId")?.trim()
                if (dataSyncId.isNullOrEmpty()) {
                    result.error("YTM_INVALID_ARGUMENT", "dataSyncId is required", null)
                    return
                }
                runOffMainThread(result) {
                    PoTokenManager.setDataSyncId(dataSyncId)
                    mapOf(
                        "poToken" to PoTokenManager.accountPoTokenForSync(dataSyncId),
                        "visitorData" to PoTokenManager.sessionVisitorData.ifEmpty { PoTokenManager.visitorData },
                    )
                }
            }
            "setDataSyncId" -> {
                val dataSyncId = call.argument<String>("dataSyncId")?.trim()
                if (!dataSyncId.isNullOrEmpty()) {
                    val appContext = context?.applicationContext
                    if (appContext != null) PoTokenManager.init(appContext)
                    PoTokenManager.setDataSyncId(dataSyncId)
                }
                result.success(true)
            }
            "updateClientVersion" -> {
                val clientName = call.argument<String>("clientName")
                val version = call.argument<String>("version")
                if (clientName != null && version != null) {
                    val type = runCatching { InnertubeClient.ClientType.valueOf(clientName) }.getOrNull()
                    if (type != null) {
                        ClientCapabilityMatrix.updateClientVersion(type, version)
                        result.success(true)
                        return
                    }
                }
                result.success(false)
            }
            "updateCapabilityMatrix" -> {
                val json = call.argument<String>("json")
                if (!json.isNullOrEmpty()) {
                    ClientCapabilityMatrix.loadFromJson(json)
                    result.success(true)
                    return
                }
                result.success(false)
            }
            "search" -> {
                val query = call.argument<String>("query")?.trim()
                if (query.isNullOrEmpty()) {
                    result.error("YTM_INVALID_ARGUMENT", "query is required", null)
                    return
                }
                captureLocale(call)
                val limit = call.argument<Int>("limit") ?: DEFAULT_SEARCH_LIMIT
                runOffMainThread(result) { search(query, limit) }
            }
            "trending" -> {
                captureLocale(call)
                val limit = call.argument<Int>("limit") ?: DEFAULT_SEARCH_LIMIT
                runOffMainThread(result) { trending(limit) }
            }
            "getPlaylist" -> {
                val url = call.argument<String>("url")?.trim()
                if (url.isNullOrEmpty()) {
                    result.error("YTM_INVALID_ARGUMENT", "url is required", null)
                    return
                }
                val limit = call.argument<Int>("limit") ?: 100
                runOffMainThread(result) { getPlaylist(url, limit) }
            }
            "getCookies" -> {
                val ctx = context
                if (ctx != null) {
                    val cookieStore = YtmCookieStore.getInstance(ctx)
                    val merged = cookieStore.readFromCookieManager() ?: cookieStore.getMergedCookieHeader()
                    result.success(merged)
                } else {
                    result.success(null)
                }
            }
            "setCookies" -> {
                val cookies = call.argument<String>("cookies")
                val ctx = context
                if (ctx != null) {
                    YtmCookieStore.getInstance(ctx).setCookies(cookies ?: "")
                }
                result.success(true)
            }
            "resolveStream" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId == null || !VIDEO_ID.matches(videoId)) {
                    result.error("YTM_INVALID_ARGUMENT", "videoId is not a YouTube id", null)
                    return
                }
                val quality = call.argument<String>("quality") ?: "high"
                runOffMainThread(result) { resolveStreamWithFallback(videoId, quality) }
            }
            else -> result.notImplemented()
        }
    }

    private fun isWifiConnected(): Boolean {
        val ctx = context ?: return true
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } else {
            @Suppress("DEPRECATION")
            val netInfo = cm.activeNetworkInfo ?: return false
            @Suppress("DEPRECATION")
            netInfo.type == ConnectivityManager.TYPE_WIFI ||
                netInfo.type == ConnectivityManager.TYPE_ETHERNET
        }
    }

    private fun runOffMainThread(result: MethodChannel.Result, work: () -> Any?) {
        val submittedAt = System.currentTimeMillis()
        executor.execute {
            // TTFA telemetry: cheap measure of how long the call waited for a
            // pool thread before running.
            val queueWaitMs = System.currentTimeMillis() - submittedAt
            YtmMetricsRegistry.recordRelayed("executor.queue_wait", queueWaitMs)
            try {
                ensureExtractorReady()
                val value = work()
                mainHandler.post { runCatching { result.success(value) } }
            } catch (e: Throwable) {
                Log.w(TAG, "YTM native request failed: ${e.message}")
                val code = errorCodeFor(e)
                val details = if (e is InnertubeClient.InnertubeException) {
                    mapOf("signal" to e.signal.code, "traceId" to e.traceId)
                } else {
                    null
                }
                mainHandler.post { runCatching { result.error(code, e.message, details) } }
            }
        }
    }

    /**
     * TTFA telemetry: forwards one key native timing over the plugin channel
     * to Dart (playback_latency_tracker attaches it to the Sentry playback
     * transaction). Safe from any thread — the invoke is posted to
     * [mainHandler] and never blocks the caller.
     */
    private fun relayTiming(
        name: String,
        durationMs: Long,
        isError: Boolean,
        attrs: Map<String, Any?>?
    ) {
        val ch = channel ?: return
        val payload = HashMap<String, Any?>(8)
        payload["name"] = name
        payload["durationMs"] = durationMs
        payload["isError"] = isError
        if (!attrs.isNullOrEmpty()) payload["attrs"] = attrs
        mainHandler.post {
            runCatching { ch.invokeMethod("nativeTiming", payload) }
        }
    }

    private fun errorCodeFor(e: Throwable): String {
        if (e is InnertubeClient.YtmSignInRequiredAbortException) {
            return "YTM_SIGNIN_REQUIRED"
        }
        if (e is InnertubeClient.InnertubeException) {
            return e.signal.code
        }
        if (e is PoTokenException.WebViewUnavailable || e is BadWebViewException) {
            return "PO_TOKEN_BROKEN"
        }
        if (e is PoTokenException.Timeout) {
            return "PO_TOKEN_TIMEOUT"
        }
        if (e is PoTokenException.Invalidated) {
            return "PO_TOKEN_INVALID"
        }
        if (e is PoTokenException) {
            return "PO_TOKEN_UNAVAILABLE"
        }
        val msg = e.message?.lowercase() ?: ""
        if (msg.contains("not a bot") || msg.contains("login_required") || msg.contains("recaptcha") || msg.contains("bot_block")) {
            return "BOT_CHALLENGE"
        }
        return when (e) {
            is ReCaptchaException -> "BOT_CHALLENGE"
            is ContentNotAvailableException -> "VIDEO_GONE"
            is IOException -> "IP_BLOCKED"
            is ExtractionException -> "CLIENT_DEPRECATED"
            else -> "RATE_LIMITED"
        }
    }

    /**
     * Search with multi-filter fallback:
     * If MUSIC_SONGS produces no results, retries with playlists and artists and merges.
     */
    private fun search(query: String, limit: Int): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenVideoIds = mutableSetOf<String>()

        // 1. Primary: MUSIC_SONGS
        try {
            val songsExtractor = ServiceList.YouTube.getSearchExtractor(
                query,
                listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS),
                "",
            )
            songsExtractor.fetchPage()
            val songItems = SearchInfo.getInfo(songsExtractor).relatedItems.asSequence().filterIsInstance<StreamInfoItem>()
            for (map in streamItemsToMaps(songItems, limit)) {
                val vid = map["videoId"] as? String
                if (vid != null && seenVideoIds.add(vid)) {
                    results.add(map)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Primary songs search failed: ${e.message}")
        }

        // 2. Fallback if empty: General search
        if (results.isEmpty()) {
            try {
                val generalExtractor = ServiceList.YouTube.getSearchExtractor(query)
                generalExtractor.fetchPage()
                val items = SearchInfo.getInfo(generalExtractor).relatedItems.asSequence().filterIsInstance<StreamInfoItem>()
                for (map in streamItemsToMaps(items, limit)) {
                    val vid = map["videoId"] as? String
                    if (vid != null && seenVideoIds.add(vid)) {
                        results.add(map)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "General search fallback failed: ${e.message}")
            }
        }

        return results.take(limit)
    }

    private fun trending(limit: Int): List<Map<String, Any?>> {
        return try {
            val kioskList = ServiceList.YouTube.kioskList
            val kioskExtractor = kioskList.getExtractorById(kioskList.defaultKioskId, null)
            kioskExtractor.fetchPage()
            val kioskInfo = org.schabi.newpipe.extractor.kiosk.KioskInfo.getInfo(kioskExtractor)
            streamItemsToMaps(
                kioskInfo.relatedItems.asSequence().filterIsInstance<StreamInfoItem>(),
                limit,
            )
        } catch (_: Throwable) {
            emptyList()
        }
    }

    /**
     * Playlist extraction with continuation pagination up to [limit].
     *
     * Liked-songs variants (LM, VLLM, LL, FEmusic_liked_*) are routed through
     * [InnertubeClient.requestBrowse] because NewPipe's PlaylistExtractor cannot
     * authenticate against YouTube's private `LL` playlist and always throws
     * "URL not accepted". All other playlists continue to use NewPipe.
     */
    private fun getPlaylist(urlOrId: String, limit: Int): Map<String, Any?> {
        val trimmed = urlOrId.trim()

        // Detect liked-songs IDs (private playlist — NewPipe cannot handle them)
        val isLikedSongs = trimmed == "LM" || trimmed == "VLLM" || trimmed == "LL" ||
            trimmed == "FEmusic_liked_videos" || trimmed == "FEmusic_liked_tracks" ||
            trimmed == "VLSE" ||
            trimmed.contains("playlist?list=LM") ||
            trimmed.contains("playlist?list=VLLM") ||
            trimmed.contains("playlist?list=LL")

        if (isLikedSongs) {
            return getPlaylistViaInnertube(limit)
        }

        // ── Public playlists via NewPipe ──────────────────────────────────────
        val cleanId = trimmed
        val rawUrl = if (cleanId.startsWith("http://") || cleanId.startsWith("https://")) {
            cleanId
        } else {
            "https://www.youtube.com/playlist?list=$cleanId"
        }
        // Normalise music.youtube.com → www.youtube.com for NewPipe compatibility
        val url = rawUrl.replace("music.youtube.com", "www.youtube.com")

        val extractor = ServiceList.YouTube.getPlaylistExtractor(url)
        extractor.fetchPage()
        val playlistInfo = PlaylistInfo.getInfo(extractor)

        val allItems = mutableListOf<StreamInfoItem>()
        allItems.addAll(playlistInfo.relatedItems.filterIsInstance<StreamInfoItem>())

        // Follow continuation pagination if available and limit not reached
        var nextPage: Page? = playlistInfo.nextPage
        var pageCount = 0
        while (nextPage != null && allItems.size < limit && pageCount < 10) {
            try {
                val pageResult = extractor.getPage(nextPage)
                val newItems = pageResult.items.filterIsInstance<StreamInfoItem>()
                if (newItems.isEmpty()) break
                allItems.addAll(newItems)
                nextPage = pageResult.nextPage
                pageCount++
            } catch (e: Exception) {
                Log.w(TAG, "Pagination fetch error: ${e.message}")
                break
            }
        }

        val tracks = streamItemsToMaps(allItems.asSequence(), limit)
        return mapOf(
            "title" to playlistInfo.name,
            "uploader" to (playlistInfo.uploaderName ?: ""),
            "thumbnailUrl" to bestArtwork(playlistInfo.thumbnails),
            "tracks" to tracks,
        )
    }

    /**
     * Fetches the liked-songs playlist via [InnertubeClient] browse (VLLM → LM fallback).
     *
     * Uses the authenticated cookie store so the request is account-scoped. Parses
     * `musicResponsiveListItemRenderer` and `musicPlaylistShelfRenderer` containers
     * from the JSON response and converts them to the same map format as [streamItemsToMaps].
     */
    private fun getPlaylistViaInnertube(limit: Int): Map<String, Any?> {
        val ctx = context?.applicationContext
            ?: throw ExtractionException("No context for InnertubeClient")

        // Ensure latest cookies from webview are in the store
        YtmCookieStore.getInstance(ctx).readFromCookieManager()

        val client = InnertubeClient(ctx)

        // Try browse IDs in priority order — VLLM is the canonical "browse as playlist" form
        val browseIds = listOf("VLLM", "FEmusic_liked_videos", "FEmusic_liked_tracks", "LM")
        var lastError: Throwable? = null

        for (bId in browseIds) {
            try {
                Log.d(TAG, "Liked songs: trying InnertubeClient browse with browseId=$bId")
                val json = client.requestBrowse(bId)
                val tracks = parseInnertubeTracksFromJson(json, limit)
                if (tracks.isNotEmpty()) {
                    Log.i(TAG, "Liked songs: parsed ${tracks.size} tracks via browseId=$bId")

                    // Follow continuation pages
                    val allTracks = tracks.toMutableList()
                    var currentJson = json
                    var pageCount = 0
                    while (allTracks.size < limit && pageCount < 10) {
                        val token = extractContinuationToken(currentJson) ?: break
                        try {
                            val contJson = client.requestContinuation(token)
                            val contTracks = parseInnertubeTracksFromJson(contJson, limit - allTracks.size)
                            if (contTracks.isEmpty()) break
                            allTracks.addAll(contTracks)
                            currentJson = contJson
                            pageCount++
                        } catch (e: Exception) {
                            Log.w(TAG, "Liked songs continuation failed: ${e.message}")
                            break
                        }
                    }

                    return mapOf(
                        "title" to "Liked Music",
                        "uploader" to "",
                        "thumbnailUrl" to null,
                        "tracks" to allTracks.take(limit),
                    )
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Liked songs InnertubeClient browse $bId failed: ${e.message}")
                lastError = e
            }
        }

        throw ExtractionException(
            "Unable to fetch liked songs via InnertubeClient",
            lastError,
        )
    }

    /**
     * Parses track maps from an InnerTube browse JSON response.
     * Handles `musicPlaylistShelfRenderer`, `musicShelfRenderer`, and
     * `musicResponsiveListItemRenderer` containers.
     */
    private fun parseInnertubeTracksFromJson(
        json: org.json.JSONObject,
        limit: Int,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()

        fun parseRenderer(renderer: org.json.JSONObject) {
            val videoId = renderer.optString("videoId").takeIf { it.length == 11 } ?: run {
                // Try nested watchEndpoint paths
                renderer.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("watchEndpoint")
                    ?.optString("videoId")
                    ?.takeIf { it.length == 11 }
            } ?: return

            // Title from flexColumns[0]
            var title = "Unknown Title"
            val flexCols = renderer.optJSONArray("flexColumns")
            if (flexCols != null && flexCols.length() > 0) {
                val runs = flexCols.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
                if (runs != null && runs.length() > 0) {
                    title = runs.optJSONObject(0)?.optString("text") ?: title
                }
            }

            // Artist from flexColumns[1] subtitle runs
            var artist = "Unknown Artist"
            if (flexCols != null && flexCols.length() > 1) {
                val runs = flexCols.optJSONObject(1)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
                if (runs != null) {
                    for (i in 0 until runs.length()) {
                        val text = runs.optJSONObject(i)?.optString("text")?.trim() ?: continue
                        if (text.isNotEmpty() && text != "•" && text != "·" &&
                            text.lowercase() != "song" && text.lowercase() != "video"
                        ) {
                            artist = text
                            break
                        }
                    }
                }
            }

            // Duration from fixedColumns[0]
            var durationSec = 0
            val fixedCols = renderer.optJSONArray("fixedColumns")
            if (fixedCols != null && fixedCols.length() > 0) {
                val durText = fixedCols.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
                    ?.optJSONObject(0)
                    ?.optString("text")
                if (durText != null) {
                    val parts = durText.split(":").mapNotNull { it.toIntOrNull() }
                    durationSec = when (parts.size) {
                        2 -> parts[0] * 60 + parts[1]
                        3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
                        else -> 0
                    }
                }
            }

            // Thumbnail
            val thumbUrl: String? = renderer
                .optJSONObject("thumbnail")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail")
                ?.optJSONArray("thumbnails")
                ?.let { arr ->
                    if (arr.length() > 0) arr.optJSONObject(arr.length() - 1)?.optString("url")
                    else null
                }

            results.add(
                mapOf(
                    "videoId" to videoId,
                    "title" to title,
                    "uploader" to artist,
                    "thumbnailUrl" to thumbUrl,
                    "duration" to durationSec.toLong(),
                    "viewCount" to -1L,
                    "isLive" to false,
                    "shortDescription" to null,
                    "url" to "https://music.youtube.com/watch?v=$videoId",
                )
            )
        }

        fun traverseJson(node: Any?) {
            when (node) {
                is org.json.JSONObject -> {
                    // Container renderers — recurse into contents
                    val shelfKeys = listOf("musicPlaylistShelfRenderer", "musicShelfRenderer")
                    for (key in shelfKeys) {
                        if (node.has(key)) {
                            val contents = node.optJSONObject(key)?.optJSONArray("contents")
                            if (contents != null) {
                                for (i in 0 until contents.length()) {
                                    if (results.size >= limit) return
                                    traverseJson(contents.opt(i))
                                }
                            }
                            return
                        }
                    }
                    // Leaf renderer
                    if (node.has("musicResponsiveListItemRenderer")) {
                        parseRenderer(node.getJSONObject("musicResponsiveListItemRenderer"))
                        return
                    }
                    // Generic recursion
                    val keys = node.keys()
                    while (keys.hasNext()) {
                        if (results.size >= limit) return
                        traverseJson(node.opt(keys.next()))
                    }
                }
                is org.json.JSONArray -> {
                    for (i in 0 until node.length()) {
                        if (results.size >= limit) return
                        traverseJson(node.opt(i))
                    }
                }
            }
        }

        traverseJson(json)
        return results
    }

    /** Extracts a continuation token from an InnerTube JSON response object. */
    private fun extractContinuationToken(json: org.json.JSONObject): String? {
        fun find(node: Any?): String? {
            return when (node) {
                is org.json.JSONObject -> {
                    // nextContinuationData.continuation
                    node.optJSONObject("nextContinuationData")
                        ?.optString("continuation")?.takeIf { it.isNotEmpty() }
                        // continuationEndpoint.continuationCommand.token
                        ?: node.optJSONObject("continuationEndpoint")
                            ?.optJSONObject("continuationCommand")
                            ?.optString("token")?.takeIf { it.isNotEmpty() }
                        ?: node.optJSONObject("continuationCommand")
                            ?.optString("token")?.takeIf { it.isNotEmpty() }
                        ?: run {
                            val keys = node.keys()
                            while (keys.hasNext()) {
                                val r = find(node.opt(keys.next()))
                                if (r != null) return@run r
                            }
                            null
                        }
                }
                is org.json.JSONArray -> {
                    for (i in 0 until node.length()) {
                        val r = find(node.opt(i))
                        if (r != null) return r
                    }
                    null
                }
                else -> null
            }
        }
        return find(json)
    }

    /**
     * Resolves audio stream using dual-engine fallback:
     * 1. Native InnertubeClient (fast, multi-client, itag ladder)
     * 2. NewPipeExtractor bridge fallback
     */
    private fun resolveStreamWithFallback(videoId: String, quality: String): Map<String, Any?> {
        var innertubeError: Throwable? = null
        val ctx = context?.applicationContext

        // 1. Primary: Native InnertubeClient
        if (ctx != null) {
            val client = InnertubeClient(ctx)
            try {
                val res = client.resolvePlayerStream(videoId, quality)
                val streamUrl = res["url"] as? String
                if (streamUrl != null) {
                    val uriHost = runCatching { java.net.URI(streamUrl).host }.getOrNull()
                    if (uriHost != null) {
                        val pinnedFamily = YtmHttpClient.getPinnedIpFamily(uriHost)
                        ProxyManager.setPinnedIpFamily(pinnedFamily)
                    }
                }
                return res
            } catch (e: Throwable) {
                innertubeError = e
                Log.w(TAG, "Native Innertube stream extraction failed for $videoId: ${e.message}. Attempting NewPipeExtractor fallback...")
            }
        }

        // 2. Fallback: NewPipeExtractor
        try {
            val stream = resolveStreamNewPipe(videoId, quality)
            return stream
        } catch (newPipeError: Throwable) {
            if (innertubeError != null) {
                newPipeError.addSuppressed(innertubeError)
            }
            throw innertubeError ?: newPipeError
        }
    }

    private fun resolveStreamNewPipe(videoId: String, quality: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        if (info.streamType == StreamType.LIVE_STREAM || info.streamType == StreamType.AUDIO_LIVE_STREAM) {
            throw ExtractionException("Live streams are not supported")
        }

        val playable = info.audioStreams.filter {
            it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && !it.content.isNullOrEmpty()
        }
        if (playable.isEmpty()) {
            throw ExtractionException("No progressive audio stream available in NewPipe extractor")
        }

        val m4aStreams = playable.filter { it.format == MediaFormat.M4A }
        val streamPool = if (m4aStreams.isNotEmpty()) m4aStreams else playable

        val selected = when (quality.lowercase()) {
            "low" -> streamPool.minByOrNull { it.averageBitrate }
            "medium" -> streamPool.minByOrNull { kotlin.math.abs(it.averageBitrate - 128) }
            else -> streamPool.maxByOrNull { it.averageBitrate }
        } ?: streamPool.first()

        return mapOf(
            "videoId" to videoId,
            "url" to selected.content,
            "mimeType" to (selected.format?.mimeType ?: "audio/mp4"),
            "container" to (selected.format?.suffix ?: ""),
            "bitrateKbps" to selected.averageBitrate.coerceAtLeast(0),
            "durationMs" to info.duration.coerceAtLeast(0L) * 1000L,
            "title" to info.name,
            "artist" to (info.uploaderName ?: ""),
            "artworkUrl" to bestArtwork(info.thumbnails),
            "userAgent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.7204.93 Safari/537.36",
        )
    }

    private fun streamItemsToMaps(items: Sequence<StreamInfoItem>, limit: Int): List<Map<String, Any?>> =
        items
            .filterNot { it.streamType == StreamType.LIVE_STREAM || it.streamType == StreamType.AUDIO_LIVE_STREAM }
            .mapNotNull { item ->
                val videoId = videoIdOf(item.url) ?: return@mapNotNull null
                mapOf(
                    "videoId" to videoId,
                    "title" to item.name,
                    "artist" to (item.uploaderName ?: ""),
                    "durationMs" to item.duration.coerceAtLeast(0L) * 1000L,
                    "artworkUrl" to bestArtwork(item.thumbnails),
                )
            }
            .take(limit)
            .toList()

    private fun videoIdOf(url: String?): String? {
        if (url == null) return null
        val fromFactory = runCatching { YoutubeStreamLinkHandlerFactory.getInstance().getId(url) }
            .getOrNull()
        val id = fromFactory ?: runCatching { Uri.parse(url).getQueryParameter("v") }.getOrNull()
        return id?.takeIf { VIDEO_ID.matches(it) }
    }

    private fun bestArtwork(images: List<Image>?): String? {
        if (images.isNullOrEmpty()) return null
        val sized = images.filter { it.width > 0 }
        val rawUrl = sized.maxByOrNull { it.width * it.height }?.url
            ?: sized.maxByOrNull { it.width }?.url
            ?: images.last().url

        return upgradeToHighRes(rawUrl)
    }

    private fun upgradeToHighRes(url: String): String {
        var upgraded = url
        if (upgraded.contains("googleusercontent.com") || upgraded.contains("ggpht.com")) {
            upgraded = upgraded.replace(Regex("=w\\d+-h\\d+[^?]*"), "=s1200")
            upgraded = upgraded.replace(Regex("=s\\d+[^?]*"), "=s1200")
        }
        return upgraded
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
        executor.shutdownNow()
        InnertubeClient.shutdown()
    }
}
