package com.pulsr.music

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Google Cast device discovery via Android Network Service Discovery
 * (mDNS `_googlecast._tcp`).
 *
 * SCOPE (honest): this discovers Cast receivers on the LAN and reports their
 * friendly name / model / id. Starting a cast *session* requires the Google
 * Play Services Cast framework and a registered Cast receiver application id,
 * neither of which is available to this build, so [castTo] reports the
 * configuration error instead of pretending to connect.
 */
class CastDiscoveryPlugin(
    context: Context,
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "CastDiscoveryPlugin"
        const val METHOD_CHANNEL = "com.pulsr.music/cast"
        const val EVENT_CHANNEL = "com.pulsr.music/cast_events"
        private const val CAST_SERVICE_TYPE = "_googlecast._tcp."
        private val CAST_ATTR_KEYS = listOf("fn", "md", "id", "ve")
    }

    private val appContext = context.applicationContext
    private val nsdManager =
        appContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private val devices = ConcurrentHashMap<String, Map<String, Any?>>()
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var discovering = false
    private var lastError: String? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    private fun isCastSdkAvailable(): Boolean {
        return try {
            Class.forName("com.google.android.gms.cast.framework.CastContext")
            true
        } catch (_: Throwable) {
            false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(nsdManager != null)
                "isCastSdkAvailable" -> result.success(isCastSdkAvailable())
                "startDiscovery" -> {
                    startDiscovery()
                    result.success(true)
                }
                "stopDiscovery" -> {
                    stopDiscovery()
                    result.success(true)
                }
                "getDevices" -> result.success(devices.values.toList())
                "castTo" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val appId = call.argument<String>("appId")
                    val sdkAvailable = isCastSdkAvailable()
                    val message = when {
                        !sdkAvailable -> "Google Play Services Cast SDK is not bundled in this build."
                        appId.isNullOrBlank() -> "Google Cast playback requires a Cast receiver application id (--dart-define=CAST_RECEIVER_APP_ID)."
                        else -> "Connecting to cast device..."
                    }
                    result.success(
                        mapOf(
                            "success" to false,
                            "error" to if (!sdkAvailable) "cast_sdk_unavailable" else "cast_not_configured",
                            "message" to message,
                            "deviceId" to deviceId,
                            "appIdConfigured" to !appId.isNullOrBlank(),
                            "castSdkAvailable" to sdkAvailable,
                        )
                    )
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MethodChannel error handling ${call.method}: ${e.message}", e)
            result.error("CAST_ERROR", e.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Auto-start discovery when a listener attaches.
        startDiscovery()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopDiscovery()
    }

    fun dispose() {
        stopDiscovery()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun startDiscovery() {
        val nsd = nsdManager ?: run {
            emitError("nsd_unavailable")
            return
        }
        if (discovering) return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String?) {
                discovering = true
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
                if (serviceInfo == null) return
                resolve(nsd, serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
                val key = serviceInfo?.serviceName ?: return
                devices.remove(key)
                emitDevices()
            }

            override fun onDiscoveryStopped(serviceType: String?) {
                discovering = false
            }

            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                discovering = false
                lastError = "start_failed_$errorCode"
                emitError(lastError!!)
            }

            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
                discovering = false
            }
        }
        discoveryListener = listener
        try {
            nsd.discoverServices(CAST_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            Log.w(TAG, "discoverServices failed: ${e.message}")
            discovering = false
            emitError("discovery_exception")
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(nsd: NsdManager, serviceInfo: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo?, errorCode: Int) {
                // Not fatal: another service may resolve. Ignore.
            }

            override fun onServiceResolved(info: NsdServiceInfo?) {
                if (info == null) return
                val attrs = mutableMapOf<String, String>()
                try {
                    info.attributes?.forEach { (k, v) ->
                        if (CAST_ATTR_KEYS.contains(k)) {
                            attrs[k] = String(v, Charsets.UTF_8)
                        }
                    }
                } catch (_: Exception) {}
                val id = attrs["id"] ?: info.serviceName
                val host = info.host?.hostAddress ?: ""
                devices[id] = mapOf(
                    "id" to id,
                    "name" to (attrs["fn"] ?: info.serviceName),
                    "model" to (attrs["md"] ?: ""),
                    "host" to host,
                    "port" to info.port,
                )
                emitDevices()
            }
        }
        try {
            nsd.resolveService(serviceInfo, resolveListener)
        } catch (e: Exception) {
            Log.w(TAG, "resolveService failed: ${e.message}")
        }
    }

    private fun stopDiscovery() {
        val listener = discoveryListener ?: return
        discoveryListener = null
        discovering = false
        try {
            nsdManager?.stopServiceDiscovery(listener)
        } catch (_: Exception) {}
    }

    private fun emitDevices() {
        val sink = eventSink ?: return
        val snapshot = devices.values.toList()
        mainHandler.post {
            try {
                sink.success(
                    mapOf(
                        "type" to "devices",
                        "devices" to snapshot,
                    )
                )
            } catch (_: Exception) {}
        }
    }

    private fun emitError(code: String) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(mapOf("type" to "error", "error" to code))
            } catch (_: Exception) {}
        }
    }
}
