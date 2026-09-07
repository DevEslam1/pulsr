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
     * @param vpnActive  CellularFailoverHelper.isVpnActive(context)
     * @param isCellular true when the active network is metered/cellular
     */
    fun egressId(proxyLabel: String?, vpnActive: Boolean, isCellular: Boolean): String {
        if (!proxyLabel.isNullOrBlank() && !proxyLabel.equals("DIRECT", ignoreCase = true)) {
            return "proxy:$proxyLabel"
        }
        return when {
            vpnActive -> "vpn:direct"
            isCellular -> "cell:direct"
            else -> "wifi:direct"
        }
    }
}
