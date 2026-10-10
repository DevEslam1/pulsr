package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsbAudioControlParserTest {

    private fun uac2Config(): ByteArray = byteArrayOf(
        // Audio Control interface (class 0x01 / subclass 0x01 / protocol 0x20)
        9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
        // Feature Unit (subtype 0x06), unitId 3, source 2, controlSize 2,
        // master + 2 channels each advertising Volume (0x02) + Mute (0x01).
        12, 0x24, 0x06, 0x03, 0x02, 0x02,
        0x03, 0x00,
        0x03, 0x00,
        0x03, 0x00,
        // AudioStreaming interface #1
        9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x20, 0x00,
        // Isochronous OUT endpoint (addr 0x01, attrs 0x01, max packet 0x0040)
        7, 0x05, 0x01, 0x01, 0x40, 0x00, 0x01,
    )

    @Test
    fun parsesIsochronousOutEndpoint() {
        val result = UsbAudioControlParser.parse(uac2Config())
        val ep = result.streamingEndpoint
        assertNotNull(ep)
        assertEquals(0x01, ep!!.address)
        assertEquals(1, ep.interfaceNumber)
        assertEquals(0, ep.altSetting)
        assertEquals(0x40, ep.maxPacketSize)
    }

    @Test
    fun parsesUac2FeatureUnitVolume() {
        val result = UsbAudioControlParser.parse(uac2Config())
        assertEquals(UsbAudioControlParser.UAC2, result.uacVersion)
        assertTrue(result.hasVolumeControl)
        val vu = result.volumeUnit
        assertNotNull(vu)
        assertEquals(3, vu!!.unitId)
        assertEquals(0, vu.interfaceNumber)
        assertEquals(2, vu.channels)
        assertTrue(vu.volumeOnMaster)
        assertEquals(1, result.streamingInterface)
    }

    @Test
    fun parsesUac1Protocol() {
        val data = uac2Config()
        data[7] = 0x00 // Audio Control protocol -> UAC1
        val result = UsbAudioControlParser.parse(data)
        assertEquals(UsbAudioControlParser.UAC1, result.uacVersion)
    }

    @Test
    fun noFeatureUnitWhenVolumeBitAbsent() {
        val data = uac2Config()
        // Clear the Volume bit, keep Mute (0x01) in every control bitmap.
        // FU control bitmaps start at index 15 (master), 17 (ch1), 19 (ch2).
        for (offset in intArrayOf(15, 17, 19)) {
            data[offset] = 0x01
            data[offset + 1] = 0x00
        }
        val result = UsbAudioControlParser.parse(data)
        assertNull(result.volumeUnit)
    }

    @Test
    fun parsesAsyncFeedbackEndpoint() {
        val configWithFeedback = byteArrayOf(
            // Audio Control interface
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // AudioStreaming interface #1
            9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x20, 0x00,
            // Isochronous OUT endpoint (addr 0x01, attrs 0x05 = Asynchronous Isochronous OUT)
            7, 0x05, 0x01, 0x05, 0x40, 0x00, 0x01,
            // Isochronous IN feedback endpoint (addr 0x81, attrs 0x11 = Feedback Isochronous IN)
            7, 0x05, 0x81.toByte(), 0x11, 0x04, 0x00, 0x01,
        )
        val result = UsbAudioControlParser.parse(configWithFeedback)
        assertNotNull(result.streamingEndpoint)
        assertEquals(0x01, result.streamingEndpoint!!.address)
        assertTrue(result.hasFeedbackEndpoint)
        assertNotNull(result.feedbackEndpoint)
        assertEquals(0x81, result.feedbackEndpoint!!.address)
        assertEquals(4, result.feedbackEndpoint!!.maxPacketSize)
    }

    @Test
    fun malformedDescriptorsDoNotThrow() {
        assertNull(UsbAudioControlParser.parse(null).volumeUnit)
        assertEquals(0, UsbAudioControlParser.parse(ByteArray(0)).uacVersion)
        assertEquals(
            0,
            UsbAudioControlParser.parse(byteArrayOf(0xFF.toByte(), 0x24, 0x06)).uacVersion,
        )
    }

    @Test
    fun fuzzedDescriptorsNeverCrashParser() {
        // Zero-length chunk loop-guard
        val zeroLengthChunk = byteArrayOf(0x00, 0x01, 0x02, 0x03)
        val r0 = UsbAudioControlParser.parse(zeroLengthChunk)
        assertEquals(0, r0.uacVersion)

        // Oversized length claims (buffer overrun defense)
        val oversizedLength = byteArrayOf(120, 0x04, 0x00, 0x00)
        val r1 = UsbAudioControlParser.parse(oversizedLength)
        assertNull(r1.volumeUnit)

        // Truncated endpoint descriptors
        val truncatedEp = byteArrayOf(
            9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x20, 0x00,
            3, 0x05, 0x01 // says length is 3, endpoint expects 7
        )
        val r2 = UsbAudioControlParser.parse(truncatedEp)
        assertNull(r2.streamingEndpoint)

        // Pseudo-random fuzzed byte arrays
        val random = java.util.Random(1337)
        for (i in 0 until 100) {
            val length = random.nextInt(128)
            val bytes = ByteArray(length)
            random.nextBytes(bytes)
            val res = UsbAudioControlParser.parse(bytes)
            assertNotNull(res) // Must gracefully return a result object without uncaught exception
        }
    }

    @Test
    fun parsesFormatTypeIII() {
        val configWithFormatTypeIII = byteArrayOf(
            // AudioStreaming interface #1
            9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00,
            // Class-specific AS interface descriptor: FORMAT_TYPE (0x02), formatType = 0x03 (Type III IEC61937),
            // bNrChannels = 2, bSubFrameSize = 2, bBitResolution = 16, bSamFreqType = 1 (discrete frequency)
            11, 0x24, 0x02, 0x03, 0x02, 0x02, 0x10, 0x01,
            // 48000 Hz = 0x00BB80 -> 0x80, 0xBB, 0x00
            0x80.toByte(), 0xBB.toByte(), 0x00,
        )
        val result = UsbAudioControlParser.parse(configWithFormatTypeIII)
        assertEquals(listOf(48000), result.supportedRates)
    }

    /**
     * A multi-alt UAC2 DAC: AudioControl interface + programmable Clock Source,
     * then two AudioStreaming alt settings (alt 1 = 32-bit/4-byte subslot with an
     * async feedback IN endpoint, alt 2 = 24-bit/3-byte subslot). Exercises clock
     * tracking (FIX 1) and per-alt FORMAT_TYPE_I enumeration (FIX 3).
     */
    private fun uac2MultiAltConfig(clockControls: Int = 0x03): ByteArray = byteArrayOf(
        // AudioControl interface #0 (class 0x01 / subclass 0x01 / protocol 0x20 = UAC2)
        9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
        // UAC2 Clock Source: subtype 0x0B, bClockID 5, bmAttributes 0x03,
        // bmControls (freq control), bAssocTerminal 0, iClockSource 0.
        8, 0x24, 0x0B, 0x05, 0x03, clockControls.toByte(), 0x00, 0x00,
        // AudioStreaming interface #1 alt 0 (zero-bandwidth, no endpoint)
        9, 0x04, 0x01, 0x00, 0x00, 0x01, 0x02, 0x20, 0x00,
        // AudioStreaming interface #1 alt 1 (1 endpoint)
        9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
        // UAC2 AS_GENERAL (subtype 0x01), bNrChannels (index 10) = 2
        16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        // UAC2 FORMAT_TYPE_I (6 bytes): bSubslotSize 4, bBitResolution 32
        6, 0x24, 0x02, 0x01, 0x04, 0x20,
        // Iso OUT endpoint 0x01, attrs 0x05 (async), wMaxPacketSize 0x0400
        7, 0x05, 0x01, 0x05, 0x00, 0x04, 0x01,
        // Iso IN feedback endpoint 0x81, attrs 0x11 (feedback usage), maxPacket 4
        7, 0x05, 0x81.toByte(), 0x11, 0x04, 0x00, 0x01,
        // AudioStreaming interface #1 alt 2 (1 endpoint)
        9, 0x04, 0x01, 0x02, 0x01, 0x01, 0x02, 0x20, 0x00,
        // UAC2 AS_GENERAL, bNrChannels = 2
        16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        // UAC2 FORMAT_TYPE_I: bSubslotSize 3, bBitResolution 24 (0x18)
        6, 0x24, 0x02, 0x01, 0x03, 0x18,
        // Iso OUT endpoint 0x01, attrs 0x05, wMaxPacketSize 0x0300
        7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
    )

    @Test
    fun parsesUac2ClockSource() {
        val result = UsbAudioControlParser.parse(uac2MultiAltConfig())
        assertEquals(UsbAudioControlParser.UAC2, result.uacVersion)
        val clock = result.clockSource
        assertNotNull(clock)
        assertEquals(5, clock!!.clockId)
        assertEquals(0, clock.controlInterface) // AudioControl interface number
        assertTrue(clock.frequencyProgrammable) // bmControls 0x03 = read/write
    }

    @Test
    fun clockSourceReadOnlyIsNotProgrammable() {
        // bmControls 0x01 = Clock Frequency Control read-only (single fixed rate).
        val result = UsbAudioControlParser.parse(uac2MultiAltConfig(clockControls = 0x01))
        val clock = result.clockSource
        assertNotNull(clock)
        assertFalse(clock!!.frequencyProgrammable)
    }

    @Test
    fun enumeratesPerAltSettingFormats() {
        val result = UsbAudioControlParser.parse(uac2MultiAltConfig())
        val formats = result.altSettingFormats
        // Alt 0 is zero-bandwidth (no endpoint/format) and must NOT appear.
        assertEquals(2, formats.size)

        val alt1 = formats.first { it.altSetting == 1 }
        assertEquals(1, alt1.interfaceNumber)
        assertEquals(0x01, alt1.endpointAddress)
        assertEquals(4, alt1.subslotSize) // 32-bit container
        assertEquals(32, alt1.bitResolution)
        assertEquals(2, alt1.channels)
        assertEquals(0x0400, alt1.maxPacketSize)
        assertEquals(0x81, alt1.feedbackEndpointAddress) // async feedback IN
        assertTrue(alt1.supportedRates.isEmpty()) // UAC2 rates come from the clock

        val alt2 = formats.first { it.altSetting == 2 }
        assertEquals(3, alt2.subslotSize) // 24-bit packed
        assertEquals(24, alt2.bitResolution)
        assertNull(alt2.feedbackEndpointAddress)
    }

    @Test
    fun uac1FormatTypeIReportsSubslotAndBitResolution() {
        // UAC1 FORMAT_TYPE_I (protocol 0x00): bNrChannels 2, bSubframeSize 3,
        // bBitResolution 24, bSamFreqType 1, 96000 Hz.
        val uac1 = byteArrayOf(
            // AudioStreaming interface #2 alt 1
            9, 0x04, 0x02, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00,
            // UAC1 FORMAT_TYPE_I: subframe 3 (24-bit packed), 1 discrete rate
            11, 0x24, 0x02, 0x01, 0x02, 0x03, 0x18, 0x01,
            // 96000 Hz = 0x017700 -> 0x00, 0x77, 0x01
            0x00, 0x77, 0x01,
            // Iso OUT endpoint 0x02, attrs 0x09 (iso adaptive), maxPacket 0x0120
            7, 0x05, 0x02, 0x09, 0x20, 0x01, 0x01,
        )
        val result = UsbAudioControlParser.parse(uac1)
        val fmt = result.altSettingFormats.single()
        assertEquals(2, fmt.interfaceNumber)
        assertEquals(1, fmt.altSetting)
        assertEquals(0x02, fmt.endpointAddress)
        assertEquals(3, fmt.subslotSize)
        assertEquals(24, fmt.bitResolution)
        assertEquals(2, fmt.channels)
        assertEquals(listOf(96000), fmt.supportedRates)
    }
}
