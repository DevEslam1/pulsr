package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.time.Instant

/**
 * Layer 3: Persistent, Secure Storage for YouTube Music PoToken & Attestation State.
 *
 * Follows the [FingerprintStore] and [YtmCookieStore] pattern:
 * - Uses [EncryptedSharedPreferences] with fallback to standard [SharedPreferences]
 * - Persists streaming poToken, visitorData, integrityToken, dataSyncId, generatedAt, and TTL
 * - Tolerates corrupt, unparseable, or missing values by returning empty/expired state
 * - Provides thread-safe, atomic mutations
 */
internal object PoTokenStore {
    private const val TAG = "PoTokenStore"
    private const val PREFS_NAME = "ytm_po_token_prefs"
    private const val SECURE_PREFS_NAME = "ytm_po_token_secure_prefs"

    private const val KEY_STREAMING_TOKEN = "ytm_streaming_po_token"
    private const val KEY_VISITOR_DATA = "ytm_visitor_data"
    private const val KEY_INTEGRITY_TOKEN = "ytm_integrity_token"
    private const val KEY_DATA_SYNC_ID = "ytm_data_sync_id"
    private const val KEY_GENERATED_AT = "ytm_generated_at"
    private const val KEY_TTL_SECONDS = "ytm_ttl_seconds"
    private const val KEY_EXPIRY_INSTANT = "ytm_expiry_instant"

    const val DEFAULT_TTL_SECONDS = 12 * 3600L // 12 hours
    const val REFRESH_MARGIN_SECONDS = 1800L // 30 minutes before expiry

    data class StoredTokenData(
        val streamingPoToken: String,
        val visitorData: String,
        val integrityToken: String,
        val dataSyncId: String,
        val generatedAt: Long,
        val ttlSeconds: Long,
        val expiryInstant: Long
    ) {
        val isExpired: Boolean
            get() {
                if (streamingPoToken.isEmpty() || visitorData.isEmpty()) return true
                if (expiryInstant <= 0L || generatedAt <= 0L) return true
                val now = Instant.now().epochSecond
                return expiryInstant <= now
            }

        val isExpiringSoon: Boolean
            get() {
                if (isExpired) return true
                val now = Instant.now().epochSecond
                return (expiryInstant - now) <= REFRESH_MARGIN_SECONDS
            }
    }

    @Volatile
    private var prefsInstance: SharedPreferences? = null
    private val lock = Any()

    fun getPrefs(context: Context): SharedPreferences {
        prefsInstance?.let { return it }
        synchronized(lock) {
            prefsInstance?.let { return it }
            val legacy = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val p = try {
                val masterKey = MasterKey.Builder(context.applicationContext)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    context.applicationContext,
                    SECURE_PREFS_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                )
            } catch (t: Throwable) {
                Log.w(TAG, "EncryptedSharedPreferences unavailable; falling back to standard prefs: ${t.message}")
                legacy
            }
            prefsInstance = p
            return p
        }
    }

    /**
     * Loads the stored token data, tolerating corrupt, invalid, or missing entries.
     */
    fun loadTokenData(context: Context): StoredTokenData {
        val prefs = getPrefs(context)
        return try {
            val token = prefs.getString(KEY_STREAMING_TOKEN, "") ?: ""
            val visitor = prefs.getString(KEY_VISITOR_DATA, "") ?: ""
            val integrity = prefs.getString(KEY_INTEGRITY_TOKEN, "") ?: ""
            val dataSync = prefs.getString(KEY_DATA_SYNC_ID, "") ?: ""
            val genAt = prefs.getLong(KEY_GENERATED_AT, 0L)
            val ttl = prefs.getLong(KEY_TTL_SECONDS, DEFAULT_TTL_SECONDS)
            var expiry = prefs.getLong(KEY_EXPIRY_INSTANT, 0L)

            // Validate integrity of stored numbers
            if (genAt > 0L && expiry <= 0L) {
                expiry = genAt + ttl
            }

            StoredTokenData(
                streamingPoToken = token,
                visitorData = visitor,
                integrityToken = integrity,
                dataSyncId = dataSync,
                generatedAt = genAt,
                ttlSeconds = ttl,
                expiryInstant = expiry
            )
        } catch (t: Throwable) {
            Log.e(TAG, "Corrupt token store encountered; resetting store: ${t.message}", t)
            clear(context)
            StoredTokenData("", "", "", "", 0L, DEFAULT_TTL_SECONDS, 0L)
        }
    }

    /**
     * Atomically saves newly minted poToken attestation data.
     */
    fun saveTokenData(
        context: Context,
        streamingPoToken: String,
        visitorData: String,
        integrityToken: String = "",
        dataSyncId: String = "",
        ttlSeconds: Long = DEFAULT_TTL_SECONDS,
        generatedAt: Long = Instant.now().epochSecond
    ) {
        val prefs = getPrefs(context)
        val expiryInstant = generatedAt + ttlSeconds
        try {
            prefs.edit()
                .putString(KEY_STREAMING_TOKEN, streamingPoToken)
                .putString(KEY_VISITOR_DATA, visitorData)
                .putString(KEY_INTEGRITY_TOKEN, integrityToken)
                .putString(KEY_DATA_SYNC_ID, dataSyncId)
                .putLong(KEY_GENERATED_AT, generatedAt)
                .putLong(KEY_TTL_SECONDS, ttlSeconds)
                .putLong(KEY_EXPIRY_INSTANT, expiryInstant)
                .apply()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to save token data to store: ${t.message}", t)
        }
    }

    /**
     * Updates only the dataSyncId without altering existing token or expiry.
     */
    fun saveDataSyncId(context: Context, dataSyncId: String) {
        try {
            getPrefs(context).edit().putString(KEY_DATA_SYNC_ID, dataSyncId).apply()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to update dataSyncId in store: ${t.message}", t)
        }
    }

    /**
     * Clears attestation state while keeping the dataSyncId, which identifies the
     * signed-in account rather than the token.
     */
    fun clearAttestation(context: Context) {
        try {
            getPrefs(context).edit()
                .remove(KEY_STREAMING_TOKEN)
                .remove(KEY_VISITOR_DATA)
                .remove(KEY_INTEGRITY_TOKEN)
                .remove(KEY_GENERATED_AT)
                .remove(KEY_TTL_SECONDS)
                .remove(KEY_EXPIRY_INSTANT)
                .apply()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to clear attestation state: ${t.message}", t)
        }
    }

    /**
     * Clears all persisted poToken state (e.g. on invalidation or corruption).
     */
    fun clear(context: Context) {
        try {
            getPrefs(context).edit().clear().apply()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to clear token store: ${t.message}", t)
        }
    }
}
