package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetAddress
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

/**
 * Layer 4: Native DNS-over-HTTPS (DoH) resolver.
 *
 * Fallback resolver using Cloudflare (1.1.1.1) and Google (8.8.8.8) DoH APIs
 * when system DNS returns NXDOMAIN or poisoned records. Strictly generic.
 */
object DnsOverHttpsResolver {
    private const val CACHE_TTL_MS = 5 * 60 * 1000L
    private const val NEGATIVE_TTL_MS = 30_000L
    private const val MAX_CACHE_SIZE = 256
    private const val HARD_DEADLINE_MS = 3000L
    private const val QUERY_TIMEOUT_MS = 1500

    private data class CacheEntry(val addresses: List<InetAddress>, val expiresAt: Long)

    private val cacheLock = Any()
    private val dnsCache = object : LinkedHashMap<String, CacheEntry>(MAX_CACHE_SIZE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CacheEntry>?): Boolean {
            return size > MAX_CACHE_SIZE
        }
    }

    private val executor = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "PulsrDoH").apply { isDaemon = true }
    }

    @Volatile
    private var appContext: Context? = null

    /** Called once at engine attach; only used for IPv4/IPv6 ordering. */
    fun initialize(context: Context) {
        appContext = context.applicationContext
    }

    private fun now(): Long = System.currentTimeMillis()

    private fun isNumericIp(ip: String): Boolean {
        val parts = ip.split('.')
        if (parts.size == 4) {
            return parts.all { part ->
                part.toIntOrNull()?.let { it in 0..255 } == true && (part == "0" || !part.startsWith("0"))
            }
        }
        if (ip.contains(':') && ip.count { it == ':' } >= 2) {
            // Require at least one hex digit (rejects ":::"/"::") and at most one
            // "::" compression run, so malformed strings are never mistaken for
            // literals and handed to the socket layer.
            val hasHexDigit = ip.any { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' }
            if (!hasHexDigit || ip.split("::").size > 2) return false
            val hexParts = ip.split(':')
            return hexParts.all { it.isEmpty() || (it.length <= 4 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' }) }
        }
        return false
    }

    private fun cached(hostname: String): CacheEntry? {
        val at = now()
        return synchronized(cacheLock) {
            val entry = dnsCache[hostname]
            if (entry != null && at < entry.expiresAt) {
                entry
            } else {
                if (entry != null) dnsCache.remove(hostname)
                null
            }
        }
    }

    private fun putInCache(hostname: String, addresses: List<InetAddress>, ttlMillis: Long) {
        val ttl = ttlMillis.coerceIn(NEGATIVE_TTL_MS, CACHE_TTL_MS)
        synchronized(cacheLock) {
            dnsCache[hostname] = CacheEntry(addresses, now() + ttl)
        }
    }

    fun resolve(hostname: String): InetAddress? = resolveAll(hostname).firstOrNull()

    /**
     * Resolves every address for [hostname] (A + AAAA in parallel). Positive
     * and negative answers are cached; the whole lookup is bounded by a ~3 s
     * deadline so a dead DoH endpoint cannot stall playback.
     */
    fun resolveAll(hostname: String): List<InetAddress> {
        // A literal address needs no resolver round-trip (and a DoH query for
        // "1.2.3.4" cannot answer anyway).
        if (isNumericIp(hostname)) {
            return runCatching { listOf(InetAddress.getByName(hostname)) }.getOrDefault(emptyList())
        }
        cached(hostname)?.let { return orderAddresses(it.addresses) }

        val deadline = now() + HARD_DEADLINE_MS
        val answers = java.util.concurrent.ConcurrentLinkedQueue<Pair<InetAddress, Long>>()
        val minTtl = AtomicLong(Long.MAX_VALUE)

        fun collect(results: List<Pair<InetAddress, Long>>) {
            for (answer in results) {
                answers.add(answer)
                minTtl.accumulateAndGet(answer.second) { a, b -> minOf(a, b) }
            }
        }

        fun startProvider(baseUrl: String, latch: CountDownLatch) {
            for (recordType in listOf("A", "AAAA")) {
                executor.execute {
                    try {
                        val remaining = deadline - now()
                        if (remaining > 0) {
                            val timeout = minOf(QUERY_TIMEOUT_MS.toLong(), remaining).toInt()
                            collect(queryDoH(baseUrl, hostname, recordType, timeout))
                        }
                    } catch (_: Exception) {
                    } finally {
                        latch.countDown()
                    }
                }
            }
        }

        // Happy Eyeballs for DoH: Cloudflare starts immediately. If it has not
        // produced a usable answer within 250 ms (or settles without one),
        // Google races in parallel instead of waiting for the full timeout.
        val cfLatch = CountDownLatch(2)
        startProvider("https://1.1.1.1/dns-query", cfLatch)
        try {
            cfLatch.await(250L, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        var googleLatch: CountDownLatch? = null
        // Cloudflare settling without an answer (NXDOMAIN or both queries
        // empty) must still race Google; only a usable answer skips the fallback.
        if (answers.isEmpty() && now() < deadline) {
            val latch = CountDownLatch(2)
            googleLatch = latch
            startProvider("https://dns.google/resolve", latch)
        }

        // Return as soon as either provider has finished with a usable answer
        // instead of blocking on the slower provider's full timeout. Latches
        // cannot wait on "either", so poll in short slices and re-check both.
        try {
            while (true) {
                val cfDone = cfLatch.count == 0L
                val google = googleLatch
                val googleDone = google == null || google.count == 0L
                if (cfDone && googleDone) break
                if (answers.isNotEmpty() && (cfDone || google?.count == 0L)) break
                val remaining = deadline - now()
                if (remaining <= 0L) break
                val waiter = if (!cfDone) cfLatch else google ?: break
                waiter.await(minOf(remaining, 25L), TimeUnit.MILLISECONDS)
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }

        val addresses = answers.map { it.first }
            .distinctBy { it.hostAddress }
        if (addresses.isEmpty()) {
            putInCache(hostname, emptyList(), NEGATIVE_TTL_MS)
            return emptyList()
        }

        val ttl = if (minTtl.get() == Long.MAX_VALUE) NEGATIVE_TTL_MS
        else (minTtl.get() * 1000L).coerceIn(NEGATIVE_TTL_MS, CACHE_TTL_MS)
        putInCache(hostname, addresses, ttl)
        return orderAddresses(addresses)
    }

    private fun queryDoH(
        baseUrl: String,
        hostname: String,
        recordType: String,
        timeoutMs: Int,
    ): List<Pair<InetAddress, Long>> {
        if (timeoutMs <= 0) return emptyList()
        var conn: HttpURLConnection? = null
        return try {
            val encodedName = URLEncoder.encode(hostname, "UTF-8")
            val url = URL("$baseUrl?name=$encodedName&type=$recordType")
            // Bypass proxy: DoH must reach the resolver even when a custom
            // proxy is dead, otherwise a bad proxy loops into DoH failure.
            conn = url.openConnection(java.net.Proxy.NO_PROXY) as HttpURLConnection
            conn.setRequestProperty("Accept", "application/dns-json")
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.requestMethod = "GET"

            val out = mutableListOf<Pair<InetAddress, Long>>()
            if (conn.responseCode == 200) {
                val json = conn.inputStream.bufferedReader().use { it.readText() }
                val root = JSONObject(json)
                if (root.optInt("Status", -1) == 0) {
                    val answers = root.optJSONArray("Answer") ?: return emptyList()
                    for (i in 0 until answers.length()) {
                        val ans = answers.getJSONObject(i)
                        val type = ans.optInt("type")
                        val ttl = ans.optLong("TTL", 0L)
                        if (ttl <= 0L) continue
                        if (type == 1 || type == 28) {
                            val ip = ans.optString("data")
                            if (ip.isNotEmpty() && isNumericIp(ip)) {
                                out.add(InetAddress.getByName(ip) to ttl)
                            }
                        }
                    }
                }
            }
            out
        } catch (_: Exception) {
            emptyList()
        } finally {
            conn?.disconnect()
        }
    }

    /**
     * IPv4 first on a dual-stack network; IPv6 first only when the active
     * network has no IPv4 address at all.
     */
    private fun orderAddresses(addresses: List<InetAddress>): List<InetAddress> {
        if (addresses.size < 2) return addresses
        val v4 = addresses.filter { it is Inet4Address }
        val v6 = addresses.filter { it !is Inet4Address }
        if (v4.isEmpty() || v6.isEmpty()) return addresses
        return if (activeNetworkHasIpv4()) v4 + v6 else v6 + v4
    }

    private fun activeNetworkHasIpv4(): Boolean {
        val ctx = appContext ?: return true
        return runCatching {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return@runCatching true
            val network = cm.activeNetwork ?: return@runCatching true
            val link = cm.getLinkProperties(network) ?: return@runCatching true
            link.linkAddresses.any { it.address is Inet4Address }
        }.getOrDefault(true)
    }
}
