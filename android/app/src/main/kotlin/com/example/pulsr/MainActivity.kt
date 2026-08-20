package com.example.pulsr

import android.content.Intent
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val LYRICS_CHANNEL = "com.example.pulsr/lyrics"
    private val FILE_OPENER_CHANNEL = "com.example.pulsr/file_opener"
    private var pendingAudioUri: String? = null
    private var fileOpenerChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAudioIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAudioIntent(intent)
    }

    private fun handleAudioIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW || intent?.action == Intent.ACTION_SEND) {
            val uri = intent.data?.toString() ?: intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)?.toString()
            if (uri != null) {
                pendingAudioUri = uri
                fileOpenerChannel?.invokeMethod("onAudioFileOpened", uri)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TagEditorPlugin.registerWith(flutterEngine)
        VisualizerPlugin.registerWith(flutterEngine)
        RingtonePlugin.registerWith(flutterEngine)

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LYRICS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getEmbeddedLyrics") {
                val filePath = call.argument<String>("filePath")
                if (filePath == null) {
                    result.error("INVALID_ARGUMENT", "File path is null", null)
                    return@setMethodCallHandler
                }
                try {
                    val retriever = MediaMetadataRetriever()
                    retriever.setDataSource(filePath)
                    val lyrics = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        retriever.extractMetadata(1000)
                    } else {
                        null
                    }
                    retriever.release()
                    result.success(lyrics)
                } catch (e: Exception) {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
