package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Task B6: Egress & IP-Binding Session Manager for YouTube Music.
 *
 * Ensures that googlevideo playback and download URLs are resolved and fetched through the
 * exact same IP egress (network interface + active proxy node). Prevents mid-stream 403 Forbidden
 * caused by IP mismatch when network changes or proxy rotates.
 *
 * Features:
 * - Sticky egress per playback session/track
 * - Dynamic Egress ID: "${networkType}_${proxyExit}"
 * - Event-driven notification to Dart layer on connectivity / proxy transitions
 * - URL invalidation & re-pre-resolution trigger on egress changes
 */
class EgressSessionManager(
    private val context: Context? = null
) {
    companion object {
        private const val TAG = "EgressSessionManager"

        @Volatile
        private var instance: EgressSessionManager? = null

        fun getInstance(context: Context? = null): EgressSessionManager {
            return instance ?: synchronized(this) {
                instance ?: EgressSessionManager(context?.applicationContext).also { instance = it }
            }
        }
    }

    @Volatile
    private var currentNetworkType: String = "WIFI"

    @Volatile
    private var currentProxyExit: String = "DIRECT"

    @Volatile
    private var activeSessionTrackId: String? = null

    @Volatile
    private var activeSessionEgressId: String? = null

    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    init {
        updateProxyExit(ProxyPool.currentPathLabel)
        ProxyPool.setOnPathChangeListener { newPath ->
            updateProxyExit(newPath)
        }
        setupNetworkMonitoring()
    }

    private fun setupNetworkMonitoring() {
        if (context == null) return
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    val newType = when {
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "WIFI"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "CELLULAR"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ETHERNET"
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "VPN"
                        else -> "OTHER"
                    }
                    if (newType != currentNetworkType) {
                        currentNetworkType = newType
                        onEgressChanged()
                    }
                }

                override fun onLost(network: Network) {
                    currentNetworkType = "NONE"
                    onEgressChanged()
                }
            }
            cm.registerNetworkCallback(request, networkCallback!!)
        } catch (t: Throwable) {
            Log.w(TAG, "Network callback registration failed non-fatally: ${t.message}")
        }
    }

    @Synchronized
    fun updateNetworkTypeForTesting(networkType: String) {
        if (currentNetworkType != networkType) {
            currentNetworkType = networkType
            onEgressChanged()
        }
    }

    @Synchronized
    fun updateProxyExit(proxyExit: String) {
        val normalized = if (proxyExit.isBlank()) "DIRECT" else proxyExit
        if (currentProxyExit != normalized) {
            currentProxyExit = normalized
            onEgressChanged()
        }
    }

    /**
     * Current composite egress identifier: e.g. "WIFI_DIRECT" or "CELLULAR_HTTP:192.168.1.1:8080".
     */
    val currentEgressId: String
        get() = "${currentNetworkType}_${currentProxyExit}"

    /**
     * Binds a track to the current active egress, establishing sticky session for its playback duration.
     */
    @Synchronized
    fun bindTrackSession(trackId: String): String {
        activeSessionTrackId = trackId
        val egress = currentEgressId
        activeSessionEgressId = egress
        return egress
    }

    /**
     * Rotates proxy exit cleanly between tracks (never mid-track) and notifies cache listeners.
     */
    @Synchronized
    fun rotateBetweenTracks(newProxyExit: String? = null): String {
        if (newProxyExit != null) {
            currentProxyExit = newProxyExit
        } else {
            ProxyPool.onPathFailed()
            currentProxyExit = ProxyPool.currentPathLabel
        }
        val newEgress = currentEgressId
        activeSessionEgressId = newEgress
        onEgressChanged()
        return newEgress
    }

    /**
     * Validates whether a cached URL's egress ID matches the currently active egress.
     */
    fun isEgressValid(resolvedEgressId: String?): Boolean {
        if (resolvedEgressId == null || resolvedEgressId.isEmpty()) return true
        return resolvedEgressId == currentEgressId
    }

    fun addOnEgressChangeListener(listener: (String) -> Unit) {
        listeners.add(listener)
    }

    fun removeOnEgressChangeListener(listener: (String) -> Unit) {
        listeners.remove(listener)
    }

    private fun onEgressChanged() {
        val egress = currentEgressId
        Log.i(TAG, "Egress changed to $egress; notifying ${listeners.size} listeners")
        for (l in listeners) {
            try {
                l.invoke(egress)
            } catch (t: Throwable) {
                Log.w(TAG, "Listener error during egress change: ${t.message}")
            }
        }
    }
}
