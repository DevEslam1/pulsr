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
import java.util.zip.GZIPInputStream

/**
 * Hardened Innertube API Client with Multi-Client Context Support and Strategy Engine.
 *
 * Implements 6-Layer Resilience:
 * - L1: Consistent Device Fingerprinting per ClientType
 * - L2: Precise YtmBlockSignal parser (8 response signals + a transport signal)
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

        /**
         * Version actually put on the wire.
         *
         * Web clients synthesise today's date: YouTube rejects a `1.<date>` that
         * is weeks stale, so a pinned literal here (or in the asset) ages out.
         * Every other client takes the [ClientCapabilityMatrix] value, which is
         * what makes `client_capabilities.json` able to bump a version without a
         * new build — before this the matrix was loaded, logged and then ignored.
         */
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
                else -> ClientCapabilityMatrix.getCapability(this)
                    .defaultClientVersion
                    .ifBlank { clientVersion }
            }

        /** `x-youtube-client-name`, overridable through the capability matrix. */
        val effectiveClientNameId: String
            get() = ClientCapabilityMatrix.getCapability(this)
                .clientNameId
                .ifBlank { clientNameId }

        /**
         * Whether this client may carry the signed-in Google session: the cookie
         * jar, the SAPISIDHASH `Authorization`, the session `visitorData`, the
         * account-bound poToken and `user.lockedSafetyMode`.
         *
         * Only WEB_REMIX may. The remaining [isWeb] clients are embed / TV /
         * mobile-web contexts that earn their place in the chain precisely by
         * resolving *logged out* on a flagged IP. An authenticated embed request
         * is an auth-context mismatch: YouTube answers LOGIN_REQUIRED with
         * "sign in to confirm you're not a bot", which [YtmBlockSignal] reads as
         * a BotChallenge — so it counts toward the chain short-circuit and
         * invalidates the poToken mid-sweep. Signing in therefore disabled the
         * exact fallbacks that work while signed out. This is the same
         * guest-only rule already applied to ANDROID_MUSIC / IOS_MUSIC.
         */
        val acceptsSessionAuth: Boolean
            get() = this == WEB_REMIX
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

        val traceId = UUID.randomUUID().toString()

        // These are written from up to three pool threads during the hedged
        // race, so they cannot be plain captured vars.
        val lastSignalRef = java.util.concurrent.atomic.AtomicReference(YtmBlockSignal.RateLimited)
        val lastExceptionRef = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)

        // Track IP-level blocks to short-circuit early. The hedged race runs 2
        // candidates up front, so a threshold of 2 fires before the sequential
        // tail ever starts — the 7 remaining clients never get tried. 5 lets
        // the tail prove itself (last-resort clients like ANDROID_TESTSUITE
        // often survive a flagged IP) while still bailing out of a doomed
        // sweep instead of burning ~10-20s per track.
        val blockSignalCount = java.util.concurrent.atomic.AtomicInteger(0)
        val blockClients = java.util.concurrent.CopyOnWriteArrayList<String>()
        // attemptClient cannot throw the short-circuit itself: its own
        // `catch (t: Throwable)` would swallow it. It parks the exception here
        // and the race / sequential loops rethrow it.
        val shortCircuit = java.util.concurrent.atomic.AtomicReference<InnertubeException?>(null)

        fun attemptClient(client: ClientType): Map<String, Any?>? {
            if (Thread.currentThread().isInterrupted) return null
            if (shortCircuit.get() != null) return null
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
                    lastSignalRef.set(parsedSignal)
                    Log.w(TAG, "[$traceId] Client ${client.name} returned status $status -> $parsedSignal")
                    if ((parsedSignal == YtmBlockSignal.BotChallenge || parsedSignal == YtmBlockSignal.PoTokenInvalid) &&
                        (client == ClientType.ANDROID_MUSIC || client == ClientType.WEB_REMIX)) {
                        // Throttled: during an IP-flagged sweep every client hits
                        // this branch; the refresh itself is a no-op while the
                        // token is fresh, so once a minute is plenty.
                        val now = android.os.SystemClock.elapsedRealtime()
                        if (now - lastBotRefreshTriggerMs > 30_000L) {
                            lastBotRefreshTriggerMs = now
                            PoTokenManager.invalidate()
                            PoTokenManager.triggerBackgroundRefresh()
                        }
                    }
                    if (parsedSignal == YtmBlockSignal.IpBlocked ||
                        parsedSignal == YtmBlockSignal.BotChallenge) {
                        blockClients.add(client.name)
                        val count = blockSignalCount.incrementAndGet()
                        if (count >= 5) {
                            Log.w(TAG, "[$traceId] Short-circuiting chain: $count IP-level blocks (${blockClients.joinToString()})")
                            shortCircuit.compareAndSet(
                                null,
                                InnertubeException(
                                    signal = parsedSignal,
                                    message = "IP/bot blocked by $count clients (${blockClients.joinToString()}) for video $videoId",
                                    traceId = traceId
                                )
                            )
                        }
                    }
                    return null
                }

                val streamingData = playerJson.optJSONObject("streamingData")
                val formatArrays = listOfNotNull(
                    streamingData?.optJSONArray("adaptiveFormats"),
                    streamingData?.optJSONArray("formats")
                )

                val audioFormats = mutableListOf<Pair<JSONObject, String>>()
                for (array in formatArrays) {
                    for (i in 0 until array.length()) {
                        val format = array.optJSONObject(i) ?: continue
                        val mime = format.optString("mimeType")
                        val url = extractUrlFromFormat(format)
                        if (mime.startsWith("audio/") && !url.isNullOrEmpty()) {
                            audioFormats.add(format to url)
                        }
                    }
                }

                if (audioFormats.isEmpty()) {
                    // An empty format list normally means the poToken was
                    // rejected, but a genuinely unavailable track reports the
                    // same shape — only claim PoTokenInvalid when a token was
                    // actually attached.
                    val hadFormatArrays = formatArrays.any { it.length() > 0 }
                    lastSignalRef.set(
                        if (hadFormatArrays) YtmBlockSignal.VideoGone else YtmBlockSignal.PoTokenInvalid
                    )
                    Log.w(TAG, "[$traceId] Client ${client.name} returned no usable audio formats")
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
                    "traceId" to traceId,
                    // googlevideo URLs are time-boxed. Without this the Dart
                    // model's isExpired/isExpiringSoon are permanently false and
                    // both the player and the downloader run on dead URLs.
                    "expiresAt" to parseUrlExpiryEpochSeconds(selectedUrl)
                )
            } catch (t: Throwable) {
                Log.w(TAG, "[$traceId] Failed resolving with ${client.name}: ${t.message}")
                lastExceptionRef.set(t)
                if (t is InnertubeException) lastSignalRef.set(t.signal)
                return null
            }
        }

        val trackType = ClientWinnerStore.TRACK_TYPE_MUSIC
        val winnerStore = ClientWinnerStore.getInstance(context)

        // Authenticated cold-start datasyncId bootstrap. harvestSessionState only
        // yields a datasyncId on some responses, so a signed-in cold start needs
        // one WEB_REMIX round trip before an account-bound poToken can be minted.
        //
        // Its result is now used instead of discarded: the response was thrown
        // away, so every track resolved in the throttle window paid a full extra
        // authenticated player request that could not do anything but fail or be
        // ignored. If it resolves, that *is* the answer; if it does not, the
        // datasyncId it harvested still benefits the chain below.
        if (cookieStore.isSessionValid() && PoTokenManager.dataSyncId.isEmpty()) {
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - lastDataSyncBootstrapMs > DATASYNC_BOOTSTRAP_INTERVAL_MS) {
                lastDataSyncBootstrapMs = now
                val bootstrapped = attemptClient(ClientType.WEB_REMIX)
                if (bootstrapped != null) {
                    winnerStore.recordWinningClient(trackType, ClientType.WEB_REMIX)
                    return bootstrapped
                }
                winnerStore.recordFailure(trackType, ClientType.WEB_REMIX)
                shortCircuit.get()?.let { throw it }
            }
        }

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

        fun cancelAll(except: java.util.concurrent.Future<*>? = null) {
            for (f in activeFutures) { if (f != except) f.cancel(true) }
            activeFutures.clear()
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
                        cancelAll(done)
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
            shortCircuit.get()?.let { cancelAll(); throw it }
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
        val hedgeRaceDeadline = android.os.SystemClock.elapsedRealtime() + HEDGE_RACE_TIMEOUT_MS
        while (android.os.SystemClock.elapsedRealtime() < hedgeRaceDeadline && activeFutures.isNotEmpty()) {
            val doneList = activeFutures.filter { it.isDone }
            for (done in doneList) {
                try {
                    val (client, res) = done.get()
                    if (res != null) {
                        cancelAll(done)
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
            shortCircuit.get()?.let { cancelAll(); throw it }
            try {
                Thread.sleep(15L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }

        // The race timed out with candidates still running. Cancel them before
        // the sequential fallback: leaving them in flight holds 2 of the 3 pool
        // threads, so every sequential attempt queues behind work whose result
        // is already being discarded.
        cancelAll()

        shortCircuit.get()?.let { throw it }

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
            shortCircuit.get()?.let { throw it }
        }

        throw InnertubeException(
            signal = lastSignalRef.get(),
            message = "All Innertube client fallback resolutions failed for video $videoId",
            traceId = traceId,
            cause = lastExceptionRef.get()
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
            }.getOrElse { t ->
                Log.w(TAG, "Discarding ciphered format (itag ${format.optInt("itag")}): ${t.message}")
                null
            }
        }
        return null
    }

    /**
     * googlevideo URLs carry an `expire` query param (epoch seconds, ~6h out).
     * Returns null when the parameter is absent or unparseable.
     */
    private fun parseUrlExpiryEpochSeconds(url: String): Long? = runCatching {
        Uri.parse(url).getQueryParameter("expire")?.toLongOrNull()
    }.getOrNull()

    fun requestPlayer(videoId: String, clientType: ClientType): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/player?prettyPrint=false&key=$API_KEY"
        val payload = buildPlayerBody(videoId, clientType)
        return postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.PLAYER, maxRetries = 1)
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
            if (!rateLimiter.acquirePermit(bucket)) {
                Thread.currentThread().interrupt()
                lastError = IOException("Rate limiter wait interrupted for ${clientType.name}")
                break
            }
            // The limiter now owns exactly one permit on our behalf; track it so
            // the 429/5xx paths that deliberately drop it mid-iteration do not
            // let `finally` over-release (Semaphore.release has no upper bound,
            // so an over-release permanently widens the concurrency cap).
            var permitHeld = true

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
                    .header("x-youtube-client-name", clientType.effectiveClientNameId)
                    .header("x-youtube-client-version", clientType.effectiveClientVersion)

                // Attach visitorData if available
                val authedWeb = clientType.acceptsSessionAuth && cookieStore.isSessionValid()
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
                    // Only an authenticated request has an "auth user" to index.
                    if (authedWeb) {
                        reqBuilder.header("x-goog-authuser", "0")
                    }
                } else {
                    reqBuilder.header("X-Origin", clientType.endpointHost)
                }

                // Attach cookies and SAPISIDHASH only for the one client allowed
                // to carry the session (see ClientType.acceptsSessionAuth). Also
                // gated on isSessionValid(): CookieManager hands back empty and
                // "EXPIRED" values, and attaching a jar plus a SAPISIDHASH built
                // from those is an authenticated request with no credential.
                if (authedWeb) {
                    val cookieHeader = cookieStore.getMergedCookieHeader(clientType.endpointHost)
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

                // Every other client stays guest-only: attaching WEB session
                // cookies to ANDROID_MUSIC/IOS_MUSIC — or to the embed/TV/MWEB
                // web clients — poisons the fallback that works logged-out
                // (YouTube returns LOGIN_REQUIRED for mismatched auth on those
                // endpoints). Authenticated playback is covered by WEB_REMIX
                // with cookies + SAPISIDHASH above.

                val response = YtmHttpClient.okHttpClient.newCall(reqBuilder.build()).execute()
                val code = response.code

                // Only the authenticated client's Set-Cookie may touch the jar.
                // A guest embed/MWEB response hands out its own VISITOR_INFO1_LIVE
                // / YSC, and merging those into the session jar overwrote the
                // signed-in values with anonymous ones.
                if (authedWeb) {
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
                    // Sleep outside the global permit: holding it across a
                    // (potentially 15m) backoff starves all other buckets.
                    rateLimiter.releasePermit()
                    permitHeld = false
                    Thread.sleep(backoff)
                    permitHeld = rateLimiter.acquirePermit(bucket)
                    if (!permitHeld) {
                        Thread.currentThread().interrupt()
                        lastError = IOException("Rate limiter wait interrupted after 429")
                        break
                    }
                    continue
                }

                if (code == 403) {
                    ProxyManager.onPathFailed(urlStr)
                }

                if (code in 500..599) {
                    Log.w(TAG, "[$traceId] Server error ($code) on attempt $attempt. Retrying...")
                    response.close()
                    val sleepMs = (1000L shl attempt) + (0..500).random()
                    rateLimiter.releasePermit()
                    permitHeld = false
                    Thread.sleep(sleepMs)
                    permitHeld = rateLimiter.acquirePermit(bucket)
                    if (!permitHeld) {
                        Thread.currentThread().interrupt()
                        lastError = IOException("Rate limiter wait interrupted after $code")
                        break
                    }
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
                // DoH fallback: resolve via DNS-over-HTTPS, inject into the
                // shared TTL cache so the immediate retry hits the fresh IP
                // instead of the same failing system DNS.
                val host = Uri.parse(urlStr).host
                if (host != null) {
                    val dohResolved = DnsOverHttpsResolver.resolve(host)
                    if (dohResolved != null) {
                        Log.i(TAG, "[$traceId] Resolved host $host via DoH: ${dohResolved.hostAddress}")
                        runCatching {
                            YtmHttpClient.TtlDnsCache.instance.put(host, listOf(dohResolved))
                        }
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
                if (permitHeld) rateLimiter.releasePermit()
            }
        }

        // The signal must reflect what actually went wrong. Hardcoding
        // RateLimited here converted every real BotChallenge into a global
        // backoff, so the app cooled down instead of refreshing the poToken —
        // and turned every offline blip into a rate-limit cooldown.
        val terminalSignal = when (val err = lastError) {
            is InnertubeException -> err.signal
            is UnknownHostException,
            is java.net.ConnectException,
            is java.net.NoRouteToHostException,
            is java.net.SocketTimeoutException,
            is javax.net.ssl.SSLException -> YtmBlockSignal.NetworkUnavailable
            else -> YtmBlockSignal.RateLimited
        }

        throw InnertubeException(
            signal = terminalSignal,
            message = "Innertube request failed after $maxRetries attempts for ${clientType.name}",
            traceId = traceId,
            cause = lastError
        )
    }

    private fun harvestSessionState(json: JSONObject, clientType: ClientType) {
        if (!clientType.acceptsSessionAuth || !cookieStore.isSessionValid()) return
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
        }
        playbackContext.put("contentPlaybackContext", contentPlaybackContext)
        root.put("playbackContext", playbackContext)

        // Only web clients consume a poToken. Computing readiness before this
        // guard made ANDROID_VR / IOS_MUSIC block on ensureReadySync() — which
        // spins up a BotGuard WebView — even though the entire reason those
        // clients are in the chain is that they need no token.
        if (clientType.isWeb) {
            val hasPo = PoTokenManager.isReady ||
                (!PoTokenManager.webViewBroken && !PoTokenManager.isLimitedMode && PoTokenManager.ensureReadySync())
            if (hasPo) {
                val dataSyncId = PoTokenManager.dataSyncId
                // Only the client that actually carries the session may send an
                // account-bound token. An embed/MWEB request is a guest request,
                // and a datasyncId-bound token in a guest context is rejected.
                val poToken = if (clientType.acceptsSessionAuth &&
                    cookieStore.isSessionValid() &&
                    dataSyncId.isNotEmpty()
                ) {
                    PoTokenManager.accountPoTokenForSync(dataSyncId)
                } else {
                    // A token must be bound to visitorData. Minting one against a
                    // videoId produces a token YouTube rejects outright, so with
                    // no visitorData it is better to send none.
                    val tokenTarget = PoTokenManager.visitorData
                    if (tokenTarget.isEmpty()) "" else PoTokenManager.poTokenForSync(tokenTarget)
                }
                if (poToken.isNotEmpty()) {
                    root.put(
                        "serviceIntegrityDimensions",
                        JSONObject().put("poToken", poToken),
                    )
                }
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
            val authedWeb = clientType.acceptsSessionAuth && cookieStore.isSessionValid()
            // Must mirror the X-Goog-Visitor-Id header built in postWithRetry.
            // Sending the header without the matching context.client.visitorData
            // is an identity mismatch and reliably provokes a bot challenge.
            val visitorData = if (authedWeb) {
                PoTokenManager.sessionVisitorData.ifEmpty { PoTokenManager.visitorData }
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
            // Must be the full video URL (not just the domain) — YouTube validates
            // this against the videoId being requested. A bare domain returns ERROR
            // with no streamingData.
            val embedVideoUrl = if (!videoId.isNullOrEmpty()) {
                "https://www.youtube.com/watch?v=$videoId"
            } else {
                "https://www.youtube.com"
            }
            thirdParty.put("embedUrl", embedVideoUrl)
            contextJson.put("thirdParty", thirdParty)
        }

        if (clientType.acceptsSessionAuth && cookieStore.isSessionValid()) {
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
        // Ceiling on the hedged race before falling back to the sequential tail.
        const val HEDGE_RACE_TIMEOUT_MS = 3000L
        private const val DATASYNC_BOOTSTRAP_INTERVAL_MS = 300_000L
        // Last bot-refresh trigger across all resolve calls (throttle).
        @Volatile
        private var lastBotRefreshTriggerMs = 0L
        @Volatile
        private var lastDataSyncBootstrapMs = 0L
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
                    // 3 threads over-subscribed as soon as a prefetch and a user
                    // tap overlapped: the hedge's second candidate queued behind
                    // the other resolve and could not complete inside the 350ms
                    // window, defeating the race entirely.
                    val newPool = java.util.concurrent.Executors.newFixedThreadPool(6) { r ->
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
