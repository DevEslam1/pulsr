package com.pulsr.music

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.ceil

/**
 * High-performance, thread-safe in-memory metrics registry for YTM subsystem operations.
 * Tracks execution counts, error counts, P50 and P95 latencies in rolling sample windows.
 */
object YtmMetricsRegistry {
    private const val MAX_WINDOW_SAMPLES = 200

    class OpMetrics {
        val totalCount = AtomicLong(0L)
        val errorCount = AtomicLong(0L)
        private val latencySamples = ConcurrentLinkedQueue<Long>()

        fun record(durationMs: Long, isError: Boolean = false) {
            totalCount.incrementAndGet()
            if (isError) {
                errorCount.incrementAndGet()
            }
            latencySamples.add(durationMs)
            while (latencySamples.size > MAX_WINDOW_SAMPLES) {
                latencySamples.poll()
            }
        }

        fun snapshot(): Map<String, Any> {
            val samples = latencySamples.toList().sorted()
            val count = totalCount.get()
            val errors = errorCount.get()
            val p50 = if (samples.isNotEmpty()) {
                val idx = (samples.size * 0.50).toInt().coerceIn(0, samples.size - 1)
                samples[idx]
            } else 0L

            val p95 = if (samples.isNotEmpty()) {
                val idx = (samples.size * 0.95).toInt().coerceIn(0, samples.size - 1)
                samples[idx]
            } else 0L

            val errRate = if (count > 0) (errors.toDouble() / count.toDouble()) else 0.0

            return mapOf(
                "totalCount" to count,
                "errorCount" to errors,
                "errorRate" to errRate,
                "p50Ms" to p50,
                "p95Ms" to p95,
                "windowSize" to samples.size
            )
        }

        fun reset() {
            totalCount.set(0L)
            errorCount.set(0L)
            latencySamples.clear()
        }
    }

    private val metricsMap = ConcurrentHashMap<String, OpMetrics>()

    private fun getOp(name: String): OpMetrics =
        metricsMap.computeIfAbsent(name) { OpMetrics() }

    fun record(operation: String, durationMs: Long, isError: Boolean = false) {
        getOp(operation).record(durationMs, isError)
    }

    inline fun <T> measure(operation: String, block: () -> T): T {
        val start = System.currentTimeMillis()
        var error = false
        try {
            return block()
        } catch (t: Throwable) {
            error = true
            throw t
        } finally {
            record(operation, System.currentTimeMillis() - start, error)
        }
    }

    fun snapshotAll(): Map<String, Map<String, Any>> =
        metricsMap.mapValues { it.value.snapshot() }

    fun resetAll() {
        metricsMap.values.forEach { it.reset() }
    }
}
