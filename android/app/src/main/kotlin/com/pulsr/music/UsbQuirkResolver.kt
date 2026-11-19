package com.pulsr.music

/**
 * Facts about the attached USB Audio device that the quirk resolver needs.
 *
 * [supportedRates] is what the descriptors/clock ranges actually advertise. An
 * empty list means "unknown" (UAC2 alt settings carry no rate list until the
 * clock range is read), never "nothing is supported".
 */
data class UsbDeviceFacts(
    val vid: Int = 0,
    val pid: Int = 0,
    val uacVersion: Int = 2,
    val supportedRates: List<Int> = emptyList(),
    val requestedRate: Int = 48_000,
    val requestedDepth: Int = 24,
    val requestedChannels: Int = 2,
    val feedbackPresent: Boolean = false,
)

/**
 * Stream parameters after the per-device quirk profile has been applied.
 *
 * Invariants the caller can rely on:
 *
 *  * [effectiveRate] is always [UsbDeviceFacts.requestedRate]. The resolver
 *    never picks a different rate; when the rate is unsupported it reports the
 *    refusal through [rejected]`["rate"]` and the caller refuses to start.
 *  * [effectiveDepth] only differs from the request when `force16Bit` applied.
 *  * [effectiveChannels] is never changed by a quirk.
 *  * [appliedQuirks] lists profile keys that took effect, in canonical order
 *    (independent of the profile map's iteration order).
 *  * [bitPerfectReason] is the first cause in canonical order when several
 *    quirks affect bit-perfect playback.
 *
 * [volumeCalibrationDb] is a DAC/HAL-side calibration, not a sample-domain
 * gain, so it is reported without marking bit-perfect affected. A caller that
 * applies it digitally must treat bit-perfect as compromised itself.
 */
data class ResolvedStreamParams(
    val effectiveRate: Int,
    val effectiveDepth: Int,
    val effectiveChannels: Int,
    val silenceMs: Int,
    val transferSizeBytes: Int,
    val bufferMs: Int,
    val disableExplicitFeedback: Boolean,
    val preferredSelectorPin: Int?,
    val altResetOnStop: Boolean,
    val uac1ReassertAfterAlt: Boolean,
    val disableUac2ClockSwitch: Boolean,
    val volumeCalibrationDb: Double,
    val appliedQuirks: List<String>,
    val bitPerfectAffected: Boolean,
    val bitPerfectReason: String?,
    val rejected: Map<String, String>,
)

/**
 * Resolves a per-device quirk profile into concrete stream parameters.
 *
 * The profile is a flat map (usually parsed from JSON) of optional keys:
 * `silenceMs`, `force16Bit`, `altResetOnStop`, `transferSizeBytes`, `bufferMs`,
 * `disableExplicitFeedback`, `preferredSelectorPin`, `volumeCalibrationDb`,
 * `uac1ReassertAfterAlt`, `disableUac2ClockSwitch`.
 *
 * Nothing is silently ignored: an unknown key, a wrong type or an out-of-range
 * value is reported in [ResolvedStreamParams.rejected] with a machine-readable
 * reason, and the affected parameter keeps its default. A `null` value is
 * treated as "not configured" (JSON profiles routinely carry nulls), not as an
 * error.
 *
 * Validation ranges: `silenceMs` 0..2000, `transferSizeBytes` 0 or 64..65536
 * (0 = auto), `bufferMs` 0..10000 (0 = auto), `preferredSelectorPin` 0..255,
 * `volumeCalibrationDb` -24..24 dB.
 *
 * Bit-perfect rules: `force16Bit` forces 16-bit and marks the chain affected
 * with reason `quirk_force_16bit`; `disableUac2ClockSwitch` marks it affected
 * with `quirk_clock_switch_disabled` on a UAC2 device only. `altResetOnStop`
 * and `uac1ReassertAfterAlt` are transport quirks: they are reported in
 * [ResolvedStreamParams.appliedQuirks] but do not change the sample values.
 */
object UsbQuirkResolver {

