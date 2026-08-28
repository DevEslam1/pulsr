package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap

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

    companion object {
        private const val TAG = "JsDecipherCache"
        private const val PREFS_NAME = "pulsr_ytm_decipher_cache"
        private const val KEY_PREFIX_RULES = "rules_"
        private const val KEY_PREFIX_TIME = "time_"
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
     * Resolves signature using cached transform rules or basic transform ladder.
     */
    fun decipherSignature(signature: String, playerHash: String = "default"): String {
        val rules = getRules(playerHash)
        if (rules != null && !rules.isExpired && rules.transformSteps.isNotEmpty()) {
            return applyTransforms(signature, rules.transformSteps)
        }
        return signature
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

    fun clearAll() {
        memoryCache.clear()
        prefs?.edit()?.clear()?.apply()
    }
}
