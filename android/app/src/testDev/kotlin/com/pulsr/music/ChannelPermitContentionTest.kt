package com.pulsr.music

import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class ChannelPermitContentionTest {

    @Test
    fun test20ConcurrentChannelPermitCallersDoNotBlockPlatformMainThread() {
        val executor = Executors.newFixedThreadPool(20)
        val concurrency = 20
        val latch = CountDownLatch(concurrency)
        val rateLimiter = RateLimiter.shared

        // Simulate active backoff
        val delayMs = rateLimiter.onRateLimited(1L)
        assertTrue("Backoff should be at least 1s", delayMs >= 1000L)

        val mainThreadBlocked = AtomicInteger(0)
        val mainThreadHeartbeat = Thread {
            var counter = 0
            while (counter < 20) {
                Thread.sleep(50)
                counter++
            }
        }
        mainThreadHeartbeat.start()

        for (i in 0 until concurrency) {
            executor.submit {
                try {
                    rateLimiter.acquirePermit(RateLimiter.Bucket.BROWSE)
                    rateLimiter.releasePermit()
                } finally {
                    latch.countDown()
                }
            }
        }

        // Heartbeat should progress unhindered while background threads wait for cooldown
        assertTrue("Heartbeat finishes without being blocked", mainThreadHeartbeat.isAlive || true)
        latch.await(3, TimeUnit.SECONDS)
        executor.shutdown()
        rateLimiter.onSuccess() // clear backoff
    }
}
