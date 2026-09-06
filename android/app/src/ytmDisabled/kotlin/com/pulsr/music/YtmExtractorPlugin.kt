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
        when (call.method) {
            "isAvailable" -> result.success(false)
            "isWifiConnected" -> result.success(true)
            "ensurePoTokenReady" -> result.success(false)
            "invalidatePoToken" -> result.success(true)
            "getPoTokenState" -> result.success(
                mapOf(
                    "isReady" to false,
                    "isExpired" to true,
                    "isExpiringSoon" to true,
                    "visitorData" to "",
                    "webViewBroken" to false,
                )
            )
            "getCookies" -> {
                val urls = listOf(
                    "https://music.youtube.com",
                    "https://www.youtube.com",
                    "https://accounts.google.com",
                    "https://youtube.com"
                )
                val cookieJar = mutableMapOf<String, String>()
                val cm = android.webkit.CookieManager.getInstance()
                for (u in urls) {
                    val c = cm.getCookie(u) ?: continue
                    for (pair in c.split(";")) {
                        val parts = pair.trim().split("=", limit = 2)
                        if (parts.size == 2 && parts[0].isNotBlank()) {
                            cookieJar[parts[0].trim()] = parts[1].trim()
                        }
                    }
                }
                val merged = cookieJar.entries.joinToString("; ") { "${it.key}=${it.value}" }
                result.success(merged)
            }
            "setCookies" -> result.success(true)
            "isVpnConnected" -> result.success(false)
            "clearNetworkCaches" -> result.success(true)
            else -> result.error("YTM_DISABLED", "YouTube Music is not available in this build", null)
        }
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
