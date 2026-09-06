package com.pulsr.music

import android.util.Log
import okhttp3.ConnectionPool
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
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
        private val DOH_ENDPOINTS = listOf(
            "https://8.8.8.8/resolve",
            "https://1.1.1.1/dns-query",
            "https://dns.google/resolve"
        )
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
         * Resolves hostname via public DNS over HTTPS.
         *
         * The endpoints are IP literals on purpose: `https://dns.google/...`
         * would itself need a system DNS lookup, which is the exact thing that
         * just failed. Both providers list their resolver IPs as SANs on the
         * serving certificate, so TLS verification still succeeds.
         */
        private fun resolveDoH(hostname: String): List<InetAddress> {
            for (endpoint in DOH_ENDPOINTS) {
                val result = queryDoH(endpoint, hostname)
                if (result.isNotEmpty()) return result
            }
            return emptyList()
        }

        private fun queryDoH(endpoint: String, hostname: String): List<InetAddress> {
            return try {
                val dohUrl = "$endpoint?name=$hostname&type=A"
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
                Log.w(TAG, "DoH lookup failed for $hostname via $endpoint: ${t.message}")
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
     * Asynchronously warms DNS for [url]'s host.
     *
     * This used to fire a real HEAD request to the googlevideo URL. That never
     * paid off: playback goes through ExoPlayer's own HTTP stack and connection
     * pool, so the warmed socket was never reused — it just spent an extra
     * request against YouTube (with a User-Agent that did not even match the
     * client the URL was minted for). Populating the resolver cache is the part
     * that actually carries over.
     */
    fun preConnect(url: String) {
        preConnectExecutor.execute {
            try {
                val httpUrl = url.toHttpUrlOrNull() ?: return@execute
                val host = httpUrl.host
                if (!host.contains("googlevideo.com") && !host.contains("youtube.com")) return@execute
                if (TtlDnsCache.instance.getCached(host) != null) return@execute

                TtlDnsCache.instance.lookup(host)
                Log.d(TAG, "Pre-resolved DNS for $host")
            } catch (t: Throwable) {
                Log.d(TAG, "DNS pre-warm failed non-fatally: ${t.message}")
            }
        }
    }
}
