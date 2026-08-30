package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.math.min
import kotlin.random.Random

/**
 * Layer 5: Adaptive Rate Limiter with Multi-Bucket Pacing, Jitter, and Persistence.
 *
 * Features:
 * - Per-endpoint token buckets (SEARCH, BROWSE, PLAYER, STREAM, DOWNLOAD)
 * - Global concurrency cap (max 8 in-flight requests)
 * - Adaptive multiplier (doubles cooldown on 429, decays after 10m clean traffic)
 * - Full-jitter exponential backoff (base 1s, capped at 15 min)
 * - Retry-After header respect
 * - SharedPreferences persistence across app restarts
 * - Injectable Clock for deterministic testing
 */
class RateLimiter(
    private val clock: Clock = SystemClockImpl(),
    private var prefs: SharedPreferences? = null,
    val respectfulMode: Boolean = true
) {
    interface Clock {
        fun elapsedRealtime(): Long
        fun currentTimeMillis(): Long
        fun sleep(millis: Long)
    }

    class SystemClockImpl : Clock {
        override fun elapsedRealtime(): Long = try {
            SystemClock.elapsedRealtime()
        } catch (_: Throwable) {
            System.currentTimeMillis()
        }
        override fun currentTimeMillis(): Long = System.currentTimeMillis()
        override fun sleep(millis: Long) = Thread.sleep(millis)
    }

    enum class Bucket(val maxTokens: Int, val refillPerSecond: Double, val minGapMs: Long) {
        SEARCH(3, 1.0, 1000L),
        BROWSE(5, 2.0, 300L),
        PLAYER(5, 2.0, 200L),
        STREAM(12, 6.0, 50L),
        DOWNLOAD(6, 3.0, 200L)
    }

    private class BucketState(val bucket: Bucket, var availableTokens: Double, var lastRefill: Long, var lastRequest: Long = 0L)

    private val bucketStates = ConcurrentHashMap<Bucket, BucketState>()
    private val globalSemaphore = Semaphore(8, true)
    private val backoffUntilTimestamp = AtomicLong(0L)
    private val adaptiveMultiplier = AtomicInteger(1)
    private val lastSuccessTimestamp = AtomicLong(0L)
    private val consecutiveThrottles = AtomicInteger(0)
    private val consecutiveSuccesses = AtomicInteger(0)

    private val lock = ReentrantLock()
    private val condition = lock.newCondition()

    init {
        val now = clock.elapsedRealtime()
        for (b in Bucket.values()) {
            bucketStates[b] = BucketState(b, b.maxTokens.toDouble(), now)
        }
    }

    fun initPrefs(context: Context) {
        prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val savedBackoff = prefs?.getLong(KEY_BACKOFF_UNTIL, 0L) ?: 0L
        val nowWall = clock.currentTimeMillis()
        if (savedBackoff > nowWall) {
            val remainingMs = savedBackoff - nowWall
            // TTFA: clamp restored backoff at launch so a prior session's 429
            // spiral cannot silently delay the first play. In-session adaptive
            // AIMD backoff (onRateLimited) is unaffected.
            val clampedMs = remainingMs.coerceAtMost(LAUNCH_BACKOFF_CLAMP_MS)
            backoffUntilTimestamp.set(clock.elapsedRealtime() + clampedMs)
        }
    }

    /**
     * Acquires permit for [bucket], honoring concurrency cap and pacing floors.
     */
    fun acquirePermit(bucket: Bucket = Bucket.PLAYER) {
        // 1. Global in-flight concurrency limiter — ensure release on interrupt
        var acquired = false
        try {
            globalSemaphore.acquire()
            acquired = true
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            return
        }
        val startWait = clock.elapsedRealtime()
        var releasedOnExit = false

        fun releaseIfNeeded() {
            if (acquired && !releasedOnExit) {
                releasedOnExit = true
                globalSemaphore.release()
            }
        }

        while (true) {
            val now = clock.elapsedRealtime()
            val backoffUntil = backoffUntilTimestamp.get()

            if (now < backoffUntil) {
                val sleepTime = backoffUntil - now
                if (sleepTime > 0) {
                    lock.lock()
                    try {
                        condition.await(sleepTime, TimeUnit.MILLISECONDS)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        releaseIfNeeded()
                        return
                    } finally {
                        lock.unlock()
                    }
                }
                continue
            }

            lock.lock()
            try {
                // Check clean traffic decay (10 minutes clean decays multiplier)
                val lastSuccess = lastSuccessTimestamp.get()
                if (lastSuccess > 0 && (now - lastSuccess) > 600_000L) {
                    adaptiveMultiplier.set(1)
                }

                val state = bucketStates[bucket] ?: BucketState(bucket, bucket.maxTokens.toDouble(), now).also {
                    bucketStates[bucket] = it
                }

                // Refill bucket tokens
                val elapsedSec = (now - state.lastRefill) / 1000.0
                if (elapsedSec > 0) {
                    val currentMultiplier = adaptiveMultiplier.get()
                    val effectiveRefill = bucket.refillPerSecond / currentMultiplier.toDouble()
                    state.availableTokens = min(bucket.maxTokens.toDouble(), state.availableTokens + (elapsedSec * effectiveRefill))
                    state.lastRefill = now
                }

                // Check respectful human pacing gap
                if (respectfulMode && bucket.minGapMs > 0 && state.lastRequest > 0) {
                    val gapElapsed = now - state.lastRequest
                    val currentMult = adaptiveMultiplier.get()
                    val requiredGap = bucket.minGapMs * currentMult
                    if (gapElapsed < requiredGap) {
                        val waitGap = requiredGap - gapElapsed + (0..150).random()
                        try {
                            condition.await(waitGap, TimeUnit.MILLISECONDS)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                            releaseIfNeeded()
                            return
                        }
                        continue
                    }
                }

                if (state.availableTokens >= 1.0) {
                    state.availableTokens -= 1.0
                    state.lastRequest = now
                    val waitTotal = clock.elapsedRealtime() - startWait
                    if (waitTotal > 10) {
                        if (bucket == Bucket.PLAYER) {
                            // TTFA telemetry: player-bucket waits ride the
                            // one-way relay into the Sentry playback span.
                            YtmMetricsRegistry.recordRelayed("rate_limiter.wait_player", waitTotal)
                        } else {
                            YtmMetricsRegistry.record("rate_limiter.wait_${bucket.name.lowercase()}", waitTotal)
                        }
                    }
                    // Success path: caller must release via releasePermit(), so don't auto-release here
                    return
                }

                val waitTimeMs = ((1.0 - state.availableTokens) / (bucket.refillPerSecond / adaptiveMultiplier.get().toDouble()) * 1000.0)
                    .toLong().coerceIn(50L, 500L)
                try {
                    condition.await(waitTimeMs, TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    releaseIfNeeded()
                    return
                }
            } finally {
                lock.unlock()
            }
        }
    }

    fun releasePermit() {
        globalSemaphore.release()
    }

    /**
     * Handles RateLimited / 429 response, doubling the multiplier and applying jittered backoff.
     */
    fun onRateLimited(retryAfterSeconds: Long? = null): Long {
        val count = consecutiveThrottles.incrementAndGet().coerceAtMost(10)
        consecutiveSuccesses.set(0)
        val multiplier = adaptiveMultiplier.updateAndGet { (it * 2).coerceAtMost(16) }

        val delayMs = if (retryAfterSeconds != null && retryAfterSeconds > 0) {
            retryAfterSeconds * 1000L
        } else {
            val baseDelayMs = (1L shl (count - 1)) * 1000L * multiplier // 1s, 2s, 4s, 8s...
            val cappedDelayMs = min(baseDelayMs, 900_000L) // 15 min max cap

            // Full Jitter: +/- 20%
            val jitterRange = (cappedDelayMs * 0.2).toLong().coerceAtLeast(200L)
            val jitter = Random.nextLong(-jitterRange, jitterRange)
            (cappedDelayMs + jitter).coerceAtLeast(1000L)
        }

        val nowRealtime = clock.elapsedRealtime()
        val backoffUntil = nowRealtime + delayMs
        backoffUntilTimestamp.set(backoffUntil)

        // Persist to prefs
        val wallBackoffUntil = clock.currentTimeMillis() + delayMs
        prefs?.edit()?.putLong(KEY_BACKOFF_UNTIL, wallBackoffUntil)?.apply()

        // Drain tokens
        bucketStates.values.forEach { it.availableTokens = 0.0 }
        YtmMetricsRegistry.record("rate_limiter.429_backoff", delayMs, isError = true)
        return delayMs
    }

    /**
     * AIMD Recovery: Additive Increase per 5 clean requests until back to baseline.
     */
    fun onSuccess() {
        consecutiveThrottles.set(0)
        lastSuccessTimestamp.set(clock.elapsedRealtime())
        val successes = consecutiveSuccesses.incrementAndGet()
        if (successes % 5 == 0 && adaptiveMultiplier.get() > 1) {
            adaptiveMultiplier.decrementAndGet()
        }
        if (adaptiveMultiplier.get() == 1) {
            prefs?.edit()?.remove(KEY_BACKOFF_UNTIL)?.apply()
        }
    }

    fun getRemainingBackoffMs(): Long {
        val now = clock.elapsedRealtime()
        val until = backoffUntilTimestamp.get()
        return (until - now).coerceAtLeast(0L)
    }

    companion object {
        private const val PREFS_NAME = "ytm_ratelimiter_prefs"
        private const val KEY_BACKOFF_UNTIL = "key_backoff_until"

        /** TTFA: cap on backoff restored from prefs at launch (see [initPrefs]). */
        private const val LAUNCH_BACKOFF_CLAMP_MS = 2_000L

        val shared: RateLimiter by lazy { RateLimiter() }
    }
}
