package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class PoTokenSingleFlightTest {

    @Test
    fun testConcurrentMintingCoalescesToSingleExecution() {
        val executor = Executors.newFixedThreadPool(10)
        val concurrency = 10
        val latch = CountDownLatch(concurrency)
        val startGate = CountDownLatch(1)

        val evaluationCount = AtomicInteger(0)
        val inFlight = ConcurrentHashMap<String, String>()
        val lock = Any()

        fun mintMockToken(visitorData: String, identifier: String): String {
            val key = "$visitorData:$identifier"
            return synchronized(lock) {
                if (inFlight.containsKey(key)) {
                    inFlight[key]!!
                } else {
                    evaluationCount.incrementAndGet()
                    Thread.sleep(50) // simulate JS minting
                    val result = "minted_token_for_$key"
                    inFlight[key] = result
                    result
                }
            }
        }

        val results = ConcurrentHashMap.newKeySet<String>()

        for (i in 0 until concurrency) {
            executor.submit {
                startGate.await()
                try {
                    val token = mintMockToken("test_visitor", "test_id")
                    results.add(token)
                } finally {
                    latch.countDown()
                }
            }
        }

        startGate.countDown()
        assertTrue("All threads should complete within 3 seconds", latch.await(3, TimeUnit.SECONDS))
        assertEquals("Evaluation must occur exactly once across parallel callers", 1, evaluationCount.get())
        assertEquals("All callers receive the identical single-flight token", 1, results.size)
        assertEquals("minted_token_for_test_visitor:test_id", results.first())
        executor.shutdown()
    }

    @Test
    fun testKeyScopeIsStrictlyBoundToVisitorDataAndIdentifier() {
        val inFlight = ConcurrentHashMap<String, String>()
        val evaluationCount = AtomicInteger(0)
        val lock = Any()

        fun mintMock(visitorData: String, identifier: String): String {
            val key = "$visitorData:$identifier"
            return synchronized(lock) {
                inFlight.computeIfAbsent(key) {
                    evaluationCount.incrementAndGet()
                    "token_$key"
                }
            }
        }

        val token1 = mintMock("visitorA", "clientA")
        val token2 = mintMock("visitorB", "clientA") // different visitor -> new evaluation
        val token3 = mintMock("visitorA", "clientA") // cached -> reuse

        assertEquals(2, evaluationCount.get())
        assertEquals("token_visitorA:clientA", token1)
        assertEquals("token_visitorB:clientA", token2)
        assertEquals(token1, token3)
    }
}
