package com.pulsr.music

/**
 * Pure parser for USB Audio Class (UAC1/UAC2/UAC3) Audio Control
 * class-specific descriptors.
 *
 * From a raw configuration descriptor stream it extracts:
 *  - the advertised UAC version (from the Audio Control interface protocol),
 *  - the first Feature Unit that carries a Volume control (needed to issue
 *    GET/SET_CUR volume class requests), and
 *  - the first AudioStreaming interface number (used for the optional
 *    exclusive interface claim).
 *
 * Framework-free and bounds-checked so it can be unit tested on the JVM and can
 * never throw on a malformed/truncated descriptor blob.
 */
object UsbAudioControlParser {

    const val UAC_NONE = 0
    const val UAC1 = 1
    const val UAC2 = 2
    const val UAC3 = 3

    data class FeatureUnitVolume(
        val unitId: Int,
        /** Audio Control interface number (wIndex low byte for class requests). */
        val interfaceNumber: Int,
        val channels: Int,
        val volumeOnMaster: Boolean,
        val writableChannels: List<Int> = if (volumeOnMaster) listOf(0) else emptyList(),
    ) {
        val controlChannels: List<Int> get() = when {
            0 in writableChannels -> listOf(0)
            channels > 0 && (1..channels).all { it in writableChannels } -> (1..channels).toList()
            else -> emptyList()
        }
    }

    /** The AudioStreaming isochronous OUT endpoint used for exclusive playback. */
    data class StreamingEndpoint(
        val address: Int,
        val interfaceNumber: Int,
        val altSetting: Int,
        val maxPacketSize: Int,
    )

    /**
     * A UAC2 Clock Source entity. Needed to issue the Clock-Source
     * `SET_CUR(CS_SAM_FREQ_CONTROL)` request that actually programs the DAC's
     * sample clock before streaming (UAC1 has no clock entity; its rate is set
     * on the streaming endpoint instead).
     */
    data class ClockSource(
        /** bClockID of the Clock Source entity (wIndex high byte of the request). */
        val clockId: Int,
        /** AudioControl interface number (wIndex low byte of the request). */
        val controlInterface: Int,
        /**
         * True when the Clock Frequency Control is host read/write (bmControls
         * D1..D0 == 0b11). When it is read-only (0b01) the clock exposes a
         * single fixed rate and SET_CUR must NOT be issued.
         */
        val frequencyProgrammable: Boolean,
    )

    /**
     * One AudioStreaming alternate setting's FORMAT_TYPE_I wire format. Lets the
     * caller SELECT the alt setting whose subslot size / bit resolution matches
     * the requested bit depth instead of blindly using the first iso-OUT
     * endpoint.
     */
    data class AltSettingFormat(
        val interfaceNumber: Int,
        val altSetting: Int,
        /** Isochronous OUT endpoint address exposed by this alt setting. */
        val endpointAddress: Int,
        val maxPacketSize: Int,
        /** Bytes per audio subslot on the wire: UAC2 bSubslotSize / UAC1 bSubframeSize. */
        val subslotSize: Int,
        /** Valid bits per sample: bBitResolution. */
        val bitResolution: Int,
        /** bNrChannels where advertised (UAC1 FORMAT_TYPE_I / UAC2 AS_GENERAL), else 0. */
        val channels: Int,
        /** Async feedback IN endpoint address on this alt setting, if any. */
        val feedbackEndpointAddress: Int?,
        /** Discrete/continuous rates declared by this alt (UAC1); empty for UAC2. */
        val supportedRates: List<Int>,
    )

    data class Result(
        val uacVersion: Int,
        val volumeUnit: FeatureUnitVolume?,
        val streamingInterface: Int?,
        val streamingEndpoint: StreamingEndpoint? = null,
        val feedbackEndpoint: StreamingEndpoint? = null,
        val supportedRates: List<Int> = emptyList(),
        val clockSource: ClockSource? = null,
        val altSettingFormats: List<AltSettingFormat> = emptyList(),
    ) {
        val hasVolumeControl: Boolean get() = volumeUnit?.controlChannels?.isNotEmpty() == true
        val hasFeedbackEndpoint: Boolean get() = feedbackEndpoint != null
    }

    private const val DESC_INTERFACE = 0x04
    private const val DESC_ENDPOINT = 0x05
    private const val DESC_CS_INTERFACE = 0x24

    private const val CLASS_AUDIO = 0x01
    private const val SUBCLASS_AUDIOCONTROL = 0x01
    private const val SUBCLASS_AUDIOSTREAMING = 0x02

