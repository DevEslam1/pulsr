package com.pulsr.music

import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Item 6 regression: `detect()` used to write the status ONLY when no bundle was
 * found, so a BYPASSED verdict from an earlier pass survived every later
 * re-detection (reboot, OEM effect switched back on, effects released). The
 * verdict must be recomputed whenever detection reports bundles, and BYPASSED
 * may only be inferred from effects this controller actually holds.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class SystemAudioEffectsControllerTest {

    private class FakeHandle(override var enabled: Boolean) :
        SystemAudioEffectsController.ManagedEffectHandle {
        var released = false
        override fun hasControl(): Boolean = true
        override fun release() {
            released = true
        }
    }

    @Test
    fun detectionWithNoHeldEffectReportsActiveInsteadOfStaleBypassed() {
        val controller = SystemAudioEffectsController(RuntimeEnvironment.getApplication())
        val bundle = "Dolby Atmos (Dolby)"

        // A live silenced effect: detection keeps the honest BYPASSED verdict.
        controller.registerManagedEffectForTesting(FakeHandle(enabled = false), priorEnabled = true)
        assertEquals(
            SystemAudioEffectsController.Status.BYPASSED,
            controller.applyDetectionResultForTesting(listOf(bundle)),
        )

        // Releasing restores the OEM state. Detection must now say ACTIVE, not keep
        // the stale BYPASSED that the old code could never overwrite.
        controller.release()
        assertEquals(
            SystemAudioEffectsController.Status.ACTIVE,
            controller.applyDetectionResultForTesting(listOf(bundle)),
        )

        // And a non-empty detection must never report BYPASSED on its own.
        val status = controller.applyDetectionResultForTesting(listOf(bundle))
        assertEquals(SystemAudioEffectsController.Status.ACTIVE, status)
    }

    @Test
    fun detectionWithoutBundlesReportsUnsupportedDevice() {
        val controller = SystemAudioEffectsController(RuntimeEnvironment.getApplication())
        assertEquals(
            SystemAudioEffectsController.Status.UNSUPPORTED_DEVICE,
            controller.applyDetectionResultForTesting(emptyList()),
        )
    }

    @Test
    fun realDetectionNeverClaimsBypassedWithoutHoldingAnEffect() {
        val controller = SystemAudioEffectsController(RuntimeEnvironment.getApplication())
        // Robolectric's AudioEffect.queryEffects() returns no descriptors, so this is
        // the honest "unsupported" path; the point is that detect() runs the verdict
        // (it used to leave the previous status untouched when bundles were seen).
        val report = controller.detect()
        val status = SystemAudioEffectsController.Status.fromString(report["status"] as String)
        assertEquals(SystemAudioEffectsController.Status.UNSUPPORTED_DEVICE, status)
        assertEquals(false, report["hasDolbyOrVendor"])
    }
}
