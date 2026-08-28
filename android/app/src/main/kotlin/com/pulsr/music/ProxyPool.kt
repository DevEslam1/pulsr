package com.pulsr.music

import android.net.Uri
import android.os.SystemClock
import android.util.Log
import java.net.Authenticator
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.PasswordAuthentication
import java.net.Proxy
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * Layer 4: Generic Network Proxy Pool & Path Rotation Engine.
 *
 * Placed in src/main: contains NO domain-specific terms to ensure strict GPL/Play isolation.
 *
 * Features:
 * - Multi-proxy pool (HTTP / SOCKS5)
 * - Health checks & latency scoring against generic probe endpoints
 * - Circuit breaker: 3 consecutive failures mark dead for 15 minutes
 * - Auto-rotation on path failure
 * - Path stickiness tracking
 */
object ProxyPool {
    private const val TAG = "ProxyPool"
    private const val DEAD_TIMEOUT_MS = 15 * 60 * 1000L // 15 minutes
    private const val MAX_CONSECUTIVE_FAILURES = 3

    private fun nowMs(): Long = try {
        SystemClock.elapsedRealtime()
    } catch (_: Throwable) {
        System.currentTimeMillis()
    }

    private fun logI(tag: String, msg: String) {
        try {
            Log.i(tag, msg)
        } catch (_: Throwable) {
            println("[$tag] $msg")
        }
    }

    private fun logW(tag: String, msg: String) {
        try {
            Log.w(tag, msg)
        } catch (_: Throwable) {
            System.err.println("[$tag] $msg")
        }
    }

    data class ProxyNode(
        val id: String,
        val type: Proxy.Type,
        val host: String,
        val port: Int,
        val username: String = "",
        val password: String = "",
        var latencyMs: Long = -1L,
        var consecutiveFailures: Int = 0,
        var deadUntilTimestamp: Long = 0L,
        var isEnabled: Boolean = true
    ) {
        val isAlive: Boolean
            get() {
                if (!isEnabled) return false
                val now = nowMs()
                return now >= deadUntilTimestamp
            }

        fun toJavaProxy(): Proxy {
            return Proxy(type, InetSocketAddress(host, port))
        }
    }

    private val proxies = CopyOnWriteArrayList<ProxyNode>()
    private val failureCounts = ConcurrentHashMap<String, Int>()
    private var activeProxyIndex = 0
    private var autoRotateEnabled = true
    private val executor = Executors.newFixedThreadPool(2)

    @Volatile
    var currentPathLabel: String = "DIRECT"
        private set

    @Volatile
    private var onPathChangeListener: ((String) -> Unit)? = null

    fun setOnPathChangeListener(listener: (String) -> Unit) {
        onPathChangeListener = listener
    }

    fun setAutoRotate(enabled: Boolean) {
        autoRotateEnabled = enabled
    }

    fun setProxies(list: List<ProxyNode>) {
        proxies.clear()
        proxies.addAll(list)
        activeProxyIndex = 0
        logI(TAG, "Proxy pool updated with ${list.size} proxies")
    }

    fun getActiveProxy(targetUrl: String? = null): Proxy? {
        if (proxies.isEmpty()) return null

        val aliveList = proxies.filter { it.isAlive }
        if (aliveList.isEmpty()) {
            currentPathLabel = "DIRECT"
            return null
        }

        val selected = aliveList[activeProxyIndex % aliveList.size]
        currentPathLabel = "${selected.type.name}:${selected.host}:${selected.port}"

        // Set authenticator if required
        if (selected.username.isNotEmpty()) {
            Authenticator.setDefault(object : Authenticator() {
                override fun getPasswordAuthentication(): PasswordAuthentication? {
                    if (requestorType == RequestorType.PROXY) {
                        return PasswordAuthentication(selected.username, selected.password.toCharArray())
                    }
                    return null
                }
            })
        }

        return selected.toJavaProxy()
    }

    /**
     * Triggered on IP block or connection failure: marks current node failing and rotates.
     */
    fun onPathFailed(targetUrl: String? = null) {
        if (proxies.isEmpty()) return

        val aliveList = proxies.filter { it.isAlive }
        if (aliveList.isNotEmpty()) {
            val failing = aliveList[activeProxyIndex % aliveList.size]
            failing.consecutiveFailures++

            if (failing.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                failing.deadUntilTimestamp = nowMs() + DEAD_TIMEOUT_MS
                logW(TAG, "Proxy ${failing.host}:${failing.port} tripped circuit breaker; disabled for 15m")
            }

            if (autoRotateEnabled) {
                activeProxyIndex = (activeProxyIndex + 1) % aliveList.size
                val newActive = proxies.filter { it.isAlive }.let {
                    if (it.isNotEmpty()) it[activeProxyIndex % it.size] else null
                }
                val newLabel = newActive?.let { "${it.type.name}:${it.host}:${it.port}" } ?: "DIRECT"
                currentPathLabel = newLabel
                logI(TAG, "Rotated proxy path to $newLabel")
                onPathChangeListener?.invoke(newLabel)
            }
        }
    }

    fun onPathSuccess() {
        if (proxies.isNotEmpty()) {
            val aliveList = proxies.filter { it.isAlive }
            if (aliveList.isNotEmpty()) {
                val current = aliveList[activeProxyIndex % aliveList.size]
                current.consecutiveFailures = 0
            }
        }
    }

    /**
     * Probes all configured proxies against a generic probe endpoint.
     */
    fun testAllProxies(
        probeUrl: String = "https://www.google.com/generate_204",
        timeoutMs: Int = 8000,
        callback: (List<Map<String, Any?>>) -> Unit
    ) {
        executor.execute {
            val results = mutableListOf<Map<String, Any?>>()
            for (node in proxies) {
                val start = System.currentTimeMillis()
                var conn: HttpURLConnection? = null
                try {
                    val url = URL(probeUrl)
                    conn = url.openConnection(node.toJavaProxy()) as HttpURLConnection
                    conn.connectTimeout = timeoutMs
                    conn.readTimeout = timeoutMs
                    conn.instanceFollowRedirects = true
                    conn.requestMethod = "GET"

                    val code = conn.responseCode
                    val latency = System.currentTimeMillis() - start
                    val success = code in 200..399

                    node.latencyMs = if (success) latency else -1L
                    if (success) {
                        node.consecutiveFailures = 0
                        node.deadUntilTimestamp = 0L
                    }

                    results.add(
                        mapOf(
                            "id" to node.id,
                            "host" to node.host,
                            "port" to node.port,
                            "success" to success,
                            "latencyMs" to latency.toInt(),
                            "error" to if (!success) "HTTP $code" else null
                        )
                    )
                } catch (e: Throwable) {
                    val latency = System.currentTimeMillis() - start
                    node.consecutiveFailures++
                    results.add(
                        mapOf(
                            "id" to node.id,
                            "host" to node.host,
                            "port" to node.port,
                            "success" to false,
                            "latencyMs" to latency.toInt(),
                            "error" to (e.message ?: e.javaClass.simpleName)
                        )
                    )
                } finally {
                    conn?.disconnect()
                }
            }
            callback(results)
        }
    }
}
