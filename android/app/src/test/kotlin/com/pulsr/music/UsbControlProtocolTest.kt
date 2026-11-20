package com.pulsr.music

import org.junit.Assert.*
import org.junit.Test

class UsbControlProtocolTest {
    @Test fun integer32RequiresTrueValidBitsNotJustFourByteSubslot() {
        val padded24 = UsbAudioControlParser.AltSettingFormat(1, 1, 1, 1024, 4, 24, 2, null, emptyList())
        val raw32 = padded24.copy(altSetting = 2, bitResolution = 32)
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(padded24))
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 32, 2))
        assertEquals(raw32, UsbAudioProtocol.selectFormat(
            parsed.copy(altSettingFormats = listOf(padded24, raw32)), 48000, 32, 2))
        assertEquals(padded24, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2))
    }

    @Test fun failedNativeMixerClearRetainsOwnershipAndRetryReleasesIt() {
        var owned = true
        assertFalse(HiResDacPlugin.clearMixerOwnership({ false }, { owned = false }))
        assertTrue(owned)
        assertFalse(HiResDacPlugin.clearMixerOwnership({ throw IllegalStateException("busy") }, { owned = false }))
        assertTrue(owned)
        assertFalse(HiResDacPlugin.clearMixerOwnership({ null }, { owned = false }))
        assertTrue(owned)
        assertTrue(HiResDacPlugin.clearMixerOwnership({ true }, { owned = false }))
        assertFalse(owned)
    }

    private data class Request(val type: Int, val request: Int, val value: Int, val index: Int, val size: Int)

    private class Device(val version: Int) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        val values = mutableMapOf(0 to -1536, 1 to -1536, 2 to -1536)
        val mutes = mutableMapOf(0 to false, 1 to false, 2 to false)
        var uac2RangeSupported = true
        var shortRequest = -1
        var ignoreWrites = false
        var failChannel = -1
        var resolution = 256
        var clockRate = 48000
        var acceptClockWrite = true
        var rangeCount = 1
        var minRaw = -15360
        var maxRaw = 0
        var quantizationOffset = 0
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            if (request == shortRequest) return buffer.size - 1
            fun put(offset: Int, raw: Int, bytes: Int = 2) {
                repeat(bytes) { buffer[offset + it] = (raw shr (it * 8)).toByte() }
            }
            // CS_MUTE (0x01) is a one-byte control; CS_VOLUME (0x02) is
            // two bytes. The selector lives in wValue's high byte.
            val cs = (value shr 8) and 0xFF
            val muteChannel = value and 0xFF
            if (buffer.size == 1 && cs == 0x01) {
                if (type and 0x80 != 0) {
                    put(0, if (mutes[muteChannel] == true) 1 else 0, 1)
                } else {
                    mutes[muteChannel] = buffer[0].toInt() != 0
                }
                return 1
            }
            if (value == 0x100) {
                if (type and 0x80 != 0) put(0, clockRate, buffer.size)
                else if (acceptClockWrite) clockRate = buffer.indices.fold(0) { a, i -> a or ((buffer[i].toInt() and 255) shl (8 * i)) }
                return buffer.size
            }
            val channel = value and 255
            if (channel == failChannel) return -1
            if (type == 0x21) {
                if (!ignoreWrites) values[channel] = (((buffer[0].toInt() and 255) or ((buffer[1].toInt() and 255) shl 8)).toShort().toInt() + quantizationOffset)
            } else when {
                request == 0x81 -> put(0, values.getValue(channel))
                // UAC2 volume ranges are read with GET_RANGE (0x82); UAC1 uses
                // the GET_MIN/MAX/RES triplet, where 0x82 is GET_MIN.
                request == 0x82 && version == UsbAudioControlParser.UAC2 -> {
                    if (!uac2RangeSupported) {
                        // UAC2 firmware with no GET_RANGE: the first count read
                        // returns the triplet-shaped GET_MIN value, which
                        // fails the count bound and triggers GET_MIN/MAX/RES.
                        put(0, minRaw)
                    } else {
                        put(0, rangeCount)
                        if (buffer.size > 2) {
                            put(2, minRaw); put(4, maxRaw); put(6, resolution)
                            if (rangeCount == 2) {
                                put(8, 256); put(10, 512); put(12, 256)
                            }
                        }
                    }
                }
                request == 0x82 -> put(0, minRaw)
                request == 0x83 -> put(0, maxRaw)
                request == 0x84 -> put(0, resolution)
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
        assertTrue(device.requests.contains(Request(0xA1, 0x82, 0x200, 0x302, 8)))
        assertTrue(control.setDb(-12.25))
        assertEquals(-13.0, control.currentDb!!, 0.0)
        assertTrue(control.applied)
        assertTrue(device.requests.contains(Request(0x21, 1, 0x200, 0x302, 2)))
        assertTrue(device.requests.contains(Request(0xA1, 0x81, 0x200, 0x302, 2)))
        assertFalse(device.requests.any { it.request in 0x83..0x84 })
    }

    @Test fun volumeVerificationToleratesQuantizationRoundingWithinResolution() {
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.refresh())
        // Set volume normally first
        assertTrue(control.setDb(-12.0))
        assertTrue(control.applied)
        // Now simulate a DAC whose internal quantization rounds written raw value by 1 LSB (within ±1 LSB tolerance)
        device.quantizationOffset = 1
        assertTrue(control.setDb(-10.0))
        assertTrue(control.applied)
        // A read-back one res step away must NOT count as applied (narrowed to ±1 raw LSB)
        device.quantizationOffset = device.resolution
        assertFalse(control.setDb(-8.0))
        assertFalse(control.applied)
    }

    @Test fun uac1RetainsLegacyRequestsAndTwoBytePayloads() {
        val device = Device(1)
        val control = volume(device)
        assertTrue(control.refresh())
        assertTrue(control.setDb(-10.0))
        assertEquals(setOf(0x81, 0x82, 0x83, 0x84), device.requests.filter { it.type == 0xA1 }.map { it.request }.toSet())
        assertTrue(device.requests.all { it.size == 2 })
    }

    @Test fun hardwareMuteUsesCsMuteAndReadsBack() {
        val device = Device(2)
        val volume = UsbHardwareVolume(
            2,
            UsbAudioControlParser.FeatureUnitVolume(
                3, 2, 2, false, listOf(1, 2),
                muteOnMaster = false, writableMuteChannels = listOf(1, 2),
            ),
            device,
        )
        assertTrue(volume.hasMute)
        assertEquals(false, volume.getMute())
        assertTrue(volume.setMute(true))
        assertEquals(true, volume.getMute())
        assertTrue(volume.setMute(false))
        assertEquals(false, volume.getMute())
        // The MUTE selector (0x01) is used, never a volume write of zero.
        assertTrue(device.requests.any { it.request == 0x01 && it.size == 1 })
        assertTrue(device.requests.any { it.request == 0x81 && it.size == 1 })
    }

    @Test fun hardwareMuteIsUnavailableWithoutAMuteBit() {
        val device = Device(2)
        val volume = UsbHardwareVolume(
            2,
            UsbAudioControlParser.FeatureUnitVolume(3, 2, 2, false, listOf(1, 2)),
            device,
        )
        assertFalse(volume.hasMute)
        assertNull(volume.getMute())
        assertFalse(volume.setMute(true))
    }

    @Test fun uac2RangeFallsBackToMinMaxRes() {
        val device = Device(2)
        device.uac2RangeSupported = false
        val volume = volume(device)
        assertTrue(volume.refresh())
        assertEquals(-60.0, volume.minDb!!, 0.0)
        assertEquals(0.0, volume.maxDb!!, 0.0)
        assertEquals(-6.0, volume.currentDb!!, 0.0)
        assertTrue(volume.setDb(-12.0))
        assertTrue(volume.applied)
        assertEquals(-12.0, volume.currentDb!!, 0.0)
        assertTrue(device.requests.any { it.request == 0x82 })
        assertTrue(device.requests.any { it.request == 0x83 })
        assertTrue(device.requests.any { it.request == 0x84 })
    }

    @Test fun stepDbFollowsTheDacResolution() {
        val device = Device(2)
        val volume = volume(device)
        assertTrue(volume.refresh())
        // The fake reports a 256 Q8 (1 dB) resolution.
        assertEquals(1.0, volume.stepDb, 0.0)
    }

    @Test fun shortsAndFailedReadbackNeverProveApplication() {
        // Any short read fails the refresh that first populates it, for the
        // CUR read (0x81) and for the UAC2 RANGE read (0x82) alike.
        for (request in listOf(0x81, 0x82)) {
            val device = Device(2)
            val control = volume(device)
            device.shortRequest = request
            assertFalse(control.refresh())
            assertFalse(control.applied)
            assertFalse(control.ready)
            assertNull(control.currentDb)
        }
        // Ranges are read once per connection, so after a successful write it
        // is the short CUR read-back that must destroy the applied evidence.
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.refresh())
        assertTrue(control.setDb(-10.0))
        device.shortRequest = 0x81
        assertFalse(control.refresh())
        assertFalse(control.applied)
        assertFalse(control.ready)
        assertNull(control.currentDb)
        // A write the device ignores never proves application either.
        val ignoring = Device(2)
        val ignoringControl = volume(ignoring)
        ignoring.ignoreWrites = true
        assertFalse(ignoringControl.setDb(-10.0))
        assertFalse(ignoringControl.applied)
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
        assertTrue(device.requests.any { it.request == 0x82 && it.size == 14 })
    }

    @Test fun clockMustReadBackExactlyEvenWhenFixed() {
        val device = Device(2)
        val clock = UsbAudioControlParser.ClockSource(5, 2, false)
        assertTrue(UsbAudioProtocol.setSampleRate(device, 2, clock, 1, 48000, false))
        assertEquals(listOf(Request(0xA1, 0x81, 0x100, 0x502, 4)), device.requests)
        assertFalse(UsbAudioProtocol.setSampleRate(device, 2, clock, 1, 96000, false))
        device.acceptClockWrite = false
        assertFalse(UsbAudioProtocol.setSampleRate(device, 2, clock.copy(frequencyProgrammable = true), 1, 96000, false))
        // The read-back is GET_CUR (0x81); a short read must fail verification.
        device.shortRequest = 0x81
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
        assertNull(UsbAudioProtocol.selectFormat(parsed.copy(uacVersion = 3), 48000, 24, 2))
    }

    @Test fun formatSelectionRefusesChannelLayoutMismatch() {
        val stereo = UsbAudioControlParser.AltSettingFormat(1, 1, 1, 1024, 3, 24, 2, null, emptyList())
        val mono = stereo.copy(altSetting = 2, endpointAddress = 2, channels = 1)
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(mono, stereo))
        // The alt whose channel count matches is taken ...
        assertEquals(1, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2)!!.altSetting)
        assertEquals(2, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 1)!!.altSetting)
        // ... and a request no alt can carry verbatim is refused: re-framing
        // mono into 8 channels would alter the samples, which Bit-Perfect must
        // never do silently.
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 24, 8))
        // An alt that does not advertise a channel count outranks one that
        // advertises a different count (it is treated as the requested one).
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

    @Test fun formatSelectionSpansEveryPlaybackInterface() {
        // A multi-function DAC: streamingInterface tracks the FIRST iso-OUT
        // interface, but the requested 24-bit wire format only exists on a
        // second playback interface. Every iso-OUT alt is a candidate.
        val iface1 = UsbAudioControlParser.AltSettingFormat(1, 1, 0x01, 1024, 2, 16, 2, null, emptyList())
        val iface3 = UsbAudioControlParser.AltSettingFormat(3, 1, 0x02, 1024, 3, 24, 2, null, emptyList())
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(iface1, iface3))
        assertEquals(iface3, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2))
        assertEquals(iface1, UsbAudioProtocol.selectFormat(parsed, 48000, 16, 2))
    }

    @Test fun captureOnlyAltSettingIsNeverAFormatCandidate() {
        val mic = UsbAudioControlParser.AltSettingFormat(1, 1, 0x81, 1024, 2, 16, 1, null, emptyList())
        val dac = UsbAudioControlParser.AltSettingFormat(2, 1, 0x02, 1024, 3, 24, 2, null, emptyList())
        // Interface 2 owns the isochronous OUT endpoint, so it is the streaming
        // interface; the microphone alt must not be selectable at all.
        val parsed = UsbAudioControlParser.Result(2, null, 2, altSettingFormats = listOf(mic, dac))
        assertEquals(dac, UsbAudioProtocol.selectFormat(parsed, 48000, 24, 2))
        // The DAC alt advertises 2 channels; a 1-channel request is refused
        // rather than re-framed onto the stereo endpoint.
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 16, 1))
    }

    @Test fun requestsBelowTheHardwareMinimumClampInsteadOfFailing() {
        val device = Device(2)
        val control = volume(device)
        assertTrue(control.setDb(-90.0))
        assertEquals(-60.0, control.currentDb!!, 0.0)
        assertEquals(-15360, device.values.getValue(0))
        assertTrue(control.applied)
    }

    @Test fun uac1FullScaleMinimumNeverWritesTheMuteMarker() {
        val device = Device(1)
        device.minRaw = -32768
        val control = volume(device)
        assertTrue(control.refresh())
        // Raw 0x8000 is the -inf/mute marker, not a volume step: the quietest
        // writable value is one resolution (256) above it, and the advertised
        // minimum reflects what can actually be written.
        assertEquals(-127.0, control.minDb!!, 0.0)
        assertTrue(control.setDb(-200.0))
        assertEquals(-127.0, control.currentDb!!, 0.0)
        assertEquals(-32512, device.values.getValue(0))
        assertTrue(control.applied)
    }

    @Test fun muteOnlyRangeCannotBeWritten() {
        val device = Device(2)
        device.minRaw = -32768
        device.maxRaw = -32768
        device.values[0] = -32768
        device.values[1] = -32768
        device.values[2] = -32768
        // A range that contains nothing but the mute marker has no real step:
        // the refresh succeeds (the device is where it says it is) but no
        // volume request can ever be written.
        val control = volume(device)
        assertTrue(control.refresh())
        assertFalse(control.setDb(-6.0))
        assertFalse(control.applied)
        assertFalse(device.requests.any { it.type == 0x21 })
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
        // Narrower PCM fits inside an already-open wider wire container via
        // zero-padding without tearing down the endpoint; wider requests must
        // reopen to a wider alt setting.
        assertTrue(format.matches(48000, 16, 2, true))
        assertFalse(format.matches(48000, 32, 2, true))
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

    /** Answers Clock-Selector GET_CUR pin reads; [pin] null fails the transfer. */
    private class PinDevice(private val pin: Int?) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            val p = pin ?: return -1
            if (buffer.size != 1) return -1
            buffer[0] = p.toByte()
            return 1
        }
    }

    private val clockTen = UsbAudioControlParser.ClockSource(10, 0, true)
    private val clockEleven = UsbAudioControlParser.ClockSource(11, 0, false)

    private fun selectorTopology() = UsbAudioControlParser.Result(
        2, null, 1,
        clockSource = clockTen, clockSources = listOf(clockTen, clockEleven),
        controlInterface = 0, playbackTerminalId = 3,
        terminalClockIds = mapOf(3 to 8),
        clockSelectorInputs = mapOf(8 to listOf(10, 11)),
    )

    @Test fun activeClockComesFromTheSelectorPinNotTheDescriptorOrder() {
        val device = PinDevice(2)
        assertEquals(clockEleven, UsbAudioProtocol.resolveActiveClock(device, selectorTopology()))
        // GET_CUR(CX_CLOCK_SELECTOR_CONTROL): 0xA1 / 0x81 / wValue 0x0100 /
        // wIndex (selectorId shl 8) | acInterface / 1 byte.
        assertEquals(listOf(Request(0xA1, 0x81, 0x100, 0x800, 1)), device.requests)
    }

    @Test fun failedOrInvalidSelectorPinReadRefusesToGuessAClock() {
        for (pin in listOf(null, 0, 3, 99)) {
            assertNull(UsbAudioProtocol.resolveActiveClock(PinDevice(pin), selectorTopology()))
        }
        // Without a known AC interface there is no wIndex to address, which
        // must fail the same way rather than fall back to the static guess.
        assertNull(
            UsbAudioProtocol.resolveActiveClock(
                PinDevice(1), selectorTopology().copy(controlInterface = -1),
            ),
        )
        // A cycle in the clock graph fails safe too.
        val cyclic = selectorTopology().copy(
            clockSelectorInputs = mapOf(8 to listOf(9), 9 to listOf(8)),
        )
        assertNull(UsbAudioProtocol.resolveActiveClock(PinDevice(1), cyclic))
    }

    @Test fun singleInputSelectorAndMultiplierResolveWithoutDeviceReads() {
        val viaSelector = selectorTopology().copy(
            clockSelectorInputs = mapOf(8 to listOf(10)),
        )
        val device = PinDevice(1)
        assertEquals(clockTen, UsbAudioProtocol.resolveActiveClock(device, viaSelector))
        assertTrue(device.requests.isEmpty())

        val viaMultiplier = selectorTopology().copy(
            clockSelectorInputs = emptyMap(),
            terminalClockIds = mapOf(3 to 12),
            clockMultiplierSources = mapOf(12 to 10),
        )
        assertEquals(clockTen, UsbAudioProtocol.resolveActiveClock(PinDevice(null), viaMultiplier))
    }

    @Test fun silentClockTopologyKeepsTheStaticGuess() {
        val parsed = UsbAudioControlParser.Result(
            2, null, 1, clockSource = clockTen, clockSources = listOf(clockTen),
        )
        val device = PinDevice(null)
        assertEquals(clockTen, UsbAudioProtocol.resolveActiveClock(device, parsed))
        assertTrue(device.requests.isEmpty())
    }

    private class RateDevice(
        val version: Int,
        var currentRate: Int = 44100,
        var allowWrite: Boolean = true,
        var allowReadback: Boolean = true,
    ) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            val isRead = (type and 0x80) != 0
            if (isRead) {
                if (!allowReadback) return -1
                repeat(buffer.size) { buffer[it] = (currentRate shr (it * 8)).toByte() }
                return buffer.size
            } else {
                if (!allowWrite) return -1
                currentRate = buffer.indices.fold(0) { a, i -> a or ((buffer[i].toInt() and 255) shl (8 * i)) }
                return buffer.size
            }
        }
    }

    @Test fun uac1SampleRateReadbackSupportedYieldsVerified() {
        val dev = RateDevice(1, currentRate = 44100, allowReadback = true)
        val res = UsbAudioProtocol.setSampleRateWithResult(dev, 1, null, 0x01, 48000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.VERIFIED, res)
        assertEquals(48000, dev.currentRate)
    }

    @Test fun uac1SampleRateReadbackUnsupportedYieldsUnverifiedReadbackUnsupported() {
        val dev = RateDevice(1, currentRate = 44100, allowReadback = false)
        val res = UsbAudioProtocol.setSampleRateWithResult(dev, 1, null, 0x01, 48000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.UNVERIFIED_READBACK_UNSUPPORTED, res)
        assertEquals(48000, dev.currentRate)
    }

    @Test fun uac1SampleRateFailedWhenTransferFails() {
        val dev = RateDevice(1, currentRate = 44100, allowWrite = false)
        val res = UsbAudioProtocol.setSampleRateWithResult(dev, 1, null, 0x01, 96000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.FAILED, res)
    }

    @Test fun uac2SampleRateReadbackFailsWhenReadbackRefused() {
        val dev = RateDevice(2, currentRate = 44100, allowReadback = false)
        val clock = UsbAudioControlParser.ClockSource(5, 0, true)
        val res = UsbAudioProtocol.setSampleRateWithResult(dev, 2, clock, 0x01, 48000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.FAILED, res)
    }

    @Test fun selectFormatStrictlyRefusesChannelMismatch() {
        val stereoDac = UsbAudioControlParser.AltSettingFormat(1, 1, 0x01, 1024, 2, 16, 2, null, emptyList())
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(stereoDac))
        // 2 channels matches
        assertNotNull(UsbAudioProtocol.selectFormat(parsed, 48000, 16, 2))
        // 1, 6, 8 channels are refused (returns null) rather than corrupted
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 16, 1))
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 16, 6))
        assertNull(UsbAudioProtocol.selectFormat(parsed, 48000, 16, 8))
    }

    @Test fun uac3DescriptorParsesAsUac3Version() {
        // AudioControl interface with protocol 0x30 = UAC3
        val uac3Desc = byteArrayOf(
            9, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x30, 0x00,
        )
        val parsed = UsbAudioControlParser.parse(uac3Desc)
        assertEquals(UsbAudioControlParser.UAC3, parsed.uacVersion)
        assertEquals("UAC3", UsbDacDiagnostics.uacLabel(parsed.uacVersion))
    }

    @Test fun uac3FormatSelectionIsRefused() {
        val stereoDac = UsbAudioControlParser.AltSettingFormat(1, 1, 0x01, 1024, 3, 24, 2, null, emptyList())
        val parsed = UsbAudioControlParser.Result(3, null, 1, altSettingFormats = listOf(stereoDac))
        val selected = UsbAudioProtocol.selectFormat(parsed, 96000, 24, 2)
        assertNull(selected)
    }

    @Test fun selectFormatCovers24In32Uac1FixedRateAndChannelMismatch() {
        val uac2In32 = UsbAudioControlParser.AltSettingFormat(
            interfaceNumber = 1,
            altSetting = 1,
            endpointAddress = 0x01,
            maxPacketSize = 1024,
            subslotSize = 4,
            bitResolution = 24,
            channels = 2,
            feedbackEndpointAddress = null,
            supportedRates = emptyList(),
        )
        val uac2Parsed = UsbAudioControlParser.Result(
            uacVersion = UsbAudioControlParser.UAC2,
            volumeUnit = null,
            streamingInterface = 1,
            altSettingFormats = listOf(uac2In32),
        )
        assertEquals(uac2In32, UsbAudioProtocol.selectFormat(uac2Parsed, 96000, 24, 2))
        assertNull(UsbAudioProtocol.selectFormat(uac2Parsed, 96000, 32, 2))
        assertNull(UsbAudioProtocol.selectFormat(uac2Parsed, 96000, 24, 4))

        val uac1Fixed = UsbAudioControlParser.AltSettingFormat(
            interfaceNumber = 1,
            altSetting = 1,
            endpointAddress = 0x01,
            maxPacketSize = 256,
            subslotSize = 3,
            bitResolution = 24,
            channels = 2,
            feedbackEndpointAddress = null,
            supportedRates = listOf(44100, 48000),
            sampleRateControlSupported = false,
        )
        val uac1Parsed = UsbAudioControlParser.Result(
            uacVersion = UsbAudioControlParser.UAC1,
            volumeUnit = null,
            streamingInterface = 1,
            altSettingFormats = listOf(uac1Fixed),
        )
        assertEquals(uac1Fixed, UsbAudioProtocol.selectFormat(uac1Parsed, 48000, 24, 2))
        assertNull(UsbAudioProtocol.selectFormat(uac1Parsed, 96000, 24, 2))
        assertNull(UsbAudioProtocol.selectFormat(uac1Parsed, 48000, 24, 1))
    }

    @Test fun uac3SampleRateProgrammingIsRefused() {
        val dev = RateDevice(3, currentRate = 44100, allowReadback = true)
        val clock = UsbAudioControlParser.ClockSource(clockId = 4, controlInterface = 0, frequencyProgrammable = true)
        val res = UsbAudioProtocol.setSampleRateWithResult(dev, 3, clock, 0x01, 96000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.FAILED, res)
    }

    @Test fun selectFormatRejectsBitDepthsTheSinkCannotPack() {
        // A 20-bit / 3-byte alt is listed first and does fit 16..24 numerically,
        // but UsbAudioSink::Open only packs 16/24/32 valid bits.
        val twentyBit = UsbAudioControlParser.AltSettingFormat(1, 1, 0x01, 1024, 3, 20, 2, null, emptyList())
        val twentyFourBit = UsbAudioControlParser.AltSettingFormat(1, 2, 0x01, 1024, 3, 24, 2, null, emptyList())
        val parsed = UsbAudioControlParser.Result(2, null, 1, altSettingFormats = listOf(twentyBit, twentyFourBit))
        assertEquals(twentyFourBit, UsbAudioProtocol.selectFormat(parsed, 48000, 16, 2))
        assertNull(
            UsbAudioProtocol.selectFormat(
                parsed.copy(altSettingFormats = listOf(twentyBit)), 48000, 16, 2,
            ),
        )
    }

    /**
     * UAC2 device with a two-pin Clock Selector 8 on AC interface 0:
     * pin 1 -> Clock Source 10 (fixed 44.1 kHz), pin 2 -> Clock Source 11
     * (programmable). A rate write only lands on the programmable clock; the
     * fixed one keeps reporting 44.1 kHz.
     *
     * [unlockedUntilProgrammed] clocks answer CLOCK_VALID with 0 until their own
     * rate write has landed (a real DAC reports "not valid" until programmed);
     * [permanentlyUnlocked] clocks never report valid.
     */
    private class SelectorDevice(
        var selectorPin: Int = 1,
        var currentRate: Int = 44100,
        private val unlockedUntilProgrammed: Set<Int> = emptySet(),
        private val permanentlyUnlocked: Set<Int> = emptySet(),
        /** Refuses selector writes of this pin value (a wedged selector). */
        private val refuseSelectorPin: Int? = null,
        private val fixedClockId: Int = 10,
        private val programmableClockId: Int = 11,
        private val selectorId: Int = 8,
        private val interfaceNumber: Int = 0,
    ) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        val pinWrites = mutableListOf<Int>()
        val refusedPinWrites = mutableListOf<Int>()
        val rateWrites = mutableListOf<Int>()
        private val programmedClocks = mutableSetOf<Int>()
        var failRateWrites = false

        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            val isRead = (type and 0x80) != 0
            if ((index and 0xFF) != interfaceNumber) return -1
            val entity = index shr 8
            fun put(raw: Int) {
                repeat(buffer.size) { buffer[it] = (raw shr (it * 8)).toByte() }
            }
            return when {
                entity == selectorId && buffer.size == 1 -> {
                    if (isRead) {
                        buffer[0] = selectorPin.toByte()
                        1
                    } else {
                        val written = buffer[0].toInt() and 0xFF
                        if (written == refuseSelectorPin) {
                            refusedPinWrites += written
                            -1
                        } else {
                            selectorPin = written
                            pinWrites += written
                            1
                        }
                    }
                }
                value == 0x0200 && buffer.size == 1 -> {
                    if (!isRead) {
                        -1
                    } else {
                        val locked = when {
                            entity in permanentlyUnlocked -> false
                            entity in unlockedUntilProgrammed -> entity in programmedClocks
                            else -> true
                        }
                        buffer[0] = (if (locked) 1 else 0).toByte()
                        1
                    }
                }
                value == 0x0100 && buffer.size == 4 -> {
                    val programmable = entity == programmableClockId
                    if (!programmable && entity != fixedClockId) {
                        -1
                    } else if (isRead) {
                        put(if (programmable) currentRate else 44100)
                        4
                    } else if (programmable && !failRateWrites) {
                        val written = buffer.indices.fold(0) { acc, i ->
                            acc or ((buffer[i].toInt() and 255) shl (8 * i))
                        }
                        rateWrites += written
                        currentRate = written
                        programmedClocks += entity
                        4
                    } else {
                        -1
                    }
                }
                else -> -1
            }
        }
    }

    private fun selectorParsed(validityReadable: Boolean = false): UsbAudioControlParser.Result {
        val fixed = UsbAudioControlParser.ClockSource(
            clockId = 10, controlInterface = 0, frequencyProgrammable = false,
            validityReadable = validityReadable,
        )
        val programmable = UsbAudioControlParser.ClockSource(
            clockId = 11, controlInterface = 0, frequencyProgrammable = true,
            validityReadable = validityReadable,
        )
        return UsbAudioControlParser.Result(
            uacVersion = 2,
            volumeUnit = null,
            streamingInterface = 1,
            clockSource = fixed,
            clockSources = listOf(fixed, programmable),
            controlInterface = 0,
            playbackTerminalId = 3,
            terminalClockIds = mapOf(3 to 8),
            clockSelectorInputs = mapOf(8 to listOf(10, 11)),
            clockSelectorInterfaces = mapOf(8 to 0),
        )
    }

    @Test fun programPlaybackClockSwitchesToThePinThatCanDeliverTheRate() {
        val device = SelectorDevice(selectorPin = 1)
        val result = UsbAudioProtocol.programPlaybackClock(device, selectorParsed(), 0x01, 96000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.VERIFIED, result)
        // SET_CUR(CX_CLOCK_SELECTOR_CONTROL) on selector 8, pin 2, AC interface 0.
        assertTrue(device.requests.contains(Request(0x21, 1, 0x0100, 0x0800, 1)))
        assertEquals(listOf(2), device.pinWrites)
        assertEquals(2, device.selectorPin)
        // Then the rate on Clock Source 11, verified by read-back.
        assertTrue(device.requests.contains(Request(0x21, 1, 0x0100, 0x0B00, 4)))
        assertTrue(device.requests.contains(Request(0xA1, 0x81, 0x0100, 0x0B00, 4)))
        assertEquals(listOf(96000), device.rateWrites)
        // The fixed 44.1 kHz clock was only ever read, never written.
        assertTrue(device.requests.contains(Request(0xA1, 0x81, 0x0100, 0x0A00, 4)))
        assertFalse(device.requests.any { it.type == 0x21 && it.index == 0x0A00 })
    }

    @Test fun programPlaybackClockRestoresTheOriginalPinWhenEveryPinFails() {
        val device = SelectorDevice(selectorPin = 1)
        device.failRateWrites = true
        val result = UsbAudioProtocol.programPlaybackClock(device, selectorParsed(), 0x01, 96000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.FAILED, result)
        // Pin 2 was tried, then the selector was put back on pin 1: the DAC is
        // not left pointing at a source that was just proven unusable.
        assertEquals(listOf(2, 1), device.pinWrites)
        assertEquals(1, device.selectorPin)
        assertTrue(device.rateWrites.isEmpty())
    }

    @Test fun programPlaybackClockReportsAFailedSelectorRestoreDistinctly() {
        // Pin 2 cannot deliver the rate and the selector refuses to go back to
        // pin 1, even on the retry: the DAC is left on a dead source, which is a
        // different failure than "no pin supports this rate".
        val device = SelectorDevice(selectorPin = 1, refuseSelectorPin = 1)
        device.failRateWrites = true
        val result = UsbAudioProtocol.programPlaybackClock(device, selectorParsed(), 0x01, 96000, false)
        assertEquals(UsbAudioProtocol.RateSetResult.SELECTOR_RESTORE_FAILED, result)
        assertFalse(result.isSuccess)
        assertEquals(listOf(2), device.pinWrites)
        // The restore was attempted twice before being reported.
        assertEquals(listOf(1, 1), device.refusedPinWrites)
    }

    @Test fun programPlaybackClockWithoutASelectorFailsInsteadOfGuessing() {
        val device = SelectorDevice()
        val parsed = selectorParsed().copy(
            terminalClockIds = mapOf(3 to 10),
            clockSelectorInputs = emptyMap(),
        )
        assertEquals(
            UsbAudioProtocol.RateSetResult.FAILED,
            UsbAudioProtocol.programPlaybackClock(device, parsed, 0x01, 96000, false),
        )
        assertTrue(device.pinWrites.isEmpty())
        assertTrue(device.rateWrites.isEmpty())
    }

    @Test fun programPlaybackClockProgramsAClockThatReportsItselfUnlockedUntilProgrammed() {
        // A real DAC reports CLOCK_VALID == 0 until its clock is programmed; the
        // old flow judged validity first and refused this working device.
        val device = SelectorDevice(selectorPin = 2, unlockedUntilProgrammed = setOf(11))
        val result = UsbAudioProtocol.programPlaybackClock(
            device, selectorParsed(validityReadable = true), 0x01, 96000, false,
        )
        assertEquals(UsbAudioProtocol.RateSetResult.VERIFIED, result)
        // SET_CUR(CS_SAM_FREQ_CONTROL) really was issued on Clock Source 11.
        assertTrue(device.requests.contains(Request(0x21, 1, 0x0100, 0x0B00, 4)))
        assertEquals(listOf(96000), device.rateWrites)
        // Validity was consulted afterwards, as a post-condition only.
        assertTrue(device.requests.contains(Request(0xA1, 0x81, 0x0200, 0x0B00, 1)))
        // The working pin is kept: no switch, no restore.
        assertTrue(device.pinWrites.isEmpty())
        assertEquals(2, device.selectorPin)
    }

    @Test fun programPlaybackClockRejectsAClockThatStaysUnlockedAfterProgrammingAndTriesTheNextPin() {
        // Pin 2 (Clock Source 11) takes the rate but never reports valid, so it
        // must not be accepted; pin 1 is tried next and the selector restored.
        val device = SelectorDevice(selectorPin = 2, permanentlyUnlocked = setOf(11))
        val result = UsbAudioProtocol.programPlaybackClock(
            device, selectorParsed(validityReadable = true), 0x01, 96000, false,
        )
        assertEquals(UsbAudioProtocol.RateSetResult.FAILED, result)
        assertEquals(listOf(96000), device.rateWrites)
        assertEquals(listOf(1, 2), device.pinWrites)
        assertEquals(2, device.selectorPin)
    }

    @Test fun programPlaybackClockDelegatesToTheUac1EndpointPath() {
        val dev = RateDevice(1, currentRate = 44100, allowReadback = true)
        val parsed = UsbAudioControlParser.Result(1, null, 1)
        assertEquals(
            UsbAudioProtocol.RateSetResult.VERIFIED,
            UsbAudioProtocol.programPlaybackClock(dev, parsed, 0x01, 48000, false),
        )
        assertEquals(
            listOf(Request(0x22, 1, 0x100, 0x01, 3), Request(0xA2, 0x81, 0x100, 0x01, 3)),
            dev.requests,
        )
    }

    /** Answers a single-byte Clock-Validity read; null means the transfer fails. */
    private class ValidityDevice(private val reported: Int?) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            if (buffer.size != 1) return -1
            val byte = reported ?: return -1
            buffer[0] = byte.toByte()
            return 1
        }
    }

    @Test fun clockValidityIsOneByteAndFailsOpen() {
        val clock = UsbAudioControlParser.ClockSource(11, 0, true, validityReadable = true)
        assertFalse(UsbAudioProtocol.isClockValid(ValidityDevice(0), clock))
        assertTrue(UsbAudioProtocol.isClockValid(ValidityDevice(1), clock))
        // A failed transfer is not evidence that the clock is unlocked.
        assertTrue(UsbAudioProtocol.isClockValid(ValidityDevice(null), clock))
        val device = ValidityDevice(1)
        assertTrue(UsbAudioProtocol.isClockValid(device, clock))
        // GET_CUR(CS_CLOCK_VALID_CONTROL): 0xA1 / 0x81 / 0x0200 / (11 shl 8), 1 byte.
        assertEquals(listOf(Request(0xA1, 0x81, 0x0200, 0x0B00, 1)), device.requests)
        // A clock without a readable validity control is never queried at all.
        val quiet = ValidityDevice(0)
        assertTrue(UsbAudioProtocol.isClockValid(quiet, clock.copy(validityReadable = false)))
        assertTrue(quiet.requests.isEmpty())
    }

    @Test fun setClockSelectorPinAddressesTheSelectorsOwnInterface() {
        val requests = mutableListOf<Request>()
        val payloads = mutableListOf<Int>()
        val device = object : UsbControlTransfer {
            override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
                requests += Request(type, request, value, index, buffer.size)
                payloads += buffer[0].toInt() and 0xFF
                return 1
            }
        }
        assertTrue(UsbAudioProtocol.setClockSelectorPin(device, 8, 2, 2))
        assertEquals(listOf(Request(0x21, 0x01, 0x0100, 0x0802, 1)), requests)
        assertEquals(listOf(2), payloads)
        // Unaddressable selector/interface and a 0th pin are refused up front.
        assertFalse(UsbAudioProtocol.setClockSelectorPin(device, 0, 2, 1))
        assertFalse(UsbAudioProtocol.setClockSelectorPin(device, 8, -1, 1))
        assertFalse(UsbAudioProtocol.setClockSelectorPin(device, 8, 2, 0))
        assertEquals(1, requests.size)
    }

    @Test fun activeClockSelectionRecordsTheSelectorAndPinItRead() {
        val selection = UsbAudioProtocol.resolveActiveClockSelection(PinDevice(2), selectorTopology())
        assertNotNull(selection)
        assertEquals(clockEleven, selection!!.clock)
        assertEquals(8, selection.selectorId)
        assertEquals(2, selection.pin)
        assertEquals(0, selection.selectorInterface)
        // Without any terminal clock the static guess is kept, with no selector.
        val plain = UsbAudioProtocol.resolveActiveClockSelection(
            PinDevice(null),
            UsbAudioControlParser.Result(2, null, 1, clockSource = clockTen, clockSources = listOf(clockTen)),
        )
        assertEquals(clockTen, plain!!.clock)
        assertNull(plain.selectorId)
        assertNull(plain.pin)
    }

    /**
     * UAC2 device whose Clock Source 11 answers GET_RANGE with [subranges]
     * (min, max, resolution each) and GET_CUR with [currentRate].
     */
    private class RangeDevice(
        private val subranges: List<Triple<Int, Int, Int>>?,
        private val currentRate: Int?,
    ) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            fun put(offset: Int, raw: Int, bytes: Int) {
                repeat(bytes) { buffer[offset + it] = (raw shr (it * 8)).toByte() }
            }
            if (request == 0x82) {
                val ranges = subranges ?: return -1
                if (buffer.size == 2) {
                    put(0, ranges.size, 2)
                    return 2
                }
                if (buffer.size != 2 + ranges.size * 12) return -1
                put(0, ranges.size, 2)
                ranges.forEachIndexed { n, range ->
                    put(2 + n * 12, range.first, 4)
                    put(6 + n * 12, range.second, 4)
                    put(10 + n * 12, range.third, 4)
                }
                return buffer.size
            }
            if (request == 0x81 && buffer.size == 4) {
                val rate = currentRate ?: return -1
                put(0, rate, 4)
                return 4
            }
            return -1
        }
    }

    private fun rangedParsed(): UsbAudioControlParser.Result {
        val programmable = UsbAudioControlParser.ClockSource(11, 0, true)
        return UsbAudioControlParser.Result(
            uacVersion = 2,
            volumeUnit = null,
            streamingInterface = 1,
            clockSource = programmable,
            clockSources = listOf(programmable),
            controlInterface = 0,
            playbackTerminalId = 3,
            terminalClockIds = mapOf(3 to 11),
        )
    }

    @Test fun uac2RateDiscoveryReadsTheClockRangeWithoutFabricatingRates() {
        val device = RangeDevice(
            subranges = listOf(
                Triple(44100, 48000, 1),
                Triple(705600, 768000, 1),
            ),
            currentRate = 96000,
        )
        assertEquals(
            listOf(44100, 48000, 705600, 768000),
            UsbAudioProtocol.queryPlaybackRates(device, rangedParsed()),
        )
        // Count first (2 bytes), then 2 + 2*12 bytes of subrange payloads.
        assertTrue(device.requests.contains(Request(0xA1, 0x82, 0x0100, 0x0B00, 2)))
        assertTrue(device.requests.contains(Request(0xA1, 0x82, 0x0100, 0x0B00, 26)))
    }

    @Test fun uac2RateDiscoveryKeepsSingleValuedSubrangesExact() {
        val device = RangeDevice(
            subranges = listOf(Triple(96000, 96000, 0), Triple(48000, 88200, 1)),
            currentRate = 44100,
        )
        assertEquals(
            listOf(48000, 88200, 96000),
            UsbAudioProtocol.queryPlaybackRates(device, rangedParsed()),
        )
    }

    @Test fun uac2RateDiscoveryReturnsEmptyRatherThanInventingRates() {
        // Neither a range nor a current value: nothing is known.
        assertTrue(
            UsbAudioProtocol.queryPlaybackRates(RangeDevice(null, null), rangedParsed()).isEmpty(),
        )
        // No range published: the exact current value is the only honest answer.
        assertEquals(
            listOf(96000),
            UsbAudioProtocol.queryPlaybackRates(RangeDevice(null, 96000), rangedParsed()),
        )
    }

    @Test fun uac1RateDiscoveryComesFromTheDescriptorsAlone() {
        val parsed = UsbAudioControlParser.Result(1, null, 1, supportedRates = listOf(44100, 48000, 96000))
        val device = RangeDevice(null, null)
        assertEquals(listOf(44100, 48000, 96000), UsbAudioProtocol.queryPlaybackRates(device, parsed))
        assertTrue(device.requests.isEmpty())
    }

    /**
     * UAC2 device with a three-pin Clock Selector 8 on AC interface 0:
     * pin 1 -> Clock Source 10 (fixed 44.1 kHz), pin 2 -> Clock Source 11
     * (fixed 48 kHz), pin 3 -> Clock Source 12 (programmable, current rate moves
     * with SET_CUR). CLOCK_VALID is not readable, so it never blocks a clock.
     */
    private class ThreePinSelectorDevice(var selectorPin: Int = 1) : UsbControlTransfer {
        val requests = mutableListOf<Request>()
        val pinWrites = mutableListOf<Int>()
        val rateWrites = mutableListOf<Int>()
        private var currentRate = 48000

        override fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int {
            requests += Request(type, request, value, index, buffer.size)
            if ((index and 0xFF) != 0) return -1
            val entity = index shr 8
            val isRead = (type and 0x80) != 0
            fun put(raw: Int) {
                repeat(buffer.size) { buffer[it] = (raw shr (it * 8)).toByte() }
            }
            if (entity == 8 && buffer.size == 1) {
                if (isRead) {
                    buffer[0] = selectorPin.toByte()
                } else {
                    selectorPin = buffer[0].toInt() and 0xFF
                    pinWrites += selectorPin
                }
                return 1
            }
            if (value == 0x0100 && buffer.size == 4) {
                return when (entity) {
                    10 -> { put(44100); 4 }
                    11 -> { put(48000); 4 }
                    12 -> {
                        if (isRead) {
                            put(currentRate)
                        } else {
                            currentRate = buffer.indices.fold(0) { acc, i ->
                                acc or ((buffer[i].toInt() and 255) shl (8 * i))
                            }
                            rateWrites += currentRate
                        }
                        4
                    }
                    else -> -1
                }
            }
            return -1
        }
    }

    private val threePinParsed = UsbAudioControlParser.Result(
        uacVersion = 2,
        volumeUnit = null,
        streamingInterface = 1,
        clockSource = UsbAudioControlParser.ClockSource(10, 0, false),
        clockSources = listOf(
            UsbAudioControlParser.ClockSource(10, 0, false),
            UsbAudioControlParser.ClockSource(11, 0, false),
            UsbAudioControlParser.ClockSource(12, 0, true),
        ),
        controlInterface = 0,
        playbackTerminalId = 3,
        terminalClockIds = mapOf(3 to 8),
        clockSelectorInputs = mapOf(8 to listOf(10, 11, 12)),
        clockSelectorInterfaces = mapOf(8 to 0),
    )

    @Test fun preferredSelectorPinIsUsedFirstWhenItCanDeliverTheRate() {
        val device = ThreePinSelectorDevice(selectorPin = 1)
        val result = UsbAudioProtocol.programPlaybackClock(
            device, threePinParsed, 0x01, 96000, false, 3,
        )
        assertEquals(UsbAudioProtocol.RateSetResult.VERIFIED, result)
        // Pin 3 was selected directly: the default scan would have written pin 2
        // first and failed on its fixed 48 kHz clock.
        assertEquals(listOf(3), device.pinWrites)
        assertEquals(3, device.selectorPin)
        assertEquals(listOf(96000), device.rateWrites)
        // The fixed 48 kHz source was never selected, so it was never written.
        assertFalse(device.requests.any { it.type == 0x21 && it.index == 0x0B00 })
    }

    @Test fun preferredSelectorPinThatCannotDeliverTheRateFallsBackToTheExistingScan() {
        val device = ThreePinSelectorDevice(selectorPin = 1)
        // Preferred pin 2 is a fixed 48 kHz source: it accepts the pin write but
        // cannot carry 96 kHz, so the selector goes back to its original pin and
        // the existing scan finds pin 3.
        val result = UsbAudioProtocol.programPlaybackClock(
            device, threePinParsed, 0x01, 96000, false, 2,
        )
        assertEquals(UsbAudioProtocol.RateSetResult.VERIFIED, result)
        assertEquals(listOf(2, 1, 3), device.pinWrites)
        assertEquals(3, device.selectorPin)
        assertEquals(listOf(96000), device.rateWrites)
    }

    @Test fun absentPreferredSelectorPinBehavesExactlyAsTheDefaultEntryPoint() {
        // A pin the selector does not expose is ignored: both calls must issue
        // byte-for-byte identical request sequences.
        val withHint = ThreePinSelectorDevice(selectorPin = 1)
        val withoutHint = ThreePinSelectorDevice(selectorPin = 1)
        assertEquals(
            UsbAudioProtocol.RateSetResult.VERIFIED,
            UsbAudioProtocol.programPlaybackClock(withoutHint, threePinParsed, 0x01, 96000, false),
        )
        assertEquals(
            UsbAudioProtocol.RateSetResult.VERIFIED,
            UsbAudioProtocol.programPlaybackClock(withHint, threePinParsed, 0x01, 96000, false, 9),
        )
        assertEquals(withoutHint.requests, withHint.requests)
        assertEquals(listOf(2, 3), withHint.pinWrites)
        assertEquals(3, withHint.selectorPin)
    }

    @Test fun uacControlRequestBuildersForMuteAndVolume() {
        assertEquals(0x01, UsbAudioProtocol.CS_MUTE)
        assertEquals(0x02, UsbAudioProtocol.CS_VOLUME)

        // Mute SET_CUR: bmRequestType = 0x21, bRequest = 0x01, wValue = (CS_MUTE << 8) | ch, wLength = 1
        val muteSet = UsbAudioProtocol.buildMuteRequest(write = true, unitId = 7, interfaceNumber = 1, channel = 2, uacVersion = 2)
        assertEquals(0x21, muteSet.requestType)
        assertEquals(0x01, muteSet.request)
        assertEquals((0x01 shl 8) or 2, muteSet.value)
        assertEquals((7 shl 8) or 1, muteSet.index)
        assertEquals(1, muteSet.length)

        // Mute GET_CUR UAC2: bmRequestType = 0xA1, bRequest = 0x81
        val muteGetUac2 = UsbAudioProtocol.buildMuteRequest(write = false, unitId = 7, interfaceNumber = 1, channel = 0, uacVersion = 2)
        assertEquals(0xA1, muteGetUac2.requestType)
        assertEquals(0x81, muteGetUac2.request)
        assertEquals(0x0100, muteGetUac2.value)
        assertEquals((7 shl 8) or 1, muteGetUac2.index)
        assertEquals(1, muteGetUac2.length)

        // Mute GET_CUR UAC1: bmRequestType = 0xA1, bRequest = 0x81
        val muteGetUac1 = UsbAudioProtocol.buildMuteRequest(write = false, unitId = 7, interfaceNumber = 1, channel = 1, uacVersion = 1)
        assertEquals(0x81, muteGetUac1.request)

        // Volume SET_CUR: wValue = (CS_VOLUME << 8) | ch, wLength = 2
        val volSet = UsbAudioProtocol.buildVolumeRequest(write = true, unitId = 7, interfaceNumber = 1, channel = 1, uacVersion = 2)
        assertEquals(0x21, volSet.requestType)
        assertEquals(0x01, volSet.request)
        assertEquals((0x02 shl 8) or 1, volSet.value)
        assertEquals((7 shl 8) or 1, volSet.index)
        assertEquals(2, volSet.length)

        // Volume GET_CUR: bmRequestType = 0xA1, bRequest = 0x81, wLength = 2
        val volGet = UsbAudioProtocol.buildVolumeRequest(write = false, unitId = 7, interfaceNumber = 1, channel = 1, uacVersion = 2)
        assertEquals(0xA1, volGet.requestType)
        assertEquals(0x81, volGet.request)
        assertEquals((0x02 shl 8) or 1, volGet.value)
        assertEquals((7 shl 8) or 1, volGet.index)
        assertEquals(2, volGet.length)
    }
}
