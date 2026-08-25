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
 * [Proxy] objects for [PulsrDownloader] (NewPipeExtractor) and [InnertubeClient].
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

        applySystemProperties()
        Log.i(TAG, "Proxy configured: enabled=$enabled, type=$proxyType, host=${this.host}:${this.port}, hasAuth=${this.username.isNotEmpty()}")
    }

    private fun applySystemProperties() {
        if (enabled && host.isNotEmpty() && port > 0) {
            val nonProxyHosts = bypassList.joinToString("|")

            if (proxyType == "socks5" || proxyType == "socks") {
                System.setProperty("socksProxyHost", host)
                System.setProperty("socksProxyPort", port.toString())
                System.clearProperty("http.proxyHost")
                System.clearProperty("http.proxyPort")
                System.clearProperty("https.proxyHost")
                System.clearProperty("https.proxyPort")
            } else {
                System.setProperty("http.proxyHost", host)
                System.setProperty("http.proxyPort", port.toString())
                System.setProperty("https.proxyHost", host)
                System.setProperty("https.proxyPort", port.toString())
                System.setProperty("http.nonProxyHosts", nonProxyHosts)
                System.setProperty("https.nonProxyHosts", nonProxyHosts)
                System.clearProperty("socksProxyHost")
                System.clearProperty("socksProxyPort")
            }

            if (username.isNotEmpty()) {
                val currentHost = host
                val currentPort = port
                val user = username
                val pass = password
                Authenticator.setDefault(object : Authenticator() {
                    override fun getPasswordAuthentication(): PasswordAuthentication? {
                        if (requestingHost.equals(currentHost, ignoreCase = true) || requestingPort == currentPort) {
                            return PasswordAuthentication(user, pass.toCharArray())
                        }
                        return null
                    }
                })
            } else {
                Authenticator.setDefault(null)
            }
        } else {
            System.clearProperty("http.proxyHost")
            System.clearProperty("http.proxyPort")
            System.clearProperty("https.proxyHost")
            System.clearProperty("https.proxyPort")
            System.clearProperty("http.nonProxyHosts")
            System.clearProperty("https.nonProxyHosts")
            System.clearProperty("socksProxyHost")
            System.clearProperty("socksProxyPort")
            Authenticator.setDefault(null)
        }
    }

    /**
     * Checks whether the target [url] matches the bypass host list.
     */
    fun isBypassed(url: String?): Boolean {
        if (url == null) return false
        val uriHost = runCatching { Uri.parse(url).host?.lowercase() }.getOrNull() ?: return false
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
    fun getProxy(url: String? = null): Proxy? {
        if (!enabled || host.isBlank() || port <= 0) return null
        if (url != null && isBypassed(url)) return null

        val type = if (proxyType == "socks5" || proxyType == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
        return runCatching {
            Proxy(type, InetSocketAddress(host, port))
        }.getOrNull()
    }

    /**
     * Probes proxy connectivity to [testUrl] and returns latency in milliseconds or an error message.
     */
    fun testConnection(
        testUrl: String = "https://music.youtube.com/generate_204",
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
