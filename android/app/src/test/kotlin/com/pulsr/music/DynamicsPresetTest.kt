package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DynamicsPresetTest {

    @Test
    fun testAllDynamicsPresetsAreValid() {
        val presets = AudioEffectsPlugin.DYNAMICS_PRESETS
        assertTrue("Presets should not be empty", presets.isNotEmpty())

        val expectedPresets = listOf(
            "studioPunch",
            "warmAnalog",
            "vocalFocus",
            "nightLeveller",
            "bassTightener"
        )

        for (name in expectedPresets) {
            val preset = presets[name]
            assertTrue("Preset $name should exist", preset != null)
            val errors = AudioEffectsPlugin.validateDynamicsPreset(preset!!)
            assertEquals("Preset $name should have zero validation errors: $errors", 0, errors.size)
        }

        // Also test every preset currently registered in DYNAMICS_PRESETS
        for ((name, preset) in presets) {
            val errors = AudioEffectsPlugin.validateDynamicsPreset(preset)
            assertEquals("Registered preset $name should have zero validation errors: $errors", 0, errors.size)
        }
    }
}
