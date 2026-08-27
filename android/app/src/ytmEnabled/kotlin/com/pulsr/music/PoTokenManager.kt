package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.services.youtube.InnertubeClientRequestInfo
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import java.time.Instant

/**
 * Singleton PoToken Lifecycle Manager.
 *
 * Persists and proactively refreshes BotGuard proof-of-origin tokens (poToken, visitorData, integrityToken).
 * Manages an LRU cache for minted per-video tokens (64 entries, 30 min TTL) and degrades gracefully
 * to stale cached tokens if the system WebView encounters a critical failure.
 */
object PoTokenManager {
    private const val TAG = "PoTokenManager"
    private const val PREFS_NAME = "ytm_po_token_prefs"
    private const val KEY_VISITOR_DATA = "ytm_visitor_data"
    private const val KEY_INTEGRITY_TOKEN = "ytm_integrity_token"
    private const val KEY_EXPIRY_INSTANT = "ytm_expiry_instant"
    private const val KEY_LAST_STREAMING_TOKEN = "ytm_last_streaming_token"
    private const val KEY_DATA_SYNC_ID = "ytm_data_sync_id"

    private const val LRU_CAPACITY = 64
    private const val TOKEN_TTL_SECONDS = 1800L // 30 minutes
    private const val EXPIRING_SOON_MARGIN_SECONDS = 600L // 10 minutes

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

    /**
     * Raw `datasyncId` of the currently authenticated account (e.g. "userSessionId||" or
     * "delegated||user"). Empty when logged out. Used as the poToken content-binding for
     * authenticated `WEB_REMIX` player requests.
     */
    @Volatile
    var dataSyncId: String = ""
        private set

    /**
     * `visitorData` harvested from an authenticated Innertube response. Sent in the client context
     * for authenticated `WEB_REMIX` requests (the account-bound poToken binds to [dataSyncId], not
     * this). Non-persisted: re-harvested from the first authed response each session.
     */
    @Volatile
    var sessionVisitorData: String = ""
        private set

    @Volatile
    var webViewBroken: Boolean = false
        private set

    @Volatile
    private var generator: PoTokenGenerator? = null

    private var appContext: Context? = null
    private var prefs: SharedPreferences? = null
    private val stateMutex = kotlinx.coroutines.sync.Mutex()
    private var refreshInFlight: kotlinx.coroutines.Deferred<Boolean>? = null

    private data class CachedToken(val token: String, val timestamp: Long)
    private val tokenLru = LruCache<String, CachedToken>(LRU_CAPACITY)

