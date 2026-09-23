package com.pulsr.music

import android.content.Context
import android.net.Uri
import android.util.Log
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
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
import java.util.concurrent.Callable
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Hardened Innertube API Client with Multi-Client Context Support and Strategy Engine.
 *
 * Implements 6-Layer Resilience:
 * - L1: Consistent Device Fingerprinting per ClientType
 * - L2: Precise YtmBlockSignal parser (8 response signals + a transport signal)
 * - L3: Dynamic ResolutionStrategy & Capability Matrix Fallback
 * - L4: ProxyPool, DoH, and Cellular Failover Integration
 * - L5: Adaptive Multi-Bucket Rate Limiter with Jitter and Persistence
 * - L6: Stream itag Fallback Ladder (251 -> 140 -> 139 -> 250 -> 249)
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
         * WEB_REMIX prefers the version scraped from music.youtube.com by Dart:
         * a stale one makes YouTube answer every player request with UNPLAYABLE
         * "Video unavailable", which looks identical to a rejected poToken. Web
         * clients otherwise synthesise today's date (a pinned `1.<date>` ages
         * out), and every other client takes the [ClientCapabilityMatrix] value,
         * which is what makes `client_capabilities.json` able to bump a version
         * without a new build.
         */
        val effectiveClientVersion: String
            get() {
                if (this == WEB_REMIX) {
                    val scraped = ClientCapabilityMatrix.getWebMusicClientVersion()
                    if (scraped.isNotEmpty()) return scraped
                }
                return ClientCapabilityMatrix.getCapability(this)
                    .defaultClientVersion
                    .ifBlank {
                        when (this) {
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

    /**
     * Typed result of resolving a client attempt.
     *
     * Distinguishes successful payloads from real client-specific failures vs.
     * neutral skips (short-circuits, thread interruptions, network outages).
     * Prevents [ClientWinnerStore] pollution.
     */
    sealed class AttemptResult {
        data class Success(val payload: Map<String, Any?>) : AttemptResult()
        data class Failure(val signal: YtmBlockSignal?, val isClientSpecific: Boolean = true) : AttemptResult()
        object ShortCircuited : AttemptResult()
        object Interrupted : AttemptResult()
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
     * 4. Selects optimal itag via audio itag ladder (251 -> 140 -> 139 -> 250 -> 249)
     */
    /**
     * 2026-09 gap 4: GVS (googlevideo) gating is expanding per-client. For
     * clients whose capability marks them poToken-requiring, append the
     * streaming (gvs-context) poToken as 'pot='. Matrix-driven so capability
     * overrides update behavior without a release. Idempotent.
     */
    private fun maybeAppendStreamPot(url: String, client: ClientType): String {
        val host = runCatching { Uri.parse(url).host ?: "" }.getOrDefault("")
        if (!host.contains("googlevideo.com")) return url
        if (!ClientCapabilityMatrix.getCapability(client).requiresPoToken) return url
        val dataSyncId = PoTokenManager.dataSyncId
        val isAuthed = client.acceptsSessionAuth && cookieStore.isSessionValid()
        val token = if (isAuthed) {
            // FIX #9: For authenticated session, only use account token if dataSyncId is present.
            // Do NOT fall back to guest streamingPoToken!
            if (dataSyncId.isNotEmpty()) {
                PoTokenManager.accountPoTokenForSync(dataSyncId)
            } else {
                ""
            }
        } else {
            PoTokenManager.streamingPoToken
        }
        if (token.isEmpty()) return url

        return runCatching {
            val uri = Uri.parse(url)
            val existingPot = uri.getQueryParameter("pot")
            // FIX #17: If pot is already present and non-empty, do not re-append
            if (!existingPot.isNullOrEmpty()) return url

            // If pot parameter is present but empty (e.g. pot=, ?pot&, or ?pot#), replace it
            val emptyPotPattern = Regex("([?&])pot=?(?=&|#|$)")
            if (emptyPotPattern.containsMatchIn(url)) {
                val encodedToken = URLEncoder.encode(token, "UTF-8")
                val replacement = "$1pot=" + Regex.escapeReplacement(encodedToken)
                emptyPotPattern.replaceFirst(url, replacement)
            } else {
                uri.buildUpon().appendQueryParameter("pot", token).toString()
            }
        }.getOrDefault(url)
    }

    fun resolvePlayerStream(videoId: String, quality: String = "high"): Map<String, Any?> {
        val traceId = UUID.randomUUID().toString()

        // FIX #13 & #16: Shared egress bot/block circuit breaker check
        val nowMs = android.os.SystemClock.elapsedRealtime()
        val breakerUntil = globalBlockCooldownUntilMs.get()
        if (nowMs < breakerUntil && consecutiveEgressBlocks.get() >= 1) {
            val remainingSec = ((breakerUntil - nowMs) / 1000L).coerceAtLeast(1)
            val signal = globalBlockSignal.get()
            Log.w(TAG, "[$traceId] Fast-failing: egress bot/block breaker active ($signal) for another ${remainingSec}s")
            throw InnertubeException(
                signal = signal,
                message = "Egress is currently under $signal cooldown ($remainingSec s remaining)",
                traceId = traceId
            )
        }

        val clientChain = resolutionStrategy.buildChain(
            ResolutionStrategy.Operation.STREAM_RESOLVE,
            limitedMode = PoTokenManager.isLimitedMode,
            hasJsEngine = true
        )

        // FIX #1: Nullable AtomicReference with neutral default on throw
        val lastSignalRef = AtomicReference<YtmBlockSignal?>(null)
        val lastExceptionRef = AtomicReference<Throwable?>(null)

        // Priority-based signal update: higher priority = more actionable recovery action.
        fun signalPriority(s: YtmBlockSignal?): Int = when (s) {
            YtmBlockSignal.BotChallenge            -> 8
            YtmBlockSignal.PoTokenInvalid          -> 7
            YtmBlockSignal.RateLimited             -> 6
            YtmBlockSignal.IpBlocked               -> 5
            YtmBlockSignal.SignatureDecipherFailed -> 4
            YtmBlockSignal.SabrEnforced            -> 3
            YtmBlockSignal.SignInRequired          -> 2
            YtmBlockSignal.ClientDeprecated        -> 2
            YtmBlockSignal.GeoBlocked              -> 2
            YtmBlockSignal.VideoGone               -> 1
            YtmBlockSignal.NetworkUnavailable      -> 0
            null                                   -> -1
        }
        fun updateBestSignal(newSignal: YtmBlockSignal?) {
            if (newSignal == null) return
            lastSignalRef.updateAndGet { current ->
                if (signalPriority(newSignal) > signalPriority(current)) newSignal else current
            }
        }

        // Track IP-level blocks AND bot challenges to short-circuit early.
        val blockSignalCount = AtomicInteger(0)
        val blockClients = CopyOnWriteArrayList<String>()
        val shortCircuit = AtomicReference<InnertubeException?>(null)

        // FIX #24: Dynamic short-circuit threshold relative to eligible chain size
        val shortCircuitThreshold = (clientChain.size * 0.65).toInt().coerceIn(3, 6)

        // FIX #11 & #12: Track active okhttp3.Calls per client in thread-safe lists
        val activeCalls = ConcurrentHashMap<ClientType, CopyOnWriteArrayList<okhttp3.Call>>()
        val activeFutures = CopyOnWriteArrayList<Future<Pair<ClientType, AttemptResult>>>()

        fun cancelAll(exceptFuture: Future<*>? = null, exceptClient: ClientType? = null) {
            for (f in activeFutures) {
                if (f != exceptFuture) f.cancel(true)
            }
            for ((client, callList) in activeCalls) {
                if (client != exceptClient) {
                    for (call in callList) {
                        runCatching { call.cancel() }
                    }
                }
            }
            activeFutures.clear()
        }

        fun attemptClient(
            client: ClientType,
            ignoreShortCircuit: Boolean = false
        ): AttemptResult {
            if (Thread.currentThread().isInterrupted) return AttemptResult.Interrupted
            // FIX #2: Allow bypass during PoToken recovery
            if (!ignoreShortCircuit && shortCircuit.get() != null) return AttemptResult.ShortCircuited

            // FIX #7: Keep default safe and wrap fingerprint store in try block
            var actualRequestUa = client.userAgent

            try {
                val fp = FingerprintStore.getFingerprint(context)
                actualRequestUa = fp.buildUserAgent(client)

                Log.d(TAG, "[$traceId] Attempting player resolution for $videoId using client: ${client.name}")
                val playerJson = requestPlayer(videoId, client, activeCalls)
                if (Thread.currentThread().isInterrupted) return AttemptResult.Interrupted

                val playability = playerJson.optJSONObject("playabilityStatus")
                val status = playability?.optString("status") ?: ""
                val reason = playability?.optString("reason") ?: ""
                val subreason = playability?.optJSONObject("errorScreen")
                    ?.optJSONObject("playerErrorMessageRenderer")
                    ?.optJSONObject("subreason")
                    ?.optString("simpleText") ?: ""

                // FIX #10 & #6: Explicitly include ERROR, CONTENT_CHECK_REQUIRED, and LIVE_STREAM in playability check
                if (status.equals("LOGIN_REQUIRED", ignoreCase = true) ||
                    status.equals("UNPLAYABLE", ignoreCase = true) ||
                    status.equals("ERROR", ignoreCase = true) ||
                    status.equals("CONTENT_CHECK_REQUIRED", ignoreCase = true) ||
                    status.startsWith("LIVE_STREAM", ignoreCase = true) ||
                    status.contains("BOT", ignoreCase = true)) {

                    val parsedSignal = YtmBlockSignal.parse(200, status, playability)
                    updateBestSignal(parsedSignal)
                    // FIX #18 & #19: Log reason and subreason with redaction/truncation
                    val logReason = if (subreason.isNotEmpty()) "$reason ($subreason)" else reason
                    Log.w(TAG, "[$traceId] Client ${client.name} returned status $status (reason='${logReason.take(100)}') -> $parsedSignal")

                    if ((parsedSignal == YtmBlockSignal.PoTokenInvalid ||
                            PoTokenManager.isExpired() ||
                            PoTokenManager.isLimitedMode) &&
                        (client == ClientType.ANDROID_MUSIC || client == ClientType.WEB_REMIX)) {
                        // FIX #21: AtomicLong check-and-set for thread-safe throttle
                        val now = android.os.SystemClock.elapsedRealtime()
                        val last = lastBotRefreshTriggerMs.get()
                        if (now - last > 30_000L && lastBotRefreshTriggerMs.compareAndSet(last, now)) {
                            PoTokenManager.invalidate()
                            PoTokenManager.triggerBackgroundRefresh()
                        }
                    }

                    val isEgressBlock = parsedSignal == YtmBlockSignal.IpBlocked ||
                        parsedSignal == YtmBlockSignal.BotChallenge ||
                        parsedSignal == YtmBlockSignal.PoTokenInvalid

                    // FIX #15: Applies to any client executing without session auth
                    val isGuestClient = !client.acceptsSessionAuth || !cookieStore.isSessionValid()
                    val guestSignInAsBlock =
                        parsedSignal == YtmBlockSignal.SignInRequired &&
                            isGuestClient &&
                            blockSignalCount.get() > 0

                    if (isEgressBlock || guestSignInAsBlock) {
                        blockClients.add(client.name)
                        val count = blockSignalCount.incrementAndGet()
                        if (count >= shortCircuitThreshold) {
                            val winningSignal = lastSignalRef.get() ?: parsedSignal
                            Log.w(TAG, "[$traceId] Short-circuiting chain: $count block signals ($winningSignal) from (${blockClients.joinToString()}) for $videoId")
                            val exc = InnertubeException(
                                signal = winningSignal,
                                message = "Blocked by $count clients (${blockClients.joinToString()}) for video $videoId",
                                traceId = traceId
                            )
                            // FIX #2 & #11: Only increment global breaker if this thread actually sets the short circuit!
                            if (shortCircuit.compareAndSet(null, exc)) {
                                globalBlockSignal.set(winningSignal)
                                consecutiveEgressBlocks.incrementAndGet()
                                globalBlockCooldownUntilMs.set(android.os.SystemClock.elapsedRealtime() + 15_000L)
                            }
                        }
                    }

                    // FIX #1: Base client-specific failure only on true client signals, not raw UNPLAYABLE
                    val isClientSpecific = parsedSignal == YtmBlockSignal.ClientDeprecated ||
                        parsedSignal == YtmBlockSignal.SabrEnforced ||
                        parsedSignal == YtmBlockSignal.SignatureDecipherFailed
                    if (parsedSignal == YtmBlockSignal.SabrEnforced) {
                        SabrDemotionStore.markSabrEnforced(client)
                    }
                    return AttemptResult.Failure(parsedSignal, isClientSpecific = isClientSpecific)
                }

                val streamingData = playerJson.optJSONObject("streamingData")
                val formatArrays = listOfNotNull(
                    streamingData?.optJSONArray("adaptiveFormats"),
                    streamingData?.optJSONArray("formats")
                )

                // FIX #9: Single pass counting formats, URLs, and ciphers without duplicate extraction
                var totalFormats = 0
                var totalUrls = 0
                var cipheredCount = 0
                val audioFormats = mutableListOf<Pair<JSONObject, String>>()

                for (array in formatArrays) {
                    for (i in 0 until array.length()) {
                        val format = array.optJSONObject(i) ?: continue
                        totalFormats++
                        if (format.optString("signatureCipher").isNotEmpty() ||
                            format.optString("cipher").isNotEmpty()) {
                            cipheredCount++
                        }
                        val url = extractUrlFromFormat(format)
                        if (!url.isNullOrEmpty()) {
                            totalUrls++
                            val mime = format.optString("mimeType")
                            if (mime.startsWith("audio/")) {
                                audioFormats.add(format to url)
                            }
                        }
                    }
                }

                if (audioFormats.isEmpty()) {
                    val hadFormatArrays = totalFormats > 0
                    val hadCiphered = cipheredCount > 0
                    val emptySignal = when {
                        YtmBlockSignal.detectSabrStructural(
                            hasStreamingData = streamingData != null,
                            formatCount = totalFormats,
                            urlCount = totalUrls,
                            cipherCount = cipheredCount,
                        ) -> {
                            SabrDemotionStore.markSabrEnforced(client)
                            Log.w(TAG, "[$traceId] ${client.name} SABR-enforced (formats=$totalFormats, urls=0) -> demoted")
                            YtmBlockSignal.SabrEnforced
                        }
                        hadCiphered -> YtmBlockSignal.SignatureDecipherFailed
                        hadFormatArrays -> YtmBlockSignal.VideoGone
                        else -> YtmBlockSignal.PoTokenInvalid
                    }
                    updateBestSignal(emptySignal)
                    Log.w(TAG, "[$traceId] Client ${client.name} returned no usable audio formats (hadCiphered=$hadCiphered) -> $emptySignal")
                    val isClientSpecific = emptySignal == YtmBlockSignal.SabrEnforced || emptySignal == YtmBlockSignal.SignatureDecipherFailed
                    return AttemptResult.Failure(emptySignal, isClientSpecific = isClientSpecific)
                }

                // Layer 6: Itag Ladder 2026 — Opus 251 (160kbps) preferred over AAC 140
                val itagLadder = listOf(251, 140, 139, 250, 249)
                val selectedPair = when (quality.lowercase()) {
                    "low" -> audioFormats.minByOrNull { safeBitrate(it.first) }
                    "medium" -> audioFormats.minByOrNull { kotlin.math.abs(safeBitrate(it.first) - 128000) }
                    else -> {
                        audioFormats.sortedWith(
                            compareBy<Pair<JSONObject, String>> { pair ->
                                val itag = pair.first.optInt("itag", 0)
                                val idx = itagLadder.indexOf(itag)
                                if (idx >= 0) idx else 99
                            }.thenByDescending { safeBitrate(it.first) }
                        ).firstOrNull() ?: audioFormats.maxByOrNull { safeBitrate(it.first) }
                    }
                } ?: audioFormats.first()

                val selected = selectedPair.first
                val selectedUrl = selectedPair.second
                val selectedMime = selected.optString("mimeType", "audio/mp4")
                val selectedBitrate = safeBitrate(selected)
                val durationMs = selected.optLong("approxDurationMs", 0L)
                val videoDetails = playerJson.optJSONObject("videoDetails")

                val title = videoDetails?.optString("title") ?: ""
                val author = videoDetails?.optString("author") ?: ""

                // FIX #27: Extract highest resolution thumbnail if present
                val artworkUrl = extractBestArtworkUrl(videoDetails)

                // FIX #28: Robust container inference
                val container = when {
                    selectedMime.contains("mp4", ignoreCase = true) ||
                        selectedMime.contains("m4a", ignoreCase = true) ||
                        selectedMime.contains("aac", ignoreCase = true) -> "m4a"
                    selectedMime.contains("webm", ignoreCase = true) ||
                        selectedMime.contains("opus", ignoreCase = true) -> "webm"
                    selectedMime.contains("ogg", ignoreCase = true) -> "ogg"
                    else -> if (selected.optInt("itag", 0) in listOf(140, 139)) "m4a" else "webm"
                }

                Log.i(TAG, "[$traceId] Successfully resolved $videoId via ${client.name} (itag: ${selected.optInt("itag")}, bitrate: $selectedBitrate)")
                val finalUrl = maybeAppendStreamPot(selectedUrl, client)

                // FIX #8 & #20: Pre-connect non-blocking, non-fatal, on dedicated executor with wrapped scheduling
                runCatching {
                    preConnectExecutor.execute {
                        runCatching {
                            YtmHttpClient.preConnect(finalUrl)
                        }.onFailure {
                            Log.w(TAG, "[$traceId] preConnect async failed for ${client.name}: ${it.message}")
                        }
                    }
                }.onFailure {
                    Log.w(TAG, "[$traceId] Could not schedule preConnect for ${client.name}: ${it.message}")
                }

                val payload = mapOf(
                    "videoId" to videoId,
                    "url" to finalUrl,
                    "mimeType" to selectedMime.split(";").first().trim(),
                    "container" to container,
                    "bitrateKbps" to (selectedBitrate / 1000),
                    "durationMs" to durationMs,
                    "title" to title,
                    "artist" to author,
                    "artworkUrl" to artworkUrl,
                    "userAgent" to actualRequestUa, // FIX #8: Matches actual request UA
                    "activeClient" to client.name,
                    "traceId" to traceId,
                    "expiresAt" to parseUrlExpiryEpochSeconds(finalUrl)
                )
                return AttemptResult.Success(payload)
            } catch (t: Throwable) {
                // FIX #13: Never mask fatal JVM errors
                if (t is VirtualMachineError) throw t
                if (t is ThreadDeath) throw t
                if (t is InterruptedException || Thread.currentThread().isInterrupted) {
                    return AttemptResult.Interrupted
                }
                Log.w(TAG, "[$traceId] Failed resolving with ${client.name}: ${t.message}")
                lastExceptionRef.set(t)
                val sig = if (t is InnertubeException) {
                    updateBestSignal(t.signal)
                    t.signal
                } else null

                // FIX #2: Count transport-level egress blocks toward short-circuit
                val isTransportEgressBlock =
                    sig == YtmBlockSignal.IpBlocked ||
                    sig == YtmBlockSignal.BotChallenge ||
                    sig == YtmBlockSignal.PoTokenInvalid

                val isGuestClient = !client.acceptsSessionAuth || !cookieStore.isSessionValid()
                val transportGuestSignInAsBlock =
                    sig == YtmBlockSignal.SignInRequired &&
                    isGuestClient &&
                    blockSignalCount.get() > 0

                if (isTransportEgressBlock || transportGuestSignInAsBlock) {
                    blockClients.add(client.name)
                    val count = blockSignalCount.incrementAndGet()
                    if (count >= shortCircuitThreshold) {
                        val winningSignal = lastSignalRef.get() ?: YtmBlockSignal.BotChallenge
                        Log.w(TAG, "[$traceId] Short-circuiting chain on transport block: $count block signals ($winningSignal) from (${blockClients.joinToString()}) for $videoId")
                        val exc = InnertubeException(
                            signal = winningSignal,
                            message = "Blocked by $count clients (${blockClients.joinToString()}) for video $videoId",
                            traceId = traceId
                        )
                        if (shortCircuit.compareAndSet(null, exc)) {
                            globalBlockSignal.set(winningSignal)
                            consecutiveEgressBlocks.incrementAndGet()
                            globalBlockCooldownUntilMs.set(
                                android.os.SystemClock.elapsedRealtime() + 15_000L
                            )
                        }
                    }
                }

                val isClientSpecific = sig == YtmBlockSignal.ClientDeprecated ||
                    sig == YtmBlockSignal.SabrEnforced ||
                    sig == YtmBlockSignal.SignatureDecipherFailed
                if (sig == YtmBlockSignal.SabrEnforced) {
                    SabrDemotionStore.markSabrEnforced(client)
                }
                return AttemptResult.Failure(sig, isClientSpecific = isClientSpecific)
            }
        }

        val trackType = ClientWinnerStore.TRACK_TYPE_MUSIC
        val winnerStore = ClientWinnerStore.getInstance(context)

        // Authenticated cold-start datasyncId bootstrap
        if (cookieStore.isSessionValid() && PoTokenManager.dataSyncId.isEmpty()) {
            val now = android.os.SystemClock.elapsedRealtime()
            val last = lastDataSyncBootstrapMs.get()
            // FIX #21: Atomic check-and-set for datasync bootstrap
            if (now - last > DATASYNC_BOOTSTRAP_INTERVAL_MS && lastDataSyncBootstrapMs.compareAndSet(last, now)) {
                val bootstrapped = attemptClient(ClientType.WEB_REMIX, ignoreShortCircuit = true)
                // FIX #3 & #14: Comprehensive handling of AttemptResult in datasync bootstrap
                when (bootstrapped) {
                    is AttemptResult.Success -> {
                        winnerStore.recordWinningClient(trackType, ClientType.WEB_REMIX)
                        consecutiveEgressBlocks.set(0)
                        globalBlockCooldownUntilMs.set(0L)
                        globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                        return bootstrapped.payload
                    }
                    is AttemptResult.Failure -> {
                        if (bootstrapped.isClientSpecific) {
                            winnerStore.recordFailure(trackType, ClientType.WEB_REMIX)
                        }
                        // FIX #11: Differentiate bootstrap retry cooldown by failure signal
                        val backoffMs = when (bootstrapped.signal) {
                            YtmBlockSignal.RateLimited -> 60_000L
                            YtmBlockSignal.NetworkUnavailable -> 10_000L
                            else -> 30_000L
                        }
                        lastDataSyncBootstrapMs.set(now - DATASYNC_BOOTSTRAP_INTERVAL_MS + backoffMs)
                    }
                    is AttemptResult.Interrupted -> {
                        Thread.currentThread().interrupt()
                        lastDataSyncBootstrapMs.set(now - DATASYNC_BOOTSTRAP_INTERVAL_MS + 5_000L)
                        throw InnertubeException(
                            signal = YtmBlockSignal.NetworkUnavailable,
                            message = "Stream resolution interrupted during datasync bootstrap for $videoId",
                            traceId = traceId
                        )
                    }
                    is AttemptResult.ShortCircuited -> {
                        shortCircuit.get()?.let { throw it }
                    }
                }
            }
        }

        fun tryPoTokenRecovery(): Map<String, Any?>? {
            val sc = shortCircuit.get()
            val recoverySignal = sc?.signal ?: lastSignalRef.get()
            val tokenStale = PoTokenManager.isExpired() || PoTokenManager.isLimitedMode
            if (recoverySignal == YtmBlockSignal.PoTokenInvalid ||
                (recoverySignal == YtmBlockSignal.BotChallenge && tokenStale)) {
                val refreshed = runCatching { PoTokenManager.ensureReadySync() }.getOrDefault(false)
                if (refreshed && !PoTokenManager.isLimitedMode) {
                    Log.i(TAG, "[$traceId] PoToken refreshed, retrying WEB_REMIX...")
                    val webRes = attemptClient(ClientType.WEB_REMIX, ignoreShortCircuit = true)
                    // FIX #4: Abort on Interrupted in recovery
                    if (webRes is AttemptResult.Interrupted) {
                        Thread.currentThread().interrupt()
                        throw InnertubeException(
                            signal = YtmBlockSignal.NetworkUnavailable,
                            message = "Stream resolution interrupted during PoToken recovery for $videoId",
                            traceId = traceId
                        )
                    }
                    if (webRes is AttemptResult.Success) {
                        shortCircuit.set(null) // clear short-circuit on recovery
                        winnerStore.recordWinningClient(trackType, ClientType.WEB_REMIX)
                        consecutiveEgressBlocks.set(0)
                        globalBlockCooldownUntilMs.set(0L)
                        globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                        return webRes.payload
                    }
                    // FIX #10: Skip subsequent recovery attempt if failure is NetworkUnavailable or RateLimited
                    if (webRes is AttemptResult.Failure &&
                        (webRes.signal == YtmBlockSignal.NetworkUnavailable ||
                         webRes.signal == YtmBlockSignal.RateLimited)) {
                        Log.d(TAG, "[$traceId] WEB_REMIX recovery failed with ${webRes.signal}; skipping Android client retry")
                        return null
                    }

                    Log.i(TAG, "[$traceId] WEB_REMIX retry failed, retrying ANDROID_MUSIC with fresh poToken...")
                    val androidRes = attemptClient(ClientType.ANDROID_MUSIC, ignoreShortCircuit = true)
                    // FIX #4: Abort on Interrupted in recovery
                    if (androidRes is AttemptResult.Interrupted) {
                        Thread.currentThread().interrupt()
                        throw InnertubeException(
                            signal = YtmBlockSignal.NetworkUnavailable,
                            message = "Stream resolution interrupted during PoToken recovery for $videoId",
                            traceId = traceId
                        )
                    }
                    if (androidRes is AttemptResult.Success) {
                        shortCircuit.set(null) // clear short-circuit on recovery
                        winnerStore.recordWinningClient(trackType, ClientType.ANDROID_MUSIC)
                        consecutiveEgressBlocks.set(0)
                        globalBlockCooldownUntilMs.set(0L)
                        globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                        return androidRes.payload
                    }
                }
            }
            return null
        }

        val candidate1 = clientChain.firstOrNull()
        val candidate2 = clientChain.getOrNull(1)

        val completionService = ExecutorCompletionService<Pair<ClientType, AttemptResult>>(streamResolverPool)

        fun submitCandidate(client: ClientType): Future<Pair<ClientType, AttemptResult>>? {
            return try {
                val future = completionService.submit(Callable {
                    val res = attemptClient(client)
                    client to res
                })
                activeFutures.add(future)
                future
            } catch (e: java.util.concurrent.RejectedExecutionException) {
                Log.w(TAG, "Stream resolver pool rejected candidate ${client.name}", e)
                null
            }
        }

        if (Thread.currentThread().isInterrupted) {
            throw InnertubeException(
                signal = YtmBlockSignal.NetworkUnavailable,
                message = "Stream resolution interrupted before start for $videoId",
                traceId = traceId
            )
        }

        var candidate1Submitted = false
        if (candidate1 != null) {
            candidate1Submitted = submitCandidate(candidate1) != null
        }

        // Wait up to HEDGE_DELAY_MS (350 ms) for candidate 1 via completionService.poll
        if (candidate1Submitted) {
            try {
                val completedFuture = completionService.poll(HEDGE_DELAY_MS, TimeUnit.MILLISECONDS)
                if (completedFuture != null) {
                    activeFutures.remove(completedFuture)
                    val (client, res) = completedFuture.get()
                    when (res) {
                        is AttemptResult.Success -> {
                            // FIX #5: Cleanly cancel all in-flight calls on success
                            cancelAll()
                            winnerStore.recordWinningClient(trackType, client)
                            consecutiveEgressBlocks.set(0)
                            globalBlockCooldownUntilMs.set(0L)
                            globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                            return res.payload
                        }
                        is AttemptResult.Failure -> {
                            if (res.isClientSpecific) {
                                winnerStore.recordFailure(trackType, client)
                            }
                        }
                        is AttemptResult.Interrupted -> {
                            cancelAll()
                            throw InnertubeException(
                                signal = YtmBlockSignal.NetworkUnavailable,
                                message = "Stream resolution interrupted for video $videoId",
                                traceId = traceId
                            )
                        }
                        is AttemptResult.ShortCircuited -> {}
                    }
                }
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                cancelAll()
                throw InnertubeException(
                    signal = YtmBlockSignal.NetworkUnavailable,
                    message = "Stream resolution interrupted during hedge delay for $videoId",
                    traceId = traceId
                )
            } catch (e: CancellationException) {
                // FIX #5: Catch CancellationException explicitly around Future.get()
                Log.d(TAG, "[$traceId] Candidate 1 was canceled: ${e.message}")
            } catch (e: ExecutionException) {
                val cause = e.cause
                if (cause is VirtualMachineError || cause is ThreadDeath) {
                    throw cause
                }
                Log.w(TAG, "Candidate 1 execution threw: ${cause?.message}")
            }
        }

        shortCircuit.get()?.let { cancelAll(); throw it }

        if (Thread.currentThread().isInterrupted) {
            cancelAll()
            throw InnertubeException(
                signal = YtmBlockSignal.NetworkUnavailable,
                message = "Stream resolution interrupted before launching candidate 2 for $videoId",
                traceId = traceId
            )
        }

        // Hedged race: launch candidate 2 if candidate 1 did not complete in hedge window
        if (candidate2 != null) {
            submitCandidate(candidate2)
        }

        // Race remaining active candidates using completionService.poll with remaining timeout
        val hedgeRaceDeadline = android.os.SystemClock.elapsedRealtime() + HEDGE_RACE_TIMEOUT_MS
        while (activeFutures.isNotEmpty()) {
            val remainingMs = hedgeRaceDeadline - android.os.SystemClock.elapsedRealtime()
            if (remainingMs <= 0) break

            try {
                val completed = completionService.poll(remainingMs, TimeUnit.MILLISECONDS) ?: break
                activeFutures.remove(completed)
                val (client, res) = completed.get()
                when (res) {
                    is AttemptResult.Success -> {
                        // FIX #5: Cleanly cancel all in-flight calls on success
                        cancelAll()
                        winnerStore.recordWinningClient(trackType, client)
                        consecutiveEgressBlocks.set(0)
                        globalBlockCooldownUntilMs.set(0L)
                        globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                        return res.payload
                    }
                    is AttemptResult.Failure -> {
                        if (res.isClientSpecific) {
                            winnerStore.recordFailure(trackType, client)
                        }
                    }
                    is AttemptResult.Interrupted -> {
                        cancelAll()
                        throw InnertubeException(
                            signal = YtmBlockSignal.NetworkUnavailable,
                            message = "Stream resolution interrupted for video $videoId",
                            traceId = traceId
                        )
                    }
                    is AttemptResult.ShortCircuited -> {}
                }
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                cancelAll()
                throw InnertubeException(
                    signal = YtmBlockSignal.NetworkUnavailable,
                    message = "Stream resolution interrupted during hedged race for $videoId",
                    traceId = traceId
                )
            } catch (e: CancellationException) {
                // FIX #5: Catch CancellationException explicitly around Future.get()
                Log.d(TAG, "[$traceId] Candidate future was canceled during race: ${e.message}")
            } catch (e: ExecutionException) {
                val cause = e.cause
                if (cause is VirtualMachineError || cause is ThreadDeath) {
                    throw cause
                }
                Log.w(TAG, "Candidate execution threw in race: ${cause?.message}")
            }

            shortCircuit.get()?.let { cancelAll(); throw it }
        }

        // Race timed out or candidates finished: cancel any remaining in-flight calls
        cancelAll()

        shortCircuit.get()?.let { sc ->
            if (sc.signal == YtmBlockSignal.BotChallenge || sc.signal == YtmBlockSignal.PoTokenInvalid) {
                tryPoTokenRecovery()?.let { return it }
            }
            throw sc
        }

        if (Thread.currentThread().isInterrupted) {
            throw InnertubeException(
                signal = YtmBlockSignal.NetworkUnavailable,
                message = "Stream resolution interrupted before sequential fallback for $videoId",
                traceId = traceId
            )
        }

        // Fallback: sequential check on remaining candidates in chain
        val remainingClients = clientChain.drop(2)
        for (client in remainingClients) {
            if (Thread.currentThread().isInterrupted) {
                throw InnertubeException(
                    signal = YtmBlockSignal.NetworkUnavailable,
                    message = "Stream resolution interrupted during sequential fallback for $videoId",
                    traceId = traceId
                )
            }

            val res = attemptClient(client)
            when (res) {
                is AttemptResult.Success -> {
                    winnerStore.recordWinningClient(trackType, client)
                    consecutiveEgressBlocks.set(0)
                    globalBlockCooldownUntilMs.set(0L)
                    globalBlockSignal.set(YtmBlockSignal.BotChallenge)
                    return res.payload
                }
                is AttemptResult.Failure -> {
                    if (res.isClientSpecific) {
                        winnerStore.recordFailure(trackType, client)
                    }
                }
                is AttemptResult.Interrupted -> {
                    throw InnertubeException(
                        signal = YtmBlockSignal.NetworkUnavailable,
                        message = "Stream resolution interrupted during sequential fallback for $videoId",
                        traceId = traceId
                    )
                }
                is AttemptResult.ShortCircuited -> {}
            }

            shortCircuit.get()?.let { sc ->
                if (sc.signal == YtmBlockSignal.BotChallenge || sc.signal == YtmBlockSignal.PoTokenInvalid) {
                    tryPoTokenRecovery()?.let { return it }
                }
                throw sc
            }
        }

        tryPoTokenRecovery()?.let { return it }

        // FIX #3: Respect any short-circuit triggered by the final recovery attempt
        shortCircuit.get()?.let { throw it }

        val finalSignal = lastSignalRef.get() ?: YtmBlockSignal.NetworkUnavailable
        throw InnertubeException(
            signal = finalSignal,
            message = "All Innertube client fallback resolutions failed for video $videoId",
            traceId = traceId,
            cause = lastExceptionRef.get()
        )
    }

    private fun extractUrlFromFormat(format: JSONObject): String? {
        val directUrl = format.optString("url")
        if (directUrl.isNotEmpty()) {
            return applyNTransformIfNeeded(directUrl)
        }

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
                    var resolved = if (sig != null) {
                        val decipherCache = JsDecipherCache.getInstance(context)
                        val deciphered = decipherCache.decipherSignature(sig)
                        val separator = if (rawUrl.contains("?")) "&" else "?"
                        "$rawUrl$separator$sigParam=${URLEncoder.encode(deciphered, "UTF-8")}"
                    } else {
                        rawUrl
                    }
                    resolved = applyNTransformIfNeeded(resolved)
                    resolved
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
     * FIX #9: Surgically replaces only the 'n' parameter in the query string with boundary anchoring,
     * preserving parameter order, other parameters, and percent-encoding.
     */
    private fun applyNTransformIfNeeded(url: String): String {
        return try {
            val uri = Uri.parse(url)
            val n = uri.getQueryParameter("n") ?: return url
            if (n.isEmpty()) return url
            val cache = JsDecipherCache.getInstance(context)
            val transformed = cache.decipherN(n)
            // FIX #4: Guard against empty or unchanged transformed n
            if (transformed.isNullOrEmpty() || transformed == n) return url

            val encodedOld = URLEncoder.encode(n, "UTF-8")
            val encodedNew = URLEncoder.encode(transformed, "UTF-8")

            // FIX #9: Anchor boundaries ([?&] ... (?=&|$)) so other params containing "n=" are not replaced
            val patternExact = Regex("([?&])n=${Regex.escape(n)}(?=&|$)")
            val patternEncoded = Regex("([?&])n=${Regex.escape(encodedOld)}(?=&|$)")

            when {
                patternExact.containsMatchIn(url) -> patternExact.replaceFirst(url, "$1n=$encodedNew")
                patternEncoded.containsMatchIn(url) -> patternEncoded.replaceFirst(url, "$1n=$encodedNew")
                else -> {
                    uri.buildUpon().clearQuery().apply {
                        for (name in uri.queryParameterNames) {
                            if (name == "n") appendQueryParameter("n", transformed)
                            else uri.getQueryParameters(name).forEach { appendQueryParameter(name, it) }
                        }
                    }.build().toString()
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "n-transform failed: ${t.message}")
            url
        }
    }

    private fun safeBitrate(format: JSONObject): Int {
        val b = format.optInt("bitrate", 0)
        if (b > 0) return b
        val avgB = format.optInt("averageBitrate", 0)
        if (avgB > 0) return avgB
        return when (format.optInt("itag", 0)) {
            251 -> 160000
            140 -> 128000
            139, 250 -> 70000
            249 -> 50000
            else -> 128000
        }
    }

    private fun extractBestArtworkUrl(videoDetails: JSONObject?): String? {
        val thumbnails = videoDetails?.optJSONObject("thumbnail")?.optJSONArray("thumbnails") ?: return null
        if (thumbnails.length() == 0) return null
        var maxW = 0
        var bestUrl: String? = null
        for (i in 0 until thumbnails.length()) {
            val t = thumbnails.optJSONObject(i) ?: continue
            val w = t.optInt("width", 0)
            val u = t.optString("url")
            if (w >= maxW && u.isNotEmpty()) {
                maxW = w
                bestUrl = u
            }
        }
        return bestUrl
    }

    private fun parseUrlExpiryEpochSeconds(url: String): Long? = runCatching {
        Uri.parse(url).getQueryParameter("expire")?.toLongOrNull()
    }.getOrNull()

    fun requestPlayer(
        videoId: String,
        clientType: ClientType,
        activeCalls: ConcurrentHashMap<ClientType, CopyOnWriteArrayList<okhttp3.Call>>? = null
    ): JSONObject {
        val endpoint = "${clientType.endpointHost}/youtubei/v1/player?prettyPrint=false&key=$API_KEY"
        val payload = buildPlayerBody(videoId, clientType)
        return postWithRetry(endpoint, payload, clientType, RateLimiter.Bucket.PLAYER, maxAttempts = 2, activeCalls = activeCalls)
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

    private fun addActiveCall(
        activeCalls: ConcurrentHashMap<ClientType, CopyOnWriteArrayList<okhttp3.Call>>?,
        clientType: ClientType,
        call: okhttp3.Call
    ) {
        if (activeCalls == null) return
        synchronized(activeCalls) {
            val list = activeCalls[clientType]
                ?: CopyOnWriteArrayList<okhttp3.Call>().also {
                    activeCalls[clientType] = it
                }
            list.add(call)
        }
    }

    private fun removeActiveCall(
        activeCalls: ConcurrentHashMap<ClientType, CopyOnWriteArrayList<okhttp3.Call>>?,
        clientType: ClientType,
        call: okhttp3.Call
    ) {
        if (activeCalls == null) return
        synchronized(activeCalls) {
            activeCalls[clientType]?.let { list ->
                list.remove(call)
                if (list.isEmpty()) {
                    activeCalls.remove(clientType)
                }
            }
        }
    }

    private fun postWithRetry(
        urlStr: String,
        body: JSONObject,
        clientType: ClientType,
        bucket: RateLimiter.Bucket,
        maxAttempts: Int = 3,
        activeCalls: ConcurrentHashMap<ClientType, CopyOnWriteArrayList<okhttp3.Call>>? = null,
    ): JSONObject {
        var lastError: Exception? = null
        val traceId = UUID.randomUUID().toString()
        var sleepAfterAttemptMs = 0L

        for (attempt in 0 until maxAttempts) {
            // FIX #6: Check interruption at the start of every attempt
            if (Thread.currentThread().isInterrupted) {
                lastError = IOException("Innertube request interrupted before attempt $attempt for ${clientType.name}")
                break
            }

            if (sleepAfterAttemptMs > 0) {
                try {
                    Thread.sleep(sleepAfterAttemptMs)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    lastError = IOException("Sleep interrupted between attempts for ${clientType.name}")
                    break
                }
                sleepAfterAttemptMs = 0L
            }

            if (!rateLimiter.acquirePermit(bucket)) {
                if (Thread.currentThread().isInterrupted) {
                    lastError = IOException("Rate limiter wait interrupted for ${clientType.name}")
                } else {
                    lastError = InnertubeException(
                        signal = YtmBlockSignal.RateLimited,
                        message = "Rate limiter permit acquisition timed out for ${clientType.name}",
                        traceId = traceId
                    )
                }
                break
            }

            var call: okhttp3.Call? = null
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

                val rollout = PoTokenManager.rolloutToken
                if (clientType.isWeb && rollout.isNotEmpty()) {
                    reqBuilder.header("X-Goog-RolloutToken", rollout)
                }

                val authedWeb = clientType.acceptsSessionAuth && cookieStore.isSessionValid()
                val visitorData = if (authedWeb) {
                    PoTokenManager.sessionVisitorData
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
                } else {
                    reqBuilder.header("X-Origin", clientType.endpointHost)
                }

                if (authedWeb) {
                    val cookieHeader = cookieStore.getMergedCookieHeader(clientType.endpointHost)
                    if (!cookieHeader.isNullOrEmpty()) {
                        reqBuilder.header("Cookie", cookieHeader)
                        // FIX #1: Only send x-goog-authuser when auth cookies are actually present
                        reqBuilder.header("x-goog-authuser", "0")

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

                // FIX #3 & #12: Thread-safe tracking in activeCalls list per ClientType
                val builtCall = YtmHttpClient.okHttpClient.newCall(reqBuilder.build())
                call = builtCall
                addActiveCall(activeCalls, clientType, builtCall)

                val response = builtCall.execute()
                val code = response.code

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
                    lastError = InnertubeException(
                        signal = YtmBlockSignal.RateLimited,
                        message = "HTTP 429 Rate limited from ${clientType.name}",
                        traceId = traceId
                    )
                    response.close()
                    sleepAfterAttemptMs = backoff
                    continue
                }

                if (code == 403) {
                    ProxyManager.onPathFailed(urlStr)
                }

                if (code in 500..599) {
                    Log.w(TAG, "[$traceId] Server error ($code) on attempt $attempt. Retrying...")
                    // FIX #15: Set server error message in lastError
                    lastError = IOException("HTTP $code server error from ${clientType.name}")
                    response.close()
                    val sleepMs = (1000L shl attempt) + (0..500).random()
                    sleepAfterAttemptMs = sleepMs
                    continue
                }

                val responseStr = response.body?.string() ?: ""

                if (code !in 200..299) {
                    val signal = YtmBlockSignal.parse(code, responseStr)
                    val truncated = responseStr.take(300)
                    Log.w(TAG, "[$traceId] Innertube (${clientType.name}) non-200 ($code) -> $signal: $truncated")
                    throw InnertubeException(signal, "HTTP error $code ($signal): $truncated", traceId)
                }

                // FIX #13 & #16: Parse JSON before reporting success; handle JSON parse errors explicitly
                val parsed = JSONObject(responseStr)
                rateLimiter.onSuccess()
                ProxyManager.onPathSuccess()
                harvestSessionState(parsed, clientType)
                return parsed
            } catch (e: InnertubeException) {
                // FIX #2: Fail fast on egress/terminal blocks so short-circuit trips immediately
                if (
                    e.signal == YtmBlockSignal.SignInRequired ||
                    e.signal == YtmBlockSignal.VideoGone ||
                    e.signal == YtmBlockSignal.BotChallenge ||
                    e.signal == YtmBlockSignal.IpBlocked ||
                    e.signal == YtmBlockSignal.PoTokenInvalid ||
                    e.signal == YtmBlockSignal.ClientDeprecated ||
                    e.signal == YtmBlockSignal.SabrEnforced ||
                    e.signal == YtmBlockSignal.SignatureDecipherFailed ||
                    e.signal == YtmBlockSignal.GeoBlocked
                ) {
                    throw e
                }
                lastError = e
            } catch (e: UnknownHostException) {
                ProxyManager.onPathFailed(urlStr)
                val host = Uri.parse(urlStr).host
                if (host != null) {
                    val dohResolved = runCatching { DnsOverHttpsResolver.resolve(host) }
                        .onFailure { Log.w(TAG, "[$traceId] DoH resolution failed for $host: ${it.message}") }
                        .getOrNull()
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
                // FIX #6: Abort retries if thread was interrupted or call was explicitly canceled
                if (Thread.currentThread().isInterrupted || call?.isCanceled() == true) {
                    break
                }
                Log.w(TAG, "[$traceId] Network error on attempt $attempt for ${clientType.name}: ${e.message}")
            } catch (e: JSONException) {
                // FIX #1: JSON parse errors indicate response malformation, not client deprecation
                lastError = e
                Log.e(TAG, "[$traceId] Malformed JSON in response from ${clientType.name}: ${e.message}")
                break
            } catch (e: Exception) {
                lastError = e
                Log.e(TAG, "[$traceId] Unexpected error in Innertube post: ${e.message}", e)
            } finally {
                // FIX #8 & #12: Safe cleanup in finally to prevent masking exceptions
                if (call != null) {
                    runCatching { removeActiveCall(activeCalls, clientType, call) }
                }
                runCatching { rateLimiter.releasePermit() }
            }
        }

        // FIX #1 & #7: Classify terminal signal accurately (JSONException -> NetworkUnavailable)
        val terminalSignal = when (val err = lastError) {
            is InnertubeException -> err.signal
            is JSONException -> YtmBlockSignal.NetworkUnavailable
            is UnknownHostException,
            is java.net.ConnectException,
            is java.net.NoRouteToHostException,
            is java.net.SocketTimeoutException,
            is javax.net.ssl.SSLException -> YtmBlockSignal.NetworkUnavailable
            is IOException -> YtmBlockSignal.NetworkUnavailable
            else -> YtmBlockSignal.NetworkUnavailable
        }

        throw InnertubeException(
            signal = terminalSignal,
            message = "Innertube request failed after $maxAttempts attempts for ${clientType.name}",
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
        val sts = runCatching { JsDecipherCache.getInstance(context).getSignatureTimestamp() }.getOrNull()
            ?: runCatching { PlayerJavaScript.signatureTimestamp() }.getOrNull()
        val contentPlaybackContext = JSONObject().apply {
            put("html5Preference", "HTML5_PREF_WANTS")
            if (sts != null) put("signatureTimestamp", sts)
        }
        playbackContext.put("contentPlaybackContext", contentPlaybackContext)
        if (sts != null) {
            try { playbackContext.put("signatureTimestamp", sts) } catch (_: Throwable) {}
        }
        root.put("playbackContext", playbackContext)

        val requiresPo = clientType.isWeb || ClientCapabilityMatrix.getCapability(clientType).requiresPoToken
        if (requiresPo) {
            val hasPo = PoTokenManager.isReady ||
                (!PoTokenManager.webViewBroken && !PoTokenManager.isLimitedMode && PoTokenManager.ensureReadySync())
            if (hasPo) {
                val dataSyncId = PoTokenManager.dataSyncId
                val isAuthed = clientType.acceptsSessionAuth && cookieStore.isSessionValid()
                val poToken = if (isAuthed) {
                    if (dataSyncId.isNotEmpty()) {
                        PoTokenManager.accountPoTokenForSync(dataSyncId)
                    } else {
                        ""
                    }
                } else {
                    PoTokenManager.poTokenForSync(videoId)
                }
                if (poToken.isNotEmpty()) {
                    if (clientType.isWeb) {
                        root.put(
                            "serviceIntegrityDimensions",
                            JSONObject().put("poToken", poToken),
                        )
                    }
                    contentPlaybackContext.put("poToken", poToken)
                    Log.d(TAG, "[$clientType] Attached player poToken (len=${poToken.length}, video=$videoId, isWeb=${clientType.isWeb})")
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
                    put("osName", "Android")
                    put("osVersion", "9")
                    put("platform", "MOBILE")
                }
                ClientType.MWEB -> {
                    put("platform", "MOBILE")
                    put("clientFormFactor", "SMALL_FORM_FACTOR")
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
        const val HEDGE_RACE_TIMEOUT_MS = 3000L
        private const val DATASYNC_BOOTSTRAP_INTERVAL_MS = 300_000L

        private val lastBotRefreshTriggerMs = AtomicLong(0L)
        private val lastDataSyncBootstrapMs = AtomicLong(0L)

        private val globalBlockCooldownUntilMs = AtomicLong(0L)
        private val consecutiveEgressBlocks = AtomicInteger(0)
        private val globalBlockSignal = AtomicReference(YtmBlockSignal.BotChallenge)

        private val threadCounter = AtomicInteger(0)

        // FIX #6 & #20: Recreatable dedicated executor for non-blocking pre-connect
        @Volatile
        private var _preConnectExecutor: java.util.concurrent.ExecutorService? = null
        val preConnectExecutor: java.util.concurrent.ExecutorService
            get() {
                val existing = _preConnectExecutor
                if (existing != null && !existing.isShutdown && !existing.isTerminated) return existing
                synchronized(this) {
                    val existing2 = _preConnectExecutor
                    if (existing2 != null && !existing2.isShutdown && !existing2.isTerminated) return existing2
                    val newExecutor = Executors.newFixedThreadPool(2) { r ->
                        Thread(r).apply {
                            isDaemon = true
                            name = "InnertubePreConnect-${threadCounter.incrementAndGet()}"
                        }
                    }
                    _preConnectExecutor = newExecutor
                    return newExecutor
                }
            }

        val API_KEY: String = YtmConfig.getYtmApiKey()
        @Volatile
        private var _streamResolverPool: java.util.concurrent.ExecutorService? = null
        val streamResolverPool: java.util.concurrent.ExecutorService
            get() {
                val existing = _streamResolverPool
                if (existing != null && !existing.isShutdown && !existing.isTerminated) return existing
                synchronized(this) {
                    val existing2 = _streamResolverPool
                    if (existing2 != null && !existing2.isShutdown && !existing2.isTerminated) return existing2
                    val newPool = Executors.newFixedThreadPool(6) { r ->
                        Thread(r).apply {
                            isDaemon = true
                            name = "InnertubeStream-${threadCounter.incrementAndGet()}"
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
            try {
                _preConnectExecutor?.shutdownNow()
            } catch (_: Exception) {}
            _streamResolverPool = null
            _preConnectExecutor = null
        }
    }
}
