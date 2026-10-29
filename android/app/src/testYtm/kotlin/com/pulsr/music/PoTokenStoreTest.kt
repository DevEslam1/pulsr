package com.pulsr.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PoTokenStoreTest {

    @Test
    fun testStoredTokenDataValidation() {
        val now = Instant.now().epochSecond

        // 1. Fresh valid token
        val validToken = PoTokenStore.StoredTokenData(
            streamingPoToken = "valid_streaming_token",
            visitorData = "valid_visitor_data",
            integrityToken = "integrity_123",
            dataSyncId = "sync_456",
            generatedAt = now - 100,
            ttlSeconds = 3600,
            expiryInstant = now + 3500
        )
        assertFalse("Valid token should not be expired", validToken.isExpired)
        assertFalse("Valid token with plenty of TTL should not be expiring soon", validToken.isExpiringSoon)

        // 2. Expiring soon token (remaining <= REFRESH_MARGIN_SECONDS = 1800s)
        val expiringSoonToken = PoTokenStore.StoredTokenData(
            streamingPoToken = "valid_streaming_token",
            visitorData = "valid_visitor_data",
            integrityToken = "integrity_123",
            dataSyncId = "sync_456",
            generatedAt = now - 3000,
            ttlSeconds = 3600,
            expiryInstant = now + 600 // 10 minutes remaining (< 30 min margin)
        )
        assertFalse("Expiring soon token is not yet expired", expiringSoonToken.isExpired)
        assertTrue("Token with 10 min remaining should be flagged expiring soon", expiringSoonToken.isExpiringSoon)

        // 3. Fully expired token
        val expiredToken = PoTokenStore.StoredTokenData(
            streamingPoToken = "expired_token",
            visitorData = "visitor_data",
            integrityToken = "integrity_123",
            dataSyncId = "sync_456",
            generatedAt = now - 4000,
            ttlSeconds = 3600,
            expiryInstant = now - 400
        )
        assertTrue("Past expiry token should be expired", expiredToken.isExpired)
        assertTrue("Expired token should also report expiring soon", expiredToken.isExpiringSoon)
    }

    @Test
    fun testCorruptAndMissingTokenHandling() {
        // Missing token string
        val missingToken = PoTokenStore.StoredTokenData(
            streamingPoToken = "",
            visitorData = "visitor_data",
            integrityToken = "",
            dataSyncId = "",
            generatedAt = Instant.now().epochSecond,
            ttlSeconds = 3600,
            expiryInstant = Instant.now().epochSecond + 3600
        )
        assertTrue("Missing token should be treated as expired/invalid", missingToken.isExpired)

        // Missing visitor data
        val missingVisitor = PoTokenStore.StoredTokenData(
            streamingPoToken = "token_abc",
            visitorData = "",
            integrityToken = "",
            dataSyncId = "",
            generatedAt = Instant.now().epochSecond,
            ttlSeconds = 3600,
            expiryInstant = Instant.now().epochSecond + 3600
        )
        assertTrue("Missing visitor data should be treated as expired/invalid", missingVisitor.isExpired)

        // Corrupt zero or negative timestamps
        val corruptTimestamp = PoTokenStore.StoredTokenData(
            streamingPoToken = "token_abc",
            visitorData = "visitor_xyz",
            integrityToken = "",
            dataSyncId = "",
            generatedAt = 0L,
            ttlSeconds = 3600,
            expiryInstant = 0L
        )
        assertTrue("Corrupt zero timestamps should be treated as expired", corruptTimestamp.isExpired)
    }

    @Test
    fun testBackgroundRefreshTriggerOn403() {
        val sig = YtmBlockSignal.parse(403, "Access Denied")
        assertEquals(YtmBlockSignal.IpBlocked, sig)

        // Bot challenge or poToken invalid should trigger refresh
        val poTokenInvalidSig = YtmBlockSignal.parse(200, "po_token_invalid")
        assertEquals(YtmBlockSignal.PoTokenInvalid, poTokenInvalidSig)
    }
}
