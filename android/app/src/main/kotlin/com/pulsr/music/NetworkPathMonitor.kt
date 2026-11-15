package com.pulsr.music

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import java.security.MessageDigest
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Process-wide view of the active network path.
 *
 * Values are derived from [ConnectivityManager] rather than transport-type
 * snapshots so a Wi-Fi-to-Wi-Fi switch, a cellular IP change, or a VPN
 * reconnect produces a different identity even though the transport type is
 * unchanged. Direct-path identities are persisted with cached tokens and URLs,
 * so [Snapshot.identity] deliberately excludes the process-local network
 * handle and uses interface plus addresses instead.
 */
object NetworkPathMonitor {
    private const val TAG = "NetworkPathMonitor"

    data class Snapshot(
        val identity: String,
        val sessionKey: String,
        val vpnActive: Boolean,
        val cellular: Boolean,
        val wifi: Boolean,
        val metered: Boolean,
        val online: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "identity" to identity,
            "vpnActive" to vpnActive,
            "cellular" to cellular,
            "wifi" to wifi,
            "metered" to metered,
            "online" to online,
        )
    }

    private val listeners = CopyOnWriteArrayList<(Snapshot) -> Unit>()
    private val lock = Any()

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var callback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var lastSessionKey: String = ""

    private fun offline(): Snapshot =
        Snapshot("offline", "offline", vpnActive = false, cellular = false, wifi = false,
            metered = true, online = false)

    fun start(context: Context) {
        synchronized(lock) {
            if (callback != null) return
            val ctx = context.applicationContext
            appContext = ctx
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return
            val networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = refreshAndNotify()
                override fun onLost(network: Network) = refreshAndNotify()
                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) = refreshAndNotify()

                override fun onLinkPropertiesChanged(
                    network: Network,
                    linkProperties: android.net.LinkProperties,
                ) = refreshAndNotify()
            }
            try {
                cm.registerDefaultNetworkCallback(networkCallback)
                callback = networkCallback
                lastSessionKey = current(ctx).sessionKey
            } catch (t: Throwable) {
                // Prod/Pure removes ACCESS_NETWORK_STATE; monitoring is optional.
                Log.w(TAG, "Network callback registration failed: ${t.message}")
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            val cm = appContext?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            callback?.let { cb -> runCatching { cm?.unregisterNetworkCallback(cb) } }
            callback = null
            lastSessionKey = ""
        }
    }

    fun addListener(listener: (Snapshot) -> Unit) {
        if (!listeners.contains(listener)) listeners.add(listener)
    }

    fun removeListener(listener: (Snapshot) -> Unit) {
        listeners.remove(listener)
    }

    fun current(context: Context? = appContext): Snapshot {
        val ctx = context ?: return offline()
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return offline()
        val active = runCatching { cm.activeNetwork }.getOrNull() ?: return offline()
        val caps = runCatching { cm.getNetworkCapabilities(active) }.getOrNull()
            ?: return offline()

        val vpn = caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val underlying = if (vpn) {
            runCatching { underlyingCapabilities(cm, active) }.getOrDefault(emptyList())
        } else {
            listOf(caps)
        }
        val wifi = underlying.any { isUsable(it) && isWifiLike(it) }
        val cellular = !wifi && underlying.any { isUsable(it) && isCellular(it) }
        val metered = runCatching { cm.isActiveNetworkMetered }.getOrDefault(true)
        val online = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
            underlying.any { it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) }
        val identity = identityOf(cm, active, vpn)
        val sessionKey = sessionKeyOf(cm, active)

        return Snapshot(
            identity = identity,
            sessionKey = sessionKey,
            vpnActive = vpn,
            cellular = cellular,
            wifi = wifi,
            metered = metered,
            online = online,
        )
    }

    fun isWifiConnected(context: Context): Boolean = current(context).wifi

    fun isMetered(context: Context): Boolean = current(context).metered

    @Synchronized
    private fun refreshAndNotify() {
        val ctx = appContext ?: return
        val snapshot = current(ctx)
        if (snapshot.sessionKey == lastSessionKey) return
        lastSessionKey = snapshot.sessionKey
        for (listener in listeners) {
            try {
                listener(snapshot)
            } catch (_: Throwable) {
            }
        }
    }

    private fun isUsable(caps: NetworkCapabilities): Boolean {
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun isWifiLike(caps: NetworkCapabilities): Boolean =
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)

    private fun isCellular(caps: NetworkCapabilities): Boolean =
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)

    private fun underlyingCapabilities(
        cm: ConnectivityManager,
        vpnNetwork: Network,
    ): List<NetworkCapabilities> {
        // Requiring VALIDATED keeps an idle or captive Wi-Fi network from
        // masquerading as the active path when a VPN is up.
        return cm.allNetworks.mapNotNull { network ->
            if (network == vpnNetwork) return@mapNotNull null
            runCatching { cm.getNetworkCapabilities(network) }.getOrNull()
        }.filter { caps ->
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
    }

    private fun identityOf(cm: ConnectivityManager, network: Network, vpn: Boolean): String {
        val link = runCatching { cm.getLinkProperties(network) }.getOrNull()
        val material = buildString {
            append(if (vpn) "vpn|" else "direct|")
            if (vpn) append(network.networkHandle).append('|')
            append(link?.interfaceName.orEmpty())
            val addresses = link?.linkAddresses
                ?.mapNotNull { it.address?.hostAddress }
                ?.sorted()
                .orEmpty()
            if (addresses.isNotEmpty()) {
                append('|')
                append(addresses.joinToString(","))
            }
        }
        return sha256(material).take(16)
    }

    private fun sessionKeyOf(cm: ConnectivityManager, network: Network): String {
        val link = runCatching { cm.getLinkProperties(network) }.getOrNull()
        val addresses = link?.linkAddresses
            ?.mapNotNull { it.address?.hostAddress }
            ?.sorted()
            .orEmpty()
        return "${network.networkHandle}|${link?.interfaceName.orEmpty()}|${addresses.joinToString(",")}"
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it.toInt() and 0xFF) }
    }
}
