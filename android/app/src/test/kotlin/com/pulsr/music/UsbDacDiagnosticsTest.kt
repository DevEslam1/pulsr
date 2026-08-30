package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Phase 4 (P4-1): pure-logic tests for UsbDacDiagnostics.
 *
 * Descriptor fixtures are hand-built USB standard interface descriptors:
 *   [bLength][bDescriptorType][bInterfaceNumber][bAlternateSetting]
 *   [bNumEndpoints][bInterfaceClass][bInterfaceSubClass][bInterfaceProtocol]
 */
class UsbDacDiagnosticsTest {

    private fun interfaceDescriptor(
        cls: Int,
        subclass: Int,
        protocol: Int,
        extra: ByteArray = ByteArray(0),
    ): ByteArray {
        val body = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, cls.toByte(), subclass.toByte(), protocol.toByte(), 0,
        ) + extra
        body[0] = body.size.toByte() // bLength covers optional extra bytes
        return body
    }

    @Test
    fun testUac2ControlInterfaceIsDetected() {
        val descriptors = interfaceDescriptor(0x01, 0x01, 0x20)
        assertEquals(UsbDacDiagnostics.UAC2, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testUac1ControlInterfaceIsDetected() {
        val descriptors = interfaceDescriptor(0x01, 0x01, 0x00)
        assertEquals(UsbDacDiagnostics.UAC1, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testUac3ControlInterfaceIsDetected() {
        val descriptors = interfaceDescriptor(0x01, 0x01, 0x30)
        assertEquals(UsbDacDiagnostics.UAC3, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testHighestVersionWinsWhenMultipleControlInterfaces() {
        val descriptors = interfaceDescriptor(0x01, 0x01, 0x00) +
            interfaceDescriptor(0x01, 0x01, 0x20)
        assertEquals(UsbDacDiagnostics.UAC2, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testNonAudioInterfaceIsIgnored() {
        // HID interface (class 0x03) must not be reported as audio
        val descriptors = interfaceDescriptor(0x03, 0x00, 0x00)
        assertEquals(UsbDacDiagnostics.UAC_NONE, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testAudioStreamingInterfaceAloneIsNotEnough() {
        // AS interface (subclass 0x02) without an AC interface: no version claim
        val descriptors = interfaceDescriptor(0x01, 0x02, 0x20)
        assertEquals(UsbDacDiagnostics.UAC_NONE, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testMalformedDescriptorsResyncWithoutThrowing() {
        val garbage = byteArrayOf(0, 0, 0, 0, 0, 0, 0, 0)
        val descriptors = garbage + interfaceDescriptor(0x01, 0x01, 0x20)
        assertEquals(UsbDacDiagnostics.UAC2, UsbDacDiagnostics.uacVersionFromDescriptors(descriptors))
    }

    @Test
    fun testNullAndShortInputsReturnNone() {
        assertEquals(UsbDacDiagnostics.UAC_NONE, UsbDacDiagnostics.uacVersionFromDescriptors(null))
        assertEquals(UsbDacDiagnostics.UAC_NONE, UsbDacDiagnostics.uacVersionFromDescriptors(ByteArray(4)))
    }

    @Test
    fun testInterfaceProtocolPathDetectsUac2() {
        val uac = UsbDacDiagnostics.uacVersionFromUsbInterfaces(
            listOf(Pair(0x01, 0x20), Pair(0x02, 0x20), Pair(0x03, 0x00))
        )
        assertEquals(UsbDacDiagnostics.UAC2, uac)
    }

    @Test
    fun testInterfaceProtocolPathRequiresControlSubclass() {
        // streaming interface (0x02) with UAC2 protocol but no control interface
        val uac = UsbDacDiagnostics.uacVersionFromUsbInterfaces(listOf(Pair(0x02, 0x20)))
        assertEquals(UsbDacDiagnostics.UAC_NONE, uac)
    }

    @Test
    fun testInterfaceProtocolPathHighestVersionWins() {
        val uac = UsbDacDiagnostics.uacVersionFromUsbInterfaces(
            listOf(Pair(0x01, 0x00), Pair(0x01, 0x30))
        )
        assertEquals(UsbDacDiagnostics.UAC3, uac)
    }

    @Test
    fun testInterfaceProtocolPathEmptyListIsNone() {
        assertEquals(UsbDacDiagnostics.UAC_NONE, UsbDacDiagnostics.uacVersionFromUsbInterfaces(emptyList()))
    }

    @Test
    fun testUacLabels() {
        assertEquals("UAC1", UsbDacDiagnostics.uacLabel(UsbDacDiagnostics.UAC1))
        assertEquals("UAC2", UsbDacDiagnostics.uacLabel(UsbDacDiagnostics.UAC2))
        assertEquals("UAC3", UsbDacDiagnostics.uacLabel(UsbDacDiagnostics.UAC3))
        assertEquals("none", UsbDacDiagnostics.uacLabel(UsbDacDiagnostics.UAC_NONE))
    }

    @Test
    fun testDirectFormatsProbeMatrixShapeAndNullHandling() {
        val results = UsbDacDiagnostics.directFormatsFor { tag, rate ->
            when (tag) {
                "float" -> rate >= 96000
                "24" -> true
                else -> null // unknown -> reported as not supported
            }
        }
        assertEquals(UsbDacDiagnostics.PROBE_TAGS.size, results.size)
        val float96 = results.first { it["encoding"] == "float" && it["sampleRate"] == 96000 }
        assertEquals(true, float96["supported"])
        val float48 = results.first { it["encoding"] == "float" && it["sampleRate"] == 48000 }
        assertEquals(false, float48["supported"])
        val tag32 = results.first { it["encoding"] == "32" }
        assertEquals(false, tag32["supported"]) // null probe -> false, never true
        assertTrue(results.all { it["supported"] is Boolean })
        assertFalse(results.any { it["supported"] == null })
    }
}