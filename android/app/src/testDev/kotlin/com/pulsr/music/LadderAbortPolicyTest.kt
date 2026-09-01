package com.pulsr.music

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure-logic tests for the stream ladder's early-abort policy: N consecutive
 * LOGIN_REQUIRED client responses mean a device/IP-level gate - walking the
 * rest of the chain cannot succeed.
 */
class LadderAbortPolicyTest {

    @Test
    fun testAbortsAfterThresholdConsecutiveLoginRequired() {
        val policy = LadderAbortPolicy()
        assertFalse(policy.shouldAbort())
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        assertFalse("below threshold must not abort", policy.shouldAbort())
        policy.onLoginRequired(true)
        assertTrue("4 consecutive LOGIN_REQUIRED must abort", policy.shouldAbort())
    }

    @Test
    fun testNonLoginOutcomeResetsStreak() {
        val policy = LadderAbortPolicy()
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        // A client failing for a different reason (network error, UNPLAYABLE,
        // empty formats) breaks the "consecutive LOGIN_REQUIRED" streak.
        policy.onLoginRequired(false)
        assertFalse(policy.shouldAbort())
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        policy.onLoginRequired(true)
        assertFalse("streak was reset - still below threshold", policy.shouldAbort())
        policy.onLoginRequired(true)
        assertTrue(policy.shouldAbort())
    }

    @Test
    fun testCustomThresholdRespected() {
        val policy = LadderAbortPolicy(threshold = 2)
        policy.onLoginRequired(true)
        assertFalse(policy.shouldAbort())
        policy.onLoginRequired(true)
        assertTrue(policy.shouldAbort())
    }
}
