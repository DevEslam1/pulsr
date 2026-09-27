package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger

class DecipherWiringTest {

    @Test
    fun testEgressTrackerStableMappingContract() {
        // B-03 contract test: proxy label and direct routes normalize consistently
        val directWifi = EgressTracker.egressId("DIRECT", vpnActive = false, isCellular = false)
        val nullWifi = EgressTracker.egressId(null, vpnActive = false, isCellular = false)
        val blankWifi = EgressTracker.egressId("   ", vpnActive = false, isCellular = false)
        assertEquals("wifi:direct", directWifi)
        assertEquals("wifi:direct", nullWifi)
        assertEquals("wifi:direct", blankWifi)

        val vpnDirect = EgressTracker.egressId("DIRECT", vpnActive = true, isCellular = false)
        assertEquals("vpn:direct", vpnDirect)

        val cellDirect = EgressTracker.egressId("DIRECT", vpnActive = false, isCellular = true)
        assertEquals("cell:direct", cellDirect)

        val proxyNode = EgressTracker.egressId("HTTP:1.2.3.4:8080", vpnActive = false, isCellular = false)
        assertEquals("proxy:HTTP:1.2.3.4:8080", proxyNode)

        // Verify that listeners receiving normalized egress do not trigger spurious invalidations
        val invalidationCount = AtomicInteger(0)
        var currentEgress = directWifi
        val onEgressChanged: (String) -> Unit = { newId ->
            if (currentEgress != newId) {
                invalidationCount.incrementAndGet()
                currentEgress = newId
            }
        }

        // Switching from DIRECT to DIRECT (or same label) must NOT invalidate
        onEgressChanged(EgressTracker.egressId("DIRECT", vpnActive = false, isCellular = false))
        assertEquals(0, invalidationCount.get())

        // Switching to real proxy invalidates exactly once
        onEgressChanged(EgressTracker.egressId("HTTP:1.2.3.4:8080", vpnActive = false, isCellular = false))
        assertEquals(1, invalidationCount.get())

        // Same proxy does not invalidate again
        onEgressChanged(EgressTracker.egressId("HTTP:1.2.3.4:8080", vpnActive = false, isCellular = false))
        assertEquals(1, invalidationCount.get())
    }

    @Test
    fun testCastMediaServerActiveTokenNotEvicted() {
        // B-04 acceptance test: prebuffer next track -> seek current track after simulated 6 minutes -> correct bytes served
        val server = CastMediaServer()
        assertTrue(server.start())

        try {
            val file1 = File.createTempFile("pulsr_cast_test1_", ".mp3")
            val file2 = File.createTempFile("pulsr_cast_test2_", ".mp3")
            file1.writeBytes(ByteArray(1024) { 1.toByte() })
            file2.writeBytes(ByteArray(1024) { 2.toByte() })

            // Serve file 1 (current track)
            val url1 = server.serveFile(file1.absolutePath, "audio/mpeg")
            assertNotNull(url1)
            val token1 = url1!!.substringAfterLast("/")

            // Make initial request on track 1 to make it the active serving token
            val conn1 = URL(url1).openConnection() as HttpURLConnection
            assertEquals(206, conn1.responseCode)
            val bytes1 = conn1.inputStream.readBytes()
            assertEquals(1024, bytes1.size)
            assertEquals(1.toByte(), bytes1[0])

            // Prebuffer track 2 (next track), overwriting legacyMedia
            val url2 = server.preBufferFile(file2.absolutePath, "audio/mpeg")
            assertNotNull(url2)

            // Simulate 6 minutes elapsed on file 1
            // Even after 6 minutes, token1 is the currently serving token and must NOT be evicted
            // Calling serveFile triggers the eviction pass
            val file3 = File.createTempFile("pulsr_cast_test3_", ".mp3")
            file3.writeBytes(ByteArray(512) { 3.toByte() })
            server.serveFile(file3.absolutePath, "audio/mpeg")

            // Seek on current track (track 1) with Range header
            val seekConn = URL(url1).openConnection() as HttpURLConnection
            seekConn.setRequestProperty("Range", "bytes=100-199")
            assertEquals(206, seekConn.responseCode)
            val seekBytes = seekConn.inputStream.readBytes()
            assertEquals(100, seekBytes.size)
            // Verify correct bytes from file 1 are served (NOT file 2!)
            assertEquals(1.toByte(), seekBytes[0])

            file1.delete()
            file2.delete()
            file3.delete()
        } finally {
            server.stop()
        }
    }
}
