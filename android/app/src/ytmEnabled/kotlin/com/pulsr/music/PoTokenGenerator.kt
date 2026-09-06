package com.pulsr.music

import java.io.Closeable
import java.time.Instant

/**
 * Mints the proof-of-origin tokens YouTube requires before it will hand out stream
 * URLs.
 *
 * Held as an interface so a future non-WebView implementation (e.g. a local DOM)
 * can be swapped in.
 */
internal interface PoTokenGenerator : Closeable {
    /**
     * Mints a token for [identifier] — a video id for player tokens, or the
     * visitorData for the streaming token. Blocks, and must not be called on the
     * main thread: implementations drive a WebView whose work is posted there.
     */
    fun generatePoToken(identifier: String): String

    /** Once expired, every token this generator produced is rejected by YouTube. */
    fun isExpired(): Boolean

    /** The exact instant when this generator expires, or null if unknown. */
    fun expirationInstant(): Instant? = null
}