    const val KEY_SILENCE_MS = "silenceMs"
    const val KEY_FORCE_16_BIT = "force16Bit"
    const val KEY_ALT_RESET_ON_STOP = "altResetOnStop"
    const val KEY_TRANSFER_SIZE_BYTES = "transferSizeBytes"
    const val KEY_BUFFER_MS = "bufferMs"
    const val KEY_DISABLE_EXPLICIT_FEEDBACK = "disableExplicitFeedback"
    const val KEY_PREFERRED_SELECTOR_PIN = "preferredSelectorPin"
    const val KEY_VOLUME_CALIBRATION_DB = "volumeCalibrationDb"
    const val KEY_UAC1_REASSERT_AFTER_ALT = "uac1ReassertAfterAlt"
    const val KEY_DISABLE_UAC2_CLOCK_SWITCH = "disableUac2ClockSwitch"

    const val REASON_UNKNOWN_KEY = "unknown_key"
    const val REASON_NOT_AN_INTEGER = "not_an_integer"
    const val REASON_NOT_A_NUMBER = "not_a_number"
    const val REASON_NOT_A_BOOLEAN = "not_a_boolean"
    const val REASON_UNSUPPORTED_RATE = "unsupported_rate"

    /** Canonical processing order; it also fixes the order of appliedQuirks. */
    val KNOWN_KEYS: List<String> = listOf(
        KEY_SILENCE_MS,
        KEY_FORCE_16_BIT,
        KEY_ALT_RESET_ON_STOP,
        KEY_TRANSFER_SIZE_BYTES,
        KEY_BUFFER_MS,
        KEY_DISABLE_EXPLICIT_FEEDBACK,
        KEY_PREFERRED_SELECTOR_PIN,
        KEY_VOLUME_CALIBRATION_DB,
        KEY_UAC1_REASSERT_AFTER_ALT,
        KEY_DISABLE_UAC2_CLOCK_SWITCH,
    )

    private const val REASON_RANGE_SILENCE = "out_of_range(0..2000)"
    private const val REASON_RANGE_TRANSFER = "out_of_range(0|64..65536)"
    private const val REASON_RANGE_BUFFER = "out_of_range(0..10000)"
    private const val REASON_RANGE_PIN = "out_of_range(0..255)"
    private const val REASON_RANGE_VOLUME = "out_of_range(-24..24)"

    private const val REASON_KEY_RATE = "rate"

