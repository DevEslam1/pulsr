package com.pulsr.music

import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.math.ceil

/**
 * Task 4 / Pillar 4: Real-time Latency Tracker for Tap-to-Sound Metrics.
 *
 * Tracks the elapsed duration from user tap (track selection / advance) to the first
 * audio buffer render in the playback pipeline.
 * Computes rolling p50 (median) and p95 percentiles over a bounded window of recent samples.
 */
object LatencyTracker {
    private const val MAX_SAMPLES = 100

    private val inFlightTaps = ConcurrentHashMap<String, Long>()
    private val samples = CopyOnWriteArrayList<Long>()
    private val lock = Any()

    private fun nowMs(): Long = try {
        SystemClock.elapsedRealtime()
    } catch (_: Throwable) {
        System.currentTimeMillis()
    }

    /**
     * Records a tap event for [trackId].
     */
    fun recordTap(trackId: String, timestampMs: Long = nowMs()) {
        inFlightTaps[trackId] = timestampMs
    }

    /**
     * Records the moment sound is first rendered for [trackId], recording the delta.
     * Returns the latency in milliseconds, or -1 if no tap was recorded.
     */
    fun recordSound(trackId: String, timestampMs: Long = nowMs()): Long {
        val tapTime = inFlightTaps.remove(trackId) ?: return -1L
        val latency = (timestampMs - tapTime).coerceAtLeast(0L)
        synchronized(lock) {
            samples.add(latency)
            if (samples.size > MAX_SAMPLES) {
                samples.removeAt(0)
            }
        }
        return latency
    }

    /**
     * Records an explicit latency measurement directly in milliseconds.
     */
    fun recordMeasurement(latencyMs: Long) {
        if (latencyMs < 0) return
        synchronized(lock) {
            samples.add(latencyMs)
            if (samples.size > MAX_SAMPLES) {
                samples.removeAt(0)
            }
        }
    }

    /**
     * Returns rolling p50 (median) latency in milliseconds, or 0 if no samples.
     */
    fun getP50(): Long = getPercentile(50.0)

    /**
     * Returns rolling p95 latency in milliseconds, or 0 if no samples.
     */
    fun getP95(): Long = getPercentile(95.0)

    /**
     * Calculates the [percentile] (0.0 to 100.0) value from the rolling sample window.
     */
    fun getPercentile(percentile: Double): Long {
        synchronized(lock) {
            if (samples.isEmpty()) return 0L
            val sorted = samples.sorted()
            val index = ceil((percentile / 100.0) * sorted.size).toInt() - 1
            val clampedIndex = index.coerceIn(0, sorted.size - 1)
            return sorted[clampedIndex]
        }
    }

    val sampleCount: Int
        get() = samples.size

    fun reset() {
        synchronized(lock) {
            samples.clear()
            inFlightTaps.clear()
        }
    }

    fun getSummary(): Map<String, Any> {
        synchronized(lock) {
            val count = samples.size
            if (count == 0) {
                return mapOf(
                    "count" to 0,
                    "p50Ms" to 0L,
                    "p95Ms" to 0L,
                    "minMs" to 0L,
                    "maxMs" to 0L
                )
            }
            val sorted = samples.sorted()
            val p50 = getP50()
            val p95 = getP95()
            return mapOf(
                "count" to count,
                "p50Ms" to p50,
                "p95Ms" to p95,
                "minMs" to sorted.first(),
                "maxMs" to sorted.last(),
                "lastMs" to (samples.lastOrNull() ?: 0L)
            )
        }
    }
}
