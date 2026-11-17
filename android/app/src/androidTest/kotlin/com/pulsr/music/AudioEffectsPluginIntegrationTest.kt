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

    // Live count of enabled app-owned HAL effects, read from the public debug
    // map only. -1 when the key is missing, so a renamed key fails both the
    // `>= 1` and the `== 0` assertion instead of silently satisfying one.
    private fun halStagesActive(report: Map<*, *>): Int =
        (report["halStagesActive"] as? Number)?.toInt() ?: -1

    private fun dspDebugStatus(): Map<*, *> {
        val report = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull("DSP debug report should be available", report)
        return report!!
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

    /**
     * Phase 5 item 16 (audit/verify_tests.md BF-4 / 3.1A): the bypass must leave
     * no app-owned HAL effect enabled on the live session, including when the
     * session is swapped while the bypass is active - the swap recreates every
     * effect instance from the user's flags, which is the regression this test
     * exists for.
     *
     * `halStagesActive` counts *live, enabled* effect objects
     * (AudioEffectsPlugin.countEnabledAppOwnedHalStages), so the first
     * assertion is a positive control: on its own, `== 0` would also pass on a
     * build where the cleanup was deleted and nothing was ever constructed.
     * `isBitExactChain` is deliberately NOT asserted: it needs
     * nativeLastBlockWasBitPerfect(), i.e. a block rendered by the native
     * engine, which a plugin-only instrumentation test never produces.
     *
     * If the positive control fails, the device refused to construct or enable
     * the HAL effects for a session with no live AudioTrack; the fallback in
     * audit/verify_tests.md 3.1A is a real session id plus a muted AudioTrack.
     */
    @Test
    fun testBitPerfectBypassClearsAndRestoresAppOwnedHalStages() {
        // Session 1: three app-owned HAL stages, all user-enabled.
        invoke("setAudioSessionId", mapOf("audioSessionId" to 1))
        val virtualizerResult = invoke("setVirtualizerEnabled", mapOf("enabled" to true))
        val volumeBoostResult = invoke("setVolumeBoost", mapOf("milliBels" to 400))
        val bassBoostResult = invoke("setBassBoost", mapOf("strength" to 400))

        // Positive control: the effects must really exist and be enabled,
        // otherwise every `halStagesActive == 0` below is vacuous.
        val stagesBeforeBypass = halStagesActive(dspDebugStatus())
        assertTrue(
            "No app-owned HAL stage was enabled on session 1 " +
                "(virtualizer=$virtualizerResult, volumeBoost=$volumeBoostResult, " +
                "bassBoost=$bassBoostResult), so the bypass assertions below would be vacuous",
            stagesBeforeBypass >= 1
        )

        // Bypass on: a stream called bit-perfect may not pass an app-owned
        // effect, so the live count must drop to zero.
        val bypassResult = invoke("setBypassDspForBitPerfect", mapOf("bypass" to true))
        assertTrue(
            "Bit-perfect bypass must be accepted with the native engine loaded: $bypassResult",
            bypassResult == true
        )
        val bypassedReport = dspDebugStatus()
        assertEquals(
            "Bit-perfect bypass must suppress every app-owned HAL stage",
            0,
            halStagesActive(bypassedReport)
        )
        assertTrue(
            "Bit-perfect bypass must still be requested",
            bypassedReport["isBitPerfectRequested"] == true
        )

        // Session swap while bypassed: recreateEffects() must not rebuild the
        // stages the user's flags still describe.
        invoke("setAudioSessionId", mapOf("audioSessionId" to 202))
        assertEquals(
            "A session swap during bypass must not re-enable a single HAL stage",
            0,
            halStagesActive(dspDebugStatus())
        )

        // Bypass off: the restore path must honour the untouched user flags.
        val restoreResult = invoke("setBypassDspForBitPerfect", mapOf("bypass" to false))
        assertTrue(
            "Leaving bit-perfect must be accepted: $restoreResult",
            restoreResult == true
        )
        val restoredReport = dspDebugStatus()
        assertTrue(
            "Leaving the bypass must clear the request",
            restoredReport["isBitPerfectRequested"] == false
        )
        assertTrue(
            "Leaving the bypass must restore the app-owned HAL stages the user enabled",
            halStagesActive(restoredReport) >= 1
        )

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testRouteChangesAndFormatResync() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 110))

        // Simulate 44.1 kHz track
        val resync44 = invoke("resyncForTrack", mapOf("sampleRate" to 44100.0, "channels" to 2))
        assertNotNull(resync44)
        val status44 = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(status44)
        val isNative44 = status44?.get("isNativeDspLoaded") as? Boolean ?: false
        if (isNative44) {
            assertEquals(44100.0, (status44?.get("appliedSampleRate") as? Number)?.toDouble() ?: 0.0, 0.5)
        }

        // Simulate route change to Hi-Res USB DAC at 96 kHz
        val resync96 = invoke("resyncForTrack", mapOf("sampleRate" to 96000.0, "channels" to 2))
        assertNotNull(resync96)
        val status96 = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(status96)
        val isNative96 = status96?.get("isNativeDspLoaded") as? Boolean ?: false
        if (isNative96) {
            assertEquals(96000.0, (status96?.get("appliedSampleRate") as? Number)?.toDouble() ?: 0.0, 0.5)
        }

        // Simulate route fallback back to 48 kHz
        val resync48 = invoke("resyncForTrack", mapOf("sampleRate" to 48000.0, "channels" to 2))
        assertNotNull(resync48)
        val status48 = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(status48)
        val isNative48 = status48?.get("isNativeDspLoaded") as? Boolean ?: false
        if (isNative48) {
            assertEquals(48000.0, (status48?.get("appliedSampleRate") as? Number)?.toDouble() ?: 0.0, 0.5)
        }

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testBluetoothDisconnectAndReconnect() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 115))

        // Headphone crossfeed on Bluetooth route
        invoke("setCrossfeedMode", mapOf("mode" to "headphone"))
        invoke("setCrossfeedEnabled", mapOf("enabled" to true))
        val statusBt1 = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(statusBt1)
        @Suppress("UNCHECKED_CAST")
        val stagesBt1 = statusBt1?.get("stages") as? List<Map<String, Any?>>
        val cfStage1 = stagesBt1?.firstOrNull { it["name"] == "Bauer Binaural Crossfeed" }
        assertEquals(true, cfStage1?.get("isEnabled"))

        // Route change to speaker
        invoke("setCrossfeedMode", mapOf("mode" to "speaker"))
        val statusSpeaker = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(statusSpeaker)

        // Reconnect Bluetooth
        invoke("setCrossfeedMode", mapOf("mode" to "headphone"))
        val crossfeedResult = invoke("setCrossfeedEnabled", mapOf("enabled" to true))
        assertNotNull(crossfeedResult)
        val statusBt2 = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(statusBt2)
        @Suppress("UNCHECKED_CAST")
        val stagesBt2 = statusBt2?.get("stages") as? List<Map<String, Any?>>
        val cfStage2 = stagesBt2?.firstOrNull { it["name"] == "Bauer Binaural Crossfeed" }
        assertEquals(true, cfStage2?.get("isEnabled"))

        // Clean tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }

    @Test
    fun testUsbDacConnectAndDisconnect() {
        invoke("setAudioSessionId", mapOf("audioSessionId" to 120))

        // USB DAC connect: 192 kHz direct format resync
        val usbConnect = invoke("resyncForTrack", mapOf("sampleRate" to 192000.0, "channels" to 2))
        assertNotNull(usbConnect)
        val statusUsb = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(statusUsb)
        val isNativeUsb = statusUsb?.get("isNativeDspLoaded") as? Boolean ?: false
        if (isNativeUsb) {
            assertEquals(192000.0, (statusUsb?.get("appliedSampleRate") as? Number)?.toDouble() ?: 0.0, 0.5)
        }

        // USB DAC disconnect: fallback to built-in speaker at 48 kHz
        val usbDisconnect = invoke("resyncForTrack", mapOf("sampleRate" to 48000.0, "channels" to 2))
        assertNotNull(usbDisconnect)
        val statusSpeaker = invoke("getDspDebugStatus") as? Map<*, *>
        assertNotNull(statusSpeaker)
        val isNativeSpeaker = statusSpeaker?.get("isNativeDspLoaded") as? Boolean ?: false
        if (isNativeSpeaker) {
            assertEquals(48000.0, (statusSpeaker?.get("appliedSampleRate") as? Number)?.toDouble() ?: 0.0, 0.5)
        }

        // Tear down
        invoke("setAudioSessionId", mapOf("audioSessionId" to 0))
    }
}
