package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Validation, defaults and bit-perfect reporting of [UsbQuirkResolver].
 *
 * The resolver is the only place a per-device profile turns into stream
 * parameters, so every rule gets a table entry: an unknown key, a wrong type, a
 * value one past a range and every boundary value are all pinned here.
 */
class UsbQuirkResolverTest {

    private fun facts(
        vid: Int = 0x2972,
        pid: Int = 0x00A1,
        uacVersion: Int = 2,
        supportedRates: List<Int> = listOf(44_100, 48_000, 88_200, 96_000, 192_000),
        requestedRate: Int = 96_000,
        requestedDepth: Int = 24,
        requestedChannels: Int = 2,
        feedbackPresent: Boolean = true,
    ) = UsbDeviceFacts(
        vid = vid,
        pid = pid,
        uacVersion = uacVersion,
        supportedRates = supportedRates,
        requestedRate = requestedRate,
        requestedDepth = requestedDepth,
        requestedChannels = requestedChannels,
        feedbackPresent = feedbackPresent,
    )

    // --------------------------------------------------------------- defaults

    @Test
    fun unknownDeviceGetsPureDefaultsAndTheRequestedFormat() {
        val resolved = UsbQuirkResolver.resolve(emptyMap(), facts())

        assertEquals(96_000, resolved.effectiveRate)
        assertEquals(24, resolved.effectiveDepth)
        assertEquals(2, resolved.effectiveChannels)
        assertEquals(0, resolved.silenceMs)
        assertEquals(0, resolved.transferSizeBytes)
        assertEquals(0, resolved.bufferMs)
        assertFalse(resolved.disableExplicitFeedback)
        assertNull(resolved.preferredSelectorPin)
        assertFalse(resolved.altResetOnStop)
        assertFalse(resolved.uac1ReassertAfterAlt)
        assertFalse(resolved.disableUac2ClockSwitch)
        assertEquals(0.0, resolved.volumeCalibrationDb, 0.0)
        assertTrue(resolved.appliedQuirks.isEmpty())
        assertFalse(resolved.bitPerfectAffected)
        assertNull(resolved.bitPerfectReason)
        assertTrue(resolved.rejected.isEmpty())
    }

    @Test
    fun emptyProfileFromMalformedJsonBehavesLikeNoProfile() {
        val resolved = UsbQuirkResolver.resolveJson("{not json at all", facts())
        assertEquals(UsbQuirkResolver.resolve(emptyMap(), facts()), resolved)
    }

    // ------------------------------------------------------------- happy path

    @Test
    fun aFullProfileAppliesEveryQuirkInCanonicalOrder() {
        // Deliberately shuffled: appliedQuirks must not depend on map order.
        val profile = linkedMapOf<String, Any?>(
            "disableUac2ClockSwitch" to true,
            "uac1ReassertAfterAlt" to true,
            "volumeCalibrationDb" to -6.5,
            "preferredSelectorPin" to 3,
            "disableExplicitFeedback" to true,
            "bufferMs" to 50,
            "transferSizeBytes" to 1024,
            "altResetOnStop" to true,
            "force16Bit" to true,
            "silenceMs" to 250,
        )

        val resolved = UsbQuirkResolver.resolve(profile, facts())

        assertEquals(
            listOf(
                "silenceMs",
                "force16Bit",
                "altResetOnStop",
                "transferSizeBytes",
                "bufferMs",
                "disableExplicitFeedback",
                "preferredSelectorPin",
                "volumeCalibrationDb",
                "uac1ReassertAfterAlt",
                "disableUac2ClockSwitch",
            ),
            resolved.appliedQuirks,
        )
        assertEquals(250, resolved.silenceMs)
        assertEquals(1024, resolved.transferSizeBytes)
        assertEquals(50, resolved.bufferMs)
        assertTrue(resolved.disableExplicitFeedback)
        assertEquals(3, resolved.preferredSelectorPin)
        assertEquals(-6.5, resolved.volumeCalibrationDb, 0.0)
        assertTrue(resolved.altResetOnStop)
        assertTrue(resolved.uac1ReassertAfterAlt)
        assertTrue(resolved.disableUac2ClockSwitch)
        assertEquals(16, resolved.effectiveDepth)
        assertTrue(resolved.bitPerfectAffected)
        assertEquals("quirk_force_16bit", resolved.bitPerfectReason)
        assertTrue(resolved.rejected.isEmpty())
    }

