package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LruCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.services.youtube.InnertubeClientRequestInfo
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import java.time.Instant

/**
 * Phase 3 — Layer 3: Singleton PoToken Lifecycle Manager with Hardened VisitorData Binding
 * and Persistent Store Integration.
 *
 * Latency Optimization (Tasks 0 & 1):
 * - Persists valid poTokens via [PoTokenStore] across app launches (eliminates 4-8s cold cost)
 * - Pre-warms BotGuard WebView at app start behind ENABLE_YTM
 * - Keeps the [PoTokenWebView] generator warm in memory after first init
 * - Triggers non-blocking background refresh ~30 min before expiry
 * - On mid-session 403 / BotChallenge: immediately triggers background refresh while current
 *   playback falls back to unblocked or no-poToken clients, never blocking the audio stream.
 */
object PoTokenManager {
    private const val TAG = "PoTokenManager"

    private const val LRU_CAPACITY = 64
    private const val TOKEN_TTL_SECONDS = 1800L // 30 minutes
    private const val WEBVIEW_BROKEN_COOLDOWN_SECONDS = 1800L // 30 minutes
    private const val BACKGROUND_REFRESH_INTERVAL_MS = 60_000L
    const val EXPIRING_SOON_MARGIN_SECONDS = PoTokenStore.REFRESH_MARGIN_SECONDS // 30 minutes

    @Volatile
    var visitorData: String = ""
        private set

    @Volatile
    var integrityToken: String = ""
        private set

    @Volatile
    var expiryInstant: Long = 0L
        private set

    @Volatile
    var streamingPoToken: String = ""
        private set

    @Volatile
    var dataSyncId: String = ""
        private set

    @Volatile
    var sessionVisitorData: String = ""
        private set

    // A broken WebView is rarely permanent — an OOM-killed WebView provider or a
    // single BadWebViewException used to latch limited mode for the whole process
    // lifetime, silently downgrading every later resolution. Time-box it instead.
    @Volatile
    private var webViewBrokenUntil: Long = 0L

    val webViewBroken: Boolean
        get() = webViewBrokenUntil > Instant.now().epochSecond

    val isLimitedMode: Boolean
        get() = webViewBroken || (isExpired() && visitorData.isEmpty())

    @Volatile
    private var generator: PoTokenGenerator? = null

    /** A non-null generator that is also still able to mint. */
    private val hasWarmGenerator: Boolean
        get() = generator?.isExpired() == false

