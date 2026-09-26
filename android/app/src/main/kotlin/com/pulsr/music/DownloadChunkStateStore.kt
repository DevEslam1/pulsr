package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Thread-safe persistent store for download chunk progress and WorkManager state.
 *
 * Allows partially downloaded chunks to survive service kills, app restarts,
 * and WorkManager reschedules without losing downloaded byte progress.
 */
object DownloadChunkStateStore {
    private const val PREFS_NAME = "pulsr_download_chunk_state"
    private const val KEY_PREFIX_CHUNK = "chunk_"

    data class ChunkState(
        val videoId: String,
        val chunkIndex: Int,
        val totalChunks: Int,
        val downloadedBytes: Long,
        val totalBytes: Long,
        val updatedAt: Long,
    ) {
        fun toJson(): String {
            return JSONObject().apply {
                put("videoId", videoId)
                put("chunkIndex", chunkIndex)
                put("totalChunks", totalChunks)
                put("downloadedBytes", downloadedBytes)
                put("totalBytes", totalBytes)
                put("updatedAt", updatedAt)
            }.toString()
        }

        companion object {
            fun fromJson(jsonStr: String): ChunkState? {
                return try {
                    val obj = JSONObject(jsonStr)
                    ChunkState(
                        videoId = obj.getString("videoId"),
                        chunkIndex = obj.getInt("chunkIndex"),
                        totalChunks = obj.getInt("totalChunks"),
                        downloadedBytes = obj.getLong("downloadedBytes"),
                        totalBytes = obj.getLong("totalBytes"),
                        updatedAt = obj.optLong("updatedAt", System.currentTimeMillis()),
                    )
                } catch (_: Exception) {
                    null
                }
            }
        }
    }

    private fun getPrefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun saveChunkProgress(
        context: Context,
        videoId: String,
        chunkIndex: Int,
        totalChunks: Int,
        downloadedBytes: Long,
        totalBytes: Long,
    ) {
        val state = ChunkState(
            videoId = videoId,
            chunkIndex = chunkIndex,
            totalChunks = totalChunks,
            downloadedBytes = downloadedBytes,
            totalBytes = totalBytes,
            updatedAt = System.currentTimeMillis(),
        )
        val key = "$KEY_PREFIX_CHUNK${videoId}_$chunkIndex"
        getPrefs(context).edit().putString(key, state.toJson()).apply()
    }

    fun getChunkProgress(context: Context, videoId: String, chunkIndex: Int): ChunkState? {
        val key = "$KEY_PREFIX_CHUNK${videoId}_$chunkIndex"
        val raw = getPrefs(context).getString(key, null) ?: return null
        return ChunkState.fromJson(raw)
    }

    fun getAllChunksForVideo(context: Context, videoId: String): List<ChunkState> {
        val prefs = getPrefs(context)
        val prefix = "$KEY_PREFIX_CHUNK${videoId}_"
        val result = mutableListOf<ChunkState>()
        for ((key, value) in prefs.all) {
            if (key.startsWith(prefix) && value is String) {
                ChunkState.fromJson(value)?.let { result.add(it) }
            }
        }
        return result.sortedBy { it.chunkIndex }
    }

    fun clearChunksForVideo(context: Context, videoId: String) {
        val prefs = getPrefs(context)
        val prefix = "$KEY_PREFIX_CHUNK${videoId}_"
        val editor = prefs.edit()
        for (key in prefs.all.keys) {
            if (key.startsWith(prefix)) {
                editor.remove(key)
            }
        }
        editor.apply()
    }

    fun clearAll(context: Context) {
        getPrefs(context).edit().clear().apply()
    }
}