    @Test
    fun defaultsAreNotReportedAsAppliedQuirks() {
        val profile = mapOf<String, Any?>(
            "silenceMs" to 0,
            "transferSizeBytes" to 0,
            "bufferMs" to 0,
            "volumeCalibrationDb" to 0.0,
            "force16Bit" to false,
            "altResetOnStop" to false,
            "disableExplicitFeedback" to false,
            "uac1ReassertAfterAlt" to false,
            "disableUac2ClockSwitch" to false,
        )
        val resolved = UsbQuirkResolver.resolve(profile, facts())
        assertTrue("explicit defaults are not quirks: ${resolved.appliedQuirks}", resolved.appliedQuirks.isEmpty())
        assertTrue(resolved.rejected.isEmpty())
        assertFalse(resolved.bitPerfectAffected)
    }

    @Test
    fun selectorPinZeroIsAMeaningfulValueNotAnAbsentOne() {
        val resolved = UsbQuirkResolver.resolve(mapOf("preferredSelectorPin" to 0), facts())
        assertEquals(0, resolved.preferredSelectorPin)
        assertEquals(listOf("preferredSelectorPin"), resolved.appliedQuirks)
    }

    // ------------------------------------------------------------- bit-perfect

    @Test
    fun force16BitOverridesDepthAndExplainsBitPerfect() {
        val resolved = UsbQuirkResolver.resolve(mapOf("force16Bit" to true), facts(requestedDepth = 24))
        assertEquals(16, resolved.effectiveDepth)
        assertEquals("the sample rate is untouched", 96_000, resolved.effectiveRate)
        assertEquals(2, resolved.effectiveChannels)
        assertTrue(resolved.bitPerfectAffected)
        assertEquals("quirk_force_16bit", resolved.bitPerfectReason)
    }

    @Test
    fun force16BitOnAnAlready16BitDeviceStillReportsTheQuirk() {
        val resolved = UsbQuirkResolver.resolve(mapOf("force16Bit" to true), facts(requestedDepth = 16))
        assertEquals(16, resolved.effectiveDepth)
        assertTrue(resolved.bitPerfectAffected)
        assertEquals("quirk_force_16bit", resolved.bitPerfectReason)
        assertEquals(listOf("force16Bit"), resolved.appliedQuirks)
    }

    @Test
    fun clockSwitchQuirkOnlyAffectsBitPerfectOnUac2() {
        val uac2 = UsbQuirkResolver.resolve(mapOf("disableUac2ClockSwitch" to true), facts(uacVersion = 2))
        assertTrue(uac2.disableUac2ClockSwitch)
        assertTrue(uac2.bitPerfectAffected)
        assertEquals("quirk_clock_switch_disabled", uac2.bitPerfectReason)
        assertEquals(24, uac2.effectiveDepth)
        assertEquals(96_000, uac2.effectiveRate)

        val uac1 = UsbQuirkResolver.resolve(mapOf("disableUac2ClockSwitch" to true), facts(uacVersion = 1))
        assertTrue("the request is still honoured", uac1.disableUac2ClockSwitch)
        assertTrue(uac1.appliedQuirks.contains("disableUac2ClockSwitch"))
        assertFalse("a UAC1 device has no UAC2 clock switch to disable", uac1.bitPerfectAffected)
        assertNull(uac1.bitPerfectReason)
    }

