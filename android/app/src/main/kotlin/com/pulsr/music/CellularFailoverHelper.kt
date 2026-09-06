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
     * Keeps the network active for the lifetime of the connection.
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

        var unregisterNeeded = true
        return try {
            cm.requestNetwork(request, callback, timeoutMs)
            latch.await(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            val net = selectedNetwork.get()
            if (net != null) {
                val url = URL(targetUrl)
                val conn = net.openConnection(url) as? HttpURLConnection
                // Keep the network callback alive during connection usage, auto-unregistering after 60s
                unregisterNeeded = false
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    runCatching { cm.unregisterNetworkCallback(callback) }
                }, 60000L)
                conn
            } else {
                null
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Cellular network request failed: ${e.message}")
            null
        } finally {
            if (unregisterNeeded) {
                runCatching { cm.unregisterNetworkCallback(callback) }
            }
        }
    }

    /**
     * Executes a block within an active cellular connection scope and unregisters when done.
     */
    fun <T> withCellularConnection(
        context: Context,
        targetUrl: String,
        timeoutMs: Int = 10000,
        block: (HttpURLConnection) -> T
    ): T? {
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
            val net = selectedNetwork.get() ?: return null
            val url = URL(targetUrl)
            val conn = net.openConnection(url) as? HttpURLConnection ?: return null
            try {
                block(conn)
            } finally {
                conn.disconnect()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Cellular scoped connection failed: ${e.message}")
            null
        } finally {
            runCatching { cm.unregisterNetworkCallback(callback) }
        }
    }
}
