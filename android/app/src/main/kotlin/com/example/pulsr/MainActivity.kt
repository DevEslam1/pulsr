package com.example.pulsr

import android.media.MediaMetadataRetriever
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.pulsr/lyrics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TagEditorPlugin.registerWith(flutterEngine)
        VisualizerPlugin.registerWith(flutterEngine)
        RingtonePlugin.registerWith(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
