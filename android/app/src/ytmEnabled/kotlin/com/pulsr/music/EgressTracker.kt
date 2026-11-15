package com.pulsr.music

/**
 * 2026-09 audit gap 2: stable egress identity for PO-token binding.
 *
 * A BotGuard poToken is only valid for the egress it was minted on. Pulsr can
 * change egress mid-session via ProxyPool rotation, cellular failover, or a
 * VPN toggling on/off — after which replayed tokens 403 and get misread as
 * PoTokenInvalid, causing an invalidate/refresh loop.
 *
 * Pure function, JVM-testable. `proxyLabel` comes from
 * ProxyPool.getActiveProxy()/the path-change listener (label format
 * "TYPE:host:port", or "DIRECT"); null/blank/DIRECT means the pool is idle.
 */
internal object EgressTracker {

    /**
     * @param proxyLabel active proxy label from ProxyPool, or null/"DIRECT"
     * @param vpnActive  NetworkPathMonitor.current().vpnActive
     * @param isCellular NetworkPathMonitor.current().cellular
     * @param networkIdentity stable hash of the active network's interface and
     *        addresses. Distinguishes Wi-Fi-to-Wi-Fi and cellular egress changes
     *        that keep the same transport class. Null keeps the legacy mapping.
     */
    fun egressId(
        proxyLabel: String?,
        vpnActive: Boolean,
        isCellular: Boolean,
        networkIdentity: String? = null,
    ): String {
        if (!proxyLabel.isNullOrBlank() && !proxyLabel.equals("DIRECT", ignoreCase = true)) {
            return "proxy:$proxyLabel"
        }
        val suffix = if (networkIdentity.isNullOrBlank()) "" else ":$networkIdentity"
        return when {
            vpnActive -> "vpn:direct$suffix"
            isCellular -> "cell:direct$suffix"
            else -> "wifi:direct$suffix"
        }
    }
}
