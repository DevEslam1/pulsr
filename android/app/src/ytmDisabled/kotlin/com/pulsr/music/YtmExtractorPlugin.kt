package com.pulsr.music

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Stub for the `prod` (Play Store) flavor. MainActivity lives in src/main and so
 * references this class from every flavor, but only `dev` and `ytm` get the real
 * implementation in src/ytmEnabled -- which is what keeps GPL-3.0
 * NewPipeExtractor out of the Play Store binary entirely.
 *
 * The channel is still registered so Dart gets a clean `isAvailable == false`
 * rather than a MissingPluginException if a gate is ever missed.
 */
class YtmExtractorPlugin : MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    companion object {
        private const val CHANNEL_NAME = "com.pulsr.music/ytm"

        fun registerWith(flutterEngine: FlutterEngine, context: android.content.Context? = null): YtmExtractorPlugin {
            val plugin = YtmExtractorPlugin()
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "isAvailable") {
            result.success(false)
        } else {
            result.error("YTM_DISABLED", "YouTube Music is not available in this build", null)
        }
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
