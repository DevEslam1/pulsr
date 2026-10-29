package com.pulsr.music

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * Copies an already-downloaded audio file into the public Music/ collection via
 * MediaStore and returns its final on-disk path. Deliberately free of any
 * external proprietary reference so it can live in src/main and ship in every flavor.
 * Modeled on RingtonePlugin's MediaStore insert.
 */
class YtDownloadPlugin : FlutterPlugin, MethodCallHandler {
    private data class SavedAudio(val path: String, val contentUri: String?)

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private val saveExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/yt_download"

        private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

        fun registerWith(flutterEngine: FlutterEngine, context: Context): YtDownloadPlugin {
            val plugin = YtDownloadPlugin()
            plugin.context = context
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            plugin.installDownloadCallbacks()
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        installDownloadCallbacks()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    /**
     * Wires the DownloadService's process-global callbacks to this plugin's
     * channel. Called on engine attach and again before every
     * startDownloadForeground, because DownloadService.onDestroy clears these
     * statics (C-8) and a later download would otherwise lose its notification
     * controls.
     */
    private fun installDownloadCallbacks() {
        DownloadService.onDownloadCancelledListener = { videoId ->
            invokeOnChannel("onDownloadCancelled", mapOf("videoId" to videoId))
        }
        DownloadService.onDownloadPausedListener = { videoId ->
            invokeOnChannel("onDownloadPaused", mapOf("videoId" to videoId))
        }
        DownloadService.onDownloadResumedListener = { videoId ->
            invokeOnChannel("onDownloadResumed", mapOf("videoId" to videoId))
        }
        DownloadService.onDownloadCompletedListener = { videoId ->
            invokeOnChannel("onDownloadCompleted", mapOf("videoId" to videoId))
        }
        DownloadService.onDownloadDegradedListener = { stage ->
            invokeOnChannel("onDownloadServiceDegraded", mapOf("stage" to stage))
        }
    }

    private fun invokeOnChannel(method: String, arguments: Map<String, Any?>) {
        mainHandler.post {
            if (context == null) return@post
            if (!::channel.isInitialized) return@post
            try {
                channel.invokeMethod(method, arguments)
            } catch (_: Exception) {}
        }
    }

    fun cleanup() {
        DownloadService.onDownloadCancelledListener = null
        DownloadService.onDownloadPausedListener = null
        DownloadService.onDownloadResumedListener = null
        DownloadService.onDownloadCompletedListener = null
        DownloadService.onDownloadDegradedListener = null
        // The Dart engine that owns the transfers is going away with this
        // plugin, so the foreground notification has no writer left. Without
        // this, swiping the task away while a download is running left the
        // process and its stale "downloading" notification alive indefinitely
        // (the service is stopWithTask=false).
        context?.let { ctx ->
            try {
                DownloadService.stop(ctx)
            } catch (_: Exception) {
            }
            // ACTION_STOP can be refused when the app is in the background;
            // stopService always tears the FGS down (and its notification) if
            // it is still running.
            try {
                ctx.stopService(
                    android.content.Intent(ctx, DownloadService::class.java)
                )
            } catch (_: Exception) {
            }
        }
        if (::channel.isInitialized) {
            channel.setMethodCallHandler(null)
        }
        saveExecutor.shutdown()
        try {
            saveExecutor.awaitTermination(100, java.util.concurrent.TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val currentContext = context ?: run {
            result.error("NO_CONTEXT", "Context is null", null)
            return
        }

        when (call.method) {
            "saveToMusic" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val displayName = call.argument<String>("displayName")
                val title = call.argument<String>("title")
                    ?: displayName?.substringBeforeLast('.') ?: "Unknown"
                val mimeType = call.argument<String>("mimeType") ?: "audio/mp4"

                if (sourcePath.isNullOrEmpty() || displayName.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "sourcePath and displayName are required", null)
                    return
                }
                val source = File(sourcePath)
                if (!source.exists()) {
                    result.error("FILE_NOT_FOUND", "Source file not found at $sourcePath", null)
                    return
                }

                // F7: the copy plus the MediaStore insert is a full-file
                // transfer and used to run right here, on the main thread
                // inside `onMethodCall`. On a large file that blocked the UI
                // thread (jank, and an ANR when the file is slow to write), so
                // it moves to a worker and the outcome is delivered back on the
                // platform thread — which is where `result` must be invoked.
                saveExecutor.execute {
                    try {
                        val saved = saveToMediaStore(currentContext, source, displayName, title, mimeType)
                        mainHandler.post {
                            if (saved != null) {
                                result.success(mapOf(
                                    "path" to saved.path,
                                    "contentUri" to saved.contentUri,
                                ))
                            } else {
                                result.error("SAVE_FAILED", "MediaStore did not return a path", null)
                            }
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("SAVE_FAILED", e.localizedMessage ?: "Unknown error", e.stackTraceToString())
                        }
                    }
                }
            }
            "deleteFromMusic" -> {
                val path = call.argument<String>("path")
                val contentUri = call.argument<String>("contentUri")
                if (path.isNullOrEmpty() && contentUri.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "path or contentUri is required", null)
                    return
                }
                saveExecutor.execute {
                    try {
                        val deleted = deleteFromMusic(currentContext, path, contentUri)
                        mainHandler.post { result.success(deleted) }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("DELETE_FAILED", e.localizedMessage ?: "Unknown error", null)
                        }
                    }
                }
            }
            "getFreeDiskSpace" -> {
                // Returns available bytes, or -1L when unknown. Dart callers
                // treat <= 0 as "unknown, don't block" (guarded by `> 0`).
                try {
                    val musicDir = currentContext.getExternalFilesDir(Environment.DIRECTORY_MUSIC)
                        ?: currentContext.filesDir
                    val stat = android.os.StatFs(musicDir.path)
                    val availableBytes = stat.availableBlocksLong * stat.blockSizeLong
                    result.success(availableBytes)
                } catch (e: Exception) {
                    try {
                        val availableBytes = currentContext.filesDir.usableSpace
                        result.success(availableBytes)
                    } catch (e2: Exception) {
                        result.success(-1L)
                    }
                }
            }
            // B-07: Download foreground service lifecycle
            "startDownloadForeground" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val title = call.argument<String>("title") ?: ""
                // DownloadService.onDestroy clears these statics (C-8), so they
                // must be re-installed before every new download.
                installDownloadCallbacks()
                try {
                    DownloadService.start(currentContext, videoId, title)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FGS_START_FAILED", e.message, null)
                }
            }
            "updateDownloadProgress" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val title = call.argument<String>("title") ?: ""
                val progress = (call.argument<Int>("progress") ?: 0).coerceIn(0, 100)
                try {
                    DownloadService.updateProgress(currentContext, videoId, title, progress)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            // C-7: mirror an in-app pause/resume into the download notification.
            "setDownloadPaused" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val paused = call.argument<Boolean>("paused") ?: false
                try {
                    DownloadService.setPaused(currentContext, videoId, paused)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "stopDownloadForeground" -> {
                try {
                    DownloadService.stop(currentContext)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "persistChunkProgress" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val chunkIndex = call.argument<Int>("chunkIndex") ?: 0
                val totalChunks = call.argument<Int>("totalChunks") ?: 1
                val downloadedBytes = call.argument<Number>("downloadedBytes")?.toLong() ?: 0L
                val totalBytes = call.argument<Number>("totalBytes")?.toLong() ?: 0L
                if (videoId.isNotEmpty()) {
                    DownloadChunkStateStore.saveChunkProgress(
                        currentContext, videoId, chunkIndex, totalChunks, downloadedBytes, totalBytes
                    )
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "getPersistedChunkProgress" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                if (videoId.isNotEmpty()) {
                    val chunks = DownloadChunkStateStore.getAllChunksForVideo(currentContext, videoId)
                    val list = chunks.map {
                        mapOf(
                            "videoId" to it.videoId,
                            "chunkIndex" to it.chunkIndex,
                            "totalChunks" to it.totalChunks,
                            "downloadedBytes" to it.downloadedBytes,
                            "totalBytes" to it.totalBytes,
                            "updatedAt" to it.updatedAt,
                        )
                    }
                    result.success(list)
                } else {
                    result.success(emptyList<Map<String, Any>>())
                }
            }
            "clearPersistedChunkProgress" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                if (videoId.isNotEmpty()) {
                    DownloadChunkStateStore.clearChunksForVideo(currentContext, videoId)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Deletes the MediaStore row and the file behind a completed download.
     *
     * Prefers the content URI captured at save time (stable across renamed
     * files and scoped-storage DATA quirks) and falls back to resolving the row
     * by path. The direct file delete remains the last resort for pre-Q rows
     * or files MediaStore never indexed.
     */
    internal fun deleteFromMusic(context: Context, path: String?, contentUri: String?): Boolean {
        var deleted = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            if (!contentUri.isNullOrEmpty()) {
                try {
                    deleted = resolver.delete(Uri.parse(contentUri), null, null) > 0
                } catch (_: Exception) {
                }
            }
            if (!deleted && !path.isNullOrEmpty()) {
                try {
                    @Suppress("DEPRECATION")
                    resolver.query(
                        collection,
                        arrayOf(MediaStore.Audio.Media._ID),
                        "${MediaStore.Audio.Media.DATA} = ?",
                        arrayOf(path),
                        null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val uri = ContentUris.withAppendedId(collection, cursor.getLong(0))
                            deleted = resolver.delete(uri, null, null) > 0
                        }
                    }
                } catch (_: Exception) {
                }
            }
        }
        if (!path.isNullOrEmpty()) {
            try {
                val file = File(path)
                if (file.exists()) deleted = file.delete() || deleted
            } catch (_: Exception) {
            }
        }
        return deleted
    }

    private fun saveToMediaStore(
        context: Context,
        source: File,
        displayName: String,
        title: String,
        mimeType: String,
    ): SavedAudio? {
        val resolver = context.contentResolver

        val lowerMime = mimeType.trim().lowercase()
        val lowerName = displayName.trim().lowercase()

        val cleanDisplayName: String
        val resolvedMimeType: String

        when {
            lowerMime.contains("webm") || lowerName.endsWith(".webm") || lowerName.endsWith(".webm.oga") -> {
                // If it is an Opus stream in WebM container, save with clean .opus extension
                // and audio/opus on Q+ (or .ogg and audio/ogg on pre-Q) so Android MediaProvider does not append .oga
                val base = displayName.replace(Regex("""\.(webm|oga)+$""", RegexOption.IGNORE_CASE), "")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cleanDisplayName = "$base.opus"
                    resolvedMimeType = "audio/opus"
                } else {
                    cleanDisplayName = "$base.ogg"
                    resolvedMimeType = "audio/ogg"
                }
            }
            lowerMime.contains("ogg") || lowerName.endsWith(".ogg") || lowerName.endsWith(".oga") -> {
                val base = displayName.replace(Regex("""\.(ogg|oga)+$""", RegexOption.IGNORE_CASE), "")
                cleanDisplayName = "$base.ogg"
                resolvedMimeType = "audio/ogg"
            }
            lowerMime.contains("mp4") || lowerMime.contains("m4a") || lowerName.endsWith(".m4a") -> {
                cleanDisplayName = displayName
                resolvedMimeType = "audio/mp4"
            }
            else -> {
                cleanDisplayName = displayName
                resolvedMimeType = mimeType
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, cleanDisplayName)
                put(MediaStore.Audio.Media.TITLE, title)
                put(MediaStore.Audio.Media.MIME_TYPE, resolvedMimeType)
                put(MediaStore.Audio.Media.IS_MUSIC, true)
                put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: return null
            var success = false
            try {
                val copied = resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(source).use { input -> input.copyTo(out) }
                    true
                } ?: false
                if (!copied) {
                    return null
                }
                success = true

                // Best-effort clear IS_PENDING
                runCatching {
                    resolver.update(uri, ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }, null, null)
                }

                var path: String? = null
                resolver.query(uri, arrayOf(MediaStore.Audio.Media.DATA), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val idx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                        if (idx >= 0) path = c.getString(idx)
                    }
                }
                if (path.isNullOrEmpty()) {
                    val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                    path = File(musicDir, cleanDisplayName).absolutePath
                }
                val finalPath = path
                    ?: File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), cleanDisplayName).absolutePath
                MediaScannerConnection.scanFile(context, arrayOf(finalPath), arrayOf(resolvedMimeType), null)
                return SavedAudio(finalPath, uri.toString())
            } finally {
                if (!success) {
                    try {
                        resolver.update(uri, ContentValues().apply {
                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                        }, null, null)
                        resolver.delete(uri, null, null)
                    } catch (_: Throwable) {}
                }
            }
        }

        // Pre-Q: write straight into the public Music dir, then index it.
        // Mirrors the Q+ rollback: a failed copy deletes the partial file, and
        // a failed index cleans up its row (and the orphan file) — never leave
        // a partial file or a dangling MediaStore row behind.
        @Suppress("DEPRECATION")
        val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        if (!musicDir.exists()) musicDir.mkdirs()

        var dest = File(musicDir, cleanDisplayName)
        if (dest.exists()) {
            val base = dest.nameWithoutExtension
            val ext = dest.extension
            var i = 1
            while (dest.exists()) {
                dest = File(musicDir, if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext")
                i++
            }
        }
        try {
            FileInputStream(source).use { input ->
                FileOutputStream(dest).use { out -> input.copyTo(out) }
            }
        } catch (e: Exception) {
            try { if (dest.exists()) dest.delete() } catch (_: Exception) {}
            throw e
        }

        var insertedUri: android.net.Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, dest.name)
                put(MediaStore.Audio.Media.TITLE, title)
                put(MediaStore.Audio.Media.MIME_TYPE, resolvedMimeType)
                put(MediaStore.Audio.Media.IS_MUSIC, true)
                @Suppress("DEPRECATION")
                put(MediaStore.Audio.Media.DATA, dest.absolutePath)
            }
            insertedUri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
            if (insertedUri == null) {
                // Index refused the row but the file itself is complete — keep
                // it usable via the scanner rather than deleting user data.
                android.util.Log.w("YtDownloadPlugin", "MediaStore insert returned null; keeping file at ${dest.absolutePath}")
            }
            MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), arrayOf(resolvedMimeType), null)
            return SavedAudio(dest.absolutePath, insertedUri?.toString())
        } catch (e: Exception) {
            android.util.Log.w("YtDownloadPlugin", "MediaStore insert threw; falling back to scanner and preserving file at ${dest.absolutePath}", e)
            try { insertedUri?.let { resolver.delete(it, null, null) } } catch (_: Exception) {}
            MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), arrayOf(resolvedMimeType), null)
            return SavedAudio(dest.absolutePath, null)
        }
    }
}
