package com.pulsr.music

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.images.ArtworkFactory
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.logging.Level
import java.util.logging.Logger

class TagEditorPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private val backgroundExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/tag_editor"

        fun registerWith(flutterEngine: FlutterEngine, context: Context): TagEditorPlugin {
            val plugin = TagEditorPlugin()
            plugin.context = context
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            disableLogger()
            return plugin
        }

        private fun disableLogger() {
            try {
                Logger.getLogger("org.jaudiotagger").level = Level.OFF
            } catch (_: Exception) {}
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        disableLogger()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        if (::channel.isInitialized) {
            channel.setMethodCallHandler(null)
        }
        backgroundExecutor.shutdown()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "readTags" -> {
                val path = call.argument<String>("path")
                val includeArtwork = call.argument<Boolean>("includeArtwork") ?: true
                if (path.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }
                backgroundExecutor.execute {
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                            }
                            return@execute
                        }
                        val audioFile = AudioFileIO.read(file)
                        val tag = audioFile.tag
                        val header = audioFile.audioHeader

                        val tagMap = mutableMapOf<String, Any?>()
                        if (tag != null) {
                            tagMap["title"] = tag.getFirst(FieldKey.TITLE)
                            tagMap["artist"] = tag.getFirst(FieldKey.ARTIST)
                            tagMap["album"] = tag.getFirst(FieldKey.ALBUM)
                            tagMap["albumArtist"] = tag.getFirst(FieldKey.ALBUM_ARTIST)
                            tagMap["genre"] = tag.getFirst(FieldKey.GENRE)
                            tagMap["year"] = tag.getFirst(FieldKey.YEAR)
                            tagMap["trackNumber"] = tag.getFirst(FieldKey.TRACK)
                            tagMap["discNumber"] = tag.getFirst(FieldKey.DISC_NO)
                            tagMap["composer"] = tag.getFirst(FieldKey.COMPOSER)
                            tagMap["lyrics"] = tag.getFirst(FieldKey.LYRICS)
                            tagMap["comment"] = tag.getFirst(FieldKey.COMMENT)

                            if (includeArtwork) {
                                val artwork = tag.firstArtwork
                                if (artwork != null && artwork.binaryData != null) {
                                    tagMap["hasArtwork"] = true
                                    tagMap["artworkBytes"] = artwork.binaryData
                                    tagMap["artworkMimeType"] = artwork.mimeType
                                } else {
                                    tagMap["hasArtwork"] = false
                                }
                            } else {
                                tagMap["hasArtwork"] = tag.firstArtwork != null
                            }
                        }

                        if (header != null) {
                            tagMap["bitRate"] = header.bitRate
                            tagMap["sampleRate"] = header.sampleRate
                            tagMap["format"] = header.format
                            tagMap["channels"] = header.channels
                            tagMap["trackLength"] = header.trackLength
                            tagMap["isLossless"] = header.isLossless
                            // Bit depth is only meaningful for PCM/lossless; lossy
                            // formats report 0 here, which the Dart side treats as
                            // "unknown" and falls back to codec defaults.
                            tagMap["bitsPerSample"] = runCatching { header.bitsPerSample }.getOrDefault(0)
                        }

                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.success(tagMap)
                        }
                    } catch (e: Exception) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.error("READ_TAGS_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                }
            }

            "writeTags" -> {
                val path = call.argument<String>("path")
                val tags: Map<String, Any?>? = call.argument<Map<String, Any?>>("tags") ?: (call.arguments as? Map<String, Any?>)

                if (path.isNullOrEmpty() || tags == null) {
                    result.error("INVALID_ARGUMENT", "File path and tags are required", null)
                    return
                }

                backgroundExecutor.execute {
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                            }
                            return@execute
                        }

                        val audioFile = AudioFileIO.read(file)
                        var tag = audioFile.tag
                        if (tag == null) {
                            tag = audioFile.createDefaultTag()
                            audioFile.tag = tag
                        }

                        tags["title"]?.let { tag.setField(FieldKey.TITLE, it.toString()) }
                        tags["artist"]?.let { tag.setField(FieldKey.ARTIST, it.toString()) }
                        tags["album"]?.let { tag.setField(FieldKey.ALBUM, it.toString()) }
                        tags["albumArtist"]?.let { tag.setField(FieldKey.ALBUM_ARTIST, it.toString()) }
                        tags["genre"]?.let { tag.setField(FieldKey.GENRE, it.toString()) }
                        tags["year"]?.let { tag.setField(FieldKey.YEAR, it.toString()) }
                        tags["trackNumber"]?.let { tag.setField(FieldKey.TRACK, it.toString()) }
                        tags["discNumber"]?.let { tag.setField(FieldKey.DISC_NO, it.toString()) }
                        tags["composer"]?.let { tag.setField(FieldKey.COMPOSER, it.toString()) }
                        tags["lyrics"]?.let { tag.setField(FieldKey.LYRICS, it.toString()) }
                        tags["comment"]?.let { tag.setField(FieldKey.COMMENT, it.toString()) }

                        // Handle artwork update if provided via bytes or file path
                        val rawArtworkBytes = (tags["artworkBytes"] as? ByteArray)
                            ?: (tags["artworkPath"] as? String)?.let { artPath ->
                                val artFile = File(artPath)
                                if (artFile.exists()) artFile.readBytes() else null
                            }

                        var effectiveArtworkBytes = rawArtworkBytes
                        if (effectiveArtworkBytes != null && effectiveArtworkBytes.size > 1024 * 1024) {
                            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(effectiveArtworkBytes, 0, effectiveArtworkBytes.size, options)
                            // Scale down whenever the file exceeds 1 MB — regardless of pixel count.
                            // Previously the condition was `<= 10000000L` which was inverted: it scaled
                            // moderate images (< 10 MP) but let extremely large images through unscaled.
                            if (options.outWidth > 0 && options.outHeight > 0) {
                                try {
                                    val bmp = BitmapFactory.decodeByteArray(effectiveArtworkBytes, 0, effectiveArtworkBytes.size)
                                    if (bmp != null) {
                                        var scaled: Bitmap? = null
                                        try {
                                            scaled = Bitmap.createScaledBitmap(bmp, 500, 500, true)
                                            val stream = ByteArrayOutputStream()
                                            scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                            effectiveArtworkBytes = stream.toByteArray()
                                        } catch (oom: OutOfMemoryError) {
                                            if (rawArtworkBytes.size > 5 * 1024 * 1024) {
                                                throw IllegalArgumentException("Artwork exceeds 5MB limit and cannot be scaled down due to low memory")
                                            }
                                            effectiveArtworkBytes = rawArtworkBytes
                                        } finally {
                                            if (scaled != null && scaled != bmp) {
                                                scaled.recycle()
                                            }
                                            bmp.recycle()
                                        }
                                    }
                                } catch (oom: OutOfMemoryError) {
                                    if (rawArtworkBytes.size > 5 * 1024 * 1024) {
                                        throw IllegalArgumentException("Artwork exceeds 5MB limit and cannot be scaled down due to low memory")
                                    }
                                    effectiveArtworkBytes = rawArtworkBytes
                                } catch (_: Throwable) {
                                    effectiveArtworkBytes = rawArtworkBytes
                                }
                            }
                        }

                        if (effectiveArtworkBytes != null && effectiveArtworkBytes.isNotEmpty()) {
                            try {
                                val artwork = ArtworkFactory.getNew()
                                artwork.binaryData = effectiveArtworkBytes
                                val mime = tags["artworkMimeType"] as? String ?: "image/jpeg"
                                artwork.mimeType = mime
                                tag.deleteArtworkField()
                                tag.setField(artwork)
                            } catch (artEx: Exception) {
                                // Non-fatal, continue writing tags
                            }
                        } else if (tags["removeArtwork"] == true) {
                            tag.deleteArtworkField()
                        }

                        AudioFileIO.write(audioFile)

                        // Trigger Android system MediaStore scan so changes are indexed immediately
                        context?.let { ctx ->
                            try {
                                MediaScannerConnection.scanFile(ctx, arrayOf(path), null, null)
                            } catch (_: Exception) {}
                        }

                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.error("WRITE_TAGS_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
