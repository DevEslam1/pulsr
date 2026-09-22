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
import org.jaudiotagger.tag.flac.FlacTag
import org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag
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
        try {
            backgroundExecutor.awaitTermination(100, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
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
                    var tempFile: java.io.File? = null
                    try {
                        val file = if (path.startsWith("content:")) {
                            val uri = android.net.Uri.parse(path)
                            tempFile = java.io.File.createTempFile("tag_read_", ".tmp", context?.cacheDir)
                            context?.contentResolver?.openInputStream(uri)?.use { input ->
                                tempFile.outputStream().use { output -> input.copyTo(output) }
                            }
                            tempFile
                        } else {
                            File(path)
                        }

                        if (file == null || !file.exists()) {
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
                            var lyrics = tag.getFirst(FieldKey.LYRICS)
                            if (lyrics.isNullOrBlank()) {
                                val vorbisTag: VorbisCommentTag? = when (tag) {
                                    is FlacTag -> tag.vorbisCommentTag
                                    is VorbisCommentTag -> tag
                                    else -> null
                                }
                                if (vorbisTag != null) {
                                    for (key in listOf("SYNCEDLYRICS", "UNSYNCEDLYRICS", "SYNCED LYRICS", "UNSYNCED LYRICS")) {
                                        val v = vorbisTag.getFirst(key)
                                        if (!v.isNullOrBlank()) {
                                            lyrics = v
                                            break
                                        }
                                    }
                                }
                            }
                            tagMap["lyrics"] = lyrics
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
                    } finally {
                        tempFile?.let { runCatching { it.delete() } }
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
                    val isContentUri = path.startsWith("content:")
                    var tempFile: java.io.File? = null
                    var backupFile: java.io.File? = null
                    var verified = false
                    try {
                        val file = if (isContentUri) {
                            val uri = android.net.Uri.parse(path)
                            tempFile = java.io.File.createTempFile("tag_write_", ".tmp", context?.cacheDir)
                            context?.contentResolver?.openInputStream(uri)?.use { input ->
                                tempFile.outputStream().use { output -> input.copyTo(output) }
                            }
                            tempFile
                        } else {
                            File(path)
                        }

                        if (file == null || !file.exists()) {
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
                        if (tags.containsKey("lyrics")) {
                            val lyricsVal = tags["lyrics"]?.toString()
                            if (lyricsVal.isNullOrEmpty()) {
                                runCatching { tag.deleteField(FieldKey.LYRICS) }
                                val vorbisTag = when (tag) {
                                    is FlacTag -> tag.vorbisCommentTag
                                    is VorbisCommentTag -> tag
                                    else -> null
                                }
                                if (vorbisTag != null) {
                                    for (k in listOf("SYNCEDLYRICS", "UNSYNCEDLYRICS", "SYNCED LYRICS", "UNSYNCED LYRICS")) {
                                        runCatching { vorbisTag.deleteField(k) }
                                    }
                                }
                            } else {
                                tag.setField(FieldKey.LYRICS, lyricsVal)
                            }
                        }
                        if (tags.containsKey("comment")) {
                            val commentVal = tags["comment"]?.toString()
                            if (commentVal.isNullOrEmpty()) {
                                runCatching { tag.deleteField(FieldKey.COMMENT) }
                            } else {
                                tag.setField(FieldKey.COMMENT, commentVal)
                            }
                        }

                        // Handle artwork update if provided via bytes or file path
                        val rawArtworkBytes = (tags["artworkBytes"] as? ByteArray)
                            ?: (tags["artworkPath"] as? String)?.let { artPath ->
                                val artFile = File(artPath)
                                if (artFile.exists()) artFile.readBytes() else null
                            }

                        var effectiveArtworkBytes = rawArtworkBytes
                        var effectiveArtworkMime = tags["artworkMimeType"] as? String ?: "image/jpeg"
                        if (effectiveArtworkBytes != null && effectiveArtworkBytes.size > 1024 * 1024) {
                            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(effectiveArtworkBytes, 0, effectiveArtworkBytes.size, options)
                            if (options.outWidth > 0 && options.outHeight > 0) {
                                try {
                                    val bmp = BitmapFactory.decodeByteArray(effectiveArtworkBytes, 0, effectiveArtworkBytes.size)
                                    if (bmp != null) {
                                        var scaled: Bitmap? = null
                                        try {
                                            val maxDim = 500
                                            val origW = bmp.width
                                            val origH = bmp.height
                                            val (targetW, targetH) = if (origW > maxDim || origH > maxDim) {
                                                if (origW >= origH) {
                                                    maxDim to (origH * maxDim / origW).coerceAtLeast(1)
                                                } else {
                                                    (origW * maxDim / origH).coerceAtLeast(1) to maxDim
                                                }
                                            } else {
                                                origW to origH
                                            }
                                            scaled = if (targetW != origW || targetH != origH) {
                                                Bitmap.createScaledBitmap(bmp, targetW, targetH, true)
                                            } else {
                                                bmp
                                            }
                                            val stream = ByteArrayOutputStream()
                                            scaled.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                            effectiveArtworkBytes = stream.toByteArray()
                                            effectiveArtworkMime = "image/jpeg"
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
                                artwork.mimeType = effectiveArtworkMime
                                tag.deleteArtworkField()
                                tag.setField(artwork)
                            } catch (artEx: Exception) {
                                // Non-fatal, continue writing tags
                            }
                        } else if (tags["removeArtwork"] == true) {
                            tag.deleteArtworkField()
                        }

                        // Atomic safety net (defect 24-01): backup the original so an
                        // interrupted write is recoverable instead of corrupting the
                        // user's only copy.
                        backupFile = null
                        if (!isContentUri) {
                            try {
                                val src = File(path)
                                val bak = java.io.File(src.parent, ".${src.name}.pulsr.bak")
                                runCatching { if (bak.exists()) bak.delete() }
                                src.copyTo(bak, overwrite = true)
                                backupFile = bak
                            } catch (_: Exception) {
                                backupFile = null
                            }
                        }

                        try {
                            AudioFileIO.write(audioFile)
                        } catch (writeEx: Exception) {
                            // Restore backup on failed write when possible.
                            try {
                                if (!isContentUri && backupFile != null && backupFile.exists()) {
                                    backupFile.copyTo(File(path), overwrite = true)
                                }
                            } catch (_: Exception) {}
                            throw writeEx
                        }

                        if (isContentUri) {
                            val uri = android.net.Uri.parse(path)
                            context?.contentResolver?.openOutputStream(uri, "rwt")?.use { out ->
                                file.inputStream().use { input -> input.copyTo(out) }
                            }
                        }

                        // Post-write verification: re-read and compare key fields.
                        // Returns a map so Dart can distinguish written-but-unverified
                        // from fully verified (defect 24-03 scoped-storage honesty).
                        verified = false
                        try {
                            val reread = AudioFileIO.read(if (isContentUri) file else File(path))
                            val rtag = reread.tag
                            if (rtag != null) {
                                val expTitle = tags["title"]?.toString()
                                val gotTitle = runCatching { rtag.getFirst(FieldKey.TITLE) }.getOrNull()
                                verified = expTitle.isNullOrEmpty() || gotTitle == expTitle
                            }
                        } catch (_: Exception) {
                            verified = false
                        }

                        // Trigger Android system MediaStore scan so filesystem changes are indexed immediately.
                        // Skip for content:// URIs as they are managed directly by their DocumentProvider.
                        if (!isContentUri) {
                            context?.let { ctx ->
                                try {
                                    MediaScannerConnection.scanFile(ctx, arrayOf(path), null, null)
                                } catch (_: Exception) {}
                            }
                        }

                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.success(mapOf("ok" to true, "verified" to verified))
                        }
                    } catch (e: Exception) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.error("WRITE_TAGS_ERROR", e.message, e.stackTraceToString())
                        }
                    } finally {
                        tempFile?.let { runCatching { it.delete() } }
                        backupFile?.let { backup ->
                            if (verified) {
                                runCatching { backup.delete() }
                            } else {
                                try {
                                    if (!isContentUri && backup.exists()) {
                                        backup.copyTo(File(path), overwrite = true)
                                    }
                                    backup.delete()
                                } catch (_: Exception) {}
                            }
                        }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }
}
