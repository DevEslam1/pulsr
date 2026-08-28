package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JsDecipherCacheTest {

    @Test
    fun testTransformOperations() {
        val cache = JsDecipherCache()

        // 1. Reverse: "abcdef" -> "fedcba"
        val reversed = cache.applyTransforms("abcdef", listOf("reverse"))
        assertEquals("fedcba", reversed)

        // 2. Splice: "abcdef" with splice:2 -> "cdef"
        val spliced = cache.applyTransforms("abcdef", listOf("splice:2"))
        assertEquals("cdef", spliced)

        // 3. Swap: "abcdef" with swap:3 (swap index 0 and 3) -> "dbcaef"
        val swapped = cache.applyTransforms("abcdef", listOf("swap:3"))
        assertEquals("dbcaef", swapped)

        // 4. Combined chain: "abcdef" -> reverse "fedcba" -> splice:2 "dcba" -> swap:2 (swap 'd' and 'b') -> "bcda"
        val combined = cache.applyTransforms("abcdef", listOf("reverse", "splice:2", "swap:2"))
        assertEquals("bcda", combined)
    }

    @Test
    fun testInMemoryDecipherRuleStorageAndRetrieval() {
        val cache = JsDecipherCache()
        cache.putRules("player_v1", listOf("reverse", "swap:1"))

        val retrieved = cache.getRules("player_v1")
        assertTrue(retrieved != null)
        assertEquals(listOf("reverse", "swap:1"), retrieved?.transformSteps)

        val deciphered = cache.decipherSignature("hello", "player_v1")
        // "hello" -> reverse "olleh" -> swap 1 (swap 'o' and 'l') -> "loleh"
        assertEquals("loleh", deciphered)
    }

    @Test
    fun testCachedRulesExpiry() {
        val now = System.currentTimeMillis()

        val freshRules = JsDecipherCache.CachedDecipherRules(
            playerHash = "hash1",
            transformSteps = listOf("reverse"),
            cachedAt = now - 1000L,
            ttlMs = 24 * 60 * 60 * 1000L
        )
        assertFalse("Fresh rules should not be expired", freshRules.isExpired)

        val expiredRules = JsDecipherCache.CachedDecipherRules(
            playerHash = "hash2",
            transformSteps = listOf("reverse"),
            cachedAt = now - (25 * 60 * 60 * 1000L), // 25h ago
            ttlMs = 24 * 60 * 60 * 1000L
        )
        assertTrue("Past 24h rules must be expired", expiredRules.isExpired)
    }

    @Test
    fun testDecipherCleanFallbackOnInvalidOrEmpty() {
        val cache = JsDecipherCache()
        val emptyResult = cache.applyTransforms("abc", emptyList())
        assertEquals("abc", emptyResult)

        val outOfBoundsSplice = cache.applyTransforms("abc", listOf("splice:10"))
        assertEquals("abc", outOfBoundsSplice)

        val outOfBoundsSwap = cache.applyTransforms("abc", listOf("swap:10"))
        assertEquals("abc", outOfBoundsSwap)
    }
}
