package com.pulsr.music

import android.content.Context

/**
 * Network-state queries used for egress binding.
 *
 * Routing preference is left to Android's default network. Pulsr does not
 * silently move a request onto cellular when the Wi-Fi path is blocked,
 * because that would spend metered data without the user's consent.
 */
object CellularFailoverHelper {
    fun isVpnActive(context: Context): Boolean =
        NetworkPathMonitor.current(context).vpnActive

    fun isCellularActive(context: Context): Boolean =
        NetworkPathMonitor.current(context).cellular
}
