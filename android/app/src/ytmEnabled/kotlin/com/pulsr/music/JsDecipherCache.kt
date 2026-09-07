package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap

internal class UndecipherableSignatureException(playerHash: String) :
    IllegalStateException("No cached decipher rules for player hash $playerHash")

/**
 * Task 5 — JS Player Decipher & N-Sig Transform Cache.
 *
 * Caches decipher transforms and decoded stream parameters per player version hash.
 * Persisted to disk with a 24-hour TTL, eliminating redundant base.js network downloads
 * and JavaScript engine evaluations on every resolution.
 */
internal class JsDecipherCache(
    context: Context? = null,
    private val prefs: SharedPreferences? = context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
) {

    private val memoryCache = ConcurrentHashMap<String, CachedDecipherRules>()

    data class CachedDecipherRules(
        val playerHash: String,
        val transformSteps: List<String>, // e.g. ["reverse", "splice:3", "swap:2"]
        val cachedAt: Long = System.currentTimeMillis(),
        val ttlMs: Long = 24 * 60 * 60 * 1000L // 24 hours
    ) {
        val isExpired: Boolean
            get() = System.currentTimeMillis() - cachedAt >= ttlMs
    }

    data class CachedNTransform(
        val playerHash: String,
        val nSteps: List<String>,
        val signatureTimestamp: Int? = null,
        val cachedAt: Long = System.currentTimeMillis(),
        val ttlMs: Long = 24 * 60 * 60 * 1000L
    ) {
        val isExpired: Boolean
            get() = System.currentTimeMillis() - cachedAt >= ttlMs
    }

    companion object {
        private const val TAG = "JsDecipherCache"
        private const val PREFS_NAME = "pulsr_ytm_decipher_cache"
        private const val KEY_PREFIX_RULES = "rules_"
        private const val KEY_PREFIX_TIME = "time_"
        private const val KEY_PREFIX_N_RULES = "n_rules_"
        private const val KEY_PREFIX_N_TIME = "n_time_"
        private const val KEY_PREFIX_STS = "sts_"
        private const val DEFAULT_TTL_MS = 24 * 60 * 60 * 1000L

        @Volatile
        private var instance: JsDecipherCache? = null

        fun getInstance(context: Context): JsDecipherCache {
            return instance ?: synchronized(this) {
                instance ?: JsDecipherCache(context.applicationContext).also { instance = it }
            }
        }

        private fun logD(tag: String, msg: String) {
            try {
                Log.d(tag, msg)
            } catch (_: Throwable) {
                println("[$tag] $msg")
            }
        }
    }

    /**
     * Resolves signature using cached transform rules.
     *
     * Throws [UndecipherableSignatureException] when no usable rules are cached.
     * Returning the input untransformed produced a URL that googlevideo answers
     * with 403, which the block classifier then read as an IP block; failing lets
     * the caller discard the format and try the next client instead.
     */
    fun decipherSignature(signature: String, playerHash: String = "default"): String {
        val rules = getRules(playerHash)
        if (rules == null || rules.isExpired || rules.transformSteps.isEmpty()) {
            throw UndecipherableSignatureException(playerHash)
        }
        return applyTransforms(signature, rules.transformSteps)
    }

    /**
     * Applies transform operations to signature.
     */
    fun applyTransforms(signature: String, steps: List<String>): String {
        var chars = signature.toCharArray()
        for (step in steps) {
            val parts = step.split(":")
            when (parts[0]) {
                "reverse" -> {
                    chars.reverse()
                }
                "splice" -> {
                    val count = parts.getOrNull(1)?.toIntOrNull() ?: 0
                    if (count in 1 until chars.size) {
                        chars = chars.sliceArray(count until chars.size)
                    }
                }
                "swap" -> {
                    val index = parts.getOrNull(1)?.toIntOrNull() ?: 0
                    if (index in 0 until chars.size && chars.isNotEmpty()) {
                        val tmp = chars[0]
                        chars[0] = chars[index]
                        chars[index] = tmp
                    }
                }
            }
        }
        return String(chars)
    }

    /**
     * Retrieves transform rules from memory or persistent store.
     */
    fun getRules(playerHash: String): CachedDecipherRules? {
        val inMemory = memoryCache[playerHash]
        if (inMemory != null && !inMemory.isExpired) {
            return inMemory
        }

        val storedSteps = prefs?.getString(KEY_PREFIX_RULES + playerHash, null) ?: return null
        val storedTime = prefs.getLong(KEY_PREFIX_TIME + playerHash, 0L)
        if (System.currentTimeMillis() - storedTime >= DEFAULT_TTL_MS) {
            clearRules(playerHash)
            return null
        }

        val steps = storedSteps.split(",").filter { it.isNotEmpty() }
        val rules = CachedDecipherRules(playerHash, steps, storedTime)
        memoryCache[playerHash] = rules
        return rules
    }

    /**
     * Stores transform rules for player version hash.
     */
    fun putRules(playerHash: String, steps: List<String>) {
        val now = System.currentTimeMillis()
        memoryCache[playerHash] = CachedDecipherRules(playerHash, steps, now)
        prefs?.edit()
            ?.putString(KEY_PREFIX_RULES + playerHash, steps.joinToString(","))
            ?.putLong(KEY_PREFIX_TIME + playerHash, now)
            ?.apply()
        logD(TAG, "Cached decipher rules for player hash $playerHash with ${steps.size} steps")
    }

    fun clearRules(playerHash: String) {
        memoryCache.remove(playerHash)
        prefs?.edit()
            ?.remove(KEY_PREFIX_RULES + playerHash)
            ?.remove(KEY_PREFIX_TIME + playerHash)
            ?.apply()
    }

    // --- N-param transform (throttling) ---
    private val nMemoryCache = ConcurrentHashMap<String, CachedNTransform>()

    fun decipherN(n: String, playerHash: String = "default"): String {
        val cached = getNTransform(playerHash) ?: return n
        if (cached.isExpired || cached.nSteps.isEmpty()) return n
        return applyTransforms(n, cached.nSteps)
    }

    fun getNTransform(playerHash: String): CachedNTransform? {
        val inMem = nMemoryCache[playerHash]
        if (inMem != null && !inMem.isExpired) return inMem
        val stored = prefs?.getString(KEY_PREFIX_N_RULES + playerHash, null) ?: return null
        val storedTime = prefs.getLong(KEY_PREFIX_N_TIME + playerHash, 0L)
        if (System.currentTimeMillis() - storedTime >= DEFAULT_TTL_MS) {
            clearNTransform(playerHash)
            return null
        }
        val steps = stored.split(",").filter { it.isNotEmpty() }
        val sts = prefs.getInt(KEY_PREFIX_STS + playerHash, -1).takeIf { it != -1 }
        val entry = CachedNTransform(playerHash, steps, sts, storedTime)
        nMemoryCache[playerHash] = entry
        return entry
    }

    fun putNTransform(playerHash: String, steps: List<String>, signatureTimestamp: Int? = null) {
        val now = System.currentTimeMillis()
        nMemoryCache[playerHash] = CachedNTransform(playerHash, steps, signatureTimestamp, now)
        val edit = prefs?.edit()
            ?.putString(KEY_PREFIX_N_RULES + playerHash, steps.joinToString(","))
            ?.putLong(KEY_PREFIX_N_TIME + playerHash, now)
        if (signatureTimestamp != null) edit?.putInt(KEY_PREFIX_STS + playerHash, signatureTimestamp)
        edit?.apply()
        logD(TAG, "Cached n-transform for $playerHash sts=$signatureTimestamp steps=${steps.size}")
    }

    fun getSignatureTimestamp(playerHash: String = "default"): Int? {
        val cached = getNTransform(playerHash) ?: return prefs?.getInt(KEY_PREFIX_STS + playerHash, -1)?.takeIf { it != -1 }
        return cached.signatureTimestamp ?: prefs?.getInt(KEY_PREFIX_STS + playerHash, -1)?.takeIf { it != -1 }
    }

    fun clearNTransform(playerHash: String) {
        nMemoryCache.remove(playerHash)
        prefs?.edit()?.remove(KEY_PREFIX_N_RULES + playerHash)?.remove(KEY_PREFIX_N_TIME + playerHash)?.remove(KEY_PREFIX_STS + playerHash)?.apply()
    }

    fun clearAll() {
        memoryCache.clear()
        nMemoryCache.clear()
        prefs?.edit()?.clear()?.apply()
    }
}