    /** Applies [profile] to [facts]. Never throws for malformed values. */
    fun resolve(profile: Map<String, Any?>, facts: UsbDeviceFacts): ResolvedStreamParams {
        val rejected = LinkedHashMap<String, String>()
        val applied = ArrayList<String>()

        for (key in profile.keys) {
            if (key !in KNOWN_KEYS) rejected[key] = REASON_UNKNOWN_KEY
        }

        var silenceMs = 0
        var force16Bit = false
        var altResetOnStop = false
        var transferSizeBytes = 0
        var bufferMs = 0
        var disableExplicitFeedback = false
        var preferredSelectorPin: Int? = null
        var volumeCalibrationDb = 0.0
        var uac1ReassertAfterAlt = false
        var disableUac2ClockSwitch = false

        var bitPerfectAffected = false
        var bitPerfectReason: String? = null

        fun markBitPerfect(reason: String) {
            if (!bitPerfectAffected) {
                bitPerfectAffected = true
                bitPerfectReason = reason
            }
        }

        profile[KEY_SILENCE_MS]?.let { raw ->
            val value = asInt(raw)
            when {
                value == null -> rejected[KEY_SILENCE_MS] = REASON_NOT_AN_INTEGER
                value !in 0..2_000 -> rejected[KEY_SILENCE_MS] = REASON_RANGE_SILENCE
                else -> {
                    silenceMs = value
                    if (value != 0) applied += KEY_SILENCE_MS
                }
            }
        }

        profile[KEY_FORCE_16_BIT]?.let { raw ->
            val value = asBoolean(raw)
            when {
                value == null -> rejected[KEY_FORCE_16_BIT] = REASON_NOT_A_BOOLEAN
                value -> {
                    force16Bit = true
                    applied += KEY_FORCE_16_BIT
                    markBitPerfect("quirk_force_16bit")
                }
            }
        }

        profile[KEY_ALT_RESET_ON_STOP]?.let { raw ->
            val value = asBoolean(raw)
            when {
                value == null -> rejected[KEY_ALT_RESET_ON_STOP] = REASON_NOT_A_BOOLEAN
                value -> {
                    altResetOnStop = true
                    applied += KEY_ALT_RESET_ON_STOP
                }
            }
        }

        profile[KEY_TRANSFER_SIZE_BYTES]?.let { raw ->
            val value = asInt(raw)
            when {
                value == null -> rejected[KEY_TRANSFER_SIZE_BYTES] = REASON_NOT_AN_INTEGER
                value != 0 && value !in 64..65_536 -> rejected[KEY_TRANSFER_SIZE_BYTES] = REASON_RANGE_TRANSFER
                else -> {
                    transferSizeBytes = value
                    if (value != 0) applied += KEY_TRANSFER_SIZE_BYTES
                }
            }
        }

        profile[KEY_BUFFER_MS]?.let { raw ->
            val value = asInt(raw)
            when {
                value == null -> rejected[KEY_BUFFER_MS] = REASON_NOT_AN_INTEGER
                value !in 0..10_000 -> rejected[KEY_BUFFER_MS] = REASON_RANGE_BUFFER
                else -> {
                    bufferMs = value
                    if (value != 0) applied += KEY_BUFFER_MS
                }
            }
        }

        profile[KEY_DISABLE_EXPLICIT_FEEDBACK]?.let { raw ->
            val value = asBoolean(raw)
            when {
                value == null -> rejected[KEY_DISABLE_EXPLICIT_FEEDBACK] = REASON_NOT_A_BOOLEAN
                value -> {
                    disableExplicitFeedback = true
                    applied += KEY_DISABLE_EXPLICIT_FEEDBACK
                }
            }
        }

        profile[KEY_PREFERRED_SELECTOR_PIN]?.let { raw ->
            val value = asInt(raw)
            when {
                value == null -> rejected[KEY_PREFERRED_SELECTOR_PIN] = REASON_NOT_AN_INTEGER
                value !in 0..255 -> rejected[KEY_PREFERRED_SELECTOR_PIN] = REASON_RANGE_PIN
                else -> {
                    preferredSelectorPin = value
                    applied += KEY_PREFERRED_SELECTOR_PIN
                }
            }
        }

        profile[KEY_VOLUME_CALIBRATION_DB]?.let { raw ->
            val value = asDouble(raw)
            when {
                value == null -> rejected[KEY_VOLUME_CALIBRATION_DB] = REASON_NOT_A_NUMBER
                value < -24.0 || value > 24.0 -> rejected[KEY_VOLUME_CALIBRATION_DB] = REASON_RANGE_VOLUME
                else -> {
                    volumeCalibrationDb = value
                    if (value != 0.0) applied += KEY_VOLUME_CALIBRATION_DB
                }
            }
        }

        profile[KEY_UAC1_REASSERT_AFTER_ALT]?.let { raw ->
            val value = asBoolean(raw)
            when {
                value == null -> rejected[KEY_UAC1_REASSERT_AFTER_ALT] = REASON_NOT_A_BOOLEAN
                value -> {
                    uac1ReassertAfterAlt = true
                    applied += KEY_UAC1_REASSERT_AFTER_ALT
                }
            }
        }

        profile[KEY_DISABLE_UAC2_CLOCK_SWITCH]?.let { raw ->
            val value = asBoolean(raw)
            when {
                value == null -> rejected[KEY_DISABLE_UAC2_CLOCK_SWITCH] = REASON_NOT_A_BOOLEAN
                value -> {
                    disableUac2ClockSwitch = true
                    applied += KEY_DISABLE_UAC2_CLOCK_SWITCH
                    if (facts.uacVersion >= 2) markBitPerfect("quirk_clock_switch_disabled")
                }
            }
        }

        if (facts.supportedRates.isNotEmpty() && facts.requestedRate !in facts.supportedRates) {
            rejected[REASON_KEY_RATE] = REASON_UNSUPPORTED_RATE
        }

        return ResolvedStreamParams(
            effectiveRate = facts.requestedRate,
            effectiveDepth = if (force16Bit) 16 else facts.requestedDepth,
            effectiveChannels = facts.requestedChannels,
            silenceMs = silenceMs,
            transferSizeBytes = transferSizeBytes,
            bufferMs = bufferMs,
            disableExplicitFeedback = disableExplicitFeedback,
            preferredSelectorPin = preferredSelectorPin,
            altResetOnStop = altResetOnStop,
            uac1ReassertAfterAlt = uac1ReassertAfterAlt,
            disableUac2ClockSwitch = disableUac2ClockSwitch,
            volumeCalibrationDb = volumeCalibrationDb,
            appliedQuirks = applied.toList(),
            bitPerfectAffected = bitPerfectAffected,
            bitPerfectReason = bitPerfectReason,
            rejected = rejected.toMap(),
        )
    }

