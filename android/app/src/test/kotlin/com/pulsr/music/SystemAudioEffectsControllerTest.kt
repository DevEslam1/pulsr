package com.pulsr.music

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemAudioEffectsControllerTest {

    @Test
    fun testStatusEnumValues() {
        assertEquals("bypassed", SystemAudioEffectsController.Status.BYPASSED.value)
        assertEquals("active", SystemAudioEffectsController.Status.ACTIVE.value)
        assertEquals("unknown", SystemAudioEffectsController.Status.UNKNOWN.value)
        assertEquals("unsupportedDevice", SystemAudioEffectsController.Status.UNSUPPORTED_DEVICE.value)

        assertEquals(SystemAudioEffectsController.Status.BYPASSED, SystemAudioEffectsController.Status.fromString("bypassed"))
        assertEquals(SystemAudioEffectsController.Status.ACTIVE, SystemAudioEffectsController.Status.fromString("active"))
        assertEquals(SystemAudioEffectsController.Status.UNKNOWN, SystemAudioEffectsController.Status.fromString("unknown"))
        assertEquals(SystemAudioEffectsController.Status.UNSUPPORTED_DEVICE, SystemAudioEffectsController.Status.fromString("unsupportedDevice"))
    }

    @Test
    fun testPolicyEnumValues() {
        assertEquals("auto", SystemAudioEffectsController.Policy.AUTO.value)
        assertEquals("tryDisable", SystemAudioEffectsController.Policy.TRY_DISABLE.value)
        assertEquals("leaveOn", SystemAudioEffectsController.Policy.LEAVE_ON.value)

        assertEquals(SystemAudioEffectsController.Policy.AUTO, SystemAudioEffectsController.Policy.fromString("auto"))
        assertEquals(SystemAudioEffectsController.Policy.TRY_DISABLE, SystemAudioEffectsController.Policy.fromString("tryDisable"))
        assertEquals(SystemAudioEffectsController.Policy.LEAVE_ON, SystemAudioEffectsController.Policy.fromString("leaveOn"))
    }

    @Test
    fun testKnownVendorEffectsList() {
        val effects = SystemAudioEffectsController.KNOWN_VENDOR_EFFECTS
        assertTrue("Known vendor effects must contain Dolby signatures", effects.any { it.keyword == "dolby" })
        assertTrue("Known vendor effects must contain Dirac signature", effects.any { it.keyword == "dirac" })
        assertTrue("Known vendor effects must contain SoundAlive signature", effects.any { it.keyword == "soundalive" })
    }
}
