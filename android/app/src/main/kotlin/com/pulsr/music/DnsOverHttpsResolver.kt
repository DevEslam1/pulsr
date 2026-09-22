package com.pulsr.music

import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * Layer 4: Native DNS-over-HTTPS (DoH) Resolver.
 *
 * Fallback resolver using Cloudflare (1.1.1.1) and Google (8.8.8.8) DoH APIs
 * when system DNS returns NXDOMAIN or poisoned records.
 * Strictly generic in src/main.
 */
object DnsOverHttpsResolver {
    private const val TAG = "DnsOverHttpsResolver"
    private val dnsCache = ConcurrentHashMap<String, Pair<InetAddress, Long>>()
    private const val CACHE_TTL_MS = 5 * 60 * 1000L // 5 minutes

    private const val MAX_CACHE_SIZE = 256

    private fun isNumericIp(ip: String): Boolean {
        val parts = ip.split('.')
        if (parts.size == 4) {
            return parts.all { part ->
                part.toIntOrNull()?.let { it in 0..255 } == true && (part == "0" || !part.startsWith("0"))
            }
        }
        if (ip.contains(':') && ip.count { it == ':' } >= 2) {
            val hexParts = ip.split(':')
            return hexParts.all { it.isEmpty() || (it.length <= 4 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' }) }
        }
        return false
    }

    private fun putInCache(hostname: String, address: InetAddress, now: Long) {
        if (dnsCache.size >= MAX_CACHE_SIZE) {
            val expired = dnsCache.entries.filter { (now - it.value.second) >= CACHE_TTL_MS }
            for (entry in expired) {
                dnsCache.remove(entry.key)
            }
            if (dnsCache.size >= MAX_CACHE_SIZE) {
                // Evict the oldest 25% of entries rather than clearing the entire cache
                val toEvict = dnsCache.entries
                    .sortedBy { it.value.second }
                    .take((MAX_CACHE_SIZE / 4).coerceAtLeast(1))
                for (entry in toEvict) {
                    dnsCache.remove(entry.key)
                }
            }
        }
        dnsCache[hostname] = address to now
    }

    fun resolve(hostname: String): InetAddress? {
        val now = System.currentTimeMillis()
        val cached = dnsCache[hostname]
        if (cached != null && (now - cached.second) < CACHE_TTL_MS) {
            return cached.first
        }

        // Try Cloudflare DoH first (A, then AAAA)
        val cfResolved = resolveViaCloudflare(hostname)
        if (cfResolved != null) {
            putInCache(hostname, cfResolved, now)
            return cfResolved
        }

        // Fallback to Google DoH (A, then AAAA)
        val googleResolved = resolveViaGoogle(hostname)
        if (googleResolved != null) {
            putInCache(hostname, googleResolved, now)
            return googleResolved
        }

        return null
    }

    private fun queryDoH(baseUrl: String, hostname: String, recordType: String): InetAddress? {
        return runCatching {
            val url = URL("$baseUrl?name=$hostname&type=$recordType")
            // Bypass proxy — DoH must reach the resolver even when a custom
            // proxy is dead, otherwise a bad proxy loops into DoH failure.
            val conn = url.openConnection(java.net.Proxy.NO_PROXY) as HttpURLConnection
            try {
                conn.setRequestProperty("Accept", "application/dns-json")
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                conn.requestMethod = "GET"

                if (conn.responseCode == 200) {
                    val json = conn.inputStream.bufferedReader().use { it.readText() }
                    val root = JSONObject(json)
                    val status = root.optInt("Status", -1)
                    if (status != 0) {
                        return@runCatching null
                    }
                    val answers = root.optJSONArray("Answer")
                    if (answers != null && answers.length() > 0) {
                        for (i in 0 until answers.length()) {
                            val ans = answers.getJSONObject(i)
                            val type = ans.optInt("type")
                            val ttl = ans.optInt("TTL", 0)
                            if (ttl <= 0) continue
                            // Type 1 = A, Type 28 = AAAA
                            if (type == 1 || type == 28) {
                                val ip = ans.optString("data")
                                if (ip.isNotEmpty() && isNumericIp(ip)) {
                                    return@runCatching InetAddress.getByName(ip)
                                }
                            }
                        }
                    }
                }
                null
            } finally {
                conn.disconnect()
            }
        }.getOrNull()
    }

    private fun resolveViaCloudflare(hostname: String): InetAddress? {
        return queryDoH("https://1.1.1.1/dns-query", hostname, "A")
            ?: queryDoH("https://1.1.1.1/dns-query", hostname, "AAAA")
    }

    private fun resolveViaGoogle(hostname: String): InetAddress? {
        return queryDoH("https://dns.google/resolve", hostname, "A")
            ?: queryDoH("https://dns.google/resolve", hostname, "AAAA")
    }
}