    /** Convenience overload for a JSON profile string; malformed JSON means "no quirks". */
    fun resolveJson(raw: String?, facts: UsbDeviceFacts): ResolvedStreamParams =
        resolve(fromJson(raw), facts)

    /**
     * Parses a flat JSON object into a map, tolerating anything.
     *
     * Returns an empty map for null/blank input, malformed JSON, a non-object
     * root (arrays, scalars) or trailing garbage. Nested objects/arrays are
     * preserved as Map/List values so [resolve] can reject them by type.
     */
    fun fromJson(raw: String?): Map<String, Any?> {
        if (raw.isNullOrBlank()) return emptyMap()
        val parsed = try {
            MiniJsonParser(raw).parseDocument()
        } catch (_: Exception) {
            return emptyMap()
        }
        val objectMap = parsed as? Map<*, *> ?: return emptyMap()
        val out = LinkedHashMap<String, Any?>(objectMap.size)
        for ((key, value) in objectMap) {
            if (key is String) out[key] = value
        }
        return out
    }

    // ------------------------------------------------------------ coercion

    private fun asInt(value: Any?): Int? = when (value) {
        is Int -> value
        is Long -> if (value in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) value.toInt() else null
        is Short -> value.toInt()
        is Byte -> value.toInt()
        is Double ->
            if (value.isFinite() && value % 1.0 == 0.0 &&
                value >= Int.MIN_VALUE.toDouble() && value <= Int.MAX_VALUE.toDouble()
            ) {
                value.toInt()
            } else {
                null
            }

        is Float ->
            if (value.isFinite() && value % 1.0f == 0.0f &&
                value >= Int.MIN_VALUE.toFloat() && value <= Int.MAX_VALUE.toFloat()
            ) {
                value.toInt()
            } else {
                null
            }

        is String -> value.trim().toIntOrNull()
        else -> null
    }

    private fun asDouble(value: Any?): Double? = when (value) {
        is Double -> value.takeIf { it.isFinite() }
        is Float -> value.toDouble().takeIf { it.isFinite() }
        is Int -> value.toDouble()
        is Long -> value.toDouble()
        is Short -> value.toDouble()
        is Byte -> value.toDouble()
        is String -> value.trim().toDoubleOrNull()?.takeIf { it.isFinite() }
        else -> null
    }

    private fun asBoolean(value: Any?): Boolean? = value as? Boolean
}

/**
 * Minimal recursive-descent JSON reader.
 *
 * Deliberately local: the main source set must stay free of `org.json` (an
 * Android framework class) so the component runs in a plain JVM unit test, and
 * the profile schema is a flat object of scalars, so a full JSON library would
 * be more surface than value.
 */
private class MiniJsonParser(private val text: String) {

    private var index = 0

    fun parseDocument(): Any? {
        val value = parseValue(0)
        skipWhitespace()
        if (index != text.length) throw IllegalArgumentException("trailing characters at $index")
        return value
    }

    private fun parseValue(depth: Int): Any? {
        if (depth > MAX_DEPTH) throw IllegalArgumentException("nesting deeper than $MAX_DEPTH")
        skipWhitespace()
        if (index >= text.length) throw IllegalArgumentException("unexpected end of input")
        return when (val ch = text[index]) {
            '{' -> parseObject(depth)
            '[' -> parseArray(depth)
            '"' -> parseString()
            't' -> {
                expect("true")
                true
            }

            'f' -> {
                expect("false")
                false
            }

            'n' -> {
                expect("null")
                null
            }

            else -> if (ch == '-' || ch in '0'..'9') {
                parseNumber()
            } else {
                throw IllegalArgumentException("unexpected '$ch' at $index")
            }
        }
    }

