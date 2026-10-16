package com.pulsr.music

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AudioEffectsPluginIntegrationTest {

    private lateinit var context: Context
    private lateinit var plugin: AudioEffectsPlugin

    private class SyncResult : MethodChannel.Result {
        var successValue: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        val latch = CountDownLatch(1)

        override fun success(result: Any?) {
            successValue = result
            latch.countDown()
        }

        override fun error(code: String, message: String?, details: Any?) {
            errorCode = code
            errorMessage = message
            latch.countDown()
        }

        override fun notImplemented() {
            errorCode = "NOT_IMPLEMENTED"
            latch.countDown()
        }

        fun await(timeoutSeconds: Long = 3): Any? {
            assertTrue("Method call timed out", latch.await(timeoutSeconds, TimeUnit.SECONDS))
            assertNull("Method returned error: $errorCode - $errorMessage", errorCode)
            return successValue
        }
    }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        plugin = AudioEffectsPlugin()
    }

    private fun invoke(method: String, args: Map<String, Any?> = emptyMap()): Any? {
        val result = SyncResult()
        plugin.onMethodCall(MethodCall(method, args), result)
        return result.await()
    }

    @Test
    fun testAudioSessionRecreationAndDetachment() {
        // Step 1: Attach to initial session S1 (101)
        val s1Result = invoke("setAudioSessionId", mapOf("audioSessionId" to 101))
        assertNotNull("Session 101 should return status", s1Result)

        // Configure DSP stage on S1
        invoke("setVirtualizerStrength", mapOf("strength" to 500))
        invoke("setBassBoost", mapOf("strength" to 400))

        // Step 2: Recreate AudioTrack with a new session S2 (202)
        val s2Result = invoke("setAudioSessionId", mapOf("audioSessionId" to 202))
        assertNotNull("Session 202 should return status", s2Result)

        // Query status to ensure S2 is now the active session and no stale S1 remains
        val report = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull("DSP report should be available", report)
        assertEquals("Active session must match S2", 202, (report?.get("audioSessionId") as? Number)?.toInt())

        // Step 3: Tear down to 0 - must safely detach all effects
        val detachResult = invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
        assertEquals("Detaching session 0 must succeed", true, detachResult)

        val detachedReport = invoke("getDspDebugStatus") as? Map<*, *>
        assertEquals("Session should be 0", 0, (detachedReport?.get("audioSessionId") as? Number)?.toInt())
        assertEquals("Session attached flag should be false", false, detachedReport?.get("isSessionAttached"))
    }

    @Test
    fun testBitPerfectEnableAndDisableRestoration() {
        // Set up active session
        invoke("setAudioSessionId", mapOf("audioSessionId" to 105))

        // Enable stages
        invoke("setLimiterEnabled", mapOf("enabled" to true))
        invoke("setReverbEnabled", mapOf("enabled" to true))
        invoke("setCrossfeedEnabled", mapOf("enabled" to true))

        // Step 1: Enable Bit-Perfect bypass
        val bypassResult = invoke("setBypassDspForBitPerfect", mapOf("bypass" to true))
        assertEquals(true, bypassResult)

        val bypassedReport = invoke("getDspDebugStatus") as? Map<*, *>
        assertEquals("Bit-perfect bypass must be active", true, bypassedReport?.get("isBitPerfectBypassActive"))

        // Step 2: Disable Bit-Perfect bypass - all DSP stages must restore
        val restoreResult = invoke("setBypassDspForBitPerfect", mapOf("bypass" to false))
        assertEquals(true, restoreResult)

        val restoredReport = invoke("getDspDebugStatus") as? Map<*, *>
        assertEquals("Bit-perfect bypass must be inactive", false, restoredReport?.get("isBitPerfectBypassActive"))

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testRouteChangesAndFormatResync() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 110))

        // Simulate 44.1 kHz track
        val resync44 = invoke("resyncForTrack", mapOf("sampleRate" to 44100.0, "channels" to 2))
        assertNotNull(resync44)

        // Simulate route change to Hi-Res USB DAC at 96 kHz
        val resync96 = invoke("resyncForTrack", mapOf("sampleRate" to 96000.0, "channels" to 2))
        assertNotNull(resync96)

        // Simulate route fallback back to 48 kHz
        val resync48 = invoke("resyncForTrack", mapOf("sampleRate" to 48000.0, "channels" to 2))
        assertNotNull(resync48)

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testBluetoothDisconnectAndReconnect() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 115))

        // Headphone crossfeed on Bluetooth route
        invoke("setCrossfeedMode", mapOf("mode" to "headphone"))
        invoke("setCrossfeedEnabled", mapOf("enabled" to true))

        // Route change to speaker
        invoke("setCrossfeedMode", mapOf("mode" to "speaker"))

        // Reconnect Bluetooth
        invoke("setCrossfeedMode", mapOf("mode" to "headphone"))
        val crossfeedResult = invoke("setCrossfeedEnabled", mapOf("enabled" to true))
        assertNotNull(crossfeedResult)

        // Clean tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testUsbDacConnectAndDisconnect() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 120))

        // USB DAC connect: 192 kHz direct format resync
        val usbConnect = invoke("resyncForTrack", mapOf("sampleRate" to 192000.0, "channels" to 2))
        assertNotNull(usbConnect)

        // USB DAC disconnect: fallback to built-in speaker at 48 kHz
        val usbDisconnect = invoke("resyncForTrack", mapOf("sampleRate" to 48000.0, "channels" to 2))
        assertNotNull(usbDisconnect)

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }
}
