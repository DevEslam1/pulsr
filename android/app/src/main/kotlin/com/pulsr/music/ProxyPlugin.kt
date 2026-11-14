package com.pulsr.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Proxy
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * MethodChannel plugin for managing proxy pool settings and testing connectivity from Flutter.
 * Placed in src/main - strictly generic.
 */
class ProxyPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var executor: ExecutorService = newExecutor()
    private val executorLock = Any()
    @Volatile
    private var engineAttached = false

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/proxy"
        private val activeEngines = AtomicInteger(0)

        private fun newExecutor(): ExecutorService =
            Executors.newFixedThreadPool(2) { r ->
                Thread(r, "PulsrProxy").apply { isDaemon = true }
            }

        fun registerWith(flutterEngine: FlutterEngine, context: Context): ProxyPlugin {
            val plugin = ProxyPlugin()
            plugin.context = context
            plugin.ensureExecutor()
            plugin.engineAttached = true
            activeEngines.incrementAndGet()
            DnsOverHttpsResolver.initialize(context)
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel = channel
            channel.setMethodCallHandler(plugin)
            ProxyPool.setOnPathChangeListener { label ->
                plugin.mainHandler.post {
                    safeCall("ProxyPlugin", "onPathChanged") {
                        plugin.channel?.invokeMethod("onPathChanged", mapOf("path" to label))
                    }
                }
            }
            return plugin
        }
    }

    private fun ensureExecutor(): ExecutorService {
        val current = executor
        if (!current.isShutdown) return current
        synchronized(executorLock) {
            if (executor.isShutdown) {
                executor = newExecutor()
            }
            return executor
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        ensureExecutor()
        if (!engineAttached) {
            engineAttached = true
            activeEngines.incrementAndGet()
        }
        DnsOverHttpsResolver.initialize(binding.applicationContext)
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
        val currentExecutor = executor
        try {
            currentExecutor.shutdownNow()
            currentExecutor.awaitTermination(100, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: Exception) {}
        if (engineAttached) {
            engineAttached = false
            val remaining = activeEngines.updateAndGet { count -> if (count > 0) count - 1 else 0 }
            if (remaining == 0) {
                ProxyManager.dispose()
            }
        }
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
                val failClosed = call.argument<Boolean>("failClosed") ?: false

                ProxyManager.setProxy(
                    enabled = enabled,
                    type = type,
                    host = host,
                    port = port,
                    username = username,
                    password = password,
                    bypassHosts = bypassHosts,
                    failClosed = failClosed,
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
                // An empty list clears the pool but must not mark it as an
                // explicit (user-supplied) pool; otherwise ProxyManager stops
                // honoring the single-proxy configuration.
                ProxyPool.setProxies(nodes, isExplicit = nodes.isNotEmpty())
                // The JVM Authenticator resolves HTTPS CONNECT credentials from
                // the pool; a pool-only configuration must install it too.
                ProxyManager.refreshAuthenticator()
                result.success(true)
            }
            "testProxy" -> {
                val testUrl = call.argument<String>("testUrl") ?: "https://www.google.com/generate_204"
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000

                try {
                    ensureExecutor().execute {
                        val res = ProxyManager.testConnection(testUrl, timeoutMs)
                        mainHandler.post {
                            try {
                                result.success(res)
                            } catch (_: Exception) {
                            }
                        }
                    }
                } catch (e: java.util.concurrent.RejectedExecutionException) {
                    result.error("PLUGIN_DISPOSED", "Proxy plugin is shutting down", null)
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
            else -> result.notImplemented()
        }
    }
}