    private fun parseObject(depth: Int): Map<String, Any?> {
        index++ // '{'
        val out = LinkedHashMap<String, Any?>()
        skipWhitespace()
        if (peek() == '}') {
            index++
            return out
        }
        while (true) {
            skipWhitespace()
            if (peek() != '"') throw IllegalArgumentException("expected object key at $index")
            val key = parseString()
            skipWhitespace()
            if (peek() != ':') throw IllegalArgumentException("expected ':' at $index")
            index++
            out[key] = parseValue(depth + 1)
            skipWhitespace()
            when (peek()) {
                ',' -> index++
                '}' -> {
                    index++
                    return out
                }

                else -> throw IllegalArgumentException("expected ',' or '}' at $index")
            }
        }
    }

    private fun parseArray(depth: Int): List<Any?> {
        index++ // '['
        val out = ArrayList<Any?>()
        skipWhitespace()
        if (peek() == ']') {
            index++
            return out
        }
        while (true) {
            out += parseValue(depth + 1)
            skipWhitespace()
            when (peek()) {
                ',' -> index++
                ']' -> {
                    index++
                    return out
                }

                else -> throw IllegalArgumentException("expected ',' or ']' at $index")
            }
        }
    }

    private fun parseString(): String {
        index++ // opening quote
        val out = StringBuilder()
        while (index < text.length) {
            val ch = text[index++]
            when {
                ch == '"' -> return out.toString()
                ch == '\\' -> {
                    if (index >= text.length) throw IllegalArgumentException("dangling escape")
                    when (val escaped = text[index++]) {
                        '"' -> out.append('"')
                        '\\' -> out.append('\\')
                        '/' -> out.append('/')
                        'b' -> out.append('\b')
                        'f' -> out.append('\u000C')
                        'n' -> out.append('\n')
                        'r' -> out.append('\r')
                        't' -> out.append('\t')
                        'u' -> {
                            if (index + 4 > text.length) throw IllegalArgumentException("short unicode escape")
                            val hex = text.substring(index, index + 4)
                            index += 4
                            out.append(hex.toInt(16).toChar())
                        }

                        else -> throw IllegalArgumentException("unsupported escape '\\$escaped'")
                    }
                }

                else -> out.append(ch)
            }
        }
        throw IllegalArgumentException("unterminated string")
    }

    private fun parseNumber(): Number {
        val start = index
        if (peek() == '-') index++
        var digits = 0
        while (index < text.length && text[index].isDigit()) {
            index++
            digits++
        }
        if (digits == 0) throw IllegalArgumentException("bad number at $start")
        var integral = true
        if (index < text.length && text[index] == '.') {
            integral = false
            index++
            var fraction = 0
            while (index < text.length && text[index].isDigit()) {
                index++
                fraction++
            }
            if (fraction == 0) throw IllegalArgumentException("bad fraction at $start")
        }
        if (index < text.length && (text[index] == 'e' || text[index] == 'E')) {
            integral = false
            index++
            if (index < text.length && (text[index] == '+' || text[index] == '-')) index++
            var exponent = 0
            while (index < text.length && text[index].isDigit()) {
                index++
                exponent++
            }
            if (exponent == 0) throw IllegalArgumentException("bad exponent at $start")
        }
        val raw = text.substring(start, index)
        return if (integral) raw.toLongOrNull() ?: raw.toDouble() else raw.toDouble()
    }

    private fun skipWhitespace() {
        while (index < text.length && text[index].isWhitespace()) index++
    }

    private fun peek(): Char = if (index < text.length) text[index] else '\u0000'

    private fun expect(literal: String) {
        if (!text.startsWith(literal, index)) throw IllegalArgumentException("expected '$literal' at $index")
        index += literal.length
    }

    private companion object {
        const val MAX_DEPTH = 32
    }
}
