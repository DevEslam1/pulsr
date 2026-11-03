package com.pulsr.music

import android.net.Uri
import android.util.Log
import java.net.Authenticator
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.PasswordAuthentication
import java.net.Proxy
import java.net.URL

/**
 * Thread-safe JVM & Application Proxy Manager.
 *
 * Configures system-wide Java network properties and provides explicit
 * [Proxy] objects for network clients and [InnertubeClient].
 *
 * Fully generic (no YTM or domain-specific terms) to preserve GPL / Play isolation.
 */
object ProxyManager {
    private const val TAG = "ProxyManager"

    @Volatile
    var enabled: Boolean = false
        private set

    @Volatile
    var proxyType: String = "http" // "http" or "socks5"
        private set

    @Volatile
    var host: String = ""
        private set

    @Volatile
    var port: Int = 8080
        private set

    @Volatile
    var username: String = ""
        private set

    @Volatile
    var password: String = ""
        private set

    @Volatile
    var failClosed: Boolean = false
        private set

    /** True when failClosed is set and every configured proxy path is dead. */
    @Volatile
    var blocked: Boolean = false
        private set

    fun isBlocked(): Boolean = blocked

    private val defaultBypassList = listOf(
        "localhost",
        "127.0.0.1",
        "::1",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "*.local",
    )

    private val LEGACY_DEFAULT_BYPASS = listOf("localhost", "127.0.0.1")

    @Volatile
    private var bypassList: List<String> = defaultBypassList

    @Volatile
    private var directFallbackLogged: Boolean = false

    private var proxyAuthenticator: Authenticator? = null
    private val authLock = Any()

