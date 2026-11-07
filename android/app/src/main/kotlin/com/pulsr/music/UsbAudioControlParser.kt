package com.pulsr.music

/**
 * Pure parser for USB Audio Class (UAC1/UAC2/UAC3) Audio Control
 * class-specific descriptors.
 *
 * From a raw configuration descriptor stream it extracts:
 *  - the advertised UAC version (from the Audio Control interface protocol),
 *  - the Feature Unit that carries a Volume control **on the playback path**
 *    (needed to issue GET/SET_CUR volume class requests),
 *  - the AudioStreaming interface that owns an isochronous OUT endpoint
 *    (a capture-only interface must never become the playback target),
 *  - the Clock Source that actually feeds that streaming interface, resolved
 *    through the terminal / clock-selector topology instead of by descriptor
 *    order.
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
     *
     * When a device has several Clock Sources, [Result.clockSource] is the one
     * the playback stream is wired to (terminal -> clock, through a Clock
     * Selector when the device uses one), not simply the first entity in the
     * descriptor list.
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
        /** Every Clock Source entity found, in descriptor order. */
        val clockSources: List<ClockSource> = emptyList(),
        /** AudioControl interface number (wIndex low byte), or -1 when absent. */
        val controlInterface: Int = -1,
        /** bTerminalLink of the playback AudioStreaming interface, if any. */
        val playbackTerminalId: Int? = null,
        /** Terminal ID -> bCSourceID (UAC2 clock entity wired to a terminal). */
        val terminalClockIds: Map<Int, Int> = emptyMap(),
        /** Clock Selector ID -> its input clock entity IDs, in pin order. */
        val clockSelectorInputs: Map<Int, List<Int>> = emptyMap(),
        /** Clock Multiplier ID -> the clock entity ID it multiplies. */
        val clockMultiplierSources: Map<Int, Int> = emptyMap(),
    ) {
        val hasVolumeControl: Boolean get() = volumeUnit?.controlChannels?.isNotEmpty() == true
        val hasFeedbackEndpoint: Boolean get() = feedbackEndpoint != null
    }

    private const val DESC_INTERFACE = 0x04
    private const val DESC_ENDPOINT = 0x05
    private const val DESC_CS_INTERFACE = 0x24

    private const val CLASS_AUDIO = 0x01
    private const val CLASS_VENDOR_SPECIFIC = 0xFF
    private const val SUBCLASS_AUDIOCONTROL = 0x01
    private const val SUBCLASS_AUDIOSTREAMING = 0x02

    private const val SUBTYPE_FEATURE_UNIT = 0x06

    // AudioControl entity subtypes (UAC1 and UAC2 share the numbering for
    // units/terminals; the clock entities only exist from UAC2 on).
    private const val SUBTYPE_INPUT_TERMINAL = 0x02
    private const val SUBTYPE_OUTPUT_TERMINAL = 0x03
    private const val SUBTYPE_SELECTOR_UNIT = 0x05

    /**
     * UAC2 Audio Control CLOCK_SOURCE class-specific subtype: 0x0A, matching
     * the Audio Class 2 definition (kernel `UAC2_CLOCK_SOURCE`). 0x0B is
     * CLOCK_SELECTOR, whose own clock ID is only an alias for one of the
     * Clock Sources connected to its inputs.
     */
    private const val SUBTYPE_CLOCK_SOURCE = 0x0A
    private const val SUBTYPE_CLOCK_SELECTOR = 0x0B

    /**
     * UAC2 CLOCK_MULTIPLIER (4.7.2.13): bClockID, bSourceID. Like a selector it
     * is an alias — the programmable clock is the source it multiplies.
     */
    private const val SUBTYPE_CLOCK_MULTIPLIER = 0x0C

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

    /** Guard against a descriptor that points an entity back at itself. */
    private const val MAX_ENTITY_HOPS = 64

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

    /**
     * True when the interface's class/subclass/protocol triple really describes
     * a USB Audio Class streaming (0x02) or control (0x01) interface.
     *
     * A vendor-specific (0xFF) class only counts when the subclass and protocol
     * also look like audio: several non-audio accessories (ADB among them)
     * publish class 0xFF, and accepting any of them as "a DAC" made the app
     * open the wrong device.
     */
    fun isAudioFunctionInterface(
        ifaceClass: Int,
        ifaceSubclass: Int,
        ifaceProtocol: Int,
    ): Boolean =
        (ifaceSubclass == SUBCLASS_AUDIOCONTROL || ifaceSubclass == SUBCLASS_AUDIOSTREAMING) &&
            (ifaceClass == CLASS_AUDIO || looksLikeVendorAudio(ifaceClass, ifaceProtocol))

    fun isAudioStreamingInterface(
        ifaceClass: Int,
        ifaceSubclass: Int,
        ifaceProtocol: Int,
    ): Boolean = ifaceSubclass == SUBCLASS_AUDIOSTREAMING &&
        (ifaceClass == CLASS_AUDIO || looksLikeVendorAudio(ifaceClass, ifaceProtocol))

    fun isAudioControlInterface(
        ifaceClass: Int,
        ifaceSubclass: Int,
        ifaceProtocol: Int,
    ): Boolean = ifaceSubclass == SUBCLASS_AUDIOCONTROL &&
        (ifaceClass == CLASS_AUDIO || looksLikeVendorAudio(ifaceClass, ifaceProtocol))

    /**
     * Vendor-specific interfaces are audio only when the protocol agrees: the
     * subclass alone (0x01/0x02) is shared with CDC and other classes, and
     * class 0xFF alone is shared with ADB and other accessories.
     */
    private fun looksLikeVendorAudio(ifaceClass: Int, ifaceProtocol: Int): Boolean =
        ifaceClass == CLASS_VENDOR_SPECIFIC &&
            (ifaceProtocol == 0x00 || ifaceProtocol == 0x20 || ifaceProtocol == 0x30)

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
        val supportedRates = mutableListOf<Int>()
        val standardRates = intArrayOf(44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000)

        // AudioControl topology, used to decide which entities belong to the
        // playback path instead of to a capture (microphone) path:
        //  - clockSources / clockSelectorInputs: the clock graph,
        //  - entitySourceIds: entity or terminal ID -> the ID feeding it,
        //  - terminalClockIds: terminal ID -> bCSourceID (UAC2 only),
        //  - streamingTerminalLinks: AudioStreaming interface -> bTerminalLink,
        //  - volumeCandidates: every Feature Unit with a writable volume.
        val clockSources = mutableListOf<ClockSource>()
        val clockSelectorInputs = mutableMapOf<Int, MutableList<Int>>()
        val clockMultiplierSources = mutableMapOf<Int, Int>()
        val entitySourceIds = mutableMapOf<Int, Int>()
        val terminalClockIds = mutableMapOf<Int, Int>()
        val streamingTerminalLinks = mutableMapOf<Int, Int>()
        val volumeCandidates = mutableListOf<FeatureUnitVolume>()

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
                                // The playback interface is only known once an
                                // isochronous OUT endpoint shows up below: a
                                // combo DAC that lists its capture interface
                                // first must not become the streaming target.
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
                            // First isochronous OUT endpoint seen anywhere in
                            // the configuration defines the playback target:
                            // its interface, not "the first AudioStreaming
                            // interface", is the one worth claiming/streaming.
                            if (streamingInterface == null) {
                                streamingInterface = currentAsInterface
                            }
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
                            val feedbackUsage = usage == 0x10
                            val maxPacketIsFeedbackSized = maxPacket in 3..4
                            // An IN endpoint only carries async feedback for a
                            // stream that has an isochronous OUT endpoint in the
                            // same alt setting. Without that requirement an
                            // ordinary asynchronous *capture* data endpoint
                            // (attrs 0x04..0x0C) was mistaken for the feedback
                            // pipe of the DAC.
                            val looksLikeFeedback = curOutEp >= 0 &&
                                (feedbackUsage || maxPacketIsFeedbackSized)
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
                        val uac2ClockTopology = uacVersion == UAC2

                        // Entity ID -> the entity that feeds it (bSourceID), so
                        // the playback path can be walked backwards from the
                        // terminal an AudioStreaming interface is linked to.
                        if (subtype == SUBTYPE_FEATURE_UNIT && bLength >= 5) {
                            val unitId = descriptors[i + 3].toInt() and 0xFF
                            val sourceId = descriptors[i + 4].toInt() and 0xFF
                            if (unitId > 0 && sourceId > 0) entitySourceIds[unitId] = sourceId
                        } else if (subtype == SUBTYPE_OUTPUT_TERMINAL && bLength >= 9) {
                            val terminalId = descriptors[i + 3].toInt() and 0xFF
                            val sourceId = descriptors[i + 7].toInt() and 0xFF
                            if (terminalId > 0) {
                                if (sourceId > 0) entitySourceIds[terminalId] = sourceId
                                // UAC2 OUTPUT_TERMINAL adds bCSourceID at i+8.
                                if (uac2ClockTopology && bLength >= 10) {
                                    val clockId = descriptors[i + 8].toInt() and 0xFF
                                    if (clockId > 0) terminalClockIds[terminalId] = clockId
                                }
                            }
                        } else if (subtype == SUBTYPE_INPUT_TERMINAL &&
                            bLength >= 8 && uac2ClockTopology
                        ) {
                            // UAC2 INPUT_TERMINAL carries bCSourceID at i+7.
                            val terminalId = descriptors[i + 3].toInt() and 0xFF
                            val clockId = descriptors[i + 7].toInt() and 0xFF
                            if (terminalId > 0 && clockId > 0) {
                                terminalClockIds[terminalId] = clockId
                            }
                        } else if (subtype == SUBTYPE_SELECTOR_UNIT && bLength >= 6) {
                            // UAC1/UAC2 selector: bUnitID, bNr(In)Pins,
                            // baSourceID[] ... take the first input as the
                            // traversal edge.
                            val unitId = descriptors[i + 3].toInt() and 0xFF
                            val sourceId = descriptors[i + 5].toInt() and 0xFF
                            if (unitId > 0 && sourceId > 0) entitySourceIds[unitId] = sourceId
                        }

                        if (subtype == SUBTYPE_FEATURE_UNIT && bLength >= 7) {
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
                                if (candidate.controlChannels.isNotEmpty()) {
                                    volumeCandidates.add(candidate)
                                }
                            }
                        } else if (subtype == SUBTYPE_CLOCK_SOURCE &&
                            uac2ClockTopology && bLength >= 6
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
                            if (clockId > 0 &&
                                clockSources.none { it.clockId == clockId }
                            ) {
                                clockSources.add(
                                    ClockSource(
                                        clockId = clockId,
                                        controlInterface = currentAcInterface,
                                        frequencyProgrammable = programmable,
                                    ),
                                )
                            }
                        } else if (subtype == SUBTYPE_CLOCK_SELECTOR &&
                            uac2ClockTopology && bLength >= 6
                        ) {
                            // Clock Selector: bClockID, bNrInPins, baCSourceID[]
                            // (UAC2 4.7.2.11). The stream is clocked by one of
                            // those inputs, chosen at runtime.
                            val selectorClockId = descriptors[i + 3].toInt() and 0xFF
                            val pinCount = descriptors[i + 4].toInt() and 0xFF
                            if (selectorClockId > 0 && pinCount in 1..32) {
                                val inputs =
                                    clockSelectorInputs.getOrPut(selectorClockId) { mutableListOf() }
                                for (pin in 0 until pinCount) {
                                    val offset = i + 5 + pin
                                    if (offset >= i + bLength) break
                                    val inputId = descriptors[offset].toInt() and 0xFF
                                    if (inputId > 0 && inputId !in inputs) inputs.add(inputId)
                                }
                            }
                        } else if (subtype == SUBTYPE_CLOCK_MULTIPLIER &&
                            uac2ClockTopology && bLength >= 5
                        ) {
                            // Clock Multiplier: bClockID, bSourceID (UAC2
                            // 4.7.2.13). The frequency control lives on the
                            // source clock, so resolution must follow the edge.
                            val multiplierId = descriptors[i + 3].toInt() and 0xFF
                            val sourceId = descriptors[i + 4].toInt() and 0xFF
                            if (multiplierId > 0 && sourceId > 0) {
                                clockMultiplierSources.putIfAbsent(multiplierId, sourceId)
                            }
                        }
                    } else if (currentClass == CLASS_AUDIO &&
                        currentSubclass == SUBCLASS_AUDIOSTREAMING &&
                        bLength >= 4
                    ) {
                        val subtype = descriptors[i + 2].toInt() and 0xFF
                        if (subtype == SUBTYPE_AS_GENERAL && bLength >= 4) {
                            // bTerminalLink (i+3) names the AudioControl
                            // terminal this stream is wired to; UAC1 and UAC2
                            // agree on that offset.
                            if (currentAsInterface >= 0) {
                                val link = descriptors[i + 3].toInt() and 0xFF
                                if (link > 0) streamingTerminalLinks.putIfAbsent(
                                    currentAsInterface, link,
                                )
                            }
                            if (uacVersion == UAC2 && bLength >= 11) {
                                // UAC2 AS_GENERAL carries bNrChannels at i+10
                                // (UAC1 keeps the channel count in
                                // FORMAT_TYPE_I instead).
                                curChannels = descriptors[i + 10].toInt() and 0xFF
                            }
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

        // Playback topology: the interface that owns the isochronous OUT
        // endpoint, the terminal it is linked to, and every entity feeding that
        // terminal. Volume units and clocks on the capture path stay out.
        val playbackTerminalId = streamingInterface?.let { streamingTerminalLinks[it] }
        // The linked terminal is normally the USB *input* terminal, which sits
        // UPSTREAM of the Feature Unit, so the chain is walked from each
        // candidate back towards its source and tested for that terminal. Some
        // devices link the OUTPUT terminal instead (downstream of the Feature
        // Unit), so the walk from the terminal is checked as well.
        volumeUnit = playbackTerminalId?.let { terminal ->
            val fromTerminal = entityChainToSource(terminal, entitySourceIds)
            volumeCandidates.firstOrNull { c ->
                terminal in entityChainToSource(c.unitId, entitySourceIds) ||
                    c.unitId in fromTerminal
            }
        } ?: volumeCandidates.firstOrNull()
        val clockSource = resolvePlaybackClock(
            terminalClockIds = terminalClockIds,
            clockSelectorInputs = clockSelectorInputs,
            clockMultiplierSources = clockMultiplierSources,
            clockSources = clockSources,
            playbackTerminalId = playbackTerminalId,
        )

        return Result(
            uacVersion = uacVersion,
            volumeUnit = volumeUnit,
            streamingInterface = streamingInterface,
            streamingEndpoint = streamingEndpoint,
            feedbackEndpoint = feedbackEndpoint,
            supportedRates = supportedRates.distinct().sorted(),
            clockSource = clockSource,
            altSettingFormats = altSettingFormats.toList(),
            clockSources = clockSources.toList(),
            controlInterface = currentAcInterface,
            playbackTerminalId = playbackTerminalId,
            terminalClockIds = terminalClockIds.toMap(),
            clockSelectorInputs = clockSelectorInputs.mapValues { it.value.toList() },
            clockMultiplierSources = clockMultiplierSources.toMap(),
        )
    }

    /**
     * Walk upstream from [startId] through the `bSourceID` references of the
     * AudioControl graph and return every entity ID on the way.
     *
     * Bounded so a malformed descriptor claiming a reference cycle cannot spin
     * forever; an unresolved start simply yields an empty chain, which callers
     * treat as "topology unknown" rather than as "not on the playback path".
     */
    private fun entityChainToSource(
        startId: Int?,
        entitySourceIds: Map<Int, Int>,
    ): Set<Int> {
        var current = startId ?: return emptySet()
        val chain = mutableSetOf<Int>()
        while (current > 0 && chain.add(current)) {
            current = entitySourceIds[current] ?: 0
            if (chain.size >= MAX_ENTITY_HOPS) break
        }
        return chain
    }

    /**
     * The Clock Source that statically appears to feed the playback stream.
     *
     * Preference order: the clock wired to the streaming terminal, followed
     * through single-input Clock Selectors and Clock Multipliers; and only when
     * the topology says nothing (or names a multi-input selector, whose active
     * pin is device state this parser cannot read) the single programmable
     * clock in the configuration. The last step is a documented guess for
     * devices whose AC graph is incomplete, not a measured fact; callers with
     * a live connection must use `UsbAudioProtocol.resolveActiveClock` instead.
     */
    private fun resolvePlaybackClock(
        terminalClockIds: Map<Int, Int>,
        clockSelectorInputs: Map<Int, List<Int>>,
        clockMultiplierSources: Map<Int, Int>,
        clockSources: List<ClockSource>,
        playbackTerminalId: Int?,
    ): ClockSource? {
        val wired = playbackTerminalId?.let { terminalClockIds[it] }
        if (wired != null) {
            var current: Int? = wired
            val seen = mutableSetOf<Int>()
            while (current != null && seen.add(current)) {
                clockSources.firstOrNull { it.clockId == current }?.let { return it }
                current = clockSelectorInputs[current]?.takeIf { it.size == 1 }?.get(0)
                    ?: clockMultiplierSources[current]
            }
        }
        return clockSources.singleOrNull { it.frequencyProgrammable }
            ?: clockSources.firstOrNull { it.frequencyProgrammable }
            ?: clockSources.firstOrNull()
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

    private companion object {
        /**
         * Raw 0x8000 in a UAC volume range is the -inf / mute marker, not a
         * volume step. A volume request must never write it (that would silently
         * mute the DAC); the quietest writable step is one resolution above it.
         */
        const val MUTE_RAW = -32768
    }

    private var ranges: Map<Int, List<Range>> = emptyMap()
    private var expected: Map<Int, Int>? = null
    var currentDb: Double? = null
        private set
    val ready: Boolean get() = ranges.isNotEmpty() && currentDb != null
    val applied: Boolean get() = ready && expected != null

    /** Quietest raw value a volume request may write for one channel's ranges. */
    private fun effectiveMin(rs: List<Range>): Int {
        val quietest = rs.minByOrNull { it.min } ?: return 0
        return if (quietest.min == MUTE_RAW) quietest.min + quietest.res else quietest.min
    }

    val minDb: Double? get() = ranges.values.maxOfOrNull { effectiveMin(it) }?.div(256.0)
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

    private fun read(request: Int, channel: Int, isSigned: Boolean = true): Int? {
        val data = ByteArray(2)
        if (!transfer(request, channel, data)) return null
        return if (isSigned) signed(data) else unsigned(data)
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
        // A UAC1 device that supports the full -128 dB span legitimately reports
        // 0x8000 as its minimum, so that value must not be treated as "absent".
        return result.takeIf { rs -> rs.isNotEmpty() && rs.all { it.min <= it.max && it.res > 0 } }
    }

    fun refresh(): Boolean {
        fun fail(): Boolean { invalidate(); return false }
        val channels = unit.controlChannels
        if (channels.isEmpty()) return fail()
        val discovered = mutableMapOf<Int, List<Range>>()
        val values = mutableMapOf<Int, Int>()
        for (channel in channels) {
            // Ranges are static for a connection; only the current value moves.
            val rs = ranges[channel] ?: readRanges(channel) ?: return fail()
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
        val targets = mutableMapOf<Int, Int>()
        for ((channel, rs) in ranges) {
            // Clamp into what the device can actually do: a request below the
            // quietest writable step (or above the loudest one, e.g. after a
            // negative calibration offset) becomes that step instead of a
            // refusal. Rounding still favours attenuation inside the range. The
            // 0x8000 mute marker is never a write target: when a device reports
            // it as its minimum, the floor becomes one resolution above it.
            val lo = effectiveMin(rs)
            val hi = rs.maxOf { it.max }
            if (lo > hi) { invalidate(); return false }
            val target = kotlin.math.floor(db * 256.0).coerceIn(lo.toDouble(), hi.toDouble())
            targets[channel] = rs.filter { it.min <= target }.maxOfOrNull { r ->
                r.min + ((minOf(target, r.max.toDouble()) - r.min) / r.res).toInt() * r.res
            } ?: lo
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

    /**
     * The stream the caller asked for, as the caller must be able to recognise
     * it again.
     *
     * [bitDepth] is the *requested* depth, not the container the endpoint was
     * opened with: comparing the request against the wire size made a 16-bit
     * track on a 24-bit-only DAC look like a format change on every call, so
     * the stream was torn down and restarted forever. The wire resolution is
     * what the plugin publishes as its confirmed direct-stream status.
     */
    data class StreamFormat(
        val sampleRate: Int,
        /** Requested depth (what [matches] compares). */
        val bitDepth: Int,
        /** Requested channel count (what [matches] compares). */
        val channels: Int,
        /** Wire bit resolution of the opened alt setting (what status reports). */
        val wireBitDepth: Int = bitDepth,
        /** Channel count of the opened alt setting (what status reports). */
        val wireChannels: Int = channels,
    ) {
        fun matches(rate: Int, depth: Int, count: Int, nativeActive: Boolean): Boolean =
            nativeActive && sampleRate == rate && bitDepth == depth && channels == count
    }

    /**
     * Pick the alt setting whose wire format can carry the requested sample
     * rate / bit depth / channel layout.
     *
     * Every candidate is an alt setting that exposes an isochronous OUT
     * endpoint (capture-only alts never enter [UsbAudioControlParser.Result.altSettingFormats]),
     * so ALL playback interfaces compete, not just the one that happened to
     * own the first iso-OUT endpoint. Ties break deterministically on
     * bit resolution, then subslot size, then interface number, then alt
     * setting number.
     *
     * The channel count must match exactly (an alt that advertises none is
     * treated as the requested one). Duplicating, padding or dropping channels
     * to fit a different layout would change the samples, which Bit-Perfect must
     * never do silently, so such a track is refused with `format_unsupported`.
     */
    fun selectFormat(parsed: UsbAudioControlParser.Result, rate: Int, depth: Int, channels: Int): UsbAudioControlParser.AltSettingFormat? {
        if (rate <= 0 || channels <= 0 || depth !in listOf(16, 24, 32) || parsed.uacVersion !in 1..2) return null
        return parsed.altSettingFormats.filter { fmt ->
            // Defence in depth: the parser only enumerates iso-OUT alts, but a
            // capture endpoint address must never be selected even if one slips
            // into the candidate list.
            fmt.endpointAddress and 0x80 == 0 &&
                fmt.altSetting > 0 && fmt.subslotSize in 2..4 &&
                (fmt.channels == 0 || fmt.channels == channels) &&
                fmt.bitResolution in depth..(fmt.subslotSize * 8) &&
                (if (parsed.uacVersion == 2) true else rate in fmt.supportedRates)
        }.minWithOrNull(
            compareBy(
                { it.bitResolution },
                { it.subslotSize },
                { it.interfaceNumber },
                { it.altSetting },
            ),
        )
    }

    /**
     * The Clock Source actually driving the playback stream, resolved against
     * live device state.
     *
     * When the streaming terminal is wired through a multi-input Clock
     * Selector, the active pin is read with GET_CUR(CX_CLOCK_SELECTOR_CONTROL):
     * bmRequestType 0xA1, bRequest 0x01, wValue 0x0100, wIndex
     * (selectorClockID shl 8) or controlInterface, one byte, 1-based pin
     * number. A failed or out-of-range pin read fails the whole resolution:
     * programming a guessed clock would tune a different part of the DAC to
     * the wrong rate, so the caller must refuse the stream instead. When the
     * topology names no clock entity at all, the static best guess from
     * [UsbAudioControlParser.Result.clockSource] is kept.
     */
    fun resolveActiveClock(
        transport: UsbControlTransfer,
        parsed: UsbAudioControlParser.Result,
    ): UsbAudioControlParser.ClockSource? {
        val wired = parsed.playbackTerminalId?.let { parsed.terminalClockIds[it] }
            ?: return parsed.clockSource
        var current: Int? = wired
        val seen = mutableSetOf<Int>()
        while (current != null && seen.add(current)) {
            parsed.clockSources.firstOrNull { it.clockId == current }?.let { return it }
            val inputs = parsed.clockSelectorInputs[current]
            if (inputs != null) {
                if (inputs.size == 1) {
                    current = inputs[0]
                    continue
                }
                val pin = readSelectorPin(transport, current, parsed.controlInterface)
                    ?: return null
                current = inputs.getOrNull(pin - 1) ?: return null
                continue
            }
            val source = parsed.clockMultiplierSources[current]
            if (source != null) {
                current = source
                continue
            }
            // Dangling reference: the descriptor graph is inconsistent, so keep
            // the static guess rather than inventing a clock.
            return parsed.clockSource
        }
        // Reference cycle in the clock graph: fail safe.
        return null
    }

    private fun readSelectorPin(
        transport: UsbControlTransfer,
        selectorClockId: Int,
        controlInterface: Int,
    ): Int? {
        if (controlInterface < 0) return null
        return try {
            val data = ByteArray(1)
            val read = transport.transfer(
                0xA1, 0x01, 0x0100, (selectorClockId shl 8) or controlInterface, data,
            )
            if (read != 1) null else data[0].toInt() and 0xFF
        } catch (_: Exception) {
            null
        }
    }

    enum class RateSetResult {
        VERIFIED,
        UNVERIFIED_READBACK_UNSUPPORTED,
        FAILED;

        val isSuccess: Boolean get() = this == VERIFIED || this == UNVERIFIED_READBACK_UNSUPPORTED
    }

    fun setSampleRateWithResult(
        transport: UsbControlTransfer, version: Int, clock: UsbAudioControlParser.ClockSource?,
        endpoint: Int, rate: Int, fixedUac1: Boolean,
    ): RateSetResult {
        if (rate <= 0 || version !in 1..2 || (version == 2 && clock == null)) return RateSetResult.FAILED
        val size = if (version == 2) 4 else 3
        if (size == 3 && rate > 0xFFFFFF) return RateSetResult.FAILED
        val index = if (version == 2) (clock!!.clockId shl 8) or clock.controlInterface else endpoint
        val setType = if (version == 2) 0x21 else 0x22
        val programmable = if (version == 2) clock!!.frequencyProgrammable else !fixedUac1
        return try {
            if (programmable) {
                val data = ByteArray(size) { (rate shr (8 * it)).toByte() }
                if (transport.transfer(setType, 1, 0x100, index, data) != size) return RateSetResult.FAILED
            }
            val data = ByteArray(size)
            val readRes = transport.transfer(setType or 0x80, if (version == 2) 1 else 0x81, 0x100, index, data)
            if (readRes != size) {
                if (version == 1) {
                    return RateSetResult.UNVERIFIED_READBACK_UNSUPPORTED
                }
                return RateSetResult.FAILED
            }
            val actual = data.indices.fold(0L) { acc, i -> acc or ((data[i].toLong() and 255) shl (8 * i)) }
            if (actual == rate.toLong()) RateSetResult.VERIFIED else RateSetResult.FAILED
        } catch (_: Exception) { RateSetResult.FAILED }
    }

    fun setSampleRate(
        transport: UsbControlTransfer, version: Int, clock: UsbAudioControlParser.ClockSource?,
        endpoint: Int, rate: Int, fixedUac1: Boolean,
    ): Boolean = setSampleRateWithResult(transport, version, clock, endpoint, rate, fixedUac1) == RateSetResult.VERIFIED
}

