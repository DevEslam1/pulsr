package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.util.concurrent.ConcurrentHashMap

/**
 * 2026-09 audit gap 1: per-client SABR demotions with TTL.
 *
 * When YouTube forces SABR on a client, that client keeps returning formats
 * without direct URLs. Those responses are classified
 * [YtmBlockSignal.SabrEnforced] and the client is demoted to the TAIL of the
 * stream chain (never removed — a YouTube-side rollback should self-heal after
 * TTL) until the demotion expires.
 *
 * SABR is a client/streaming-protocol state, NOT an attestation failure:
 * never invalidate poTokens as a consequence of a demotion.
 *
 * Split into [SabrDemotionState] (pure, JVM-testable, injected clock) and the
 * Android persistence wrapper, mirroring the testDev test approach.
 */
internal class SabrDemotionState(
    private val clock: () -> Long,
    private val ttlMs: Long = DEFAULT_TTL_MS,
) {
    private val demotedUntil = ConcurrentHashMap<String, Long>()

    fun mark(clientName: String) {
        demotedUntil[clientName] = clock() + ttlMs
    }

    fun isDemoted(clientName: String): Boolean {
        val until = demotedUntil[clientName] ?: return false
        if (until <= clock()) {
            demotedUntil.remove(clientName)
            return false
        }
        return true
    }

    fun clear(clientName: String) {
        demotedUntil.remove(clientName)
    }

    fun clearAll() {
        demotedUntil.clear()
    }

    fun demotedNames(): List<String> =
        demotedUntil.keys.filter { isDemoted(it) }.sorted()

    companion object {
        const val DEFAULT_TTL_MS = 24 * 60 * 60 * 1000L
    }
}

/**
 * Android persistence wrapper. Survives process restarts so a SABR wave does
 * not re-burn the chain on every cold start.
 */
internal object SabrDemotionStore {
    private const val TAG = "SabrDemotionStore"
    private const val PREFS = "ytm_sabr_demotions"
    private const val KEY_PREFIX = "demoted_until_"

    @Volatile
    private var prefs: SharedPreferences? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        }
    }

    fun markSabrEnforced(client: InnertubeClient.ClientType) {
        val until = System.currentTimeMillis() + SabrDemotionState.DEFAULT_TTL_MS
        Log.i(TAG, "SABR demotion: ${client.name} until epoch=$until")
        prefs?.edit()?.putLong(KEY_PREFIX + client.name, until)?.apply()
    }

    fun isSabrDemoted(client: InnertubeClient.ClientType): Boolean {
        val until = prefs?.getLong(KEY_PREFIX + client.name, 0L) ?: 0L
        return until > System.currentTimeMillis()
    }

    fun clear(client: InnertubeClient.ClientType) {
        prefs?.edit()?.remove(KEY_PREFIX + client.name)?.apply()
    }

    fun clearAll() {
        prefs?.edit()?.clear()?.apply()
    }
}
