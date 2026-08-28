package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Proxy
import java.util.concurrent.Executors

/**
 * MethodChannel plugin for managing proxy pool settings and testing connectivity from Flutter.
 * Placed in src/main - strictly generic.
 */
class ProxyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newFixedThreadPool(2)

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/proxy"

        fun registerWith(flutterEngine: FlutterEngine, context: Context): ProxyPlugin {
            val plugin = ProxyPlugin()
            plugin.context = context
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            ProxyPool.setOnPathChangeListener { label ->
                plugin.mainHandler.post {
                    plugin.channel?.invokeMethod("onPathChanged", mapOf("path" to label))
                }
            }
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        ProxyPool.setOnPathChangeListener { label ->
            mainHandler.post {
                channel?.invokeMethod("onPathChanged", mapOf("path" to label))
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        try {
            executor.shutdownNow()
        } catch (_: Exception) {}
        ProxyManager.dispose()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setProxy" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val type = call.argument<String>("type")
                val host = call.argument<String>("host")
                val port = call.argument<Int>("port")
                val username = call.argument<String>("username")
                val password = call.argument<String>("password")
                val bypassHosts = call.argument<String>("bypassHosts")

                ProxyManager.setProxy(
                    enabled = enabled,
                    type = type,
                    host = host,
                    port = port,
                    username = username,
                    password = password,
                    bypassHosts = bypassHosts,
                )
                result.success(true)
            }
            "setProxyPool" -> {
                val rawList = call.argument<List<Map<String, Any?>>>("proxies") ?: emptyList()
                val autoRotate = call.argument<Boolean>("autoRotate") ?: true
                val nodes = rawList.mapNotNull { map ->
                    val host = (map["host"] as? String)?.trim() ?: return@mapNotNull null
                    val port = (map["port"] as? Number)?.toInt() ?: return@mapNotNull null
                    if (host.isEmpty() || port <= 0) return@mapNotNull null
                    val typeStr = (map["type"] as? String)?.lowercase() ?: "http"
                    val pType = if (typeStr == "socks5" || typeStr == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
                    val username = (map["username"] as? String)?.trim() ?: ""
                    val password = (map["password"] as? String) ?: ""
                    val isEnabled = (map["isEnabled"] as? Boolean) ?: true
                    val id = (map["id"] as? String) ?: "$host:$port"

                    ProxyPool.ProxyNode(
                        id = id,
                        type = pType,
                        host = host,
                        port = port,
                        username = username,
                        password = password,
                        isEnabled = isEnabled
                    )
                }
                ProxyPool.setAutoRotate(autoRotate)
                ProxyPool.setProxies(nodes)
                result.success(true)
            }
            "testProxy" -> {
                val testUrl = call.argument<String>("testUrl") ?: "https://www.google.com/generate_204"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000

                executor.execute {
                    val res = ProxyManager.testConnection(testUrl, timeoutMs)
                    mainHandler.post {
                        result.success(res)
                    }
                }
            }
            "testAllProxies" -> {
                val probeUrl = call.argument<String>("probeUrl") ?: "https://www.google.com/generate_204"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 8000
                ProxyPool.testAllProxies(probeUrl, timeoutMs) { results ->
                    mainHandler.post {
                        result.success(results)
                    }
                }
            }
            "getPathLabel" -> {
                result.success(ProxyPool.currentPathLabel)
            }
            "setPinnedIpFamily" -> {
                val family = call.argument<String>("family")
                ProxyManager.setPinnedIpFamily(family)
                result.success(true)
            }
            "getPinnedIpFamily" -> {
                result.success(ProxyManager.pinnedIpFamily)
            }
            else -> result.notImplemented()
        }
    }
}