    @Synchronized
    fun setProxy(
        enabled: Boolean,
        type: String?,
        host: String?,
        port: Int?,
        username: String?,
        password: String?,
        bypassHosts: String?,
        failClosed: Boolean = false,
    ) {
        this.enabled = enabled
        this.proxyType = (type ?: "http").lowercase()
        this.host = (host ?: "").trim()
        this.port = if (port != null && port in 1..65535) port else 8080
        this.username = (username ?: "").trim()
        this.password = password ?: ""
        this.failClosed = failClosed
        this.blocked = false
        this.directFallbackLogged = false
        val parsedBypass = if (bypassHosts == null) {
            defaultBypassList
        } else {
            bypassHosts.split(",")
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
        }
        // The Dart settings layer still ships 'localhost, 127.0.0.1' as its
        // default. Treat that exact legacy value as "no custom list" so the
        // private-range/::1/*.local defaults actually protect LAN requests.
        this.bypassList = if (parsedBypass == LEGACY_DEFAULT_BYPASS) {
            defaultBypassList
        } else {
            parsedBypass
        }

        // Also configure ProxyPool if host is non-empty, unless an explicit multi-proxy pool was set
        if (enabled && this.host.isNotEmpty()) {
            if (!ProxyPool.hasExplicitPool) {
                val pType = if (this.proxyType == "socks5" || this.proxyType == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
                val node = ProxyPool.ProxyNode(
                    id = "${this.host}:${this.port}",
                    type = pType,
                    host = this.host,
                    port = this.port,
                    username = this.username,
                    password = this.password,
                    isEnabled = true
                )
                ProxyPool.setProxies(listOf(node), isExplicit = false)
            }
        } else if (!enabled) {
            if (!ProxyPool.hasExplicitPool) {
                ProxyPool.setProxies(emptyList(), isExplicit = false)
            }
        }

        // Install/refresh the JVM Authenticator after the pool is updated so a
        // pool-only configuration (setProxyPool without setProxy) can still
        // authenticate HTTPS CONNECT tunnels.
        refreshAuthenticator()

        logI(TAG, "Proxy configured: enabled=$enabled, type=$proxyType, host=${this.host}:${this.port}, hasAuth=${this.username.isNotEmpty()}")
    }

    /**
     * Installs the proxy Authenticator for the current pool/single-proxy
     * configuration. Safe to call after setProxyPool; credentials are resolved
     * at challenge time, so the authenticator never captures a stale node.
     */
    fun refreshAuthenticator() {
        synchronized(authLock) {
            if (!enabled && !ProxyPool.isPoolConfigured()) {
                Authenticator.setDefault(null)
                proxyAuthenticator = null
                return
            }
            val auth = object : Authenticator() {
                override fun getPasswordAuthentication(): PasswordAuthentication? {
                    if (requestorType != RequestorType.PROXY) return null
                    // HTTPS CONNECT authenticates here, never via a header.
                    // Match credentials to the exact proxy endpoint that
                    // challenged us, so rotating pools authenticate with
                    // the node that is actually serving the tunnel.
                    val fromPool = ProxyPool.credentialsFor(requestingHost, requestingPort)
                    if (fromPool != null) {
                        return PasswordAuthentication(fromPool.first, fromPool.second.toCharArray())
                    }
                    if (this@ProxyManager.username.isNotEmpty() &&
                        requestingHost.equals(this@ProxyManager.host, ignoreCase = true) &&
                        (requestingPort == this@ProxyManager.port || requestingPort == -1)) {
                        return PasswordAuthentication(
                            this@ProxyManager.username,
                            this@ProxyManager.password.toCharArray()
                        )
                    }
                    return null
                }
            }
            proxyAuthenticator = auth
            Authenticator.setDefault(auth)
        }
    }

    private fun logI(tag: String, msg: String) {
        try {
            Log.i(tag, msg)
        } catch (_: Throwable) {
            println("[$tag] $msg")
        }
    }

    /**
     * Resets proxy state and removes the default Authenticator.
     */
    @Synchronized
    fun dispose() {
        synchronized(authLock) {
            Authenticator.setDefault(null)
            proxyAuthenticator = null
        }
        enabled = false
        host = ""
        port = 0
        username = ""
        password = ""
        failClosed = false
        blocked = false
        directFallbackLogged = false
        bypassList = emptyList()
        ProxyPool.clearPool()
    }

    /**
     * Checks whether the target [url] matches the bypass host list.
     */
    @Synchronized
    fun isBypassed(url: String?): Boolean {
        if (url == null) return false
        val uriHost = (runCatching { java.net.URI(url).host?.lowercase() }
            .getOrNull()
            ?: runCatching { Uri.parse(url).host?.lowercase() }
            .getOrNull()
            ?: return false).removePrefix("[").removeSuffix("]")
        for (pattern in bypassList) {
            if (pattern == uriHost) return true
            if (pattern == "::1" && uriHost == "::1") return true
            // Literal-IP CIDR matching only; hostnames are never resolved here.
            if (pattern.contains('/') && ipv4InCidr(uriHost, pattern)) return true
            // Require a dot boundary so *.example.com does NOT match fakeexample.com.
            if (pattern.startsWith("*.")) {
                val domain = pattern.substring(2)
                if (uriHost == domain || uriHost.endsWith(".$domain")) return true
            }
            if (pattern == "localhost" && (uriHost == "localhost" || uriHost == "127.0.0.1")) return true
        }
        return false
    }

    private fun ipv4ToLong(host: String): Long? {
        val parts = host.split('.')
        if (parts.size != 4) return null
        var value = 0L
        for (part in parts) {
            val octet = part.toIntOrNull() ?: return null
            if (octet !in 0..255) return null
            value = (value shl 8) or octet.toLong()
        }
        return value
    }

    private fun ipv4InCidr(host: String, cidr: String): Boolean {
        val hostValue = ipv4ToLong(host) ?: return false
        val slash = cidr.indexOf('/')
        if (slash <= 0) return false
        val network = ipv4ToLong(cidr.substring(0, slash)) ?: return false
        val prefix = cidr.substring(slash + 1).toIntOrNull() ?: return false
        if (prefix !in 0..32) return false
        if (prefix == 0) return true
        val mask = (0xFFFFFFFFL shl (32 - prefix)) and 0xFFFFFFFFL
        return (hostValue and mask) == (network and mask)
    }

    /**
     * Returns a [Proxy] instance to be passed to [URL.openConnection], or null if
     * proxying is disabled or bypassed for [url].
     */
    @Synchronized
    fun getProxy(url: String? = null): Proxy? {
        if (!enabled) {
            blocked = false
            return null
        }
        if (url != null && isBypassed(url)) {
            blocked = false
            return null
        }

        val poolProxy = ProxyPool.getActiveProxy(url)
        if (poolProxy != null) {
            blocked = false
            directFallbackLogged = false
            return poolProxy
        }

        // A configured pool with no live node means the circuit breaker is
        // open. Falling back to the raw configured host here would ignore the
        // breaker and hammer a known-dead endpoint.
        if (ProxyPool.isPoolConfigured()) {
            if (failClosed) {
                if (!blocked) Log.w(TAG, "All proxy paths are dead; failing closed (no DIRECT fallback)")
                blocked = true
            } else {
                if (!directFallbackLogged) {
                    Log.w(TAG, "All proxy paths are dead; using DIRECT")
                    directFallbackLogged = true
                }
                blocked = false
            }
            return null
        }

        blocked = false
        if (host.isBlank() || port <= 0) return null
        val type = if (proxyType == "socks5" || proxyType == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
        return runCatching {
            Proxy(type, InetSocketAddress.createUnresolved(host, port))
        }.getOrNull()
    }

    fun onPathFailed(url: String? = null) {
        ProxyPool.onPathFailed(url)
    }

    fun onPathSuccess() {
        ProxyPool.onPathSuccess()
    }

    /**
     * Probes proxy connectivity to [testUrl] and returns latency in milliseconds or an error message.
     */
    fun testConnection(
        testUrl: String = "https://www.google.com/generate_204",
        timeoutMs: Int = 10000,
    ): Map<String, Any?> {
        val start = System.currentTimeMillis()
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(testUrl)
            val proxy = getProxy(testUrl)
            if (proxy == null && isBlocked()) {
                return mapOf(
                    "success" to false,
                    "latencyMs" to (System.currentTimeMillis() - start).toInt(),
                    "error" to "PROXY_BLOCKED",
                )
            }
            conn = (if (proxy != null) url.openConnection(proxy) else url.openConnection()) as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = true
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "PulsrMusic/1.0.0 (Android; +https://pulsr.app)")

            val code = conn.responseCode
            val elapsed = System.currentTimeMillis() - start

            if (code in 200..399) {
                mapOf("success" to true, "latencyMs" to elapsed.toInt(), "error" to null)
            } else {
                mapOf("success" to false, "latencyMs" to elapsed.toInt(), "error" to "HTTP $code: ${conn.responseMessage}")
            }
        } catch (e: Throwable) {
            val elapsed = System.currentTimeMillis() - start
            Log.w(TAG, "Proxy test failed: ${e.message}")
            mapOf(
                "success" to false,
                "latencyMs" to elapsed.toInt(),
                "error" to (e.localizedMessage ?: e.javaClass.simpleName),
            )
        } finally {
            conn?.disconnect()
        }
    }
}
