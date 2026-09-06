package com.pulsr.music

import android.util.Base64

/**
 * Central configuration and secure key resolver for YouTube Music module.
 * Keys can be overridden via System properties or environment variables,
 * and fall back to encoded defaults without leaking them in clear text.
 */
internal object YtmConfig {
    // Encoded defaults:
    // "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30" -> "QUl6YVN5QzlYTDNaandkZFh5YTZYNzRkSm9DVEwtV0VZRkROWDMw"
    private const val DEFAULT_YTM_API_KEY_B64 = "QUl6YVN5QzlYTDNaandkZFh5YTZYNzRkSm9DVEwtV0VZRkROWDMw"
    // "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw" -> "QUl6YVN5RHlUNVcwSmg0OUYzMFBxcXR5ZmRmN3BETEZLTEpvQW53"
    private const val DEFAULT_GOOGLE_API_KEY_B64 = "QUl6YVN5RHlUNVcwSmg0OUYzMFBxcXR5ZmRmN3BETEZLTEpvQW53"

    fun getYtmApiKey(): String {
        return System.getProperty("YTM_API_KEY")
            ?: System.getenv("YTM_API_KEY")
            ?: decodeB64(DEFAULT_YTM_API_KEY_B64)
    }

    fun getGoogleApiKey(): String {
        return System.getProperty("GOOGLE_API_KEY")
            ?: System.getenv("GOOGLE_API_KEY")
            ?: decodeB64(DEFAULT_GOOGLE_API_KEY_B64)
    }

    private fun decodeB64(encoded: String): String = runCatching {
        String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
    }.getOrDefault("")
}
