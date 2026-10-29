package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class HedgedResolutionTest {

    @Test
    fun testDefaultStreamChainKeepsLastResortClientsOffTheFastPath() {
        val chain = ResolutionStrategy.DEFAULT_STREAM_CHAIN

        // Fast audio clients present
        assertTrue("IOS_MUSIC should be in default stream chain", chain.contains(InnertubeClient.ClientType.IOS_MUSIC))
        assertTrue("ANDROID_MUSIC should be in default stream chain", chain.contains(InnertubeClient.ClientType.ANDROID_MUSIC))
        assertTrue("ANDROID_VR should be in default stream chain", chain.contains(InnertubeClient.ClientType.ANDROID_VR))
        assertTrue("WEB_REMIX should be in default stream chain", chain.contains(InnertubeClient.ClientType.WEB_REMIX))

        // The TV embed and bare test client exist only as no-login last resorts for
        // IP-flagged waves, so they must sit strictly behind every audio client
        // rather than being raced on the hedged fast path.
        val lastResorts = listOf(
            InnertubeClient.ClientType.TVHTML5_SIMPLY_EMBEDDED_PLAYER,
            InnertubeClient.ClientType.ANDROID_TESTSUITE
        )
        val firstLastResortIndex = chain.indexOfFirst { it in lastResorts }
        assertTrue("Chain must still offer a no-login last resort", firstLastResortIndex >= 0)
        assertTrue(
            "Last-resort clients must come after every audio client",
            chain.drop(firstLastResortIndex).all { it in lastResorts }
        )
        assertTrue(
            "Hedged race covers the first two candidates, which must both be audio clients",
            firstLastResortIndex >= 2
        )
    }

    @Test
    fun testHedgedRaceCandidate1WinsWithin350MsCancelsCandidate2() {
        val executor = Executors.newFixedThreadPool(2)
        val candidate2Started = AtomicBoolean(false)
        val candidate2Cancelled = AtomicBoolean(false)

        val hedgeDelayMs = 350L

        // Candidate 1 finishes in 100ms
        val candidate1Future = executor.submit<String> {
            Thread.sleep(100L)
            "https://googlevideo.com/stream_candidate1"
        }

        // Monitor with 350ms hedge window
        val winnerFuture = CompletableFuture<String>()
        var candidate2Future: java.util.concurrent.Future<*>? = null

        val startTime = System.currentTimeMillis()
        while (System.currentTimeMillis() - startTime < hedgeDelayMs) {
            if (candidate1Future.isDone) {
                winnerFuture.complete(candidate1Future.get())
                break
            }
            Thread.sleep(10L)
        }

        // Candidate 2 only launched if candidate 1 did not complete within hedgeDelayMs
        if (!winnerFuture.isDone) {
            candidate2Future = executor.submit {
                candidate2Started.set(true)
                try {
                    Thread.sleep(300L)
                } catch (_: InterruptedException) {
                    candidate2Cancelled.set(true)
                }
            }
        }

        val result = winnerFuture.get(1, TimeUnit.SECONDS)
        assertEquals("https://googlevideo.com/stream_candidate1", result)
        assertFalse("Candidate 2 should not have been started because candidate 1 won within 350ms", candidate2Started.get())

        executor.shutdownNow()
    }

    @Test
    fun testHedgedRaceCandidate1HangsCandidate2WinsAndCancelsCandidate1() {
        val executor = Executors.newFixedThreadPool(2)
        val candidate1Cancelled = AtomicBoolean(false)

        val hedgeDelayMs = 350L

        // Candidate 1 hangs (simulating network stall / 6s waterfall)
        val candidate1Future = executor.submit<String?> {
            try {
                Thread.sleep(5000L)
                "https://googlevideo.com/stream_candidate1_slow"
            } catch (_: InterruptedException) {
                candidate1Cancelled.set(true)
                null
            }
        }

        val winnerFuture = CompletableFuture<String>()
        var candidate2Future: java.util.concurrent.Future<String?>? = null

        val startTime = System.currentTimeMillis()
        while (System.currentTimeMillis() - startTime < hedgeDelayMs) {
            if (candidate1Future.isDone && candidate1Future.get() != null) {
                winnerFuture.complete(candidate1Future.get())
                break
            }
            Thread.sleep(10L)
        }

        // Candidate 1 didn't finish within 350ms -> launch candidate 2 hedge!
        if (!winnerFuture.isDone) {
            candidate2Future = executor.submit<String?> {
                Thread.sleep(150L) // Candidate 2 finishes fast
                "https://googlevideo.com/stream_candidate2_fast"
            }
        }

        assertNotNull("Candidate 2 must be launched on hedge trigger", candidate2Future)

        // Poll for first to finish
        val hedgeStartTime = System.currentTimeMillis()
        while (System.currentTimeMillis() - hedgeStartTime < 2000L) {
            if (candidate2Future?.isDone == true && candidate2Future.get() != null) {
                winnerFuture.complete(candidate2Future.get())
                candidate1Future.cancel(true)
                break
            }
            Thread.sleep(10L)
        }

        val result = winnerFuture.get(1, TimeUnit.SECONDS)
        assertEquals("https://googlevideo.com/stream_candidate2_fast", result)
        assertTrue("Candidate 1 should be cancelled when candidate 2 wins", candidate1Cancelled.get() || candidate1Future.isCancelled)

        executor.shutdownNow()
    }

    @Test
    fun testWinningClientPriorityChainOrdering() {
        val defaultChain = listOf(
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_MUSIC,
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.WEB_REMIX
        )

        // Suppose ANDROID_VR is the recorded winning client
        val winner = InnertubeClient.ClientType.ANDROID_VR
        val prioritizedChain = listOf(winner) + (defaultChain - winner)

        assertEquals("Winner should be placed at index 0", InnertubeClient.ClientType.ANDROID_VR, prioritizedChain[0])
        assertEquals("Remaining candidates follow without duplication", 4, prioritizedChain.size)
        assertEquals(listOf(
            InnertubeClient.ClientType.ANDROID_VR,
            InnertubeClient.ClientType.IOS_MUSIC,
            InnertubeClient.ClientType.ANDROID_MUSIC,
            InnertubeClient.ClientType.WEB_REMIX
        ), prioritizedChain)
    }
}
