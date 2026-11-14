package com.pulsr.music

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.Proxy

class NativeHardeningRegressionTest {

    @After
    fun tearDown() {
        ProxyPool.clearPool()
    }

    // ---- AudioIntentClassifier ----

    @Test
    fun spoofedYouTubeHostsAreRejectedAndRealHostsAccepted() {
        assertFalse(AudioIntentClassifier.isYouTubeUrl("https://evil.com/youtube.com/watch?v=abc"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("https://notyoutube.com/watch?v=abc"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("https://youtube.com.evil.tld/watch?v=abc"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("https://youtu.be.attacker.org/xyz"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("https://evil.com/?redirect=https://youtu.be/xyz"))
        assertFalse(AudioIntentClassifier.isYouTubeUrl("just mentioning youtube.com without scheme"))

        assertTrue(AudioIntentClassifier.isYouTubeUrl("https://www.youtube.com/watch?v=abc"))
        assertTrue(AudioIntentClassifier.isYouTubeUrl("https://music.youtube.com/watch?v=abc"))
        assertTrue(AudioIntentClassifier.isYouTubeUrl("https://youtu.be/abc"))
        assertTrue(AudioIntentClassifier.isYouTubeUrl("Check out this track https://m.youtube.com/watch?v=xyz !"))
    }

    @Test
    fun proxyTextIsRecognisedAndArbitraryTextRejected() {
        assertTrue(AudioIntentClassifier.isProxyText("http://10.0.0.1:8080"))
        assertTrue(AudioIntentClassifier.isProxyText("socks5 192.168.1.2:1080"))
        assertTrue(AudioIntentClassifier.isProxyText("proxy 10.0.0.5:3128"))
        assertFalse(AudioIntentClassifier.isProxyText("https://example.com/music.html"))

        assertTrue(
            AudioIntentClassifier.isAudioIntentParts(
                action = "android.intent.action.SEND",
                scheme = null,
                path = null,
                host = null,
                mimeType = "text/plain",
                textExtra = "proxy 10.0.0.5:3128",
            ),
        )
    }

    @Test
    fun fileRootTraversalAndPrefixSiblingsAreRejected() {
        val roots = listOf("/storage/emulated/0")
        assertFalse(
            AudioIntentClassifier.isSafeUriParts("file", "/storage/emulated/0/../etc/passwd", roots),
        )
        assertFalse(
            AudioIntentClassifier.isSafeUriParts("file", "/storage/emulated/0/Music/../../secret.flac", roots),
        )
        assertFalse(
            AudioIntentClassifier.isSafeUriParts("file", "/storage/emulated/0_sibling/track.flac", roots),
        )
        assertTrue(
            AudioIntentClassifier.isSafeUriParts("file", "/storage/emulated/0/Music/./track.flac", roots),
        )
    }

    // ---- AudioTempFiles ----

    @Test
    fun copyLimitedTruncatesSilentlyWhenThrowOnOverflowFalse() {
        val payload = ByteArray(1024) { (it and 0xFF).toByte() }
        val out = ByteArrayOutputStream()
        AudioTempFiles.copyLimited(
            ByteArrayInputStream(payload),
            out,
            maxBytes = 256L,
            throwOnOverflow = false,
        )
        val truncated = out.toByteArray()
        assertEquals(256, truncated.size)
        assertArrayEquals(payload.copyOfRange(0, 256), truncated)
    }

    @Test
    fun copyLimitedThrowsOnOverflowByDefaultAndPassesExactFit() {
        val payload = ByteArray(1024) { 0x42 }
        val overflowOut = ByteArrayOutputStream()
        try {
            AudioTempFiles.copyLimited(ByteArrayInputStream(payload), overflowOut, maxBytes = 256L)
            fail("Expected IOException when throwOnOverflow=true")
        } catch (_: IOException) {
            // expected
        }

        val exactOut = ByteArrayOutputStream()
        AudioTempFiles.copyLimited(ByteArrayInputStream(payload), exactOut, maxBytes = 1024L)
        assertEquals(1024, exactOut.toByteArray().size)
    }

    @Test
    fun extensionFromMagicSniffsCommonContainersAndFormats() {
        assertEquals(".flac", AudioTempFiles.extensionFromMagic("fLaC\u0000\u0000".encodeToByteArray()))
        assertEquals(".ogg", AudioTempFiles.extensionFromMagic("OggS\u0000\u0002".encodeToByteArray()))
        assertEquals(".wav", AudioTempFiles.extensionFromMagic("RIFF1234WAVE".encodeToByteArray()))
        assertEquals(".aiff", AudioTempFiles.extensionFromMagic("FORM1234AIFF".encodeToByteArray()))
        assertEquals(".m4a", AudioTempFiles.extensionFromMagic("\u0000\u0000\u0000\u0018ftypM4A ".encodeToByteArray()))
        assertEquals(".dsf", AudioTempFiles.extensionFromMagic("DSD \u001c\u0000".encodeToByteArray()))
        assertEquals(".dff", AudioTempFiles.extensionFromMagic("FRM8\u0000\u0000".encodeToByteArray()))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic("ID3\u0004\u0000".encodeToByteArray()))
        assertEquals(".mp3", AudioTempFiles.extensionFromMagic(byteArrayOf(0xFF.toByte(), 0xFB.toByte(), 0x90.toByte(), 0x00)))
        assertEquals("", AudioTempFiles.extensionFromMagic("JUNK_BYTES".encodeToByteArray()))
    }

    // ---- AudioEffectsPlugin clamp & ordering validators ----

    @Test
    fun clampRejectsNonFiniteAndBoundsFiniteValues() {
        assertEquals(-36.0, AudioEffectsPlugin.clamp(Double.NaN, -36.0, 36.0), 0.0)
        assertEquals(-36.0, AudioEffectsPlugin.clamp(Double.POSITIVE_INFINITY, -36.0, 36.0), 0.0)
        assertEquals(-36.0, AudioEffectsPlugin.clamp(Double.NEGATIVE_INFINITY, -36.0, 36.0), 0.0)
        assertEquals(-36.0, AudioEffectsPlugin.clamp(-99.0, -36.0, 36.0), 0.0)
        assertEquals(36.0, AudioEffectsPlugin.clamp(99.0, -36.0, 36.0), 0.0)
        assertEquals(12.5, AudioEffectsPlugin.clamp(12.5, -36.0, 36.0), 0.0)
    }

    @Test
    fun crossoverAndDynamicBassValidatorsEnforceStrictAscendingOrder() {
        val (f0, f1, f2) = AudioEffectsPlugin.validateMultibandCrossovers(500.0, 200.0, 200.0)
        assertTrue("Expected f0 < f1 < f2, got $f0, $f1, $f2", f0 < f1 && f1 < f2)
        assertEquals(500.0, f0, 0.0)
        assertEquals(501.0, f1, 0.0)
        assertEquals(1000.0, f2, 0.0)

        val (nanF0, nanF1, nanF2) = AudioEffectsPlugin.validateMultibandCrossovers(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            100.0,
        )
        assertTrue(nanF0.isFinite() && nanF1.isFinite() && nanF2.isFinite())
        assertTrue(nanF0 < nanF1 && nanF1 < nanF2)

        val bass = AudioEffectsPlugin.validateDynamicBassRanges(2000, 500, 200, 30)
        assertEquals(2000, bass[0])
        assertEquals(2001, bass[1])
        assertEquals(200, bass[2])
        assertEquals(201, bass[3])

        val (wLow, wHigh) = AudioEffectsPlugin.validateStereoWidthCrossovers(1000.0, 500.0)
        assertEquals(1000.0, wLow, 0.0)
        assertEquals(1001.0, wHigh, 0.0)

        assertEquals(1L * 1024 * 1024, AudioEffectsPlugin.clampCacheBudgetBytes(0L))
        assertEquals(256L * 1024 * 1024, AudioEffectsPlugin.clampCacheBudgetBytes(512L * 1024 * 1024))
    }

    // ---- TagEditorPlugin verification rules ----

    @Test
    fun tagEditorVerificationChecksAllProvidedFieldsAndEmptyTagsOnReread() {
        val emptyOk = TagEditorPlugin.verifyWrittenTags(emptyMap(), emptyMap())
        assertTrue(emptyOk.verified)
        assertTrue(emptyOk.verifiedFields.isEmpty())

        val rereadMissing = TagEditorPlugin.verifyWrittenTags(mapOf("genre" to "Jazz"), null)
        assertFalse(rereadMissing.verified)

        val genreOk = TagEditorPlugin.verifyWrittenTags(
            mapOf("genre" to "Jazz"),
            mapOf("genre" to "Jazz"),
        )
        assertTrue(genreOk.verified)
        assertEquals(mapOf("genre" to true), genreOk.verifiedFields)

        val partialFailure = TagEditorPlugin.verifyWrittenTags(
            mapOf("title" to "Song", "genre" to "Jazz"),
            mapOf("title" to "Song", "genre" to "Pop"),
        )
        assertFalse(partialFailure.verified)
        assertEquals(false, partialFailure.verifiedFields["genre"])

        val clearedOk = TagEditorPlugin.verifyWrittenTags(
            mapOf("genre" to "", "lyrics" to null),
            mapOf("genre" to "", "lyrics" to null),
        )
        assertTrue(clearedOk.verified)
    }

    // ---- ProxyPool stableOrderedAlive with mixed ewma & latency ----

    @Test
    fun proxyPoolOrdersByQualityThenEwmaDescThenPositiveLatencyAscThenId() {
        fun makeNode(
            id: String,
            quality: ProxyPool.Quality,
            ewma: Double,
            latencyMs: Long,
        ) = ProxyPool.ProxyNode(
            id = id,
            type = Proxy.Type.HTTP,
            host = "10.0.0.1",
            port = 8080,
            latencyMs = latencyMs,
            quality = quality,
            ewmaSuccessRate = ewma,
        )

        val unknownFastHighEwma = makeNode("fast", ProxyPool.Quality.UNKNOWN, ewma = 1.0, latencyMs = 20L)
        val resSlowLowEwma = makeNode("res", ProxyPool.Quality.RESIDENTIAL, ewma = 0.5, latencyMs = 300L)
        val unknownSlow = makeNode("slow", ProxyPool.Quality.UNKNOWN, ewma = 1.0, latencyMs = 200L)
        val unknownUnprobed = makeNode("unprobed", ProxyPool.Quality.UNKNOWN, ewma = 1.0, latencyMs = -1L)
        val unknownDegraded = makeNode("degraded", ProxyPool.Quality.UNKNOWN, ewma = 0.7, latencyMs = 10L)
        val dcFast = makeNode("dc", ProxyPool.Quality.DATACENTER, ewma = 1.0, latencyMs = 5L)

        ProxyPool.setProxies(
            listOf(dcFast, unknownUnprobed, unknownDegraded, unknownSlow, resSlowLowEwma, unknownFastHighEwma),
        )

        val orderedIds = ProxyPool.stableOrderedAlive().map { it.id }
        assertEquals(
            listOf("res", "fast", "slow", "unprobed", "degraded", "dc"),
            orderedIds,
        )
    }
}
