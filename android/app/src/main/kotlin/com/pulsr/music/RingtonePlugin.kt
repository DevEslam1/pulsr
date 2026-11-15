package com.pulsr.music

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileInputStream

class RingtonePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    @Volatile
    private var executor: java.util.concurrent.ExecutorService = newExecutor()
    private val executorLock = Any()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/ringtone"
        private const val MAX_RINGTONE_BYTES = 100L * 1024 * 1024

        private fun newExecutor(): java.util.concurrent.ExecutorService =
            java.util.concurrent.Executors.newSingleThreadExecutor { r ->
                Thread(r, "PulsrRingtone").apply { isDaemon = true }
            }

        fun registerWith(flutterEngine: FlutterEngine, context: Context): RingtonePlugin {
            val plugin = RingtonePlugin()
            plugin.context = context
            plugin.ensureExecutor()
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    private fun ensureExecutor(): java.util.concurrent.ExecutorService {
        val current = executor
        if (!current.isShutdown) return current
        synchronized(executorLock) {
            if (executor.isShutdown) {
                executor = newExecutor()
            }
            return executor
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        ensureExecutor()
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
        executor.shutdownNow()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val currentContext = context ?: run {
            result.error("NO_CONTEXT", "Context is null", null)
            return
        }

        when (call.method) {
            "checkWriteSettingsPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    result.success(Settings.System.canWrite(currentContext))
                } else {
                    result.success(true)
                }
            }
            "openWriteSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                            data = Uri.parse("package:" + currentContext.packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        currentContext.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANNOT_OPEN_SETTINGS", e.message, null)
                    }
                } else {
                    result.success(true)
                }
            }
            "setRingtone" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(currentContext)) {
                    result.error("PERMISSION_DENIED", "WRITE_SETTINGS permission is required", null)
                    return
                }

                val filePath = call.argument<String>("filePath")
                val typeStr = call.argument<String>("type") ?: "ringtone"

                if (filePath.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "File path is required", null)
                    return
                }

                val ringtoneType = when (typeStr.lowercase()) {
                    "notification" -> RingtoneManager.TYPE_NOTIFICATION
                    "alarm" -> RingtoneManager.TYPE_ALARM
                    else -> RingtoneManager.TYPE_RINGTONE
                }

                // Copy + MediaStore insert are full-file disk operations; they
                // must not run on the platform thread.
                try {
                    ensureExecutor().execute {
                        var tempFile: File? = null
                        try {
                            var displayName: String? = null
                            var sourceMime: String? = null
                            val file: File? = if (filePath.startsWith("content:")) {
                                val uri = Uri.parse(filePath)
                                displayName = runCatching {
                                    AudioTempFiles.displayName(currentContext, uri)
                                }.getOrNull()
                                sourceMime = runCatching {
                                    currentContext.contentResolver.getType(uri)
                                }.getOrNull()
                                tempFile = AudioTempFiles.copyToTempFile(
                                    currentContext,
                                    uri,
                                    "ringtone_",
                                    maxBytes = MAX_RINGTONE_BYTES,
                                )
                                tempFile
                            } else {
                                File(filePath)
                            }

                            if (file == null || !file.exists()) {
                                mainHandler.post {
                                    result.error("FILE_NOT_FOUND", "Audio file not found at $filePath", null)
                                }
                                return@execute
                            }
                            val name = sanitizeDisplayName(
                                displayName?.takeIf { it.isNotBlank() } ?: file.name
                            )
                            val mime = normalizeMime(sourceMime, name)

                            val contentUri = getAudioContentUri(
                                currentContext, file, ringtoneType, name, mime
                            )
                            if (contentUri == null) {
                                mainHandler.post {
                                    result.error("URI_ERROR", "Failed to resolve MediaStore Uri for file", null)
                                }
                                return@execute
                            }
                            RingtoneManager.setActualDefaultRingtoneUri(currentContext, ringtoneType, contentUri)
                            mainHandler.post { result.success(true) }
                        } catch (e: AudioTempFiles.TempFileSizeLimitException) {
                            mainHandler.post {
                                result.error(
                                    "FILE_TOO_LARGE",
                                    "Audio file exceeds maximum ringtone size (100 MB)",
                                    null
                                )
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "SET_RINGTONE_FAILED",
                                    e.localizedMessage ?: "Unknown error",
                                    e.stackTraceToString()
                                )
                            }
                        } finally {
                            tempFile?.let { runCatching { it.delete() } }
                        }
                    }
                } catch (_: java.util.concurrent.RejectedExecutionException) {
                    result.error("PLUGIN_DISPOSED", "Ringtone plugin is shutting down", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun getAudioContentUri(
        context: Context,
        file: File,
        ringtoneType: Int,
        displayName: String,
        sourceMime: String?,
    ): Uri? {
        val fileName = displayName
        val mimeType = normalizeMime(sourceMime, fileName)

        val relativeFolder = when (ringtoneType) {
            RingtoneManager.TYPE_NOTIFICATION -> "${Environment.DIRECTORY_NOTIFICATIONS}/"
            RingtoneManager.TYPE_ALARM -> "${Environment.DIRECTORY_ALARMS}/"
            else -> "${Environment.DIRECTORY_RINGTONES}/"
        }

        // 1. Try querying MediaStore by DISPLAY_NAME and SIZE, then verify the
        // actual underlying bytes/path match so distinct files sharing name+size
        // cannot collide.
        @Suppress("DEPRECATION")
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
        )
        val selection = "${MediaStore.Audio.Media.DISPLAY_NAME}=? AND ${MediaStore.Audio.Media.SIZE}=? AND ${MediaStore.Audio.Media.MIME_TYPE} LIKE 'audio/%'"
        val selectionArgs = arrayOf(fileName, file.length().toString())

        val cursor = context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null
        )

        var uri: Uri? = null
        cursor?.use {
            val idIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val dataIndex = it.getColumnIndex(MediaStore.Audio.Media.DATA)
            while (it.moveToNext()) {
                val id = it.getLong(idIndex)
                val dataPath = if (dataIndex >= 0) it.getString(dataIndex) else null
                val candidateUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                val samePath = dataPath != null && runCatching {
                    File(dataPath).canonicalPath == file.canonicalPath
                }.getOrDefault(false)
                if (samePath || mediaContentMatchesFile(context, candidateUri, file)) {
                    uri = candidateUri
                    break
                }
            }
        }

        if (uri != null) {
            return uri
        }

        // 2. Insert into MediaStore safely supporting Android 10+ Scoped Storage

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Audio.Media.TITLE, file.nameWithoutExtension)
            put(MediaStore.Audio.Media.SIZE, file.length())
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.Media.IS_RINGTONE, ringtoneType == RingtoneManager.TYPE_RINGTONE)
            put(MediaStore.Audio.Media.IS_NOTIFICATION, ringtoneType == RingtoneManager.TYPE_NOTIFICATION)
            put(MediaStore.Audio.Media.IS_ALARM, ringtoneType == RingtoneManager.TYPE_ALARM)
            put(MediaStore.Audio.Media.IS_MUSIC, false)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Audio.Media.RELATIVE_PATH, relativeFolder)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                val publicDir = Environment.getExternalStoragePublicDirectory(
                    when (ringtoneType) {
                        RingtoneManager.TYPE_NOTIFICATION -> Environment.DIRECTORY_NOTIFICATIONS
                        RingtoneManager.TYPE_ALARM -> Environment.DIRECTORY_ALARMS
                        else -> Environment.DIRECTORY_RINGTONES
                    }
                )
                if (!publicDir.exists()) publicDir.mkdirs()
                val target = File(publicDir, fileName)
                try {
                    file.inputStream().use { input -> target.outputStream().use { out -> input.copyTo(out) } }
                    @Suppress("DEPRECATION")
                    put(MediaStore.Audio.Media.DATA, target.absolutePath)
                } catch (_: Exception) {
                    @Suppress("DEPRECATION")
                    put(MediaStore.Audio.Media.DATA, file.absolutePath)
                }
            }
        }

        val insertedUri = context.contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
        if (insertedUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val out = context.contentResolver.openOutputStream(insertedUri)
                    ?: throw java.io.IOException("Cannot open $insertedUri for writing")
                out.use { stream ->
                    FileInputStream(file).use { input -> input.copyTo(stream) }
                }
                val cleared = context.contentResolver.update(
                    insertedUri,
                    ContentValues().apply { put(MediaStore.Audio.Media.IS_PENDING, 0) },
                    null,
                    null
                ) > 0
                if (!cleared) {
                    // Leave nothing half-published behind; the caller must
                    // report an error, not a URI that no longer exists.
                    runCatching { context.contentResolver.delete(insertedUri, null, null) }
                    return null
                }
            } catch (e: Exception) {
                android.util.Log.w("RingtonePlugin", "Failed to write ringtone content stream: ${e.message}")
                runCatching { context.contentResolver.delete(insertedUri, null, null) }
                return null
            }
        }

        return insertedUri
    }

    private fun sanitizeDisplayName(raw: String): String {
        var name = raw.trim().replace('/', '_').replace('\\', '_')
        while (name.contains("..")) name = name.replace("..", "_")
        name = name.filterNot { it.isISOControl() }.trim().trim('.')
        if (name.isEmpty()) return "ringtone"
        if (name.length > 120) {
            val dot = name.lastIndexOf('.')
            val extension = if (dot > 0 && name.length - dot <= 10) name.substring(dot) else ""
            val base = if (dot > 0) name.substring(0, dot) else name
            name = base.take((120 - extension.length).coerceAtLeast(1)) + extension
        }
        return name
    }

    private fun normalizeMime(rawMime: String?, fileName: String): String {
        val lower = rawMime?.lowercase()?.substringBefore(';')?.trim().orEmpty()
        return when {
            lower.contains("mpeg") || lower.contains("mp3") -> "audio/mpeg"
            lower.contains("mp4") || lower.contains("m4a") || lower.contains("aac") -> "audio/mp4"
            lower.contains("wav") -> "audio/x-wav"
            lower.contains("flac") -> "audio/flac"
            lower.contains("ogg") || lower.contains("opus") || lower.contains("vorbis") -> "audio/ogg"
            lower.contains("wma") -> "audio/x-ms-wma"
            else -> getMimeType(fileName)
        }
    }

    private fun mediaContentMatchesFile(context: Context, candidateUri: Uri, file: File): Boolean {
        return try {
            val expectedLen = file.length()
            context.contentResolver.openInputStream(candidateUri)?.use { candidateStream ->
                file.inputStream().use { sourceStream ->
                    val bufA = ByteArray(8192)
                    val bufB = ByteArray(8192)
                    var total = 0L
                    var matched = true
                    while (true) {
                        val readA = sourceStream.read(bufA)
                        if (readA < 0) {
                            matched = candidateStream.read() < 0 && total == expectedLen
                            break
                        }
                        var off = 0
                        while (off < readA) {
                            val readB = candidateStream.read(bufB, off, readA - off)
                            if (readB <= 0) {
                                matched = false
                                break
                            }
                            off += readB
                        }
                        if (!matched) break
                        for (i in 0 until readA) {
                            if (bufA[i] != bufB[i]) {
                                matched = false
                                break
                            }
                        }
                        if (!matched) break
                        total += readA
                    }
                    matched
                }
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun getMimeType(path: String): String {
        return when {
            path.endsWith(".mp3", ignoreCase = true) -> "audio/mpeg"
            path.endsWith(".m4a", ignoreCase = true) ||
                path.endsWith(".mp4", ignoreCase = true) -> "audio/mp4"
            path.endsWith(".wav", ignoreCase = true) -> "audio/x-wav"
            path.endsWith(".ogg", ignoreCase = true) -> "audio/ogg"
            path.endsWith(".opus", ignoreCase = true) -> "audio/ogg"
            path.endsWith(".flac", ignoreCase = true) -> "audio/flac"
            path.endsWith(".aac", ignoreCase = true) -> "audio/mp4"
            path.endsWith(".wma", ignoreCase = true) -> "audio/x-ms-wma"
            path.endsWith(".dsf", ignoreCase = true) || path.endsWith(".dff", ignoreCase = true) -> "audio/x-dsd"
            else -> "audio/mpeg"
        }
    }
}
