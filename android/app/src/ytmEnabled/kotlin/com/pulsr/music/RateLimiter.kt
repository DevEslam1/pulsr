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
        SEARCH(8, 2.0, 1500L),
        BROWSE(10, 4.0, 500L),
        PLAYER(10, 5.0, 200L),
        STREAM(12, 6.0, 100L),
        DOWNLOAD(6, 3.0, 300L)
    }

    private class BucketState(val bucket: Bucket, var availableTokens: Double, var lastRefill: Long, var lastRequest: Long = 0L)

    private val bucketStates = ConcurrentHashMap<Bucket, BucketState>()
    private val globalSemaphore = Semaphore(8, true)
    private val backoffUntilTimestamp = AtomicLong(0L)
    private val adaptiveMultiplier = AtomicInteger(1)
    private val lastSuccessTimestamp = AtomicLong(0L)
    private val consecutiveThrottles = AtomicInteger(0)

    // Start of the current uninterrupted run of successful requests. Zeroed by
    // [onRateLimited] so the multiplier only decays after genuinely clean
    // traffic, not after ten minutes of being blocked.
    private val cleanSinceTimestamp = AtomicLong(0L)

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
            backoffUntilTimestamp.set(clock.elapsedRealtime() + remainingMs)
        }
    }

    /**
     * Acquires permit for [bucket], honoring concurrency cap and pacing floors.
     *
     * Returns true when a global permit is held by the caller — the caller must
     * then release it exactly once. Returns false when the wait was interrupted,
     * in which case no permit is held and the caller must not release one.
     */
    fun acquirePermit(bucket: Bucket = Bucket.PLAYER): Boolean {
        while (true) {
            // 1. Backoff check: sleep outside the global concurrency permit to prevent
            // starvations of unrelated calls or pools.
            val now = clock.elapsedRealtime()
            val backoffUntil = backoffUntilTimestamp.get()

            if (now < backoffUntil) {
                val sleepTime = backoffUntil - now + Random.nextLong(0L, 2000L)
                if (sleepTime > 0) {
                    lock.lock()
                    try {
                        condition.await(sleepTime, TimeUnit.MILLISECONDS)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return false
                    } finally {
                        lock.unlock()
                    }
                }
                continue
            }

            // 2. Global in-flight concurrency limiter
            try {
                globalSemaphore.acquire()
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }

            // Check if backoff arrived while waiting on the semaphore
            val postAcquireNow = clock.elapsedRealtime()
            if (postAcquireNow < backoffUntilTimestamp.get()) {
                globalSemaphore.release()
                continue
            }

            lock.lock()
            try {
                // Decay the multiplier only after a sustained clean run. Keying
                // this off "no success for 10 minutes" would reset the backoff
                // in the middle of a block, which is when it is needed most.
                val cleanSince = cleanSinceTimestamp.get()
                if (cleanSince > 0 && consecutiveThrottles.get() == 0 && (postAcquireNow - cleanSince) > CLEAN_DECAY_MS) {
                    adaptiveMultiplier.set(1)
                    cleanSinceTimestamp.set(postAcquireNow)
                }

                val state = bucketStates[bucket] ?: BucketState(bucket, bucket.maxTokens.toDouble(), postAcquireNow).also {
                    bucketStates[bucket] = it
                }

                // Refill bucket tokens
                val elapsedSec = (postAcquireNow - state.lastRefill) / 1000.0
                if (elapsedSec > 0) {
                    state.availableTokens = min(bucket.maxTokens.toDouble(), state.availableTokens + (elapsedSec * bucket.refillPerSecond))
                    state.lastRefill = postAcquireNow
                }

                // Check respectful human pacing gap
                if (respectfulMode && bucket.minGapMs > 0 && state.lastRequest > 0) {
                    val gapElapsed = postAcquireNow - state.lastRequest
                    if (gapElapsed < bucket.minGapMs) {
                        val waitGap = bucket.minGapMs - gapElapsed + (0..150).random()
                        globalSemaphore.release()
                        try {
                            condition.await(waitGap, TimeUnit.MILLISECONDS)
                        } catch (_: InterruptedException) {
                            Thread.currentThread().interrupt()
                            return false
                        }
                        continue
                    }
                }

                if (state.availableTokens >= 1.0) {
                    state.availableTokens -= 1.0
                    state.lastRequest = postAcquireNow
                    return true
                }

                val waitTimeMs = ((1.0 - state.availableTokens) / bucket.refillPerSecond * 1000.0).toLong().coerceIn(50L, 500L)
                globalSemaphore.release()
                try {
                    condition.await(waitTimeMs, TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return false
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
        val candidateBackoff = nowRealtime + delayMs
        // Never shorten an active window: a `Retry-After: 3` arriving mid-ban
        // must not cut a 15 minute cooldown down to 3 seconds.
        val backoffUntil = backoffUntilTimestamp.updateAndGet { existing ->
            if (existing > candidateBackoff) existing else candidateBackoff
        }
        val effectiveDelayMs = (backoffUntil - nowRealtime).coerceAtLeast(delayMs)

        // Persist to prefs
        val wallBackoffUntil = clock.currentTimeMillis() + effectiveDelayMs
        prefs?.edit()?.putLong(KEY_BACKOFF_UNTIL, wallBackoffUntil)?.apply()

        // Drain tokens. `lastRefill` must move with them, otherwise refill is
        // purely time-based and the next acquire immediately credits the whole
        // backoff window back as tokens, making the drain a no-op.
        lock.lock()
        try {
            val drainAt = nowRealtime
            bucketStates.values.forEach {
                it.availableTokens = 0.0
                it.lastRefill = drainAt
            }
        } finally {
            lock.unlock()
        }
        cleanSinceTimestamp.set(0L)
        return effectiveDelayMs
    }

    /**
     * Resets throttle counter on successful response.
     */
    fun onSuccess() {
        consecutiveThrottles.set(0)
        val now = clock.elapsedRealtime()
        lastSuccessTimestamp.set(now)
        cleanSinceTimestamp.compareAndSet(0L, now)
        prefs?.edit()?.remove(KEY_BACKOFF_UNTIL)?.apply()
    }

    fun getRemainingBackoffMs(): Long {
        val now = clock.elapsedRealtime()
        val until = backoffUntilTimestamp.get()
        return (until - now).coerceAtLeast(0L)
    }

    /**
     * Drops throttle state after a network-path change (VPN up/down, Wi-Fi <->
     * mobile). Backoff/throttle verdicts belong to the previous egress IP;
     * carrying them onto the new route needlessly silences resolves there.
     */
    fun resetAfterNetworkChange() {
        consecutiveThrottles.set(0)
        adaptiveMultiplier.set(1)
        backoffUntilTimestamp.set(0L)
        val now = clock.elapsedRealtime()
        lock.lock()
        try {
            bucketStates.values.forEach {
                it.availableTokens = it.bucket.maxTokens.toDouble()
                it.lastRefill = now
            }
            condition.signalAll()
        } finally {
            lock.unlock()
        }
        cleanSinceTimestamp.set(now)
        prefs?.edit()?.remove(KEY_BACKOFF_UNTIL)?.apply()
    }

    companion object {
        private const val PREFS_NAME = "ytm_ratelimiter_prefs"
        private const val KEY_BACKOFF_UNTIL = "key_backoff_until"
        private const val CLEAN_DECAY_MS = 600_000L

        val shared: RateLimiter by lazy { RateLimiter() }
    }
}
