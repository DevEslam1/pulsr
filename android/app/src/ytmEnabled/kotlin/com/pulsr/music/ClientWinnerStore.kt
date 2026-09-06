package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * Task 4 — Persistent Store for Winning Innertube Clients per Track Type.
 *
 * Remembers the winning Innertube client per track type (music vs longform)
 * so subsequent stream resolutions can immediately target the proven winner
 * and bypass the entire multi-client waterfall.
 */
internal class ClientWinnerStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val TAG = "ClientWinnerStore"
        private const val PREFS_NAME = "pulsr_ytm_client_winners"
        private const val KEY_PREFIX_WINNER = "winner_"
        private const val KEY_PREFIX_FAILURES = "failures_"
        private const val KEY_PREFIX_RECORDED_AT = "recorded_at_"
        private const val MAX_CONSECUTIVE_FAILURES = 2

        // A winner is evidence about the *current* conditions — which client YouTube
        // was serving during one IP-flagged wave. Without an expiry the store pinned
        // that client to the front of the chain indefinitely, long after the regular
        // clients had recovered.
        private const val WINNER_TTL_MS = 6 * 60 * 60 * 1000L

        // Never worth promoting: these only exist as no-login last resorts and they
        // hand back low-bitrate or restricted streams, so pinning one to the front
        // permanently degrades quality for every later track.
        private val NON_PROMOTABLE = setOf(
            InnertubeClient.ClientType.ANDROID_TESTSUITE,
            InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
        )

        const val TRACK_TYPE_MUSIC = "music"
        const val TRACK_TYPE_LONGFORM = "longform"

        @Volatile
        private var instance: ClientWinnerStore? = null

        fun getInstance(context: Context): ClientWinnerStore {
            return instance ?: synchronized(this) {
                instance ?: ClientWinnerStore(context.applicationContext).also { instance = it }
            }
        }
    }

    /**
     * Returns the cached winning client for [trackType], or null if none is recorded,
     * it has expired, or it failed too many times.
     */
    @Synchronized
    fun getWinningClient(trackType: String = TRACK_TYPE_MUSIC): InnertubeClient.ClientType? {
        val clientName = prefs.getString(KEY_PREFIX_WINNER + trackType, null) ?: return null
        val failures = prefs.getInt(KEY_PREFIX_FAILURES + trackType, 0)
        if (failures >= MAX_CONSECUTIVE_FAILURES) {
            Log.d(TAG, "Evicting winner $clientName for $trackType due to $failures consecutive failures")
            clearWinner(trackType)
            return null
        }
        val recordedAt = prefs.getLong(KEY_PREFIX_RECORDED_AT + trackType, 0L)
        val age = System.currentTimeMillis() - recordedAt
        if (recordedAt <= 0L || age > WINNER_TTL_MS || age < 0L) {
            Log.d(TAG, "Evicting stale winner $clientName for $trackType (age ${age}ms)")
            clearWinner(trackType)
            return null
        }
        return try {
            InnertubeClient.ClientType.valueOf(clientName)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /**
     * Records a successful client resolution for [trackType], resetting any failure count.
     */
    @Synchronized
    fun recordWinningClient(trackType: String = TRACK_TYPE_MUSIC, client: InnertubeClient.ClientType) {
        if (client in NON_PROMOTABLE) {
            Log.d(TAG, "Not promoting last-resort client ${client.name} for $trackType")
            return
        }
        prefs.edit()
            .putString(KEY_PREFIX_WINNER + trackType, client.name)
            .putInt(KEY_PREFIX_FAILURES + trackType, 0)
            .putLong(KEY_PREFIX_RECORDED_AT + trackType, System.currentTimeMillis())
            .apply()
        Log.d(TAG, "Recorded winning client ${client.name} for $trackType")
    }

    /**
     * Increments the consecutive failure count for the current winner of [trackType].
     */
    @Synchronized
    fun recordFailure(trackType: String = TRACK_TYPE_MUSIC, client: InnertubeClient.ClientType) {
        val currentWinner = prefs.getString(KEY_PREFIX_WINNER + trackType, null)
        if (currentWinner == client.name) {
            val failures = prefs.getInt(KEY_PREFIX_FAILURES + trackType, 0) + 1
            prefs.edit().putInt(KEY_PREFIX_FAILURES + trackType, failures).apply()
            Log.w(TAG, "Recorded failure for winner $currentWinner on $trackType (total: $failures)")
            if (failures >= MAX_CONSECUTIVE_FAILURES) {
                clearWinner(trackType)
            }
        }
    }

    /**
     * Clears recorded winner for [trackType].
     */
    @Synchronized
    fun clearWinner(trackType: String = TRACK_TYPE_MUSIC) {
        prefs.edit()
            .remove(KEY_PREFIX_WINNER + trackType)
            .remove(KEY_PREFIX_FAILURES + trackType)
            .remove(KEY_PREFIX_RECORDED_AT + trackType)
            .apply()
    }

    /**
     * Clears all recorded winning clients across all track types.
     */
    @Synchronized
    fun clearAll() {
        prefs.edit().clear().apply()
    }
}
