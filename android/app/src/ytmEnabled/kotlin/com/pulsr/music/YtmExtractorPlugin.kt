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
import org.json.JSONArray
import org.json.JSONObject
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
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger

/**
 * YouTube Music search, playlist extraction, and multi-client stream resolution.
 *
 * Production-hardened with:
 * - Thread-safe off-main-thread execution for all MethodChannel handlers
 * - Selective NewPipe initialization (only for methods requiring NewPipe)
 * - Safe MethodChannel result encoding handling (no hung Dart futures on codec failures)
 * - Canonical track map schema harmonized across NewPipe and InnerTube
 * - Distinguishes empty playlists from network/auth/bot browse errors
 * - Deep cause-chain error classification with HTTP status code and multi-lingual bot detection
 * - Sanitized parameter bounds, safe locale resolution, and lifecycle cleanup
 */
class YtmExtractorPlugin : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val threadCounter = AtomicInteger(0)
    private val executor: ExecutorService = Executors.newFixedThreadPool(3, ThreadFactory { r ->
        Thread(r, "ytm-plugin-${threadCounter.incrementAndGet()}").apply {
            isDaemon = true
        }
    })

    companion object {
        private const val TAG = "YtmExtractorPlugin"
        private const val CHANNEL_NAME = "com.pulsr.music/ytm"
        private const val DEFAULT_SEARCH_LIMIT = 30
        private const val MAX_SEARCH_LIMIT = 200
        private const val DEFAULT_PLAYLIST_LIMIT = 100
        private const val MAX_PLAYLIST_LIMIT = 1000
        private const val MAX_PAGES = 30
        private const val DEFAULT_EXPIRY_SECONDS = 21600L // 6 hours
        private const val DEFAULT_COUNTRY_CODE = "US"
        private const val MAX_TRAVERSAL_DEPTH = 40

        private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")
        private val CLIENT_VERSION_REGEX = Regex("^\\d+(\\.\\d+)+$")
        private val LANGUAGE_REGEX = Regex("^[a-zA-Z]{2,8}$")
        private val COUNTRY_REGEX = Regex("^[a-zA-Z]{2}$")
        private val HTTP_429_REGEX = Regex("\\b429\\b")
        private val HTTP_407_REGEX = Regex("\\b407\\b")
        private val HTTP_403_REGEX = Regex("\\b403\\b")

        private val MEDIA_TYPE_LABELS = setOf(
            "song", "video", "canción", "cancion", "vídeo", "música", "musica",
            "chanson", "titel", "lied", "piste", "brano", "faixa", "أغنية", "فيديو",
            "曲", "노래", "歌曲", "音乐", "音樂", "песня", "видео", "şarkı", "गीत", "गाना"
        )

        private fun normalizeDigits(input: String): String {
            val sb = StringBuilder(input.length)
            for (ch in input) {
                when (ch) {
                    in '0'..'9' -> sb.append(ch)
                    in '\u0660'..'\u0669' -> sb.append((ch.code - 0x0660 + '0'.code).toChar())
                    in '\u06f0'..'\u06f9' -> sb.append((ch.code - 0x06f0 + '0'.code).toChar())
                    in '\u0966'..'\u096f' -> sb.append((ch.code - 0x0966 + '0'.code).toChar())
                    else -> sb.append(ch)
                }
            }
            return sb.toString()
        }

        private val initLock = Any()

        @Volatile
        private var extractorReady = false

        @Volatile
        private var pendingCountry: String? = null

        @Volatile
        private var pendingLang: String? = null

        fun registerWith(flutterEngine: FlutterEngine, context: Context? = null): YtmExtractorPlugin {
            val plugin = YtmExtractorPlugin()
            val appContext = context?.applicationContext
            plugin.context = appContext
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)

            // Off the main thread: the first init decrypts the persisted poToken via
            // EncryptedSharedPreferences, which is keystore-backed disk I/O and ran
            // during engine attach.
            appContext?.let { ctx ->
                plugin.executor.execute {
                    runCatching {
                        plugin.ensureExtractorReady()
                        PoTokenManager.init(ctx)
                    }
                }
                plugin.executor.execute {
                    runCatching {
                        plugin.ensureExtractorReady()
                        PlayerJavaScript.warmUp()
                    }
                }
            }

            // Proxy rotation changes egress -> re-mint tokens
            ProxyPool.setOnPathChangeListener { label -> EgressSignals.onEgressChanged?.invoke(label) }
            EgressSignals.onEgressChanged = { id -> PoTokenManager.onEgressChanged(id) }
            return plugin
        }
    }

    private fun ensureExtractorReady() {
        if (extractorReady) return
        synchronized(initLock) {
            if (extractorReady) return
            val appContext = context?.applicationContext
                ?: throw ExtractionException("No application context available for NewPipe initialization")

            val locale = resolveLocale()
            val countryCode = (pendingCountry?.takeIf { it.isNotBlank() }
                ?: locale.country).ifBlank { DEFAULT_COUNTRY_CODE }

            NewPipe.init(
                PulsrDownloader(appContext),
                Localization.fromLocale(locale),
                ContentCountry(countryCode),
            )

            PoTokenManager.init(appContext)
            RateLimiter.shared.initPrefs(appContext)
            YoutubeStreamExtractor.setPoTokenProvider(PoTokenProviderImpl(appContext))
            extractorReady = true
        }
    }

    private fun resolveDefaultLocale(): Locale {
        val ctx = context
        if (ctx != null) {
            val config = ctx.resources.configuration
            val loc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val locales = config.locales
                if (!locales.isEmpty) locales[0] else null
            } else {
                @Suppress("DEPRECATION")
                config.locale
            }
            if (loc != null) return loc
        }
        return Locale.getDefault()
    }

    private fun resolveLocale(): Locale {
        return runCatching {
            val lang = pendingLang?.takeIf { LANGUAGE_REGEX.matches(it) }
            val country = pendingCountry?.takeIf { COUNTRY_REGEX.matches(it) }
            if (lang != null) {
                Locale.Builder().setLanguage(lang).apply {
                    if (country != null) setRegion(country)
                }.build()
            } else {
                resolveDefaultLocale()
            }
        }.getOrElse { resolveDefaultLocale() }
    }

    private fun captureLocale(countryArg: String?, langArg: String?) {
        val country = countryArg?.trim()?.takeIf { it.isNotBlank() }
        val lang = langArg?.trim()?.takeIf { it.isNotBlank() }
        synchronized(initLock) {
            var changed = false
            if (country != null && country != pendingCountry) {
                pendingCountry = country
                changed = true
            }
            if (lang != null && lang != pendingLang) {
                pendingLang = lang
                changed = true
            }
            if (changed && extractorReady) {
                val ctx = context?.applicationContext
                if (ctx != null) {
                    FingerprintStore.updateLocale(ctx, pendingLang, pendingCountry)
                    val ok = runCatching {
                        val locale = resolveLocale()
                        val countryCode = (pendingCountry ?: locale.country).ifBlank { DEFAULT_COUNTRY_CODE }
                        NewPipe.init(
                            PulsrDownloader(ctx),
                            Localization.fromLocale(locale),
                            ContentCountry(countryCode),
                        )
                    }.isSuccess
                    if (!ok) {
                        Log.w(TAG, "Failed to re-initialize NewPipe with new locale, marking extractor unready")
                        extractorReady = false
                    }
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isAvailable" -> result.success(true)
                "isWifiConnected" -> {
                    runOffMainThread(result, requireExtractorReady = false) { isWifiConnected() }
                }
                "ensurePoTokenReady" -> {
                    runOffMainThread(result, requireExtractorReady = false) {
                        val appContext = context?.applicationContext
                        if (appContext == null) {
                            false
                        } else {
                            PoTokenManager.init(appContext)
                            PoTokenManager.ensureReadySync()
                        }
                    }
                }
                "invalidatePoToken" -> {
                    runOffMainThread(result, requireExtractorReady = false) {
                        PoTokenManager.invalidate()
                        true
                    }
                }
                "getPlayerPoToken" -> {
                    val videoId = call.argument<String>("videoId")?.trim()
                    if (videoId.isNullOrEmpty() || !VIDEO_ID.matches(videoId)) {
                        result.success(null)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        val appContext = context?.applicationContext
                        if (appContext != null) PoTokenManager.init(appContext)
                        PoTokenManager.poTokenForSync(videoId)
                    }
                }
                "isVpnConnected" -> {
                    runOffMainThread(result, requireExtractorReady = false) {
                        val ctx = context?.applicationContext
                        if (ctx != null) CellularFailoverHelper.isVpnActive(ctx) else false
                    }
                }
                "updateClientCapabilities" -> {
                    val json = call.argument<String>("json") ?: ""
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(false)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        ClientCapabilityMatrix.applyRemoteCapabilities(json, ctx)
                        true
                    }
                }
                "getClientCapabilitiesState" -> {
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(null)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        ClientCapabilityMatrix.remoteState(ctx)
                    }
                }
                "setClientVersion" -> {
                    val version = call.argument<String>("clientVersion")?.trim()
                    if (version.isNullOrEmpty() || !CLIENT_VERSION_REGEX.matches(version)) {
                        result.success(false)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        ClientCapabilityMatrix.setWebMusicClientVersion(version)
                        true
                    }
                }
                "clearNetworkCaches" -> {
                    runOffMainThread(result, requireExtractorReady = false) {
                        YtmHttpClient.TtlDnsCache.instance.clear()
                        RateLimiter.shared.resetAfterNetworkChange()
                        PlayerJavaScript.clearCaches()
                        try {
                            val ctx = context?.applicationContext
                            if (ctx != null) {
                                PoTokenManager.invalidate()
                                PoTokenManager.preWarm(ctx)
                            }
                        } catch (_: Throwable) {}
                        true
                    }
                }
                "preWarm" -> {
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(true)
                        return
                    }
                    // Non-blocking background warm-up of JavaScript player and PoToken generator
                    runOffMainThread(result, requireExtractorReady = false) {
                        ensureExtractorReady()
                        ClientCapabilityMatrix.init(ctx)
                        executor.execute { runCatching { PlayerJavaScript.warmUp() } }
                        PoTokenManager.preWarm(ctx)
                        true
                    }
                }
                "resetIdentities" -> {
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(true)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        PoTokenManager.invalidate()
                        FingerprintStore.resetFingerprint(ctx)
                        true
                    }
                }
                "getLimitedMode" -> {
                    runOffMainThread(result, requireExtractorReady = false) { PoTokenManager.isLimitedMode }
                }
                "getPoTokenState" -> {
                    runOffMainThread(result, requireExtractorReady = false) {
                        mapOf(
                            "isReady" to PoTokenManager.isReady,
                            "isExpired" to PoTokenManager.isExpired(),
                            "isExpiringSoon" to PoTokenManager.isExpiringSoon(),
                            "visitorData" to PoTokenManager.visitorData,
                            "streamingPoToken" to PoTokenManager.streamingPoToken,
                            "webViewBroken" to PoTokenManager.webViewBroken,
                            "isLimitedMode" to PoTokenManager.isLimitedMode,
                        )
                    }
                }
                "getAccountPoToken" -> {
                    val dataSyncId = call.argument<String>("dataSyncId")?.trim()
                    if (dataSyncId.isNullOrEmpty()) {
                        result.error("YTM_INVALID_ARGUMENT", "dataSyncId is required", null)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        PoTokenManager.setDataSyncId(dataSyncId)
                        mapOf(
                            "poToken" to PoTokenManager.accountPoTokenForSync(dataSyncId),
                            "visitorData" to PoTokenManager.sessionVisitorData.ifEmpty { PoTokenManager.visitorData },
                        )
                    }
                }
                "setDataSyncId" -> {
                    val dataSyncId = call.argument<String>("dataSyncId")?.trim()
                    if (dataSyncId.isNullOrEmpty()) {
                        result.success(false)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        val appContext = context?.applicationContext
                        if (appContext != null) PoTokenManager.init(appContext)
                        PoTokenManager.setDataSyncId(dataSyncId)
                        true
                    }
                }
                "search" -> {
                    val query = call.argument<String>("query")?.trim()
                    if (query.isNullOrEmpty()) {
                        result.error("YTM_INVALID_ARGUMENT", "query is required", null)
                        return
                    }
                    val country = call.argument<String>("country")
                    val lang = call.argument<String>("lang")
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
                    runOffMainThread(result, requireExtractorReady = true) {
                        captureLocale(country, lang)
                        search(query, limit)
                    }
                }
                "searchContinuation" -> {
                    val token = call.argument<String>("continuation")?.trim()
                    if (token.isNullOrEmpty()) {
                        result.error("YTM_INVALID_ARGUMENT", "continuation is required", null)
                        return
                    }
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
                    runOffMainThread(result, requireExtractorReady = false) { searchContinuation(token, limit) }
                }
                "trending" -> {
                    val country = call.argument<String>("country")
                    val lang = call.argument<String>("lang")
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
                    runOffMainThread(result, requireExtractorReady = false) {
                        captureLocale(country, lang)
                        trending(limit)
                    }
                }
                "getCharts" -> {
                    val country = call.argument<String>("country")
                    val lang = call.argument<String>("lang")
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
                    runOffMainThread(result, requireExtractorReady = false) {
                        captureLocale(country, lang)
                        browseMusicSection("FEmusic_charts", limit)
                    }
                }
                "getMoods" -> {
                    val country = call.argument<String>("country")
                    val lang = call.argument<String>("lang")
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_SEARCH_LIMIT, MAX_SEARCH_LIMIT)
                    runOffMainThread(result, requireExtractorReady = false) {
                        captureLocale(country, lang)
                        browseMusicSection("FEmusic_moods_and_genres", limit)
                    }
                }
                "getPlaylist" -> {
                    val url = call.argument<String>("url")?.trim()
                    if (url.isNullOrEmpty()) {
                        result.error("YTM_INVALID_ARGUMENT", "url is required", null)
                        return
                    }
                    val limit = sanitizeLimit(call.argument<Int>("limit"), DEFAULT_PLAYLIST_LIMIT, MAX_PLAYLIST_LIMIT)
                    runOffMainThread(result, requireExtractorReady = true) { getPlaylist(url, limit) }
                }
                "getCookies" -> {
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(null)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        val cookieStore = YtmCookieStore.getInstance(ctx)
                        val cookies = cookieStore.readFromCookieManager()
                        if (cookies.isNullOrBlank()) cookieStore.getMergedCookieHeader() else cookies
                    }
                }
                "setCookies" -> {
                    val cookies = call.argument<String>("cookies")
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(true)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        YtmCookieStore.getInstance(ctx).setCookies(cookies ?: "")
                        true
                    }
                }
                "clearCookies" -> {
                    val ctx = context?.applicationContext
                    if (ctx == null) {
                        result.success(true)
                        return
                    }
                    runOffMainThread(result, requireExtractorReady = false) {
                        YtmCookieStore.getInstance(ctx).clear()
                        PoTokenManager.init(ctx)
                        PoTokenManager.clearSession()
                        true
                    }
                }
                "resolveStream" -> {
                    val videoId = call.argument<String>("videoId")?.trim()
                    if (videoId.isNullOrEmpty() || !VIDEO_ID.matches(videoId)) {
                        result.error("YTM_INVALID_ARGUMENT", "videoId is not a valid YouTube id", null)
                        return
                    }
                    val quality = call.argument<String>("quality")?.trim() ?: "high"
                    runOffMainThread(result, requireExtractorReady = true) { resolveStreamWithFallback(videoId, quality) }
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled exception in onMethodCall: ${t.message}", t)
            result.error("EXTRACTOR_ERROR", t.message, null)
        }
    }

    private fun sanitizeLimit(limit: Int?, default: Int, max: Int): Int {
        return (limit ?: default).coerceIn(1, max)
    }

    private fun isWifiConnected(): Boolean {
        val ctx = context?.applicationContext ?: return false
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork
            val activeCaps = if (activeNetwork != null) cm.getNetworkCapabilities(activeNetwork) else null
            if (activeCaps != null && (activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    activeCaps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))) {
                return true
            }
            // If activeNetwork has TRANSPORT_VPN, query all physical networks
            @Suppress("DEPRECATION")
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                    return true
                }
            }
            false
        } else {
            @Suppress("DEPRECATION")
            val netInfo = cm.activeNetworkInfo ?: return false
            @Suppress("DEPRECATION")
            netInfo.type == ConnectivityManager.TYPE_WIFI ||
                netInfo.type == ConnectivityManager.TYPE_ETHERNET
        }
    }

    private fun runOffMainThread(
        result: MethodChannel.Result,
        requireExtractorReady: Boolean = true,
        work: () -> Any?,
    ) {
        if (executor.isShutdown || executor.isTerminated) {
            result.error("YTM_SHUTDOWN", "YTM extractor is shutting down", null)
            return
        }
        try {
            executor.execute {
                try {
                    if (requireExtractorReady) {
                        ensureExtractorReady()
                    }
                    val value = work()
                    mainHandler.post {
                        try {
                            result.success(value)
                        } catch (t: Throwable) {
                            Log.e(TAG, "Failed to encode MethodChannel result: ${t.message}", t)
                            runCatching {
                                result.error(
                                    "YTM_ENCODE_ERROR",
                                    "Native result could not be encoded: ${t.message}",
                                    mapOf("type" to (value?.javaClass?.name ?: "null")),
                                )
                            }
                        }
                    }
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
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            result.error("YTM_SHUTDOWN", "YTM extractor is shutting down", null)
        }
    }

    private fun errorCodeFor(e: Throwable): String {
        var current: Throwable? = e
        var depth = 0
        var isRateLimited = false
        var isBotChallenge = false
        var isIpBlocked = false
        var isProxyAuth = false
        var isNetwork = false
        var isAuth = false
        var isLiveUnsupported = false
        var isEmptyResult = false
        var sawContentNotAvailable = false
        var sawExtractionException = false
        var innertubeSignal: String? = null

        while (current != null && depth < 10) {
            if (current is InnertubeClient.InnertubeException) {
                innertubeSignal = current.signal.code
                break
            }
            if (current is RateLimitedException) {
                isRateLimited = true
                break
            }
            if (current is ReCaptchaException) {
                isBotChallenge = true
                break
            }
            if (current is ContentNotAvailableException) {
                sawContentNotAvailable = true
            }
            if (current is ExtractionException) {
                sawExtractionException = true
            }

            val msg = (current.message ?: "").lowercase(Locale.ROOT)
            if (msg.contains("no trending tracks found") || msg.contains("no tracks found")) {
                isEmptyResult = true
            }
            if (msg.contains("live streams are not supported") || msg.contains("live stream unsupported")) {
                isLiveUnsupported = true
                break
            }
            if (msg.contains("too many requests") || msg.contains("rate_limit") || msg.contains("rate limit") ||
                HTTP_429_REGEX.containsMatchIn(msg)
            ) {
                isRateLimited = true
                break
            }
            if (HTTP_407_REGEX.containsMatchIn(msg) || msg.contains("proxy authentication")) {
                isProxyAuth = true
                break
            }
            if (HTTP_403_REGEX.containsMatchIn(msg) || msg.contains("forbidden") || msg.contains("ip_block") || msg.contains("access denied")) {
                isIpBlocked = true
            }
            if (msg.contains("not a bot") || msg.contains("login_required") || msg.contains("recaptcha") ||
                msg.contains("bot_block") || msg.contains("botguard") || msg.contains("sign in to confirm") ||
                msg.contains("confirm you're") || msg.contains("confirm you’re") || msg.contains("automated queries") ||
                msg.contains("unusual traffic") || msg.contains("device check") || msg.contains("verify you're human")
            ) {
                isBotChallenge = true
                break
            }
            if (msg.contains("sign in") || msg.contains("unauthenticated") || msg.contains("login required")) {
                isAuth = true
            }
            if (isNetworkFailure(current)) {
                isNetwork = true
            }

            current = current.cause
            depth++
        }

        if (innertubeSignal != null) return innertubeSignal
        if (isLiveUnsupported) return "LIVE_UNSUPPORTED"
        if (isRateLimited) return "RATE_LIMITED"
        if (isBotChallenge) return "BOT_CHALLENGE"
        if (isProxyAuth) return "PROXY_AUTH_REQUIRED"
        if (isIpBlocked) return "IP_BLOCKED"
        if (isAuth) return "SIGN_IN_REQUIRED"
        if (isNetwork) return "YTM_NETWORK"
        if (sawContentNotAvailable) return "VIDEO_GONE"
        if (isEmptyResult) return "YTM_EMPTY"
        if (sawExtractionException) return "CLIENT_DEPRECATED"

        return "EXTRACTOR_ERROR"
    }

    private fun isNetworkFailure(e: Throwable): Boolean {
        var cause: Throwable? = e
        var depth = 0
        while (cause != null && depth < 5) {
            when (cause) {
                is java.net.UnknownHostException,
                is java.net.SocketException,
                is java.io.InterruptedIOException,
                is javax.net.ssl.SSLException,
                -> return true
            }
            cause = cause.cause
            depth++
        }
        return false
    }

    /**
     * Canonical track representation matching Dart YtmTrack.fromChannel expectations.
     * Backwards-compatible aliases (uploader, thumbnailUrl, duration) are retained.
     */
    private fun buildTrackMap(
        videoId: String,
        title: String,
        artist: String,
        durationMs: Long,
        artworkUrl: String?,
        url: String? = null,
        isLive: Boolean = false,
    ): Map<String, Any?> {
        val safeArtist = artist.ifBlank { "Unknown Artist" }
        val safeTitle = title.ifBlank { "Unknown Title" }
        val safeDurationMs = durationMs.coerceAtLeast(0L)
        val safeUrl = url ?: "https://music.youtube.com/watch?v=$videoId"
        val safeArtwork = artworkUrl?.takeIf { it.isNotBlank() }

        return mapOf(
            // Canonical schema matching Dart YtmTrack.fromChannel
            "videoId" to videoId,
            "title" to safeTitle,
            "artist" to safeArtist,
            "durationMs" to safeDurationMs,
            "artworkUrl" to safeArtwork,
            "url" to safeUrl,
            "isLive" to isLive,

            // Backwards-compatibility aliases
            "uploader" to safeArtist,
            "thumbnailUrl" to safeArtwork,
            "duration" to (safeDurationMs / 1000L),
            "viewCount" to -1L,
            "shortDescription" to null,
        )
    }

    /**
     * Search with multi-tier fallback:
     * 1. Primary: NewPipe MUSIC_SONGS filter.
     * 2. If results < limit: fallback to NewPipe general search.
     * 3. If results < limit: supplement with native InnerTube search.
     * Propagates bot challenges / rate limits if no tracks could be extracted.
     */
    private fun search(query: String, limit: Int): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenVideoIds = mutableSetOf<String>()
        var primaryError: Throwable? = null
        var innerTubeError: Throwable? = null

        // Supplements 2 and 3 are each a full extra network round trip run
        // sequentially behind the primary. They only buy more rows, never a
        // usable answer, so only pay for them when the primary came up short
        // of a full page: ten songs already fills the search list, and a
        // near-full primary used to be followed by two more hops that often
        // added nothing. Callers asking for a smaller page keep the old
        // behaviour (minOf == their limit).
        val minAcceptable = minOf(limit, 10)

        // 1. Primary: MUSIC_SONGS
        try {
            val songsExtractor = ServiceList.YouTube.getSearchExtractor(
                query,
                listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS),
                "",
            )
            songsExtractor.fetchPage()
            val songItems = (SearchInfo.getInfo(songsExtractor).relatedItems ?: emptyList()).asSequence().filterIsInstance<StreamInfoItem>()
            for (map in streamItemsToMaps(songItems, limit)) {
                val vid = map["videoId"] as? String
                if (vid != null && seenVideoIds.add(vid)) {
                    results.add(map)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Primary songs search failed: ${e.message}")
            primaryError = e
        }

        // 2. Fallback / supplement: General search if not throttled
        if (results.size < minAcceptable) {
            if (primaryError !is ReCaptchaException && primaryError !is RateLimitedException) {
                try {
                    val generalExtractor = ServiceList.YouTube.getSearchExtractor(query)
                    generalExtractor.fetchPage()
                    val items = (SearchInfo.getInfo(generalExtractor).relatedItems ?: emptyList()).asSequence().filterIsInstance<StreamInfoItem>()
                    for (map in streamItemsToMaps(items, limit - results.size)) {
                        val vid = map["videoId"] as? String
                        if (vid != null && seenVideoIds.add(vid)) {
                            results.add(map)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "General search fallback failed: ${e.message}")
                }
            }
        }

        // 3. Fallback / supplement: Native InnerTube search
        if (results.size < minAcceptable) {
            val ctx = context?.applicationContext
            if (ctx != null) {
                try {
                    YtmCookieStore.getInstance(ctx).readFromCookieManager()
                    val client = InnertubeClient(ctx)
                    val json = client.requestSearch(query)
                    val innerTracks = parseInnertubeTracksFromJson(json, limit - results.size)
                    for (map in innerTracks) {
                        val vid = map["videoId"] as? String
                        if (vid != null && seenVideoIds.add(vid)) {
                            results.add(map)
                        }
                    }
                } catch (e: Throwable) {
                    Log.w(TAG, "InnerTube search fallback failed: ${e.message}")
                    innerTubeError = e
                }
            }
        }

        // Propagate genuine errors when no results could be extracted
        if (results.isEmpty()) {
            val errToRethrow = primaryError ?: innerTubeError
            if (errToRethrow != null) {
                throw errToRethrow
            }
        }

        return results.take(limit)
    }

    private fun trending(limit: Int): List<Map<String, Any?>> {
        val ctx = context?.applicationContext
            ?: throw ExtractionException("No context available for trending")
        YtmCookieStore.getInstance(ctx).readFromCookieManager()
        val client = InnertubeClient(ctx)
        var lastError: Throwable? = null
        val browseIds = listOf("FEmusic_charts", "FEmusic_moods_and_genres")
        for (bid in browseIds) {
            try {
                val json = client.requestBrowse(bid)
                val tracks = parseInnertubeTracksFromJson(json, limit)
                if (tracks.isNotEmpty()) {
                    Log.i(TAG, "trending: $bid returned ${tracks.size} tracks")
                    return tracks.take(limit)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "trending browse $bid failed: ${e.message}")
                lastError = e
            }
        }

        // Fail with real error rather than serving unrelated non-music kiosk videos
        throw lastError ?: ExtractionException("No trending tracks found in YouTube Music sections")
    }

    private fun searchContinuation(token: String, limit: Int): List<Map<String, Any?>> {
        val ctx = context?.applicationContext
            ?: throw ExtractionException("No context available for searchContinuation")
        YtmCookieStore.getInstance(ctx).readFromCookieManager()
        val client = InnertubeClient(ctx)
        val json = client.requestContinuation(token)
        val errorObj = json.optJSONObject("error")
        if (errorObj != null) {
            val errMsg = errorObj.optString("message").takeIf { it.isNotBlank() }
                ?: "InnerTube continuation error ${errorObj.optInt("code")}"
            throw ExtractionException(errMsg)
        }
        return parseInnertubeTracksFromJson(json, limit).take(limit)
    }

    private fun browseMusicSection(browseId: String, limit: Int): List<Map<String, Any?>> {
        val ctx = context?.applicationContext
            ?: throw ExtractionException("No context available for browseMusicSection")
        YtmCookieStore.getInstance(ctx).readFromCookieManager()
        val client = InnertubeClient(ctx)
        val json = client.requestBrowse(browseId)
        val errorObj = json.optJSONObject("error")
        if (errorObj != null) {
            val errMsg = errorObj.optString("message").takeIf { it.isNotBlank() }
                ?: "InnerTube browse error ${errorObj.optInt("code")}"
            throw ExtractionException(errMsg)
        }
        return parseInnertubeTracksFromJson(json, limit).take(limit)
    }

    private fun maskId(id: String): String {
        return if (id.length <= 8) "***" else id.take(4) + "..." + id.takeLast(4)
    }

    /**
     * Playlist extraction with continuation pagination up to [limit].
     * Tries InnerTube first (authenticated cookies, private playlists, mixes),
     * then falls back to NewPipe for public playlists.
     */
    private fun getPlaylist(urlOrId: String, limit: Int): Map<String, Any?> {
        val trimmed = urlOrId.trim()
        var lastError: Throwable? = null

        // 1. Try InnertubeClient first
        try {
            val result = getPlaylistViaInnertube(trimmed, limit)
            val tracks = result["tracks"] as? List<*>
            // If request succeeded (even with 0 tracks, if explicitly empty), return result
            if (result.isNotEmpty() && (tracks != null)) {
                return result
            }
        } catch (e: Throwable) {
            Log.w(TAG, "getPlaylist: Innertube failed for ${maskId(trimmed)}: ${e.message}")
            lastError = e
        }

        // 2. Fallback to NewPipe for public playlists
        try {
            val listParam = runCatching {
                val uri = Uri.parse(trimmed)
                val list = uri.getQueryParameter("list")
                if (!list.isNullOrBlank()) list else {
                    val lastSegment = uri.lastPathSegment
                    if (lastSegment != null && lastSegment != "playlist") lastSegment else null
                }
            }.getOrNull()

            val cleanId = (listParam ?: trimmed).removePrefix("VL")
            val rawUrl = if (cleanId.startsWith("http://") || cleanId.startsWith("https://")) {
                cleanId
            } else {
                "https://www.youtube.com/playlist?list=$cleanId"
            }
            val url = rawUrl.replace("music.youtube.com", "www.youtube.com")

            val extractor = ServiceList.YouTube.getPlaylistExtractor(url)
            extractor.fetchPage()
            val playlistInfo = PlaylistInfo.getInfo(extractor)

            val allItems = mutableListOf<StreamInfoItem>()
            allItems.addAll((playlistInfo.relatedItems ?: emptyList()).filterIsInstance<StreamInfoItem>())

            var nextPage: Page? = playlistInfo.nextPage
            var pageCount = 0
            while (nextPage != null && allItems.size < limit && pageCount < MAX_PAGES) {
                try {
                    val pageResult = extractor.getPage(nextPage)
                    val newItems = (pageResult.items ?: emptyList()).filterIsInstance<StreamInfoItem>()
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
            val isTruncated = nextPage != null
            return mapOf(
                "title" to playlistInfo.name,
                "uploader" to (playlistInfo.uploaderName ?: ""),
                "thumbnailUrl" to bestArtwork(playlistInfo.thumbnails),
                "tracks" to tracks,
                "isTruncated" to isTruncated,
            )
        } catch (e: Throwable) {
            Log.w(TAG, "getPlaylist: NewPipe fallback failed for ${maskId(trimmed)}: ${e.message}")
            if (lastError != null) {
                lastError.addSuppressed(e)
            } else {
                lastError = e
            }
        }

        // Propagate real failure to Dart instead of masking with dummy empty playlist
        throw lastError ?: ExtractionException("Playlist extraction failed")
    }

    /**
     * Fetches playlists via [InnertubeClient] browse with fallback browse IDs.
     * Uses the authenticated cookie store when available so account-scoped playlists work.
     */
    private fun getPlaylistViaInnertube(urlOrId: String, limit: Int): Map<String, Any?> {
        val ctx = context?.applicationContext
            ?: throw ExtractionException("No context for InnertubeClient")

        YtmCookieStore.getInstance(ctx).readFromCookieManager()
        val client = InnertubeClient(ctx)
        val trimmed = urlOrId.trim()

        val isLikedSongs = trimmed == "LM" || trimmed == "VLLM" || trimmed == "LL" ||
            trimmed == "FEmusic_liked_videos" || trimmed == "FEmusic_liked_tracks" ||
            trimmed == "VLSE" ||
            trimmed.contains("playlist?list=LM") ||
            trimmed.contains("playlist?list=VLLM") ||
            trimmed.contains("playlist?list=LL")

        val browseIds: List<String>
        if (isLikedSongs) {
            browseIds = listOf("VLLM", "FEmusic_liked_videos", "FEmusic_liked_tracks", "LM")
        } else {
            var cleanId = trimmed
            if (cleanId.contains("list=")) {
                val uri = Uri.parse(cleanId)
                cleanId = uri.getQueryParameter("list") ?: cleanId
            }
            cleanId = cleanId.removePrefix("VL")
            browseIds = listOf("VL$cleanId", cleanId)
        }

        var lastError: Throwable? = null
        var anyBrowseSucceeded = false
        var emptyPlaylistFallback: Map<String, Any?>? = null

        for (bId in browseIds) {
            try {
                val json = client.requestBrowse(bId)
                val errorObj = json.optJSONObject("error")
                if (errorObj != null) {
                    val errMsg = errorObj.optString("message").takeIf { it.isNotBlank() }
                        ?: "InnerTube error ${errorObj.optInt("code")}"
                    throw ExtractionException(errMsg)
                }
                val alerts = json.optJSONArray("alerts")
                if (alerts != null) {
                    for (i in 0 until alerts.length()) {
                        val alert = alerts.optJSONObject(i)?.optJSONObject("alertRenderer")
                        val alertType = alert?.optString("type")
                        if (alertType.equals("ERROR", ignoreCase = true)) {
                            val alertText = extractTextRuns(alert?.optJSONObject("text")?.optJSONArray("runs"))
                            throw ExtractionException(alertText?.takeIf { it.isNotBlank() } ?: "InnerTube alert error")
                        }
                    }
                }
                anyBrowseSucceeded = true
                val tracks = parsePlaylistTracksFromJson(json, limit)
                val (extractedTitle, extractedUploader, extractedThumb) = extractPlaylistHeader(
                    json,
                    if (isLikedSongs) "Liked Music" else "YouTube Playlist"
                )

                if (tracks.isNotEmpty()) {
                    val allTracks = tracks.toMutableList()
                    val seenIds = tracks.mapNotNull { it["videoId"] as? String }.toMutableSet()
                    var currentJson = json
                    var pageCount = 0
                    var hasContinuation = false

                    while (allTracks.size < limit && pageCount < MAX_PAGES) {
                        val token = extractPlaylistContinuationToken(currentJson)
                        if (token == null) {
                            hasContinuation = false
                            break
                        }
                        hasContinuation = true
                        try {
                            val contJson = client.requestContinuation(token)
                            val contTracks = parsePlaylistTracksFromJson(contJson, limit - allTracks.size)
                            if (contTracks.isEmpty()) {
                                hasContinuation = false
                                break
                            }
                            for (t in contTracks) {
                                val vid = t["videoId"] as? String
                                if (vid == null || seenIds.add(vid)) {
                                    allTracks.add(t)
                                }
                            }
                            currentJson = contJson
                            pageCount++
                        } catch (e: Exception) {
                            Log.w(TAG, "Playlist continuation failed: ${e.message}")
                            break
                        }
                    }

                    // Re-check if continuation remains after loop
                    if (hasContinuation) {
                        hasContinuation = extractPlaylistContinuationToken(currentJson) != null
                    }

                    return mapOf(
                        "title" to extractedTitle,
                        "uploader" to extractedUploader,
                        "thumbnailUrl" to (extractedThumb ?: allTracks.firstOrNull()?.get("artworkUrl")),
                        "tracks" to allTracks.take(limit),
                        "isTruncated" to hasContinuation,
                    )
                } else if (emptyPlaylistFallback == null) {
                    // Valid browse response, but 0 tracks found (empty playlist)
                    emptyPlaylistFallback = mapOf(
                        "title" to extractedTitle,
                        "uploader" to extractedUploader,
                        "thumbnailUrl" to extractedThumb,
                        "tracks" to emptyList<Map<String, Any?>>(),
                        "isTruncated" to false,
                    )
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Playlist InnertubeClient browse ${maskId(bId)} failed: ${e.message}")
                lastError = e
            }
        }

        // If at least one browse succeeded but returned 0 tracks, return the empty playlist
        if (anyBrowseSucceeded && emptyPlaylistFallback != null) {
            return emptyPlaylistFallback
        }

        throw lastError ?: ExtractionException("No tracks found in playlist browse response")
    }

    private fun extractPlaylistHeader(json: JSONObject, defaultTitle: String): Triple<String, String, String?> {
        fun findHeaderNode(node: Any?, depth: Int = 0): JSONObject? {
            if (depth > MAX_TRAVERSAL_DEPTH) return null
            return when (node) {
                is JSONObject -> {
                    val header = node.optJSONObject("musicDetailHeaderRenderer")
                        ?: node.optJSONObject("musicEditablePlaylistDetailHeaderRenderer")?.optJSONObject("header")?.optJSONObject("musicDetailHeaderRenderer")
                        ?: node.optJSONObject("musicResponsiveHeaderRenderer")
                    if (header != null) return header
                    val keys = node.keys()
                    while (keys.hasNext()) {
                        val found = findHeaderNode(node.opt(keys.next()), depth + 1)
                        if (found != null) return found
                    }
                    null
                }
                is JSONArray -> {
                    for (i in 0 until node.length()) {
                        val found = findHeaderNode(node.opt(i), depth + 1)
                        if (found != null) return found
                    }
                    null
                }
                else -> null
            }
        }

        val detailHeader = (json.optJSONObject("header")?.let { findHeaderNode(it) })
            ?: findHeaderNode(json)
            ?: return Triple(defaultTitle, "", null)

        val title = extractTextRuns(detailHeader.optJSONObject("title")?.optJSONArray("runs")) ?: defaultTitle

        var uploader = ""
        val subtitleRuns = detailHeader.optJSONObject("subtitle")?.optJSONArray("runs")
            ?: detailHeader.optJSONObject("straplineTextOne")?.optJSONArray("runs")
        val playlistMetaRegex = Regex("^\\d+\\s*(songs?|tracks?|minutes?|hours?|mins?|hrs?)$", RegexOption.IGNORE_CASE)
        val genericLabelRegex = Regex("^(playlist|album|ep|single)$", RegexOption.IGNORE_CASE)

        if (subtitleRuns != null) {
            for (i in 0 until subtitleRuns.length()) {
                val fullText = subtitleRuns.optJSONObject(i)?.optString("text")?.trim() ?: continue
                if (fullText.isEmpty()) continue
                val segments = fullText.split("•", "·").map { it.trim() }.filter { it.isNotEmpty() }
                for (t in segments) {
                    if (!playlistMetaRegex.matches(t) &&
                        !genericLabelRegex.matches(t) &&
                        !MEDIA_TYPE_LABELS.contains(t.lowercase(Locale.ROOT))
                    ) {
                        uploader = t
                        break
                    }
                }
                if (uploader.isNotEmpty()) break
            }
        }

        val thumbObj = detailHeader.optJSONObject("thumbnail")?.optJSONObject("musicThumbnailRenderer")?.optJSONObject("thumbnail")
            ?: detailHeader.optJSONObject("thumbnail")?.optJSONObject("croppedSquareThumbnailRenderer")?.optJSONObject("thumbnail")
        val thumbUrl = extractThumbnailUrl(thumbObj)

        return Triple(title, uploader, thumbUrl)
    }

    private fun extractTextRuns(runs: JSONArray?): String? {
        if (runs == null || runs.length() == 0) return null
        val sb = StringBuilder()
        for (i in 0 until runs.length()) {
            val text = runs.optJSONObject(i)?.optString("text")
            if (!text.isNullOrEmpty()) {
                sb.append(text)
            }
        }
        return sb.toString().trim().takeIf { it.isNotEmpty() }
    }

    private fun extractThumbnailUrl(thumbnailsObj: JSONObject?): String? {
        val arr = thumbnailsObj?.optJSONArray("thumbnails") ?: return null
        var bestUrl: String? = null
        var maxPixels = -1
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            val url = item.optString("url").trim()
            if (url.isEmpty()) continue
            val w = item.optInt("width", 0)
            val h = item.optInt("height", 0)
            val pixels = w * h
            if (pixels > maxPixels || bestUrl == null) {
                maxPixels = pixels
                bestUrl = url
            }
        }
        return bestUrl?.let { upgradeToHighRes(it) }
    }

    private fun isRendererLive(renderer: JSONObject): Boolean {
        val badges = renderer.optJSONArray("badges")
        if (badges != null) {
            for (i in 0 until badges.length()) {
                val badgeObj = badges.optJSONObject(i)?.optJSONObject("musicInlineBadgeRenderer")
                    ?: badges.optJSONObject(i)?.optJSONObject("liveBadgeRenderer")
                val style = badgeObj?.optString("icon") ?: badgeObj?.optString("style") ?: ""
                val label = badgeObj?.optJSONObject("accessibilityData")?.optJSONObject("accessibilityData")?.optString("label") ?: ""
                if (style.contains("LIVE", ignoreCase = true) ||
                    label.contains("live", ignoreCase = true) ||
                    label.contains("directo", ignoreCase = true) ||
                    label.contains("vivo", ignoreCase = true) ||
                    label.contains("مباشر", ignoreCase = true)
                ) {
                    return true
                }
            }
        }
        val overlays = renderer.optJSONObject("thumbnailOverlay")
            ?.optJSONObject("musicItemThumbnailOverlayRenderer")
            ?.optJSONObject("content")
        if (overlays != null) {
            val overlayBadge = overlays.optJSONObject("musicPlayButtonRenderer")
                ?.optJSONObject("playNavigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optJSONObject("watchEndpointMusicSupportedConfigs")
                ?.optJSONObject("watchEndpointMusicConfig")
                ?.optString("musicVideoType")
            if (overlayBadge?.contains("LIVE", ignoreCase = true) == true) {
                return true
            }
        }
        val fixedCols = renderer.optJSONArray("fixedColumns")
        if (fixedCols != null && fixedCols.length() > 0) {
            val durText = extractTextRuns(
                fixedCols.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
            )
            if (durText != null && (durText.equals("LIVE", ignoreCase = true) ||
                    durText.equals("DIRECTO", ignoreCase = true) ||
                    durText.equals("EN VIVO", ignoreCase = true) ||
                    durText.equals("مباشر", ignoreCase = true))
            ) {
                return true
            }
        }
        return false
    }

    /**
     * Parses track maps from an InnerTube browse JSON response.
     * Handles musicPlaylistShelfRenderer, musicShelfRenderer, and musicResponsiveListItemRenderer containers.
     */
    private fun parseInnertubeTracksFromJson(
        json: JSONObject,
        limit: Int,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenVideoIds = mutableSetOf<String>()

        fun parseRenderer(renderer: JSONObject) {
            val videoId = renderer.optString("videoId").takeIf { it.length == 11 } ?: run {
                renderer.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("watchEndpoint")
                    ?.optString("videoId")
                    ?.takeIf { it.length == 11 }
            } ?: return

            if (isRendererLive(renderer)) return
            if (!seenVideoIds.add(videoId)) return

            val flexCols = renderer.optJSONArray("flexColumns")
            val title = extractTextRuns(
                flexCols?.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
            ) ?: "Unknown Title"

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
                            !MEDIA_TYPE_LABELS.contains(text.lowercase(Locale.ROOT))
                        ) {
                            artist = text
                            break
                        }
                    }
                }
            }

            var durationSec = 0
            val fixedCols = renderer.optJSONArray("fixedColumns")
            if (fixedCols != null && fixedCols.length() > 0) {
                val durText = extractTextRuns(
                    fixedCols.optJSONObject(0)
                        ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                        ?.optJSONObject("text")
                        ?.optJSONArray("runs")
                )
                if (durText != null) {
                    val parts = normalizeDigits(durText).split(":").mapNotNull { it.toIntOrNull() }
                    durationSec = when (parts.size) {
                        2 -> parts[0] * 60 + parts[1]
                        3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
                        else -> 0
                    }
                }
            }

            val thumbObj = renderer
                .optJSONObject("thumbnail")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail")
            val thumbUrl = extractThumbnailUrl(thumbObj)

            results.add(
                buildTrackMap(
                    videoId = videoId,
                    title = title,
                    artist = artist,
                    durationMs = durationSec * 1000L,
                    artworkUrl = thumbUrl,
                    url = "https://music.youtube.com/watch?v=$videoId",
                    isLive = false,
                )
            )
        }

        fun parseTwoRowRenderer(renderer: JSONObject) {
            val videoId = renderer.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.length == 11 }
                ?: renderer.optJSONObject("title")
                    ?.optJSONArray("runs")
                    ?.optJSONObject(0)
                    ?.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("watchEndpoint")
                    ?.optString("videoId")
                    ?.takeIf { it.length == 11 }
                ?: return

            if (isRendererLive(renderer)) return
            if (!seenVideoIds.add(videoId)) return

            val title = extractTextRuns(renderer.optJSONObject("title")?.optJSONArray("runs")) ?: "Unknown Title"

            var artist = "Unknown Artist"
            val subtitleRuns = renderer.optJSONObject("subtitle")?.optJSONArray("runs")
            if (subtitleRuns != null && subtitleRuns.length() > 0) {
                for (i in 0 until subtitleRuns.length()) {
                    val text = subtitleRuns.optJSONObject(i)?.optString("text")?.trim() ?: continue
                    if (text.isNotEmpty() && text != "•" && text != "·" &&
                        !MEDIA_TYPE_LABELS.contains(text.lowercase(Locale.ROOT))
                    ) {
                        artist = text
                        break
                    }
                }
            }

            val thumbObj = renderer.optJSONObject("thumbnailRenderer")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail")
                ?: renderer.optJSONObject("thumbnail")
                    ?.optJSONObject("musicThumbnailRenderer")
                    ?.optJSONObject("thumbnail")
            val thumbUrl = extractThumbnailUrl(thumbObj)

            results.add(
                buildTrackMap(
                    videoId = videoId,
                    title = title,
                    artist = artist,
                    durationMs = 0L,
                    artworkUrl = thumbUrl,
                    url = "https://music.youtube.com/watch?v=$videoId",
                    isLive = false,
                )
            )
        }

        fun traverseJson(node: Any?, depth: Int = 0) {
            if (depth > MAX_TRAVERSAL_DEPTH || results.size >= limit) return
            when (node) {
                is JSONObject -> {
                    val shelfKeys = listOf("musicPlaylistShelfRenderer", "musicShelfRenderer", "musicCarouselShelfRenderer")
                    for (key in shelfKeys) {
                        if (node.has(key)) {
                            val shelfObj = node.optJSONObject(key)
                            val contents = shelfObj?.optJSONArray("contents")
                                ?: shelfObj?.optJSONArray("continuationItems")
                            if (contents != null) {
                                for (i in 0 until contents.length()) {
                                    if (results.size >= limit) return
                                    traverseJson(contents.opt(i), depth + 1)
                                }
                            }
                            return
                        }
                    }
                    if (node.has("musicResponsiveListItemRenderer")) {
                        parseRenderer(node.getJSONObject("musicResponsiveListItemRenderer"))
                        return
                    }
                    if (node.has("musicTwoRowItemRenderer")) {
                        parseTwoRowRenderer(node.getJSONObject("musicTwoRowItemRenderer"))
                        return
                    }
                    val keys = node.keys()
                    while (keys.hasNext()) {
                        if (results.size >= limit) return
                        traverseJson(node.opt(keys.next()), depth + 1)
                    }
                }
                is JSONArray -> {
                    for (i in 0 until node.length()) {
                        if (results.size >= limit) return
                        traverseJson(node.opt(i), depth + 1)
                    }
                }
            }
        }

        traverseJson(json)
        return results
    }

    /**
     * Parses tracks strictly belonging to a playlist shelf.
     * Scopes extraction to musicPlaylistShelfContinuation or musicPlaylistShelfRenderer.
     * Returns emptyList() if no playlist shelf is present to avoid unrelated recommendations.
     */
    private fun parsePlaylistTracksFromJson(
        json: JSONObject,
        limit: Int,
    ): List<Map<String, Any?>> {
        val contContents = json.optJSONObject("continuationContents")
        val playlistCont = contContents?.optJSONObject("musicPlaylistShelfContinuation")
            ?: contContents?.optJSONObject("musicShelfContinuation")
        if (playlistCont != null) {
            return parseShelfListItems(playlistCont, limit)
        }

        fun findShelf(node: Any?, depth: Int = 0): JSONObject? {
            if (depth > MAX_TRAVERSAL_DEPTH) return null
            return when (node) {
                is JSONObject -> {
                    if (node.has("musicPlaylistShelfRenderer")) {
                        node.optJSONObject("musicPlaylistShelfRenderer")
                    } else if (node.has("musicShelfRenderer")) {
                        node.optJSONObject("musicShelfRenderer")
                    } else {
                        val keys = node.keys()
                        while (keys.hasNext()) {
                            val res = findShelf(node.opt(keys.next()), depth + 1)
                            if (res != null) return res
                        }
                        null
                    }
                }
                is JSONArray -> {
                    for (i in 0 until node.length()) {
                        val res = findShelf(node.opt(i), depth + 1)
                        if (res != null) return res
                    }
                    null
                }
                else -> null
            }
        }

        val shelf = findShelf(json)
        if (shelf != null) {
            return parseShelfListItems(shelf, limit)
        }

        return emptyList()
    }

    private fun parseShelfListItems(
        shelf: JSONObject,
        limit: Int,
    ): List<Map<String, Any?>> {
        val contents = shelf.optJSONArray("contents")
            ?: shelf.optJSONArray("continuationItems")
            ?: return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        val seenVideoIds = mutableSetOf<String>()
        for (i in 0 until contents.length()) {
            if (results.size >= limit) break
            val item = contents.optJSONObject(i) ?: continue
            val responsive = item.optJSONObject("musicResponsiveListItemRenderer")
            val track = if (responsive != null) {
                parseSingleResponsiveRenderer(responsive, seenVideoIds)
            } else {
                val twoRow = item.optJSONObject("musicTwoRowItemRenderer")
                if (twoRow != null) parseSingleTwoRowRenderer(twoRow, seenVideoIds) else null
            }
            if (track != null) {
                results.add(track)
            }
        }
        return results
    }

    private fun parseSingleResponsiveRenderer(
        renderer: JSONObject,
        seenVideoIds: MutableSet<String>,
    ): Map<String, Any?>? {
        val videoId = renderer.optString("videoId").takeIf { it.length == 11 } ?: run {
            renderer.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.length == 11 }
        } ?: return null

        if (isRendererLive(renderer)) return null
        if (!seenVideoIds.add(videoId)) return null

        val flexCols = renderer.optJSONArray("flexColumns")
        val title = extractTextRuns(
            flexCols?.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.optJSONArray("runs")
        ) ?: "Unknown Title"

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
                        !MEDIA_TYPE_LABELS.contains(text.lowercase(Locale.ROOT))
                    ) {
                        artist = text
                        break
                    }
                }
            }
        }

        var durationSec = 0
        val fixedCols = renderer.optJSONArray("fixedColumns")
        if (fixedCols != null && fixedCols.length() > 0) {
            val durText = extractTextRuns(
                fixedCols.optJSONObject(0)
                    ?.optJSONObject("musicResponsiveListItemFixedColumnRenderer")
                    ?.optJSONObject("text")
                    ?.optJSONArray("runs")
            )
            if (durText != null) {
                val parts = normalizeDigits(durText).split(":").mapNotNull { it.toIntOrNull() }
                durationSec = when (parts.size) {
                    2 -> parts[0] * 60 + parts[1]
                    3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
                    else -> 0
                }
            }
        }

        val thumbObj = renderer
            .optJSONObject("thumbnail")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
        val thumbUrl = extractThumbnailUrl(thumbObj)

        return buildTrackMap(
            videoId = videoId,
            title = title,
            artist = artist,
            durationMs = durationSec * 1000L,
            artworkUrl = thumbUrl,
            url = "https://music.youtube.com/watch?v=$videoId",
            isLive = false,
        )
    }

    private fun parseSingleTwoRowRenderer(
        renderer: JSONObject,
        seenVideoIds: MutableSet<String>,
    ): Map<String, Any?>? {
        val videoId = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("watchEndpoint")
            ?.optString("videoId")
            ?.takeIf { it.length == 11 }
            ?: renderer.optJSONObject("title")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.length == 11 }
            ?: return null

        if (isRendererLive(renderer)) return null
        if (!seenVideoIds.add(videoId)) return null

        val title = extractTextRuns(renderer.optJSONObject("title")?.optJSONArray("runs")) ?: "Unknown Title"

        var artist = "Unknown Artist"
        val subtitleRuns = renderer.optJSONObject("subtitle")?.optJSONArray("runs")
        if (subtitleRuns != null && subtitleRuns.length() > 0) {
            for (i in 0 until subtitleRuns.length()) {
                val text = subtitleRuns.optJSONObject(i)?.optString("text")?.trim() ?: continue
                if (text.isNotEmpty() && text != "•" && text != "·" &&
                    !MEDIA_TYPE_LABELS.contains(text.lowercase(Locale.ROOT))
                ) {
                    artist = text
                    break
                }
            }
        }

        val thumbObj = renderer.optJSONObject("thumbnailRenderer")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?: renderer.optJSONObject("thumbnail")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail")
        val thumbUrl = extractThumbnailUrl(thumbObj)

        return buildTrackMap(
            videoId = videoId,
            title = title,
            artist = artist,
            durationMs = 0L,
            artworkUrl = thumbUrl,
            url = "https://music.youtube.com/watch?v=$videoId",
            isLive = false,
        )
    }

    /** Extracts a playlist continuation token across all InnerTube shelf and section representations. */
    private fun extractPlaylistContinuationToken(json: JSONObject): String? {
        val contContents = json.optJSONObject("continuationContents")
        if (contContents != null) {
            val playlistCont = contContents.optJSONObject("musicPlaylistShelfContinuation")
                ?: contContents.optJSONObject("musicShelfContinuation")
            if (playlistCont != null) {
                val token = extractTokenFromShelfContinuations(playlistCont)
                if (token != null) return token
            }
            val sectionCont = contContents.optJSONObject("sectionListContinuation")
            if (sectionCont != null) {
                val token = extractTokenFromSectionContinuation(sectionCont)
                if (token != null) return token
            }
        }

        fun findShelf(node: Any?, depth: Int = 0): JSONObject? {
            if (depth > MAX_TRAVERSAL_DEPTH) return null
            return when (node) {
                is JSONObject -> {
                    if (node.has("musicPlaylistShelfRenderer")) {
                        node.optJSONObject("musicPlaylistShelfRenderer")
                    } else if (node.has("musicShelfRenderer")) {
                        node.optJSONObject("musicShelfRenderer")
                    } else {
                        val keys = node.keys()
                        while (keys.hasNext()) {
                            val res = findShelf(node.opt(keys.next()), depth + 1)
                            if (res != null) return res
                        }
                        null
                    }
                }
                is JSONArray -> {
                    for (i in 0 until node.length()) {
                        val res = findShelf(node.opt(i), depth + 1)
                        if (res != null) return res
                    }
                    null
                }
                else -> null
            }
        }

        val shelf = findShelf(json)
        if (shelf != null) {
            val token = extractTokenFromShelfContinuations(shelf)
            if (token != null) return token
        }

        // Generic fallback search for continuationItemRenderer
        return findContinuationTokenGeneric(json)
    }

    private fun extractTokenFromShelfContinuations(shelf: JSONObject): String? {
        val continuations = shelf.optJSONArray("continuations")
            ?: shelf.optJSONArray("continuationItems")
            ?: return null
        for (i in 0 until continuations.length()) {
            val c = continuations.optJSONObject(i) ?: continue
            val cir = c.optJSONObject("continuationItemRenderer") ?: c
            val nextData = cir.optJSONObject("nextContinuationData")
            val token = nextData?.optString("continuation")?.takeIf { it.isNotEmpty() }
            if (token != null) return token
            val endpoint = cir.optJSONObject("continuationEndpoint")
            val cmdToken = endpoint?.optJSONObject("continuationCommand")?.optString("token")?.takeIf { it.isNotEmpty() }
            if (cmdToken != null) return cmdToken
            val cmd = cir.optJSONObject("continuationCommand")
            val directToken = cmd?.optString("token")?.takeIf { it.isNotEmpty() }
            if (directToken != null) return directToken
        }
        return null
    }

    private fun extractTokenFromSectionContinuation(section: JSONObject): String? {
        val contents = section.optJSONArray("contents") ?: return null
        for (i in 0 until contents.length()) {
            val item = contents.optJSONObject(i) ?: continue
            val cir = item.optJSONObject("continuationItemRenderer") ?: continue
            val token = cir.optJSONObject("continuationEndpoint")
                ?.optJSONObject("continuationCommand")
                ?.optString("token")
                ?.takeIf { it.isNotEmpty() }
            if (token != null) return token
        }
        return null
    }

    private fun findContinuationTokenGeneric(node: Any?, depth: Int = 0): String? {
        if (depth > MAX_TRAVERSAL_DEPTH) return null
        return when (node) {
            is JSONObject -> {
                val cir = node.optJSONObject("continuationItemRenderer")
                if (cir != null) {
                    val cmd = cir.optJSONObject("continuationEndpoint")?.optJSONObject("continuationCommand")
                        ?: cir.optJSONObject("continuationCommand")
                    val token = cmd?.optString("token")?.takeIf { it.isNotEmpty() }
                    if (token != null) return token
                }
                val keys = node.keys()
                while (keys.hasNext()) {
                    val token = findContinuationTokenGeneric(node.opt(keys.next()), depth + 1)
                    if (token != null) return token
                }
                null
            }
            is JSONArray -> {
                for (i in 0 until node.length()) {
                    val token = findContinuationTokenGeneric(node.opt(i), depth + 1)
                    if (token != null) return token
                }
                null
            }
            else -> null
        }
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
                return client.resolvePlayerStream(videoId, quality)
            } catch (e: Throwable) {
                innertubeError = e
                Log.w(TAG, "Native Innertube stream extraction failed for $videoId: ${e.message}. Attempting NewPipeExtractor fallback...")
            }
        }

        // 2. Fallback: NewPipeExtractor
        try {
            return resolveStreamNewPipe(videoId, quality)
        } catch (newPipeError: Throwable) {
            Log.w(TAG, "NewPipeExtractor fallback also failed for $videoId: ${newPipeError.message}")
            val primary = innertubeError ?: newPipeError
            if (primary !== newPipeError) primary.addSuppressed(newPipeError)
            throw primary
        }
    }

    private fun resolveStreamNewPipe(videoId: String, quality: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        if (info.streamType == StreamType.LIVE_STREAM || info.streamType == StreamType.AUDIO_LIVE_STREAM) {
            throw ExtractionException("Live streams are not supported")
        }

        val playable = info.audioStreams.filter {
            it.isUrl && !it.content.isNullOrEmpty()
        }
        if (playable.isEmpty()) {
            throw ExtractionException("No playable audio stream available in NewPipe extractor")
        }

        val selected = when (quality.lowercase(Locale.ROOT)) {
            "low" -> playable.minByOrNull { bitrateToKbps(it.averageBitrate) }
            "medium" -> playable.minByOrNull { kotlin.math.abs(bitrateToKbps(it.averageBitrate) - 128) }
            else -> {
                val maxBitrate = playable.maxOfOrNull { bitrateToKbps(it.averageBitrate) } ?: 0
                val highStreams = playable.filter { bitrateToKbps(it.averageBitrate) >= (maxBitrate - 16) }
                highStreams.firstOrNull { it.format == MediaFormat.M4A } ?: playable.maxByOrNull { bitrateToKbps(it.averageBitrate) }
            }
        } ?: playable.first()

        val url = selected.content.orEmpty()
        if (url.isBlank()) {
            throw ExtractionException("Selected audio stream has no URL")
        }

        val ctx = context?.applicationContext
        val cookieHeader = if (ctx != null) YtmCookieStore.getInstance(ctx).getMergedCookieHeader() else null
        val headers = mutableMapOf<String, String>(
            "User-Agent" to PulsrDownloader.USER_AGENT
        )
        if (!cookieHeader.isNullOrBlank()) {
            headers["Cookie"] = cookieHeader
        }

        val expirySeconds = urlExpiryEpochSeconds(url) ?: (System.currentTimeMillis() / 1000L + DEFAULT_EXPIRY_SECONDS)

        return mapOf(
            "videoId" to videoId,
            "url" to url,
            "mimeType" to (selected.format?.mimeType ?: "audio/mp4"),
            "container" to (selected.format?.suffix ?: "m4a"),
            "bitrateKbps" to bitrateToKbps(selected.averageBitrate),
            "durationMs" to info.duration.coerceAtLeast(0L) * 1000L,
            "title" to info.name,
            "artist" to (info.uploaderName ?: "Unknown Artist"),
            "artworkUrl" to bestArtwork(info.thumbnails),
            "userAgent" to PulsrDownloader.USER_AGENT,
            "headers" to headers,
            "expiresAt" to expirySeconds,
        )
    }

    private fun bitrateToKbps(raw: Int): Int = when {
        raw <= 0 -> 0
        raw < 1000 -> raw // Already in kbps (e.g. 48, 64, 128, 160, 256)
        raw < 10_000 -> raw // Ambiguous low range edge cases
        else -> raw / 1000 // In bits/sec (e.g. 48000, 128000, 256000)
    }

    private fun urlExpiryEpochSeconds(url: String?): Long? {
        if (url.isNullOrEmpty()) return null
        return runCatching { Uri.parse(url).getQueryParameter("expire")?.toLongOrNull() }.getOrNull()
    }

    private fun streamItemsToMaps(items: Sequence<StreamInfoItem>, limit: Int): List<Map<String, Any?>> {
        val seen = mutableSetOf<String>()
        return items
            .filterNot { it.streamType == StreamType.LIVE_STREAM || it.streamType == StreamType.AUDIO_LIVE_STREAM }
            .mapNotNull { item ->
                val videoId = videoIdOf(item.url) ?: return@mapNotNull null
                if (!seen.add(videoId)) return@mapNotNull null
                buildTrackMap(
                    videoId = videoId,
                    title = item.name,
                    artist = item.uploaderName ?: "Unknown Artist",
                    durationMs = item.duration.coerceAtLeast(0L) * 1000L,
                    artworkUrl = bestArtwork(item.thumbnails),
                    url = item.url,
                    isLive = false,
                )
            }
            .take(limit)
            .toList()
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
            ?: images.lastOrNull()?.url

        return rawUrl?.let { upgradeToHighRes(it) }
    }

    private fun upgradeToHighRes(url: String): String {
        var upgraded = url
        if (upgraded.contains("googleusercontent.com") || upgraded.contains("ggpht.com")) {
            upgraded = upgraded.replace(Regex("=w\\d+-h\\d+[^?]*"), "=s1200")
            upgraded = upgraded.replace(Regex("=s\\d+[^?]*"), "=s1200")
        }
        return upgraded
    }

    /**
     * Cleans up plugin resources on engine detachment.
     * Note: Pulsr is a single Flutter engine application; global teardown is safe here.
     */
    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
        EgressSignals.onEgressChanged = null
        ProxyPool.setOnPathChangeListener { }
        synchronized(initLock) {
            extractorReady = false
            pendingCountry = null
            pendingLang = null
        }
        try {
            executor.shutdownNow()
        } catch (_: Exception) {}
        runCatching { PoTokenManager.invalidate() }
        runCatching { InnertubeClient.shutdown() }
    }
}
