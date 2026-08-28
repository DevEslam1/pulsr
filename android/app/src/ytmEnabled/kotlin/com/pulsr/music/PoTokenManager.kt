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

    @Volatile
    var webViewBroken: Boolean = false
        private set

    val isLimitedMode: Boolean
        get() = webViewBroken || (isExpired() && visitorData.isEmpty())

    @Volatile
    private var generator: PoTokenGenerator? = null

    private var appContext: Context? = null
    private val stateMutex = Mutex()
    private var refreshInFlight: kotlinx.coroutines.Deferred<Boolean>? = null

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
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (isExpired() || isExpiringSoon() || generator == null) {
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
            CoroutineScope(Dispatchers.IO).launch {
                runCatching { ensureReady() }
            }
        }
    }

    /**
     * Non-blocking background regeneration triggered on 403 or invalidation signal.
     */
    fun triggerBackgroundRefresh() {
        val ctx = appContext ?: return
        Log.i(TAG, "Triggering non-blocking background PoToken regeneration")
        CoroutineScope(Dispatchers.IO).launch {
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

        if (isReady && !isExpiringSoon() && generator != null) {
            return@withContext true
        }

        stateMutex.withLock {
            if (isReady && !isExpiringSoon() && generator != null) {
                return@withContext true
            }

            refreshInFlight?.let { existing ->
                return@withContext try {
                    existing.await()
                } catch (_: Throwable) {
                    visitorData.isNotEmpty()
                }
            }

            val deferred = CoroutineScope(Dispatchers.IO).async {
                try {
                    refreshInternal()
                    true
                } catch (e: BadWebViewException) {
                    Log.e(TAG, "System WebView is broken for BotGuard: ${e.message}", e)
                    webViewBroken = true
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
        if (webViewBroken) return visitorData.isNotEmpty()
        if (isReady && !isExpiringSoon() && generator != null) return true

        return kotlinx.coroutines.runBlocking(Dispatchers.IO) {
            ensureReady()
        }
    }

    /**
     * Generates or retrieves cached poToken strictly bound to current [visitorData].
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
            synchronized(tokenLru) {
                val fallback = tokenLru.get(identifier)?.token
                if (!fallback.isNullOrEmpty()) return fallback
            }
            if (streamingPoToken.isNotEmpty()) return streamingPoToken
            return ""
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
                synchronized(tokenLru) {
                    tokenLru.get(identifier)?.token ?: streamingPoToken
                }
            }
        }

        // 5. If we have a valid stored streaming token, return it and warm generator in background
        if (streamingPoToken.isNotEmpty() && !isExpired()) {
            triggerBackgroundRefresh()
            return streamingPoToken
        }

        // 6. Cold path fallback: synchronous generation
        ensureReadySync()

        val activeGen = generator
        if (activeGen == null || activeGen.isExpired()) {
            synchronized(tokenLru) {
                return tokenLru.get(identifier)?.token ?: streamingPoToken
            }
        }

        return try {
            val minted = activeGen.generatePoToken(identifier)
            synchronized(tokenLru) {
                tokenLru.put(identifier, CachedToken(minted, visitorData, Instant.now().epochSecond))
            }
            minted
        } catch (t: Throwable) {
            Log.w(TAG, "Minting poToken failed for $identifier: ${t.message}", t)
            synchronized(tokenLru) {
                tokenLru.get(identifier)?.token ?: streamingPoToken
            }
        }
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
     */
    fun invalidate() {
        val oldGen = generator
        generator = null
        expiryInstant = 0L
        dataSyncId = ""
        sessionVisitorData = ""
        visitorData = ""
        streamingPoToken = ""
        oldGen?.let { Handler(Looper.getMainLooper()).post { it.close() } }
        appContext?.let { PoTokenStore.clear(it) }
        synchronized(tokenLru) {
            tokenLru.evictAll()
        }
    }

    fun evictMintedTokens() {
        synchronized(tokenLru) {
            tokenLru.evictAll()
        }
    }

    private fun refreshInternal() {
        val ctx = appContext ?: throw IllegalStateException("PoTokenManager is not initialized with Context")

        val oldGen = generator
        generator = null
        oldGen?.let { Handler(Looper.getMainLooper()).post { it.close() } }

        // 1. Fetch visitorData from Innertube if missing or expired
        val clientRequestInfo = InnertubeClientRequestInfo.ofWebClient()
        clientRequestInfo.clientInfo.clientVersion = YoutubeParsingHelper.getClientVersion()

        val newVisitorData = try {
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
            if (visitorData.isNotEmpty()) visitorData else throw e
        }

        // 2. Instantiate offscreen BotGuard generator
        val newGenerator = PoTokenWebView.newPoTokenGenerator(ctx)

        // 3. Mint the streaming poToken using visitorData
        val newStreamingToken = newGenerator.generatePoToken(newVisitorData)

        // 4. Default 12 hour expiry with 30 min margin
        val now = Instant.now().epochSecond
        val ttlSeconds = PoTokenStore.DEFAULT_TTL_SECONDS
        val newExpiry = now + ttlSeconds

        visitorData = newVisitorData
        streamingPoToken = newStreamingToken
        expiryInstant = newExpiry
        generator = newGenerator

        // 5. Persist to secure store
        PoTokenStore.saveTokenData(
            context = ctx,
            streamingPoToken = newStreamingToken,
            visitorData = newVisitorData,
            integrityToken = integrityToken,
            dataSyncId = dataSyncId,
            ttlSeconds = ttlSeconds,
            generatedAt = now
        )

        synchronized(tokenLru) {
            tokenLru.evictAll() // Flush old visitorData bindings
            tokenLru.put(newVisitorData, CachedToken(newStreamingToken, newVisitorData, now))
        }

        Log.i(TAG, "Successfully refreshed PoToken attestation. Valid until epoch $newExpiry")
    }
}
