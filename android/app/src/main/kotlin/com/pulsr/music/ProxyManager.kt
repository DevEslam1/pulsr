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
    private var bypassList: List<String> = listOf("localhost", "127.0.0.1")

    @Volatile
    var pinnedIpFamily: String? = null // "ipv4" or "ipv6"
        private set

    fun setPinnedIpFamily(family: String?) {
        pinnedIpFamily = family?.lowercase()?.trim()
    }

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
    ) {
        this.enabled = enabled
        this.proxyType = (type ?: "http").lowercase()
        this.host = (host ?: "").trim()
        this.port = if (port != null && port in 1..65535) port else 8080
        this.username = (username ?: "").trim()
        this.password = password ?: ""
        this.bypassList = (bypassHosts ?: "localhost, 127.0.0.1")
            .split(",")
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }

        synchronized(authLock) {
            if (enabled && this.username.isNotEmpty()) {
                val auth = object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication? {
                        if (requestorType == RequestorType.PROXY) {
                            return PasswordAuthentication(this@ProxyManager.username, this@ProxyManager.password.toCharArray())
                        }
                        return null
                    }
                }
                proxyAuthenticator = auth
                Authenticator.setDefault(auth)
            } else {
                Authenticator.setDefault(null)
                proxyAuthenticator = null
            }
        }

        // Also configure ProxyPool if host is non-empty
        if (enabled && this.host.isNotEmpty()) {
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
            ProxyPool.setProxies(listOf(node))
        } else if (!enabled) {
            ProxyPool.setProxies(emptyList())
        }

        logI(TAG, "Proxy configured: enabled=$enabled, type=$proxyType, host=${this.host}:${this.port}, hasAuth=${this.username.isNotEmpty()}")
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
        bypassList = emptyList()
        ProxyPool.setProxies(emptyList())
    }

    /**
     * Checks whether the target [url] matches the bypass host list.
     */
    @Synchronized
    fun isBypassed(url: String?): Boolean {
        if (url == null) return false
        val uriHost = runCatching { java.net.URI(url).host?.lowercase() }
            .getOrNull()
            ?: runCatching { Uri.parse(url).host?.lowercase() }
            .getOrNull()
            ?: return false
        for (pattern in bypassList) {
            if (pattern == uriHost) return true
            if (pattern.startsWith("*.") && uriHost.endsWith(pattern.substring(2))) return true
            if (pattern == "localhost" && (uriHost == "localhost" || uriHost == "127.0.0.1")) return true
        }
        return false
    }

    /**
     * Returns a [Proxy] instance to be passed to [URL.openConnection], or null if
     * proxying is disabled or bypassed for [url].
     */
    @Synchronized
    fun getProxy(url: String? = null): Proxy? {
        if (!enabled) return null
        if (url != null && isBypassed(url)) return null

        val poolProxy = ProxyPool.getActiveProxy(url)
        if (poolProxy != null) return poolProxy

        if (host.isBlank() || port <= 0) return null
        val type = if (proxyType == "socks5" || proxyType == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
        return runCatching {
            Proxy(type, InetSocketAddress(host, port))
        }.getOrNull()
    }

    /** Returns Proxy-Authorization header for current active proxy if needed */
    fun getProxyAuthHeader(url: String? = null): String? {
        if (!enabled) return null
        if (username.isEmpty()) {
            // Check pool node credentials
            val poolNode = runCatching { ProxyPool }.getOrNull()?.let {
                // Try to retrieve selected node via reflection of aliveList
                null
            }
            return null
        }
        val creds = "$username:$password"
        return "Basic " + android.util.Base64.encodeToString(creds.toByteArray(Charsets.UTF_8), android.util.Base64.NO_WRAP)
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
            conn = (if (proxy != null) url.openConnection(proxy) else url.openConnection()) as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = true
            conn.requestMethod = "GET"
            conn.setRequestProperty("User-Agent", "PulsrMusic/1.0.0 (Android; +https://pulsr.app)")
            getProxyAuthHeader(testUrl)?.let { conn.setRequestProperty("Proxy-Authorization", it) }

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
