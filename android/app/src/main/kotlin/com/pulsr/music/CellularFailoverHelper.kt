package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Layer 4: Cellular Network Failover Helper.
 *
 * Allows requesting temporary cellular transport when Wi-Fi encounters blocking.
 * Strictly generic (no domain terms) in src/main.
 */
object CellularFailoverHelper {
    private const val TAG = "CellularFailover"

    fun isVpnActive(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } else {
            false
        }
    }

    /**
     * Executes an HTTP request strictly routed over the cellular network.
     */
    fun openCellularConnection(context: Context, targetUrl: String, timeoutMs: Int = 10000): HttpURLConnection? {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return null
        val latch = CountDownLatch(1)
        val selectedNetwork = AtomicReference<Network?>(null)

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                selectedNetwork.set(network)
                latch.countDown()
            }

            override fun onUnavailable() {
                latch.countDown()
            }
        }

        return try {
            cm.requestNetwork(request, callback, timeoutMs)
            latch.await(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            val net = selectedNetwork.get()
            if (net != null) {
                val url = URL(targetUrl)
                net.openConnection(url) as? HttpURLConnection
            } else {
                null
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Cellular network request failed: ${e.message}")
            null
        } finally {
            runCatching { cm.unregisterNetworkCallback(callback) }
        }
    }
}
