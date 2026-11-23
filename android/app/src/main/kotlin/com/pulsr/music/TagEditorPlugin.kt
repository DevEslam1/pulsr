package com.pulsr.music

import android.app.Activity
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.jaudiotagger.tag.Tag
import org.jaudiotagger.tag.images.ArtworkFactory
import org.jaudiotagger.tag.flac.FlacTag
import org.jaudiotagger.tag.vorbiscomment.VorbisCommentTag
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.logging.Level
import java.util.logging.Logger

class TagEditorPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    internal var context: Context? = null
    internal var writeAudioFile: (org.jaudiotagger.audio.AudioFile) -> Unit = { AudioFileIO.write(it) }
    internal var createWriteRequestIntent: ((ContentResolver, List<Uri>) -> PendingIntent?)? = null
    @Volatile
    private var currentActivity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val writePermissionLock = Any()
    @Volatile
    private var pendingWritePermissionLatch: CountDownLatch? = null
    @Volatile
    private var pendingWritePermissionGranted: Boolean = false
    @Volatile
    private var backgroundExecutor: java.util.concurrent.ExecutorService = newExecutor()
    private val executorLock = Any()
    private val pathLocks = java.util.concurrent.ConcurrentHashMap<String, Any>()

    internal fun attachActivity(activity: Activity) {
        currentActivity = activity
    }

    internal fun detachActivity(activity: Activity) {
        if (currentActivity === activity) {
            currentActivity = null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        currentActivity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        currentActivity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        handleActivityResult(requestCode, resultCode, data)

    internal fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_MEDIA_WRITE) return false
        pendingWritePermissionGranted = (resultCode == Activity.RESULT_OK)
        pendingWritePermissionLatch?.countDown()
        return true
    }

    private fun lockForPath(path: String): Any {
        val key = if (path.startsWith("content:")) {
            path
        } else {
            runCatching { File(path).canonicalPath }.getOrDefault(path)
        }
        return pathLocks.computeIfAbsent(key) { Any() }
    }

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/tag_editor"
        internal const val REQUEST_CODE_MEDIA_WRITE = 41072

        internal fun sniffArtworkMimeType(bytes: ByteArray): String? {
            if (bytes.size >= 3 &&
                bytes[0] == 0xFF.toByte() &&
                bytes[1] == 0xD8.toByte() &&
                bytes[2] == 0xFF.toByte()
            ) {
                return "image/jpeg"
            }
            if (bytes.size >= 8 &&
                bytes[0] == 0x89.toByte() &&
                bytes[1] == 0x50.toByte() &&
                bytes[2] == 0x4E.toByte() &&
                bytes[3] == 0x47.toByte() &&
                bytes[4] == 0x0D.toByte() &&
                bytes[5] == 0x0A.toByte() &&
                bytes[6] == 0x1A.toByte() &&
                bytes[7] == 0x0A.toByte()
            ) {
                return "image/png"
            }
            if (bytes.size >= 12 &&
                bytes[0] == 'R'.code.toByte() &&
                bytes[1] == 'I'.code.toByte() &&
                bytes[2] == 'F'.code.toByte() &&
                bytes[3] == 'F'.code.toByte() &&
                bytes[8] == 'W'.code.toByte() &&
                bytes[9] == 'E'.code.toByte() &&
                bytes[10] == 'B'.code.toByte() &&
                bytes[11] == 'P'.code.toByte()
            ) {
                return "image/webp"
            }
            if (bytes.size >= 6 &&
                bytes[0] == 'G'.code.toByte() &&
                bytes[1] == 'I'.code.toByte() &&
                bytes[2] == 'F'.code.toByte() &&
                bytes[3] == '8'.code.toByte() &&
                (bytes[4] == '7'.code.toByte() || bytes[4] == '9'.code.toByte()) &&
                bytes[5] == 'a'.code.toByte()
            ) {
                return "image/gif"
            }
            if (bytes.size >= 2 &&
                bytes[0] == 'B'.code.toByte() &&
                bytes[1] == 'M'.code.toByte()
            ) {
                return "image/bmp"
            }
            return null
        }

        private fun newExecutor(): java.util.concurrent.ExecutorService =
            java.util.concurrent.Executors.newFixedThreadPool(2) { r ->
                Thread(r, "PulsrTagEditor").apply { isDaemon = true }
            }

        fun registerWith(flutterEngine: FlutterEngine, context: Context): TagEditorPlugin {
            val plugin = TagEditorPlugin()
            plugin.context = context
            plugin.ensureExecutor()
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

        internal data class TagVerificationOutcome(
            val verified: Boolean,
            val verifiedFields: Map<String, Boolean>,
        )

        private val TEXT_FIELD_KEYS: List<Pair<String, FieldKey>> = listOf(
            "title" to FieldKey.TITLE,
            "artist" to FieldKey.ARTIST,
            "album" to FieldKey.ALBUM,
            "albumArtist" to FieldKey.ALBUM_ARTIST,
            "genre" to FieldKey.GENRE,
            "year" to FieldKey.YEAR,
            "trackNumber" to FieldKey.TRACK,
            "discNumber" to FieldKey.DISC_NO,
            "composer" to FieldKey.COMPOSER,
        )

        private val VORBIS_LYRICS_FALLBACK_KEYS = listOf(
            "SYNCEDLYRICS",
            "UNSYNCEDLYRICS",
            "SYNCED LYRICS",
            "UNSYNCED LYRICS",
        )

        private val VERIFIABLE_TEXT_FIELDS =
            TEXT_FIELD_KEYS.map { it.first } + listOf("lyrics", "comment")

        private fun normalizeSlashInt(raw: String): String {
            val parts = raw.split('/')
            if (parts.size > 2) return raw.trim()
            val normalized = parts.map { part ->
                val trimmed = part.trim()
                trimmed.toIntOrNull()?.toString() ?: trimmed
            }
            return normalized.joinToString("/")
        }

        private fun tagFieldMatches(field: String, expected: String, actual: String?): Boolean {
            if (expected.isEmpty()) return actual.isNullOrBlank()
            if (actual == null) return false
            if (actual == expected) return true
            return when (field) {
                "trackNumber", "discNumber" -> normalizeSlashInt(expected) == normalizeSlashInt(actual)
                "year" -> {
                    val expTrim = expected.trim()
                    val actTrim = actual.trim()
                    val expInt = expTrim.toIntOrNull()?.toString() ?: expTrim
                    val actInt = actTrim.toIntOrNull()?.toString() ?: actTrim
                    expInt == actInt ||
                        (expInt.length == 4 && actTrim.startsWith("$expInt-")) ||
                        (actInt.length == 4 && expTrim.startsWith("$actInt-"))
                }
                else -> false
            }
        }

        internal fun verifyWrittenTags(
            requestedTags: Map<String, Any?>,
            rereadTags: Map<String, Any?>?,
        ): TagVerificationOutcome {
            if (rereadTags == null) {
                return TagVerificationOutcome(verified = false, verifiedFields = emptyMap())
            }
            val verifiedFields = mutableMapOf<String, Boolean>()
            for (field in VERIFIABLE_TEXT_FIELDS) {
                val provided = when (field) {
                    "lyrics", "comment" -> requestedTags.containsKey(field)
                    else -> requestedTags[field] != null
                }
                if (!provided) continue
                val expected = requestedTags[field]?.toString() ?: ""
                val actual = rereadTags[field]?.toString()
                verifiedFields[field] = tagFieldMatches(field, expected, actual)
            }
            val hasArtworkWrite =
                ((requestedTags["artworkBytes"] as? ByteArray)?.isNotEmpty() == true) ||
                    ((requestedTags["artworkPath"] as? String)?.isNotEmpty() == true)
            val artworkPresent = (rereadTags["hasArtwork"] as? Boolean)
                ?: (rereadTags["artwork"] as? Boolean)
                ?: ((rereadTags["artworkBytes"] as? ByteArray)?.isNotEmpty() == true)
            if (hasArtworkWrite) {
                verifiedFields["artwork"] = artworkPresent
            } else if (requestedTags["removeArtwork"] == true) {
                verifiedFields["artwork"] = !artworkPresent
            }
            return TagVerificationOutcome(
                verified = verifiedFields.values.all { it },
                verifiedFields = verifiedFields,
            )
        }

        private fun readLyricsFromTag(tag: Tag): String? {
            var lyrics = runCatching { tag.getFirst(FieldKey.LYRICS) }.getOrNull()
            if (lyrics.isNullOrBlank()) {
                val vorbisTag: VorbisCommentTag? = when (tag) {
                    is FlacTag -> tag.vorbisCommentTag
                    is VorbisCommentTag -> tag
                    else -> null
                }
                if (vorbisTag != null) {
                    for (key in VORBIS_LYRICS_FALLBACK_KEYS) {
                        val v = runCatching { vorbisTag.getFirst(key) }.getOrNull()
                        if (!v.isNullOrBlank()) {
                            lyrics = v
                            break
                        }
                    }
                }
            }
            return lyrics
        }

        private fun readCanonicalTagFields(tag: Tag): MutableMap<String, Any?> {
            val map = mutableMapOf<String, Any?>()
            for ((key, fieldKey) in TEXT_FIELD_KEYS) {
                map[key] = runCatching { tag.getFirst(fieldKey) }.getOrNull()
            }
            map["lyrics"] = readLyricsFromTag(tag)
            map["comment"] = runCatching { tag.getFirst(FieldKey.COMMENT) }.getOrNull()
            val artwork = runCatching { tag.firstArtwork }.getOrNull()
            map["hasArtwork"] =
                artwork != null && artwork.binaryData != null && artwork.binaryData.isNotEmpty()
            return map
        }
    }

    private fun ensureExecutor(): java.util.concurrent.ExecutorService {
        val current = backgroundExecutor
        if (!current.isShutdown) return current
        synchronized(executorLock) {
            if (backgroundExecutor.isShutdown) {
                backgroundExecutor = newExecutor()
            }
            return backgroundExecutor
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        ensureExecutor()
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
        val currentExecutor = backgroundExecutor
        currentExecutor.shutdown()
        try {
            currentExecutor.awaitTermination(100, java.util.concurrent.TimeUnit.MILLISECONDS)
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
                ensureExecutor().execute {
                    synchronized(lockForPath(path)) {
                    var tempFile: java.io.File? = null
                    try {
                        val file = if (path.startsWith("content:")) {
                            val uri = android.net.Uri.parse(path)
                            val ctx = context ?: throw java.io.IOException("Context unavailable")
                            tempFile = AudioTempFiles.copyToTempFile(ctx, uri, "tag_read_")
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
                        val tagMap = mutableMapOf<String, Any?>()
                        try {
                            val audioFile = AudioFileIO.read(file)
                            val tag = audioFile.tag
                            val header = audioFile.audioHeader

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
                                tagMap["lyrics"] = readLyricsFromTag(tag)
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
                        } catch (_: Exception) {
                            // Jaudiotagger does not support WebM, Opus in some containers, etc.
                        }

                        // Fallback & supplement using Android's native MediaMetadataRetriever and MediaExtractor
                        supplementWithMediaRetriever(file, includeArtwork, tagMap)
                        supplementWithMediaExtractor(file, tagMap)

                        // For Opus or WebM files where sampleRate is still missing/0, default to Opus specification 48kHz
                        val nameLower = file.name.lowercase()
                        val formatStr = (tagMap["format"] as? String)?.lowercase() ?: ""
                        val isOpus = nameLower.endsWith(".opus") || nameLower.contains(".webm") ||
                                nameLower.endsWith(".oga") || formatStr.contains("opus")
                        if (isOpus) {
                            val sr = (tagMap["sampleRate"] as? String)?.toIntOrNull() ?: 0
                            if (sr <= 0) {
                                tagMap["sampleRate"] = "48000"
                            }
                            if (tagMap["format"] == null || formatStr.isEmpty()) {
                                tagMap["format"] = "OPUS"
                            }
                            if (tagMap["channels"] == null) {
                                tagMap["channels"] = "2"
                            }
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
            }

            "writeTags" -> {
                val path = call.argument<String>("path")
                val tags: Map<String, Any?>? = call.argument<Map<String, Any?>>("tags") ?: (call.arguments as? Map<String, Any?>)

                if (path.isNullOrEmpty() || tags == null) {
                    result.error("INVALID_ARGUMENT", "File path and tags are required", null)
                    return
                }

                ensureExecutor().execute {
                    synchronized(lockForPath(path)) {
                    val isContentUri = path.startsWith("content:")
                    var tempFile: java.io.File? = null
                    var backupFile: java.io.File? = null
                    var verified = false
                    try {
                        val file = if (isContentUri) {
                            val uri = android.net.Uri.parse(path)
                            val ctx = context ?: throw java.io.IOException("Context unavailable")
                            tempFile = AudioTempFiles.copyToTempFile(ctx, uri, "tag_write_")
                            // Preserve the original bytes before jaudiotagger
                            // touches anything, so a failed write-back can be
                            // rolled back without touching user storage again.
                            backupFile = java.io.File.createTempFile(
                                "tag_backup_",
                                tempFile.name.substringAfterLast('.', "tmp").let { ".$it" },
                                ctx.cacheDir
                            )
                            tempFile.copyTo(backupFile, overwrite = true)
                            tempFile
                        } else {
                            File(path)
                        }

                        if (file == null || !file.exists()) {
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
                                result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                            }
                            return@synchronized
                        }

                        val audioFile = AudioFileIO.read(file)
                        var tag = audioFile.tag
                        if (tag == null) {
                            tag = audioFile.createDefaultTag()
                            audioFile.tag = tag
                        }

                        for ((key, fieldKey) in TEXT_FIELD_KEYS) {
                            val raw = tags[key] ?: continue
                            val str = raw.toString()
                            if (str.isEmpty()) {
                                runCatching { tag.deleteField(fieldKey) }
                            } else {
                                tag.setField(fieldKey, str)
                            }
                        }
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
                                    for (k in VORBIS_LYRICS_FALLBACK_KEYS) {
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

                        // Handle artwork update if provided via bytes or file path.
                        // Record artwork errors instead of silently ignoring them:
                        // - artwork-only requests throw WRITE_TAGS_ERROR;
                        // - mixed text+artwork requests preserve text edits, mark
                        //   verified=false / verifiedFields["artwork"]=false, and surface artworkError.
                        var artworkError: String? = null
                        val hasNonArtworkTags = tags.keys.any {
                            it !in setOf("artworkPath", "artworkBytes", "artworkMimeType", "removeArtwork")
                        }
                        val artworkPathArg = tags["artworkPath"] as? String
                        val rawArtworkBytes = (tags["artworkBytes"] as? ByteArray)
                            ?: artworkPathArg?.takeIf { it.isNotBlank() }?.let { artPath ->
                                val artFile = File(artPath)
                                if (!artFile.exists()) {
                                    artworkError = "Artwork file not found at $artPath"
                                    null
                                } else {
                                    runCatching { artFile.readBytes() }.onFailure { readEx ->
                                        artworkError = "Failed to read artwork at $artPath: ${readEx.message ?: readEx.javaClass.simpleName}"
                                    }.getOrNull()
                                }
                            }

                        var effectiveArtworkBytes = rawArtworkBytes
                        val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        if (rawArtworkBytes != null && rawArtworkBytes.isNotEmpty()) {
                            runCatching {
                                BitmapFactory.decodeByteArray(rawArtworkBytes, 0, rawArtworkBytes.size, boundsOptions)
                            }
                        }
                        var effectiveArtworkMime = rawArtworkBytes?.let { sniffArtworkMimeType(it) }
                            ?: boundsOptions.outMimeType?.takeIf { it.isNotBlank() }
                            ?: (tags["artworkMimeType"] as? String)?.takeIf { it.isNotBlank() }
                            ?: "image/jpeg"
                        if (effectiveArtworkBytes != null && effectiveArtworkBytes.size > 1024 * 1024) {
                            if (boundsOptions.outWidth > 0 && boundsOptions.outHeight > 0) {
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
                                                artworkError = "Artwork exceeds 5MB limit and cannot be scaled down due to low memory"
                                                effectiveArtworkBytes = null
                                            } else {
                                                effectiveArtworkBytes = rawArtworkBytes
                                            }
                                        } finally {
                                            if (scaled != null && scaled != bmp) {
                                                scaled.recycle()
                                            }
                                            bmp.recycle()
                                        }
                                    }
                                } catch (oom: OutOfMemoryError) {
                                    if (rawArtworkBytes.size > 5 * 1024 * 1024) {
                                        artworkError = "Artwork exceeds 5MB limit and cannot be scaled down due to low memory"
                                        effectiveArtworkBytes = null
                                    } else {
                                        effectiveArtworkBytes = rawArtworkBytes
                                    }
                                } catch (t: Throwable) {
                                    if (rawArtworkBytes.size > 5 * 1024 * 1024) {
                                        artworkError = "Failed to scale oversized artwork: ${t.message}"
                                        effectiveArtworkBytes = null
                                    } else {
                                        effectiveArtworkBytes = rawArtworkBytes
                                    }
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
                                artworkError = "Failed to embed artwork ($effectiveArtworkMime): ${artEx.message ?: artEx.javaClass.simpleName}"
                            }
                        } else if (tags["removeArtwork"] == true) {
                            tag.deleteArtworkField()
                        }
                        if (artworkError != null && !hasNonArtworkTags) {
                            throw java.io.IOException(artworkError)
                        }

                        // Atomic safety net (defect 24-01): backup the original in ctx.cacheDir
                        // (Android 11+ scoped storage rejects backup files created next to shared audio).
                        // Abort before touching storage if backup fails.
                        if (!isContentUri) {
                            backupFile = null
                            var pendingBackup: java.io.File? = null
                            try {
                                val src = File(path)
                                val backupDir = context?.cacheDir ?: src.parentFile
                                val suffix = src.extension.takeIf { it.isNotBlank() }?.let { ".$it.bak" } ?: ".pulsr.bak"
                                val bak = if (backupDir != null) {
                                    java.io.File.createTempFile("tag_backup_", suffix, backupDir)
                                } else {
                                    java.io.File(src.parent, ".${src.name.take(200)}.pulsr.bak")
                                }
                                pendingBackup = bak
                                src.copyTo(bak, overwrite = true)
                                if (!bak.exists() || bak.length() != src.length()) {
                                    throw java.io.IOException("Backup integrity check failed for $path")
                                }
                                backupFile = bak
                            } catch (bakEx: Exception) {
                                pendingBackup?.let { runCatching { it.delete() } }
                                backupFile = null
                                android.os.Handler(android.os.Looper.getMainLooper()).post {
                                    result.error(
                                        "BACKUP_FAILED",
                                        bakEx.message ?: "Failed to create backup before tag write",
                                        bakEx.stackTraceToString(),
                                    )
                                }
                                return@execute
                            }
                        }

                        writeAudioFileWithRecovery(
                            ctx = context,
                            path = path,
                            isContentUri = isContentUri,
                            workingFile = file,
                            audioFile = audioFile,
                        )

                        if (isContentUri) {
                            if (file.length() <= 0L) {
                                throw java.io.IOException("Tagged temp file is empty for $path")
                            }
                            val uri = android.net.Uri.parse(path)
                            val ctx = context ?: throw java.io.IOException("Context unavailable for $uri")
                            writeFileToContentUriWithRecovery(ctx, uri, file)
                            val writtenTemp = AudioTempFiles.copyToTempFile(ctx, uri, "tag_check_")
                            try {
                                if (writtenTemp.length() <= 0L) {
                                    throw java.io.IOException("Write-back to $uri produced an empty file")
                                }
                            } finally {
                                runCatching { writtenTemp.delete() }
                            }
                        }

                        // Post-write verification: re-read and compare every provided field.
                        // Returns a map so Dart can distinguish written-but-unverified
                        // from fully verified (defect 24-03 scoped-storage honesty, B-05).
                        var verifiedFields: Map<String, Boolean> = emptyMap()
                        verified = false
                        var verifyTempFile: File? = null
                        try {
                            val fileToVerify = if (isContentUri) {
                                val uri = android.net.Uri.parse(path)
                                val ctx = context
                                    ?: throw java.io.IOException("Context unavailable for $uri")
                                val vTemp = AudioTempFiles.copyToTempFile(ctx, uri, "pulsr_verify_")
                                verifyTempFile = vTemp
                                if (vTemp.length() <= 0L) {
                                    throw java.io.IOException("Verification copy of $uri is empty")
                                }
                                vTemp
                            } else {
                                File(path)
                            }
                            val reread = AudioFileIO.read(fileToVerify)
                            val rtag = reread.tag
                            val rereadMap = rtag?.let { readCanonicalTagFields(it) }
                            val outcome = verifyWrittenTags(tags, rereadMap)
                            if (artworkError != null) {
                                val updatedFields = outcome.verifiedFields.toMutableMap()
                                updatedFields["artwork"] = false
                                verifiedFields = updatedFields
                                verified = false
                            } else {
                                verifiedFields = outcome.verifiedFields
                                verified = outcome.verified
                            }
                        } catch (_: Exception) {
                            verified = false
                        } finally {
                            verifyTempFile?.let { runCatching { it.delete() } }
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

                        val backupCreated = backupFile?.exists() == true
                        val responseMap = mutableMapOf<String, Any?>(
                            "ok" to true,
                            "verified" to verified,
                            "verifiedFields" to verifiedFields,
                            "backupCreated" to backupCreated,
                        )
                        if (artworkError != null) {
                            responseMap["artworkError"] = artworkError
                        }
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.success(responseMap)
                        }
                    } catch (e: Exception) {
                        backupFile?.let { backup ->
                            if (backup.exists()) {
                                if (isContentUri) {
                                    restoreContentUri(android.net.Uri.parse(path), backup)
                                } else {
                                    runCatching { backup.copyTo(File(path), overwrite = true) }
                                }
                            }
                        }
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            result.error("WRITE_TAGS_ERROR", e.message, e.stackTraceToString())
                        }
                    } finally {
                        tempFile?.let { runCatching { it.delete() } }
                        backupFile?.let { runCatching { it.delete() } }
                    }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun isPermissionFailure(t: Throwable): Boolean {
        var cur: Throwable? = t
        while (cur != null) {
            if (cur is SecurityException) return true
            val msg = cur.message?.lowercase().orEmpty()
            if (msg.contains("permission") || msg.contains("eacces") || msg.contains("eperm")) {
                return true
            }
            cur = cur.cause
        }
        return false
    }

    @Suppress("DEPRECATION")
    private fun resolveMediaStoreUri(ctx: Context, filePath: String): Uri? {
        val candidates = linkedSetOf(filePath)
        runCatching { File(filePath).canonicalPath }.getOrNull()?.let { candidates.add(it) }
        val cr = ctx.contentResolver
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DATA}=?"
        for (candidate in candidates) {
            runCatching {
                cr.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    selection,
                    arrayOf(candidate),
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val id = cursor.getLong(0)
                        return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                    }
                }
            }
        }
        return null
    }

    private fun requestWritePermissionSync(
        ctx: Context,
        uris: List<Uri>,
        fallbackRecoverable: Throwable? = null,
    ): Boolean {
        if (uris.isEmpty()) return false
        val activity = currentActivity ?: return false
        val pendingIntent: PendingIntent = createWriteRequestIntent?.invoke(ctx.contentResolver, uris)
            ?: when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                    runCatching { MediaStore.createWriteRequest(ctx.contentResolver, uris) }.getOrNull()
                        ?: (fallbackRecoverable as? RecoverableSecurityException)?.userAction?.actionIntent
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                    (fallbackRecoverable as? RecoverableSecurityException)?.userAction?.actionIntent
                }
                else -> null
            } ?: return false

        synchronized(writePermissionLock) {
            val latch = CountDownLatch(1)
            pendingWritePermissionGranted = false
            pendingWritePermissionLatch = latch
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    activity.startIntentSenderForResult(
                        pendingIntent.intentSender,
                        REQUEST_CODE_MEDIA_WRITE,
                        null,
                        0,
                        0,
                        0,
                    )
                } catch (_: Throwable) {
                    latch.countDown()
                }
            }
            try {
                latch.await(60, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            } finally {
                if (pendingWritePermissionLatch === latch) {
                    pendingWritePermissionLatch = null
                }
            }
            return pendingWritePermissionGranted
        }
    }

    private fun writeFileToContentUriWithRecovery(ctx: Context, uri: Uri, sourceFile: File) {
        val cr = ctx.contentResolver
        fun writeOnce() {
            val pfd = cr.openFileDescriptor(uri, "rwt")
                ?: throw java.io.IOException("Failed to open file descriptor for $uri")
            pfd.use { descriptor ->
                java.io.FileOutputStream(descriptor.fileDescriptor).use { out ->
                    sourceFile.inputStream().use { input -> input.copyTo(out) }
                }
            }
        }
        try {
            writeOnce()
        } catch (secEx: SecurityException) {
            if (requestWritePermissionSync(ctx, listOf(uri), secEx)) {
                writeOnce()
            } else {
                throw SecurityException("Permission denied writing $uri: ${secEx.message}", secEx)
            }
        }
    }

    private fun writeAudioFileWithRecovery(
        ctx: Context?,
        path: String,
        isContentUri: Boolean,
        workingFile: File,
        audioFile: org.jaudiotagger.audio.AudioFile,
    ) {
        try {
            writeAudioFile(audioFile)
        } catch (ex: Exception) {
            if (isContentUri || ctx == null || !isPermissionFailure(ex)) {
                throw ex
            }
            val mediaUri = resolveMediaStoreUri(ctx, path) ?: throw ex
            val granted = requestWritePermissionSync(ctx, listOf(mediaUri), ex)
            if (!granted) {
                throw SecurityException("Permission denied writing $path: ${ex.message}", ex)
            }
            try {
                writeAudioFile(audioFile)
            } catch (directRetryEx: Exception) {
                if (!isPermissionFailure(directRetryEx)) throw directRetryEx
                // Fallback on Android 11+ FUSE if POSIX path stays restricted even after grant:
                // write tagged audio to a cache copy and flush it through the granted MediaStore URI.
                val suffix = workingFile.extension.takeIf { it.isNotBlank() }?.let { ".$it" } ?: ".tmp"
                val cacheTemp = File.createTempFile("tag_staged_", suffix, ctx.cacheDir)
                try {
                    workingFile.copyTo(cacheTemp, overwrite = true)
                    val stagedAudio = AudioFileIO.read(cacheTemp)
                    stagedAudio.tag = audioFile.tag
                    writeAudioFile(stagedAudio)
                    writeFileToContentUriWithRecovery(ctx, mediaUri, cacheTemp)
                } finally {
                    runCatching { cacheTemp.delete() }
                }
            }
        }
    }

    private fun restoreContentUri(uri: android.net.Uri, backup: File?) {
        val ctx = context ?: return
        if (backup == null || !backup.exists()) return
        for (mode in listOf("rwt", "rw")) {
            val attempt = runCatching {
                val out = ctx.contentResolver.openOutputStream(uri, mode)
                    ?: throw java.io.IOException("openOutputStream($uri, $mode) returned null")
                out.use { stream ->
                    backup.inputStream().use { input -> input.copyTo(stream) }
                }
            }
            if (attempt.isSuccess) {
                if (mode != "rwt") {
                    android.util.Log.i("TagEditorPlugin", "Restored $uri from backup using fallback mode '$mode'")
                }
                return
            }
            android.util.Log.w(
                "TagEditorPlugin",
                "Failed to restore $uri from backup (mode='$mode'): ${attempt.exceptionOrNull()?.message}",
            )
        }
    }

    private fun supplementWithMediaRetriever(
        file: File,
        includeArtwork: Boolean,
        tagMap: MutableMap<String, Any?>
    ) {
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(file.absolutePath)

            fun putIfMissing(key: String, retrieverKey: Int) {
                val current = tagMap[key]
                if (current == null || (current is String && current.isBlank())) {
                    val value = retriever.extractMetadata(retrieverKey)
                    if (!value.isNullOrBlank()) tagMap[key] = value
                }
            }

            putIfMissing("title", MediaMetadataRetriever.METADATA_KEY_TITLE)
            putIfMissing("artist", MediaMetadataRetriever.METADATA_KEY_ARTIST)
            putIfMissing("album", MediaMetadataRetriever.METADATA_KEY_ALBUM)
            putIfMissing("albumArtist", MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
            putIfMissing("genre", MediaMetadataRetriever.METADATA_KEY_GENRE)
            putIfMissing("year", MediaMetadataRetriever.METADATA_KEY_YEAR)
            putIfMissing("trackNumber", MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)
            putIfMissing("composer", MediaMetadataRetriever.METADATA_KEY_COMPOSER)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val curSr = (tagMap["sampleRate"] as? String)?.toIntOrNull() ?: 0
                if (curSr <= 0) {
                    val srStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)
                    val sr = srStr?.toIntOrNull() ?: 0
                    if (sr > 0) tagMap["sampleRate"] = sr.toString()
                }
            }

            val curBr = (tagMap["bitRate"] as? String)?.toIntOrNull() ?: 0
            if (curBr <= 0) {
                val brStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                val br = brStr?.toIntOrNull() ?: 0
                if (br > 0) tagMap["bitRate"] = (br / 1000).toString()
            }

            val curLen = tagMap["trackLength"] as? Int ?: 0
            if (curLen <= 0) {
                val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durMs = durStr?.toLongOrNull() ?: 0L
                if (durMs > 0) tagMap["trackLength"] = (durMs / 1000).toInt()
            }

            val curMime = tagMap["format"] as? String
            if (curMime.isNullOrBlank()) {
                val mime = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                if (!mime.isNullOrBlank()) {
                    tagMap["format"] = when {
                        mime.contains("opus", ignoreCase = true) -> "OPUS"
                        mime.contains("vorbis", ignoreCase = true) || mime.contains("ogg", ignoreCase = true) -> "OGG"
                        mime.contains("mp4a", ignoreCase = true) || mime.contains("aac", ignoreCase = true) -> "AAC"
                        mime.contains("mpeg", ignoreCase = true) || mime.contains("mp3", ignoreCase = true) -> "MP3"
                        mime.contains("flac", ignoreCase = true) -> "FLAC"
                        mime.contains("wav", ignoreCase = true) -> "WAV"
                        else -> mime.removePrefix("audio/").uppercase()
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val curBits = tagMap["bitsPerSample"] as? Int ?: 0
                if (curBits <= 0) {
                    val bitsStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE)
                    val bits = bitsStr?.toIntOrNull() ?: 0
                    if (bits > 0) tagMap["bitsPerSample"] = bits
                }
            }

            if (includeArtwork && tagMap["artworkBytes"] == null) {
                val pic = retriever.embeddedPicture
                if (pic != null && pic.isNotEmpty()) {
                    tagMap["hasArtwork"] = true
                    tagMap["artworkBytes"] = pic
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {}
        }
    }

    private fun supplementWithMediaExtractor(
        file: File,
        tagMap: MutableMap<String, Any?>
    ) {
        var extractor: MediaExtractor? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(file.absolutePath)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    val curSr = (tagMap["sampleRate"] as? String)?.toIntOrNull() ?: 0
                    if (curSr <= 0 && format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        val sr = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        if (sr > 0) tagMap["sampleRate"] = sr.toString()
                    }
                    if (tagMap["channels"] == null && format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        val ch = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (ch > 0) tagMap["channels"] = ch.toString()
                    }
                    val curBr = (tagMap["bitRate"] as? String)?.toIntOrNull() ?: 0
                    if (curBr <= 0 && format.containsKey(MediaFormat.KEY_BIT_RATE)) {
                        val br = format.getInteger(MediaFormat.KEY_BIT_RATE)
                        if (br > 0) tagMap["bitRate"] = (br / 1000).toString()
                    }
                    val curFormat = tagMap["format"] as? String
                    if (curFormat.isNullOrBlank()) {
                        tagMap["format"] = when {
                            mime.contains("opus", ignoreCase = true) -> "OPUS"
                            mime.contains("vorbis", ignoreCase = true) || mime.contains("ogg", ignoreCase = true) -> "OGG"
                            mime.contains("mp4a", ignoreCase = true) || mime.contains("aac", ignoreCase = true) -> "AAC"
                            mime.contains("mpeg", ignoreCase = true) || mime.contains("mp3", ignoreCase = true) -> "MP3"
                            mime.contains("flac", ignoreCase = true) -> "FLAC"
                            mime.contains("wav", ignoreCase = true) -> "WAV"
                            else -> mime.removePrefix("audio/").uppercase()
                        }
                    }
                    break
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                extractor?.release()
            } catch (_: Exception) {}
        }
    }
}
