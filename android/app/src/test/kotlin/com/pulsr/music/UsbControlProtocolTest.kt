package com.pulsr.music

import org.junit.Assert.*
import org.junit.Test

class UsbControlProtocolTest {
    private data class Request(val type: Int, val request: Int, val value: Int, val index: Int, val size: Int)

    private class Device(val version: Int) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        val values = mutableMapOf(0 to -1536, 1 to -1536, 2 to -1536)
        var shortRequest = -1
        var ignoreWrites = false
        var failChannel = -1
        var resolution = 256
        var clockRate = 48000
        var acceptClockWrite = true
        var rangeCount = 1
        var minRaw = -15360
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            if (request == shortRequest) return buffer.size - 1
            fun put(offset: Int, raw: Int, bytes: Int = 2) {
                repeat(bytes) { buffer[offset + it] = (raw shr (it * 8)).toByte() }
            }
            if (value == 0x100) {
                if (type and 0x80 != 0) put(0, clockRate, buffer.size)
                else if (acceptClockWrite) clockRate = buffer.indices.fold(0) { a, i -> a or ((buffer[i].toInt() and 255) shl (8 * i)) }
                return buffer.size
            }
            val channel = value and 255
            if (channel == failChannel) return -1
            if (type == 0x21) {
                if (!ignoreWrites) values[channel] = ((buffer[0].toInt() and 255) or ((buffer[1].toInt() and 255) shl 8)).toShort().toInt()
            } else when (request) {
                0x01, 0x81 -> put(0, values.getValue(channel))
                0x82 -> put(0, minRaw)
                0x83 -> put(0, 0)
                0x84 -> put(0, resolution)
                0x02 -> {
                    put(0, rangeCount)
                    if (buffer.size > 2) {
                        put(2, minRaw); put(4, 0); put(6, resolution)
                        if (rangeCount == 2) {
                            put(8, 256); put(10, 512); put(12, 256)
                        }
                    }
                }
                else -> return -1
            }
            return buffer.size
        }
    }

    private fun volume(device: Device, master: Boolean = true) = UsbHardwareVolume(
        device.version,
        UsbAudioControlParser.FeatureUnitVolume(3, 2, 2, master, if (master) listOf(0) else listOf(1, 2)),
        device,
    )

    @Test fun uac2UsesRangeAndSigned16CurWithVerifiedApplication() {
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.refresh())
        assertEquals(-6.0, control.currentDb!!, 0.0)
        assertFalse(control.applied)
        assertTrue(device.requests.contains(Request(0xA1, 2, 0x200, 0x302, 8)))
        assertTrue(control.setDb(-12.25))
        assertEquals(-13.0, control.currentDb!!, 0.0)
        assertTrue(control.applied)
        assertTrue(device.requests.contains(Request(0x21, 1, 0x200, 0x302, 2)))
        assertTrue(device.requests.contains(Request(0xA1, 1, 0x200, 0x302, 2)))
        assertFalse(device.requests.any { it.request in 0x81..0x84 })
    }

    @Test fun uac1RetainsLegacyRequestsAndTwoBytePayloads() {
        val device = Device(1)
        val control = volume(device)
        assertTrue(control.refresh())
        assertTrue(control.setDb(-10.0))
        assertEquals(setOf(0x81, 0x82, 0x83, 0x84), device.requests.filter { it.type == 0xA1 }.map { it.request }.toSet())
        assertTrue(device.requests.all { it.size == 2 })
    }

    @Test fun shortsAndFailedReadbackNeverProveApplication() {
        for (request in listOf(1, 2)) {
            val device = Device(2)
            val control = volume(device)
            assertTrue(control.refresh())
            assertTrue(control.setDb(-10.0))
            device.shortRequest = request
            assertFalse(control.refresh())
            assertFalse(control.applied)
            assertFalse(control.ready)
            assertNull(control.currentDb)
        }
        val device = Device(2)
        val control = volume(device)
        device.ignoreWrites = true
        assertFalse(control.setDb(-10.0))
        assertFalse(control.applied)
    }

    @Test fun externalVolumeChangeClearsAppliedEvidence() {
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.setDb(-10.0))
        device.values[0] = -512
        assertTrue(control.refresh())
        assertFalse(control.applied)
        assertEquals(-2.0, control.currentDb!!, 0.0)
    }

    @Test fun channelOnlyControlsWriteEveryChannelAndNeverMasterOrMute() {
        val device = Device(2)
        val control = volume(device, master = false)
        assertTrue(control.setDb(-10.0))
        val writes = device.requests.filter { it.type == 0x21 }
        assertEquals(listOf(0x201, 0x202), writes.map { it.value })
        device.failChannel = 2
        assertFalse(control.setDb(-12.0))
        assertFalse(control.applied)
    }

    @Test fun unknownRangeAndNonFiniteTargetsCannotWrite() {
        val device = Device(2)
        val control = volume(device)
        device.resolution = 0
        assertFalse(control.setDb(-10.0))
        assertFalse(control.setDb(Double.NaN))
        assertFalse(control.setDb(Double.POSITIVE_INFINITY))
        assertFalse(device.requests.any { it.type == 0x21 })
    }

    @Test fun resolutionIsUnsignedAndMultipleSubrangesAreDecoded() {
        val device = Device(2)
        device.resolution = 0x8000
        device.rangeCount = 2
        val control = volume(device)
        assertTrue(control.refresh())
        assertEquals(2.0, control.maxDb!!, 0.0)
        assertTrue(device.requests.any { it.request == 2 && it.size == 14 })
    }

    @Test fun clockMustReadBackExactlyEvenWhenFixed() {
        val device = Device(2)
        val clock = UsbAudioControlParser.ClockSource(5, 2, false)
        assertTrue(UsbAudioProtocol.setSampleRate(device, 2, clock, 1, 48000, false))
        assertEquals(listOf(Request(0xA1, 1, 0x100, 0x502, 4)), device.requests)
        assertFalse(UsbAudioProtocol.setSampleRate(device, 2, clock, 1, 96000, false))
        device.acceptClockWrite = false
        assertFalse(UsbAudioProtocol.setSampleRate(device, 2, clock.copy(frequencyProgrammable = true), 1, 96000, false))
        device.shortRequest = 1
        assertFalse(UsbAudioProtocol.setSampleRate(device, 2, clock, 1, 48000, false))
    }

    @Test fun uac1ClockUsesEndpointCurAndRejectsShortTransfers() {
        val device = Device(1)
        assertTrue(UsbAudioProtocol.setSampleRate(device, 1, null, 3, 96000, false))
        assertEquals(listOf(Request(0x22, 1, 0x100, 3, 3), Request(0xA2, 0x81, 0x100, 3, 3)), device.requests)
        device.shortRequest = 0x81
        assertFalse(UsbAudioProtocol.setSampleRate(device, 1, null, 3, 96000, true))
    }

    @Test fun formatSelectionRequiresValidBitsChannelsAndKnownDescriptors() {
        val format = UsbAudioControlParser.AltSettingFormat(1, 1, 1, 1024, 4, 16, 2, null, emptyList())
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(format))
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2))
        val good = format.copy(bitResolution = 24)
        assertEquals(good, UsbAudioProtocol.selectFormat(parsed.copy(altSettingFormats = listOf(good)), 48000, 24, 2))
        assertNull(UsbAudioProtocol.selectFormat(parsed.copy(altSettingFormats = emptyList()), 48000, 16, 2))
        assertNull(UsbAudioProtocol.selectFormat(parsed.copy(uacVersion = 1), 48000, 16, 2))
    }

    @Test fun formatSelectionPrefersTheAdvertisedChannelLayoutButAcceptsOthers() {
        val stereo = UsbAudioControlParser.AltSettingFormat(1, 1, 1, 1024, 3, 24, 2, null, emptyList())
        val mono = stereo.copy(altSetting = 2, endpointAddress = 2, channels = 1)
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(mono, stereo))
        // The alt whose channel count matches is taken first ...
        assertEquals(1, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2)!!.altSetting)
        // ... and a DAC that only offers another layout still gets a usable
        // endpoint, because the native sink re-frames to the alt it started on.
        assertEquals(1, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 8)!!.channels)
        // An alt that does not advertise a channel count outranks one that
        // advertises a different count.
        val unadvertised = stereo.copy(altSetting = 3, endpointAddress = 3, channels = 0)
        assertEquals(
            unadvertised,
            UsbAudioProtocol.selectFormat(
                UsbAudioControlParser.Result(
                    2, null, 1, altSettingFormats = listOf(stereo, unadvertised),
                ),
                48000, 24, 1,
            ),
        )
    }

    @Test fun captureOnlyAltSettingIsNeverAFormatCandidate() {
        val mic = UsbAudioControlParser.AltSettingFormat(1, 1, 0x81, 1024, 2, 16, 1, null, emptyList())
        val dac = UsbAudioControlParser.AltSettingFormat(2, 1, 0x02, 1024, 3, 24, 2, null, emptyList())
        // Interface 2 owns the isochronous OUT endpoint, so it is the streaming
        // interface; the microphone alt must not be selectable at all.
        val parsed = UsbAudioControlParser.Result(2, null, 2, altSettingFormats = listOf(mic, dac))
        assertEquals(dac, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2))
        assertEquals(dac, UsbAudioProtocol.selectFormat(parsed, 48000, 16, 1))
    }

    @Test fun requestsBelowTheHardwareMinimumClampInsteadOfFailing() {
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.setDb(-90.0))
        assertEquals(-60.0, control.currentDb!!, 0.0)
        assertEquals(-15360, device.values.getValue(0))
        assertTrue(control.applied)
    }

    @Test fun uac1FullScaleMinimumIsStillARealRange() {
        val device = Device(1)
        device.minRaw = -32768
        val control = volume(device)
        assertTrue(control.refresh())
        assertEquals(-128.0, control.minDb!!, 0.0)
        assertTrue(control.setDb(-200.0))
        assertEquals(-128.0, control.currentDb!!, 0.0)
        assertTrue(control.applied)
    }

    @Test fun mixerPreferenceAloneCannotProveActiveExclusiveFormat() {
        assertFalse(UsbAudioProtocol.mixerConfirmed(true, 0, 0, 0, 48000, 4))
        assertFalse(UsbAudioProtocol.mixerConfirmed(false, 4, 48000, 4, 48000, 4))
        assertFalse(UsbAudioProtocol.mixerConfirmed(true, 4, 48000, 4, 96000, 4))
        assertFalse(UsbAudioProtocol.mixerConfirmed(true, 0, 48000, 4, 48000, 4))
        assertTrue(UsbAudioProtocol.mixerConfirmed(true, 4, 48000, 4, 48000, 4))
    }

    @Test fun streamReuseRequiresNativeActivityAndEntireFormat() {
        val format = UsbAudioProtocol.StreamFormat(48000, 24, 2)
        assertTrue(format.matches(48000, 24, 2, true))
        assertFalse(format.matches(48000, 16, 2, true))
        assertFalse(format.matches(48000, 24, 1, true))
        assertFalse(format.matches(96000, 24, 2, true))
        assertFalse(format.matches(48000, 24, 2, false))
    }

    @Test fun streamReuseComparesTheRequestNotTheWireContainer() {
        // A 16-bit track on a DAC whose only usable alt setting is 24-bit: the
        // request has not changed, so the live stream must be kept. Comparing
        // the request against the container size restarted it on every call.
        val format = UsbAudioProtocol.StreamFormat(48000, 16, 2)
        assertTrue(format.matches(48000, 16, 2, true))
        assertFalse(format.matches(48000, 24, 2, true))
    }
}
