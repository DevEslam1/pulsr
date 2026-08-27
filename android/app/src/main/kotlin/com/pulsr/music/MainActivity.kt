package com.pulsr.music
 
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
 
class MainActivity : AudioServiceActivity() {
    private val LYRICS_CHANNEL = "com.pulsr.music/lyrics"
    private val FILE_OPENER_CHANNEL = "com.pulsr.music/file_opener"
    private val pendingAudioUris = ArrayDeque<String>()
    private var fileOpenerChannel: MethodChannel? = null
    private var lyricsChannel: MethodChannel? = null
    private var audioEffectsPlugin: AudioEffectsPlugin? = null
    private var tagEditorPlugin: TagEditorPlugin? = null
    private var visualizerPlugin: VisualizerPlugin? = null
    private var ringtonePlugin: RingtonePlugin? = null
    private var scrobblerPlugin: ScrobblerPlugin? = null
    private var ytmExtractorPlugin: YtmExtractorPlugin? = null
    private var ytDownloadPlugin: YtDownloadPlugin? = null
    private var waveformPlugin: WaveformPlugin? = null
    private var proxyPlugin: ProxyPlugin? = null
    private var hiResDacPlugin: HiResDacPlugin? = null
    private val lyricsExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
 
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAudioIntent(intent, fromColdStart = true)
    }
 
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAudioIntent(intent, fromColdStart = false)
    }

    override fun onDestroy() {
        synchronized(pendingAudioUris) {
            pendingAudioUris.clear()
        }
        try {
            lyricsExecutor.shutdownNow()
            lyricsExecutor.awaitTermination(1, java.util.concurrent.TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.w("MainActivity", "Error shutting down lyrics executor: ${e.message}")
        }
        super.onDestroy()
    }
 
    private fun isAudioIntent(intent: Intent, uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme == "pulsrwidget") return false
        if (isYouTubeUri(uri)) return true
        if (intent.action == Intent.ACTION_SEND) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrEmpty() && (isYouTubeUrl(text) || isProxyText(text))) return true
            return intent.type?.startsWith("audio/") == true ||
                intent.type?.startsWith("text/") == true ||
                (scheme == "content" && intent.type == null)
        }
        if (intent.type?.startsWith("audio/") == true || intent.type?.startsWith("text/") == true) return true
        val path = uri.path?.lowercase() ?: ""
        val isAudioExt = path.endsWith(".mp3") || path.endsWith(".flac") || path.endsWith(".wav") ||
            path.endsWith(".aac") || path.endsWith(".m4a") || path.endsWith(".ogg") ||
            path.endsWith(".opus") || path.endsWith(".mka")
        val isTextExt = path.endsWith(".txt") || path.endsWith(".list") || path.endsWith(".conf") || path.endsWith(".csv")
        return isAudioExt || isTextExt || (scheme == "content" && intent.type == null)
    }

    private fun isProxyText(text: String): Boolean {
        val pattern = Regex("""\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}):(\d{2,5})\b""")
        return pattern.containsMatchIn(text) && pattern.find(text)?.let { m ->
            val octets = (1..4).map { m.groupValues[it].toIntOrNull() ?: 256 }
            val port = m.groupValues[5].toIntOrNull() ?: 0
            octets.all { it in 0..255 } && port in 1..65535
        } ?: false
    }

    private fun isYouTubeUri(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: ""
        return host == "music.youtube.com" || host == "youtube.com" || host == "www.youtube.com" ||
            host == "m.youtube.com" || host == "youtu.be"
    }

    private fun isYouTubeUrl(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("music.youtube.com") || lower.contains("youtube.com") || lower.contains("youtu.be")
    }

    private fun handleAudioIntent(intent: Intent?, fromColdStart: Boolean) {
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return
        val textExtra = intent.getStringExtra(Intent.EXTRA_TEXT)
        val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val uri = intent.data ?: streamUri ?: (if (!textExtra.isNullOrEmpty() && (isYouTubeUrl(textExtra) || isProxyText(textExtra))) Uri.parse(textExtra) else null) ?: return
        if (!isAudioIntent(intent, uri)) return

        if (uri.scheme?.equals("content", ignoreCase = true) == true) {
            try {
                val flags = intent.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (flags != 0) {
                    contentResolver.takePersistableUriPermission(uri, flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } catch (e: Exception) {
                Log.d("MainActivity", "Persistable URI grant not supported or failed for $uri: ${e.message}")
            }
        }

        val uriStr = uri.toString()
        if (fromColdStart || fileOpenerChannel == null) {
            synchronized(pendingAudioUris) {
                pendingAudioUris.addLast(uriStr)
            }
        } else {
            fileOpenerChannel?.invokeMethod("onAudioFileOpened", uriStr)
        }
    }
 
    companion object {
        private const val METADATA_KEY_LYRICS = 1000
    }
 
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tagEditorPlugin = TagEditorPlugin.registerWith(flutterEngine, applicationContext)
        visualizerPlugin = VisualizerPlugin.registerWith(flutterEngine)
        ringtonePlugin = RingtonePlugin.registerWith(flutterEngine, applicationContext)
        audioEffectsPlugin = AudioEffectsPlugin.registerWith(flutterEngine, applicationContext)
        scrobblerPlugin = ScrobblerPlugin.registerWith(flutterEngine, applicationContext)
        ytmExtractorPlugin = YtmExtractorPlugin.registerWith(flutterEngine, applicationContext)
        ytDownloadPlugin = YtDownloadPlugin.registerWith(flutterEngine, applicationContext)
        waveformPlugin = WaveformPlugin.registerWith(flutterEngine, applicationContext)
        proxyPlugin = ProxyPlugin.registerWith(flutterEngine, applicationContext)
        hiResDacPlugin = HiResDacPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
 
        val fileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPENER_CHANNEL)
        fileOpenerChannel = fileChannel
        fileChannel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialAudioUri") {
                val uri = synchronized(pendingAudioUris) {
                    pendingAudioUris.removeFirstOrNull()
                }
                result.success(uri)
            } else {
                result.notImplemented()
            }
        }
 
        val lyricsChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LYRICS_CHANNEL)
        lyricsChannel = lyricsChan
        lyricsChan.setMethodCallHandler { call, result ->
            if (call.method == "getEmbeddedLyrics") {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "File path is null", null)
                    return@setMethodCallHandler
                }
                lyricsExecutor.execute {
                    val retriever = MediaMetadataRetriever()
                    try {
                        if (filePath.startsWith("content:")) {
                            retriever.setDataSource(this, Uri.parse(filePath))
                        } else {
                            retriever.setDataSource(filePath)
                        }
                        val lyrics = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            retriever.extractMetadata(METADATA_KEY_LYRICS)
                        } else {
                            null
                        }
                        runOnUiThread { runCatching { result.success(lyrics) } }
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Embedded lyrics extraction failed for $filePath: ${e.message}")
                        runOnUiThread { runCatching { result.success(null) } }
                    } finally {
                        runCatching { retriever.release() }
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        val batteryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/battery_optimization")
        batteryChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(isIgnoring)
                    } else {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("BATTERY_OPT_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }
                "getBatteryLevel" -> {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
                    val level = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
                    result.success(level)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audioEffectsPlugin?.releaseEffects()
        audioEffectsPlugin = null
        tagEditorPlugin?.cleanup()
        tagEditorPlugin = null
        visualizerPlugin?.cleanup()
        visualizerPlugin = null
        ringtonePlugin?.cleanup()
        ringtonePlugin = null
        scrobblerPlugin?.cleanup()
        scrobblerPlugin = null
        ytmExtractorPlugin?.cleanup()
        ytmExtractorPlugin = null
        ytDownloadPlugin?.cleanup()
        ytDownloadPlugin = null
        waveformPlugin?.cleanup()
        waveformPlugin = null
        proxyPlugin?.cleanup()
        proxyPlugin = null
        hiResDacPlugin?.dispose()
        hiResDacPlugin = null
        fileOpenerChannel?.setMethodCallHandler(null)
        fileOpenerChannel = null
        lyricsChannel?.setMethodCallHandler(null)
        lyricsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
