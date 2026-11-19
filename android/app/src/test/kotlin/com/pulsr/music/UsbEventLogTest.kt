package com.pulsr.music

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Schema, serialisation, redaction, bounded-memory and concurrency contract of
 * [UsbEventLog]. The JSON assertions use org.json (test-only dependency) so the
 * export is validated by an independent parser rather than by itself.
 */
class UsbEventLogTest {

    private val schemaFields = setOf(
        "timestampMs",
        "build",
        "deviceModel",
        "androidVersion",
        "vid",
        "pid",
        "uacVersion",
        "interfaceNumber",
        "altSetting",
        "endpoint",
        "rate",
        "depth",
        "channels",
        "clockSource",
        "selectorPin",
        "feedbackPresent",
        "clockDriftPpm",
        "ringFillMs",
        "underrunCount",
        "overrunCount",
        "lastError",
        "drainPending",
        "resultCode",
    )

    private fun sampleEvent(timestampMs: Long = 1_000L) = UsbEvent(
        timestampMs = timestampMs,
        build = "1.0.0+1 (dev)",
        deviceModel = "FiiO K7 BT",
        androidVersion = "14 (SDK 34)",
        vid = 0x2972,
        pid = 0x00A1,
        uacVersion = 2,
        interfaceNumber = 2,
        altSetting = 1,
        endpoint = 0x82,
        rate = 96_000,
        depth = 24,
        channels = 2,
        clockSource = 3,
        selectorPin = 255,
        feedbackPresent = true,
        clockDriftPpm = 12.5,
        ringFillMs = 18,
        underrunCount = 1,
        overrunCount = 2,
        lastError = null,
        drainPending = false,
        resultCode = 0,
    )

    private inline fun expectIllegalArgument(label: String, block: () -> Unit) {
        try {
            block()
        } catch (_: IllegalArgumentException) {
            return
        }
        throw AssertionError("$label: expected IllegalArgumentException")
    }

    // ------------------------------------------------------------------ schema

    @Test
    fun eventCarriesExactlyTheDocumentedFields() {
        val declared = UsbEvent::class.java.declaredFields
            .filterNot { it.isSynthetic }
            .map { it.name }
            .toSet()
        assertEquals("UsbEvent field set must match the support schema", schemaFields, declared)
        assertEquals(23, schemaFields.size)
    }

    @Test
    fun jsonUsesExactlyTheSchemaFieldNames() {
        val log = UsbEventLog(4)
        log.record(sampleEvent())
        val array = JSONArray(log.toJson())
        assertEquals(1, array.length())
        val keys = array.getJSONObject(0).keys().asSequence().toSet()
        assertEquals(schemaFields, keys)
    }

    // ------------------------------------------------------------- ring buffer

    @Test
    fun ringBufferEvictsOldestAndNeverGrows() {
        val log = UsbEventLog(3)
        repeat(5) { index -> log.record(sampleEvent(index.toLong())) }
        assertEquals(3, log.size())
        val timestamps = log.snapshot().map { it.timestampMs }
        assertEquals(listOf(2L, 3L, 4L), timestamps)
        assertEquals(3, JSONArray(log.toJson()).length())
    }

    @Test
    fun snapshotIsADefensiveCopy() {
        val log = UsbEventLog(8)
        log.record(sampleEvent(1))
        val first = log.snapshot()
        log.record(sampleEvent(2))
        assertEquals(1, first.size)
        assertEquals(2, log.snapshot().size)
        assertEquals(2, log.size())
    }

    @Test
    fun recordReturnsTheStoredSanitisedEvent() {
        val log = UsbEventLog(8)
        val stored = log.record(sampleEvent(7))
        assertEquals(7L, stored.timestampMs)
        assertEquals(stored, log.snapshot().single())
        assertEquals(stored, log.record(sampleEvent(7)))
    }

    @Test
    fun clearDropsEverything() {
        val log = UsbEventLog(8)
        repeat(3) { log.record(sampleEvent(it.toLong())) }
        assertEquals(3, log.size())
        log.clear()
        assertEquals(0, log.size())
        assertTrue(log.snapshot().isEmpty())
        assertEquals("[]", log.toJson())
    }

    @Test
    fun capacityIsValidated() {
        expectIllegalArgument("capacity 0") { UsbEventLog(0) }
        expectIllegalArgument("negative capacity") { UsbEventLog(-1) }
        expectIllegalArgument("capacity above the ceiling") { UsbEventLog(UsbEventLog.MAX_CAPACITY + 1) }
        assertEquals(UsbEventLog.DEFAULT_CAPACITY, UsbEventLog().capacity)
    }

    // -------------------------------------------------------------------- json

