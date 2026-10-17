package com.pulsr.music

import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Process-wide circuit breaker for egress-level blocks (IpBlocked /
 * BotChallenge / PoTokenInvalid) with escalating cooldown episodes.
 *
 * The Innertube chain used a flat 15s cooldown whether YouTube had blocked one
 * resolve or ten in a row, so a persistent IP/bot gate kept being re-probed at
 * the same cadence. Windows now double per consecutive blocked episode
 * (15s -> 30s -> 60s -> 120s cap), mirroring the Dart-side YtmService
 * bot/IP cooldown escalation.
 *
 * A successful resolve clears the streak immediately; a long idle gap
 * ([STREAK_DECAY_MS] since the last episode) restarts escalation from the base
 * window so a stale streak cannot outlive the block that created it. An active
 * window is never shortened by a concurrent shorter episode.
 *
 * Clock-injectable and framework-free so the state machine stays JVM-testable.
 */
internal class EgressBlockBreaker(
    private val clock: () -> Long = { android.os.SystemClock.elapsedRealtime() },
) {
    private val cooldownUntilMs = AtomicLong(0L)
    private val episodes = AtomicInteger(0)
    private val lastBlockAtMs = AtomicLong(0L)

    fun isActive(): Boolean = episodes.get() >= 1 && clock() < cooldownUntilMs.get()

    fun remainingMs(): Long = (cooldownUntilMs.get() - clock()).coerceAtLeast(0L)

    /**
     * Records a confirmed block episode and returns the new cooldown expiry.
     * Escalates only while episodes remain consecutive; never shortens an
     * already-active window.
     */
    @Synchronized
    fun onBlock(): Long {
        val now = clock()
        val last = lastBlockAtMs.get()
        val nextEpisodes = if (last == 0L || now - last > STREAK_DECAY_MS) 1 else episodes.get() + 1
        episodes.set(nextEpisodes)
        lastBlockAtMs.set(now)
        val candidate = now + windowForEpisodes(nextEpisodes)
        return cooldownUntilMs.updateAndGet { existing -> maxOf(existing, candidate) }
    }

    /** A successful resolve proves the egress is healthy again. */
    @Synchronized
    fun onSuccess() {
        episodes.set(0)
        cooldownUntilMs.set(0L)
        lastBlockAtMs.set(0L)
    }

    companion object {
        const val BASE_WINDOW_MS = 15_000L
        const val MAX_WINDOW_MS = 120_000L
        const val STREAK_DECAY_MS = 600_000L

        /** 15s doubled per consecutive episode, capped at [MAX_WINDOW_MS]. */
        fun windowForEpisodes(episodes: Int): Long {
            if (episodes <= 0) return 0L
            val doublings = (episodes - 1).coerceIn(0, 8)
            return minOf(BASE_WINDOW_MS shl doublings, MAX_WINDOW_MS)
        }
    }
}
