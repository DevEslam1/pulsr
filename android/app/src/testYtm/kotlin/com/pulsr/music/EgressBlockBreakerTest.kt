package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EgressBlockBreakerTest {

    private class FakeClock(var now: Long) {
        fun advance(ms: Long) {
            now += ms
        }
    }

    private fun breakerAt(clock: FakeClock) = EgressBlockBreaker { clock.now }

    @Test
    fun testWindowEscalatesPerEpisodeAndCapsAtTwoMinutes() {
        assertEquals(0L, EgressBlockBreaker.windowForEpisodes(0))
        assertEquals(15_000L, EgressBlockBreaker.windowForEpisodes(1))
        assertEquals(30_000L, EgressBlockBreaker.windowForEpisodes(2))
        assertEquals(60_000L, EgressBlockBreaker.windowForEpisodes(3))
        assertEquals(120_000L, EgressBlockBreaker.windowForEpisodes(4))
        assertEquals(120_000L, EgressBlockBreaker.windowForEpisodes(12))
    }

    @Test
    fun testConsecutiveEpisodesEscalateAndNeverShorten() {
        val clock = FakeClock(1_000_000L)
        val breaker = breakerAt(clock)

        assertFalse(breaker.isActive())

        val until1 = breaker.onBlock()
        assertEquals(clock.now + 15_000L, until1)
        assertTrue(breaker.isActive())
        assertEquals(15_000L, breaker.remainingMs())

        clock.advance(1_000L)
        val until2 = breaker.onBlock()
        assertEquals(clock.now + 30_000L, until2)
        assertTrue(until2 >= until1)

        clock.advance(1_000L)
        val until3 = breaker.onBlock()
        assertEquals(clock.now + 60_000L, until3)
        assertEquals(60_000L, breaker.remainingMs())
    }

    @Test
    fun testSuccessClearsStreakAndWindow() {
        val clock = FakeClock(5_000_000L)
        val breaker = breakerAt(clock)
        breaker.onBlock()
        breaker.onBlock()
        assertTrue(breaker.isActive())

        breaker.onSuccess()
        assertFalse(breaker.isActive())
        assertEquals(0L, breaker.remainingMs())

        // The next episode starts from the base window again.
        val until = breaker.onBlock()
        assertEquals(clock.now + 15_000L, until)
    }

    @Test
    fun testLongIdleGapRestartsEscalation() {
        val clock = FakeClock(9_000_000L)
        val breaker = breakerAt(clock)
        breaker.onBlock()
        breaker.onBlock()
        assertEquals(30_000L, breaker.remainingMs())

        clock.advance(EgressBlockBreaker.STREAK_DECAY_MS + 1)
        val until = breaker.onBlock()
        assertEquals(clock.now + 15_000L, until)
    }

    @Test
    fun testWindowExpiresAtItsDeadline() {
        val clock = FakeClock(2_000_000L)
        val breaker = breakerAt(clock)
        breaker.onBlock()
        assertTrue(breaker.isActive())

        clock.advance(15_000L)
        assertFalse(breaker.isActive())
        assertEquals(0L, breaker.remainingMs())
    }
}
