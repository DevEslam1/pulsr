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
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.ExtractionException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import java.io.IOException
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * YouTube Music search and stream resolution over NewPipeExtractor.
 *
 * Only compiled into the `dev` and `ytm` flavors. The `prod` (Play Store) flavor
 * gets the stub in src/ytmDisabled instead, so it never links the GPL-3.0
 * extractor at all.
 */
class YtmExtractorPlugin : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newFixedThreadPool(2)

    companion object {
        private const val TAG = "YtmExtractorPlugin"
        private const val CHANNEL_NAME = "com.pulsr.music/ytm"
        private const val DEFAULT_SEARCH_LIMIT = 30

        /** Every YouTube video id is exactly 11 base64url characters. */
        private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")

        /**
         * Below this the thumbnail is a list-row placeholder rather than usable
         * cover art; above it the extra bytes buy nothing at Pulsr's tile sizes.
         */
        private const val PREFERRED_ARTWORK_PX = 300

        @Volatile
        private var extractorReady = false

        fun registerWith(flutterEngine: FlutterEngine, context: Context? = null): YtmExtractorPlugin {
            val plugin = YtmExtractorPlugin()
            plugin.context = context
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    // Locale the extractor should localize to. Set from the Dart call (device
    // locale) before the one-time NewPipe.init; falls back to the Android
    // resource config / JVM default when Dart provides nothing.
    @Volatile
    private var pendingCountry: String? = null
    @Volatile
    private var pendingLang: String? = null

    private fun ensureExtractorReady() {
        if (extractorReady) return
        synchronized(Companion) {
            if (extractorReady) return
            val locale = resolveLocale()
            val countryCode = (pendingCountry?.takeIf { it.isNotBlank() }
                ?: locale.country).ifBlank { "US" }
            NewPipe.init(
                PulsrDownloader(),
                Localization.fromLocale(locale),
                ContentCountry(countryCode),
            )
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

    /**
     * Records the caller's locale so the one-time [ensureExtractorReady] can
     * localize to it. No-op once the extractor is initialized (NewPipe's
     * localization is global and fixed at init).
     */
    private fun captureLocale(call: MethodCall) {
        if (extractorReady) return
        call.argument<String>("country")?.let { pendingCountry = it }
        call.argument<String>("lang")?.let { pendingLang = it }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "isWifiConnected" -> {
                val isWifi = isWifiConnected()
                result.success(isWifi)
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
                val urls = listOf(
                    "https://music.youtube.com",
                    "https://www.youtube.com",
                    "https://accounts.google.com",
                    "https://youtube.com"
                )
                val cookieJar = mutableMapOf<String, String>()
                val cm = android.webkit.CookieManager.getInstance()
                for (u in urls) {
                    val c = cm.getCookie(u) ?: continue
                    for (pair in c.split(";")) {
                        val parts = pair.trim().split("=", limit = 2)
                        if (parts.size == 2 && parts[0].isNotBlank()) {
                            cookieJar[parts[0].trim()] = parts[1].trim()
                        }
                    }
                }
                val merged = cookieJar.entries.joinToString("; ") { "${it.key}=${it.value}" }
                result.success(merged)
            }
            "resolveStream" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId == null || !VIDEO_ID.matches(videoId)) {
                    result.error("YTM_INVALID_ARGUMENT", "videoId is not a YouTube id", null)
                    return
                }
                val quality = call.argument<String>("quality") ?: "high"
                runOffMainThread(result) { resolveStream(videoId, quality) }
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
                // runCatching: the engine may be torn down while a request is in flight.
                mainHandler.post { runCatching { result.success(value) } }
            } catch (e: Throwable) {
                Log.w(TAG, "YTM request failed: ${e.message}")
                val code = errorCodeFor(e)
                mainHandler.post { runCatching { result.error(code, e.message, null) } }
            }
        }
    }

    private fun errorCodeFor(e: Throwable): String = when (e) {
        is ReCaptchaException -> "YTM_RECAPTCHA"
        is ContentNotAvailableException -> "YTM_UNAVAILABLE"
        is IOException -> "YTM_NETWORK"
        is ExtractionException -> "YTM_EXTRACTION"
        else -> "YTM_FAILED"
    }

    private fun search(query: String, limit: Int): List<Map<String, Any?>> {
        val extractor = ServiceList.YouTube.getSearchExtractor(
            query,
            listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS),
            "",
        )
        extractor.fetchPage()
        return streamItemsToMaps(
            SearchInfo.getInfo(extractor).relatedItems.asSequence().filterIsInstance<StreamInfoItem>(),
            limit,
        )
    }

    /**
     * Surfaces trending music via YouTube's Trending kiosk. The kiosk is
     * localized by the [ContentCountry] set at init, so results follow the
     * device locale instead of a hardcoded region.
     */
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
        val items = playlistInfo.relatedItems.asSequence().filterIsInstance<StreamInfoItem>()
        val tracks = streamItemsToMaps(items, limit)
        return mapOf(
            "title" to playlistInfo.name,
            "uploader" to (playlistInfo.uploaderName ?: ""),
            "thumbnailUrl" to bestArtwork(playlistInfo.thumbnails),
            "tracks" to tracks,
        )
    }

    /** Shared shape for search and trending results, keyed to match [YtmTrack.fromChannel]. */
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

    private fun resolveStream(videoId: String, quality: String = "high"): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        if (info.streamType == StreamType.LIVE_STREAM || info.streamType == StreamType.AUDIO_LIVE_STREAM) {
            throw ExtractionException("Live streams are not supported")
        }

        val playable = info.audioStreams.filter {
            it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && !it.content.isNullOrEmpty()
        }
        if (playable.isEmpty()) {
            throw ExtractionException("No progressive audio stream available")
        }

        // M4A/AAC first: jaudiotagger (used by TagEditorPlugin) writes MP4 atoms
        // reliably but handles Opus-in-WebM poorly, so downloads must land as M4A
        // for tagging to work. Other containers are only a streaming fallback.
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
        )
    }

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
