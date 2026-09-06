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
        return ip.matches(Regex("^(\\d{1,3}\\.){3}\\d{1,3}$")) || ip.contains(":")
    }

    private fun putInCache(hostname: String, address: InetAddress, now: Long) {
        if (dnsCache.size >= MAX_CACHE_SIZE) {
            val expired = dnsCache.entries.filter { (now - it.value.second) >= CACHE_TTL_MS }
            for (entry in expired) {
                dnsCache.remove(entry.key)
            }
            if (dnsCache.size >= MAX_CACHE_SIZE) {
                dnsCache.clear()
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

        // Try Cloudflare DoH first
        val cfResolved = resolveViaCloudflare(hostname)
        if (cfResolved != null) {
            putInCache(hostname, cfResolved, now)
            return cfResolved
        }

        // Fallback to Google DoH
        val googleResolved = resolveViaGoogle(hostname)
        if (googleResolved != null) {
            putInCache(hostname, googleResolved, now)
            return googleResolved
        }

        return null
    }

    private fun resolveViaCloudflare(hostname: String): InetAddress? {
        return runCatching {
            val url = URL("https://1.1.1.1/dns-query?name=$hostname&type=A")
            val conn = url.openConnection() as HttpURLConnection
            conn.setRequestProperty("Accept", "application/dns-json")
            conn.connectTimeout = 4000
            conn.readTimeout = 4000
            conn.requestMethod = "GET"

            if (conn.responseCode == 200) {
                val json = conn.inputStream.bufferedReader().use { it.readText() }
                val root = JSONObject(json)
                val answers = root.optJSONArray("Answer")
                if (answers != null && answers.length() > 0) {
                    for (i in 0 until answers.length()) {
                        val ans = answers.getJSONObject(i)
                        val type = ans.optInt("type")
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
        }.getOrNull()
    }

    private fun resolveViaGoogle(hostname: String): InetAddress? {
        return runCatching {
            val url = URL("https://dns.google/resolve?name=$hostname&type=A")
            val conn = url.openConnection() as HttpURLConnection
            conn.setRequestProperty("Accept", "application/dns-json")
            conn.connectTimeout = 4000
            conn.readTimeout = 4000
            conn.requestMethod = "GET"

            if (conn.responseCode == 200) {
                val json = conn.inputStream.bufferedReader().use { it.readText() }
                val root = JSONObject(json)
                val answers = root.optJSONArray("Answer")
                if (answers != null && answers.length() > 0) {
                    for (i in 0 until answers.length()) {
                        val ans = answers.getJSONObject(i)
                        val type = ans.optInt("type")
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
        }.getOrNull()
    }
}
