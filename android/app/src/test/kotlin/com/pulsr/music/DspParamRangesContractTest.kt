package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Item 4 regression: the Kotlin range table must be numerically identical to the
 * Dart contract (`lib/data/audio/dsp_param_ranges.dart`).
 *
 * The Dart file is parsed as text on purpose: a hand-maintained duplicate in the
 * test would drift exactly like the production copies did. Every entry the
 * Kotlin object exposes must have a Dart twin with the same min/max/default, and
 * every shared Dart range that this object mirrors must be present.
 */
class DspParamRangesContractTest {

    @Test
    fun kotlinTableEqualsTheDartContract() {
        val dart = parseDartRanges(dartSource())
        assertTrue("parsed no DspRange entries from the Dart contract", dart.size >= 30)

        for ((name, range) in DspParamRanges.shared) {
            val expected = dart[name]
            if (expected == null) {
                fail("Dart DspParamRanges has no `$name` entry")
                return
            }
            assertEquals("$name.min", expected[0], range.min, 0.0)
            assertEquals("$name.max", expected[1], range.max, 0.0)
            assertEquals("$name.defaultValue", expected[2], range.defaultValue, 0.0)
        }

        // Coverage: the contract items this change introduced must be mirrored.
        val required = listOf(
            "dynamicEqQ",
            "dynamicEqMaxCutDb",
            "dynamicEqMaxBoostDb",
            "multibandKneeDb",
            "multibandMakeupGainDb",
            "safetyDoseThreshold",
            "safetyCeilingDb",
            "directUsbGain",
            "limiterThresholdDb",
            "limiterReleaseMs",
        )
        for (name in required) {
            assertTrue("Kotlin DspParamRanges is missing `$name`", DspParamRanges.shared.containsKey(name))
            assertTrue("Dart DspParamRanges is missing `$name`", dart.containsKey(name))
        }
    }

    @Test
    fun ditherDepthIsTheDiscreteSetTheEngineSupports() {
        assertEquals(listOf(16, 24, 32), DspParamRanges.ditherBitDepths.toList())
        assertEquals(16, DspParamRanges.normalizeDitherBitDepth(20))
        assertEquals(16, DspParamRanges.normalizeDitherBitDepth(0))
        assertEquals(16, DspParamRanges.normalizeDitherBitDepth(16))
        assertEquals(24, DspParamRanges.normalizeDitherBitDepth(24))
        assertEquals(32, DspParamRanges.normalizeDitherBitDepth(32))
    }

    private fun dartSource(): String {
        // Gradle runs JVM tests with the module directory (android/app) as cwd.
        val candidates = listOf(
            "../../lib/data/audio/dsp_param_ranges.dart",
            "../lib/data/audio/dsp_param_ranges.dart",
            "lib/data/audio/dsp_param_ranges.dart",
        )
        for (candidate in candidates) {
            val file = File(candidate)
            if (file.isFile) return file.readText()
        }
        fail("dsp_param_ranges.dart not found from ${File(".").absolutePath}")
        error("unreachable")
    }

    private fun parseDartRanges(source: String): Map<String, DoubleArray> {
        // static const DspRange <name> = DspRange(<min>, <max>[, defaultValue: <d>]);
        // Entries may wrap across lines, so the pattern runs with DOTALL.
        val pattern = Regex(
            """static\s+const\s+DspRange\s+(\w+)\s*=\s*DspRange\(\s*""" +
                """(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)""" +
                """(?:\s*,\s*defaultValue:\s*(-?\d+(?:\.\d+)?))?\s*,?\s*\)""",
            setOf(RegexOption.DOT_MATCHES_ALL),
        )
        val out = mutableMapOf<String, DoubleArray>()
        for (match in pattern.findAll(source)) {
            val min = match.groupValues[2].toDouble()
            val max = match.groupValues[3].toDouble()
            val default = match.groupValues[4].takeIf { it.isNotEmpty() }?.toDouble() ?: 0.0
            out[match.groupValues[1]] = doubleArrayOf(min, max, default)
        }
        return out
    }
}
