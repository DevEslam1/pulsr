package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Task B6: Unit tests for EgressSessionManager.
 *
 * Verifies:
 * 1. Network switch changes composite egressId and fires change listener.
 * 2. Mismatched-egress URLs fail validation and are rejected.
 * 3. ProxyPool rotation between tracks updates egress and triggers listener.
 */
class EgressSessionManagerTest {

    private lateinit var manager: EgressSessionManager
    private val changeEvents = mutableListOf<String>()

    @Before
    fun setUp() {
        manager = EgressSessionManager(context = null)
        changeEvents.clear()
        manager.addOnEgressChangeListener { changeEvents.add(it) }
    }

    @Test
    fun testNetworkSwitchChangesEgressAndNotifiesListener() {
        manager.updateNetworkTypeForTesting("WIFI")
        manager.updateProxyExit("DIRECT")
        assertEquals("WIFI_DIRECT", manager.currentEgressId)

        changeEvents.clear()
        manager.updateNetworkTypeForTesting("CELLULAR")

        assertEquals("CELLULAR_DIRECT", manager.currentEgressId)
        assertEquals(1, changeEvents.size)
        assertEquals("CELLULAR_DIRECT", changeEvents.first())
    }

    @Test
    fun testMismatchedEgressUrlIsRejected() {
        manager.updateNetworkTypeForTesting("WIFI")
        manager.updateProxyExit("DIRECT")
        val wifiEgress = manager.currentEgressId

        assertTrue(manager.isEgressValid(wifiEgress))

        // Switch network to Cellular
        manager.updateNetworkTypeForTesting("CELLULAR")

        // Old wifi-resolved URL must now be rejected
        assertFalse(manager.isEgressValid(wifiEgress))
        assertTrue(manager.isEgressValid(manager.currentEgressId))
    }

    @Test
    fun testProxyRotationBetweenTracksUpdatesEgress() {
        manager.updateNetworkTypeForTesting("WIFI")
        manager.updateProxyExit("DIRECT")

        val track1Egress = manager.bindTrackSession("track_01")
        assertEquals("WIFI_DIRECT", track1Egress)

        // Rotate proxy for next track
        changeEvents.clear()
        val track2Egress = manager.rotateBetweenTracks("HTTP:10.0.0.1:8080")

        assertEquals("WIFI_HTTP:10.0.0.1:8080", track2Egress)
        assertEquals(1, changeEvents.size)
        assertEquals("WIFI_HTTP:10.0.0.1:8080", changeEvents.first())

        // Track 1 egress should now be invalidated for future resolutions
        assertFalse(manager.isEgressValid(track1Egress))
    }
}
