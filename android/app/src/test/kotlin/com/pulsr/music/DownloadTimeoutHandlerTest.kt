package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * A10 (N-06): Unit tests for DownloadTimeoutHandler (DL-24, DL-28).
 */
class DownloadTimeoutHandlerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun testTimeoutFlushesActiveTasksAndCleansCorruptPartFiles() {
        val activeTasks = mapOf(
            "vid_001" to 45,
            "vid_002" to 80,
            "vid_003" to 10
        )

        val validPartFile = tempFolder.newFile("track_001.mp4.part").apply {
            writeBytes(ByteArray(1024 * 512) { 0x55 }) // 512 KB partial
        }
        val zeroBytePartFile = tempFolder.newFile("track_002.mp4.part").apply {
            writeBytes(ByteArray(0))
        }

        var persistedMap: Map<String, Int>? = null
        val handler = DownloadTimeoutHandler(
            statePersistenceCallback = { flushed ->
                persistedMap = flushed
            }
        )

        val report = handler.handleTimeout(
            activeDownloads = activeTasks,
            partFiles = listOf(validPartFile, zeroBytePartFile)
        )

        assertEquals(3, report.activeTasksCount)
        assertEquals(listOf("vid_001", "vid_002", "vid_003"), report.flushedVideoIds)
        assertEquals(1, report.cleanedPartFilesCount)
        assertTrue(report.resumeScheduled)

        // Verify persistence callback received all tasks
        assertEquals(activeTasks, persistedMap)

        // Verify valid part file retained for Range resume
        assertTrue(validPartFile.exists())
        assertEquals(1024 * 512L, validPartFile.length())

