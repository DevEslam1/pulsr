package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetAddress
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
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
    private const val HAPPY_EYEBALLS_DELAY_MS = 250L
    private const val SECOND_FAMILY_LINGER_MS = 120L
    private const val QUERY_TIMEOUT_MS = 1500
    private val IPV4_LITERAL_REGEX =
        Regex("""^(?:0|[1-9]\d{0,2})(?:\.(?:0|[1-9]\d{0,2})){3}$""")
    private val IPV6_HEX_CHAR_REGEX = Regex("""^[0-9a-fA-F:]+$""")
    private val IPV6_GROUP_REGEX = Regex("""^[0-9a-fA-F]{1,4}$""")

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

    internal fun isNumericIp(ip: String): Boolean {
        val candidate = ip.trim()
        if (candidate.isEmpty()) return false
        if (isStrictIpv4Literal(candidate)) return true
        return isStrictIpv6Literal(candidate)
    }

    private fun isStrictIpv4Literal(ip: String): Boolean {
        if (!IPV4_LITERAL_REGEX.matches(ip)) return false
        val parts = ip.split('.')
        return parts.size == 4 && parts.all { part -> part.toIntOrNull() in 0..255 }
    }

    private fun isStrictIpv6Literal(ip: String): Boolean {
        if (!ip.contains(':')) return false
        val normalizedHex = if (ip.contains('.')) {
            val lastColon = ip.lastIndexOf(':')
            if (lastColon < 0) return false
            val v4Tail = ip.substring(lastColon + 1)
            if (!isStrictIpv4Literal(v4Tail)) return false
            // Replace the validated 32-bit IPv4 tail with two 16-bit groups so
            // total group counting enforces <= 8 groups uniformly.
            ip.substring(0, lastColon + 1) + "0:0"
        } else {
            ip
        }

        if (!IPV6_HEX_CHAR_REGEX.matches(normalizedHex)) return false
        if (normalizedHex.contains(":::")) return false
        if (normalizedHex.startsWith(':') && !normalizedHex.startsWith("::")) return false
        if (normalizedHex.endsWith(':') && !normalizedHex.endsWith("::")) return false

        val halves = normalizedHex.split("::")
        if (halves.size > 2) return false
        val hasCompression = halves.size == 2
        val leftGroups = if (halves[0].isEmpty()) emptyList() else halves[0].split(':')
        if (!leftGroups.all { IPV6_GROUP_REGEX.matches(it) }) return false

        if (!hasCompression) {
            return leftGroups.size == 8
        }

        val rightGroups = if (halves[1].isEmpty()) emptyList() else halves[1].split(':')
        if (!rightGroups.all { IPV6_GROUP_REGEX.matches(it) }) return false
        val totalGroups = leftGroups.size + rightGroups.size
        // "::" must elide at least one group, and "::" alone (0 explicit groups)
        // is rejected alongside > 7 explicit groups around compression.
        return totalGroups in 1..7
    }

    private fun cached(hostname: String): CacheEntry? {
        val key = hostname.trim().lowercase(Locale.ROOT)
        val at = now()
        return synchronized(cacheLock) {
            val entry = dnsCache[key]
            if (entry != null && at < entry.expiresAt) {
                entry
            } else {
                if (entry != null) dnsCache.remove(key)
                null
            }
        }
    }

    private fun putInCache(hostname: String, addresses: List<InetAddress>, ttlMillis: Long) {
        val key = hostname.trim().lowercase(Locale.ROOT)
        val ttl = ttlMillis.coerceIn(NEGATIVE_TTL_MS, CACHE_TTL_MS)
        synchronized(cacheLock) {
            dnsCache[key] = CacheEntry(addresses, now() + ttl)
        }
    }

    fun resolve(hostname: String): InetAddress? = resolveAll(hostname).firstOrNull()

    /**
     * Resolves every address for [hostname] (A + AAAA in parallel). Positive
     * and negative answers are cached; the whole lookup is bounded by a ~3 s
     * deadline so a dead DoH endpoint cannot stall playback.
     */
    fun resolveAll(hostname: String): List<InetAddress> {
        val normalizedHost = hostname.trim().lowercase(Locale.ROOT)
        if (normalizedHost.isEmpty()) return emptyList()

        // A literal address needs no resolver round-trip (and a DoH query for
        // "1.2.3.4" cannot answer anyway). Only invoke InetAddress.getByName on
        // strings that strictly match our numeric IP regex/group parser so we
        // can never trigger a synchronous system DNS lookup.
        if (isNumericIp(normalizedHost)) {
            return runCatching { listOf(InetAddress.getByName(normalizedHost)) }.getOrDefault(emptyList())
        }
        cached(normalizedHost)?.let { return orderAddresses(it.addresses) }

        val deadline = now() + HARD_DEADLINE_MS
        val answers = ConcurrentLinkedQueue<Pair<InetAddress, Long>>()
        val minTtl = AtomicLong(Long.MAX_VALUE)
        val firstAnswerAt = AtomicLong(0L)
        val inFlight = AtomicInteger(0)
        val waitLock = Object()

        fun collect(results: List<Pair<InetAddress, Long>>) {
            if (results.isEmpty()) return
            synchronized(waitLock) {
                for (answer in results) {
                    answers.add(answer)
                    minTtl.accumulateAndGet(answer.second) { a, b -> minOf(a, b) }
                }
                firstAnswerAt.compareAndSet(0L, now())
                waitLock.notifyAll()
            }
        }

        fun startProvider(baseUrl: String) {
            for (recordType in listOf("A", "AAAA")) {
                inFlight.incrementAndGet()
                try {
                    executor.execute {
                        try {
                            val remaining = deadline - now()
                            if (remaining > 0) {
                                val timeout = minOf(QUERY_TIMEOUT_MS.toLong(), remaining).toInt()
                                collect(queryDoH(baseUrl, normalizedHost, recordType, timeout))
                            }
                        } catch (_: Exception) {
                        } finally {
                            synchronized(waitLock) {
                                inFlight.decrementAndGet()
                                waitLock.notifyAll()
                            }
                        }
                    }
                } catch (_: Throwable) {
                    synchronized(waitLock) {
                        inFlight.decrementAndGet()
                        waitLock.notifyAll()
                    }
                }
            }
        }

        // Happy Eyeballs for DoH: Cloudflare starts immediately. If it has not
        // produced a usable answer within 250 ms (or settles without one),
        // Google races in parallel instead of waiting for the full timeout.
        startProvider("https://1.1.1.1/dns-query")
        val fallbackAt = minOf(deadline, now() + HAPPY_EYEBALLS_DELAY_MS)
        synchronized(waitLock) {
            try {
                while (inFlight.get() > 0 && answers.isEmpty()) {
                    val remaining = fallbackAt - now()
                    if (remaining <= 0L) break
                    waitLock.wait(remaining)
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }

        // Cloudflare settling without an answer (NXDOMAIN or both queries
        // empty) must still race Google; only a usable answer skips the fallback.
        if (answers.isEmpty() && now() < deadline) {
            startProvider("https://dns.google/resolve")
        }

        // Once at least one answer arrives, linger at most 120 ms for the second
        // address family (A/AAAA) to land so an unresponsive family cannot pin the
        // lookup to the full timeout.
        synchronized(waitLock) {
            try {
                while (inFlight.get() > 0) {
                    val nowMs = now()
                    if (nowMs >= deadline) break
                    val answeredAt = firstAnswerAt.get()
                    val waitMs = if (answeredAt > 0L) {
                        val lingerDeadline = minOf(deadline, answeredAt + SECOND_FAMILY_LINGER_MS)
                        if (nowMs >= lingerDeadline) break
                        lingerDeadline - nowMs
                    } else {
                        deadline - nowMs
                    }
                    waitLock.wait(waitMs)
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }

        val addresses = answers.map { it.first }
            .distinctBy { it.hostAddress }
        if (addresses.isEmpty()) {
            putInCache(normalizedHost, emptyList(), NEGATIVE_TTL_MS)
            return emptyList()
        }

        val ttl = if (minTtl.get() == Long.MAX_VALUE) NEGATIVE_TTL_MS
        else (minTtl.get() * 1000L).coerceIn(NEGATIVE_TTL_MS, CACHE_TTL_MS)
        putInCache(normalizedHost, addresses, ttl)
        return orderAddresses(addresses)
    }

    private fun queryDoH(
        baseUrl: String,
        hostname: String,
        recordType: String,
        timeoutMs: Int,
    ): List<Pair<InetAddress, Long>> {
        if (timeoutMs <= 0) return emptyList()
        val normalizedHost = hostname.trim().lowercase(Locale.ROOT)
        var conn: HttpURLConnection? = null
        return try {
            val encodedName = URLEncoder.encode(normalizedHost, "UTF-8")
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
