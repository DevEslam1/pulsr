package com.pulsr.music

import android.content.Context
import android.os.Build
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.json.JSONObject

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class DownloadChunkStateStoreTest {
    private lateinit var context: Context

    private fun prefs() = context.getSharedPreferences("pulsr_download_chunk_state", Context.MODE_PRIVATE)

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        DownloadChunkStateStore.clearAll(context)
    }

    @After
    fun tearDown() {
        DownloadChunkStateStore.clearAll(context)
    }

    @Test
    fun progressIsReadableBeforeFlushAndCoalescedOnDisk() {
        DownloadChunkStateStore.saveChunkProgress(context, "v1", 0, 3, 100, 9000)
        // First write flushes immediately.
        assertNotNull(prefs().getString("chunk_v1_0", null))

        DownloadChunkStateStore.saveChunkProgress(context, "v1", 1, 3, 200, 9000)
        // Second write within one second is coalesced in memory.
        assertNull(prefs().getString("chunk_v1_1", null))
        val pending = DownloadChunkStateStore.getChunkProgress(context, "v1", 1)
        assertEquals(200L, pending?.downloadedBytes)

        // A newer update replaces the pending entry, still without a disk write.
        DownloadChunkStateStore.saveChunkProgress(context, "v1", 1, 3, 250, 9000)
        assertNull(prefs().getString("chunk_v1_1", null))
        assertEquals(250L, DownloadChunkStateStore.getChunkProgress(context, "v1", 1)?.downloadedBytes)

        DownloadChunkStateStore.flushPending(context)
        val onDisk = DownloadChunkStateStore.ChunkState.fromJson(prefs().getString("chunk_v1_1", null)!!)
        assertEquals(250L, onDisk?.downloadedBytes)
    }

    @Test
    fun chunkCompletionFlushesImmediately() {
        DownloadChunkStateStore.saveChunkProgress(context, "v2", 0, 2, 1000, 4000)
        assertNotNull(prefs().getString("chunk_v2_0", null))
        DownloadChunkStateStore.saveChunkProgress(context, "v2", 1, 2, 4000, 4000)
        // Last chunk -> immediate flush.
        assertNotNull(prefs().getString("chunk_v2_1", null))
    }

    @Test
    fun singleChunkProgressCoalescesUntilBytesComplete() {
        DownloadChunkStateStore.saveChunkProgress(context, "v4", 0, 1, 100, 9000)
        // First write for a video flushes immediately.
        assertEquals(
            100L,
            DownloadChunkStateStore.ChunkState.fromJson(prefs().getString("chunk_v4_0", null)!!)?.downloadedBytes
        )

        DownloadChunkStateStore.saveChunkProgress(context, "v4", 0, 1, 200, 9000)
        // Not byte-complete: buffered in memory, disk still holds the old value.
        assertEquals(
            200L,
            DownloadChunkStateStore.getChunkProgress(context, "v4", 0)?.downloadedBytes
        )
        assertEquals(
            100L,
            DownloadChunkStateStore.ChunkState.fromJson(prefs().getString("chunk_v4_0", null)!!)?.downloadedBytes
        )

        DownloadChunkStateStore.flushPending(context)
        assertEquals(
            200L,
            DownloadChunkStateStore.ChunkState.fromJson(prefs().getString("chunk_v4_0", null)!!)?.downloadedBytes
        )
    }

    @Test
    fun purgeDropsEntriesOlderThanThirtyDays() {
        val old = DownloadChunkStateStore.ChunkState(
            videoId = "old",
            chunkIndex = 0,
            totalChunks = 1,
            downloadedBytes = 10,
            totalBytes = 10,
            updatedAt = System.currentTimeMillis() - 31L * 24 * 60 * 60 * 1000,
        )
        val recent = old.copy(videoId = "recent", updatedAt = System.currentTimeMillis())
        prefs().edit()
            .putString("chunk_old_0", old.toJson())
            .putString("chunk_recent_0", recent.toJson())
            .apply()

        val removed = DownloadChunkStateStore.purgeExpired(context)
        assertEquals(1, removed)
        assertNull(prefs().getString("chunk_old_0", null))
        assertNotNull(prefs().getString("chunk_recent_0", null))
    }

    @Test
    fun clearForVideoAlsoDropsPendingEntry() {
        DownloadChunkStateStore.saveChunkProgress(context, "v3", 0, 5, 100, 5000)
        DownloadChunkStateStore.saveChunkProgress(context, "v3", 1, 5, 200, 5000)
        DownloadChunkStateStore.clearChunksForVideo(context, "v3")

        assertNull(DownloadChunkStateStore.getChunkProgress(context, "v3", 1))
        assertTrue(DownloadChunkStateStore.getAllChunksForVideo(context, "v3").isEmpty())
    }
}
