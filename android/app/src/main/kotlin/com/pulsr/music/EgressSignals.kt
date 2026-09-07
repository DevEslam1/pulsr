package com.pulsr.music

/**
 * 2026-09 gap 2: flavor-safe egress change signal. The main flavor publishes
 * (ProxyPool rotation), the ytmEnabled flavor subscribes (PoTokenManager).
 * No-op when YTM is disabled (no subscriber).
 */
object EgressSignals {
    @Volatile
    var onEgressChanged: ((String) -> Unit)? = null
}
