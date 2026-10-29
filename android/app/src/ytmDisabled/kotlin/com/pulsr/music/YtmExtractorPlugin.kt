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
        private const val DISABLED_REASON = "YouTube Music is not available in this build"

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
            "isVpnConnected" -> result.success(false)
            "getLimitedMode" -> result.success(false)
            "ensurePoTokenReady" -> result.success(false)
            "invalidatePoToken" -> result.success(true)
            "getPlayerPoToken" -> result.success(null)
            "getAccountPoToken" -> result.success(null)
            "setDataSyncId" -> result.success(true)
            "setClientVersion" -> result.success(false)
            "preWarm" -> result.success(true)
            "resetIdentities" -> result.success(true)
            // Same key set as the real plugin: the Dart layer reads streamingPoToken and
            // isLimitedMode out of this map, and a missing key is a different failure mode
            // from a false one.
            "getPoTokenState" -> result.success(
                mapOf(
                    "isReady" to false,
                    "isExpired" to true,
                    "isExpiringSoon" to true,
                    "visitorData" to "",
                    "streamingPoToken" to "",
                    "webViewBroken" to false,
                    "isLimitedMode" to false,
                )
            )
            "getClientCapabilitiesState" -> result.success(null)
            // Data calls are gated on `isAvailable == false` in Dart and must fail
            // loudly rather than return an empty payload that reads as "no
            // results". Listed explicitly so validateChannelParity can prove this
            // stub covers every method the enabled plugin declares.
            "updateClientCapabilities",
            "search",
            "searchContinuation",
            "trending",
            "getCharts",
            "getMoods",
            "getPlaylist",
            "resolveStream" -> result.error("YTM_DISABLED", DISABLED_REASON, null)
            "getCookies" -> {
                // YouTube hosts only. Folding accounts.google.com into the same
                // name-keyed jar sent Google account-management cookies to
                // youtube.com, which a browser never does.
                val urls = listOf(
                    "https://music.youtube.com",
                    "https://www.youtube.com",
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
            "clearCookies" -> result.success(true)
            "clearNetworkCaches" -> result.success(true)
            else -> result.error("YTM_DISABLED", DISABLED_REASON, null)
        }
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
