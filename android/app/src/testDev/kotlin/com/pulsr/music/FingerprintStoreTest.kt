package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class FingerprintStoreTest {

    @Test
    fun testDefaultLocaleMatchesSystemLocale() {
        val originalLocale = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            assertEquals("en", FingerprintStore.DEFAULT_HL)
            assertEquals("US", FingerprintStore.DEFAULT_GL)

            Locale.setDefault(Locale.FRANCE)
            assertEquals("fr", FingerprintStore.DEFAULT_HL)
            assertEquals("FR", FingerprintStore.DEFAULT_GL)

            Locale.setDefault(Locale.JAPAN)
            assertEquals("ja", FingerprintStore.DEFAULT_HL)
            assertEquals("JP", FingerprintStore.DEFAULT_GL)
        } finally {
            Locale.setDefault(originalLocale)
        }
    }

    @Test
    fun testUserAgentFormatting() {
        val fp = FingerprintStore.DeviceFingerprint(
            installUuid = "test-uuid",
            deviceMake = "Google",
            deviceModel = "Pixel 8",
            osVersion = "14",
            sdkInt = 34,
            hl = "en",
            gl = "US"
        )
        val androidUa = fp.buildUserAgent(InnertubeClient.ClientType.ANDROID_MUSIC)
        assertNotNull(androidUa)
        assertTrue(androidUa.contains("Pixel 8"))
        assertTrue(androidUa.contains("en_US"))

        val webUa = fp.buildUserAgent(InnertubeClient.ClientType.WEB_REMIX)
        assertTrue(webUa.contains("Windows NT 10.0"))
    }
}
