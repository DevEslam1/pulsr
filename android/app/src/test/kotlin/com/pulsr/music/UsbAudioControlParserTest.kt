package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UsbAudioControlParserTest {

    @Test
    fun streamFormatReusesAWiderWireContainerWithoutRestart() {
        val container = UsbAudioProtocol.StreamFormat(
            sampleRate = 48000,
            bitDepth = 16,
            channels = 2,
            wireBitDepth = 24,
            wireChannels = 2,
        )
        // 16-bit source opened in a 24-bit container: repeated and 24-bit tracks
        // both fit and must reuse the stream instead of restarting the endpoint.
        assertTrue(container.matches(48000, 16, 2, nativeActive = true))
        assertTrue(container.matches(48000, 24, 2, nativeActive = true))
        // A wider source or a different rate/channel layout needs a new alt.
        assertFalse(container.matches(48000, 32, 2, nativeActive = true))
        assertFalse(container.matches(44100, 16, 2, nativeActive = true))
        assertFalse(container.matches(48000, 16, 1, nativeActive = true))
        assertFalse(container.matches(48000, 16, 2, nativeActive = false))
    }

    private fun uac2Config(): ByteArray = byteArrayOf(
        // Audio Control interface (class 0x01 / subclass 0x01 / protocol 0x20)
        9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
        // UAC2: 32-bit bmaControls, writable volume in bits 3:2; trailing iFeature.
        18, 0x24, 0x06, 0x03, 0x02,
        0x0F, 0x00, 0x00, 0x00,
        0x0F, 0x00, 0x00, 0x00,
        0x0F, 0x00, 0x00, 0x00,
        0x00,
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
        assertTrue(vu.muteOnMaster)
        assertTrue(result.hasMuteControl)
        assertEquals(1, result.streamingInterface)
    }

    @Test
    fun uac2FeatureUnitSplitsMuteFromVolumeCapability() {
        // Bits 3:2 = 11 (volume RW), bits 1:0 = 00 (no mute).
        val volumeOnly = uac2Config().copyOf()
        // Master and per-channel bmaControls low bytes: 14, 18, 22.
        for (offset in intArrayOf(14, 18, 22)) volumeOnly[offset] = 0x0C
        val noMute = UsbAudioControlParser.parse(volumeOnly)
        assertTrue(noMute.hasVolumeControl)
        assertTrue(!noMute.hasMuteControl)

        // Bits 1:0 = 11 (mute RW), bits 3:2 = 00 (no volume).
        val muteOnly = uac2Config().copyOf()
        for (offset in intArrayOf(14, 18, 22)) muteOnly[offset] = 0x03
        val mute = UsbAudioControlParser.parse(muteOnly)
        assertTrue(!mute.hasVolumeControl)
        assertTrue(mute.hasMuteControl)
    }

    private fun uac1Config(): ByteArray = byteArrayOf(
        9, 0x04, 0, 0, 0, 1, 1, 0, 0,
        13, 0x24, 6, 3, 2, 2,
        3, 0, 3, 0, 3, 0, 0,
    )

    @Test
    fun parsesRealUac1FeatureUnit() {
        val result = UsbAudioControlParser.parse(uac1Config())
        assertEquals(UsbAudioControlParser.UAC1, result.uacVersion)
        assertEquals(2, result.volumeUnit!!.channels)
        assertEquals(listOf(0, 1, 2), result.volumeUnit!!.writableChannels)
        assertTrue(result.volumeUnit!!.muteOnMaster)
        assertTrue(result.hasMuteControl)
    }

    @Test
    fun uac1HighBytesAndStringIndexAreNotVolumeBits() {
        val data = uac1Config()
        for (offset in intArrayOf(15, 17, 19)) {
            data[offset] = 1
            data[offset + 1] = 2
        }
        data[21] = 2
        assertFalse(UsbAudioControlParser.parse(data).hasVolumeControl)
    }

    @Test
    fun uac2ReadOnlyAndReservedVolumeAreNotWritable() {
        for (bits in listOf(0x04, 0x08)) {
            val data = uac2Config()
            for (offset in intArrayOf(14, 18, 22)) data[offset] = bits.toByte()
            assertFalse(UsbAudioControlParser.parse(data).hasVolumeControl)
        }
    }

    @Test
    fun uac2PerChannelVolumeDoesNotInventMasterControl() {
        val data = uac2Config()
        data[14] = 0x04
        val unit = UsbAudioControlParser.parse(data).volumeUnit!!
        assertFalse(unit.volumeOnMaster)
        assertEquals(listOf(1, 2), unit.writableChannels)
        assertEquals(listOf(1, 2), unit.controlChannels)
    }

    @Test
    fun incompletePerChannelVolumeIsNotUsable() {
        val data = uac2Config()
        data[14] = 0
        data[22] = 0
        assertFalse(UsbAudioControlParser.parse(data).hasVolumeControl)
    }

    @Test
    fun shortInterfaceDescriptorDoesNotReadNextDescriptor() {
        assertNull(UsbAudioControlParser.parse(byteArrayOf(2, 4, 6, 0x24, 6, 3, 2, 0)).volumeUnit)
    }

    @Test
    fun noFeatureUnitWhenVolumeBitAbsent() {
        val data = uac2Config()
        // Keep only the UAC2 writable mute control.
        for (offset in intArrayOf(14, 18, 22)) {
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
        // UAC2 Clock Source: subtype 0x0A, bClockID 5, bmAttributes 0x03,
        // bmControls (freq control), bAssocTerminal 0, iClockSource 0.
        8, 0x24, 0x0A, 0x05, 0x03, clockControls.toByte(), 0x00, 0x00,
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
        assertTrue(fmt.sampleRateControlSupported)
    }

    @Test
    fun uac1CsEndpointDetectsMissingSampleRateControlAttribute() {
        val uac1NoFreqControl = byteArrayOf(
            // AudioStreaming interface #1 alt 1 (UAC1)
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00,
            // UAC1 FORMAT_TYPE_I: 2 channels, 3-byte subframe, 24-bit, 2 rates (48k, 96k)
            14, 0x24, 0x02, 0x01, 0x02, 0x03, 0x18, 0x02,
            0x80.toByte(), 0xBB.toByte(), 0x00,
            0x00, 0x77, 0x01,
            // Iso OUT endpoint 0x01
            7, 0x05, 0x01, 0x09, 0x20, 0x01, 0x01,
            // CS_ENDPOINT (0x25), EP_GENERAL (0x01), bmAttributes = 0x00 (no sampling freq control)
            7, 0x25, 0x01, 0x00, 0x00, 0x00, 0x00,
        )
        val result = UsbAudioControlParser.parse(uac1NoFreqControl)
        val fmt = result.altSettingFormats.single()
        assertEquals(listOf(48000, 96000), fmt.supportedRates)
        assertFalse(fmt.sampleRateControlSupported)
    }

    /**
     * A headset-shaped UAC2 configuration: the *capture* AudioStreaming
     * interface is listed first with an asynchronous isochronous IN data
     * endpoint, and playback lives on interface 2.
     */
    private fun captureFirstHeadsetConfig(): ByteArray = byteArrayOf(
        // AudioControl interface #0 (UAC2)
        9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
        // AudioStreaming interface #1 (microphone) alt 1
        9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
        6, 0x24, 0x02, 0x01, 0x02, 0x10, // FORMAT_TYPE_I: 2-byte subslot, 16 bit
        // Isochronous IN *data* endpoint 0x81, async (attrs 0x05), 256 bytes
        7, 0x05, 0x81.toByte(), 0x05, 0x00, 0x01, 0x01,
        // AudioStreaming interface #2 (DAC) alt 1
        9, 0x04, 0x02, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
        // AS_GENERAL, bTerminalLink = 5
        16, 0x24, 0x01, 0x05, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
        6, 0x24, 0x02, 0x01, 0x03, 0x18, // FORMAT_TYPE_I: 3-byte subslot, 24 bit
        // Isochronous OUT endpoint 0x02, async, 0x0300 bytes
        7, 0x05, 0x02, 0x05, 0x00, 0x03, 0x01,
        // Feedback IN endpoint 0x82, usage = feedback (attrs 0x15), 4 bytes
        7, 0x05, 0x82.toByte(), 0x15, 0x04, 0x00, 0x01,
    )

    @Test
    fun streamingInterfaceIsTheOneOwningTheIsochronousOutEndpoint() {
        val result = UsbAudioControlParser.parse(captureFirstHeadsetConfig())
        // Interface 1 (the microphone) is enumerated first and must lose.
        assertEquals(2, result.streamingInterface)
        assertEquals(0x02, result.streamingEndpoint!!.address)
        assertEquals(2, result.streamingEndpoint!!.interfaceNumber)
        // Only the playback alt setting is a streamable format.
        val fmt = result.altSettingFormats.single()
        assertEquals(2, fmt.interfaceNumber)
        assertEquals(3, fmt.subslotSize)
        assertEquals(0x82, fmt.feedbackEndpointAddress)
    }

    @Test
    fun asynchronousCaptureEndpointIsNotMistakenForFeedback() {
        val result = UsbAudioControlParser.parse(captureFirstHeadsetConfig())
        assertEquals(0x82, result.feedbackEndpoint!!.address)
        assertEquals(2, result.feedbackEndpoint!!.interfaceNumber)

        // The same capture IN endpoint with no playback stream at all must not
        // be reported as a feedback pipe.
        val captureOnly = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            6, 0x24, 0x02, 0x01, 0x02, 0x10,
            7, 0x05, 0x81.toByte(), 0x05, 0x04, 0x00, 0x01,
        )
        val micOnly = UsbAudioControlParser.parse(captureOnly)
        assertFalse(micOnly.hasFeedbackEndpoint)
        assertNull(micOnly.streamingInterface)
        assertNull(micOnly.streamingEndpoint)
    }

    /**
     * UAC2 topology: Output Terminal 3 fed by Clock Source 7 (read-only) while
     * Clock Source 6 (programmable) appears first in the descriptor order. A
     * single-clock guess would tune the wrong clock and stream at the wrong
     * rate, so the clock wired to the streaming terminal must win.
     */
    @Test
    fun clockSourceIsTheOneWiredToTheStreamingTerminal() {
        val config = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // Clock Source 6: internal programmable (bmControls 0b11).
            8, 0x24, 0x0A, 0x06, 0x03, 0x03, 0x00, 0x00,
            // Clock Source 7: external / read-only frequency control.
            8, 0x24, 0x0A, 0x07, 0x00, 0x01, 0x00, 0x00,
            // Output Terminal 3 <- source 1, clock 7.
            12, 0x24, 0x03, 0x03, 0x01, 0x03, 0x00, 0x01, 0x07, 0x00, 0x00, 0x00,
            // Playback stream, linked to terminal 3.
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(listOf(6, 7), result.clockSources.map { it.clockId })
        assertEquals(7, result.clockSource!!.clockId)
        assertFalse(result.clockSource!!.frequencyProgrammable)
    }

    @Test
    fun singleInputClockSelectorResolvesToItsSource() {
        val config = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            8, 0x24, 0x0A, 0x0A, 0x03, 0x03, 0x00, 0x00, // Clock Source 10
            8, 0x24, 0x0A, 0x0B, 0x03, 0x03, 0x00, 0x00, // Clock Source 11
            // Clock Selector 8 with a single input: Clock Source 11.
            7, 0x24, 0x0B, 0x08, 0x01, 0x0B, 0x00,
            // Output Terminal 3 clocked by the selector (bCSourceID 8).
            12, 0x24, 0x03, 0x03, 0x01, 0x03, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00,
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        // Descriptor order would give 10; the terminal wiring gives 11.
        assertEquals(11, result.clockSource!!.clockId)
    }

    @Test
    fun clockMultiplierResolvesThroughToItsSourceClock() {
        val config = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // Clock Source 10, programmable.
            8, 0x24, 0x0A, 0x0A, 0x03, 0x03, 0x00, 0x00,
            // Clock Multiplier 12 <- source 10 (subtype 0x0C).
            7, 0x24, 0x0C, 0x0C, 0x0A, 0x03, 0x00,
            // Output Terminal 3 <- source 1, clocked by the multiplier.
            12, 0x24, 0x03, 0x03, 0x01, 0x03, 0x00, 0x01, 0x0C, 0x00, 0x00, 0x00,
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(mapOf(12 to 10), result.clockMultiplierSources)
        assertEquals(3, result.playbackTerminalId)
        assertEquals(mapOf(3 to 12), result.terminalClockIds)
        assertEquals(0, result.controlInterface)
        // The frequency control lives on the source clock, not the multiplier.
        assertEquals(10, result.clockSource!!.clockId)
    }

    @Test
    fun multiInputSelectorIsExposedForRuntimePinRead() {
        val config = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // Clock Source 10 programmable, Clock Source 11 read-only.
            8, 0x24, 0x0A, 0x0A, 0x03, 0x03, 0x00, 0x00,
            8, 0x24, 0x0A, 0x0B, 0x03, 0x01, 0x00, 0x00,
            // Clock Selector 8, two input pins: 1 -> 10, 2 -> 11.
            8, 0x24, 0x0B, 0x08, 0x02, 0x0A, 0x0B, 0x00,
            // Output Terminal 3 clocked by the selector (bCSourceID 8).
            12, 0x24, 0x03, 0x03, 0x01, 0x03, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00,
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(listOf(10, 11), result.clockSelectorInputs.getValue(8))
        assertEquals(mapOf(3 to 8), result.terminalClockIds)
        assertEquals(0, result.controlInterface)
        // The selector's owning AC interface is recorded so a runtime pin write
        // can address it even when it is not `controlInterface`.
        assertEquals(mapOf(8 to 0), result.clockSelectorInterfaces)
        // Static resolution cannot read the active pin; it stays on the
        // documented single-programmable-clock guess while the runtime
        // resolver (UsbAudioProtocol.resolveActiveClock) reads the pin.
        assertEquals(10, result.clockSource!!.clockId)
    }

    @Test
    fun volumeUnitComesFromThePlaybackPathNotTheFirstFeatureUnit() {
        val config = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // Feature Unit 2 (microphone path) with writable volume, listed FIRST.
            18, 0x24, 0x06, 0x02, 0x01,
            0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00,
            // Feature Unit 4 fed by Input Terminal 5 -> the playback chain.
            18, 0x24, 0x06, 0x04, 0x05,
            0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00,
            // Input Terminal 5 = USB streaming, clocked by Clock Source 8.
            17, 0x24, 0x02, 0x05, 0x01, 0x01, 0x00, 0x08, 0x02,
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            // Clock Source 8, programmable.
            8, 0x24, 0x0A, 0x08, 0x03, 0x03, 0x00, 0x00,
            // Output Terminal 6 <- Feature Unit 4, clocked by 8.
            12, 0x24, 0x03, 0x06, 0x02, 0x03, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00,
            // Playback stream alt 1 linked to Output Terminal 6.
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x06, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(4, result.volumeUnit!!.unitId)
        assertEquals(8, result.clockSource!!.clockId)
    }

    @Test
    fun clockSourceSubtypeIsNotConfusedWithClockSelector() {
        // 0x0B is CLOCK_SELECTOR; its bClockID must never be handed to the
        // Clock-Source SET_CUR path as if it were a Clock Source.
        val withSelectorOnly = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            7, 0x24, 0x0B, 0x05, 0x01, 0x03, 0x00,
        )
        val result = UsbAudioControlParser.parse(withSelectorOnly)
        assertTrue(result.clockSources.isEmpty())
        assertNull(result.clockSource)
    }

    @Test
    fun vendorSpecificInterfacesAreOnlyAudioWhenTheyLookLikeAudio() {
        // An explicitly audio-classed streaming interface is always accepted.
        assertTrue(UsbAudioControlParser.isAudioStreamingInterface(0x01, 0x02, 0x20))
        assertTrue(UsbAudioControlParser.isAudioFunctionInterface(0x01, 0x01, 0x00))
        // A vendor-specific (0xFF) interface needs an audio subclass *and* an
        // audio protocol; the ADB/debug accessory shape must not qualify.
        assertTrue(UsbAudioControlParser.isAudioStreamingInterface(0xFF, 0x02, 0x20))
        assertFalse(UsbAudioControlParser.isAudioFunctionInterface(0xFF, 0x42, 0x01))
        assertFalse(UsbAudioControlParser.isAudioStreamingInterface(0xFF, 0x02, 0x01))
        // Subclass 0x02 alone is not audio: CDC-ACM data interfaces use it.
        assertFalse(UsbAudioControlParser.isAudioStreamingInterface(0x02, 0x02, 0x01))
        assertFalse(UsbAudioControlParser.isAudioFunctionInterface(0x03, 0x02, 0x00))
    }

    @Test
    fun parsesVendorSpecificClassDac() {
        // Vendor-specific class (0xFF) DAC declaring UAC2 protocol (0x20)
        val config = byteArrayOf(
            // Audio Control interface (class 0xFF, subclass 0x01, protocol 0x20)
            9, 0x04, 0x00, 0x00, 0x00, 0xFF.toByte(), 0x01, 0x20, 0x00,
            18, 0x24, 0x06, 0x03, 0x02,
            0x0F, 0x00, 0x00, 0x00,
            0x0F, 0x00, 0x00, 0x00,
            0x0F, 0x00, 0x00, 0x00,
            0x00,
            // AudioStreaming interface #1 (class 0xFF, subclass 0x02, protocol 0x20)
            9, 0x04, 0x01, 0x00, 0x00, 0xFF.toByte(), 0x02, 0x20, 0x00,
            // Isochronous OUT endpoint
            7, 0x05, 0x01, 0x01, 0x40, 0x00, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(UsbAudioControlParser.UAC2, result.uacVersion)
        assertNotNull(result.streamingEndpoint)
        assertEquals(0x01, result.streamingEndpoint!!.address)
        assertTrue(result.hasVolumeControl)
        assertEquals(3, result.volumeUnit!!.unitId)
    }

    @Test
    fun vendorClassNonAudioDeviceIsIgnoredWithoutPair() {
        // Vendor device with only an interface 0xFF/0x02/0x00 and no AudioControl pair
        val vendorNonAudio = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x01, 0xFF.toByte(), 0x02, 0x00, 0x00,
            7, 0x05, 0x01, 0x01, 0x40, 0x00, 0x01,
        )
        val result = UsbAudioControlParser.parse(vendorNonAudio)
        assertNull(result.streamingEndpoint)
        assertNull(result.streamingInterface)
        assertEquals(UsbAudioControlParser.UAC_NONE, result.uacVersion)
    }

    @Test
    fun hasAudioControlAndStreamingPairHandlesStandardVendorOnlyAndIncompletePairs() {
        val standardAc = UsbAudioControlParser.InterfaceSignature(0x01, 0x01, 0x20)
        val standardAs = UsbAudioControlParser.InterfaceSignature(0x01, 0x02, 0x20)
        val vendorAc = UsbAudioControlParser.InterfaceSignature(0xFF, 0x01, 0x20)
        val vendorAs = UsbAudioControlParser.InterfaceSignature(0xFF, 0x02, 0x20)
        val adbIface = UsbAudioControlParser.InterfaceSignature(0xFF, 0x42, 0x01)

        assertTrue(UsbAudioControlParser.hasAudioControlAndStreamingPair(listOf(standardAc, standardAs)))
        assertTrue(UsbAudioControlParser.hasAudioControlAndStreamingPair(listOf(vendorAc, vendorAs)))
        assertTrue(
            UsbAudioControlParser.hasAudioControlAndStreamingPair(
                listOf(vendorAc, vendorAs),
                vendorOnly = true,
            )
        )
        assertFalse(
            UsbAudioControlParser.hasAudioControlAndStreamingPair(
                listOf(standardAc, standardAs),
                vendorOnly = true,
            )
        )
        assertFalse(UsbAudioControlParser.hasAudioControlAndStreamingPair(listOf(standardAc)))
        assertFalse(UsbAudioControlParser.hasAudioControlAndStreamingPair(listOf(vendorAs)))
        assertFalse(UsbAudioControlParser.hasAudioControlAndStreamingPair(listOf(vendorAc, adbIface)))
    }

    @Test
    fun selectPreferredAudioDeviceCanRequireARealRouteMatch() {
        // Two DACs attached at once and the routed output is the only one worth
        // streaming to: with requireRouteMatch the parser must not fall back to
        // "the first qualifying device" (which could be the silent other DAC).
        val vendorDac = UsbAudioControlParser.UsbDeviceSummary(
            id = 2,
            vendorId = 0x20B1,
            productId = 0x3008,
            manufacturerName = "Acme",
            productName = "Vendor DAC",
            interfaces = listOf(
                UsbAudioControlParser.InterfaceSignature(0xFF, 0x01, 0x20),
                UsbAudioControlParser.InterfaceSignature(0xFF, 0x02, 0x20),
            ),
        )
        val standardDac = UsbAudioControlParser.UsbDeviceSummary(
            id = 3,
            vendorId = 0x1234,
            productId = 0x5678,
            manufacturerName = "FiiO",
            productName = "K11",
            interfaces = listOf(
                UsbAudioControlParser.InterfaceSignature(0x01, 0x01, 0x20),
                UsbAudioControlParser.InterfaceSignature(0x01, 0x02, 0x20),
            ),
        )
        val attached = listOf(vendorDac, standardDac)

        // Default behaviour is unchanged: the standard-audio bonus alone picks
        // the first candidate.
        assertEquals(standardDac, UsbAudioControlParser.selectPreferredAudioDevice(attached))
        // ...but that bonus is not a route match, so requiring one yields null.
        assertNull(
            UsbAudioControlParser.selectPreferredAudioDevice(attached, requireRouteMatch = true),
        )
        // A hint that matches neither device is refused the same way.
        assertNull(
            UsbAudioControlParser.selectPreferredAudioDevice(
                devices = attached,
                routeProductName = "Unrelated",
                routeAddress = "usb-0000:0000-0",
                requireRouteMatch = true,
            ),
        )
        // A route VID/PID match is enough.
        assertEquals(
            vendorDac,
            UsbAudioControlParser.selectPreferredAudioDevice(
                devices = attached,
                routeAddress = "usb-20b1:3008-0",
                requireRouteMatch = true,
            ),
        )
        // A route product-name match is enough too.
        assertEquals(
            standardDac,
            UsbAudioControlParser.selectPreferredAudioDevice(
                devices = attached,
                routeProductName = "K11",
                requireRouteMatch = true,
            ),
        )
    }

    @Test
    fun selectPreferredAudioDevicePrefersRoutedVidPidThenNameThenStandardAudio() {
        val nonAudio = UsbAudioControlParser.UsbDeviceSummary(
            id = 1,
            vendorId = 0x18D1,
            productId = 0x4EE7,
            manufacturerName = "Google",
            productName = "ADB",
            interfaces = listOf(UsbAudioControlParser.InterfaceSignature(0xFF, 0x42, 0x01)),
        )
        val vendorDac = UsbAudioControlParser.UsbDeviceSummary(
            id = 2,
            vendorId = 0x20B1,
            productId = 0x3008,
            manufacturerName = "Acme",
            productName = "Vendor DAC",
            interfaces = listOf(
                UsbAudioControlParser.InterfaceSignature(0xFF, 0x01, 0x20),
                UsbAudioControlParser.InterfaceSignature(0xFF, 0x02, 0x20),
            ),
        )
        val standardDac = UsbAudioControlParser.UsbDeviceSummary(
            id = 3,
            vendorId = 0x1234,
            productId = 0x5678,
            manufacturerName = "FiiO",
            productName = "K11",
            interfaces = listOf(
                UsbAudioControlParser.InterfaceSignature(0x01, 0x01, 0x20),
                UsbAudioControlParser.InterfaceSignature(0x01, 0x02, 0x20),
            ),
        )

        assertNull(UsbAudioControlParser.selectPreferredAudioDevice(listOf(nonAudio)))
        assertEquals(
            standardDac,
            UsbAudioControlParser.selectPreferredAudioDevice(listOf(nonAudio, vendorDac, standardDac)),
        )
        assertEquals(
            vendorDac,
            UsbAudioControlParser.selectPreferredAudioDevice(
                devices = listOf(nonAudio, standardDac, vendorDac),
                routeProductName = "K11",
                routeAddress = "usb-20b1:3008-0",
            ),
        )
        assertEquals(
            vendorDac,
            UsbAudioControlParser.selectPreferredAudioDevice(
                devices = listOf(nonAudio, standardDac, vendorDac),
                routeProductName = "Vendor DAC",
                routeAddress = null,
            ),
        )
    }

    @Test
    fun clockSelectorRecordsItsOwnAudioControlInterface() {
        val config = byteArrayOf(
            // AudioControl interface #3, UAC2.
            9, 0x04, 0x03, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            8, 0x24, 0x0A, 0x0A, 0x03, 0x03, 0x00, 0x00, // Clock Source 10
            8, 0x24, 0x0A, 0x0B, 0x03, 0x03, 0x00, 0x00, // Clock Source 11
            8, 0x24, 0x0B, 0x08, 0x02, 0x0A, 0x0B, 0x00, // Clock Selector 8: pins 10, 11
            // Output Terminal 6, fed by source 1 and clocked by selector 8.
            12, 0x24, 0x03, 0x06, 0x01, 0x03, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00,
            // Playback stream on interface #4, linked to Output Terminal 6.
            9, 0x04, 0x04, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x06, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x04, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(mapOf(8 to 3), result.clockSelectorInterfaces)
        assertEquals(3, result.controlInterface)
        assertEquals(6, result.playbackTerminalId)
        assertEquals(mapOf(6 to 8), result.terminalClockIds)
    }

    @Test
    fun clockSourceValidityControlIsReadableWhenBmControlsD3D2IsSet() {
        // 0x0C and 0x0F both carry Clock Validity Control as read/write (D3..D2).
        assertTrue(
            UsbAudioControlParser.parse(uac2MultiAltConfig(clockControls = 0x0C))
                .clockSource!!.validityReadable,
        )
        assertTrue(
            UsbAudioControlParser.parse(uac2MultiAltConfig(clockControls = 0x0F))
                .clockSource!!.validityReadable,
        )
        // 0x0D = validity read-only (D3..D2 = 0b01) is still readable.
        assertTrue(
            UsbAudioControlParser.parse(uac2MultiAltConfig(clockControls = 0x0D))
                .clockSource!!.validityReadable,
        )
        // 0x03 = frequency control only: there is nothing to ask.
        assertFalse(
            UsbAudioControlParser.parse(uac2MultiAltConfig(clockControls = 0x03))
                .clockSource!!.validityReadable,
        )
    }

    @Test
    fun continuousUac1RangeCoversSevenHundredSixtyEightKilohertz() {
        val continuous = byteArrayOf(
            // AudioStreaming interface #1 alt 1, UAC1 (protocol 0x00).
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x00, 0x00,
            // UAC1 FORMAT_TYPE_I: 2 ch, 3-byte subframe, 24-bit,
            // bSamFreqType = 0 => continuous range.
            14, 0x24, 0x02, 0x01, 0x02, 0x03, 0x18, 0x00,
            // 44100 = 0x00AC44, 768000 = 0x0BB800.
            0x44, 0xAC.toByte(), 0x00,
            0x00, 0xB8.toByte(), 0x0B,
            // Isochronous OUT endpoint.
            7, 0x05, 0x01, 0x09, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(continuous)
        assertEquals(
            listOf(44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000),
            result.supportedRates,
        )
        assertEquals(result.supportedRates, result.altSettingFormats.single().supportedRates)
    }

    @Test
    fun uac3StreamingFormatIsNotParsedWithTheUac1Layout() {
        val config = byteArrayOf(
            // AudioControl interface #0, protocol 0x30 = UAC3.
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x30, 0x00,
            // AudioStreaming interface #1 alt 1, UAC3.
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x30, 0x00,
            // FORMAT_TYPE_I shaped class-specific descriptor. UAC3 lays these
            // out differently, so the UAC1 offsets must never be applied.
            6, 0x24, 0x02, 0x01, 0x04, 0x20,
            // Isochronous OUT endpoint.
            7, 0x05, 0x01, 0x05, 0x00, 0x04, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(UsbAudioControlParser.UAC3, result.uacVersion)
        assertTrue(result.altSettingFormats.isEmpty())
        // The endpoint is still discoverable, so streaming is refused later
        // with a precise reason instead of no DAC found.
        assertEquals(0x01, result.streamingEndpoint!!.address)
    }

    @Test
    fun featureUnitOffThePlaybackPathIsNotASilentFallback() {
        val config = byteArrayOf(
            // AudioControl interface #0, UAC2.
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x20, 0x00,
            // Feature Unit 2 with writable volume, on the CAPTURE path, FIRST.
            18, 0x24, 0x06, 0x02, 0x01,
            0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00,
            // Input Terminal 5 (microphone) feeds Feature Unit 2.
            17, 0x24, 0x02, 0x05, 0x01, 0x01, 0x00, 0x08, 0x02,
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            // Output Terminal 6, fed by source 1: no Feature Unit here.
            12, 0x24, 0x03, 0x06, 0x01, 0x03, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00,
            8, 0x24, 0x0A, 0x08, 0x03, 0x03, 0x00, 0x00, // Clock Source 8
            // Playback stream linked to Output Terminal 6.
            9, 0x04, 0x01, 0x01, 0x01, 0x01, 0x02, 0x20, 0x00,
            16, 0x24, 0x01, 0x06, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
            6, 0x24, 0x02, 0x01, 0x03, 0x18,
            7, 0x05, 0x01, 0x05, 0x00, 0x03, 0x01,
        )
        val result = UsbAudioControlParser.parse(config)
        assertEquals(6, result.playbackTerminalId)
        // Feature Unit 2 belongs to the microphone: writing it would move the
        // record gain. With the playback terminal known, the first candidate is
        // not an acceptable answer.
        assertNull(result.volumeUnit)
        assertFalse(result.hasVolumeControl)
    }

    @Test
    fun featureUnitIsStillFoundWithoutAnyStreamingInterface() {
        // No AudioStreaming interface means no playback terminal at all, so the
        // single-candidate fallback must keep working there.
        val result = UsbAudioControlParser.parse(uac1Config())
        assertNull(result.playbackTerminalId)
        assertEquals(3, result.volumeUnit!!.unitId)
    }
}