    private const val SUBTYPE_FEATURE_UNIT = 0x06

    /** UAC2 Audio Control CLOCK_SOURCE class-specific subtype. */
    private const val SUBTYPE_CLOCK_SOURCE = 0x0B

    /** AudioStreaming class-specific subtypes / format identifiers. */
    private const val SUBTYPE_AS_GENERAL = 0x01
    private const val SUBTYPE_FORMAT_TYPE = 0x02
    private const val FORMAT_TYPE_I = 0x01
    private const val FORMAT_TYPE_III = 0x03

    /** Clock Source bmControls D1..D0 (Clock Frequency Control); 0b11 == read/write. */
    private const val CLOCK_FREQ_CONTROL_MASK = 0x03
    private const val CLOCK_FREQ_CONTROL_RW = 0x03

    /** D1 of a Feature Unit control bitmap = Volume. */
    private const val CONTROL_VOLUME = 0x02

    /** Standard interface descriptor offsets. */
    private const val OFF_IF_CLASS = 5
    private const val OFF_IF_SUBCLASS = 6
    private const val OFF_IF_PROTOCOL = 7
    private const val OFF_IF_NUMBER = 2
    private const val OFF_IF_ALT = 3

    /** Standard endpoint descriptor offsets + isochronous transfer type. */
    private const val OFF_EP_ADDRESS = 2
    private const val OFF_EP_ATTRIBUTES = 3
    private const val OFF_EP_MAX_PACKET = 4
    private const val XFER_ISOCHRONOUS = 0x01
    private const val EP_DIR_IN = 0x80

