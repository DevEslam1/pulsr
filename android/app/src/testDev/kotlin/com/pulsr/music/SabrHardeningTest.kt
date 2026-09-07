// JVM tests for the 2026-09 hardening kit (SabrDemotionState, SABR structural
// detection, EgressTracker). No Android framework needed — pure logic only.
// Place in: android/app/src/testDev/kotlin/com/pulsr/music/SabrHardeningTest.kt

package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SabrHardeningTest {

    // ---- YtmBlockSignal.detectSabrStructural --------------------------------

    @Test
    fun `structural SABR detected when formats exist without urls or cipher`() {
        assertTrue(
            YtmBlockSignal.detectSabrStructural(
                hasStreamingData = true, formatCount = 4, urlCount = 0, cipherCount = 0,
            )
        )
    }

    @Test
    fun `direct urls present means not SABR`() {
        assertFalse(
            YtmBlockSignal.detectSabrStructural(
                hasStreamingData = true, formatCount = 4, urlCount = 3, cipherCount = 0,
            )
        )
    }

    @Test
    fun `ciphered-only response is SignatureDecipherFailed territory, not SABR`() {
        assertFalse(
            YtmBlockSignal.detectSabrStructural(
                hasStreamingData = true, formatCount = 4, urlCount = 0, cipherCount = 4,
            )
        )
    }

    @Test
    fun `no streamingData or empty formats is not SABR`() {
        assertFalse(
            YtmBlockSignal.detectSabrStructural(
                hasStreamingData = false, formatCount = 0, urlCount = 0, cipherCount = 0,
            )
        )
    }

    // ---- YtmBlockSignal.parse: SABR substring precedence --------------------

    @Test
    fun `parse maps explicit SABR wording to SabrEnforced`() {
        val playability = org.json.JSONObject()
            .put("status", "UNPLAYABLE")
            .put("reason", "YouTube is forcing SABR streaming for this client")
        assertEquals(YtmBlockSignal.SabrEnforced, YtmBlockSignal.parse(200, "UNPLAYABLE", playability))
    }

    // ---- SabrDemotionState TTL ----------------------------------------------

    @Test
    fun `demotion expires after TTL`() {
        var now = 1_000_000L
        val state = SabrDemotionState(clock = { now })
        state.mark("WEB_REMIX")
        assertTrue(state.isDemoted("WEB_REMIX"))
        now += SabrDemotionState.DEFAULT_TTL_MS + 1
        assertFalse(state.isDemoted("WEB_REMIX"))
    }

    @Test
    fun `clear removes demotion immediately`() {
        var now = 1_000_000L
        val state = SabrDemotionState(clock = { now })
        state.mark("IOS_MUSIC")
        state.clear("IOS_MUSIC")
        assertFalse(state.isDemoted("IOS_MUSIC"))
    }

    // ---- EgressTracker -------------------------------------------------------

    @Test
    fun `proxy label wins over network class`() {
        assertEquals("proxy:HTTP:1.2.3.4:8080", EgressTracker.egressId("HTTP:1.2.3.4:8080", vpnActive = false, isCellular = false))
    }

    @Test
    fun `DIRECT label falls through to network class`() {
        assertEquals("wifi:direct", EgressTracker.egressId("DIRECT", vpnActive = false, isCellular = false))
        assertEquals("cell:direct", EgressTracker.egressId(null, vpnActive = false, isCellular = true))
    }

    @Test
    fun `vpn beats cellular when no proxy`() {
        assertEquals("vpn:direct", EgressTracker.egressId(null, vpnActive = true, isCellular = true))
    }
}
