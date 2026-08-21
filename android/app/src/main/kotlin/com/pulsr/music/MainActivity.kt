package com.pulsr.music
 
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
 
class MainActivity : AudioServiceActivity() {
    private val LYRICS_CHANNEL = "com.pulsr.music/lyrics"
    private val FILE_OPENER_CHANNEL = "com.pulsr.music/file_opener"
    private var pendingAudioUri: String? = null
    private var fileOpenerChannel: MethodChannel? = null
    private var lyricsChannel: MethodChannel? = null
    private var audioEffectsPlugin: AudioEffectsPlugin? = null
    private var tagEditorPlugin: TagEditorPlugin? = null
    private var visualizerPlugin: VisualizerPlugin? = null
    private var ringtonePlugin: RingtonePlugin? = null
    private val backgroundExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
 
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
        backgroundExecutor.shutdown()
        super.onDestroy()
    }
 
    private fun isAudioIntent(intent: Intent, uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (scheme == "pulsrwidget") return false
        if (intent.action == Intent.ACTION_SEND) {
            return intent.type?.startsWith("audio/") == true ||
                (scheme == "content" && intent.type == null)
        }
        if (intent.type?.startsWith("audio/") == true) return true
        val path = uri.path?.lowercase() ?: ""
        val isAudioExt = path.endsWith(".mp3") || path.endsWith(".flac") || path.endsWith(".wav") ||
            path.endsWith(".aac") || path.endsWith(".m4a") || path.endsWith(".ogg") ||
            path.endsWith(".opus") || path.endsWith(".wma") || path.endsWith(".alac") ||
            path.endsWith(".aiff") || path.endsWith(".dsf") || path.endsWith(".dff")
        return isAudioExt || (scheme == "content" && intent.type == null)
    }

    private fun handleAudioIntent(intent: Intent?, fromColdStart: Boolean) {
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return
        val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val uri = intent.data ?: streamUri ?: return
        if (!isAudioIntent(intent, uri)) return

        if (fromColdStart) {
            pendingAudioUri = uri.toString()
        } else {
            fileOpenerChannel?.invokeMethod("onAudioFileOpened", uri.toString())
            pendingAudioUri = null
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
 
        val fileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPENER_CHANNEL)
        fileOpenerChannel = fileChannel
        fileChannel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialAudioUri") {
                val uri = pendingAudioUri
                pendingAudioUri = null
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
                backgroundExecutor.execute {
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
        fileOpenerChannel?.setMethodCallHandler(null)
        fileOpenerChannel = null
        lyricsChannel?.setMethodCallHandler(null)
        lyricsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