    fun init(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
            val p = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs = p
            visitorData = p.getString(KEY_VISITOR_DATA, "") ?: ""
            integrityToken = p.getString(KEY_INTEGRITY_TOKEN, "") ?: ""
            expiryInstant = p.getLong(KEY_EXPIRY_INSTANT, 0L)
            streamingPoToken = p.getString(KEY_LAST_STREAMING_TOKEN, "") ?: ""
            dataSyncId = p.getString(KEY_DATA_SYNC_ID, "") ?: ""
        }
    }

    val isReady: Boolean
        get() = visitorData.isNotEmpty() && !isExpired()

    fun isExpired(): Boolean {
        val now = Instant.now().epochSecond
        return expiryInstant <= now
    }

    fun isExpiringSoon(): Boolean {
        val now = Instant.now().epochSecond
        return expiryInstant - now < EXPIRING_SOON_MARGIN_SECONDS
    }

    /**
     * Ensures attestation state is ready. Loads cached values, or runs BotGuard VM in WebView
     * if expired or missing. Deduplicates in-flight refreshes to prevent thundering herd.
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

            val deferred = kotlinx.coroutines.CoroutineScope(Dispatchers.IO).async {
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

    /**
     * Synchronous variant for NewPipe extractor thread callbacks.
     */
    fun ensureReadySync(): Boolean {
        if (webViewBroken) return visitorData.isNotEmpty()
        if (isReady && !isExpiringSoon() && generator != null) return true

        return kotlinx.coroutines.runBlocking(Dispatchers.IO) {
            ensureReady()
        }
    }

    /**
     * Generates or retrieves a cached poToken for [identifier] (either videoId or visitorData).
     */
    suspend fun poTokenFor(identifier: String): String = withContext(Dispatchers.IO) {
        poTokenForSync(identifier)
    }

    /**
     * Thread-safe synchronous resolution with LRU cache.
     */
    fun poTokenForSync(identifier: String): String {
        val now = Instant.now().epochSecond
        synchronized(tokenLru) {
            val cached = tokenLru.get(identifier)
            if (cached != null && (now - cached.timestamp) < TOKEN_TTL_SECONDS) {
                return cached.token
            }
        }

        if (webViewBroken) {
            synchronized(tokenLru) {
                val fallback = tokenLru.get(identifier)?.token
                if (!fallback.isNullOrEmpty()) return fallback
            }
            if (streamingPoToken.isNotEmpty()) return streamingPoToken
            return ""
        }

        ensureReadySync()

        val gen = generator
        if (gen == null || gen.isExpired()) {
            synchronized(tokenLru) {
                return tokenLru.get(identifier)?.token ?: streamingPoToken
            }
        }

        return try {
            val minted = gen.generatePoToken(identifier)
            synchronized(tokenLru) {
                // Stamp AFTER minting: WebView generation can take seconds, so
                // using the pre-mint clock would silently shorten the TTL.
                tokenLru.put(identifier, CachedToken(minted, Instant.now().epochSecond))
            }
            minted
        } catch (t: Throwable) {
            Log.w(TAG, "Minting poToken failed for $identifier: ${t.message}", t)
            synchronized(tokenLru) {
                tokenLru.get(identifier)?.token ?: streamingPoToken
            }
        }
    }

    /**
     * Records the raw [id] `datasyncId` of the authenticated account. Blank input is ignored so
     * an empty harvest never wipes a good value (use [invalidate] to clear on logout). When the
     * value changes, evicts the stale account-bound token(s) so the next request re-mints.
     */
    fun setDataSyncId(id: String) {
        val normalized = id.trim()
        if (normalized.isEmpty()) return
        synchronized(tokenLru) {
            if (normalized == dataSyncId) return
            val old = dataSyncId
            dataSyncId = normalized
            prefs?.edit()?.putString(KEY_DATA_SYNC_ID, normalized)?.apply()
            if (old.isNotEmpty()) tokenLru.remove(old)
            tokenLru.remove(normalized)
        }
    }

    /**
     * Records the `visitorData` [v] harvested from an authenticated response. Blank input ignored.
     */
    fun setSessionVisitorData(v: String) {
        val normalized = v.trim()
        if (normalized.isEmpty()) return
        sessionVisitorData = normalized
    }

    /**
     * Returns a poToken bound to the account [dataSyncId] for authenticated `WEB_REMIX` player
     * requests. Reuses the LRU-cached [poTokenForSync] minting keyed on the raw dataSyncId.
     */
    fun accountPoTokenForSync(dataSyncId: String): String {
        val id = dataSyncId.trim()
        if (id.isEmpty()) return ""
        ensureReadySync()
        return poTokenForSync(id)
    }

    /**
     * Forces full cache invalidation and triggers re-attestation on the next request.
     */
    fun invalidate() {
        val oldGen = generator
        generator = null
        expiryInstant = 0L
        dataSyncId = ""
        sessionVisitorData = ""
        oldGen?.let { Handler(Looper.getMainLooper()).post { it.close() } }
        prefs?.edit()?.remove(KEY_EXPIRY_INSTANT)?.remove(KEY_DATA_SYNC_ID)?.apply()
        synchronized(tokenLru) {
            tokenLru.evictAll()
        }
    }

    /**
     * Evicts only the minted per-identifier tokens, keeping the WebView
     * attestation (generator + visitorData + integrity token) alive. Used when
     * YouTube bot-gates a resolution cycle: re-minting per-video tokens against
     * the existing attestation is cheap, whereas a full [invalidate] forces a
     * multi-second BotGuard WebView re-run every cycle while flagged.
     */
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

        // 3. Mint the streaming poToken using visitorData (must be first)
        val newStreamingToken = newGenerator.generatePoToken(newVisitorData)

        // 4. Default 12 hour expiry with 10 min margin if not explicitly parsed
        val newExpiry = Instant.now().plusSeconds(12 * 3600 - EXPIRING_SOON_MARGIN_SECONDS).epochSecond

        visitorData = newVisitorData
        streamingPoToken = newStreamingToken
        expiryInstant = newExpiry
        generator = newGenerator

        // 5. Persist to SharedPreferences
        prefs?.edit()?.apply {
            putString(KEY_VISITOR_DATA, newVisitorData)
            putString(KEY_LAST_STREAMING_TOKEN, newStreamingToken)
            putLong(KEY_EXPIRY_INSTANT, newExpiry)
            apply()
        }

        synchronized(tokenLru) {
            tokenLru.put(newVisitorData, CachedToken(newStreamingToken, Instant.now().epochSecond))
        }

        Log.i(TAG, "Successfully refreshed PoToken attestation. Valid until epoch $newExpiry")
    }
}
