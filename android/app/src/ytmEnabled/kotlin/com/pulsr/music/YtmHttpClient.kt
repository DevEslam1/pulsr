package com.pulsr.music

import android.content.Context
import android.util.Log
import okhttp3.ConnectionPool
import okhttp3.Dns
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import java.net.InetAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Task 6 — Connection, DNS, and Proxy Hygiene Engine for YouTube Music.
 *
 * Features:
 * - Single shared OkHttpClient across resolution layer
 * - ConnectionPool: keep-alive 5 min, max 8 idle connections
 * - TtlDnsCache: 10 min in-memory DNS TTL cache with DoH fallback for YouTube & googlevideo domains
 * - TLS pre-connect: warms TCP + TLS sockets to googlevideo servers in background
 * - Proxy hygiene: 0 ms overhead when proxy disabled
 */
internal object YtmHttpClient {
    private const val TAG = "YtmHttpClient"

    /**
     * In-memory TTL DNS cache with DoH fallback.
     */
    class TtlDnsCache(
        private val ttlMs: Long = 10 * 60 * 1000L // 10 minutes
    ) : Dns {
        private val cache = ConcurrentHashMap<String, Pair<List<InetAddress>, Long>>()

    companion object {
        val instance = TtlDnsCache()
        private val IPV4_REGEX =
            Regex("^((25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)\\.){3}(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)$")
    }

        @Throws(UnknownHostException::class)
        override fun lookup(hostname: String): List<InetAddress> {
            val now = System.currentTimeMillis()
            val cached = cache[hostname]
            if (cached != null && (now - cached.second) < ttlMs && cached.first.isNotEmpty()) {
                return cached.first
            }

            return try {
                val addresses = Dns.SYSTEM.lookup(hostname)
                if (addresses.isNotEmpty()) {
                    cache[hostname] = addresses to now
                }
                addresses
            } catch (e: UnknownHostException) {
                // DoH fallback for YouTube & googlevideo domains
                val dohResult = resolveDoH(hostname)
                if (dohResult.isNotEmpty()) {
                    cache[hostname] = dohResult to now
                    dohResult
                } else {
                    // If cached entry exists even if stale, use it as disaster recovery
                    if (cached != null && cached.first.isNotEmpty()) {
                        Log.w(TAG, "System DNS failed for $hostname, using stale cached IP")
                        cached.first
                    } else {
                        throw e
                    }
                }
            }
        }

        /**
         * Resolves hostname via Google Public DNS over HTTPS (DoH).
         */
        private fun resolveDoH(hostname: String): List<InetAddress> {
            return try {
                val dohUrl = "https://dns.google/resolve?name=$hostname&type=A"
                val conn = (java.net.URL(dohUrl).openConnection() as java.net.HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 3000
                    setRequestProperty("Accept", "application/dns-json")
                }
                val body = conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
                val json = JSONObject(body)
                val answers = json.optJSONArray("Answer") ?: return emptyList()
                val addresses = mutableListOf<InetAddress>()
                for (i in 0 until answers.length()) {
                    val answer = answers.getJSONObject(i)
                    // Only A records (type 1): CNAME hostnames would bounce
                    // back to system DNS, and AAAA breaks IPv4-only networks.
                    if (answer.optInt("type", -1) != 1) continue
                    val data = answer.optString("data")
                    if (data.isNotEmpty() && IPV4_REGEX.matches(data)) {
                        runCatching {
                            addresses.add(InetAddress.getByName(data))
                        }
                    }
                }
                addresses
            } catch (t: Throwable) {
                Log.w(TAG, "DoH lookup failed for $hostname: ${t.message}")
                emptyList()
            }
        }

        fun put(hostname: String, addresses: List<InetAddress>) {
            cache[hostname] = addresses to System.currentTimeMillis()
        }

        fun getCached(hostname: String): List<InetAddress>? {
            val now = System.currentTimeMillis()
            val entry = cache[hostname] ?: return null
            return if (now - entry.second < ttlMs) entry.first else null
        }

        fun clear() {
            cache.clear()
        }
    }

    private val connectionPool = ConnectionPool(8, 5, TimeUnit.MINUTES)
    private val preConnectExecutor = Executors.newFixedThreadPool(2) { r ->
        Thread(r).apply {
            isDaemon = true
            name = "YtmPreConnect"
        }
    }

    val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectionPool(connectionPool)
            .dns(TtlDnsCache.instance)
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .proxySelector(object : ProxySelector() {
                override fun select(uri: URI?): List<Proxy> {
                    val urlStr = uri?.toString()
                    val customProxy = ProxyManager.getProxy(urlStr)
                    return if (customProxy != null) listOf(customProxy) else listOf(Proxy.NO_PROXY)
                }

                override fun connectFailed(uri: URI?, sa: SocketAddress?, ioe: IOException?) {
                    ProxyManager.onPathFailed(uri?.toString())
                }
            })
            .build()
    }

    /**
     * Asynchronously pre-connects and warms the TLS socket to [url] in the shared connection pool.
     */
    fun preConnect(url: String) {
        preConnectExecutor.execute {
            try {
                val httpUrl = url.toHttpUrlOrNull() ?: return@execute
                val host = httpUrl.host
                if (!host.contains("googlevideo.com") && !host.contains("youtube.com")) return@execute

                Log.d(TAG, "Pre-connecting TLS socket to $host...")
                // Perform lightweight HEAD request or DNS/Socket warm-up
                val req = Request.Builder()
                    .url(url)
                    .head()
                    .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0")
                    .build()

                okHttpClient.newCall(req).execute().use { response ->
                    Log.d(TAG, "Pre-connect to $host finished with code ${response.code} (socket placed in pool)")
                }
            } catch (t: Throwable) {
                // Non-fatal preconnect failure
                Log.d(TAG, "Pre-connect failed non-fatally: ${t.message}")
            }
        }
    }
}
