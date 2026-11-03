package com.pulsr.music

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Thread-safe persistent store for download chunk progress.
 *
 * Progress updates arrive several times per second, so writes are coalesced in
 * memory and flushed at most once per second per video (or immediately when a
 * chunk completes). A download that is killed loses at most ~1 s of progress
 * instead of thrashing SharedPreferences on every buffer callback.
 */
object DownloadChunkStateStore {
    private const val PREFS_NAME = "pulsr_download_chunk_state"
    private const val KEY_PREFIX_CHUNK = "chunk_"
    private const val FLUSH_INTERVAL_MS = 1000L
    const val MAX_AGE_MS = 30L * 24 * 60 * 60 * 1000

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

    private val lock = Any()
    private val pending = HashMap<String, ChunkState>()
    private val lastFlushAtByVideo = HashMap<String, Long>()
    private val scheduledVideos = HashSet<String>()
    private val scheduler = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "PulsrChunkStateFlush").apply { isDaemon = true }
    }

    private fun getPrefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun keyFor(videoId: String, chunkIndex: Int): String =
        "$KEY_PREFIX_CHUNK${videoId}_$chunkIndex"

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
        val chunkComplete = chunkIndex >= totalChunks - 1 ||
            (totalBytes > 0L && downloadedBytes >= totalBytes)
        val appContext = context.applicationContext
        val now = System.currentTimeMillis()
        synchronized(lock) {
            pending[keyFor(videoId, chunkIndex)] = state
            val lastFlush = lastFlushAtByVideo[videoId] ?: 0L
            val elapsed = now - lastFlush
            if (chunkComplete || elapsed >= FLUSH_INTERVAL_MS) {
                flushVideoLocked(appContext, videoId, now)
            } else {
                scheduleFlushLocked(appContext, videoId, FLUSH_INTERVAL_MS - elapsed)
            }
        }
    }

    /** Flushes every pending entry; used on pause/cancel/service teardown and by tests. */
    fun flushPending(context: Context) {
        val appContext = context.applicationContext
        synchronized(lock) {
            val videoIds = pending.values.map { it.videoId }.toSet()
            val now = System.currentTimeMillis()
            for (videoId in videoIds) {
                flushVideoLocked(appContext, videoId, now)
            }
        }
    }

    private fun scheduleFlushLocked(context: Context, videoId: String, delayMs: Long) {
        if (!scheduledVideos.add(videoId)) return
        try {
            scheduler.schedule({
                synchronized(lock) {
                    scheduledVideos.remove(videoId)
                    flushVideoLocked(context, videoId, System.currentTimeMillis())
                }
            }, delayMs.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            scheduledVideos.remove(videoId)
            flushVideoLocked(context, videoId, System.currentTimeMillis())
        }
    }

    private fun flushVideoLocked(context: Context, videoId: String, now: Long) {
        val prefix = "$KEY_PREFIX_CHUNK${videoId}_"
        val entries = pending.filterKeys { it.startsWith(prefix) }
        lastFlushAtByVideo[videoId] = now
        if (entries.isEmpty()) return
        val editor = getPrefs(context).edit()
        for ((key, state) in entries) {
            editor.putString(key, state.toJson())
            pending.remove(key)
        }
        editor.apply()
    }

    fun getChunkProgress(context: Context, videoId: String, chunkIndex: Int): ChunkState? {
        val key = keyFor(videoId, chunkIndex)
        synchronized(lock) {
            pending[key]?.let { return it }
        }
        val raw = getPrefs(context).getString(key, null) ?: return null
        return ChunkState.fromJson(raw)
    }

    fun getAllChunksForVideo(context: Context, videoId: String): List<ChunkState> {
        val prefs = getPrefs(context)
        val prefix = "$KEY_PREFIX_CHUNK${videoId}_"
        val merged = LinkedHashMap<Int, ChunkState>()
        for ((key, value) in prefs.all) {
            if (key.startsWith(prefix) && value is String) {
                ChunkState.fromJson(value)?.let { merged[it.chunkIndex] = it }
            }
        }
        synchronized(lock) {
            for ((key, state) in pending) {
                if (key.startsWith(prefix)) merged[state.chunkIndex] = state
            }
        }
        return merged.values.sortedBy { it.chunkIndex }
    }

    fun clearChunksForVideo(context: Context, videoId: String) {
        val prefix = "$KEY_PREFIX_CHUNK${videoId}_"
        synchronized(lock) {
            pending.keys.removeAll { it.startsWith(prefix) }
            lastFlushAtByVideo.remove(videoId)
            scheduledVideos.remove(videoId)
        }
        val prefs = getPrefs(context)
        val editor = prefs.edit()
        for (key in prefs.all.keys) {
            if (key.startsWith(prefix)) {
                editor.remove(key)
            }
        }
        editor.apply()
    }

    fun clearAll(context: Context) {
        synchronized(lock) {
            pending.clear()
            lastFlushAtByVideo.clear()
            scheduledVideos.clear()
        }
        getPrefs(context).edit().clear().apply()
    }

    /** Drops entries that have not been touched for [maxAgeMs] (default 30 days). */
    fun purgeExpired(context: Context, maxAgeMs: Long = MAX_AGE_MS): Int {
        val cutoff = System.currentTimeMillis() - maxAgeMs
        val prefs = getPrefs(context)
        val editor = prefs.edit()
        var removed = 0
        for ((key, value) in prefs.all) {
            if (!key.startsWith(KEY_PREFIX_CHUNK) || value !is String) continue
            val state = ChunkState.fromJson(value) ?: continue
            if (state.updatedAt < cutoff) {
                editor.remove(key)
                removed++
            }
        }
        if (removed > 0) editor.apply()
        return removed
    }
}