    fun parse(descriptors: ByteArray?): Result {
        if (descriptors == null || descriptors.size < 8) {
            return Result(UAC_NONE, null, null)
        }
        var uacVersion = UAC_NONE
        var currentAcInterface = -1
        var currentAsInterface = -1
        var currentClass = 0
        var currentSubclass = 0
        var currentAltSetting = 0
        var volumeUnit: FeatureUnitVolume? = null
        var streamingInterface: Int? = null
        var streamingEndpoint: StreamingEndpoint? = null
        var feedbackEndpoint: StreamingEndpoint? = null
        var clockSource: ClockSource? = null
        val supportedRates = mutableListOf<Int>()
        val standardRates = intArrayOf(44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000)

        // Per-alt-setting FORMAT_TYPE_I accumulators. Descriptors for one alt
        // setting arrive as: AudioStreaming INTERFACE -> AS_GENERAL -> FORMAT_TYPE
        // -> iso OUT endpoint [-> feedback IN endpoint]. We gather them here and
        // flush a completed AltSettingFormat when the next INTERFACE descriptor
        // (or end of blob) closes the current alt setting.
        val altSettingFormats = mutableListOf<AltSettingFormat>()
        var curAsAlt = false
        var curIface = -1
        var curAlt = 0
        var curSubslot = 0
        var curBitRes = 0
        var curChannels = 0
        var curOutEp = -1
        var curOutMaxPacket = 0
        var curFbEp = -1
        val curRates = mutableListOf<Int>()

        fun flushAltSetting() {
            // A usable alt setting must expose both an iso OUT endpoint and a
            // decoded FORMAT_TYPE_I subslot size.
            if (curAsAlt && curOutEp >= 0 && curSubslot in 1..4) {
                altSettingFormats.add(
                    AltSettingFormat(
                        interfaceNumber = curIface,
                        altSetting = curAlt,
                        endpointAddress = curOutEp,
                        maxPacketSize = curOutMaxPacket,
                        subslotSize = curSubslot,
                        bitResolution = curBitRes,
                        channels = curChannels,
                        feedbackEndpointAddress = if (curFbEp >= 0) curFbEp else null,
                        supportedRates = curRates.distinct().sorted(),
                    ),
                )
            }
            curAsAlt = false
            curOutEp = -1
            curOutMaxPacket = 0
            curFbEp = -1
            curSubslot = 0
            curBitRes = 0
            curChannels = 0
            curRates.clear()
        }

        var i = 0
        while (i + 2 <= descriptors.size) {
            val bLength = descriptors[i].toInt() and 0xFF
            if (bLength < 2 || i + bLength > descriptors.size) {
                i += 1 // malformed / truncated: resync one byte at a time
                continue
            }
            val bType = descriptors[i + 1].toInt() and 0xFF

            when (bType) {
                DESC_INTERFACE -> {
                    if (bLength < 9) {
                        flushAltSetting()
                        currentClass = 0
                        currentSubclass = 0
                        i += bLength
                        continue
                    }
                    // A new interface descriptor closes the previous alt setting:
                    // flush whatever FORMAT_TYPE_I + endpoints we accumulated.
                    flushAltSetting()
                    val ifaceNumber = descriptors[i + OFF_IF_NUMBER].toInt() and 0xFF
                    currentClass = descriptors[i + OFF_IF_CLASS].toInt() and 0xFF
                    currentSubclass = descriptors[i + OFF_IF_SUBCLASS].toInt() and 0xFF
                    currentAltSetting = descriptors[i + OFF_IF_ALT].toInt() and 0xFF
                    if (currentClass == CLASS_AUDIO) {
                        when (currentSubclass) {
                            SUBCLASS_AUDIOCONTROL -> {
                                currentAcInterface = ifaceNumber
                                val protocol =
                                    descriptors[i + OFF_IF_PROTOCOL].toInt() and 0xFF
                                val v = when (protocol) {
                                    0x20 -> UAC2
                                    0x30 -> UAC3
                                    0x00 -> UAC1
                                    else -> UAC_NONE
                                }
                                if (v > uacVersion) uacVersion = v
                            }
                            SUBCLASS_AUDIOSTREAMING -> {
                                currentAsInterface = ifaceNumber
                                if (streamingInterface == null) streamingInterface = ifaceNumber
                                // Begin accumulating this alt setting's format.
                                curAsAlt = true
                                curIface = ifaceNumber
                                curAlt = currentAltSetting
                            }
                        }
                    }
                }

                DESC_ENDPOINT -> {
                    // First isochronous OUT endpoint on an AudioStreaming
                    // interface is the exclusive playback target. Also detect
                    // asynchronous feedback IN endpoints (Pillar 3).
                    if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOSTREAMING &&
                        bLength >= 7
                    ) {
                        val address = descriptors[i + OFF_EP_ADDRESS].toInt() and 0xFF
                        val attributes = descriptors[i + OFF_EP_ATTRIBUTES].toInt() and 0xFF
                        val maxPacket =
                            (descriptors[i + OFF_EP_MAX_PACKET].toInt() and 0xFF) or
                                ((descriptors[i + OFF_EP_MAX_PACKET + 1].toInt() and 0xFF) shl 8)
                        val isIso = (attributes and 0x03) == XFER_ISOCHRONOUS
                        val isOut = (address and EP_DIR_IN) == 0
                        val isIn = (address and EP_DIR_IN) != 0

                        if (isIso && isOut) {
                            // Record the first iso-OUT endpoint of THIS alt
                            // setting (per-alt format enumeration, FIX 3) ...
                            if (curOutEp < 0) {
                                curOutEp = address
                                curOutMaxPacket = maxPacket
                            }
                            // ... and the first iso-OUT across the whole config
                            // (legacy single-endpoint fallback target).
                            if (streamingEndpoint == null) {
                                streamingEndpoint = StreamingEndpoint(
                                    address = address,
                                    interfaceNumber = currentAsInterface,
                                    altSetting = currentAltSetting,
                                    maxPacketSize = maxPacket,
                                )
                            }
                        } else if (isIso && isIn) {
                            val usage = (attributes and 0x30)
                            val synch = (attributes and 0x0C)
                            // Feedback IN endpoints are tiny (3-4 bytes) and/or
                            // flagged as feedback usage / asynchronous sync.
                            val looksLikeFeedback =
                                usage == 0x10 || synch == 0x04 || maxPacket in 3..8
                            if (looksLikeFeedback) {
                                if (curFbEp < 0) curFbEp = address
                                if (feedbackEndpoint == null) {
                                    feedbackEndpoint = StreamingEndpoint(
                                        address = address,
                                        interfaceNumber = currentAsInterface,
                                        altSetting = currentAltSetting,
                                        maxPacketSize = maxPacket,
                                    )
                                }
                            }
                        }
                    }
                }

                DESC_CS_INTERFACE -> {
                    // Class-specific interface descriptors. Byte 2 is the
                    // class-specific subtype. On an Audio Control interface we
                    // look for Feature Units (volume) and Clock Sources (UAC2
                    // sample-clock programming); on an AudioStreaming interface
                    // we decode the per-alt FORMAT_TYPE_I wire format.
                    if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOCONTROL &&
                        bLength >= 4
                    ) {
                        val subtype = descriptors[i + 2].toInt() and 0xFF
                        if (subtype == SUBTYPE_FEATURE_UNIT && volumeUnit == null && bLength >= 7) {
                            val unitId = descriptors[i + 3].toInt() and 0xFF
                            val uac2 = uacVersion == UAC2
                            val controlSize = if (uac2) 4 else descriptors[i + 5].toInt() and 0xFF
                            val prefix = if (uac2) 5 else 6
                            val bitmapBytes = bLength - prefix - 1 // Exclude iFeature.
                            if (uacVersion in UAC1..UAC2 && unitId > 0 &&
                                controlSize in 1..4 && bitmapBytes >= controlSize &&
                                bitmapBytes % controlSize == 0
                            ) {
                                val count = bitmapBytes / controlSize
                                val writable = (0 until count).filter { channel ->
                                    val low = descriptors[i + prefix + channel * controlSize].toInt() and 0xFF
                                    if (uac2) ((low shr 2) and 3) == 3 else (low and CONTROL_VOLUME) != 0
                                }
                                val candidate = FeatureUnitVolume(
                                    unitId, currentAcInterface, count - 1, 0 in writable, writable,
                                )
                                if (candidate.controlChannels.isNotEmpty()) volumeUnit = candidate
                            }
                        } else if (subtype == SUBTYPE_CLOCK_SOURCE &&
                            clockSource == null && bLength >= 6
                        ) {
                            // UAC2 Clock Source entity:
                            //   i+3 bClockID, i+4 bmAttributes, i+5 bmControls.
                            // bmControls D1..D0 == 0b11 => the sample-frequency
                            // control is host read/write, so SET_CUR may program
                            // it; 0b01 => read-only single fixed rate (guarded by
                            // the caller so SET_CUR is skipped).
                            val clockId = descriptors[i + 3].toInt() and 0xFF
                            val bmControls = descriptors[i + 5].toInt() and 0xFF
                            val programmable =
                                (bmControls and CLOCK_FREQ_CONTROL_MASK) == CLOCK_FREQ_CONTROL_RW
                            clockSource = ClockSource(
                                clockId = clockId,
                                controlInterface = currentAcInterface,
                                frequencyProgrammable = programmable,
                            )
                        }
                    } else if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOSTREAMING &&
                        bLength >= 4
                    ) {
                        val subtype = descriptors[i + 2].toInt() and 0xFF
                        if (subtype == SUBTYPE_AS_GENERAL && uacVersion == UAC2 && bLength >= 11) {
                            // UAC2 AS_GENERAL carries bNrChannels at i+10 (UAC1
                            // keeps the channel count in FORMAT_TYPE_I instead).
                            curChannels = descriptors[i + 10].toInt() and 0xFF
                        } else if (subtype == SUBTYPE_FORMAT_TYPE) {
                            val formatType = descriptors[i + 3].toInt() and 0xFF
                            if (formatType == FORMAT_TYPE_I) {
                                if (uacVersion == UAC2) {
                                    // UAC2 FORMAT_TYPE_I is 6 bytes: bSubslotSize
                                    // @ i+4, bBitResolution @ i+5. Sample rates
                                    // live in the Clock Source, not here.
                                    if (bLength >= 6) {
                                        curSubslot = descriptors[i + 4].toInt() and 0xFF
                                        curBitRes = descriptors[i + 5].toInt() and 0xFF
                                    }
                                } else if (bLength >= 8) {
                                    // UAC1 / unknown FORMAT_TYPE_I: bNrChannels
                                    // @ i+4, bSubframeSize @ i+5, bBitResolution
                                    // @ i+6, bSamFreqType @ i+7.
                                    curChannels = descriptors[i + 4].toInt() and 0xFF
                                    curSubslot = descriptors[i + 5].toInt() and 0xFF
                                    curBitRes = descriptors[i + 6].toInt() and 0xFF
                                }
                            }
                            // Sample-rate table: UAC1 / unknown FORMAT_TYPE_I and
                            // FORMAT_TYPE_III embed rates after bSamFreqType @ i+7.
                            if ((formatType == FORMAT_TYPE_I || formatType == FORMAT_TYPE_III) &&
                                uacVersion != UAC2 && bLength >= 8
                            ) {
                                val samFreqType = descriptors[i + 7].toInt() and 0xFF
                                if (samFreqType == 0 && bLength >= 14) {
                                    val lower = (descriptors[i + 8].toInt() and 0xFF) or
                                        ((descriptors[i + 9].toInt() and 0xFF) shl 8) or
                                        ((descriptors[i + 10].toInt() and 0xFF) shl 16)
                                    val upper = (descriptors[i + 11].toInt() and 0xFF) or
                                        ((descriptors[i + 12].toInt() and 0xFF) shl 8) or
                                        ((descriptors[i + 13].toInt() and 0xFF) shl 16)
                                    for (r in standardRates) {
                                        if (r in lower..upper) {
                                            supportedRates.add(r)
                                            curRates.add(r)
                                        }
                                    }
                                } else if (samFreqType > 0) {
                                    for (k in 0 until samFreqType) {
                                        val offset = i + 8 + 3 * k
                                        if (offset + 3 <= i + bLength) {
                                            val r = (descriptors[offset].toInt() and 0xFF) or
                                                ((descriptors[offset + 1].toInt() and 0xFF) shl 8) or
                                                ((descriptors[offset + 2].toInt() and 0xFF) shl 16)
                                            if (r > 0) {
                                                supportedRates.add(r)
                                                curRates.add(r)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            i += bLength
        }
        // Flush the final alt setting (no trailing INTERFACE descriptor closes it).
        flushAltSetting()

        return Result(
            uacVersion = uacVersion,
            volumeUnit = volumeUnit,
            streamingInterface = streamingInterface,
            streamingEndpoint = streamingEndpoint,
            feedbackEndpoint = feedbackEndpoint,
            supportedRates = supportedRates.distinct().sorted(),
            clockSource = clockSource,
            altSettingFormats = altSettingFormats.toList(),
        )
    }
}

internal fun interface UsbControlTransfer {
    fun transfer(type: Int, request: Int, value: Int, index: Int, buffer: ByteArray): Int
}

internal class UsbHardwareVolume(
    private val version: Int,
    private val unit: UsbAudioControlParser.FeatureUnitVolume,
    private val transport: UsbControlTransfer,
) {
    private data class Range(val min: Int, val max: Int, val res: Int)
    private var ranges: Map<Int, List<Range>> = emptyMap()
    private var expected: Map<Int, Int>? = null
    var currentDb: Double? = null
        private set
    val ready: Boolean get() = ranges.isNotEmpty() && currentDb != null
    val applied: Boolean get() = ready && expected != null
    val minDb: Double? get() = ranges.values.maxOfOrNull { rs -> rs.minOf { it.min } }?.div(256.0)
    val maxDb: Double? get() = ranges.values.minOfOrNull { rs -> rs.maxOf { it.max } }?.div(256.0)

    fun invalidate() {
        ranges = emptyMap()
        expected = null
        currentDb = null
    }

    private fun transfer(request: Int, channel: Int, data: ByteArray, write: Boolean = false): Boolean = try {
        transport.transfer(if (write) 0x21 else 0xA1, request, 0x200 or channel,
            (unit.unitId shl 8) or unit.interfaceNumber, data) == data.size
    } catch (_: Exception) { false }

    private fun unsigned(data: ByteArray, offset: Int = 0): Int =
        (data[offset].toInt() and 255) or ((data[offset + 1].toInt() and 255) shl 8)

    private fun signed(data: ByteArray, offset: Int = 0): Int = unsigned(data, offset).toShort().toInt()

    private fun read(request: Int, channel: Int, signed: Boolean = true): Int? {
        val data = ByteArray(2)
        if (!transfer(request, channel, data)) return null
        return if (signed) signed(data) else unsigned(data)
    }

    private fun readRanges(channel: Int): List<Range>? {
        val result = when (version) {
            UsbAudioControlParser.UAC1 -> listOf(Range(
                read(0x82, channel) ?: return null,
                read(0x83, channel) ?: return null,
                read(0x84, channel, false) ?: return null,
            ))
            UsbAudioControlParser.UAC2 -> {
                val countBytes = ByteArray(2)
                if (!transfer(0x02, channel, countBytes)) return null
                val count = unsigned(countBytes)
                // Bound the device-supplied allocation to a control-transfer payload.
                if (count !in 1..1024) return null
                val data = ByteArray(2 + count * 6)
                if (!transfer(0x02, channel, data) || unsigned(data) != count) return null
                (0 until count).map { n ->
                    val p = 2 + n * 6
                    Range(signed(data, p), signed(data, p + 2), unsigned(data, p + 4))
                }
            }
            else -> return null
        }
        return result.takeIf { rs -> rs.all { it.min > -32768 && it.min <= it.max && it.res > 0 } }
    }

    fun refresh(): Boolean {
        fun fail(): Boolean { invalidate(); return false }
        val channels = unit.controlChannels
        if (channels.isEmpty()) return fail()
        val discovered = mutableMapOf<Int, List<Range>>()
        val values = mutableMapOf<Int, Int>()
        for (channel in channels) {
            val rs = readRanges(channel) ?: return fail()
            val raw = read(if (version == 2) 0x01 else 0x81, channel) ?: return fail()
            if (rs.none { raw in it.min..it.max }) return fail()
            discovered[channel] = rs
            values[channel] = raw
        }
        ranges = discovered
        currentDb = values.values.maxOrNull()!! / 256.0
        if (expected != values) expected = null
        return true
    }

    fun setDb(db: Double): Boolean {
        expected = null
        if (!db.isFinite()) { invalidate(); return false }
        if (!refresh()) return false
        val target = kotlin.math.floor(db * 256.0).coerceAtMost(32767.0)
        val targets = mutableMapOf<Int, Int>()
        for ((channel, rs) in ranges) {
            // Round toward attenuation; never raise a request below the supported minimum.
            targets[channel] = rs.filter { it.min <= target }.maxOfOrNull { r ->
                r.min + ((minOf(target, r.max.toDouble()) - r.min) / r.res).toInt() * r.res
            } ?: return false
        }
        for ((channel, raw) in targets) {
            val data = byteArrayOf(raw.toByte(), (raw shr 8).toByte())
            if (!transfer(0x01, channel, data, write = true)) { invalidate(); return false }
        }
        expected = targets
        if (!refresh()) return false
        return applied
    }
}

internal object UsbAudioProtocol {
    fun mixerConfirmed(applied: Boolean, routedDevice: Int, rate: Int, encoding: Int, mixerRate: Int, mixerEncoding: Int): Boolean =
        applied && routedDevice > 0 && rate > 0 && encoding > 0 && rate == mixerRate && encoding == mixerEncoding

    data class StreamFormat(val sampleRate: Int, val bitDepth: Int, val channels: Int) {
        fun matches(rate: Int, depth: Int, count: Int, nativeActive: Boolean): Boolean =
            nativeActive && sampleRate == rate && bitDepth == depth && channels == count
    }

    fun selectFormat(parsed: UsbAudioControlParser.Result, rate: Int, depth: Int, channels: Int): UsbAudioControlParser.AltSettingFormat? {
        if (rate <= 0 || channels <= 0 || depth !in listOf(16, 24, 32) || parsed.uacVersion !in 1..2) return null
        return parsed.altSettingFormats.filter { fmt ->
            (parsed.streamingInterface == null || fmt.interfaceNumber == parsed.streamingInterface) &&
                fmt.altSetting > 0 && fmt.channels == channels &&
                fmt.subslotSize in 2..4 && fmt.bitResolution in depth..(fmt.subslotSize * 8) &&
                (if (parsed.uacVersion == 2) true else rate in fmt.supportedRates)
        }.minWithOrNull(compareBy({ it.bitResolution }, { it.subslotSize }))
    }

    fun setSampleRate(
        transport: UsbControlTransfer, version: Int, clock: UsbAudioControlParser.ClockSource?,
        endpoint: Int, rate: Int, fixedUac1: Boolean,
    ): Boolean {
        if (rate <= 0 || version !in 1..2 || (version == 2 && clock == null)) return false
        val size = if (version == 2) 4 else 3
        if (size == 3 && rate > 0xFFFFFF) return false
        val index = if (version == 2) (clock!!.clockId shl 8) or clock.controlInterface else endpoint
        val setType = if (version == 2) 0x21 else 0x22
        val programmable = if (version == 2) clock!!.frequencyProgrammable else !fixedUac1
        return try {
            if (programmable) {
                val data = ByteArray(size) { (rate shr (8 * it)).toByte() }
                if (transport.transfer(setType, 1, 0x100, index, data) != size) return false
            }
            val data = ByteArray(size)
            if (transport.transfer(setType or 0x80, if (version == 2) 1 else 0x81, 0x100, index, data) != size) return false
            val actual = data.indices.fold(0L) { acc, i -> acc or ((data[i].toLong() and 255) shl (8 * i)) }
            actual == rate.toLong()
        } catch (_: Exception) { false }
    }
}
