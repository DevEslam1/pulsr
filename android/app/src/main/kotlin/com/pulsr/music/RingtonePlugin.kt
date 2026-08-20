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

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/ringtone"

        fun registerWith(flutterEngine: FlutterEngine) {
            val plugin = RingtonePlugin()
            plugin.channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.channel.setMethodCallHandler(plugin)
            flutterEngine.plugins.add(plugin)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
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

                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "Audio file not found at $filePath", null)
                    return
                }

                val ringtoneType = when (typeStr.lowercase()) {
                    "notification" -> RingtoneManager.TYPE_NOTIFICATION
                    "alarm" -> RingtoneManager.TYPE_ALARM
                    else -> RingtoneManager.TYPE_RINGTONE
                }

                try {
                    val contentUri = getAudioContentUri(currentContext, file, ringtoneType)
                    if (contentUri != null) {
                        RingtoneManager.setActualDefaultRingtoneUri(currentContext, ringtoneType, contentUri)
                        result.success(true)
                    } else {
                        result.error("URI_ERROR", "Failed to resolve MediaStore Uri for file", null)
                    }
                } catch (e: Exception) {
                    result.error("SET_RINGTONE_FAILED", e.localizedMessage ?: "Unknown error", e.stackTraceToString())
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun getAudioContentUri(context: Context, file: File, ringtoneType: Int): Uri? {
        val fileName = file.name
        val mimeType = getMimeType(file.absolutePath)

        // 1. Try querying MediaStore by DISPLAY_NAME
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DISPLAY_NAME}=?"
        val selectionArgs = arrayOf(fileName)

        val cursor = context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null
        )

        var uri: Uri? = null
        cursor?.use {
            if (it.moveToFirst()) {
                val idIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val id = it.getLong(idIndex)
                uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
            }
        }

        if (uri != null) {
            return uri
        }

        // 2. Insert into MediaStore safely supporting Android 10+ Scoped Storage
        val relativeFolder = when (ringtoneType) {
            RingtoneManager.TYPE_NOTIFICATION -> "${Environment.DIRECTORY_NOTIFICATIONS}/"
            RingtoneManager.TYPE_ALARM -> "${Environment.DIRECTORY_ALARMS}/"
            else -> "${Environment.DIRECTORY_RINGTONES}/"
        }

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Audio.Media.TITLE, file.nameWithoutExtension)
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
                put(MediaStore.Audio.Media.DATA, file.absolutePath)
            }
        }

        val insertedUri = context.contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
        if (insertedUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                context.contentResolver.openOutputStream(insertedUri)?.use { out ->
                    FileInputStream(file).use { input ->
                        input.copyTo(out)
                    }
                }
                val updateValues = ContentValues().apply {
                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                }
                context.contentResolver.update(insertedUri, updateValues, null, null)
            } catch (_: Exception) {
                // Ignore copy errors, uri might still be usable
            }
        }

        return insertedUri
    }

    private fun getMimeType(path: String): String {
        return when {
            path.endsWith(".mp3", ignoreCase = true) -> "audio/mp3"
            path.endsWith(".m4a", ignoreCase = true) -> "audio/m4a"
            path.endsWith(".wav", ignoreCase = true) -> "audio/wav"
            path.endsWith(".ogg", ignoreCase = true) -> "audio/ogg"
            path.endsWith(".flac", ignoreCase = true) -> "audio/flac"
            path.endsWith(".aac", ignoreCase = true) -> "audio/aac"
            else -> "audio/*"
        }
    }
}