    @Test
    fun transportQuirksDoNotChangeSampleValuesOrBitPerfect() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf("altResetOnStop" to true, "uac1ReassertAfterAlt" to true),
            facts(requestedRate = 192_000, requestedDepth = 24, requestedChannels = 2),
        )
        assertEquals(192_000, resolved.effectiveRate)
        assertEquals(24, resolved.effectiveDepth)
        assertEquals(2, resolved.effectiveChannels)
        assertFalse(resolved.bitPerfectAffected)
        assertNull(resolved.bitPerfectReason)
        assertEquals(listOf("altResetOnStop", "uac1ReassertAfterAlt"), resolved.appliedQuirks)
    }

    @Test
    fun force16BitWinsTheReasonWhenSeveralQuirksApply() {
        // Insertion order clock-switch-first must not change the canonical result.
        val profile = linkedMapOf<String, Any?>(
            "disableUac2ClockSwitch" to true,
            "force16Bit" to true,
        )
        val resolved = UsbQuirkResolver.resolve(profile, facts(uacVersion = 2))
        assertTrue(resolved.bitPerfectAffected)
        assertEquals("quirk_force_16bit", resolved.bitPerfectReason)
        assertEquals(listOf("force16Bit", "disableUac2ClockSwitch"), resolved.appliedQuirks)
    }

    @Test
    fun volumeCalibrationIsReportedWithoutTouchingTheBitPerfectVerdict() {
        // Documented decision: the calibration is applied by the DAC/HAL path,
        // not by scaling samples, so the resolver does not claim bit-perfect is
        // broken. A digital-domain implementation must mark it itself.
        val resolved = UsbQuirkResolver.resolve(mapOf("volumeCalibrationDb" to -6.0), facts())
        assertEquals(-6.0, resolved.volumeCalibrationDb, 0.0)
        assertTrue(resolved.appliedQuirks.contains("volumeCalibrationDb"))
        assertFalse(resolved.bitPerfectAffected)
    }

    // ------------------------------------------------------------------- rate

    @Test
    fun unsupportedRateIsRejectedButTheRequestIsKept() {
        val resolved = UsbQuirkResolver.resolve(
            emptyMap(),
            facts(supportedRates = listOf(44_100, 48_000), requestedRate = 96_000),
        )
        assertEquals("unsupported_rate", resolved.rejected["rate"])
        assertEquals("the caller decides what to do, the resolver never lies", 96_000, resolved.effectiveRate)
    }

    @Test
    fun supportedRateIsAccepted() {
        val resolved = UsbQuirkResolver.resolve(
            emptyMap(),
            facts(supportedRates = listOf(44_100, 48_000, 96_000), requestedRate = 96_000),
        )
        assertNull(resolved.rejected["rate"])
        assertEquals(96_000, resolved.effectiveRate)
    }

    @Test
    fun emptySupportedRatesMeansUnknownAndNeverInventsARate() {
        val resolved = UsbQuirkResolver.resolve(
            emptyMap(),
            facts(supportedRates = emptyList(), requestedRate = 768_000),
        )
        assertNull("unknown support is not a rejection", resolved.rejected["rate"])
        assertEquals("never invent a rate the caller did not ask for", 768_000, resolved.effectiveRate)
    }

    // ------------------------------------------------------------ range table

    @Test
    fun rangeValidationTable() {
        data class Case(val key: String, val value: Any?, val expectedReason: String?, val expectApplied: Boolean = true)

        val cases = listOf(
            Case("silenceMs", -1, "out_of_range(0..2000)", expectApplied = false),
            Case("silenceMs", 2_001, "out_of_range(0..2000)", expectApplied = false),
            Case("silenceMs", 0, null, expectApplied = false),
            Case("silenceMs", 2_000, null),
            Case("transferSizeBytes", -1, "out_of_range(0|64..65536)", expectApplied = false),
            Case("transferSizeBytes", 1, "out_of_range(0|64..65536)", expectApplied = false),
            Case("transferSizeBytes", 63, "out_of_range(0|64..65536)", expectApplied = false),
            Case("transferSizeBytes", 65_537, "out_of_range(0|64..65536)", expectApplied = false),
            Case("transferSizeBytes", 0, null, expectApplied = false),
            Case("transferSizeBytes", 64, null),
            Case("transferSizeBytes", 65_536, null),
            Case("bufferMs", -1, "out_of_range(0..10000)", expectApplied = false),
            Case("bufferMs", 10_001, "out_of_range(0..10000)", expectApplied = false),
            Case("bufferMs", 0, null, expectApplied = false),
            Case("bufferMs", 10_000, null),
            Case("preferredSelectorPin", -1, "out_of_range(0..255)", expectApplied = false),
            Case("preferredSelectorPin", 256, "out_of_range(0..255)", expectApplied = false),
            Case("preferredSelectorPin", 0, null),
            Case("preferredSelectorPin", 255, null),
            Case("volumeCalibrationDb", -24.5, "out_of_range(-24..24)", expectApplied = false),
            Case("volumeCalibrationDb", 24.5, "out_of_range(-24..24)", expectApplied = false),
            Case("volumeCalibrationDb", -24.0, null),
            Case("volumeCalibrationDb", 24.0, null),
        )

        for (case in cases) {
            val resolved = UsbQuirkResolver.resolve(mapOf(case.key to case.value), facts())
            val label = "${case.key}=${case.value}"
            if (case.expectedReason == null) {
                assertNull("$label must be accepted, rejected=${resolved.rejected}", resolved.rejected[case.key])
                assertEquals("$label applied?", case.expectApplied, resolved.appliedQuirks.contains(case.key))
            } else {
                assertEquals("$label", case.expectedReason, resolved.rejected[case.key])
                assertFalse("$label must not be applied", resolved.appliedQuirks.contains(case.key))
            }
        }
    }

    @Test
    fun aRejectedValueKeepsTheDefaultForThatParameter() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf("silenceMs" to 9_999, "bufferMs" to 20, "force16Bit" to true),
            facts(),
        )
        assertEquals(0, resolved.silenceMs)
        assertEquals("valid neighbours still apply", 20, resolved.bufferMs)
        assertEquals(16, resolved.effectiveDepth)
        assertEquals("out_of_range(0..2000)", resolved.rejected["silenceMs"])
    }

    // ------------------------------------------------------------ type errors

    @Test
    fun malformedTypesAreRejectedWithReasons() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf<String, Any?>(
                "silenceMs" to "abc",
                "bufferMs" to true,
                "transferSizeBytes" to 64.5,
                "preferredSelectorPin" to "pin-1",
                "volumeCalibrationDb" to "loud",
                "force16Bit" to 1,
                "altResetOnStop" to "yes",
                "disableExplicitFeedback" to listOf(true),
            ),
            facts(),
        )

        assertEquals("not_an_integer", resolved.rejected["silenceMs"])
        assertEquals("not_an_integer", resolved.rejected["bufferMs"])
        assertEquals("not_an_integer", resolved.rejected["transferSizeBytes"])
        assertEquals("not_an_integer", resolved.rejected["preferredSelectorPin"])
        assertEquals("not_a_number", resolved.rejected["volumeCalibrationDb"])
        assertEquals("not_a_boolean", resolved.rejected["force16Bit"])
        assertEquals("not_a_boolean", resolved.rejected["altResetOnStop"])
        assertEquals("not_a_boolean", resolved.rejected["disableExplicitFeedback"])
        assertTrue("nothing malformed may apply", resolved.appliedQuirks.isEmpty())
    }

    @Test
    fun numericStringsAndIntegralDoublesAreAccepted() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf<String, Any?>(
                "silenceMs" to "150",
                "bufferMs" to 25.0,
                "volumeCalibrationDb" to "-3.5",
            ),
            facts(),
        )
        assertEquals(150, resolved.silenceMs)
        assertEquals(25, resolved.bufferMs)
        assertEquals(-3.5, resolved.volumeCalibrationDb, 0.0)
        assertTrue(resolved.rejected.isEmpty())
    }

    @Test
    fun nullValuesMeanNotConfiguredRatherThanMalformed() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf<String, Any?>("silenceMs" to null, "force16Bit" to null, "preferredSelectorPin" to null),
            facts(),
        )
        assertTrue(resolved.rejected.isEmpty())
        assertEquals(0, resolved.silenceMs)
        assertFalse(resolved.bitPerfectAffected)
        assertNull(resolved.preferredSelectorPin)
    }

    @Test
    fun unknownKeysAreRejectedAndDoNotStopValidOnes() {
        val resolved = UsbQuirkResolver.resolve(
            mapOf("magicQuirk" to true, "silenceMs" to 100, "anotherOne" to 5),
            facts(),
        )
        assertEquals("unknown_key", resolved.rejected["magicQuirk"])
        assertEquals("unknown_key", resolved.rejected["anotherOne"])
        assertEquals(100, resolved.silenceMs)
        assertEquals(listOf("silenceMs"), resolved.appliedQuirks)
    }

    // ------------------------------------------------------------------ json

    @Test
    fun fromJsonParsesScalarsNestedValuesAndEscapes() {
        val map = UsbQuirkResolver.fromJson(
            """
            {
              "silenceMs": 150,
              "force16Bit": true,
              "preferredSelectorPin": 0,
              "volumeCalibrationDb": -3.5,
              "deviceModel": "DAC \u00e9 \"pro\"",
              "nested": {"a": 1},
              "list": [1, 2],
              "nothing": null
            }
            """.trimIndent()
        )

        assertEquals(150L, map["silenceMs"])
        assertEquals(true, map["force16Bit"])
        assertEquals(0L, map["preferredSelectorPin"])
        assertEquals(-3.5, map["volumeCalibrationDb"])
        assertEquals("DAC é \"pro\"", map["deviceModel"])
        assertEquals(mapOf("a" to 1L), map["nested"])
        assertEquals(listOf(1L, 2L), map["list"])
        assertTrue(map.containsKey("nothing"))
        assertNull(map["nothing"])
        assertEquals(8, map.size)
    }

    @Test
    fun fromJsonReturnsAnEmptyMapForAnythingMalformed() {
        val malformed = listOf(
            null,
            "",
            "   ",
            "{silenceMs:150}",
            """{"silenceMs":}""",
            """{"silenceMs":150""",
            """{"silenceMs":150} trailing""",
            "[1,2,3]",
            "42",
            "\"just a string\"",
            """{"a": 1,}""",
        )
        for (raw in malformed) {
            assertTrue("expected empty map for: $raw", UsbQuirkResolver.fromJson(raw).isEmpty())
        }
    }

    @Test
    fun fromJsonAcceptsAnEmptyObject() {
        assertTrue(UsbQuirkResolver.fromJson("{}").isEmpty())
        assertTrue(UsbQuirkResolver.fromJson(" { } ").isEmpty())
    }

    @Test
    fun resolveJsonMatchesResolveOnTheParsedMap() {
        val raw = """{"silenceMs":120,"bufferMs":30,"force16Bit":true,"preferredSelectorPin":7}"""
        val fromString = UsbQuirkResolver.resolveJson(raw, facts())
        val fromMap = UsbQuirkResolver.resolve(UsbQuirkResolver.fromJson(raw), facts())
        assertEquals(fromMap, fromString)
        assertEquals(120, fromString.silenceMs)
        assertEquals(30, fromString.bufferMs)
        assertEquals(7, fromString.preferredSelectorPin)
        assertEquals(16, fromString.effectiveDepth)
    }

    @Test
    fun resolveJsonSurvivesAProfileWithTheWrongShape() {
        val arrayRoot = UsbQuirkResolver.resolveJson("[1,2,3]", facts())
        assertEquals(UsbQuirkResolver.resolve(emptyMap(), facts()), arrayRoot)

        val nestedValue = UsbQuirkResolver.resolveJson("""{"silenceMs":{"ms":100}}""", facts())
        assertEquals("not_an_integer", nestedValue.rejected["silenceMs"])
        assertEquals(0, nestedValue.silenceMs)
    }
}
