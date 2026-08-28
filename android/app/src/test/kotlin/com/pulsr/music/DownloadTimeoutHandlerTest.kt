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
}
