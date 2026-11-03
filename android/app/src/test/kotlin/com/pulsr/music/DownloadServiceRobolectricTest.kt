package com.pulsr.music

import android.content.Intent
import android.os.Build
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(org.robolectric.RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class DownloadServiceRobolectricTest {

    private val completed = mutableListOf<String>()
    private val cancelled = mutableListOf<String>()

    @Before
    fun setUp() {
        DownloadChunkStateStore.clearAll(RuntimeEnvironment.getApplication())
        DownloadService.onDownloadCompletedListener = { completed.add(it) }
        DownloadService.onDownloadCancelledListener = { cancelled.add(it) }
    }

    @After
    fun tearDown() {
        DownloadService.onDownloadCompletedListener = null
        DownloadService.onDownloadCancelledListener = null
        DownloadChunkStateStore.clearAll(RuntimeEnvironment.getApplication())
    }

    private fun startIntent(service: DownloadService, id: String) =
        Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_START
            putExtra(DownloadService.EXTRA_VIDEO_ID, id)
            putExtra(DownloadService.EXTRA_TITLE, "Track $id")
        }

    private fun updateIntent(service: DownloadService, id: String, progress: Int) =
        Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_UPDATE
            putExtra(DownloadService.EXTRA_VIDEO_ID, id)
            putExtra(DownloadService.EXTRA_TITLE, "Track $id")
            putExtra(DownloadService.EXTRA_PROGRESS, progress)
        }

    @Test
    fun progressAtHundredInvokesCompletedListenerAndClearsChunks() {
        val service = Robolectric.buildService(DownloadService::class.java).create().get()
        val context = RuntimeEnvironment.getApplication()
        DownloadChunkStateStore.saveChunkProgress(context, "v1", 0, 2, 10, 20)

        service.onStartCommand(startIntent(service, "v1"), 0, 1)
        service.onStartCommand(updateIntent(service, "v1", 100), 0, 2)

        assertEquals(listOf("v1"), completed)
        assertTrue(DownloadChunkStateStore.getAllChunksForVideo(context, "v1").isEmpty())
    }

    @Test
    fun multiJobCancelActionCancelsEveryActiveId() {
        val service = Robolectric.buildService(DownloadService::class.java).create().get()
        service.onStartCommand(startIntent(service, "a"), 0, 1)
        service.onStartCommand(startIntent(service, "b"), 0, 2)

        val cancelAll = Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_CANCEL
            putExtra(DownloadService.EXTRA_CANCEL_ALL, true)
        }
        service.onStartCommand(cancelAll, 0, 3)

        assertEquals(setOf("a", "b"), cancelled.toSet())
    }

    @Test
    fun missingVideoIdStillStartsForegroundPlaceholder() {
        val service = Robolectric.buildService(DownloadService::class.java).create().get()
        val malformed = Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_START
        }
        // Must not throw: startForegroundService() requires startForeground().
        service.onStartCommand(malformed, 0, 1)
        val shadow = org.robolectric.Shadows.shadowOf(service)
        // The placeholder is posted and removed again; the id records that
        // startForeground() actually ran before the service stopped itself.
        assertTrue(shadow.lastForegroundNotificationId > 0)
    }
}