    @Test
    fun jsonIsValidStableAndRoundTripsEveryField() {
        val log = UsbEventLog(4)
        log.record(sampleEvent(1_795_000_000_000L))

        val first = log.toJson()
        assertEquals("serialisation must be deterministic", first, log.toJson())

        val obj = JSONArray(first).getJSONObject(0)
        assertEquals(1_795_000_000_000L, obj.getLong("timestampMs"))
        assertEquals("1.0.0+1 (dev)", obj.getString("build"))
        assertEquals("FiiO K7 BT", obj.getString("deviceModel"))
        assertEquals("14 (SDK 34)", obj.getString("androidVersion"))
        assertEquals(0x2972, obj.getInt("vid"))
        assertEquals(0x00A1, obj.getInt("pid"))
        assertEquals(2, obj.getInt("uacVersion"))
        assertEquals(2, obj.getInt("interfaceNumber"))
        assertEquals(1, obj.getInt("altSetting"))
        assertEquals(0x82, obj.getInt("endpoint"))
        assertEquals(96_000, obj.getInt("rate"))
        assertEquals(24, obj.getInt("depth"))
        assertEquals(2, obj.getInt("channels"))
        assertEquals(3, obj.getInt("clockSource"))
        assertEquals(255, obj.getInt("selectorPin"))
        assertTrue(obj.getBoolean("feedbackPresent"))
        assertEquals(12.5, obj.getDouble("clockDriftPpm"), 0.0005)
        assertEquals(18L, obj.getLong("ringFillMs"))
        assertEquals(1L, obj.getLong("underrunCount"))
        assertEquals(2L, obj.getLong("overrunCount"))
        assertTrue(obj.isNull("lastError"))
        assertFalse(obj.getBoolean("drainPending"))
        assertEquals(0, obj.getInt("resultCode"))
    }

    @Test
    fun jsonEscapesControlCharactersAndQuotes() {
        val log = UsbEventLog(4)
        val stored = log.record(
            sampleEvent().copy(deviceModel = "DAC \"Pro\"\\mk2\nline2\ttab\u0001end")
        )

        val json = log.toJson()
        assertFalse("raw newlines must be escaped", json.contains("\n"))
        assertFalse("raw tabs must be escaped", json.contains("\t"))
        assertFalse("raw control bytes must not survive", json.contains("\u0001"))

        val parsed = JSONArray(json).getJSONObject(0).getString("deviceModel")
        assertEquals(stored.deviceModel, parsed)
        assertTrue(parsed.startsWith("DAC \"Pro\"\\mk2"))
    }

    @Test
    fun nonFiniteDriftIsSerialisedAsZero() {
        val log = UsbEventLog(4)
        val stored = log.record(sampleEvent().copy(clockDriftPpm = Double.NaN))
        assertEquals(0.0, stored.clockDriftPpm, 0.0)
        val obj = JSONArray(log.toJson()).getJSONObject(0)
        assertEquals(0.0, obj.getDouble("clockDriftPpm"), 0.0)

        log.clear()
        log.record(sampleEvent().copy(clockDriftPpm = Double.NEGATIVE_INFINITY))
        assertEquals(0.0, JSONArray(log.toJson()).getJSONObject(0).getDouble("clockDriftPpm"), 0.0)
    }

    // --------------------------------------------------------------- redaction

    @Test
    fun absolutePathsAreRedactedFromEveryTextField() {
        val log = UsbEventLog(8)
        val stored = log.record(
            sampleEvent().copy(
                build = "debug /data/local/tmp/pulsr",
                deviceModel = "C:\\Users\\alice\\DAC",
                androidVersion = "/storage/emulated/0/Android",
                lastError = "open failed: /data/app/com.pulsr.music/base.apk",
            )
        )

        assertEquals("debug [redacted_path]", stored.build)
        assertEquals("[redacted_path]", stored.deviceModel)
        assertEquals("[redacted_path]", stored.androidVersion)
        assertEquals("open failed: [redacted_path]", stored.lastError)

        val json = log.toJson()
        assertFalse(json.contains("/data/"))
        assertFalse(json.contains("/storage/"))
        assertFalse(json.contains("alice"))
        assertFalse(json.contains("base.apk"))
    }

    @Test
    fun serialLikeTokensAreRedactedButModelNamesSurvive() {
        val log = UsbEventLog(8)
        val stored = log.record(
            sampleEvent().copy(
                deviceModel = "DAC A1B2C3D4E5",
                lastError = "SN: ABCDEFGH",
            )
        )

        assertEquals("DAC [redacted_serial]", stored.deviceModel)
        assertEquals("[redacted_serial]", stored.lastError)

        val plain = log.record(sampleEvent().copy(deviceModel = "AUDIOQUEST DAC", lastError = "ERR_UNDERRUN_42"))
        assertEquals("a model name is not a serial", "AUDIOQUEST DAC", plain.deviceModel)
        assertEquals("ERR_UNDERRUN_42", plain.lastError)
    }