        // Verify 0-byte orphan deleted
        assertFalse(zeroBytePartFile.exists())
    }

    @Test
    fun testFgsBudgetEvaluationTracks6HourLimit() {
        val handler = DownloadTimeoutHandler()
        val startTime = 1000000L

        // 1 hour in
        val status1 = handler.evaluateBudget(startTime, startTime + (1L * 60 * 60 * 1000))
        assertEquals(1L * 60 * 60 * 1000, status1.elapsedMs)
        assertEquals(5L * 60 * 60 * 1000, status1.remainingMs)
        assertFalse(status1.isExhausted)

        // 6 hours in (exhausted)
        val status6 = handler.evaluateBudget(startTime, startTime + (6L * 60 * 60 * 1000))
        assertEquals(6L * 60 * 60 * 1000, status6.elapsedMs)
        assertEquals(0L, status6.remainingMs)
        assertTrue(status6.isExhausted)
    }

    @Test
    fun testAdaptiveWatchdogKillsOnlyOnZeroBytesForTimeoutWindow() {
        val handler = DownloadTimeoutHandler()

        // Slow stream but alive (bytes transferred > 0) -> NOT stalled
        val slowAlive = handler.isStreamStalled(
            bytesReceivedSinceLastCheck = 1024,
            idleDurationMs = 35000,
            stallThresholdMs = 30000
        )
        assertFalse(slowAlive)

        // Zero bytes and idle time >= 30s -> Stalled
        val deadStream = handler.isStreamStalled(
            bytesReceivedSinceLastCheck = 0,
            idleDurationMs = 31000,
            stallThresholdMs = 30000
        )
        assertTrue(deadStream)

        // Zero bytes but idle time < 30s -> NOT yet stalled
        val freshStream = handler.isStreamStalled(
            bytesReceivedSinceLastCheck = 0,
            idleDurationMs = 15000,
            stallThresholdMs = 30000
        )
        assertFalse(freshStream)
    }

    @Test
    fun testLongQueueSimulationSurvivesTimeoutWithZeroOrphanedFiles() {
        val longQueue = (1..50).associate { "vid_$it" to (it * 2) % 100 }
        val partFiles = mutableListOf<File>()

        // Generate 50 partial download files
        for (i in 1..50) {
            val file = tempFolder.newFile("track_$i.mp4.part")
            if (i % 5 == 0) {
                file.writeBytes(ByteArray(0)) // 10 corrupt/empty files
            } else {
                file.writeBytes(ByteArray(1024 * i) { 0x01 }) // Valid partial files
            }
            partFiles.add(file)
        }

        var flushedCount = 0
        val handler = DownloadTimeoutHandler(
            statePersistenceCallback = { flushed ->
                flushedCount = flushed.size
            }
        )

        val report = handler.handleTimeout(longQueue, partFiles)

        assertEquals(50, report.activeTasksCount)
        assertEquals(50, flushedCount)
        assertEquals(10, report.cleanedPartFilesCount)

        // All remaining part files on disk must be valid (> 0 bytes)
        for (file in partFiles) {
            if (file.exists()) {
                assertTrue(file.length() > 0)
            }
        }
    }

    @Test
    fun testPreTimeoutEvaluationAt5h59m() {
        val handler = DownloadTimeoutHandler()
        val startTime = 1000000L
        val fiveHours59MinMs = (5L * 60 + 59) * 60 * 1000 // 21,540,000 ms

        // At 5h 58m -> Pre-timeout not reached
        val statusPre = handler.evaluateBudget(startTime, startTime + (5L * 60 + 58) * 60 * 1000)
        assertFalse(statusPre.isPreTimeoutReached)
        assertFalse(statusPre.isExhausted)

        // At 5h 59m -> Pre-timeout REACHED (triggers safe checkpoint before hard 6h system kill)
        val status5h59m = handler.evaluateBudget(startTime, startTime + fiveHours59MinMs)
        assertTrue(status5h59m.isPreTimeoutReached)
        assertFalse(status5h59m.isExhausted)
        assertEquals(60 * 1000L, status5h59m.remainingMs) // 1 minute safety margin remaining
    }

    @Test
    fun testProcessDeathRestoreAt3h() {
        val handler = DownloadTimeoutHandler()
        val previousElapsedAtDeath = 3L * 60 * 60 * 1000 // 3 hours accumulated prior to process kill

        // New session starts after process revival: current session has 0ms elapsed, but previous was 3h
        val newSessionStart = 5000000L
        val statusAtResume = handler.evaluateBudget(
            sessionStartMs = newSessionStart,
            currentTimeMs = newSessionStart,
            previousCumulativeMs = previousElapsedAtDeath
        )

        assertEquals(3L * 60 * 60 * 1000, statusAtResume.elapsedMs)
        assertEquals(3L * 60 * 60 * 1000, statusAtResume.remainingMs)
        assertFalse(statusAtResume.isExhausted)

        // Run 2 more hours in revived session -> Total 5 hours
        val statusAfter2MoreHours = handler.evaluateBudget(
            sessionStartMs = newSessionStart,
            currentTimeMs = newSessionStart + (2L * 60 * 60 * 1000),
            previousCumulativeMs = previousElapsedAtDeath
        )
        assertEquals(5L * 60 * 60 * 1000, statusAfter2MoreHours.elapsedMs)
        assertEquals(1L * 60 * 60 * 1000, statusAfter2MoreHours.remainingMs)
        assertFalse(statusAfter2MoreHours.isExhausted)
    }

    @Test
    fun testCumulativeCapAcrossTwoRestarts() {
        val handler = DownloadTimeoutHandler()

        // Session 1: 3.5 hours
        val session1Elapsed = (3.5 * 60 * 60 * 1000).toLong() // 12,600,000 ms

        // Session 2: 2.0 hours (Total = 5.5 hours)
        val session2Start = 10000000L
        val session2Elapsed = (2.0 * 60 * 60 * 1000).toLong()
        val totalAfterSession2 = session1Elapsed + session2Elapsed
        val statusSession2 = handler.evaluateBudget(
            sessionStartMs = session2Start,
            currentTimeMs = session2Start + session2Elapsed,
            previousCumulativeMs = session1Elapsed
        )
        assertEquals(totalAfterSession2, statusSession2.elapsedMs)
        assertEquals(1800000L, statusSession2.remainingMs) // 30 mins remaining
        assertFalse(statusSession2.isExhausted)

        // Session 3: 0.6 hours (36 mins) -> Total = 6.1 hours -> Cap exhausted!
        val session3Start = 20000000L
        val session3Elapsed = (36L * 60 * 1000)
        val statusSession3 = handler.evaluateBudget(
            sessionStartMs = session3Start,
            currentTimeMs = session3Start + session3Elapsed,
            previousCumulativeMs = totalAfterSession2
        )
        assertTrue(statusSession3.isExhausted)
        assertEquals(0L, statusSession3.remainingMs)
    }

    @Test
    fun testAndroid15And16Semantics() {
        val handler = DownloadTimeoutHandler()

        // Boot-completed direct FGS start check:
        // Allowed on API 28..34, BLOCKED on API 35 (Android 15) and API 36 (Android 16)
        assertTrue(handler.canStartFgsFromBoot(28))
        assertTrue(handler.canStartFgsFromBoot(33))
        assertTrue(handler.canStartFgsFromBoot(34))
        assertFalse(handler.canStartFgsFromBoot(35))
        assertFalse(handler.canStartFgsFromBoot(36))

        // FGS Type Selection:
        // API 35 & 36 -> MEDIA_PROCESSING (2048)
        // API 34 -> DATA_SYNC (1)
        // API 28 -> Untyped (0)
        assertEquals(2048, handler.getRecommendedFgsType(36))
        assertEquals(2048, handler.getRecommendedFgsType(35))
        assertEquals(1, handler.getRecommendedFgsType(34))
        assertEquals(0, handler.getRecommendedFgsType(28))
    }
}
