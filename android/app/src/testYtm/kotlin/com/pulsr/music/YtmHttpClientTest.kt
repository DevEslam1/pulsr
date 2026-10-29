package com.pulsr.music

import okhttp3.Dns
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class YtmHttpClientTest {

    @Test
    fun testTtlDnsCacheHitAvoidsDnsResolution() {
        val dnsCache = YtmHttpClient.TtlDnsCache(ttlMs = 60_000L)
        val testHost = "test.googlevideo.com"
        val mockAddresses = listOf(InetAddress.getByName("142.250.190.46"))

        dnsCache.put(testHost, mockAddresses)

        val cached = dnsCache.getCached(testHost)
        assertNotNull(cached)
        assertEquals(mockAddresses, cached)

        // Lookup retrieves directly from cache
        val resolved = dnsCache.lookup(testHost)
        assertEquals(mockAddresses, resolved)
    }

    @Test
    fun testTtlDnsCacheExpiry() {
        val dnsCache = YtmHttpClient.TtlDnsCache(ttlMs = 50L)
        val testHost = "expired.googlevideo.com"
        val mockAddresses = listOf(InetAddress.getByName("142.250.190.46"))

        dnsCache.put(testHost, mockAddresses)
        assertNotNull(dnsCache.getCached(testHost))

        Thread.sleep(60L)

        assertNull("Cache entry should expire after TTL", dnsCache.getCached(testHost))
    }

    @Test
    fun testProxyBypassZeroOverhead() {
        ProxyManager.setProxy(
            enabled = false,
            type = "http",
            host = "1.2.3.4",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = null
        )

        val proxy = ProxyManager.getProxy("https://music.youtube.com/youtubei/v1/player")
        assertNull("When proxy is disabled, getProxy must return null immediately", proxy)
        assertFalse(ProxyManager.enabled)
    }

    @Test
    fun testSharedOkHttpClientConfig() {
        val client = YtmHttpClient.okHttpClient
        assertNotNull(client)
        assertNotNull(client.connectionPool)
        assertTrue(client.followRedirects)
        assertTrue(client.followSslRedirects)
        assertEquals(YtmHttpClient.TtlDnsCache.instance, client.dns)
    }
}
