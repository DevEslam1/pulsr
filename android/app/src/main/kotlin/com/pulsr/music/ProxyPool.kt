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

    /** 2026-09: YouTube pre-flags datacenter IPs before cookie checks. */
    enum class Quality { RESIDENTIAL, UNKNOWN, DATACENTER }
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
        var isEnabled: Boolean = true,
        val quality: Quality = Quality.UNKNOWN
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
    private val lock = Any()
    private var activeProxyIndex = 0
    @Volatile
    private var activeProxyId: String? = null
    private var autoRotateEnabled = true
    private val executor = Executors.newFixedThreadPool(2)

    @Volatile
    var hasExplicitPool: Boolean = false
        private set

    @Volatile
    var currentPathLabel: String = "DIRECT"
        private set

    @Volatile
    private var onPathChangeListener: ((String) -> Unit)? = null

    fun setOnPathChangeListener(listener: (String) -> Unit) {
        onPathChangeListener = listener
    }

    fun setAutoRotate(enabled: Boolean) {
        synchronized(lock) {
            autoRotateEnabled = enabled
        }
    }

    fun setProxies(list: List<ProxyNode>, isExplicit: Boolean = true) {
        synchronized(lock) {
            proxies.clear()
            proxies.addAll(list)
            activeProxyIndex = 0
            activeProxyId = null
            hasExplicitPool = isExplicit
            if (list.isEmpty()) {
                currentPathLabel = "DIRECT"
            }
        }
        logI(TAG, "Proxy pool updated with ${list.size} proxies (explicit=$isExplicit)")
    }

    fun clearPool() {
        synchronized(lock) {
            proxies.clear()
            activeProxyIndex = 0
            activeProxyId = null
            hasExplicitPool = false
            currentPathLabel = "DIRECT"
        }
    }

    fun getActiveProxy(targetUrl: String? = null): Proxy? {
        val selected: ProxyNode
        synchronized(lock) {
            if (proxies.isEmpty()) {
                activeProxyId = null
                currentPathLabel = "DIRECT"
                return null
            }

            val aliveList = proxies.filter { it.isAlive }
            if (aliveList.isEmpty()) {
                activeProxyId = null
                currentPathLabel = "DIRECT"
                return null
            }

            // 2026-09 gap 5: prefer residential > unknown > datacenter; stable
            // within a tier so rotation behavior is preserved.
            val ranked = aliveList.sortedBy { it.quality.ordinal }
            selected = ranked[Math.floorMod(activeProxyIndex, ranked.size)]
            activeProxyId = selected.id
            currentPathLabel = "${selected.type.name}:${selected.host}:${selected.port}"
        }

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
        } else {
            Authenticator.setDefault(null)
        }

        return selected.toJavaProxy()
    }

    /**
     * Triggered on IP block or connection failure: marks current node failing and rotates.
     */
    fun onPathFailed(targetUrl: String? = null, failedHostOrId: String? = null) {
        var newLabelToNotify: String? = null
        synchronized(lock) {
            if (proxies.isEmpty()) return

            // Attribute failure directly to the failing node rather than arbitrary modulo
            val failing = if (failedHostOrId != null) {
                proxies.firstOrNull { it.id == failedHostOrId || "${it.host}:${it.port}" == failedHostOrId || it.host == failedHostOrId }
            } else {
                activeProxyId?.let { id -> proxies.firstOrNull { it.id == id } }
                    ?: proxies.filter { it.isAlive }.let {
                        if (it.isNotEmpty()) it[Math.floorMod(activeProxyIndex, it.size)] else null
                    }
            }

            if (failing != null) {
                failing.consecutiveFailures++
                if (failing.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                    failing.deadUntilTimestamp = nowMs() + DEAD_TIMEOUT_MS
                    logW(TAG, "Proxy ${failing.host}:${failing.port} tripped circuit breaker; disabled for 15m")
                }
            }

            if (autoRotateEnabled) {
                val remainingAlive = proxies.filter { it.isAlive }
                if (remainingAlive.isNotEmpty()) {
                    activeProxyIndex = (activeProxyIndex + 1) % remainingAlive.size
                    val ranked = remainingAlive.sortedBy { it.quality.ordinal }
                    val newActive = ranked[Math.floorMod(activeProxyIndex, ranked.size)]
                    activeProxyId = newActive.id
                    val newLabel = "${newActive.type.name}:${newActive.host}:${newActive.port}"
                    currentPathLabel = newLabel
                    newLabelToNotify = newLabel
                    logI(TAG, "Rotated proxy path to $newLabel")
                } else {
                    activeProxyId = null
                    currentPathLabel = "DIRECT"
                    newLabelToNotify = "DIRECT"
                    logI(TAG, "All proxies dead, rotated path to DIRECT")
                }
            }
        }
        newLabelToNotify?.let { label ->
            onPathChangeListener?.invoke(label)
        }
    }

    fun onPathSuccess(successHostOrId: String? = null) {
        synchronized(lock) {
            val target = if (successHostOrId != null) {
                proxies.firstOrNull { it.id == successHostOrId || "${it.host}:${it.port}" == successHostOrId || it.host == successHostOrId }
            } else {
                activeProxyId?.let { id -> proxies.firstOrNull { it.id == id } }
                    ?: proxies.filter { it.isAlive }.let {
                        if (it.isNotEmpty()) it[Math.floorMod(activeProxyIndex, it.size)] else null
                    }
            }
            target?.consecutiveFailures = 0
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
                    } else {
                        node.consecutiveFailures++
                        if (node.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                            node.deadUntilTimestamp = nowMs() + DEAD_TIMEOUT_MS
                            logW(TAG, "Proxy ${node.host}:${node.port} tripped circuit breaker during health check (HTTP $code); disabled for 15m")
                        }
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
                    if (node.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                        node.deadUntilTimestamp = nowMs() + DEAD_TIMEOUT_MS
                        logW(TAG, "Proxy ${node.host}:${node.port} tripped circuit breaker during health check (${e.message}); disabled for 15m")
                    }
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
