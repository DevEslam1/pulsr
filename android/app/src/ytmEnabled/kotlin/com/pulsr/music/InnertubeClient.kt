package com.pulsr.music

import android.content.Context
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.GZIPInputStream

/**
 * Hardened Innertube API Client with Multi-Client Context Support.
 *
 * Implements robust Innertube `/player`, `/search`, `/browse`, and `/next` requests with:
 * - Multi-client priority fallback (ANDROID_MUSIC -> IOS_MUSIC -> WEB_REMIX -> WEB_EMBEDDED_PLAYER -> MWEB -> ANDROID_TESTSUITE)
 * - Tailored headers per client type (avoiding origin mismatch 400 Precondition Check Failed errors)
 * - Rate limiting (RateLimiter)
 * - Cipher stream URL extraction
 * - Timestamped SAPISIDHASH authorization header generation for authenticated web sessions
 * - Automatic HTTP retry with exponential backoff on 429 / 5xx
 * - Classification of transient, auth, bot-block, and permanent errors
 */
internal class InnertubeClient(
    private val context: Context,
    private val cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context),
    private val rateLimiter: RateLimiter = RateLimiter.shared,
) {
    enum class ClientType(
        val clientName: String,
        val clientVersion: String,
        val clientNameId: String,
        val userAgent: String,
        val isWeb: Boolean,
        val endpointHost: String,
    ) {
        ANDROID_VR(
            "ANDROID_VR",
            "1.63.27",
            "28",
            "com.google.android.apps.youtube.vr.oculus/1.63.27 (Linux; U; Android 12; en_US; Quest 2) gzip",
            false,
            "https://www.youtube.com",
        ),
        ANDROID_CREATOR(
            "ANDROID_CREATOR",
            "24.45.100",
            "62",
            "com.google.android.apps.youtube.creator/24.45.100 (Linux; U; Android 13; en_US) gzip",
            false,
            "https://www.youtube.com",
        ),
        TVHTML5_SIMPLY_EMBEDDED_PLAYER(
            "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
            "2.0",
            "85",
            "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36",
            true,
            "https://www.youtube.com",
        ),
        ANDROID_MUSIC(
            "ANDROID_MUSIC",
            "8.32.50",
            "21",
            "com.google.android.apps.youtube.music/8.32.50 (Linux; U; Android 14; en_US) gzip",
            false,
            "https://music.youtube.com",
        ),
        IOS_MUSIC(
            "IOS_MUSIC",
            "8.32.1",
            "26",
            "com.google.ios.youtubemusic/8.32.1 (iPhone15,3; U; CPU iOS 18_0 like Mac OS X; en_US)",
            false,
            "https://music.youtube.com",
        ),
        WEB_REMIX(
            "WEB_REMIX",
            "1.20260825.01.00",
            "67",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
            true,
            "https://music.youtube.com",
        ),
        WEB_EMBEDDED_PLAYER(
            "WEB_EMBEDDED_PLAYER",
            "1.20260825.01.00",
            "56",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
            true,
            "https://www.youtube.com",
        ),
        MWEB(
            "MWEB",
            "2.20260825.01.00",
            "65",
            "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36",
            true,
            "https://m.youtube.com",
        ),
        ANDROID_TESTSUITE(
            "ANDROID_TESTSUITE",
            "1.9",
            "30",
            "com.google.android.youtube/1.9 (Linux; U; Android 9; gzip)",
            false,
            "https://www.youtube.com",
        );

        val effectiveClientVersion: String
            get() = when (this) {
                WEB_REMIX, WEB_EMBEDDED_PLAYER -> {
                    val dateStr = SimpleDateFormat("yyyyMMdd", Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }.format(Date())
                    "1.$dateStr.01.00"
                }
                MWEB -> {
                    val dateStr = SimpleDateFormat("yyyyMMdd", Locale.US).apply {
                        timeZone = TimeZone.getTimeZone("UTC")
                    }.format(Date())
                    "2.$dateStr.01.00"
                }
                else -> clientVersion
            }
    }

    enum class ErrorCategory {
        TRANSIENT,
        AUTH,
        BOT_BLOCK,
        PERMANENT,
    }

    class InnertubeException(
        val category: ErrorCategory,
        message: String,
        cause: Throwable? = null,
    ) : Exception(message, cause)

    /**
     * Resolves audio formats for [videoId] using a multi-client priority fallback chain:
     * 1. ANDROID_VR (unthrottled, no PoToken/bot-block challenge required)
     * 2. ANDROID_CREATOR
     * 3. TVHTML5_SIMPLY_EMBEDDED_PLAYER
     * 4. WEB_EMBEDDED_PLAYER
     * 5. ANDROID_MUSIC
     * 6. IOS_MUSIC
     * 7. WEB_REMIX + poToken + session cookies
     * 8. MWEB
     * 9. ANDROID_TESTSUITE
     */
    fun resolvePlayerStream(videoId: String, quality: String = "high"): Map<String, Any?> {
        val clientChain = listOf(
            ClientType.ANDROID_VR,
            ClientType.ANDROID_CREATOR,
            ClientType.ANDROID_MUSIC,
            ClientType.IOS_MUSIC,
            ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            ClientType.WEB_REMIX,
            ClientType.WEB_EMBEDDED_PLAYER,
            ClientType.MWEB,
            ClientType.ANDROID_TESTSUITE,
        )

        // Authenticated cold-start: the account datasyncId may be unknown (e.g. the Dart primary
        // path was skipped). One WEB_REMIX /player call still returns responseContext.datasyncId
        // even on LOGIN_REQUIRED — harvest it so the WEB_REMIX attempt below can present an
        // account-bound poToken instead of a guest token YouTube rejects.
        if (cookieStore.isSessionValid() && PoTokenManager.dataSyncId.isEmpty()) {
            try {
                requestPlayer(videoId, ClientType.WEB_REMIX)
            } catch (t: Throwable) {
                Log.w(TAG, "Datasync bootstrap call failed for $videoId: ${t.message}")
            }
        }

        var lastException: Throwable? = null
        var sawBotGate = false

        for (client in clientChain) {
            try {
                Log.d(TAG, "Attempting player resolution for $videoId using client: ${client.name}")
                val playerJson = requestPlayer(videoId, client)

                val playability = playerJson.optJSONObject("playabilityStatus")
                val status = playability?.optString("status") ?: ""

                if (status.equals("LOGIN_REQUIRED", ignoreCase = true) ||
                    status.equals("UNPLAYABLE", ignoreCase = true) ||
                    status.contains("BOT", ignoreCase = true)) {
                    val reason = playability?.optString("reason") ?: status
                    Log.w(TAG, "Client ${client.name} returned status $status ($reason), trying next client")
                    // UNPLAYABLE means this video is restricted/unavailable, not that
                    // we are bot-gated — only LOGIN_REQUIRED/BOT prove an attestation gate.
                    if (!status.equals("UNPLAYABLE", ignoreCase = true)) sawBotGate = true
                    continue
                }

                val streamingData = playerJson.optJSONObject("streamingData") ?: continue
                val adaptiveFormats = streamingData.optJSONArray("adaptiveFormats") ?: JSONArray()

                val audioFormats = mutableListOf<Pair<JSONObject, String>>()
                for (i in 0 until adaptiveFormats.length()) {
                    val format = adaptiveFormats.getJSONObject(i)
                    val mime = format.optString("mimeType")
                    val url = extractUrlFromFormat(format)
                    if (mime.startsWith("audio/") && !url.isNullOrEmpty()) {
                        audioFormats.add(format to url)
                    }
                }

                if (audioFormats.isEmpty()) {
                    Log.w(TAG, "Client ${client.name} provided no direct audio formats, trying next")
                    continue
                }

                // Prefer M4A / AAC for jaudiotagger compatibility
                val m4aFormats = audioFormats.filter { it.first.optString("mimeType").contains("mp4") }
                val pool = if (m4aFormats.isNotEmpty()) m4aFormats else audioFormats

                val selectedPair = when (quality.lowercase()) {
                    "low" -> pool.minByOrNull { it.first.optInt("bitrate", 0) }
                    "medium" -> pool.minByOrNull { kotlin.math.abs(it.first.optInt("bitrate", 128000) - 128000) }
                    else -> pool.maxByOrNull { it.first.optInt("bitrate", 0) }
                } ?: pool.first()

                val selected = selectedPair.first
                val selectedUrl = selectedPair.second
                val selectedMime = selected.optString("mimeType", "audio/mp4")
                val selectedBitrate = selected.optInt("bitrate", 128000)
                val durationMs = selected.optLong("approxDurationMs", 0L)
                val videoDetails = playerJson.optJSONObject("videoDetails")

                val title = videoDetails?.optString("title") ?: ""
                val author = videoDetails?.optString("author") ?: ""

                Log.i(TAG, "Successfully resolved $videoId via ${client.name} (bitrate: $selectedBitrate)")
                return mapOf(
                    "videoId" to videoId,
                    "url" to selectedUrl,
                    "mimeType" to selectedMime.split(";").first().trim(),
                    "container" to if (selectedMime.contains("mp4")) "m4a" else "webm",
                    "bitrateKbps" to (selectedBitrate / 1000),
                    "durationMs" to durationMs,
                    "title" to title,
                    "artist" to author,
                    "artworkUrl" to null,
                    "userAgent" to client.userAgent,
                )
            } catch (t: Throwable) {
                Log.w(TAG, "Failed resolving with ${client.name}: ${t.message}")
                lastException = t
            }
        }

        // Only a real bot/auth gate justifies touching attestation state.
        // Evict just the minted tokens so they re-mint; a full invalidation
        // here would force a slow BotGuard WebView re-run every failing cycle
        // and hammer YouTube with retries while already flagged.
        if (sawBotGate) {
            PoTokenManager.evictMintedTokens()
            throw InnertubeException(
                ErrorCategory.BOT_BLOCK,
                "All Innertube client fallback resolutions failed for video $videoId",
                lastException,
            )
        }
        throw InnertubeException(
            ErrorCategory.TRANSIENT,
            "All Innertube client fallback resolutions failed for video $videoId",
            lastException,
        )
    }

    private fun extractUrlFromFormat(format: JSONObject): String? {
        val directUrl = format.optString("url")
        if (directUrl.isNotEmpty()) return directUrl

        val cipher = format.optString("signatureCipher").ifEmpty { format.optString("cipher") }
        if (cipher.isNotEmpty()) {
            return runCatching {
                val pairs = cipher.split("&")
                for (pair in pairs) {
                    val parts = pair.split("=", limit = 2)
                    if (parts.size == 2 && parts[0] == "url") {
                        return@runCatching URLDecoder.decode(parts[1], "UTF-8")
                    }
                }
                null
            }.getOrNull()
        }
        return null
    }

    fun requestPlayer(videoId: String, clientType: ClientType): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/player?prettyPrint=false&key=$API_KEY"
        val payload = buildPlayerBody(videoId, clientType)
        return postWithRetry(endpoint, payload, clientType)
    }

    fun requestBrowse(browseId: String, clientType: ClientType = ClientType.WEB_REMIX): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/browse?prettyPrint=false&key=$API_KEY"
        val payload = JSONObject().apply {
            put("context", buildClientContext(clientType))
            put("browseId", browseId)
        }
        return postWithRetry(endpoint, payload, clientType)
    }

    fun requestContinuation(token: String, clientType: ClientType = ClientType.WEB_REMIX): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/browse?prettyPrint=false&key=$API_KEY"
        val payload = JSONObject().apply {
            put("context", buildClientContext(clientType))
            put("continuation", token)
        }
        return postWithRetry(endpoint, payload, clientType)
    }

    fun requestSearch(query: String, params: String? = null, clientType: ClientType = ClientType.WEB_REMIX): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/search?prettyPrint=false&key=$API_KEY"
        val payload = JSONObject().apply {
            put("context", buildClientContext(clientType))
            put("query", query)
            if (!params.isNullOrEmpty()) {
                put("params", params)
            }
        }
        return postWithRetry(endpoint, payload, clientType)
    }

    private fun postWithRetry(
        urlStr: String,
        body: JSONObject,
        clientType: ClientType,
        maxRetries: Int = 3,
    ): JSONObject {
        var lastError: Exception? = null

        for (attempt in 0 until maxRetries) {
            rateLimiter.acquirePermit()

            var connection: HttpURLConnection? = null
            try {
                val proxy = ProxyManager.getProxy(urlStr)
                val url = URL(urlStr)
                val rawConn = if (proxy != null) url.openConnection(proxy) else url.openConnection()
                connection = (rawConn as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15_000 + (attempt * 5_000)
                    readTimeout = 20_000 + (attempt * 5_000)
                    doOutput = true
                    instanceFollowRedirects = true
                }

                // Headers tailored per client type
                connection.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                connection.setRequestProperty("User-Agent", clientType.userAgent)
                connection.setRequestProperty("X-Goog-Api-Key", API_KEY)
                connection.setRequestProperty("x-youtube-client-name", clientType.clientNameId)
                connection.setRequestProperty("x-youtube-client-version", clientType.clientVersion)

                if (clientType.isWeb) {
                    val origin = clientType.endpointHost
                    connection.setRequestProperty("Origin", origin)
                    connection.setRequestProperty("Referer", "$origin/")
                    connection.setRequestProperty("x-origin", origin)
                    connection.setRequestProperty("x-goog-authuser", "0")
                }

                // Only attach session cookies and SAPISIDHASH for Web client requests
                if (clientType.isWeb) {
                    val cookieHeader = cookieStore.getMergedCookieHeader()
                    if (!cookieHeader.isNullOrEmpty()) {
                        connection.setRequestProperty("Cookie", cookieHeader)

                        val sapisid = cookieStore.getCookie("SAPISID")
                        val sapisid3p = cookieStore.getCookie("__Secure-3PAPISID")
                        val sapisid1p = cookieStore.getCookie("__Secure-1PAPISID")

                        val timestamp = Instant.now().epochSecond
                        val (authType, token) = when {
                            !sapisid.isNullOrEmpty() -> "SAPISIDHASH" to sapisid
                            !sapisid3p.isNullOrEmpty() -> "SAPISID3PHASH" to sapisid3p
                            !sapisid1p.isNullOrEmpty() -> "SAPISID1PHASH" to sapisid1p
                            else -> null to null
                        }

                        if (authType != null && token != null) {
                            val toHash = "$timestamp $token ${clientType.endpointHost}"
                            val hash = sha1Hex(toHash)
                            connection.setRequestProperty("Authorization", "$authType ${timestamp}_$hash")
                        }
                    }
                }

                val bodyBytes = body.toString().toByteArray(StandardCharsets.UTF_8)
                connection.outputStream.use { it.write(bodyBytes) }

                val code = connection.responseCode

                if (clientType.isWeb) {
                    val setCookies = connection.headerFields.entries
                        .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
                        .flatMap { it.value }
                    if (setCookies.isNotEmpty()) {
                        cookieStore.ingestSetCookieHeaders(setCookies)
                    }
                }

                if (code == 429) {
                    val backoff = rateLimiter.onRateLimited()
                    Log.w(TAG, "Rate limited (429) on attempt $attempt. Backing off for ${backoff}ms")
                    Thread.sleep(backoff)
                    continue
                }

                if (code in 500..599) {
                    Log.w(TAG, "Server error ($code) on attempt $attempt. Retrying...")
                    Thread.sleep((1000L shl attempt) + (0..500).random())
                    continue
                }

                val stream: InputStream? = if (code in 200..299) connection.inputStream else connection.errorStream
                val responseStr = stream?.let { raw ->
                    val isGzip = connection.contentEncoding.equals("gzip", ignoreCase = true)
                    val input = if (isGzip) GZIPInputStream(raw) else raw
                    input.bufferedReader(StandardCharsets.UTF_8).use { it.readText() }
                } ?: ""

                if (code !in 200..299) {
                    Log.w(TAG, "Innertube (${clientType.name}) returned non-200 ($code): $responseStr")
                    if (responseStr.contains("LOGIN_REQUIRED") || responseStr.contains("invalid SAPISIDHASH")) {
                        throw InnertubeException(ErrorCategory.AUTH, "Authentication failed: $responseStr")
                    }
                    if (code == 404) {
                        throw InnertubeException(ErrorCategory.PERMANENT, "Resource not found (404)")
                    }
                    throw InnertubeException(ErrorCategory.TRANSIENT, "HTTP error $code: $responseStr")
                }

                rateLimiter.onSuccess()
                val parsed = JSONObject(responseStr)
                harvestSessionState(parsed, clientType)
                return parsed
            } catch (e: InnertubeException) {
                if (e.category == ErrorCategory.AUTH || e.category == ErrorCategory.PERMANENT) {
                    throw e
                }
                lastError = e
            } catch (e: IOException) {
                lastError = e
                Log.w(TAG, "Network error on attempt $attempt for ${clientType.name}: ${e.message}")
            } catch (e: Exception) {
                lastError = e
                Log.e(TAG, "Unexpected error in Innertube post: ${e.message}", e)
            } finally {
                connection?.disconnect()
            }
        }

        throw InnertubeException(ErrorCategory.TRANSIENT, "Innertube request failed after $maxRetries attempts for ${clientType.name}", lastError)
    }

    /**
     * Opportunistically harvests the account [PoTokenManager.dataSyncId] and session
     * [PoTokenManager.sessionVisitorData] from an authenticated web response's `responseContext`.
     * Gated on an authenticated web request so guest visitorData never pollutes session state.
     */
    private fun harvestSessionState(json: JSONObject, clientType: ClientType) {
        if (!clientType.isWeb || !cookieStore.isSessionValid()) return
        val responseContext = json.optJSONObject("responseContext") ?: return
        val dataSyncId = responseContext
            .optJSONObject("mainAppWebResponseContext")
            ?.optString("datasyncId")
        if (!dataSyncId.isNullOrBlank()) {
            PoTokenManager.setDataSyncId(dataSyncId)
        }
        val visitorData = responseContext.optString("visitorData")
        if (visitorData.isNotBlank()) {
            PoTokenManager.setSessionVisitorData(visitorData)
        }
    }

    private fun buildPlayerBody(videoId: String, clientType: ClientType): JSONObject {
        val root = JSONObject()
        root.put("context", buildClientContext(clientType, videoId))
        root.put("videoId", videoId)
        root.put("racyCheckOk", true)
        root.put("contentCheckOk", true)

        if (clientType == ClientType.WEB_EMBEDDED_PLAYER || clientType == ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER) {
            root.put("thirdParty", JSONObject().put("embedUrl", "https://www.youtube.com/watch?v=$videoId"))
        }

        val playbackContext = JSONObject()
        val contentPlaybackContext = JSONObject().apply {
            put("html5Preference", "HTML5_PREF_WANTS")
            if (PoTokenManager.isReady) {
                val dataSyncId = PoTokenManager.dataSyncId
                val poToken = if (clientType.isWeb && cookieStore.isSessionValid() && dataSyncId.isNotEmpty()) {
                    PoTokenManager.accountPoTokenForSync(dataSyncId)
                } else {
                    PoTokenManager.poTokenForSync(videoId)
                }
                if (poToken.isNotEmpty()) {
                    put("poToken", poToken)
                }
            }
        }
        playbackContext.put("contentPlaybackContext", contentPlaybackContext)
        root.put("playbackContext", playbackContext)

        // Web clients attest via root-level serviceIntegrityDimensions as well;
        // mobile clients only read contentPlaybackContext.poToken. Sending both
        // keeps every client in the chain covered.
        if (clientType.isWeb && contentPlaybackContext.has("poToken")) {
            root.put(
                "serviceIntegrityDimensions",
                JSONObject().put("poToken", contentPlaybackContext.getString("poToken")),
            )
        }

        return root
    }

    private fun buildClientContext(clientType: ClientType, videoId: String? = null): JSONObject {
        val client = JSONObject().apply {
            put("clientName", clientType.clientName)
            put("clientVersion", clientType.effectiveClientVersion)
            put("hl", "en")
            put("gl", "US")
            // Only web clients send cookies, so only they are "authenticated": send the harvested
            // session visitorData in that case, guest visitorData otherwise.
            val authedWeb = clientType.isWeb && cookieStore.isSessionValid()
            val visitorData = if (authedWeb) {
                PoTokenManager.sessionVisitorData
            } else {
                PoTokenManager.visitorData
            }
            if (visitorData.isNotEmpty()) {
                put("visitorData", visitorData)
            }

            when (clientType) {
                ClientType.ANDROID_VR -> {
                    put("androidSdkVersion", 32)
                    put("osName", "Android")
                    put("osVersion", "12")
                    put("platform", "MOBILE")
                    put("deviceMake", "Oculus")
                    put("deviceModel", "Quest 2")
                }
                ClientType.ANDROID_CREATOR -> {
                    put("androidSdkVersion", 33)
                    put("osName", "Android")
                    put("osVersion", "13")
                    put("platform", "MOBILE")
                }
                ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER -> {
                    put("platform", "TV")
                }
                ClientType.ANDROID_MUSIC -> {
                    put("androidSdkVersion", 34)
                    put("osName", "Android")
                    put("osVersion", "14")
                    put("platform", "MOBILE")
                }
                ClientType.IOS_MUSIC -> {
                    put("deviceMake", "Apple")
                    put("deviceModel", "iPhone15,3")
                    put("osName", "iOS")
                    put("osVersion", "18.0")
                    put("platform", "MOBILE")
                }
                ClientType.ANDROID_TESTSUITE -> {
                    put("androidSdkVersion", 28)
                }
                ClientType.MWEB -> {
                    put("platform", "MOBILE")
                }
                ClientType.WEB_EMBEDDED_PLAYER -> {
                    put("platform", "DESKTOP")
                }
                ClientType.WEB_REMIX -> {
                    put("platform", "DESKTOP")
                }
            }
        }

        val contextJson = JSONObject()
        contextJson.put("client", client)

        if (clientType == ClientType.WEB_EMBEDDED_PLAYER || clientType == ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER) {
            val thirdParty = JSONObject()
            thirdParty.put("embedUrl", "https://www.youtube.com")
            contextJson.put("thirdParty", thirdParty)
        }

        if (clientType.isWeb && cookieStore.isSessionValid()) {
            val user = JSONObject()
            user.put("lockedSafetyMode", false)
            contextJson.put("user", user)
        }

        return contextJson
    }

    private fun sha1Hex(input: String): String {
        val md = MessageDigest.getInstance("SHA-1")
        val bytes = md.digest(input.toByteArray(StandardCharsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "InnertubeClient"
        private const val API_KEY = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    }
}
