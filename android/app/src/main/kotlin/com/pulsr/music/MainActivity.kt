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
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.audio.generic.AbstractTag
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.flac.FlacTag
import org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag
import java.io.File
 
class MainActivity : AudioServiceActivity() {
    private val LYRICS_CHANNEL = "com.pulsr.music/lyrics"
    private val FILE_OPENER_CHANNEL = "com.pulsr.music/file_opener"
    private val pendingAudioUris = ArrayDeque<String>()
    companion object {
        private const val MAX_PENDING_AUDIO_URIS = 32
    }

    private fun addPendingAudioUri(uri: String) {
        synchronized(pendingAudioUris) {
            while (pendingAudioUris.size >= MAX_PENDING_AUDIO_URIS) {
                pendingAudioUris.removeFirstOrNull()
            }
            pendingAudioUris.addLast(uri)
        }
    }
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
    private var usbExclusivePlugin: UsbExclusivePlugin? = null
    private var castDiscoveryPlugin: CastDiscoveryPlugin? = null
    private var castSessionPlugin: CastSessionPlugin? = null
    private var roomCorrectionPlugin: RoomCorrectionPlugin? = null
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
            path.endsWith(".opus") || path.endsWith(".mka") || path.endsWith(".dsf") ||
            path.endsWith(".dff") || path.endsWith(".aiff") || path.endsWith(".alac")
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
        return host.endsWith("youtu.be") || host.endsWith("youtube.com")
    }

    private fun isYouTubeUrl(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("youtu.be") || lower.contains("youtube.com")
    }

    private fun isSafeUri(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        val allowedSchemes = listOf("content", "file", "http", "https", "pulsr")
        if (scheme !in allowedSchemes) {
            Log.w("MainActivity", "Rejected URI with unsafe scheme: $scheme")
            return false
        }
        if (scheme == "file") {
            val path = uri.path ?: return false
            @Suppress("DEPRECATION")
            val extStorage = android.os.Environment.getExternalStorageDirectory()?.path
            val extFilesPath = getExternalFilesDir(null)?.path
            val filesDirPath = filesDir?.path
            val cacheDirPath = cacheDir?.path
            val allowedRoots = listOfNotNull(extStorage, extFilesPath, filesDirPath, cacheDirPath, "/storage", "/sdcard")
            if (!allowedRoots.any { path.startsWith(it) }) {
                Log.w("MainActivity", "Rejected file URI outside allowed directories: $path")
                return false
            }
        }
        return true
    }

    private fun handleAudioIntent(intent: Intent?, fromColdStart: Boolean) {
        // Assistant / voice-search entry point: bring the app forward so the
        // Dart layer can resume or start playback. Previously dropped.
        if (intent?.action == "android.media.action.MEDIA_PLAY_FROM_SEARCH") {
            val q = intent.getStringExtra("query")
            if (fromColdStart || fileOpenerChannel == null) {
                addPendingAudioUri("pulsr://voice-search?query=${Uri.encode(q ?: "")}")
            } else {
                fileOpenerChannel?.invokeMethod("onVoiceSearch", q ?: "")
            }
            return
        }
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return
        // Multi-share (EXTRA_STREAM as list) previously dropped all but one.
        if (intent.action == Intent.ACTION_SEND_MULTIPLE || intent.hasExtra(Intent.EXTRA_STREAM)) {
            try {
                val rawList: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                val list = rawList?.filter { isSafeUri(it) }
                if (!list.isNullOrEmpty()) {
                    for (u in list) addPendingAudioUri(u.toString())
                    if (!fromColdStart && fileOpenerChannel != null) {
                        fileOpenerChannel?.invokeMethod("onAudioFileOpened", list.first().toString())
                    }
                    return
                }
            } catch (_: Exception) {}
        }
        val textExtra = intent.getStringExtra(Intent.EXTRA_TEXT)
        val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val uri = intent.data ?: streamUri ?: (if (!textExtra.isNullOrEmpty() && (isYouTubeUrl(textExtra) || isProxyText(textExtra))) Uri.parse(textExtra) else null) ?: return
        if (!isSafeUri(uri)) {
            Log.w("MainActivity", "Ignoring unsafe URI: $uri")
            return
        }
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
            addPendingAudioUri(uriStr)
        } else {
            fileOpenerChannel?.invokeMethod("onAudioFileOpened", uriStr)
        }
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
        usbExclusivePlugin = UsbExclusivePlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        castDiscoveryPlugin = CastDiscoveryPlugin(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        castSessionPlugin = CastSessionPlugin.registerWith(flutterEngine, applicationContext)
        roomCorrectionPlugin = RoomCorrectionPlugin.registerWith(flutterEngine, applicationContext)
 
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
                    var lyrics: String? = null
                    var tempFile: File? = null
                    try {
                        val file = if (filePath.startsWith("content:")) {
                            val uri = Uri.parse(filePath)
                            val inputStream = contentResolver.openInputStream(uri)
                            if (inputStream != null) {
                                tempFile = File.createTempFile("lyrics_", ".tmp", cacheDir)
                                inputStream.use { input ->
                                    tempFile.outputStream().use { output -> input.copyTo(output) }
                                }
                                tempFile
                            } else {
                                null
                            }
                        } else {
                            File(filePath)
                        }

                        if (file != null && file.exists()) {
                            // 1) jaudiotagger – LYRICS key (widely supported)
                            try {
                                val audioFile = AudioFileIO.read(file)
                                lyrics = audioFile.tag?.getFirst(FieldKey.LYRICS)
                                // 1b) FLAC/OGG store lyrics in Vorbis comments, but
                                // most taggers write UNSYNCEDLYRICS / SYNCEDLYRICS,
                                // which jaudiotagger 3.x has no FieldKey mapping for
                                // (only "LYRICS" is mapped). Probe those keys by raw
                                // name on the Vorbis-backed tags or they are missed.
                                // SYNCED is preferred over UNSYNCED when both exist
                                // (reader ids are uppercased on read, so these exact
                                // names match any letter case the tagger used).
                                if (lyrics.isNullOrBlank()) {
                                    val vorbisTag: AbstractTag? = when (val tag = audioFile.tag) {
                                        is FlacTag -> tag.vorbisCommentTag
                                        is VorbisCommentTag -> tag
                                        is AbstractTag -> tag
                                        else -> null
                                    }
                                    if (vorbisTag != null) {
                                        for (key in listOf(
                                            "SYNCEDLYRICS",
                                            "UNSYNCEDLYRICS",
                                            "SYNCED LYRICS",
                                            "UNSYNCED LYRICS"
                                        )) {
                                            val v = vorbisTag.getFirst(key)
                                            if (!v.isNullOrBlank()) {
                                                lyrics = v
                                                break
                                            }
                                        }
                                    }
                                }
                            } catch (_: Exception) {}
                            // 2) MediaMetadataRetriever fallback – some OEMs write lyrics that jaudiotagger misses
                            if (lyrics.isNullOrBlank()) {
                                var retriever: MediaMetadataRetriever? = null
                                try {
                                    retriever = MediaMetadataRetriever()
                                    if (filePath.startsWith("content:")) {
                                        retriever.setDataSource(applicationContext, Uri.parse(filePath))
                                    } else {
                                        retriever.setDataSource(file.absolutePath)
                                    }
                                    // No dedicated lyrics key in MediaMetadataRetriever, but try writer/lyricist
                                    val fallbackKeys = listOf(
                                        MediaMetadataRetriever.METADATA_KEY_WRITER,
                                        MediaMetadataRetriever.METADATA_KEY_AUTHOR
                                    )
                                    for (k in fallbackKeys) {
                                        val v = retriever.extractMetadata(k)
                                        if (!v.isNullOrBlank() && v.contains("\n")) {
                                            lyrics = v; break
                                        }
                                    }
                                } catch (_: Exception) {} finally {
                                    try { retriever?.release() } catch (_: Exception) {}
                                }
                            }
                        }
                        runOnUiThread { runCatching { result.success(lyrics) } }
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Embedded lyrics extraction failed for $filePath: ${e.message}")
                        runOnUiThread { runCatching { result.success(null) } }
                    } finally {
                        tempFile?.let { runCatching { it.delete() } }
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        // Pulsr Pure runtime guarantee: report whether the merged manifest
        // actually carries the INTERNET permission, so the Dart layer can
        // detect a bad manifest merge that would silently add network access.
        val purityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pulsr.music/purity")
        purityChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasInternetPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        checkSelfPermission(android.Manifest.permission.INTERNET) ==
                            android.content.pm.PackageManager.PERMISSION_GRANTED
                    } else {
                        packageManager.checkPermission(
                            android.Manifest.permission.INTERNET,
                            packageName) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    }
                    result.success(granted)
                }
                else -> result.notImplemented()
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
        audioEffectsPlugin?.cleanup()
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
        usbExclusivePlugin?.dispose()
        usbExclusivePlugin = null
        castDiscoveryPlugin?.dispose()
        castDiscoveryPlugin = null
        castSessionPlugin?.cleanup()
        castSessionPlugin = null
        roomCorrectionPlugin?.cleanup()
        roomCorrectionPlugin = null
        fileOpenerChannel?.setMethodCallHandler(null)
        fileOpenerChannel = null
        lyricsChannel?.setMethodCallHandler(null)
        lyricsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
