package com.pulsr.music

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.Proxy

class YtmResilienceTest {

    @Test
    fun testAll8BlockSignals() {
        // 1. RateLimited
        val sig1 = YtmBlockSignal.parse(429, "Too Many Requests")
        assertEquals(YtmBlockSignal.RateLimited, sig1)

        // 2. IpBlocked
        val sig2 = YtmBlockSignal.parse(403, "Access Denied / Forbidden")
        assertEquals(YtmBlockSignal.IpBlocked, sig2)

        // 3. BotChallenge
        val playabilityBot = JSONObject().apply {
            put("status", "LOGIN_REQUIRED")
            put("reason", "Sign in to confirm you're not a bot")
        }
        val sig3 = YtmBlockSignal.parse(200, "bot", playabilityBot)
        assertEquals(YtmBlockSignal.BotChallenge, sig3)

        // 4. PoTokenInvalid
        val sig4 = YtmBlockSignal.parse(200, "empty_adaptive_formats po_token_invalid")
        assertEquals(YtmBlockSignal.PoTokenInvalid, sig4)

        // 5. ClientDeprecated
        val sig5 = YtmBlockSignal.parse(400, "API key not valid or client version is no longer supported")
        assertEquals(YtmBlockSignal.ClientDeprecated, sig5)

        // 6. GeoBlocked
        val playabilityGeo = JSONObject().apply {
            put("status", "UNPLAYABLE")
            put("reason", "The uploader has not made this video available in your country")
        }
        val sig6 = YtmBlockSignal.parse(200, "unplayable", playabilityGeo)
        assertEquals(YtmBlockSignal.GeoBlocked, sig6)

        // 7. SignInRequired
        val playabilityAuth = JSONObject().apply {
            put("status", "LOGIN_REQUIRED")
            put("reason", "Private content. Sign in to access your playlist.")
        }
        val sig7 = YtmBlockSignal.parse(200, "login", playabilityAuth)
        assertEquals(YtmBlockSignal.SignInRequired, sig7)

        // 8. VideoGone
        val playabilityGone = JSONObject().apply {
            put("status", "ERROR")
            put("reason", "Video removed by user")
        }
        val sig8 = YtmBlockSignal.parse(200, "error", playabilityGone)
        assertEquals(YtmBlockSignal.VideoGone, sig8)
    }

    @Test
    fun testProxyPoolCircuitBreakerAndRotation() {
        val node1 = ProxyPool.ProxyNode("1", Proxy.Type.HTTP, "1.1.1.1", 8080)
        val node2 = ProxyPool.ProxyNode("2", Proxy.Type.HTTP, "2.2.2.2", 8080)
        ProxyPool.setProxies(listOf(node1, node2))
        ProxyPool.setAutoRotate(false)

        val p1 = ProxyPool.getActiveProxy()
        assertNotNull(p1)

        // Fail node 1 three times -> trip circuit breaker
        ProxyPool.onPathFailed()
        ProxyPool.onPathFailed()
        ProxyPool.onPathFailed()

        assertFalse(node1.isAlive)
        assertTrue(node2.isAlive)

        // Now active proxy should be node 2
        ProxyPool.setAutoRotate(true)
        val p2 = ProxyPool.getActiveProxy()
        assertNotNull(p2)
        assertEquals(Proxy.Type.HTTP, p2?.type())
    }

    @Test
    fun testRateLimiterDeterministicClock() {
        var mockTime = 1000L
        val fakeClock = object : RateLimiter.Clock {
            override fun elapsedRealtime(): Long = mockTime
            override fun currentTimeMillis(): Long = mockTime
            override fun sleep(millis: Long) {
                mockTime += millis
            }
        }

        val limiter = RateLimiter(clock = fakeClock, respectfulMode = false)

        // Drain burst permits
        for (i in 0 until 10) {
            limiter.acquirePermit(RateLimiter.Bucket.PLAYER)
            limiter.releasePermit()
        }

        // Trigger rate limit with explicit retry-after of 10s
        val delay = limiter.onRateLimited(10L)
        assertEquals(10000L, delay)
        assertEquals(10000L, limiter.getRemainingBackoffMs())

        // Fast-forward mock clock by 10s
        mockTime += 10000L
        assertEquals(0L, limiter.getRemainingBackoffMs())
    }

    @Test
    fun testClientCapabilityMatrixDefaults() {
        val iosCap = ClientCapabilityMatrix.getCapability(InnertubeClient.ClientType.IOS_MUSIC)
        assertFalse(iosCap.requiresPoToken)
        assertTrue(iosCap.supportsStreamResolve)

        val webCap = ClientCapabilityMatrix.getCapability(InnertubeClient.ClientType.WEB_REMIX)
        assertTrue(webCap.requiresPoToken)
        assertTrue(webCap.requiresJsSignature)
    }

    @Test
    fun testParseIntegrityTokenDataDirectAndFallback() {
        // Direct format: token at index 0
        val directPayload = "[\"dGVzdFRva2Vu\", 3600]"
        val (u8Direct, ttlDirect) = parseIntegrityTokenData(directPayload)
        assertEquals(3600L, ttlDirect)
        assertTrue(u8Direct.startsWith("new Uint8Array(["))

        // YouTube WAA / GenerateIT format: websafe fallback at index 3, index 0 is null
        val fallbackPayload = "[null, 43200, null, \"TWstdW9UV3BoOVRGcEtwNlFodg==\"]"
        val (u8Fallback, ttlFallback) = parseIntegrityTokenData(fallbackPayload)
        assertEquals(43200L, ttlFallback)
        assertTrue(u8Fallback.startsWith("new Uint8Array(["))

        // Missing TTL defaults to 12 hours (43200s)
        val defaultTtlPayload = "[null, null, null, \"dGVzdA==\"]"
        val (u8Default, ttlDefault) = parseIntegrityTokenData(defaultTtlPayload)
        assertEquals(43200L, ttlDefault)
        assertTrue(u8Default.startsWith("new Uint8Array(["))
    }
}

