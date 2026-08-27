package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * MethodChannel plugin for managing proxy settings and testing connectivity from Flutter.
 */
class ProxyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/proxy"

        fun registerWith(flutterEngine: FlutterEngine, context: Context): ProxyPlugin {
            val plugin = ProxyPlugin()
            plugin.context = context
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
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
            "testProxy" -> {
                val testUrl = call.argument<String>("testUrl") ?: "https://music.youtube.com/generate_204"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000

                executor.execute {
                    val res = ProxyManager.testConnection(testUrl, timeoutMs)
                    mainHandler.post {
                        result.success(res)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
}
