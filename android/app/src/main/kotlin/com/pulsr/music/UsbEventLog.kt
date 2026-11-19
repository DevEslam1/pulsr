package com.pulsr.music

import java.util.ArrayDeque
import java.util.Locale

/**
 * One structured USB session event.
 *
 * The field set is fixed on purpose: it is the schema a bug report is triaged
 * against, so it must not grow ad-hoc fields per call site. Everything a
 * support engineer needs to tell "wrong alt setting" from "clock drift" lives
 * here, and nothing that can identify the user or leak a descriptor dump.
 *
 * String fields are sanitised by [UsbEventLog.record] before they are stored.
 */
data class UsbEvent(
    val timestampMs: Long = 0L,
    val build: String = "",
    val deviceModel: String = "",
    val androidVersion: String = "",
    val vid: Int = 0,
    val pid: Int = 0,
    val uacVersion: Int = 0,
    val interfaceNumber: Int = 0,
    val altSetting: Int = 0,
    val endpoint: Int = 0,
    val rate: Int = 0,
    val depth: Int = 0,
    val channels: Int = 0,
    val clockSource: Int = 0,
    val selectorPin: Int = 0,
    val feedbackPresent: Boolean = false,
    val clockDriftPpm: Double = 0.0,
    val ringFillMs: Long = 0L,
    val underrunCount: Long = 0L,
    val overrunCount: Long = 0L,
    val lastError: String? = null,
    val drainPending: Boolean = false,
    val resultCode: Int = 0,
)

/**
 * Bounded, thread-safe, redacting event log for the USB exclusive path.
 *
 * A ring buffer of [capacity] events (oldest evicted first) so a stuck retry
 * loop cannot grow the heap. Appends are serialised on [lock]; readers take a
 * consistent copy and then serialise outside the lock, so a 500-event export
 * never blocks a recording audio thread for the duration of the JSON build.
 *
 * Redaction runs on every string field before it is stored:
 *
 *  * absolute paths (`/data/...`, `/storage/...`, `/mnt/...`, `C:\...`) become
 *    `[redacted_path]`;
 *  * USB-serial-like tokens: 8+ contiguous hex characters (`A1B2C3D4`, `deadbeefcafe`),
 *    8+ contiguous upper-alphanumeric characters containing a digit
 *    (`SN01234567`), and labelled serials (`SN:`, `Serial:`) become
 *    `[redacted_serial]`;
 *  * e-mail addresses become `[redacted_email]`;
 *  * space-separated hex byte dumps (raw descriptors) become `[redacted_bytes]`.
 *
 * Control characters are replaced with spaces, so the JSON is always valid and
 * no binary payload can ride along. Over-long text is truncated to
 * [MAX_TEXT_CHARS], which is what keeps a full export comfortably below a
 * quarter of a megabyte.
 *
 * The upper-alphanumeric rule requires a digit on purpose: it still catches
 * real serials (`A1B2C3D4E5`) while leaving model names such as `AUDIOQUEST`
 * intact, which is the difference between a useful and a useless log. Pure
 * hex runs need no such guard (an 8-letter English word made only of a-f is
 * vanishingly rare), so `deadbeefcafe` is still redacted; unlabelled all-letter
 * serials are caught by the `SN:`/`Serial:` rule.
 */
class UsbEventLog(val capacity: Int = DEFAULT_CAPACITY) {

    init {
        require(capacity in 1..MAX_CAPACITY) {
            "capacity must be in 1..$MAX_CAPACITY, was $capacity"
        }
    }

    private val lock = Any()
    private val buffer = ArrayDeque<UsbEvent>(capacity)

    /**
     * Appends [event] after redaction, evicting the oldest entry when full.
     * Returns the stored (redacted) copy so callers can log exactly what a
     * support bundle will contain.
     */
    fun record(event: UsbEvent): UsbEvent {
        val clean = event.sanitized()
        synchronized(lock) {
            if (buffer.size == capacity) buffer.removeFirst()
            buffer.addLast(clean)
        }
        return clean
    }

    /** Oldest-to-newest copy of the current contents. */
    fun snapshot(): List<UsbEvent> {
        synchronized(lock) {
            return buffer.toList()
        }
    }

    /** Number of retained events (<= [capacity]). */
    fun size(): Int {
        synchronized(lock) {
            return buffer.size
        }
    }

    /** Drops every retained event. */
    fun clear() {
        synchronized(lock) {
            buffer.clear()
        }
    }

    /**
     * Serialises the retained events as a JSON array, oldest first, with a
     * fixed field order. The output is stable: two calls with no intervening
     * [record] return identical strings.
     */
    fun toJson(): String {
        // Copy under the lock, serialise outside it.
        val events = synchronized(lock) { buffer.toList() }
        val out = StringBuilder(events.size * APPROX_BYTES_PER_EVENT + 2)
        out.append('[')
        events.forEachIndexed { index, event ->
            if (index > 0) out.append(',')
            out.appendEvent(event)
        }
        out.append(']')
        return out.toString()
    }

    companion object {
        const val DEFAULT_CAPACITY: Int = 500
        const val MAX_CAPACITY: Int = 100_000

        /** Longest retained string field, in characters. */
        const val MAX_TEXT_CHARS: Int = 96

        private const val APPROX_BYTES_PER_EVENT = 420
    }
}

// ---------------------------------------------------------------- serialisation

