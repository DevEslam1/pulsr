package com.pulsr.music

/**
 * Pure-logic USB Audio Class diagnostics for DAC capability reporting.
 *
 * The USB Audio Class version is identified by the bInterfaceProtocol byte of
 * the Audio Control (AC) interface descriptor (bInterfaceClass = 0x01,
 * bInterfaceSubClass = 0x01): 0x00 = UAC1, 0x20 = UAC2, 0x30 = UAC3.
 *
 * HONEST SCOPE: this reports the DAC's advertised class version only. Native
 * DSD streaming requires raw USB isochronous ownership, which the app does not
 * implement; DSD files play via the DSD->PCM decoder. Never report native-DSD
 * capability from this probe.
 */
object UsbDacDiagnostics {
    const val UAC_NONE = 0
    const val UAC1 = 1
    const val UAC2 = 2
    const val UAC3 = 3

    // USB spec 9.6.5 standard interface descriptor offsets
    private const val DESC_TYPE_INTERFACE = 0x04
    private const val CLASS_AUDIO = 0x01
    private const val SUBCLASS_AUDIOCONTROL = 0x01
    private const val OFF_B_LENGTH = 0
    private const val OFF_B_DESCRIPTOR_TYPE = 1
    private const val OFF_B_INTERFACE_CLASS = 5
    private const val OFF_B_INTERFACE_SUBCLASS = 6
    private const val OFF_B_INTERFACE_PROTOCOL = 7

    /**
     * Scans a raw configuration descriptor stream (as returned by
     * UsbConfiguration.getDescriptors()) for the highest advertised UAC
     * version of any Audio Control interface. Malformed descriptors are
     * skipped byte-by-byte (resync) instead of throwing.
     */
    fun uacVersionFromDescriptors(descriptors: ByteArray?): Int {
        if (descriptors == null || descriptors.size < 8) return UAC_NONE
        var best = UAC_NONE
        var i = 0
        while (i + 8 <= descriptors.size) {
            val bLength = descriptors[i + OFF_B_LENGTH].toInt() and 0xFF
            if (bLength < 8) {
                i += 1 // malformed descriptor: resync
                continue
            }
            val bType = descriptors[i + OFF_B_DESCRIPTOR_TYPE].toInt() and 0xFF
            val bClass = descriptors[i + OFF_B_INTERFACE_CLASS].toInt() and 0xFF
            val bSubClass = descriptors[i + OFF_B_INTERFACE_SUBCLASS].toInt() and 0xFF
            if (bType == DESC_TYPE_INTERFACE && bClass == CLASS_AUDIO && bSubClass == SUBCLASS_AUDIOCONTROL) {
                val protocol = descriptors[i + OFF_B_INTERFACE_PROTOCOL].toInt() and 0xFF
                val version = when (protocol) {
                    0x20 -> UAC2
                    0x30 -> UAC3
                    0x00 -> UAC1
                    else -> UAC_NONE
                }
                if (version > best) best = version
            }
            i += bLength
        }
        return best
    }

    /**
     * Public-API variant: maps (interfaceSubclass, interfaceProtocol) pairs
     * from UsbInterface (getInterfaceSubclass/getInterfaceProtocol) to the
     * highest UAC version among Audio Control interfaces (subclass 0x01).
     */
    fun uacVersionFromUsbInterfaces(interfaces: List<Pair<Int, Int>>): Int {
        var best = UAC_NONE
        for ((subclass, protocol) in interfaces) {
            if (subclass != SUBCLASS_AUDIOCONTROL) continue
            val version = when (protocol and 0xFF) {
                0x20 -> UAC2
                0x30 -> UAC3
                0x00 -> UAC1
                else -> UAC_NONE
            }
            if (version > best) best = version
        }
        return best
    }

    fun uacLabel(version: Int): String = when (version) {
        UAC1 -> "UAC1"
        UAC2 -> "UAC2"
        UAC3 -> "UAC3"
        else -> "none"
    }

    /** Direct-playback probe matrix: encoding tag + sample rate. Tags are
     * framework-free; the plugin maps them to android.media.AudioFormat. */
    val PROBE_TAGS: List<Pair<String, Int>> = listOf(
        "float" to 44100, "float" to 48000, "float" to 88200, "float" to 96000,
        "float" to 176400, "float" to 192000,
        "24" to 44100, "24" to 48000, "24" to 96000, "24" to 192000,
        "32" to 44100, "32" to 48000, "32" to 96000, "32" to 192000,
    )

    /**
     * Builds the per-format capability list. [probe] returns Boolean? —
     * null (unknown/unsupported API level) is reported as not supported with
     * no fabricated claim.
     */
    fun directFormatsFor(probe: (tag: String, sampleRate: Int) -> Boolean?): List<Map<String, Any?>> =
        PROBE_TAGS.map { (tag, rate) ->
            mapOf(
                "encoding" to tag,
                "sampleRate" to rate,
                "supported" to (probe(tag, rate) == true),
            )
        }
}