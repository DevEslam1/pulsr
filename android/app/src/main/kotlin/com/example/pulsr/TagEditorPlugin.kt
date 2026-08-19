package com.example.pulsr

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.images.ArtworkFactory
import java.io.File
import java.util.logging.Level
import java.util.logging.Logger

class TagEditorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        const val CHANNEL_NAME = "com.example.pulsr/tag_editor"

        fun registerWith(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
            val plugin = TagEditorPlugin()
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            disableLogger()
        }

        private fun disableLogger() {
            try {
                Logger.getLogger("org.jaudiotagger").level = Level.OFF
            } catch (_: Exception) {}
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        disableLogger()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "readTags" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }
                try {
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                        return
                    }
                    val audioFile = AudioFileIO.read(file)
                    val tag = audioFile.tag

                    val resultMap = mutableMapOf<String, Any?>()
                    if (tag != null) {
                        resultMap["title"] = tag.getFirst(FieldKey.TITLE)
                        resultMap["artist"] = tag.getFirst(FieldKey.ARTIST)
                        resultMap["album"] = tag.getFirst(FieldKey.ALBUM)
                        resultMap["genre"] = tag.getFirst(FieldKey.GENRE)
                        resultMap["year"] = tag.getFirst(FieldKey.YEAR)
                        resultMap["trackNumber"] = tag.getFirst(FieldKey.TRACK)
                        resultMap["comment"] = tag.getFirst(FieldKey.COMMENT)
                        resultMap["lyrics"] = tag.getFirst(FieldKey.LYRICS)

                        val artwork = tag.firstArtwork
                        if (artwork != null && artwork.binaryData != null) {
                            resultMap["artwork"] = artwork.binaryData
                        } else {
                            resultMap["artwork"] = null
                        }
                    } else {
                        resultMap["title"] = ""
                        resultMap["artist"] = ""
                        resultMap["album"] = ""
                        resultMap["genre"] = ""
                        resultMap["year"] = ""
                        resultMap["trackNumber"] = ""
                        resultMap["comment"] = ""
                        resultMap["lyrics"] = ""
                        resultMap["artwork"] = null
                    }
                    result.success(resultMap)
                } catch (e: Exception) {
                    result.error("READ_ERROR", "Failed to read tags: ${e.localizedMessage}", e.stackTraceToString())
                }
            }
            "writeTags" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }
                try {
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                        return
                    }
                    val audioFile = AudioFileIO.read(file)
                    var tag = audioFile.tag
                    if (tag == null) {
                        tag = audioFile.createDefaultTag()
                        audioFile.tag = tag
                    }

                    fun setOrDelete(key: FieldKey, value: String?) {
                        try {
                            if (value != null) {
                                tag.setField(key, value)
                            }
                        } catch (e: Exception) {
                            try {
                                tag.deleteField(key)
                                if (!value.isNullOrEmpty()) {
                                    tag.addField(key, value)
                                }
                            } catch (_: Exception) {}
                        }
                    }

                    call.argument<String>("title")?.let { setOrDelete(FieldKey.TITLE, it) }
                    call.argument<String>("artist")?.let { setOrDelete(FieldKey.ARTIST, it) }
                    call.argument<String>("album")?.let { setOrDelete(FieldKey.ALBUM, it) }
                    call.argument<String>("genre")?.let { setOrDelete(FieldKey.GENRE, it) }
                    call.argument<String>("year")?.let { setOrDelete(FieldKey.YEAR, it) }
                    call.argument<String>("trackNumber")?.let { setOrDelete(FieldKey.TRACK, it) }
                    call.argument<String>("comment")?.let { setOrDelete(FieldKey.COMMENT, it) }
                    call.argument<String>("lyrics")?.let { setOrDelete(FieldKey.LYRICS, it) }

                    val removeArtwork = call.argument<Boolean>("removeArtwork") ?: false
                    if (removeArtwork) {
                        try {
                            tag.deleteArtworkField()
                        } catch (_: Exception) {}
                    }

                    val artworkPath = call.argument<String>("artworkPath")
                    if (!artworkPath.isNullOrEmpty()) {
                        val artworkFile = File(artworkPath)
                        if (artworkFile.exists()) {
                            try {
                                val artwork = ArtworkFactory.createArtworkFromFile(artworkFile)
                                tag.deleteArtworkField()
                                tag.setField(artwork)
                            } catch (e: Exception) {
                                // Fallback if needed
                            }
                        }
                    }

                    AudioFileIO.write(audioFile)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("WRITE_ERROR", "Failed to write tags: ${e.localizedMessage}", e.stackTraceToString())
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
