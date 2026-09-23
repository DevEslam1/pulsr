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
    )

    /** The AudioStreaming isochronous OUT endpoint used for exclusive playback. */
    data class StreamingEndpoint(
        val address: Int,
        val interfaceNumber: Int,
        val altSetting: Int,
        val maxPacketSize: Int,
    )

    data class Result(
        val uacVersion: Int,
        val volumeUnit: FeatureUnitVolume?,
        val streamingInterface: Int?,
        val streamingEndpoint: StreamingEndpoint? = null,
        val supportedRates: List<Int> = emptyList(),
    ) {
        val hasVolumeControl: Boolean get() = volumeUnit != null
    }

    private const val DESC_INTERFACE = 0x04
    private const val DESC_ENDPOINT = 0x05
    private const val DESC_CS_INTERFACE = 0x24

    private const val CLASS_AUDIO = 0x01
    private const val SUBCLASS_AUDIOCONTROL = 0x01
    private const val SUBCLASS_AUDIOSTREAMING = 0x02

    private const val SUBTYPE_FEATURE_UNIT = 0x06

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
        val supportedRates = mutableListOf<Int>()
        val standardRates = intArrayOf(44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000)

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
                            }
                        }
                    }
                }

                DESC_ENDPOINT -> {
                    // First isochronous OUT endpoint on an AudioStreaming
                    // interface is the exclusive playback target.
                    if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOSTREAMING &&
                        streamingEndpoint == null &&
                        i + OFF_EP_MAX_PACKET + 1 < descriptors.size
                    ) {
                        val address = descriptors[i + OFF_EP_ADDRESS].toInt() and 0xFF
                        val attributes = descriptors[i + OFF_EP_ATTRIBUTES].toInt() and 0xFF
                        val maxPacket =
                            (descriptors[i + OFF_EP_MAX_PACKET].toInt() and 0xFF) or
                                ((descriptors[i + OFF_EP_MAX_PACKET + 1].toInt() and 0xFF) shl 8)
                        if ((attributes and 0x03) == XFER_ISOCHRONOUS &&
                            (address and EP_DIR_IN) == 0
                        ) {
                            streamingEndpoint = StreamingEndpoint(
                                address = address,
                                interfaceNumber = currentAsInterface,
                                altSetting = currentAltSetting,
                                maxPacketSize = maxPacket,
                            )
                        }
                    }
                }

                DESC_CS_INTERFACE -> {
                    // Only Feature Units belonging to an Audio Control interface
                    // are relevant. Byte 2 is the class-specific subtype.
                    if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOCONTROL &&
                        bLength >= 7
                    ) {
                        val subtype = descriptors[i + 2].toInt() and 0xFF
                        if (subtype == SUBTYPE_FEATURE_UNIT && volumeUnit == null) {
                            val unitId = descriptors[i + 3].toInt() and 0xFF
                            // i+4 = bSourceID, i+5 = bControlSize
                            val controlSize = descriptors[i + 5].toInt() and 0xFF
                            if (controlSize in 1..4) {
                                // Master controls start at i+6; number of channels
                                // = (bLength - 7) / bControlSize.
                                val masterStart = i + 6
                                if (masterStart < i + bLength) {
                                    var masterHasVolume = false
                                    var anyHasVolume = false
                                    var channels = 0
                                    var p = masterStart
                                    while (p + controlSize <= i + bLength) {
                                        var vol = false
                                        for (b in 0 until controlSize) {
                                            if ((descriptors[p + b].toInt() and 0xFF) and CONTROL_VOLUME != 0) {
                                                vol = true
                                                break
                                            }
                                        }
                                        if (channels == 0) masterHasVolume = vol
                                        if (vol) anyHasVolume = true
                                        if (channels > 0) { /* per-channel */ }
                                        channels += 1
                                        p += controlSize
                                    }
                                    if (anyHasVolume) {
                                        volumeUnit = FeatureUnitVolume(
                                            unitId = unitId,
                                            interfaceNumber = currentAcInterface,
                                            channels = (channels - 1).coerceAtLeast(0),
                                            volumeOnMaster = masterHasVolume,
                                        )
                                    }
                                }
                            }
                        }
                    } else if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOSTREAMING &&
                        bLength >= 8
                    ) {
                        val subtype = descriptors[i + 2].toInt() and 0xFF
                        if (subtype == 0x02) { // FORMAT_TYPE
                            val formatType = descriptors[i + 3].toInt() and 0xFF
                            if (formatType == 0x01) { // FORMAT_TYPE_I
                                val samFreqType = descriptors[i + 7].toInt() and 0xFF
                                if (samFreqType == 0 && bLength >= 14) {
                                    val lower = (descriptors[i + 8].toInt() and 0xFF) or
                                        ((descriptors[i + 9].toInt() and 0xFF) shl 8) or
                                        ((descriptors[i + 10].toInt() and 0xFF) shl 16)
                                    val upper = (descriptors[i + 11].toInt() and 0xFF) or
                                        ((descriptors[i + 12].toInt() and 0xFF) shl 8) or
                                        ((descriptors[i + 13].toInt() and 0xFF) shl 16)
                                    for (r in standardRates) {
                                        if (r in lower..upper) supportedRates.add(r)
                                    }
                                } else if (samFreqType > 0) {
                                    for (k in 0 until samFreqType) {
                                        val offset = i + 8 + 3 * k
                                        if (offset + 3 <= i + bLength) {
                                            val r = (descriptors[offset].toInt() and 0xFF) or
                                                ((descriptors[offset + 1].toInt() and 0xFF) shl 8) or
                                                ((descriptors[offset + 2].toInt() and 0xFF) shl 16)
                                            if (r > 0) supportedRates.add(r)
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

        return Result(
            uacVersion = uacVersion,
            volumeUnit = volumeUnit,
            streamingInterface = streamingInterface,
            streamingEndpoint = streamingEndpoint,
            supportedRates = supportedRates.distinct().sorted(),
        )
    }
}
