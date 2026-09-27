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

    private val appContext: Context = context.applicationContext
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

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

    @Volatile private var cachedNetworkClass: String? = null
    @Volatile private var lastNetworkQueryTimeMs: Long = 0L

    fun getCurrentNetworkClass(): String {
        val now = android.os.SystemClock.elapsedRealtime()
        val cached = cachedNetworkClass
        if (cached != null && (now - lastNetworkQueryTimeMs) < 5_000L) {
            return cached
        }
        val result = try {
            val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
                ?: return "unknown"
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val net = cm.activeNetwork ?: return "none"
                val caps = cm.getNetworkCapabilities(net) ?: return "unknown"
                when {
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
                    caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    else -> "other"
                }
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo ?: return "none"
                @Suppress("DEPRECATION")
                if (info.type == android.net.ConnectivityManager.TYPE_WIFI) "wifi" else "cellular"
            }
        } catch (_: Throwable) {
            "unknown"
        }
        cachedNetworkClass = result
        lastNetworkQueryTimeMs = now
        return result
    }

    fun buildDimensionKey(trackType: String, hourBucket: Int? = null, networkClass: String? = null): String {
        val h = hourBucket ?: (java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY) / 4)
        val net = networkClass ?: getCurrentNetworkClass()
        return "${trackType}_h${h}_$net"
    }

    private fun getWinningClientForKey(key: String): InnertubeClient.ClientType? {
        val clientName = prefs.getString(KEY_PREFIX_WINNER + key, null) ?: return null
        val failures = prefs.getInt(KEY_PREFIX_FAILURES + key, 0)
        if (failures >= MAX_CONSECUTIVE_FAILURES) {
            Log.d(TAG, "Evicting winner $clientName for $key due to $failures consecutive failures")
            clearWinner(key)
            return null
        }
        val recordedAt = prefs.getLong(KEY_PREFIX_RECORDED_AT + key, 0L)
        val age = System.currentTimeMillis() - recordedAt
        if (recordedAt <= 0L || age > WINNER_TTL_MS || age < 0L) {
            Log.d(TAG, "Evicting stale winner $clientName for $key (age ${age}ms)")
            clearWinner(key)
            return null
        }
        return try {
            InnertubeClient.ClientType.valueOf(clientName)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /**
     * Returns the cached winning client for [trackType] in the current (or specified)
     * hour-bucket and network-class, falling back to the coarse trackType winner if none recorded.
     */
    @Synchronized
    fun getWinningClient(
        trackType: String = TRACK_TYPE_MUSIC,
        hourBucket: Int? = null,
        networkClass: String? = null
    ): InnertubeClient.ClientType? {
        val dimKey = buildDimensionKey(trackType, hourBucket, networkClass)
        val dimWinner = getWinningClientForKey(dimKey)
        if (dimWinner != null) return dimWinner
        return getWinningClientForKey(trackType)
    }

    /**
     * Records a successful client resolution for [trackType] under both the dimensioned
     * and general keys, resetting any failure count.
     */
    @Synchronized
    fun recordWinningClient(
        trackType: String = TRACK_TYPE_MUSIC,
        client: InnertubeClient.ClientType,
        hourBucket: Int? = null,
        networkClass: String? = null
    ) {
        if (client in NON_PROMOTABLE) {
            Log.d(TAG, "Not promoting last-resort client ${client.name} for $trackType")
            return
        }
        val now = System.currentTimeMillis()
        val dimKey = buildDimensionKey(trackType, hourBucket, networkClass)
        prefs.edit()
            .putString(KEY_PREFIX_WINNER + trackType, client.name)
            .putInt(KEY_PREFIX_FAILURES + trackType, 0)
            .putLong(KEY_PREFIX_RECORDED_AT + trackType, now)
            .putString(KEY_PREFIX_WINNER + dimKey, client.name)
            .putInt(KEY_PREFIX_FAILURES + dimKey, 0)
            .putLong(KEY_PREFIX_RECORDED_AT + dimKey, now)
            .apply()
        Log.d(TAG, "Recorded winning client ${client.name} for $trackType (dim=$dimKey)")
    }

    /**
     * Increments the consecutive failure count for the current winner of [trackType].
     */
    @Synchronized
    fun recordFailure(
        trackType: String = TRACK_TYPE_MUSIC,
        client: InnertubeClient.ClientType,
        hourBucket: Int? = null,
        networkClass: String? = null
    ) {
        val dimKey = buildDimensionKey(trackType, hourBucket, networkClass)
        for (key in listOf(trackType, dimKey)) {
            val currentWinner = prefs.getString(KEY_PREFIX_WINNER + key, null)
            if (currentWinner == client.name) {
                val failures = prefs.getInt(KEY_PREFIX_FAILURES + key, 0) + 1
                prefs.edit().putInt(KEY_PREFIX_FAILURES + key, failures).apply()
                Log.w(TAG, "Recorded failure for winner $currentWinner on $key (total: $failures)")
                if (failures >= MAX_CONSECUTIVE_FAILURES) {
                    clearWinner(key)
                }
            }
        }
    }


    /**
     * Clears recorded winner for [trackType].
     */
    @Synchronized
    fun clearWinner(trackType: String = TRACK_TYPE_MUSIC) {
        val editor = prefs.edit()
        val exactWinner = KEY_PREFIX_WINNER + trackType
        val exactFailures = KEY_PREFIX_FAILURES + trackType
        val exactRecordedAt = KEY_PREFIX_RECORDED_AT + trackType

        val prefixWinner = KEY_PREFIX_WINNER + trackType + "_"
        val prefixFailures = KEY_PREFIX_FAILURES + trackType + "_"
        val prefixRecordedAt = KEY_PREFIX_RECORDED_AT + trackType + "_"

        editor.remove(exactWinner).remove(exactFailures).remove(exactRecordedAt)

        for (k in prefs.all.keys) {
            if (k.startsWith(prefixWinner) || k.startsWith(prefixFailures) || k.startsWith(prefixRecordedAt)) {
                editor.remove(k)
            }
        }
        editor.apply()
    }

    /**
     * Clears all recorded winning clients across all track types.
     */
    @Synchronized
    fun clearAll() {
        prefs.edit().clear().apply()
    }
}
