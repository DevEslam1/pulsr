package com.pulsr.music

import android.content.Context
import android.net.Uri
import android.util.Log
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.net.UnknownHostException
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.GZIPInputStream

/**
 * Hardened Innertube API Client with Multi-Client Context Support and Strategy Engine.
 *
 * Implements 6-Layer Resilience:
 * - L1: Consistent Device Fingerprinting per ClientType
 * - L2: Precise 8-Signal YtmBlockSignal Parser
 * - L3: Dynamic ResolutionStrategy & Capability Matrix Fallback
 * - L4: ProxyPool, DoH, and Cellular Failover Integration
 * - L5: Adaptive Multi-Bucket Rate Limiter with Jitter and Persistence
 * - L6: Stream itag Fallback Ladder (140 -> 251 -> 139 -> 250 -> 249)
 */
internal class InnertubeClient(
    private val context: Context,
    private val cookieStore: YtmCookieStore = YtmCookieStore.getInstance(context),
    private val rateLimiter: RateLimiter = RateLimiter.shared,
    private val resolutionStrategy: ResolutionStrategy = ResolutionStrategy(context, cookieStore, PoTokenManager)
) {
    private val consecutiveBotBlocks = AtomicInteger(0)
    private val lastBotBlockTimestamp = AtomicLong(0L)
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

    class InnertubeException(
        val signal: YtmBlockSignal,
        message: String,
        val traceId: String = UUID.randomUUID().toString(),
        cause: Throwable? = null,
    ) : Exception("[$traceId] [${signal.name}] $message", cause)

    /**
     * Resolves audio stream formats for [videoId] through dynamic fallback ladder:
     * 1. Consults ResolutionStrategy for eligible client chain
     * 2. Executes parallel race for high-priority tier
     * 3. Fallback sequential check for remaining clients
     * 4. Selects optimal itag via audio itag ladder (140, 251, 139, 250, 249)
     */
    fun resolvePlayerStream(videoId: String, quality: String = "high"): Map<String, Any?> {
        val clientChain = resolutionStrategy.buildChain(
            ResolutionStrategy.Operation.STREAM_RESOLVE,
            limitedMode = PoTokenManager.isLimitedMode
        )

        // Authenticated cold-start datasyncId bootstrap if needed
        if (cookieStore.isSessionValid() && PoTokenManager.dataSyncId.isEmpty()) {
            try {
                requestPlayer(videoId, ClientType.WEB_REMIX)
            } catch (t: Throwable) {
                Log.w(TAG, "Datasync bootstrap call failed for $videoId: ${t.message}")
            }
        }

        var lastException: Throwable? = null
        var lastSignal: YtmBlockSignal = YtmBlockSignal.RateLimited
        val traceId = UUID.randomUUID().toString()

        fun attemptClient(client: ClientType): Map<String, Any?>? {
            if (Thread.currentThread().isInterrupted) return null
            try {
                Log.d(TAG, "[$traceId] Attempting player resolution for $videoId using client: ${client.name}")
                val playerJson = requestPlayer(videoId, client)
                if (Thread.currentThread().isInterrupted) return null

                val playability = playerJson.optJSONObject("playabilityStatus")
                val status = playability?.optString("status") ?: ""

                if (status.equals("LOGIN_REQUIRED", ignoreCase = true) ||
                    status.equals("UNPLAYABLE", ignoreCase = true) ||
                    status.contains("BOT", ignoreCase = true)) {
                    val parsedSignal = YtmBlockSignal.parse(200, status, playability)
                    lastSignal = parsedSignal
                    Log.w(TAG, "[$traceId] Client ${client.name} returned status $status -> $parsedSignal")
                    if ((parsedSignal == YtmBlockSignal.BotChallenge || parsedSignal == YtmBlockSignal.PoTokenInvalid) &&
                        (client == ClientType.ANDROID_MUSIC || client == ClientType.WEB_REMIX)) {
                        val now = System.currentTimeMillis()
                        val lastBlock = lastBotBlockTimestamp.getAndSet(now)
                        val count = if (now - lastBlock < 30_000L) consecutiveBotBlocks.incrementAndGet() else consecutiveBotBlocks.apply { set(1) }.get()
                        PoTokenManager.evictMintedTokens()
                        if (count >= 2) {
                            Log.w(TAG, "[$traceId] Encountered $count consecutive bot blocks. Rotating identity and clearing cookies...")
                            PoTokenManager.invalidate()
                            FingerprintStore.resetFingerprint(context)
                            YtmCookieStore.getInstance(context).clearCookies()
                            consecutiveBotBlocks.set(0)
                        } else {
                            PoTokenManager.triggerBackgroundRefresh()
                        }
                    }
                    return null
                }
                consecutiveBotBlocks.set(0)

                val streamingData = playerJson.optJSONObject("streamingData")
                val adaptiveFormats = streamingData?.optJSONArray("adaptiveFormats") ?: JSONArray()

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
                    lastSignal = YtmBlockSignal.PoTokenInvalid
                    return null
                }

                // Layer 6: Itag Ladder Ordering (140, 251, 139, 250, 249)
                val itagLadder = listOf(140, 251, 139, 250, 249)
                val selectedPair = when (quality.lowercase()) {
                    "low" -> audioFormats.minByOrNull { it.first.optInt("bitrate", 0) }
                    "medium" -> audioFormats.minByOrNull { kotlin.math.abs(it.first.optInt("bitrate", 128000) - 128000) }
                    else -> {
                        // High quality: prefer ladder itags in order, or highest bitrate
                        audioFormats.sortedWith(
                            compareBy<Pair<JSONObject, String>> { pair ->
                                val itag = pair.first.optInt("itag", 0)
                                val idx = itagLadder.indexOf(itag)
                                if (idx >= 0) idx else 99
                            }.thenByDescending { it.first.optInt("bitrate", 0) }
                        ).firstOrNull() ?: audioFormats.maxByOrNull { it.first.optInt("bitrate", 0) }
                    }
                } ?: audioFormats.first()

                val selected = selectedPair.first
                val selectedUrl = selectedPair.second
                val selectedMime = selected.optString("mimeType", "audio/mp4")
                val selectedBitrate = selected.optInt("bitrate", 128000)
                val durationMs = selected.optLong("approxDurationMs", 0L)
                val videoDetails = playerJson.optJSONObject("videoDetails")

                val title = videoDetails?.optString("title") ?: ""
                val author = videoDetails?.optString("author") ?: ""

                // Pre-stream validation check: 1-byte ranged GET (fixes C-03)
                val validateStart = System.currentTimeMillis()
                val isValid = validateStreamUrl(selectedUrl)
                YtmMetricsRegistry.record("stream.validate", System.currentTimeMillis() - validateStart, isError = !isValid)
                if (!isValid) {
                    Log.w(TAG, "[$traceId] Resolved URL for ${client.name} failed 1-byte pre-validation. Escalating ladder...")
                    return null
                }

                Log.i(TAG, "[$traceId] Successfully resolved $videoId via ${client.name} (itag: ${selected.optInt("itag")}, bitrate: $selectedBitrate)")
                YtmHttpClient.preConnect(selectedUrl)
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
                    "activeClient" to client.name,
                    "traceId" to traceId
                )
            } catch (t: Throwable) {
                Log.w(TAG, "[$traceId] Failed resolving with ${client.name}: ${t.message}")
                lastException = t
                return null
            }
        }

        val trackType = ClientWinnerStore.TRACK_TYPE_MUSIC
        val winnerStore = ClientWinnerStore.getInstance(context)

        val candidate1 = clientChain.firstOrNull()
        val candidate2 = clientChain.getOrNull(1)

        val activeFutures = java.util.concurrent.CopyOnWriteArrayList<java.util.concurrent.Future<Pair<ClientType, Map<String, Any?>?>>>()

        fun submitCandidate(client: ClientType): java.util.concurrent.Future<Pair<ClientType, Map<String, Any?>?>> {
            val future = streamResolverPool.submit(java.util.concurrent.Callable {
                val res = attemptClient(client)
                client to res
            })
            activeFutures.add(future)
            return future
        }

        if (candidate1 != null) {
            submitCandidate(candidate1)
        }

        // Task 4: Wait up to HEDGE_DELAY_MS (350 ms) for candidate 1
        val hedgeDeadline = android.os.SystemClock.elapsedRealtime() + HEDGE_DELAY_MS
        while (android.os.SystemClock.elapsedRealtime() < hedgeDeadline) {
            val done = activeFutures.firstOrNull { it.isDone }
            if (done != null) {
                try {
                    val (client, res) = done.get()
                    if (res != null) {
                        for (f in activeFutures) { if (f != done) f.cancel(true) }
                        winnerStore.recordWinningClient(trackType, client)
                        return res
                    } else {
                        winnerStore.recordFailure(trackType, client)
                        activeFutures.remove(done)
                        break
                    }
                } catch (_: Throwable) {
                    activeFutures.remove(done)
                    break
                }
            }
            try {
                Thread.sleep(10L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }

        // Task 4 Hedged race: launch candidate 2 if candidate 1 did not complete within 350ms
        if (candidate2 != null && activeFutures.none { it.isDone }) {
            submitCandidate(candidate2)
        }

        // Poll for either candidate 1 or candidate 2 to complete
        val hedgeRaceDeadline = android.os.SystemClock.elapsedRealtime() + 6000L
        while (android.os.SystemClock.elapsedRealtime() < hedgeRaceDeadline && activeFutures.isNotEmpty()) {
            val doneList = activeFutures.filter { it.isDone }
            for (done in doneList) {
                try {
                    val (client, res) = done.get()
                    if (res != null) {
                        for (f in activeFutures) { if (f != done) f.cancel(true) }
                        winnerStore.recordWinningClient(trackType, client)
                        return res
                    } else {
                        winnerStore.recordFailure(trackType, client)
                        activeFutures.remove(done)
                    }
                } catch (_: Throwable) {
                    activeFutures.remove(done)
                }
            }
            if (activeFutures.isEmpty()) break
            try {
                Thread.sleep(15L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }

        // Fallback: sequential check on remaining candidates in chain
        val remainingClients = clientChain.drop(2)
        for (client in remainingClients) {
            val res = attemptClient(client)
            if (res != null) {
                winnerStore.recordWinningClient(trackType, client)
                return res
            } else {
                winnerStore.recordFailure(trackType, client)
            }
        }

        throw InnertubeException(
            signal = lastSignal,
            message = "All Innertube client fallback resolutions failed for video $videoId",
            traceId = traceId,
            cause = lastException
        )
    }

    private fun extractUrlFromFormat(format: JSONObject): String? {
        val directUrl = format.optString("url")
        if (directUrl.isNotEmpty()) return directUrl

        val cipher = format.optString("signatureCipher").ifEmpty { format.optString("cipher") }
        if (cipher.isNotEmpty()) {
            return runCatching {
                var rawUrl: String? = null
                var sig: String? = null
                var sigParam: String = "sig"

                val pairs = cipher.split("&")
                for (pair in pairs) {
                    val parts = pair.split("=", limit = 2)
                    if (parts.size == 2) {
                        when (parts[0]) {
                            "url" -> rawUrl = URLDecoder.decode(parts[1], "UTF-8")
                            "s" -> sig = URLDecoder.decode(parts[1], "UTF-8")
                            "sp" -> sigParam = URLDecoder.decode(parts[1], "UTF-8")
                        }
                    }
                }

                if (rawUrl != null) {
                    if (sig != null) {
                        val decipherCache = JsDecipherCache.getInstance(context)
                        val deciphered = decipherCache.decipherSignature(sig)
                        val separator = if (rawUrl.contains("?")) "&" else "?"
                        "$rawUrl$separator$sigParam=${URLEncoder.encode(deciphered, "UTF-8")}"
                    } else {
                        rawUrl
                    }
                } else {
                    null
                }
            }.getOrNull()
        }
        return null
    }

    private val validatedUrls = ConcurrentHashMap<String, Long>()

    private fun validateStreamUrl(url: String): Boolean {
        val now = System.currentTimeMillis()
        val lastVal = validatedUrls[url]
        if (lastVal != null && (now - lastVal) < 300_000L) {
            return true // Fast path: recently validated within 5 minutes
        }

        return try {
            val req = okhttp3.Request.Builder()
                .url(url)
                .addHeader("Range", "bytes=0-0")
                .addHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/138.0.0.0 Safari/537.36")
                .build()
            val client = YtmHttpClient.okHttpClient.newBuilder()
                .callTimeout(1200, TimeUnit.MILLISECONDS)
                .readTimeout(1000, TimeUnit.MILLISECONDS)
                .build()
            client.newCall(req).execute().use { resp ->
                val code = resp.code
                val contentType = resp.header("Content-Type") ?: ""
                val ok = (code in 200..206) && (contentType.startsWith("audio/") || contentType.startsWith("video/")) && !contentType.contains("text/html")
                if (ok) {
                    validatedUrls[url] = now
                }
                ok
            }
        } catch (_: Throwable) {
            false
        }
    }

    fun requestPlayer(videoId: String, clientType: ClientType): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/player?prettyPrint=false&key=$API_KEY"
        val payload = buildPlayerBody(videoId, clientType)
        // TTFA telemetry: report each ladder client attempt with its RTT so
        // the Dart/Sentry layer can attribute resolve latency per client.
        val start = System.currentTimeMillis()
        return try {
            val json = postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.PLAYER)
            YtmMetricsRegistry.recordRelayed(
                "ladder.client_attempt",
                System.currentTimeMillis() - start,
                attrs = mapOf("client" to clientType.name)
            )
            json
        } catch (t: Throwable) {
            YtmMetricsRegistry.recordRelayed(
                "ladder.client_attempt",
                System.currentTimeMillis() - start,
                isError = true,
                attrs = mapOf("client" to clientType.name)
            )
            throw t
        }
    }

    fun requestBrowse(browseId: String, clientType: ClientType = ClientType.WEB_REMIX): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/browse?prettyPrint=false&key=$API_KEY"
        val payload = JSONObject().apply {
            put("context", buildClientContext(clientType))
            put("browseId", browseId)
        }
        return postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.BROWSE)
    }

    fun requestContinuation(token: String, clientType: ClientType = ClientType.WEB_REMIX): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/browse?prettyPrint=false&key=$API_KEY"
        val payload = JSONObject().apply {
            put("context", buildClientContext(clientType))
            put("continuation", token)
        }
        return postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.BROWSE)
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
        return postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.SEARCH)
    }

    private fun postWithRetry(
        urlStr: String,
        body: JSONObject,
        clientType: ClientType,
        bucket: RateLimiter.Bucket,
        maxRetries: Int = 3,
    ): JSONObject {
        var lastError: Exception? = null
        val traceId = UUID.randomUUID().toString()

        for (attempt in 0 until maxRetries) {
            rateLimiter.acquirePermit(bucket)

            try {
                val fp = FingerprintStore.getFingerprint(context)
                val mediaType = "application/json; charset=UTF-8".toMediaTypeOrNull()
                val requestBody = body.toString().toRequestBody(mediaType)

                val reqBuilder = okhttp3.Request.Builder()
                    .url(urlStr)
                    .post(requestBody)
                    .header("Content-Type", "application/json; charset=UTF-8")
                    .header("User-Agent", fp.buildUserAgent(clientType))
                    .header("X-Goog-Api-Key", API_KEY)
                    .header("x-youtube-client-name", clientType.clientNameId)
                    .header("x-youtube-client-version", clientType.effectiveClientVersion)

                // Attach visitorData if available
                val authedWeb = clientType.isWeb && cookieStore.isSessionValid()
                val visitorData = if (authedWeb) {
                    PoTokenManager.sessionVisitorData.ifEmpty { PoTokenManager.visitorData }
                } else {
                    PoTokenManager.visitorData
                }
                if (visitorData.isNotEmpty()) {
                    reqBuilder.header("X-Goog-Visitor-Id", visitorData)
                }

                if (clientType.isWeb) {
                    val origin = clientType.endpointHost
                    reqBuilder.header("Origin", origin)
                    reqBuilder.header("Referer", "$origin/")
                    reqBuilder.header("X-Origin", origin)
                    reqBuilder.header("x-origin", origin)
                    reqBuilder.header("x-goog-authuser", "0")
                } else {
                    reqBuilder.header("X-Origin", clientType.endpointHost)
                }

                // Attach cookies and SAPISIDHASH for Web client requests
                if (clientType.isWeb) {
                    val cookieHeader = cookieStore.getMergedCookieHeader()
                    if (!cookieHeader.isNullOrEmpty()) {
                        reqBuilder.header("Cookie", cookieHeader)

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
                            reqBuilder.header("Authorization", "$authType ${timestamp}_$hash")
                        }
                    }
                }

                val response = YtmHttpClient.okHttpClient.newCall(reqBuilder.build()).execute()
                val code = response.code

                if (clientType.isWeb) {
                    val setCookies = response.headers("Set-Cookie")
                    if (setCookies.isNotEmpty()) {
                        cookieStore.ingestSetCookieHeaders(setCookies)
                    }
                }

                if (code == 429) {
                    val retryAfter = response.header("Retry-After")?.toLongOrNull()
                    val backoff = rateLimiter.onRateLimited(retryAfter)
                    ProxyManager.onPathFailed(urlStr)
                    Log.w(TAG, "[$traceId] Rate limited (429) on attempt $attempt. Backing off for ${backoff}ms")
                    response.close()
                    Thread.sleep(backoff)
                    continue
                }

                if (code == 403) {
                    ProxyManager.onPathFailed(urlStr)
                }

                if (code in 500..599) {
                    Log.w(TAG, "[$traceId] Server error ($code) on attempt $attempt. Retrying...")
                    response.close()
                    // TTFA: the old 1s/2s/4s sleep ladder burned the
                    // tap-to-audio budget on the synchronous play path. Cap
                    // the 5xx backoff at <=300ms (plus small jitter).
                    Thread.sleep(minOf(200L, 100L shl attempt) + (0..100).random())
                    continue
                }

                val responseStr = response.body?.string() ?: ""

                if (code !in 200..299) {
                    val signal = YtmBlockSignal.parse(code, responseStr)
                    Log.w(TAG, "[$traceId] Innertube (${clientType.name}) non-200 ($code) -> $signal: $responseStr")
                    throw InnertubeException(signal, "HTTP error $code ($signal): $responseStr", traceId)
                }

                rateLimiter.onSuccess()
                ProxyManager.onPathSuccess()
                val parsed = JSONObject(responseStr)
                harvestSessionState(parsed, clientType)
                return parsed
            } catch (e: InnertubeException) {
                if (e.signal == YtmBlockSignal.SignInRequired || e.signal == YtmBlockSignal.VideoGone) {
                    throw e
                }
                lastError = e
            } catch (e: UnknownHostException) {
                // DoH fallback attempt
                val host = Uri.parse(urlStr).host
                if (host != null) {
                    val dohResolved = DnsOverHttpsResolver.resolve(host)
                    if (dohResolved != null) {
                        Log.i(TAG, "[$traceId] Resolved host $host via DoH: ${dohResolved.hostAddress}")
                    }
                }
                lastError = e
            } catch (e: IOException) {
                lastError = e
                ProxyManager.onPathFailed(urlStr)
                Log.w(TAG, "[$traceId] Network error on attempt $attempt for ${clientType.name}: ${e.message}")
            } catch (e: Exception) {
                lastError = e
                Log.e(TAG, "[$traceId] Unexpected error in Innertube post: ${e.message}", e)
            } finally {
                rateLimiter.releasePermit()
            }
        }

        throw InnertubeException(
            signal = YtmBlockSignal.RateLimited,
            message = "Innertube request failed after $maxRetries attempts for ${clientType.name}",
            traceId = traceId,
            cause = lastError
        )
    }

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

        val hasPo = PoTokenManager.isReady || (!PoTokenManager.webViewBroken && !PoTokenManager.isLimitedMode && PoTokenManager.ensureReadySync())

        val playbackContext = JSONObject()
        val contentPlaybackContext = JSONObject().apply {
            put("html5Preference", "HTML5_PREF_WANTS")
            if (!clientType.isWeb && hasPo) {
                val tokenTarget = PoTokenManager.visitorData.ifEmpty { videoId }
                val poToken = PoTokenManager.poTokenForSync(tokenTarget)
                if (poToken.isNotEmpty()) {
                    put("poToken", poToken)
                }
            }
        }
        playbackContext.put("contentPlaybackContext", contentPlaybackContext)
        root.put("playbackContext", playbackContext)

        if (clientType.isWeb && hasPo) {
            val dataSyncId = PoTokenManager.dataSyncId
            val poToken = if (cookieStore.isSessionValid() && dataSyncId.isNotEmpty()) {
                PoTokenManager.accountPoTokenForSync(dataSyncId)
            } else {
                val tokenTarget = PoTokenManager.visitorData.ifEmpty { videoId }
                PoTokenManager.poTokenForSync(tokenTarget)
            }
            if (poToken.isNotEmpty()) {
                root.put(
                    "serviceIntegrityDimensions",
                    JSONObject().put("poToken", poToken),
                )
            }
        }

        return root
    }

    private fun buildClientContext(clientType: ClientType, videoId: String? = null): JSONObject {
        val fp = FingerprintStore.getFingerprint(context)
        val client = JSONObject().apply {
            put("clientName", clientType.clientName)
            put("clientVersion", clientType.effectiveClientVersion)
            put("hl", fp.hl)
            put("gl", fp.gl)
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
                    put("androidSdkVersion", fp.sdkInt)
                    put("osName", "Android")
                    put("osVersion", fp.osVersion)
                    put("platform", "MOBILE")
                    put("deviceMake", fp.deviceMake)
                    put("deviceModel", fp.deviceModel)
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
        const val HEDGE_DELAY_MS = 350L
        var API_KEY: String = System.getProperty("YTM_API_KEY") ?: "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
        @Volatile
        private var _streamResolverPool: java.util.concurrent.ExecutorService? = null
        val streamResolverPool: java.util.concurrent.ExecutorService
            get() {
                val existing = _streamResolverPool
                if (existing != null && !existing.isShutdown && !existing.isTerminated) return existing
                synchronized(this) {
                    val existing2 = _streamResolverPool
                    if (existing2 != null && !existing2.isShutdown && !existing2.isTerminated) return existing2
                    val newPool = java.util.concurrent.Executors.newFixedThreadPool(3) { r ->
                        Thread(r).apply {
                            isDaemon = true
                            name = "InnertubeStream-${id}"
                        }
                    }
                    _streamResolverPool = newPool
                    return newPool
                }
            }

        fun shutdown() {
            try {
                _streamResolverPool?.shutdownNow()
            } catch (_: Exception) {}
            _streamResolverPool = null
        }
    }
}
