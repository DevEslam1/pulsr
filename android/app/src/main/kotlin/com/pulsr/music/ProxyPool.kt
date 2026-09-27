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
    enum class FailureType {
        NETWORK, // Temporary network issue - retry in 30s
        TIMEOUT, // Server timeout - retry in 60s
        AUTH,    // Authentication failed - retry in 15m
        UNKNOWN  // Unknown failure - retry in 15m
    }
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
        val quality: Quality = Quality.UNKNOWN,
        var lastFailureType: FailureType = FailureType.UNKNOWN,
        var ewmaSuccessRate: Double = 1.0
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
    private val executor = Executors.newFixedThreadPool(8)
    private val probeExecutor = Executors.newCachedThreadPool()

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

    fun clear() = clearPool()

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

            // 2026-09 gap 5: prefer residential > unknown > datacenter, broken ties by EWMA success rate
            val ranked = aliveList.sortedWith(compareBy<ProxyNode> { it.quality.ordinal }.thenByDescending { it.ewmaSuccessRate })
            selected = ranked[Math.floorMod(activeProxyIndex, ranked.size)]
            activeProxyId = selected.id
            currentPathLabel = "${selected.type.name}:${selected.host}:${selected.port}"
        }

        return selected.toJavaProxy()
    }

    fun getActiveNode(): ProxyNode? {
        synchronized(lock) {
            val id = activeProxyId ?: return null
            return proxies.firstOrNull { it.id == id }
        }
    }

    fun applyAuthHeader(conn: HttpURLConnection, node: ProxyNode? = null) {
        val targetNode = node ?: getActiveNode()
        if (targetNode != null && targetNode.username.isNotEmpty()) {
            val userPass = "${targetNode.username}:${targetNode.password}"
            val basicAuth = "Basic " + android.util.Base64.encodeToString(userPass.toByteArray(), android.util.Base64.NO_WRAP)
            conn.setRequestProperty("Proxy-Authorization", basicAuth)
        }
    }

    fun resetNetworkFailures() {
        synchronized(lock) {
            proxies.filter { it.lastFailureType == FailureType.NETWORK }.forEach { node ->
                node.consecutiveFailures = 0
                node.deadUntilTimestamp = 0L
            }
        }
    }

    /**
     * Triggered on IP block or connection failure: marks current node failing and rotates.
     */
    fun onPathFailed(
        targetUrl: String? = null,
        failedHostOrId: String? = null,
        failureType: FailureType = FailureType.UNKNOWN
    ) {
        var newLabelToNotify: String? = null
        synchronized(lock) {
            if (proxies.isEmpty()) return

            // Attribute failure directly to the failing node rather than arbitrary modulo
            val failing = if (failedHostOrId != null) {
                proxies.firstOrNull { it.id == failedHostOrId || "${it.host}:${it.port}" == failedHostOrId || it.host == failedHostOrId }
            } else {
                activeProxyId?.let { id -> proxies.firstOrNull { it.id == id } }
            }

            if (failing != null) {
                failing.lastFailureType = failureType
                failing.consecutiveFailures++
                failing.ewmaSuccessRate = 0.2 * 0.0 + 0.8 * failing.ewmaSuccessRate
                val timeout = when (failureType) {
                    FailureType.NETWORK -> 30_000L
                    FailureType.TIMEOUT -> 60_000L
                    FailureType.AUTH, FailureType.UNKNOWN -> DEAD_TIMEOUT_MS
                }
                if (failing.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                    failing.deadUntilTimestamp = nowMs() + timeout
                    logW(TAG, "Proxy ${failing.host}:${failing.port} tripped circuit breaker; disabled for ${timeout / 1000}s due to $failureType")
                }
            }

            if (autoRotateEnabled) {
                val remainingAlive = proxies.filter { it.isAlive }
                if (remainingAlive.isNotEmpty()) {
                    activeProxyIndex = (activeProxyIndex + 1) % remainingAlive.size
                    val ranked = remainingAlive.sortedWith(compareBy<ProxyNode> { it.quality.ordinal }.thenByDescending { it.ewmaSuccessRate })
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
            target?.let {
                it.consecutiveFailures = 0
                it.ewmaSuccessRate = 0.2 * 1.0 + 0.8 * it.ewmaSuccessRate
            }
        }
    }

    /**
     * Happy-Eyeballs RFC 8305 proxy racing against generic probe endpoint (e.g. generate_204).
     * Dispatches candidate 0 immediately; if it doesn't respond within [staggerMs],
     * fires candidate 1 concurrently. The first candidate to verify wins and is promoted.
     */
    fun raceCandidatesHappyEyeballs(
        candidates: List<ProxyNode>,
        probeUrl: String = "https://www.google.com/generate_204",
        staggerMs: Long = 200L,
        timeoutMs: Int = 4000,
        callback: (ProxyNode?) -> Unit
    ) {
        if (candidates.isEmpty()) {
            callback(null)
            return
        }
        if (candidates.size == 1) {
            probeExecutor.execute {
                val success = testSingleProxy(candidates[0], probeUrl, timeoutMs)
                callback(if (success) candidates[0] else null)
            }
            return
        }

        probeExecutor.execute {
            val winnerRef = java.util.concurrent.atomic.AtomicReference<ProxyNode?>(null)
            val completedCount = java.util.concurrent.atomic.AtomicInteger(0)
            val total = candidates.size.coerceAtMost(3)
            val latch = java.util.concurrent.CountDownLatch(1)

            for (i in 0 until total) {
                if (winnerRef.get() != null) break
                val node = candidates[i]
                probeExecutor.execute {
                    val success = testSingleProxy(node, probeUrl, timeoutMs)
                    if (success && winnerRef.compareAndSet(null, node)) {
                        latch.countDown()
                    }
                    if (completedCount.incrementAndGet() >= total) {
                        latch.countDown()
                    }
                }
                if (i < total - 1 && winnerRef.get() == null) {
                    try {
                        Thread.sleep(staggerMs)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                    }
                }
            }

            try {
                latch.await(timeoutMs.toLong() + 500L, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            val winner = winnerRef.get()
            if (winner != null) {
                synchronized(lock) {
                    activeProxyId = winner.id
                    currentPathLabel = "${winner.type.name}:${winner.host}:${winner.port}"
                }
            }
            callback(winner)
        }
    }

    private fun testSingleProxy(node: ProxyNode, probeUrl: String, timeoutMs: Int): Boolean {
        var conn: HttpURLConnection? = null
        val start = System.currentTimeMillis()
        return try {
            val url = URL(probeUrl)
            conn = url.openConnection(node.toJavaProxy()) as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = true
            conn.requestMethod = "GET"
            if (node.username.isNotEmpty()) {
                val userPass = "${node.username}:${node.password}"
                val basicAuth = "Basic " + android.util.Base64.encodeToString(userPass.toByteArray(), android.util.Base64.NO_WRAP)
                conn.setRequestProperty("Proxy-Authorization", basicAuth)
            }
            val code = conn.responseCode
            val latency = System.currentTimeMillis() - start
            val success = code in 200..399
            node.latencyMs = if (success) latency else -1L
            if (success) {
                node.consecutiveFailures = 0
                node.deadUntilTimestamp = 0L
                node.ewmaSuccessRate = 0.2 * 1.0 + 0.8 * node.ewmaSuccessRate
            } else {
                node.ewmaSuccessRate = 0.2 * 0.0 + 0.8 * node.ewmaSuccessRate
            }
            success
        } catch (_: Throwable) {
            node.ewmaSuccessRate = 0.2 * 0.0 + 0.8 * node.ewmaSuccessRate
            false
        } finally {
            conn?.disconnect()
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
        val snapshot = proxies.toList()
        if (snapshot.isEmpty()) {
            callback(emptyList())
            return
        }

        executor.execute {
            val results = java.util.concurrent.ConcurrentHashMap<String, Map<String, Any?>>()
            val latch = java.util.concurrent.CountDownLatch(snapshot.size)

            for (node in snapshot) {
                probeExecutor.execute {
                    val start = System.currentTimeMillis()
                    var conn: HttpURLConnection? = null
                    try {
                        val url = URL(probeUrl)
                        conn = url.openConnection(node.toJavaProxy()) as HttpURLConnection
                        conn.connectTimeout = timeoutMs
                        conn.readTimeout = timeoutMs
                        conn.instanceFollowRedirects = true
                        conn.requestMethod = "GET"
                        if (node.username.isNotEmpty()) {
                            val userPass = "${node.username}:${node.password}"
                            val basicAuth = "Basic " + android.util.Base64.encodeToString(userPass.toByteArray(), android.util.Base64.NO_WRAP)
                            conn.setRequestProperty("Proxy-Authorization", basicAuth)
                        }

                        val code = conn.responseCode
                        val latency = System.currentTimeMillis() - start
                        val success = code in 200..399

                        node.latencyMs = if (success) latency else -1L
                        if (success) {
                            node.consecutiveFailures = 0
                            node.deadUntilTimestamp = 0L
                        } else {
                            node.lastFailureType = if (code == 401 || code == 407) FailureType.AUTH else FailureType.NETWORK
                            node.consecutiveFailures++
                            val timeout = if (node.lastFailureType == FailureType.AUTH) DEAD_TIMEOUT_MS else 30_000L
                            if (node.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                                node.deadUntilTimestamp = nowMs() + timeout
                                logW(TAG, "Proxy ${node.host}:${node.port} tripped circuit breaker during health check (HTTP $code); disabled for ${timeout / 1000}s")
                            }
                        }

                        results[node.id] = mapOf(
                            "id" to node.id,
                            "host" to node.host,
                            "port" to node.port,
                            "success" to success,
                            "latencyMs" to latency.toInt(),
                            "error" to if (!success) "HTTP $code" else null
                        )
                    } catch (e: Throwable) {
                        val latency = System.currentTimeMillis() - start
                        val isTimeout = e is java.net.SocketTimeoutException
                        node.lastFailureType = if (isTimeout) FailureType.TIMEOUT else FailureType.NETWORK
                        node.consecutiveFailures++
                        val timeout = if (isTimeout) 60_000L else 30_000L
                        if (node.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                            node.deadUntilTimestamp = nowMs() + timeout
                            logW(TAG, "Proxy ${node.host}:${node.port} tripped circuit breaker during health check (${e.message}); disabled for ${timeout / 1000}s")
                        }
                        results[node.id] = mapOf(
                            "id" to node.id,
                            "host" to node.host,
                            "port" to node.port,
                            "success" to false,
                            "latencyMs" to latency.toInt(),
                            "error" to (e.message ?: e.javaClass.simpleName)
                        )
                    } finally {
                        conn?.disconnect()
                        latch.countDown()
                    }
                }
            }

            try {
                latch.await(timeoutMs * 2L, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }

            val ordered = snapshot.mapNotNull { results[it.id] }
            callback(ordered)
        }
    }
}