    private var appContext: Context? = null
    private val managerScope = CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)
    private val stateMutex = Mutex()
    private var refreshInFlight: kotlinx.coroutines.Deferred<Boolean>? = null
    private val lastBackgroundRefreshMs = java.util.concurrent.atomic.AtomicLong(0L)

    private data class CachedToken(
        val token: String,
        val visitorDataBound: String,
        val timestamp: Long
    )
    private val tokenLru = LruCache<String, CachedToken>(LRU_CAPACITY)

    fun init(context: Context) {
        if (appContext == null) {
            val app = context.applicationContext
            appContext = app
            val stored = PoTokenStore.loadTokenData(app)
            if (stored.streamingPoToken.isNotEmpty() && stored.visitorData.isNotEmpty()) {
                visitorData = stored.visitorData
                integrityToken = stored.integrityToken
                streamingPoToken = stored.streamingPoToken
                dataSyncId = stored.dataSyncId
                expiryInstant = stored.expiryInstant
                synchronized(tokenLru) {
                    tokenLru.put(visitorData, CachedToken(streamingPoToken, visitorData, stored.generatedAt))
                }
                Log.d(TAG, "Loaded valid poToken from persistent store (valid until epoch $expiryInstant)")
            }
        }
    }

    val isReady: Boolean
        get() = visitorData.isNotEmpty() && streamingPoToken.isNotEmpty() && !isExpired()

    fun isExpired(): Boolean {
        val now = Instant.now().epochSecond
        return expiryInstant <= now
    }

    fun isExpiringSoon(): Boolean {
        val now = Instant.now().epochSecond
        return (expiryInstant - now) <= EXPIRING_SOON_MARGIN_SECONDS
    }

    fun isTtlCritical(): Boolean {
        val now = Instant.now().epochSecond
        val totalLifetime = PoTokenStore.DEFAULT_TTL_SECONDS
        val remaining = expiryInstant - now
        return remaining > 0 && remaining < (totalLifetime * 0.20)
    }

    /**
     * Pre-warms BotGuard WebView in background at app launch before user initiates first request.
     * Off the critical path: resolution uses stored token immediately without waiting for this.
     */
    fun preWarm(context: Context) {
        init(context)
        managerScope.launch {
            try {
                if (isExpired() || isExpiringSoon() || !hasWarmGenerator) {
                    ensureReady()
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Pre-warm failed non-fatally: ${t.message}")
            }
        }
    }

    /**
     * Triggered periodically when a YTM screen is visible to refresh when TTL < 20%.
     */
    fun checkAndRefreshVisibleScreen() {
        if (isTtlCritical() && !webViewBroken) {
            managerScope.launch {
                runCatching { ensureReady() }
            }
        }
    }

    /**
     * Non-blocking background regeneration triggered on 403 or invalidation signal.
     *
     * Throttled: `poTokenForSync` calls this on every request that has a usable
     * stored token but no warm generator, which for a cold start is every track in
     * the queue. Each call spawned a coroutine that raced for the same lock and
     * re-ran the same two network round trips. [invalidate] resets the throttle so
     * an explicit invalidation is never swallowed.
     */
    fun triggerBackgroundRefresh() {
        if (appContext == null) return
        val now = android.os.SystemClock.elapsedRealtime()
        val last = lastBackgroundRefreshMs.get()
        if (last != 0L && (now - last) < BACKGROUND_REFRESH_INTERVAL_MS) return
        if (!lastBackgroundRefreshMs.compareAndSet(last, now)) return
        Log.i(TAG, "Triggering non-blocking background PoToken regeneration")
        managerScope.launch {
            try {
                ensureReady()
            } catch (t: Throwable) {
                Log.e(TAG, "Background PoToken regeneration failed: ${t.message}", t)
            }
        }
    }

    /**
     * Ensures attestation state and generator are ready.
     */
    suspend fun ensureReady(): Boolean = withContext(Dispatchers.IO) {
        if (webViewBroken) {
            return@withContext visitorData.isNotEmpty()
        }

        if (isReady && !isExpiringSoon() && hasWarmGenerator) {
            return@withContext true
        }

        stateMutex.withLock {
            if (isReady && !isExpiringSoon() && hasWarmGenerator) {
                return@withContext true
            }

            refreshInFlight?.let { existing ->
                return@withContext try {
                    existing.await()
                } catch (_: Throwable) {
                    visitorData.isNotEmpty()
                }
            }

            val deferred = managerScope.async {
                try {
                    refreshInternal()
                    true
                } catch (e: BadWebViewException) {
                    Log.e(TAG, "System WebView is broken for BotGuard: ${e.message}", e)
                    webViewBrokenUntil = Instant.now().epochSecond + WEBVIEW_BROKEN_COOLDOWN_SECONDS
                    visitorData.isNotEmpty()
                } catch (t: Throwable) {
                    Log.e(TAG, "Failed to ensure PoToken readiness: ${t.message}", t)
                    visitorData.isNotEmpty()
                }
            }
            refreshInFlight = deferred
            try {
                deferred.await()
            } finally {
                refreshInFlight = null
            }
        }
    }

    fun ensureReadySync(): Boolean {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            Log.w(TAG, "ensureReadySync called on main thread; refusing to block")
            return isReady || visitorData.isNotEmpty()
        }
        if (webViewBroken) return visitorData.isNotEmpty()
        if (isReady && !isExpiringSoon() && hasWarmGenerator) return true

        return kotlinx.coroutines.runBlocking(Dispatchers.IO) {
            ensureReady()
        }
    }

    /**
     * Generates or retrieves a cached poToken bound to [identifier] — the
     * `visitorData` for a guest request, the `datasyncId` for a signed-in one.
     *
     * Never blocks critical-path playback if a token is already cached or stored.
     */
    fun poTokenForSync(identifier: String): String {
        val currentVisitor = visitorData
        val now = Instant.now().epochSecond

        // 1. In-memory LRU cache
        synchronized(tokenLru) {
            val cached = tokenLru.get(identifier)
            if (cached != null && cached.visitorDataBound == currentVisitor && (now - cached.timestamp) < TOKEN_TTL_SECONDS) {
                return cached.token
            }
        }

        // 2. Direct streaming poToken shortcut (fast path for player requests)
        if (identifier == currentVisitor && streamingPoToken.isNotEmpty() && !isExpired()) {
            return streamingPoToken
        }

        // 3. If WebView is broken, fallback to last streaming token
        if (webViewBroken) {
            return fallbackTokenFor(identifier)
        }

        // 4. Use existing warm generator if available
        val gen = generator
        if (gen != null && !gen.isExpired()) {
            return try {
                val minted = gen.generatePoToken(identifier)
                synchronized(tokenLru) {
                    tokenLru.put(identifier, CachedToken(minted, visitorData, Instant.now().epochSecond))
                }
                minted
            } catch (t: Throwable) {
                Log.w(TAG, "Minting poToken failed with warm generator: ${t.message}", t)
                fallbackTokenFor(identifier)
            }
        }

        // 5. If we have a valid stored streaming token, return it and warm generator
        //    in the background. Only for the guest case: the stored token is bound
        //    to visitorData, so handing it back for a datasyncId identifier ships a
        //    wrong-binding token that YouTube answers with an empty format list.
        //    That made the first signed-in resolve after every cold start fail,
        //    because a cold start has no generator but does have a stored token.
        if (identifier == currentVisitor && streamingPoToken.isNotEmpty() && !isExpired()) {
            triggerBackgroundRefresh()
            return streamingPoToken
        }

        // 6. Cold path fallback: synchronous generation
        ensureReadySync()

        val activeGen = generator
        if (activeGen == null || activeGen.isExpired()) {
            return fallbackTokenFor(identifier)
        }

        return try {
            val minted = activeGen.generatePoToken(identifier)
            synchronized(tokenLru) {
                tokenLru.put(identifier, CachedToken(minted, visitorData, Instant.now().epochSecond))
            }
            minted
        } catch (t: Throwable) {
            Log.w(TAG, "Minting poToken failed for $identifier: ${t.message}", t)
            fallbackTokenFor(identifier)
        }
    }

    /**
     * Best token still available for [identifier] when minting is impossible.
     *
     * A poToken is only valid for the identifier it was minted against, so
     * [streamingPoToken] — always bound to `visitorData` — may only stand in for
     * a guest request. For an account-bound identifier the honest answer is "no
     * token": the caller then sends the request without one, which can still
     * succeed, where a wrong-binding token is rejected every time.
     */
    private fun fallbackTokenFor(identifier: String): String {
        synchronized(tokenLru) {
            val cached = tokenLru.get(identifier)?.token
            if (!cached.isNullOrEmpty()) return cached
        }
        return if (identifier == visitorData) streamingPoToken else ""
    }

    suspend fun poTokenFor(identifier: String): String = withContext(Dispatchers.IO) {
        poTokenForSync(identifier)
    }

    fun setDataSyncId(id: String) {
        val normalized = id.trim()
        if (normalized.isEmpty()) return
        synchronized(tokenLru) {
            if (normalized == dataSyncId) return
            val old = dataSyncId
            dataSyncId = normalized
            appContext?.let { PoTokenStore.saveDataSyncId(it, normalized) }
            if (old.isNotEmpty()) tokenLru.remove(old)
            tokenLru.remove(normalized)
        }
    }

    fun setSessionVisitorData(v: String) {
        val normalized = v.trim()
        if (normalized.isEmpty()) return
        sessionVisitorData = normalized
    }

    fun accountPoTokenForSync(dataSyncId: String): String {
        val id = dataSyncId.trim()
        if (id.isEmpty()) return ""
        return poTokenForSync(id)
    }

    /**
     * Invalidation on BotChallenge or PoTokenInvalid:
     * Drops all tokens, visitorData, and generator so next call mints a completely fresh set.
     *
     * [dataSyncId] survives on purpose: it identifies the signed-in account, not the
     * attestation. Clearing it on every bot challenge left account-bound poTokens
     * unmintable until Dart happened to push the id again, which downgraded a
     * signed-in session to anonymous browsing.
     */
    fun invalidate() {
        val oldGen = generator
        generator = null
        expiryInstant = 0L
        sessionVisitorData = ""
        visitorData = ""
        streamingPoToken = ""
        integrityToken = ""
        webViewBrokenUntil = 0L
        lastBackgroundRefreshMs.set(0L)
        oldGen?.let { Handler(Looper.getMainLooper()).post { it.close() } }
        appContext?.let { PoTokenStore.clearAttestation(it) }
        synchronized(tokenLru) {
            tokenLru.evictAll()
        }
    }

    fun evictMintedTokens() {
        synchronized(tokenLru) {
            tokenLru.evictAll()
        }
    }

    /**
     * Full reset for an explicit disconnect or account switch: drops the
     * attestation *and* the dataSyncId.
     *
     * [invalidate] keeps the id on purpose — a bot challenge does not change
     * which account is signed in. A logout does, and nothing used to clear it,
     * so the next session kept minting account-bound tokens for an account the
     * user had disconnected (or, after a switch, for the previous one).
     */
    fun clearSession() {
        invalidate()
        synchronized(tokenLru) {
            val old = dataSyncId
            dataSyncId = ""
            if (old.isNotEmpty()) tokenLru.remove(old)
        }
        appContext?.let { PoTokenStore.clearDataSyncId(it) }
    }

    private fun refreshInternal() {
        val ctx = appContext ?: throw IllegalStateException("PoTokenManager is not initialized with Context")

        // 1. Fetch visitorData from Innertube — skip network fetch if we already have
        //    a non-expired visitorData (avoids broken HTML scrape in PulsrDownloader).
        val newVisitorData: String
        if (visitorData.isNotEmpty() && !isExpired()) {
            Log.d(TAG, "Reusing cached visitorData (not expired), skipping Innertube fetch")
            newVisitorData = visitorData
        } else {
            val clientRequestInfo = InnertubeClientRequestInfo.ofWebClient()
            // getClientVersion() does an HTML page scrape; if it fails (e.g. ERR_FAILED on
            // flagged IPs) fall back to a pinned version so the PoToken chain can still run.
            val resolvedVersion = try {
                YoutubeParsingHelper.getClientVersion()
            } catch (e: Exception) {
                Log.w(TAG, "getClientVersion() failed (${e.message}), using pinned fallback version")
                "2.20260905.00.00"
            }
            clientRequestInfo.clientInfo.clientVersion = resolvedVersion

            newVisitorData = try {
                YoutubeParsingHelper.getVisitorDataFromInnertube(
                    clientRequestInfo,
                    NewPipe.getPreferredLocalization(),
                    NewPipe.getPreferredContentCountry(),
                    YoutubeParsingHelper.getYouTubeHeaders(),
                    YoutubeParsingHelper.YOUTUBEI_V1_URL,
                    null,
                    false,
                )
            } catch (e: Exception) {
                Log.w(TAG, "getVisitorDataFromInnertube() failed: ${e.message}")
                if (visitorData.isNotEmpty()) {
                    Log.i(TAG, "Falling back to stale cached visitorData")
                    visitorData
                } else {
                    throw e
                }
            }
        }

        // 2. Instantiate offscreen BotGuard generator. The previous one stays usable
        //    until this one has actually minted: tearing it down up front meant a
        //    failed init left no generator at all, so every later call paid the cold
        //    path and any in-flight mint died with it.
        val newGenerator = PoTokenWebView.newPoTokenGenerator(ctx)

        // 3. Mint the streaming poToken using visitorData
        val newStreamingToken = try {
            newGenerator.generatePoToken(newVisitorData)
        } catch (t: Throwable) {
            Handler(Looper.getMainLooper()).post { newGenerator.close() }
            throw t
        }

        // 4. Calculate actual expiry from generator and store ceiling
        val now = Instant.now().epochSecond
        val generatorExpiry = newGenerator.expirationInstant()?.epochSecond ?: Long.MAX_VALUE
        val storeExpiry = now + PoTokenStore.DEFAULT_TTL_SECONDS
        val newExpiry = minOf(generatorExpiry, storeExpiry)
        val effectiveTtlSeconds = (newExpiry - now).coerceAtLeast(60L)

        visitorData = newVisitorData
        streamingPoToken = newStreamingToken
        expiryInstant = newExpiry
        val oldGen = generator
        generator = newGenerator
        if (oldGen != null && oldGen !== newGenerator) {
            Handler(Looper.getMainLooper()).post { oldGen.close() }
        }

        // 5. Persist to secure store
        PoTokenStore.saveTokenData(
            context = ctx,
            streamingPoToken = newStreamingToken,
            visitorData = newVisitorData,
            integrityToken = integrityToken,
            dataSyncId = dataSyncId,
            ttlSeconds = effectiveTtlSeconds,
            generatedAt = now
        )

        synchronized(tokenLru) {
            tokenLru.evictAll() // Flush old visitorData bindings
            tokenLru.put(newVisitorData, CachedToken(newStreamingToken, newVisitorData, now))
        }

        Log.i(TAG, "Successfully refreshed PoToken attestation. Valid until epoch $newExpiry")
    }
}
