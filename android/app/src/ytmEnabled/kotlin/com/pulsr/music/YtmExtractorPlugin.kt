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
    private val executor: ExecutorService = Executors.newFixedThreadPool(3)

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
            "getPoTokenState" -> {
                result.success(
                    mapOf(
                        "isReady" to PoTokenManager.isReady,
                        "isExpired" to PoTokenManager.isExpired(),
                        "isExpiringSoon" to PoTokenManager.isExpiringSoon(),
                        "visitorData" to PoTokenManager.visitorData,
                        "webViewBroken" to PoTokenManager.webViewBroken,
                    )
                )
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
        executor.execute {
            try {
                ensureExtractorReady()
                val value = work()
                mainHandler.post { runCatching { result.success(value) } }
            } catch (e: Throwable) {
                Log.w(TAG, "YTM native request failed: ${e.message}")
                val code = errorCodeFor(e)
                mainHandler.post { runCatching { result.error(code, e.message, null) } }
            }
        }
    }

    private fun errorCodeFor(e: Throwable): String {
        val msg = e.message?.lowercase() ?: ""
        if (msg.contains("not a bot") || msg.contains("login_required") || msg.contains("recaptcha") || msg.contains("bot_block")) {
            return "YTM_BOT_BLOCKED"
        }
        return when (e) {
            is ReCaptchaException -> "YTM_RECAPTCHA"
            is ContentNotAvailableException -> "YTM_UNAVAILABLE"
            is IOException -> "YTM_NETWORK"
            is ExtractionException -> "YTM_EXTRACTION"
            else -> "YTM_FAILED"
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
     */
    private fun getPlaylist(urlOrId: String, limit: Int): Map<String, Any?> {
        val rawUrl = if (urlOrId.startsWith("http://") || urlOrId.startsWith("https://")) {
            urlOrId
        } else {
            "https://www.youtube.com/playlist?list=$urlOrId"
        }
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
     * Resolves audio stream using multi-client priority fallback:
     * 1. NewPipeExtractor with PoTokenProvider
     * 2. InnertubeClient fallback chain (WEB_REMIX -> ANDROID -> IOS -> TV)
     */
    private fun resolveStreamWithFallback(videoId: String, quality: String): Map<String, Any?> {
        // 1. Try NewPipeExtractor
        try {
            val stream = resolveStreamNewPipe(videoId, quality)
            return stream
        } catch (e: Throwable) {
            Log.w(TAG, "NewPipe stream extraction failed for $videoId: ${e.message}. Attempting Innertube client fallback...")
        }

        // 2. Multi-client fallback via InnertubeClient
        val ctx = context?.applicationContext
        if (ctx != null) {
            val client = InnertubeClient(ctx)
            return client.resolvePlayerStream(videoId, quality)
        }

        throw ExtractionException("Unable to resolve audio stream for videoId: $videoId")
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
            "userAgent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36",
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
    }
}
