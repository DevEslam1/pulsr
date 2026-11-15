package com.pulsr.music

import android.content.Context
import android.os.Build
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class NetworkEgressTest {
    private class FakeClock : RateLimiter.Clock {
        var now = 1_000L
        override fun elapsedRealtime() = now
        override fun currentTimeMillis() = now
        override fun sleep(millis: Long) {
            now += millis
        }
    }

    private val context: Context get() = RuntimeEnvironment.getApplication()

    private fun prefs() =
        context.getSharedPreferences("ytm_ratelimiter_prefs", Context.MODE_PRIVATE)

    @Before
    fun setUp() {
        prefs().edit().clear().commit()
    }

    @After
    fun tearDown() {
        prefs().edit().clear().commit()
    }

    @Test
    fun persistedBackoffIsScopedToTheEgressThatReceivedIt() {
        val clock = FakeClock()
        var egress = "wifi:direct:a"

        val first = RateLimiter(clock = clock, respectfulMode = false)
        first.initPrefs(context) { egress }
        first.onRateLimited(10L)
        assertEquals(10_000L, first.getRemainingBackoffMs())

        // Same egress restores the persisted window.
        val same = RateLimiter(clock = clock, respectfulMode = false)
        same.initPrefs(context) { egress }
        assertEquals(10_000L, same.getRemainingBackoffMs())

        // A different path must not inherit the previous egress's cooldown.
        val other = RateLimiter(clock = clock, respectfulMode = false)
        egress = "wifi:direct:b"
        other.initPrefs(context) { egress }
        assertEquals(0L, other.getRemainingBackoffMs())
    }
}
