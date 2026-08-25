package com.pulsr.music

import android.os.SystemClock
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.min
import kotlin.random.Random

/**
 * Token-Bucket Rate Limiter with Exponential Backoff and Jitter.
 *
 * Enforces a maximum request rate across all Innertube requests (default 6 req/s with burst of 10).
 * Handles HTTP 429 backoff gracefully with randomized jitter (±20%) to avoid thundering herds.
 */
internal class RateLimiter(
    private val maxTokens: Int = 10,
    private val refillTokensPerSecond: Double = 6.0,
) {
    private val availableTokens = AtomicInteger(maxTokens)
    private val lastRefillTimestamp = AtomicLong(SystemClock.elapsedRealtime())
    private val backoffUntilTimestamp = AtomicLong(0L)
    private val consecutiveThrottles = AtomicInteger(0)

    private val lock = Any()

    /**
     * Blocks the calling thread until a token permit is available and any backoff has elapsed.
     */
    fun acquirePermit() {
        while (true) {
            val now = SystemClock.elapsedRealtime()
            val backoffUntil = backoffUntilTimestamp.get()

            if (now < backoffUntil) {
                val sleepTime = backoffUntil - now
                if (sleepTime > 0) {
                    try {
                        Thread.sleep(sleepTime)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return
                    }
                }
                continue
            }

            synchronized(lock) {
                refillTokens()
                val current = availableTokens.get()
                if (current > 0) {
                    availableTokens.decrementAndGet()
                    return
                }
            }

            // If tokens are exhausted, sleep briefly before trying again
            try {
                Thread.sleep(100)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
    }

    private fun refillTokens() {
        val now = SystemClock.elapsedRealtime()
        val lastRefill = lastRefillTimestamp.get()
        val elapsedSeconds = (now - lastRefill) / 1000.0

        if (elapsedSeconds > 0) {
            val newTokens = (elapsedSeconds * refillTokensPerSecond).toInt()
            if (newTokens > 0) {
                val current = availableTokens.get()
                val updated = min(maxTokens, current + newTokens)
                availableTokens.set(updated)
                lastRefillTimestamp.set(now)
            }
        }
    }

    /**
     * Signals an HTTP 429 Too Many Requests response.
     * Triggers exponential backoff (1s -> 2s -> 4s -> 8s ... capped at 30s) with +/-20% jitter.
     */
    fun onRateLimited(): Long {
        val throttleCount = consecutiveThrottles.incrementAndGet().coerceAtMost(5)
        val baseDelayMs = (1L shl (throttleCount - 1)) * 1000L // 1s, 2s, 4s, 8s, 16s...
        val cappedDelayMs = min(baseDelayMs, 30_000L)

        // Jitter: +/- 20%
        val jitterRange = (cappedDelayMs * 0.2).toLong().coerceAtLeast(100L)
        val jitter = Random.nextLong(-jitterRange, jitterRange)
        val delayWithJitter = (cappedDelayMs + jitter).coerceAtLeast(500L)

        val now = SystemClock.elapsedRealtime()
        val backoffUntil = now + delayWithJitter
        backoffUntilTimestamp.set(backoffUntil)

        // Drain tokens to enforce immediate pause
        availableTokens.set(0)
        return delayWithJitter
    }

    /**
     * Resets backoff count on successful requests.
     */
    fun onSuccess() {
        consecutiveThrottles.set(0)
    }

    companion object {
        val shared = RateLimiter(maxTokens = 10, refillTokensPerSecond = 6.0)
    }
}
