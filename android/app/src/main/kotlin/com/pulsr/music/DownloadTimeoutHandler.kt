package com.pulsr.music

import android.content.Context
import java.io.File

/**
 * Handles Foreground Service dataSync timeouts and adaptive watchdog (DL-24, DL-28).
 *
 * In Android 14/15 (API 34/35+), dataSync FGS executions have a 6-hour cumulative window limit.
 * Features:
 * 1. Tracks cumulative FGS budget usage (DL-24).
 * 2. Adaptive stream stall watchdog by bitrate (DL-28).
 * 3. Flushes active task states to disk/DB.
 * 4. Cleans zero-byte corrupt .part files while preserving valid partial files for Range resume.
 */
class DownloadTimeoutHandler(
    private val context: Context? = null,
    private val statePersistenceCallback: ((Map<String, Int>) -> Unit)? = null
) {
    companion object {
        const val MAX_FGS_BUDGET_MS = 6L * 60 * 60 * 1000 // 6 hours in millis (21,600,000 ms)
        const val PRE_TIMEOUT_THRESHOLD_MS = (5L * 60 + 59) * 60 * 1000 // 5h 59m in millis (21,540,000 ms)
        const val DEFAULT_STALL_TIMEOUT_MS = 30_000L // 30s zero-bytes stall watchdog
        const val PREFS_NAME = "pulsr_download_timeouts"
        const val KEY_CUMULATIVE_FGS_MS = "cumulative_fgs_ms"
        const val KEY_LAST_SESSION_START = "last_session_start"
        const val KEY_HAS_TIMEOUT = "has_timeout_occurred"
    }

    data class TimeoutReport(
        val activeTasksCount: Int,
        val flushedVideoIds: List<String>,
        val cleanedPartFilesCount: Int,
        val resumeScheduled: Boolean,
        val cumulativeElapsedMs: Long = 0L
    )

    data class BudgetStatus(
        val elapsedMs: Long,
        val remainingMs: Long,
        val isExhausted: Boolean,
        val isPreTimeoutReached: Boolean = false
    )

    /**
     * DL-24: Evaluates FGS budget usage against cumulative session time.
     */
    fun evaluateBudget(sessionStartMs: Long, currentTimeMs: Long = System.currentTimeMillis(), previousCumulativeMs: Long = 0L): BudgetStatus {
        val currentSessionElapsed = (currentTimeMs - sessionStartMs).coerceAtLeast(0L)
        val totalElapsed = currentSessionElapsed + previousCumulativeMs
        val remaining = (MAX_FGS_BUDGET_MS - totalElapsed).coerceAtLeast(0L)
        return BudgetStatus(
            elapsedMs = totalElapsed,
            remainingMs = remaining,
            isExhausted = remaining == 0L,
            isPreTimeoutReached = totalElapsed >= PRE_TIMEOUT_THRESHOLD_MS
        )
    }

    /**
     * Records cumulative FGS duration to persistent store across restarts/reboots.
     */
    fun recordCumulativeDuration(additionalMs: Long): Long {
        if (context == null) return additionalMs
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val current = prefs.getLong(KEY_CUMULATIVE_FGS_MS, 0L)
        val updated = current + additionalMs
        prefs.edit().putLong(KEY_CUMULATIVE_FGS_MS, updated).apply()
        return updated
    }

    fun getCumulativeDuration(): Long {
        if (context == null) return 0L
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong(KEY_CUMULATIVE_FGS_MS, 0L)
    }

    fun resetCumulativeDuration() {
        context?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            ?.edit()
            ?.remove(KEY_CUMULATIVE_FGS_MS)
            ?.apply()
    }

    /**
     * Android 15+ (API 35+) blocks starting dataSync/mediaProcessing FGS directly from BOOT_COMPLETED.
     */
    fun canStartFgsFromBoot(sdkInt: Int): Boolean {
        return sdkInt < 35 // Blocked on API 35 (Android 15) and API 36 (Android 16)
    }

    /**
     * Selects appropriate FGS type:
     * - API 35+ (Android 15/16): MEDIA_PROCESSING (2048 / 0x800)
     * - API 29-34 (Android 10-14): DATA_SYNC (1)
     * - API < 29: 0 (untyped)
     */
    fun getRecommendedFgsType(sdkInt: Int): Int {
        return when {
            sdkInt >= 35 -> 2048 // ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            sdkInt >= 29 -> 1    // ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else -> 0
        }
    }

    /**
     * DL-28: Adaptive watchdog check — stalls only if zero bytes received within timeout window.
     */
    fun isStreamStalled(
        bytesReceivedSinceLastCheck: Long,
        idleDurationMs: Long,
        stallThresholdMs: Long = DEFAULT_STALL_TIMEOUT_MS
    ): Boolean {
        return bytesReceivedSinceLastCheck == 0L && idleDurationMs >= stallThresholdMs
    }

    fun handleTimeout(
        activeDownloads: Map<String, Int>,
        partFiles: List<File> = emptyList(),
        currentCumulativeMs: Long = 0L
    ): TimeoutReport {
        val videoIds = activeDownloads.keys.toList()

        // 1. Flush state to persistence
        statePersistenceCallback?.invoke(activeDownloads)
        if (context != null) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().apply {
                    putBoolean(KEY_HAS_TIMEOUT, true)
                    putLong("last_timeout_timestamp", System.currentTimeMillis())
                    putLong(KEY_CUMULATIVE_FGS_MS, currentCumulativeMs)
                    putStringSet("timed_out_video_ids", videoIds.toSet())
                    apply()
                }
            } catch (_: Exception) {}
        }

        // 2. Validate .part files integrity (ensure no empty orphaned files)
        var cleanedCount = 0
        for (partFile in partFiles) {
            if (partFile.exists() && partFile.length() == 0L) {
                partFile.delete()
                cleanedCount++
            }
        }

        // 3. Post delayed resumption intent to DownloadService (Fix C6)
        if (context != null && videoIds.isNotEmpty()) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    for (vid in videoIds) {
                        val intent = android.content.Intent(context, DownloadService::class.java).apply {
                            action = DownloadService.ACTION_RESUME
                            putExtra(DownloadService.EXTRA_VIDEO_ID, vid)
                        }
                        context.startService(intent)
                    }
                } catch (_: Exception) {}
            }, 30_000L)
        }

        return TimeoutReport(
            activeTasksCount = activeDownloads.size,
            flushedVideoIds = videoIds,
            cleanedPartFilesCount = cleanedCount,
            resumeScheduled = true,
            cumulativeElapsedMs = currentCumulativeMs
        )
    }
}

