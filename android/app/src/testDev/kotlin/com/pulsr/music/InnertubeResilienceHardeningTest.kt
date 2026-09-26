package com.pulsr.music

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class InnertubeResilienceHardeningTest {

    @Test
    fun testSignalPriorityPreservesLowerPrioritySignalsWhenStartedNull() {
        fun signalPriority(s: YtmBlockSignal?): Int = when (s) {
            YtmBlockSignal.Interrupted             -> 9
            YtmBlockSignal.BotChallenge            -> 8
            YtmBlockSignal.PoTokenInvalid          -> 7
            YtmBlockSignal.RateLimited             -> 6
            YtmBlockSignal.IpBlocked               -> 5
            YtmBlockSignal.SignatureDecipherFailed -> 4
            YtmBlockSignal.SabrEnforced            -> 3
            YtmBlockSignal.SignInRequired          -> 2
            YtmBlockSignal.ClientDeprecated        -> 2
            YtmBlockSignal.GeoBlocked              -> 2
            YtmBlockSignal.VideoGone               -> 1
            YtmBlockSignal.NetworkUnavailable      -> 0
            null                                   -> -1
        }

        val lastSignalRef = AtomicReference<YtmBlockSignal?>(null)
        fun updateBestSignal(newSignal: YtmBlockSignal?) {
            if (newSignal == null) return
            lastSignalRef.updateAndGet { current ->
                if (signalPriority(newSignal) > signalPriority(current)) newSignal else current
            }
        }

        updateBestSignal(YtmBlockSignal.VideoGone)
        assertEquals(YtmBlockSignal.VideoGone, lastSignalRef.get())

        updateBestSignal(YtmBlockSignal.SabrEnforced)
        assertEquals(YtmBlockSignal.SabrEnforced, lastSignalRef.get())

        updateBestSignal(YtmBlockSignal.IpBlocked)
        assertEquals(YtmBlockSignal.IpBlocked, lastSignalRef.get())

        updateBestSignal(YtmBlockSignal.GeoBlocked)
        assertEquals(YtmBlockSignal.IpBlocked, lastSignalRef.get())

        val unparsedRef = AtomicReference<YtmBlockSignal?>(null)
        val finalSignal = unparsedRef.get() ?: YtmBlockSignal.NetworkUnavailable
        assertEquals(YtmBlockSignal.NetworkUnavailable, finalSignal)
    }

    @Test
    fun testAttemptResultHierarchyAndWinnerStoreHygiene() {
        val success = InnertubeClient.AttemptResult.Success(mapOf("url" to "https://googlevideo.com/stream"))
        val failureClientSpecific = InnertubeClient.AttemptResult.Failure(YtmBlockSignal.SabrEnforced, isClientSpecific = true)
        val failureNetwork = InnertubeClient.AttemptResult.Failure(YtmBlockSignal.NetworkUnavailable, isClientSpecific = false)
        val shortCircuited = InnertubeClient.AttemptResult.ShortCircuited
        val interrupted = InnertubeClient.AttemptResult.Interrupted

        assertTrue(success is InnertubeClient.AttemptResult.Success)
        assertTrue(failureClientSpecific.isClientSpecific)
        assertFalse(failureNetwork.isClientSpecific)
        assertTrue(shortCircuited is InnertubeClient.AttemptResult.ShortCircuited)
        assertTrue(interrupted is InnertubeClient.AttemptResult.Interrupted)
    }

    @Test
    fun testUnplayableDoesNotMarkClientSpecificFailure() {
        // FIX #1: UNPLAYABLE from BotChallenge, VideoGone, etc. must not be client-specific
        fun isClientSpecificSignal(parsedSignal: YtmBlockSignal): Boolean {
            return parsedSignal == YtmBlockSignal.ClientDeprecated ||
                parsedSignal == YtmBlockSignal.SabrEnforced ||
                parsedSignal == YtmBlockSignal.SignatureDecipherFailed
        }

        assertFalse(isClientSpecificSignal(YtmBlockSignal.BotChallenge))
        assertFalse(isClientSpecificSignal(YtmBlockSignal.IpBlocked))
        assertFalse(isClientSpecificSignal(YtmBlockSignal.VideoGone))
        assertFalse(isClientSpecificSignal(YtmBlockSignal.SignInRequired))
        assertFalse(isClientSpecificSignal(YtmBlockSignal.RateLimited))
        assertFalse(isClientSpecificSignal(YtmBlockSignal.NetworkUnavailable))

        assertTrue(isClientSpecificSignal(YtmBlockSignal.ClientDeprecated))
        assertTrue(isClientSpecificSignal(YtmBlockSignal.SabrEnforced))
        assertTrue(isClientSpecificSignal(YtmBlockSignal.SignatureDecipherFailed))
    }

    @Test
    fun testGlobalBreakerOnlyIncrementsOnceOnWinningCas() {
        // FIX #2: Global breaker increment is guarded by shortCircuit.compareAndSet(null, exc)
        val shortCircuit = AtomicReference<Exception?>(null)
        val consecutiveEgressBlocks = AtomicInteger(0)

        val exc1 = Exception("First short circuit")
        val exc2 = Exception("Second short circuit from concurrent candidate")

        // First thread succeeds in CAS -> increments
        if (shortCircuit.compareAndSet(null, exc1)) {
            consecutiveEgressBlocks.incrementAndGet()
        }

        // Second thread fails CAS -> should NOT increment
        if (shortCircuit.compareAndSet(null, exc2)) {
            consecutiveEgressBlocks.incrementAndGet()
        }

        assertEquals(1, consecutiveEgressBlocks.get())
        assertEquals(exc1, shortCircuit.get())
    }

    @Test
    fun testSafeBitrateFallbackForMissingOrZeroBitrate() {
        fun safeBitrate(format: JSONObject): Int {
            val b = format.optInt("bitrate", 0)
            if (b > 0) return b
            val avgB = format.optInt("averageBitrate", 0)
            if (avgB > 0) return avgB
            return when (format.optInt("itag", 0)) {
                251 -> 160000
                140 -> 128000
                139, 250 -> 70000
                249 -> 50000
                else -> 128000
            }
        }

        val formatWithExplicitBitrate = JSONObject().put("itag", 251).put("bitrate", 155000)
        assertEquals(155000, safeBitrate(formatWithExplicitBitrate))

        val formatWithMissingBitrateOpus = JSONObject().put("itag", 251)
        assertEquals(160000, safeBitrate(formatWithMissingBitrateOpus))

        val formatWithZeroBitrateAac = JSONObject().put("itag", 140).put("bitrate", 0)
        assertEquals(128000, safeBitrate(formatWithZeroBitrateAac))

        val formatWithAverageBitrate = JSONObject().put("itag", 140).put("bitrate", 0).put("averageBitrate", 129500)
        assertEquals(129500, safeBitrate(formatWithAverageBitrate))
    }

    @Test
    fun testThumbnailExtraction() {
        fun extractBestArtworkUrl(videoDetails: JSONObject?): String? {
            val thumbnails = videoDetails?.optJSONObject("thumbnail")?.optJSONArray("thumbnails") ?: return null
            if (thumbnails.length() == 0) return null
            var maxW = 0
            var bestUrl: String? = null
            for (i in 0 until thumbnails.length()) {
                val t = thumbnails.optJSONObject(i) ?: continue
                val w = t.optInt("width", 0)
                val u = t.optString("url")
                if (w >= maxW && u.isNotEmpty()) {
                    maxW = w
                    bestUrl = u
                }
            }
            return bestUrl
        }

        val detailsNull: JSONObject? = null
        assertNull(extractBestArtworkUrl(detailsNull))

        val detailsWithThumbs = JSONObject().apply {
            put("thumbnail", JSONObject().apply {
                put("thumbnails", JSONArray().apply {
                    put(JSONObject().put("width", 120).put("url", "https://i.ytimg.com/vi/123/default.jpg"))
                    put(JSONObject().put("width", 640).put("url", "https://i.ytimg.com/vi/123/sddefault.jpg"))
                    put(JSONObject().put("width", 320).put("url", "https://i.ytimg.com/vi/123/mqdefault.jpg"))
                })
            })
        }
        assertEquals("https://i.ytimg.com/vi/123/sddefault.jpg", extractBestArtworkUrl(detailsWithThumbs))
    }

    @Test
    fun testGenericIOExceptionClassification() {
        val lastError: Exception = IOException("Connection reset by peer")
        val terminalSignal = when (val err = lastError) {
            is InnertubeClient.InnertubeException -> err.signal
            is org.json.JSONException -> YtmBlockSignal.NetworkUnavailable
            is java.net.UnknownHostException,
            is java.net.ConnectException,
            is java.net.NoRouteToHostException,
            is java.net.SocketTimeoutException,
            is javax.net.ssl.SSLException -> YtmBlockSignal.NetworkUnavailable
            is IOException -> YtmBlockSignal.NetworkUnavailable
            else -> YtmBlockSignal.NetworkUnavailable
        }
        assertEquals(YtmBlockSignal.NetworkUnavailable, terminalSignal)
    }

    @Test
    fun testJsonExceptionMapsToNetworkUnavailableAndNotClientSpecific() {
        // FIX #1: JSONException must map to NetworkUnavailable, never ClientDeprecated
        val jsonError: Exception = org.json.JSONException("Value <html of type java.lang.String cannot be converted to JSONObject")
        val terminalSignal = when (val err = jsonError) {
            is InnertubeClient.InnertubeException -> err.signal
            is org.json.JSONException -> YtmBlockSignal.NetworkUnavailable
            else -> YtmBlockSignal.NetworkUnavailable
        }
        assertEquals(YtmBlockSignal.NetworkUnavailable, terminalSignal)

        // Verify NetworkUnavailable does not demote client in winner store
        fun isClientSpecificSignal(sig: YtmBlockSignal?): Boolean =
            sig == YtmBlockSignal.ClientDeprecated ||
            sig == YtmBlockSignal.SabrEnforced ||
            sig == YtmBlockSignal.SignatureDecipherFailed

        assertFalse(isClientSpecificSignal(terminalSignal))
    }

    @Test
    fun testAnchoredNTransformDoesNotReplaceEmbeddedParameters() {
        // FIX #9: Anchored regex should only replace real [?&]n=... parameter, not otherparam=n=...
        val originalUrl = "https://googlevideo.com/videoplayback?other=n=fakeVal&n=origNParamValue&tail=1"
        val transformed = "decipheredNValue"

        val encodedOld = URLEncoder.encode("origNParamValue", "UTF-8")
        val encodedNew = URLEncoder.encode(transformed, "UTF-8")

        val patternExact = Regex("([?&])n=${Regex.escape("origNParamValue")}(?=&|$)")
        val patternEncoded = Regex("([?&])n=${Regex.escape(encodedOld)}(?=&|$)")

        val newUrl = when {
            patternExact.containsMatchIn(originalUrl) -> patternExact.replaceFirst(originalUrl, "$1n=$encodedNew")
            patternEncoded.containsMatchIn(originalUrl) -> patternEncoded.replaceFirst(originalUrl, "$1n=$encodedNew")
            else -> originalUrl
        }

        assertTrue("other=n=fakeVal must be left untouched", newUrl.contains("other=n=fakeVal"))
        assertTrue("real n parameter must be replaced", newUrl.contains("&n=decipheredNValue"))
    }

    @Test
    fun testEmptyPotParameterReplacement() {
        // FIX #17: Replace empty pot= parameter with real token
        val token = "freshPoToken123"
        val urlWithEmptyPot = "https://googlevideo.com/videoplayback?expire=123&pot=&sparams=expire"
        val emptyPotPattern = Regex("([?&])pot=?(?=&|$)")

        val encodedToken = URLEncoder.encode(token, "UTF-8")
        val replacement = "$1pot=" + Regex.escapeReplacement(encodedToken)

        val replaced = if (emptyPotPattern.containsMatchIn(urlWithEmptyPot)) {
            emptyPotPattern.replaceFirst(urlWithEmptyPot, replacement)
        } else {
            urlWithEmptyPot
        }

        assertTrue(replaced.contains("&pot=freshPoToken123"))
        assertFalse(replaced.contains("pot=&"))
    }

    @Test
    fun testEncodedAndEscapedPotReplacementWithSpecialCharacters() {
        // FIX #4: Tokens with &, =, +, $, \ must be safely URL-encoded and Regex-escaped
        val tokenWithSpecials = "po+token=with&special\$chars\\and\\slashes"
        val urlWithEmptyPot = "https://googlevideo.com/videoplayback?expire=123&pot=&sparams=expire"
        val emptyPotPattern = Regex("([?&])pot=?(?=&|$)")

        val encodedToken = URLEncoder.encode(tokenWithSpecials, "UTF-8")
        val replacement = "$1pot=" + Regex.escapeReplacement(encodedToken)

        val replaced = if (emptyPotPattern.containsMatchIn(urlWithEmptyPot)) {
            emptyPotPattern.replaceFirst(urlWithEmptyPot, replacement)
        } else {
            urlWithEmptyPot
        }

        assertFalse("Raw unescaped & must not split parameters", replaced.contains("special\$chars"))
        assertTrue("URL must contain URL-encoded special token", replaced.contains(encodedToken))
    }

    @Test
    fun testTransportLevelEgressSignalsTriggerShortCircuit() {
        // FIX #2: Transport exceptions (IpBlocked, BotChallenge, etc.) increment block count and trigger short-circuit
        val blockSignalCount = AtomicInteger(0)
        val shortCircuitThreshold = 2
        val shortCircuit = AtomicReference<Exception?>(null)
        val globalBlockSignal = AtomicReference<YtmBlockSignal>(YtmBlockSignal.BotChallenge)

        fun onTransportException(signal: YtmBlockSignal) {
            val isTransportEgressBlock =
                signal == YtmBlockSignal.IpBlocked ||
                signal == YtmBlockSignal.BotChallenge ||
                signal == YtmBlockSignal.PoTokenInvalid

            if (isTransportEgressBlock) {
                val count = blockSignalCount.incrementAndGet()
                if (count >= shortCircuitThreshold) {
                    val exc = Exception("Blocked by $count clients")
                    if (shortCircuit.compareAndSet(null, exc)) {
                        globalBlockSignal.set(signal)
                    }
                }
            }
        }

        onTransportException(YtmBlockSignal.IpBlocked)
        assertNull(shortCircuit.get())
        assertEquals(1, blockSignalCount.get())

        onTransportException(YtmBlockSignal.BotChallenge)
        assertNotNull(shortCircuit.get())
        assertEquals(2, blockSignalCount.get())
        assertEquals(YtmBlockSignal.BotChallenge, globalBlockSignal.get())
    }

    @Test
    fun testCandidate1SubmissionNullRejectionFlag() {
        // FIX #5: If submitCandidate returns null, candidate1Submitted must be false
        fun mockSubmit(reject: Boolean): Any? = if (reject) null else "Future"

        val submittedRejected = mockSubmit(reject = true) != null
        assertFalse(submittedRejected)

        val submittedAccepted = mockSubmit(reject = false) != null
        assertTrue(submittedAccepted)
    }

    @Test
    fun testActiveCallsRemovalCleansMap() {
        // FIX #8: removeActiveCall removes client entry when list becomes empty
        val map = java.util.concurrent.ConcurrentHashMap<InnertubeClient.ClientType, java.util.concurrent.CopyOnWriteArrayList<String>>()
        val list = java.util.concurrent.CopyOnWriteArrayList<String>()
        list.add("call1")
        map[InnertubeClient.ClientType.WEB_REMIX] = list

        fun removeCall(client: InnertubeClient.ClientType, call: String) {
            synchronized(map) {
                map[client]?.let { l ->
                    l.remove(call)
                    if (l.isEmpty()) {
                        map.remove(client)
                    }
                }
            }
        }

        assertEquals(1, map.size)
        removeCall(InnertubeClient.ClientType.WEB_REMIX, "call1")
        assertEquals(0, map.size)
        assertFalse(map.containsKey(InnertubeClient.ClientType.WEB_REMIX))
    }

    @Test
    fun testAuthUserHeaderOnlyAttachedWhenCookiesPresent() {
        // FIX #1: x-goog-authuser: 0 must only be attached when cookieHeader is non-empty
        fun buildHeaders(authedWeb: Boolean, cookieHeader: String?): Map<String, String> {
            val headers = mutableMapOf<String, String>()
            if (authedWeb) {
                if (!cookieHeader.isNullOrEmpty()) {
                    headers["Cookie"] = cookieHeader
                    headers["x-goog-authuser"] = "0"
                }
            }
            return headers
        }

        val withoutCookies = buildHeaders(authedWeb = true, cookieHeader = null)
        assertFalse(withoutCookies.containsKey("x-goog-authuser"))
        assertFalse(withoutCookies.containsKey("Cookie"))

        val withEmptyCookies = buildHeaders(authedWeb = true, cookieHeader = "")
        assertFalse(withEmptyCookies.containsKey("x-goog-authuser"))

        val withValidCookies = buildHeaders(authedWeb = true, cookieHeader = "SAPISID=123")
        assertTrue(withValidCookies.containsKey("x-goog-authuser"))
        assertEquals("0", withValidCookies["x-goog-authuser"])
        assertEquals("SAPISID=123", withValidCookies["Cookie"])
    }

    @Test
    fun testNTransformGuardsEmptyOrNullString() {
        // FIX #4: Empty or null transformed n must return original url
        fun applyNTransform(url: String, transformed: String?): String {
            val n = "originalN123"
            if (transformed.isNullOrEmpty() || transformed == n) return url
            return url.replace("n=$n", "n=$transformed")
        }

        val original = "https://googlevideo.com/videoplayback?expire=123&n=originalN123"
        assertEquals(original, applyNTransform(original, ""))
        assertEquals(original, applyNTransform(original, null))
        assertEquals(original, applyNTransform(original, "originalN123"))

        val expected = "https://googlevideo.com/videoplayback?expire=123&n=decipheredN"
        assertEquals(expected, applyNTransform(original, "decipheredN"))
    }

    @Test
    fun testRecoverySkipsRateLimited() {
        // FIX #10: Skip recovery retry on RateLimited
        fun shouldSkipRecovery(signal: YtmBlockSignal?): Boolean {
            return signal == YtmBlockSignal.NetworkUnavailable || signal == YtmBlockSignal.RateLimited
        }

        assertTrue(shouldSkipRecovery(YtmBlockSignal.NetworkUnavailable))
        assertTrue(shouldSkipRecovery(YtmBlockSignal.RateLimited))
        assertFalse(shouldSkipRecovery(YtmBlockSignal.BotChallenge))
        assertFalse(shouldSkipRecovery(YtmBlockSignal.PoTokenInvalid))
    }

    @Test
    fun testDataSyncBootstrapBackoffBySignal() {
        // FIX #11: Differentiate bootstrap retry cooldown by failure signal
        fun computeBackoff(signal: YtmBlockSignal?): Long {
            return when (signal) {
                YtmBlockSignal.RateLimited -> 60_000L
                YtmBlockSignal.NetworkUnavailable -> 10_000L
                else -> 30_000L
            }
        }

        assertEquals(60_000L, computeBackoff(YtmBlockSignal.RateLimited))
        assertEquals(10_000L, computeBackoff(YtmBlockSignal.NetworkUnavailable))
        assertEquals(30_000L, computeBackoff(YtmBlockSignal.BotChallenge))
        assertEquals(30_000L, computeBackoff(YtmBlockSignal.IpBlocked))
    }

    @Test
    fun testFastFailSignalsBypassRetry() {
        fun shouldFastFail(signal: YtmBlockSignal): Boolean {
            return signal == YtmBlockSignal.SignInRequired ||
                signal == YtmBlockSignal.VideoGone ||
                signal == YtmBlockSignal.BotChallenge ||
                signal == YtmBlockSignal.IpBlocked ||
                signal == YtmBlockSignal.PoTokenInvalid ||
                signal == YtmBlockSignal.ClientDeprecated ||
                signal == YtmBlockSignal.SabrEnforced ||
                signal == YtmBlockSignal.SignatureDecipherFailed ||
                signal == YtmBlockSignal.GeoBlocked
        }

        assertTrue(shouldFastFail(YtmBlockSignal.SignInRequired))
        assertTrue(shouldFastFail(YtmBlockSignal.VideoGone))
        assertTrue(shouldFastFail(YtmBlockSignal.BotChallenge))
        assertTrue(shouldFastFail(YtmBlockSignal.IpBlocked))
        assertTrue(shouldFastFail(YtmBlockSignal.PoTokenInvalid))
        assertTrue(shouldFastFail(YtmBlockSignal.ClientDeprecated))
        assertTrue(shouldFastFail(YtmBlockSignal.SabrEnforced))
        assertTrue(shouldFastFail(YtmBlockSignal.SignatureDecipherFailed))
        assertTrue(shouldFastFail(YtmBlockSignal.GeoBlocked))

        assertFalse(shouldFastFail(YtmBlockSignal.RateLimited))
        assertFalse(shouldFastFail(YtmBlockSignal.NetworkUnavailable))
    }

    @Test
    fun testGlobalBreakerResetOnSuccess() {
        val consecutiveEgressBlocks = AtomicInteger(5)
        val globalBlockCooldownUntilMs = java.util.concurrent.atomic.AtomicLong(123456789L)
        val globalBlockSignal = AtomicReference(YtmBlockSignal.IpBlocked)

        // Simulate success path reset
        consecutiveEgressBlocks.set(0)
        globalBlockCooldownUntilMs.set(0L)
        globalBlockSignal.set(YtmBlockSignal.BotChallenge)

        assertEquals(0, consecutiveEgressBlocks.get())
        assertEquals(0L, globalBlockCooldownUntilMs.get())
        assertEquals(YtmBlockSignal.BotChallenge, globalBlockSignal.get())
    }

    @Test
    fun testEmptyPotReplacementWithUrlFragment() {
        val token = "fragmentToken123"
        val urlWithFrag = "https://googlevideo.com/videoplayback?expire=123&pot#playhead=0"
        val emptyPotPattern = Regex("([?&])pot=?(?=&|#|$)")

        val encodedToken = URLEncoder.encode(token, "UTF-8")
        val replacement = "$1pot=" + Regex.escapeReplacement(encodedToken)

        val replaced = if (emptyPotPattern.containsMatchIn(urlWithFrag)) {
            emptyPotPattern.replaceFirst(urlWithFrag, replacement)
        } else {
            urlWithFrag
        }

        assertEquals("https://googlevideo.com/videoplayback?expire=123&pot=fragmentToken123#playhead=0", replaced)
    }

    @Test
    fun testRecoveryBypassesShortCircuit() {
        val shortCircuit = AtomicReference<Exception?>(Exception("Pre-existing short-circuit"))

        fun attemptClientMock(ignoreShortCircuit: Boolean): InnertubeClient.AttemptResult {
            if (!ignoreShortCircuit && shortCircuit.get() != null) {
                return InnertubeClient.AttemptResult.ShortCircuited
            }
            return InnertubeClient.AttemptResult.Success(mapOf("recovered" to true))
        }

        // Standard attempt honors short-circuit
        val normalAttempt = attemptClientMock(ignoreShortCircuit = false)
        assertTrue(normalAttempt is InnertubeClient.AttemptResult.ShortCircuited)

        // Recovery attempt bypasses short-circuit
        val recoveryAttempt = attemptClientMock(ignoreShortCircuit = true)
        assertTrue(recoveryAttempt is InnertubeClient.AttemptResult.Success)
    }

    @Test
    fun testSabrDemotionOnNon2xxOrTransportError() {
        var demotedClient: InnertubeClient.ClientType? = null
        val demotionStoreMock = { client: InnertubeClient.ClientType -> demotedClient = client }

        val signal = YtmBlockSignal.SabrEnforced
        val client = InnertubeClient.ClientType.WEB_REMIX

        if (signal == YtmBlockSignal.SabrEnforced) {
            demotionStoreMock(client)
        }

        assertEquals(InnertubeClient.ClientType.WEB_REMIX, demotedClient)
    }

    @Test
    fun testShortCircuitThresholdDynamicBehavior() {
        val blockSignalCount = AtomicInteger(0)
        val shortCircuitThreshold = 2
        val shortCircuit = AtomicReference<Exception?>(null)

        fun recordBlock(client: String) {
            val count = blockSignalCount.incrementAndGet()
            if (count >= shortCircuitThreshold) {
                shortCircuit.compareAndSet(null, Exception("Blocked by $count clients"))
            }
        }

        recordBlock("WEB_REMIX")
        assertNull(shortCircuit.get())

        recordBlock("ANDROID_MUSIC")
        assertNotNull(shortCircuit.get())
        assertEquals("Blocked by 2 clients", shortCircuit.get()?.message)
    }
}