private fun StringBuilder.appendEvent(event: UsbEvent): StringBuilder {
    append('{')
    append("\"timestampMs\":").append(event.timestampMs)
    append(",\"build\":").appendJsonString(event.build)
    append(",\"deviceModel\":").appendJsonString(event.deviceModel)
    append(",\"androidVersion\":").appendJsonString(event.androidVersion)
    append(",\"vid\":").append(event.vid)
    append(",\"pid\":").append(event.pid)
    append(",\"uacVersion\":").append(event.uacVersion)
    append(",\"interfaceNumber\":").append(event.interfaceNumber)
    append(",\"altSetting\":").append(event.altSetting)
    append(",\"endpoint\":").append(event.endpoint)
    append(",\"rate\":").append(event.rate)
    append(",\"depth\":").append(event.depth)
    append(",\"channels\":").append(event.channels)
    append(",\"clockSource\":").append(event.clockSource)
    append(",\"selectorPin\":").append(event.selectorPin)
    append(",\"feedbackPresent\":").append(event.feedbackPresent)
    append(",\"clockDriftPpm\":").appendJsonDouble(event.clockDriftPpm)
    append(",\"ringFillMs\":").append(event.ringFillMs)
    append(",\"underrunCount\":").append(event.underrunCount)
    append(",\"overrunCount\":").append(event.overrunCount)
    append(",\"lastError\":")
    if (event.lastError == null) append("null") else appendJsonString(event.lastError)
    append(",\"drainPending\":").append(event.drainPending)
    append(",\"resultCode\":").append(event.resultCode)
    append('}')
    return this
}

private fun StringBuilder.appendJsonString(value: String): StringBuilder {
    append('"')
    for (ch in value) {
        when (ch) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            '\b' -> append("\\b")
            '\u000C' -> append("\\f")
            else -> if (ch < ' ') {
                append("\\u").append(String.format(Locale.US, "%04x", ch.code))
            } else {
                append(ch)
            }
        }
    }
    append('"')
    return this
}

private fun StringBuilder.appendJsonDouble(raw: Double): StringBuilder {
    // Fixed three decimals keeps the export byte-for-byte stable across JVMs;
    // the clamp keeps a corrupt telemetry value from producing a 300-digit token.
    val value = if (raw.isFinite()) raw.coerceIn(-1_000_000.0, 1_000_000.0) else 0.0
    return append(String.format(Locale.US, "%.3f", value))
}

// -------------------------------------------------------------------- redaction

private fun UsbEvent.sanitized(): UsbEvent = copy(
    build = UsbRedaction.text(build) ?: "",
    deviceModel = UsbRedaction.text(deviceModel) ?: "",
    androidVersion = UsbRedaction.text(androidVersion) ?: "",
    lastError = UsbRedaction.text(lastError),
    clockDriftPpm = if (clockDriftPpm.isFinite()) clockDriftPpm else 0.0,
)

private object UsbRedaction {

    const val PLACEHOLDER_PATH = "[redacted_path]"
    const val PLACEHOLDER_SERIAL = "[redacted_serial]"
    const val PLACEHOLDER_EMAIL = "[redacted_email]"
    const val PLACEHOLDER_BYTES = "[redacted_bytes]"

    /** user@example.com */
    private val EMAIL = Regex("""[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}""")

    /** Raw descriptor dumps: at least six space/tab separated hex byte pairs. */
    private val BYTE_DUMP = Regex("""\b(?:[0-9A-Fa-f]{2}[ \t]+){5,}[0-9A-Fa-f]{2}\b""")

    /** Windows absolute path, e.g. C:\Users\alice\Music */
    private val WINDOWS_PATH = Regex("""(?i)[a-z]:\\[^\s"';,]*""")

    /** Android/Linux absolute paths that carry user or app identity. */
    private val UNIX_PATH =
        Regex("""(?i)/(?:data|storage|sdcard|mnt|system|vendor|proc|odm|product|oem|home)(?:/[^\s"';,]*)?""")

    /** Labelled serial numbers: SN:, S/N:, Serial No: */
    private val LABELLED_SERIAL = Regex("""(?i)\b(?:s/n|sn|serial(?:\s*(?:no|number))?)\s*[:=#]\s*\S+""")

    /** Contiguous hex run of 8+ characters (any case): serials and hex dumps. */
    private val HEX_RUN = Regex("""[0-9A-Fa-f]{8,}""")

    /** Contiguous upper-alphanumeric run of 8+ characters containing at least one digit. */
    private val UPPER_RUN = Regex("""(?=[A-Z0-9]*[0-9])[A-Z0-9]{8,}""")

    fun text(raw: String?): String? {
        if (raw == null) return null
        var value = raw
        value = EMAIL.replace(value, PLACEHOLDER_EMAIL)
        value = BYTE_DUMP.replace(value, PLACEHOLDER_BYTES)
        value = WINDOWS_PATH.replace(value, PLACEHOLDER_PATH)
        value = UNIX_PATH.replace(value, PLACEHOLDER_PATH)
        value = LABELLED_SERIAL.replace(value, PLACEHOLDER_SERIAL)
        value = HEX_RUN.replace(value, PLACEHOLDER_SERIAL)
        value = UPPER_RUN.replace(value, PLACEHOLDER_SERIAL)
        value = stripControlCharacters(value)
        return truncate(value)
    }

    private fun stripControlCharacters(value: String): String {
        val out = StringBuilder(value.length)
        for (ch in value) {
            out.append(if (ch < ' ' || ch == '\u007F') ' ' else ch)
        }
        return out.toString()
    }

    private fun truncate(value: String): String {
        if (value.length <= UsbEventLog.MAX_TEXT_CHARS) return value
        return value.take(UsbEventLog.MAX_TEXT_CHARS - 3) + "..."
    }
}
