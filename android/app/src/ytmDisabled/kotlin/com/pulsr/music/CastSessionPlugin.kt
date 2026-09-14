package com.pulsr.music

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Stub for the `prod` (offline "Pure") flavor. MainActivity lives in src/main
 * and so references this class from every flavor; only dev/ytm get the real
 * Play Services Cast implementation in src/ytmEnabled. The channel is still
 * registered so Dart sees a clean `isAvailable == false` instead of a
 * MissingPluginException.
 */
class CastSessionPlugin : MethodChannel.MethodCallHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    companion object {
        private const val METHOD_CHANNEL = "com.pulsr.music/cast_session"
        private const val EVENT_CHANNEL = "com.pulsr.music/cast_session_events"

        fun registerWith(
            flutterEngine: FlutterEngine,
            context: android.content.Context? = null,
        ): CastSessionPlugin {
            val plugin = CastSessionPlugin()
            val mc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            plugin.methodChannel = mc
            mc.setMethodCallHandler(plugin)
            val ec = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            plugin.eventChannel = ec
            ec.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    events?.success(mapOf("type" to "routes", "routes" to emptyList<Any>()))
                }

                override fun onCancel(arguments: Any?) {}
            })
            return plugin
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(false)
            "startDiscovery" -> result.success(false)
            "stopDiscovery" -> result.success(true)
            "getRoutes" -> result.success(emptyList<Any>())
            "connect" -> result.success(false)
            "disconnect" -> result.success(true)
            "castLocalFile", "castUrl", "setPlaybackState" ->
                result.success(
                    mapOf(
                        "success" to false,
                        "error" to "Google Cast is not available in this build",
                    )
                )
            else -> result.notImplemented()
        }
    }

    fun cleanup() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel = null
    }
}
