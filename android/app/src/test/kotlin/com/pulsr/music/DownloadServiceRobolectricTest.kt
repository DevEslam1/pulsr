package com.pulsr.music

import android.content.Intent
import android.os.Build
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        DownloadService.tombstoneNowMs = { android.os.SystemClock.elapsedRealtime() }
        DownloadService.clearTombstonesForTesting()
        DownloadChunkStateStore.clearAll(RuntimeEnvironment.getApplication())
        DownloadService.onDownloadCompletedListener = { completed.add(it) }
        DownloadService.onDownloadCancelledListener = { cancelled.add(it) }
    }

    @After
    fun tearDown() {
        DownloadService.onDownloadCompletedListener = null
        DownloadService.onDownloadCancelledListener = null
        DownloadService.clearTombstonesForTesting()
        DownloadService.tombstoneNowMs = { android.os.SystemClock.elapsedRealtime() }
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

    @Test
    fun cancelTombstoneBlocksStaleUpdateUntilRestartOrTtlExpiry() {
        var fakeClockMs = 10_000L
        DownloadService.tombstoneNowMs = { fakeClockMs }

        val service = Robolectric.buildService(DownloadService::class.java).create().get()
        service.onStartCommand(startIntent(service, "v2"), 0, 1)

        val cancelSingle = Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_CANCEL
            putExtra(DownloadService.EXTRA_VIDEO_ID, "v2")
        }
        service.onStartCommand(cancelSingle, 0, 2)
        assertTrue(DownloadService.isTombstoned("v2"))
        assertEquals(listOf("v2"), cancelled)

        // Late UPDATE(100) after CANCEL must be dropped and must not fire completion.
        service.onStartCommand(updateIntent(service, "v2", 100), 0, 3)
        assertTrue(completed.isEmpty())

        // Advancing past 30s TTL expires the tombstone.
        fakeClockMs += DownloadService.TOMBSTONE_TTL_MS + 1L
        assertFalse(DownloadService.isTombstoned("v2"))

        // Explicit restart clears tombstone immediately even before TTL.
        fakeClockMs = 20_000L
        service.onStartCommand(cancelSingle, 0, 4)
        assertTrue(DownloadService.isTombstoned("v2"))
        service.onStartCommand(startIntent(service, "v2"), 0, 5)
        assertFalse(DownloadService.isTombstoned("v2"))

        service.onStartCommand(updateIntent(service, "v2", 100), 0, 6)
        assertEquals(listOf("v2"), completed)
        service.onDestroy()
    }

    @Test
    fun updateProgressDispatchesInProcessToLiveServiceWithoutStartService() {
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        val context = RuntimeEnvironment.getApplication()
        service.onStartCommand(startIntent(service, "v-live"), 0, 1)

        DownloadService.updateProgress(context, "v-live", "Track v-live", 100)
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()

        assertEquals(listOf("v-live"), completed)
        assertEquals(null, org.robolectric.Shadows.shadowOf(context).nextStartedService)
        controller.destroy()
    }

    @Test
    fun releaseJobDisposesNotificationAndStateWithoutFiringCompletion() {
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        service.onStartCommand(startIntent(service, "v-rel"), 0, 1)

        val releaseIntent = Intent(service, DownloadService::class.java).apply {
            action = DownloadService.ACTION_RELEASE
            putExtra(DownloadService.EXTRA_VIDEO_ID, "v-rel")
        }
        service.onStartCommand(releaseIntent, 0, 2)

        assertTrue("releaseJob must NOT trigger onDownloadCompletedListener", completed.isEmpty())
        assertTrue("releaseJob must NOT trigger onDownloadCancelledListener", cancelled.isEmpty())
        assertTrue("releaseJob tombstones released job id", DownloadService.isTombstoned("v-rel"))

        // While service is live, releaseJob posts directly to activeInstance on the main looper.
        val context = RuntimeEnvironment.getApplication()
        DownloadService.releaseJob(context, "v-rel-live")
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        assertTrue(DownloadService.isTombstoned("v-rel-live"))
        assertTrue(completed.isEmpty())

        // After service destruction, releaseJob dispatches ACTION_RELEASE via startService.
        controller.destroy()
        DownloadService.releaseJob(context, "v-rel-api")
        val started = org.robolectric.Shadows.shadowOf(context).nextStartedService
        assertEquals(DownloadService.ACTION_RELEASE, started?.action)
        assertEquals("v-rel-api", started?.getStringExtra(DownloadService.EXTRA_VIDEO_ID))
    }
}