    @Test
    fun emailAddressesAreRedacted() {
        val log = UsbEventLog(4)
        val stored = log.record(
            sampleEvent().copy(lastError = "auth failed for alice.wonder+usb@example.com")
        )
        assertEquals("auth failed for [redacted_email]", stored.lastError)
        assertFalse(log.toJson().contains("alice"))
        assertFalse(log.toJson().contains("@example.com"))
    }

    @Test
    fun rawDescriptorByteDumpsAreRedacted() {
        val log = UsbEventLog(4)
        val dump = "desc 09 02 4B 00 02 01 00 80 32 09 04 00 00 01 01 00 00 00 00"
        val stored = log.record(sampleEvent().copy(lastError = dump))

        assertEquals("desc [redacted_bytes]", stored.lastError)

        val field = JSONArray(log.toJson()).getJSONObject(0).getString("lastError")
        assertFalse("no byte pair may survive", Regex("""\b[0-9A-Fa-f]{2}\b""").containsMatchIn(field))
    }

    @Test
    fun everyStringFieldIsFreeOfLongHexRuns() {
        val log = UsbEventLog(4)
        log.record(
            sampleEvent().copy(
                build = "A1B2C3D4E5F6",
                deviceModel = "0123456789ABCDEF",
                androidVersion = "deadbeefcafe",
                lastError = "serial=ABCDEF0123456789",
            )
        )
        val obj = JSONArray(log.toJson()).getJSONObject(0)
        for (field in listOf("build", "deviceModel", "androidVersion", "lastError")) {
            val value = obj.getString(field)
            assertFalse(
                "$field leaked a long hex token: $value",
                Regex("[0-9A-Fa-f]{8,}").containsMatchIn(value),
            )
        }
    }

    @Test
    fun overlongTextIsTruncatedToKeepExportsSmall() {
        val log = UsbEventLog(4)
        val stored = log.record(sampleEvent().copy(lastError = "x".repeat(4_096)))
        val text = stored.lastError!!
        assertTrue("length ${text.length}", text.length <= UsbEventLog.MAX_TEXT_CHARS)
        assertTrue(text.endsWith("..."))
        assertTrue(log.toJson().length < 4_096)
    }

    // ---------------------------------------------------------- bounded memory

    @Test
    fun tenThousandAppendsStayWithinCapacityAndJsonBudget() {
        val log = UsbEventLog()
        repeat(10_000) { index ->
            log.record(
                sampleEvent().copy(
                    timestampMs = 1_795_000_000_000L + index,
                    lastError = if (index % 97 == 0) "underrun at ring fill 18 ms" else null,
                )
            )
        }

        assertEquals(UsbEventLog.DEFAULT_CAPACITY, log.size())
        assertEquals(UsbEventLog.DEFAULT_CAPACITY, log.snapshot().size)

        val json = log.toJson()
        val bytes = json.toByteArray(Charsets.UTF_8).size
        assertTrue("serialised export was $bytes bytes, budget is 262144", bytes < 256 * 1024)

        val array = JSONArray(json)
        assertEquals(UsbEventLog.DEFAULT_CAPACITY, array.length())
        assertEquals(1_795_000_000_000L + 9_500, array.getJSONObject(0).getLong("timestampMs"))
        assertEquals(1_795_000_000_000L + 9_999, array.getJSONObject(499).getLong("timestampMs"))
    }

    // -------------------------------------------------------------- concurrency

    @Test
    fun concurrentAppendsStayBoundedAndConsistent() {
        val log = UsbEventLog(500)
        val threads = 4
        val perThread = 2_500
        val start = CountDownLatch(1)
        val workers = (0 until threads).map { threadIndex ->
            Thread {
                start.await()
                repeat(perThread) { i ->
                    log.record(
                        UsbEvent(
                            timestampMs = 1_000_000L + threadIndex * 100_000L + i,
                            deviceModel = "thread-$threadIndex",
                            resultCode = i,
                        )
                    )
                }
            }.apply { isDaemon = true; name = "event-log-$threadIndex" }
        }

        workers.forEach { it.start() }
        start.countDown()
        workers.forEach { it.join(TimeUnit.SECONDS.toMillis(60)) }
        assertTrue("workers must finish", workers.none { it.isAlive })

        assertEquals(500, log.size())
        val snapshot = log.snapshot()
        assertEquals(500, snapshot.size)
        assertTrue(snapshot.all { it.timestampMs > 0 })

        val parsed = JSONArray(log.toJson())
        assertEquals(500, parsed.length())
        for (index in 0 until parsed.length()) {
            val model = parsed.getJSONObject(index).getString("deviceModel")
            assertTrue("unexpected device model '$model'", model.startsWith("thread-"))
        }
    }
}
