package com.pulsr.music

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
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
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/yt_download"

        fun registerWith(flutterEngine: FlutterEngine, context: Context): YtDownloadPlugin {
            val plugin = YtDownloadPlugin()
            plugin.context = context
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
    }

    fun cleanup() {
        if (::channel.isInitialized) {
            channel.setMethodCallHandler(null)
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

                try {
                    val finalPath = saveToMediaStore(currentContext, source, displayName, title, mimeType)
                    if (finalPath != null) {
                        result.success(finalPath)
                    } else {
                        result.error("SAVE_FAILED", "MediaStore did not return a path", null)
                    }
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.localizedMessage ?: "Unknown error", e.stackTraceToString())
                }
            }
            "getFreeDiskSpace" -> {
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
            else -> result.notImplemented()
        }
    }

    private fun saveToMediaStore(
        context: Context,
        source: File,
        displayName: String,
        title: String,
        mimeType: String,
    ): String? {
        val resolver = context.contentResolver

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Audio.Media.TITLE, title)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
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

                resolver.update(uri, ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) }, null, null)
                success = true

                var path: String? = null
                resolver.query(uri, arrayOf(MediaStore.Audio.Media.DATA), null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val idx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                        if (idx >= 0) path = c.getString(idx)
                    }
                }
                if (path.isNullOrEmpty()) {
                    val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                    path = File(musicDir, displayName).absolutePath
                }
                if (path != null) {
                    MediaScannerConnection.scanFile(context, arrayOf(path), arrayOf(mimeType), null)
                }
                return path
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
        @Suppress("DEPRECATION")
        val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
        if (!musicDir.exists()) musicDir.mkdirs()

        var dest = File(musicDir, displayName)
        if (dest.exists()) {
            val base = dest.nameWithoutExtension
            val ext = dest.extension
            var i = 1
            while (dest.exists()) {
                dest = File(musicDir, if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext")
                i++
            }
        }
        FileInputStream(source).use { input ->
            FileOutputStream(dest).use { out -> input.copyTo(out) }
        }

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, dest.name)
            put(MediaStore.Audio.Media.TITLE, title)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.Media.IS_MUSIC, true)
            @Suppress("DEPRECATION")
            put(MediaStore.Audio.Media.DATA, dest.absolutePath)
        }
        resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
        MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), arrayOf(mimeType), null)
        return dest.absolutePath
    }
}
