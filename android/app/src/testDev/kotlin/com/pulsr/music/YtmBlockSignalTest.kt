package com.pulsr.music

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YtmBlockSignalTest {

    @Test
    fun testInterruptedSignal() {
        assertEquals(
            YtmBlockSignal.Interrupted,
            YtmBlockSignal.parse(0, "java.io.InterruptedIOException: thread interrupted")
        )
        assertEquals(
            YtmBlockSignal.Interrupted,
            YtmBlockSignal.parse(0, "Coroutine interrupted during playback wait")
        )
    }

    @Test
    fun testNetworkUnavailableSignal() {
        assertEquals(
            YtmBlockSignal.NetworkUnavailable,
            YtmBlockSignal.parse(0, "java.net.UnknownHostException: Unable to resolve host music.youtube.com")
        )
        assertEquals(
            YtmBlockSignal.NetworkUnavailable,
            YtmBlockSignal.parse(0, "java.net.ConnectException: Failed to connect to /142.250.180.14:443")
        )
        assertEquals(
            YtmBlockSignal.NetworkUnavailable,
            YtmBlockSignal.parse(0, "java.net.SocketTimeoutException: network is unreachable")
        )
        assertEquals(
            YtmBlockSignal.NetworkUnavailable,
            YtmBlockSignal.parse(0, "No route to host")
        )
        assertEquals(
            YtmBlockSignal.NetworkUnavailable,
            YtmBlockSignal.parse(0, "network unavailable")
        )
    }

    @Test
    fun testSignatureDecipherFailedSignal() {
        assertEquals(
            YtmBlockSignal.SignatureDecipherFailed,
            YtmBlockSignal.parse(200, "signature decipher failed for format itag 140")
        )
        assertEquals(
            YtmBlockSignal.SignatureDecipherFailed,
            YtmBlockSignal.parse(200, "Could not decipher n-sig parameter")
        )
    }

    @Test
    fun testBotChallengeSignal() {
        assertEquals(
            YtmBlockSignal.BotChallenge,
            YtmBlockSignal.parse(403, "Please solve this recaptcha to prove you are not a bot")
        )
        assertEquals(
            YtmBlockSignal.BotChallenge,
            YtmBlockSignal.parse(403, "Our systems have detected unusual traffic from your computer network")
        )
        val botJson = JSONObject().apply { put("status", "LOGIN_REQUIRED_BOT_CHECK") }
        assertEquals(
            YtmBlockSignal.BotChallenge,
            YtmBlockSignal.parse(200, "botguard verification required", botJson)
        )
    }

    @Test
    fun testSabrEnforcedSignal() {
        assertEquals(
            YtmBlockSignal.SabrEnforced,
            YtmBlockSignal.parse(200, "YouTube Music is forcing SABR streaming for this asset")
        )
        assertEquals(
            YtmBlockSignal.SabrEnforced,
            YtmBlockSignal.parse(200, "Asset is missing a url because server-based adaptive bitrate is enforced")
        )

        // Structural SABR detection
        assertTrue(YtmBlockSignal.detectSabrStructural(hasStreamingData = true, formatCount = 3, urlCount = 0, cipherCount = 0))
        assertFalse(YtmBlockSignal.detectSabrStructural(hasStreamingData = true, formatCount = 3, urlCount = 1, cipherCount = 0))
        assertFalse(YtmBlockSignal.detectSabrStructural(hasStreamingData = true, formatCount = 3, urlCount = 0, cipherCount = 1))
        assertFalse(YtmBlockSignal.detectSabrStructural(hasStreamingData = false, formatCount = 3, urlCount = 0, cipherCount = 0))
    }

    @Test
    fun testRateLimitedSignal() {
        assertEquals(
            YtmBlockSignal.RateLimited,
            YtmBlockSignal.parse(429, "Too Many Requests")
        )
        assertEquals(
            YtmBlockSignal.RateLimited,
            YtmBlockSignal.parse(200, "User quota exceeded for Innertube endpoint")
        )
    }

    @Test
    fun testPoTokenInvalidSignal() {
        assertEquals(
            YtmBlockSignal.PoTokenInvalid,
            YtmBlockSignal.parse(403, "Invalid potoken for playback")
        )
        assertEquals(
            YtmBlockSignal.PoTokenInvalid,
            YtmBlockSignal.parse(403, "integrity token validation failed")
        )
        val okJson = JSONObject().apply { put("status", "OK") }
        assertEquals(
            YtmBlockSignal.PoTokenInvalid,
            YtmBlockSignal.parse(200, "empty_adaptive_formats returned", okJson)
        )
    }

    @Test
    fun testGeoBlockedSignal() {
        assertEquals(
            YtmBlockSignal.GeoBlocked,
            YtmBlockSignal.parse(200, "The uploader has not made this video available in your country")
        )
        val unplayableJson = JSONObject().apply { put("status", "UNPLAYABLE") }
        assertEquals(
            YtmBlockSignal.GeoBlocked,
            YtmBlockSignal.parse(200, "blocked in your country", unplayableJson)
        )
    }

    @Test
    fun testSignInRequiredSignal() {
        val signinJson = JSONObject().apply { put("status", "LOGIN_REQUIRED") }
        assertEquals(
            YtmBlockSignal.SignInRequired,
            YtmBlockSignal.parse(200, "Please sign in to access this member-only content", signinJson)
        )
        assertEquals(
            YtmBlockSignal.SignInRequired,
            YtmBlockSignal.parse(200, "authentication required for track")
        )
    }

    @Test
    fun testVideoGoneSignal() {
        assertEquals(
            YtmBlockSignal.VideoGone,
            YtmBlockSignal.parse(404, "Not Found")
        )
        assertEquals(
            YtmBlockSignal.VideoGone,
            YtmBlockSignal.parse(200, "This video has been removed by the user")
        )
        val unplayableJson = JSONObject().apply { put("status", "UNPLAYABLE") }
        assertEquals(
            YtmBlockSignal.VideoGone,
            YtmBlockSignal.parse(200, "Playback on other websites has been disabled by the video owner", unplayableJson)
        )
    }

    @Test
    fun testIpBlockedSignal() {
        assertEquals(
            YtmBlockSignal.IpBlocked,
            YtmBlockSignal.parse(403, "Access denied")
        )
        assertEquals(
            YtmBlockSignal.IpBlocked,
            YtmBlockSignal.parse(403, "Forbidden")
        )
        assertEquals(
            YtmBlockSignal.IpBlocked,
            YtmBlockSignal.parse(200, "Your IP blocked from making further requests")
        )
    }

    @Test
    fun testClientDeprecatedSignal() {
        assertEquals(
            YtmBlockSignal.ClientDeprecated,
            YtmBlockSignal.parse(400, "Client version is no longer supported")
        )
        val errJson = JSONObject().apply { put("code", 400) }
        assertEquals(
            YtmBlockSignal.ClientDeprecated,
            YtmBlockSignal.parse(200, "Bad request", null, errJson)
        )
        assertEquals(
            YtmBlockSignal.ClientDeprecated,
            YtmBlockSignal.parse(200, "Unsupported client, please upgrade to continue")
        )
    }

    @Test
    fun testFallbackCategorization() {
        assertEquals(YtmBlockSignal.RateLimited, YtmBlockSignal.parse(429, ""))
        assertEquals(YtmBlockSignal.IpBlocked, YtmBlockSignal.parse(403, ""))
        assertEquals(YtmBlockSignal.ClientDeprecated, YtmBlockSignal.parse(400, ""))
        assertEquals(YtmBlockSignal.VideoGone, YtmBlockSignal.parse(404, ""))

        val unplayableJson = JSONObject().apply { put("status", "UNPLAYABLE") }
        assertEquals(YtmBlockSignal.VideoGone, YtmBlockSignal.parse(200, "", unplayableJson))

        val errorJson = JSONObject().apply { put("status", "ERROR") }
        assertEquals(YtmBlockSignal.VideoGone, YtmBlockSignal.parse(200, "", errorJson))

        assertEquals(YtmBlockSignal.RateLimited, YtmBlockSignal.parse(500, ""))
    }
}
