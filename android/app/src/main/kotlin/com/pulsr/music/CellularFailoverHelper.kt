package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import androidx.annotation.WorkerThread
import java.io.FilterInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Delegating connection used when the caller supplied no lifecycle reference:
 * the network callback is released exactly when the connection is disconnected
 * instead of on a timer that can fire while the stream is still being read.
 */
private class UnregisterOnDisconnectConnection(
    private val delegate: HttpURLConnection,
    private val onDisconnect: () -> Unit,
) : HttpURLConnection(delegate.url) {
    private val disconnected = AtomicBoolean(false)

    override fun connect() = delegate.connect()

    override fun disconnect() {
        if (disconnected.compareAndSet(false, true)) {
            runCatching { onDisconnect() }
        }
        delegate.disconnect()
    }

    override fun usingProxy(): Boolean = delegate.usingProxy()
    override fun getInputStream(): InputStream = closeAwareStream(delegate.inputStream)
    override fun getErrorStream(): InputStream? = delegate.errorStream?.let { closeAwareStream(it) }

    // Closing the stream is the common way callers finish a download; release
    // the network callback there too so it cannot leak until process death.
    private fun closeAwareStream(stream: InputStream): InputStream =
        object : FilterInputStream(stream) {
            override fun close() {
                try {
                    super.close()
                } finally {
                    disconnect()
                }
            }
        }

    override fun getOutputStream(): OutputStream = delegate.outputStream
    override fun getResponseCode(): Int = delegate.responseCode
    override fun getResponseMessage(): String? = delegate.responseMessage
    override fun getHeaderField(position: Int): String? = delegate.getHeaderField(position)
    override fun getHeaderField(name: String?): String? = delegate.getHeaderField(name)
    override fun getHeaderFields(): MutableMap<String, MutableList<String>> = delegate.headerFields
    override fun getHeaderFieldKey(n: Int): String? = delegate.getHeaderFieldKey(n)
    override fun getRequestMethod(): String = delegate.requestMethod
    override fun setRequestMethod(method: String) = delegate.setRequestMethod(method)
    override fun getContentLength(): Int = delegate.contentLength
    override fun getContentLengthLong(): Long = delegate.contentLengthLong
    override fun getContentType(): String? = delegate.contentType

    // Timeouts and headers must reach the wrapped connection; the base
    // HttpURLConnection would otherwise keep its own (unused) defaults and the
    // caller's timeout/header settings would silently do nothing.
    override fun setConnectTimeout(timeout: Int) {
        delegate.connectTimeout = timeout
    }

    override fun getConnectTimeout(): Int = delegate.connectTimeout

    override fun setReadTimeout(timeout: Int) {
        delegate.readTimeout = timeout
    }

    override fun getReadTimeout(): Int = delegate.readTimeout

    override fun setRequestProperty(key: String?, value: String?) {
        delegate.setRequestProperty(key, value)
    }

    override fun addRequestProperty(key: String?, value: String?) {
        delegate.addRequestProperty(key, value)
    }

    override fun getRequestProperties(): MutableMap<String, MutableList<String>> = delegate.requestProperties

    override fun getRequestProperty(key: String?): String? = delegate.getRequestProperty(key)
}

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
     * True when the active network is cellular.
     *
     * poTokens are bound to the egress they were minted on, and [EgressTracker]
     * distinguishes proxy / VPN / cellular / Wi-Fi. Without this query a Wi-Fi to
     * cellular switch kept the `wifi:direct` identity, so a token minted on one
     * path was replayed on the other and read back as PoTokenInvalid.
     */
    fun isCellularActive(context: Context): Boolean = runCatching {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return@runCatching false
        val network = cm.activeNetwork ?: return@runCatching false
        val caps = cm.getNetworkCapabilities(network) ?: return@runCatching false
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
    }.getOrDefault(false)

    /**
     * Executes an HTTP request strictly routed over the cellular network.
     * Optionally accepts an [onCloseRef] to receive a callback that unregisters
     * the network callback once the caller finishes streaming data.
     */
    @WorkerThread
    fun openCellularConnection(
        context: Context,
        targetUrl: String,
        timeoutMs: Int = 10000,
        onCloseRef: AtomicReference<(() -> Unit)?>? = null
    ): HttpURLConnection? {
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
            try {
                latch.await(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return null
            }
            val net = selectedNetwork.get()
            if (net != null) {
                val url = URL(targetUrl)
                val conn = net.openConnection(url) as? HttpURLConnection
                if (conn != null) {
                    val isUnregistered = AtomicBoolean(false)
                    val unregisterAction: () -> Unit = {
                        if (isUnregistered.compareAndSet(false, true)) {
                            runCatching { cm.unregisterNetworkCallback(callback) }
                        }
                    }
                    unregisterNeeded = false
                    if (onCloseRef != null) {
                        onCloseRef.set(unregisterAction)
                        conn
                    } else {
                        // No lifecycle ref: tie the callback release to the
                        // connection itself. A 10 s timer could unregister
                        // while a slow response body is still being read.
                        UnregisterOnDisconnectConnection(conn, unregisterAction)
                    }
                } else {
                    null
                }
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
    @WorkerThread
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
            try {
                latch.await(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return null
            }
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
