package com.pulsr.music

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Looper
import android.speech.tts.TextToSpeech
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import com.hierynomus.smbj.share.File as SmbFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyLong
import org.mockito.ArgumentMatchers.eq
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper
import java.io.File
import java.io.IOException
import java.net.Proxy
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class Phase4ShellPluginsHardeningTest {

    companion object {
        init {
            System.setProperty("net.bytebuddy.experimental", "true")
        }
    }

    private val completedDownloads = mutableListOf<String>()

    @Before
    fun setUp() {
        completedDownloads.clear()
        DownloadService.tombstoneNowMs = { android.os.SystemClock.elapsedRealtime() }
        DownloadService.clearTombstonesForTesting()
        DownloadChunkStateStore.clearAll(RuntimeEnvironment.getApplication())
        DownloadService.onDownloadCompletedListener = { completedDownloads.add(it) }
        ProxyPool.clear()
        ProxyManager.dispose()
        SystemBehaviorPlugin.setStopWhenTaskRemoved(false)
    }

    @After
    fun tearDown() {
        DownloadService.onDownloadCompletedListener = null
        DownloadService.clearTombstonesForTesting()
        DownloadService.tombstoneNowMs = { android.os.SystemClock.elapsedRealtime() }
        DownloadChunkStateStore.clearAll(RuntimeEnvironment.getApplication())
        ProxyPool.clear()
        ProxyManager.dispose()
        SystemBehaviorPlugin.setStopWhenTaskRemoved(false)
    }

    private fun locateFlacFixture(): File {
        val candidates = listOf(
            File("../../third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac"),
            File("third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac"),
        )
        return candidates.firstOrNull { it.exists() }
            ?: throw AssertionError("FLAC test fixture input-VA.flac not found")
    }

    private fun pumpUntil(latch: CountDownLatch, timeoutMs: Long = 5_000L) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (latch.count > 0 && System.currentTimeMillis() < deadline) {
            ShadowLooper.idleMainLooper(50, TimeUnit.MILLISECONDS)
            Thread.sleep(25)
        }
    }

    // ---- Task 15: TagEditorPlugin writeTags no-clobber on verified=false & IO rollback ----

    @Test
    fun tagEditorWriteTagsUnverifiedDoesNotClobberWrittenTagsAndDeletesBackup() {
        val tempDir = Files.createTempDirectory("pulsr_tag_unverified_").toFile()
        val plugin = TagEditorPlugin()
        try {
            val target = File(tempDir, "track.flac")
            locateFlacFixture().copyTo(target, overwrite = true)

            // Establish a clean baseline with known title and no embedded artwork.
            val baseline = AudioFileIO.read(target)
            val baselineTag = baseline.tagOrCreateAndSetDefault
            baselineTag.setField(FieldKey.TITLE, "Original Title")
            baselineTag.deleteArtworkField()
            AudioFileIO.write(baseline)

            plugin.context = RuntimeEnvironment.getApplication()
            val latch = CountDownLatch(1)
            val successRef = AtomicReference<Any?>()
            val errorRef = AtomicReference<String?>()

            // Providing a nonexistent artworkPath triggers verifiedFields["artwork"] = false
            // while AudioFileIO.write still succeeds for title -> ok=true, verified=false.
            val missingArtwork = File(tempDir, "nonexistent_cover.jpg").absolutePath
            plugin.onMethodCall(
                MethodCall(
                    "writeTags",
                    mapOf(
                        "path" to target.absolutePath,
                        "tags" to mapOf(
                            "title" to "Updated Title",
                            "artworkPath" to missingArtwork,
                        ),
                    ),
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        successRef.set(result)
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        errorRef.set(code)
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )

            pumpUntil(latch)
            assertEquals("writeTags should complete within timeout", 0L, latch.count)
            assertNull("Expected success reply, not error", errorRef.get())

            val response = successRef.get() as? Map<*, *>
            assertNotNull("Expected map response from writeTags", response)
            assertEquals(true, response!!["ok"])
            assertEquals(false, response["verified"])
            assertEquals(true, response["backupCreated"])
            val verifiedFields = response["verifiedFields"] as? Map<*, *>
            assertEquals(true, verifiedFields?.get("title"))
            assertEquals(false, verifiedFields?.get("artwork"))

            // Verify written tags remain intact (NOT rolled back to "Original Title").
            val reread = AudioFileIO.read(target)
            assertEquals("Updated Title", reread.tag.getFirst(FieldKey.TITLE))

            // Verify backup file was deleted cleanly.
            val leftoverBackups = tempDir.listFiles { _, name -> name.endsWith(".pulsr.bak") }
                ?: emptyArray()
            assertEquals(0, leftoverBackups.size)
        } finally {
            plugin.cleanup()
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun tagEditorWriteTagsIoErrorRollsBackFromBackupAndDeletesBackup() {
        val tempDir = Files.createTempDirectory("pulsr_tag_rollback_").toFile()
        val plugin = TagEditorPlugin()
        try {
            val target = File(tempDir, "track.flac")
            locateFlacFixture().copyTo(target, overwrite = true)
            val originalBytes = target.readBytes()

            plugin.context = RuntimeEnvironment.getApplication()
            plugin.writeAudioFile = { audioFile ->
                // Simulate a partial corrupt write followed by an IO error.
                audioFile.file.writeBytes("PARTIAL_CORRUPT_DATA".toByteArray())
                throw IOException("Simulated disk full")
            }

            val latch = CountDownLatch(1)
            val errorRef = AtomicReference<String?>()
            plugin.onMethodCall(
                MethodCall(
                    "writeTags",
                    mapOf(
                        "path" to target.absolutePath,
                        "tags" to mapOf("title" to "Will Fail"),
                    ),
                ),
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        latch.countDown()
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        errorRef.set(code)
                        latch.countDown()
                    }

                    override fun notImplemented() {
                        latch.countDown()
                    }
                },
            )

            pumpUntil(latch)
            assertEquals("writeTags should complete within timeout", 0L, latch.count)
            assertEquals("WRITE_TAGS_ERROR", errorRef.get())
            assertArrayEquals(
                "Original file bytes must be restored on IO error",
                originalBytes,
                target.readBytes(),
            )

            val leftoverBackups = tempDir.listFiles { _, name -> name.endsWith(".pulsr.bak") }
                ?: emptyArray()
            assertEquals(0, leftoverBackups.size)
        } finally {
            plugin.cleanup()
            tempDir.deleteRecursively()
        }
    }

    // ---- Task 16: DownloadService ACTION_UPDATE FGS compliance & delegation ----

    @Test
    fun downloadServiceColdStartUpdateNullVideoIdPostsPlaceholderAndStops() {
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        try {
            val intent = Intent(service, DownloadService::class.java).apply {
                action = DownloadService.ACTION_UPDATE
                putExtra(DownloadService.EXTRA_PROGRESS, 50)
            }
            service.onStartCommand(intent, 0, 1)

            val shadow = Shadows.shadowOf(service)
            assertTrue(
                "Cold-start ACTION_UPDATE with null videoId must satisfy startForeground()",
                shadow.lastForegroundNotificationId > 0,
            )
            assertTrue("Service should stop itself after placeholder", shadow.isStoppedBySelf)
        } finally {
            controller.destroy()
        }
    }

    @Test
    fun downloadServiceColdStartUpdateTombstonedPostsPlaceholderAndStops() {
        DownloadService.recordTombstone("tomb-vid")
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        try {
            val intent = Intent(service, DownloadService::class.java).apply {
                action = DownloadService.ACTION_UPDATE
                putExtra(DownloadService.EXTRA_VIDEO_ID, "tomb-vid")
                putExtra(DownloadService.EXTRA_TITLE, "Cancelled Track")
                putExtra(DownloadService.EXTRA_PROGRESS, 100)
            }
            service.onStartCommand(intent, 0, 1)

            val shadow = Shadows.shadowOf(service)
            assertTrue("Tombstoned video must not fire completion", completedDownloads.isEmpty())
            assertTrue(
                "Cold-start ACTION_UPDATE for tombstoned video must satisfy startForeground()",
                shadow.lastForegroundNotificationId > 0,
            )
            assertTrue("Service should stop itself after placeholder", shadow.isStoppedBySelf)
        } finally {
            controller.destroy()
        }
    }

    @Test
    fun downloadServiceColdStartUpdateAt100CompletesAndPostsPlaceholderAndStops() {
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        try {
            val intent = Intent(service, DownloadService::class.java).apply {
                action = DownloadService.ACTION_UPDATE
                putExtra(DownloadService.EXTRA_VIDEO_ID, "cold-100")
                putExtra(DownloadService.EXTRA_TITLE, "Instant Complete")
                putExtra(DownloadService.EXTRA_PROGRESS, 100)
            }
            service.onStartCommand(intent, 0, 1)

            val shadow = Shadows.shadowOf(service)
            assertEquals(listOf("cold-100"), completedDownloads)
            assertTrue(DownloadService.isTombstoned("cold-100"))
            assertTrue(
                "Cold-start ACTION_UPDATE at 100% must satisfy startForeground()",
                shadow.lastForegroundNotificationId > 0,
            )
            assertTrue("Service should stop itself immediately on cold 100%", shadow.isStoppedBySelf)
        } finally {
            controller.destroy()
        }
    }

    @Test
    fun downloadServiceActionStopDelegatesToHandleStop() {
        val controller = Robolectric.buildService(DownloadService::class.java).create()
        val service = controller.get()
        try {
            val start = Intent(service, DownloadService::class.java).apply {
                action = DownloadService.ACTION_START
                putExtra(DownloadService.EXTRA_VIDEO_ID, "stop-vid")
                putExtra(DownloadService.EXTRA_TITLE, "Active Track")
            }
            service.onStartCommand(start, 0, 1)

            val stop = Intent(service, DownloadService::class.java).apply {
                action = DownloadService.ACTION_STOP
            }
            service.onStartCommand(stop, 0, 2)

            assertTrue(DownloadService.isTombstoned("stop-vid"))
            assertTrue(Shadows.shadowOf(service).isStoppedBySelf)
        } finally {
            controller.destroy()
        }
    }

    // ---- Task 17: TtsPlugin off-main-thread onInit safety ----

    @Test
    fun ttsPluginOffMainThreadOnInitPostsToMainLooperAndResolvesPendingResults() {
        val plugin = TtsPlugin()
        plugin.context = RuntimeEnvironment.getApplication()
        val mockTts = mock(TextToSpeech::class.java)
        `when`(mockTts.isLanguageAvailable(any())).thenReturn(TextToSpeech.LANG_AVAILABLE)

        val capturedListener = AtomicReference<TextToSpeech.OnInitListener>()
        plugin.ttsFactory = { _, listener ->
            capturedListener.set(listener)
            mockTts
        }

        val firstValue = AtomicReference<Any?>()
        val firstThread = AtomicReference<Thread?>()
        val secondValue = AtomicReference<Any?>()
        val secondThread = AtomicReference<Thread?>()

        plugin.onMethodCall(
            MethodCall("init", null),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    firstValue.set(result)
                    firstThread.set(Thread.currentThread())
                }

                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            },
        )
        plugin.onMethodCall(
            MethodCall("init", null),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    secondValue.set(result)
                    secondThread.set(Thread.currentThread())
                }

                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            },
        )

        val listener = capturedListener.get()
        assertNotNull("Expected TextToSpeech.OnInitListener to be captured", listener)

        // Fire onInit from a background worker thread (simulating Binder IPC callback).
        val bgThread = Thread {
            listener.onInit(TextToSpeech.SUCCESS)
        }
        bgThread.start()
        bgThread.join(2_000L)

        // Must NOT have executed synchronously on the background thread.
        assertNull("Pending result must not resolve on background thread", firstValue.get())
        assertNull("Second pending result must not resolve on background thread", secondValue.get())

        // Drain the main looper: both results must resolve on the main thread.
        ShadowLooper.idleMainLooper()

        assertEquals(true, firstValue.get())
        assertEquals(true, secondValue.get())
        assertSame(Looper.getMainLooper().thread, firstThread.get())
        assertSame(Looper.getMainLooper().thread, secondThread.get())

        plugin.dispose()
    }

    @Test
    fun ttsPluginOffMainThreadOnInitAfterDisposeIsIgnored() {
        val plugin = TtsPlugin()
        plugin.context = RuntimeEnvironment.getApplication()
        val mockTts = mock(TextToSpeech::class.java)
        val capturedListener = AtomicReference<TextToSpeech.OnInitListener>()
        plugin.ttsFactory = { _, listener ->
            capturedListener.set(listener)
            mockTts
        }

        val initValue = AtomicReference<Any?>()
        plugin.onMethodCall(
            MethodCall("init", null),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    initValue.set(result)
                }

                override fun error(code: String, message: String?, details: Any?) = Unit
                override fun notImplemented() = Unit
            },
        )
        plugin.dispose()
        assertEquals(false, initValue.get())

        val bgThread = Thread {
            capturedListener.get().onInit(TextToSpeech.SUCCESS)
        }
        bgThread.start()
        bgThread.join(2_000L)
        ShadowLooper.idleMainLooper()

        verify(mockTts, never()).setOnUtteranceProgressListener(any())
    }

    // ---- Task 18: SmbPlugin session eviction on password change & short-read looping ----

    @Test
    fun smbPluginPasswordChangeClosesAndRemovesPreviousSession() {
        val plugin = SmbPlugin()
        try {
            val client1 = mock(SMBClient::class.java)
            val conn1 = mock(Connection::class.java)
            val session1 = mock(Session::class.java)
            val share1 = mock(DiskShare::class.java)
            `when`(client1.connect("nas.local", 445)).thenReturn(conn1)
            `when`(conn1.isConnected).thenReturn(true)
            `when`(conn1.authenticate(any())).thenReturn(session1)
            `when`(session1.connectShare("music")).thenReturn(share1)

            val client2 = mock(SMBClient::class.java)
            val conn2 = mock(Connection::class.java)
            val session2 = mock(Session::class.java)
            val share2 = mock(DiskShare::class.java)
            `when`(client2.connect("nas.local", 445)).thenReturn(conn2)
            `when`(conn2.isConnected).thenReturn(true)
            `when`(conn2.authenticate(any())).thenReturn(session2)
            `when`(session2.connectShare("music")).thenReturn(share2)

            val clients = ArrayDeque(listOf(client1, client2))
            plugin.clientFactory = { clients.removeFirst() }

            val firstShare = plugin.shareFor(
                mapOf(
                    "host" to "nas.local",
                    "port" to 445,
                    "share" to "music",
                    "username" to "alice",
                    "password" to "old-password",
                ),
            )
            assertSame(share1, firstShare)
            assertEquals(1, plugin.cachedSessionCount())

            // Same host/port/share/user with a new password must close & evict the old session.
            val secondShare = plugin.shareFor(
                mapOf(
                    "host" to "nas.local",
                    "port" to 445,
                    "share" to "music",
                    "username" to "alice",
                    "password" to "new-password",
                ),
            )
            assertSame(share2, secondShare)
            assertEquals(1, plugin.cachedSessionCount())

            verify(share1, times(1)).close()
            verify(session1, times(1)).close()
            verify(conn1, times(1)).close()
            verify(client1, times(1)).close()
            verify(share2, never()).close()
        } finally {
            plugin.cleanup()
        }
    }

    @Test
    fun smbPluginOpenReadChunkLoopsAcrossShortSmbReads() {
        val plugin = SmbPlugin()
        try {
            val client = mock(SMBClient::class.java)
            val conn = mock(Connection::class.java)
            val session = mock(Session::class.java)
            val share = mock(DiskShare::class.java)
            val smbFile = mock(SmbFile::class.java)

            `when`(client.connect("nas.local", 445)).thenReturn(conn)
            `when`(conn.isConnected).thenReturn(true)
            `when`(conn.authenticate(any())).thenReturn(session)
            `when`(session.connectShare("music")).thenReturn(share)
            `when`(
                share.openFile(
                    eq("album/track.flac"),
                    any(),
                    isNull(),
                    any(),
                    any(),
                    isNull(),
                ),
            ).thenReturn(smbFile)

            val filePayload = byteArrayOf(10, 11, 12, 13, 14, 15, 16, 17, 18, 19)
            val baseOffset = 100L
            // Simulate an SMB2 server capping each read response to 3 bytes.
            doAnswer { invocation ->
                val buf = invocation.getArgument<ByteArray>(0)
                val fileOffset = invocation.getArgument<Long>(1)
                val bufOffset = invocation.getArgument<Int>(2)
                val requested = invocation.getArgument<Int>(3)
                val srcPos = (fileOffset - baseOffset).toInt()
                if (srcPos < 0 || srcPos >= filePayload.size) {
                    -1
                } else {
                    val toCopy = minOf(3, requested, filePayload.size - srcPos)
                    System.arraycopy(filePayload, srcPos, buf, bufOffset, toCopy)
                    toCopy
                }
            }.`when`(smbFile).read(any(ByteArray::class.java), anyLong(), anyInt(), anyInt())

            plugin.clientFactory = { client }

            val exactChunk = plugin.openReadChunk(
                mapOf(
                    "host" to "nas.local",
                    "port" to 445,
                    "share" to "music",
                    "path" to "album/track.flac",
                    "offset" to baseOffset,
                    "length" to filePayload.size,
                ),
            )
            assertArrayEquals(filePayload, exactChunk)

            // Requesting more than remaining bytes stops cleanly at EOF and trims the array.
            val eofChunk = plugin.openReadChunk(
                mapOf(
                    "host" to "nas.local",
                    "port" to 445,
                    "share" to "music",
                    "path" to "album/track.flac",
                    "offset" to baseOffset,
                    "length" to filePayload.size + 12,
                ),
            )
            assertArrayEquals(filePayload, eofChunk)
        } finally {
            plugin.cleanup()
        }
    }

    // ---- Task 19: ProxyManager non-explicit pool clearing & SystemBehaviorPlugin weak activity set ----

    @Test
    fun proxyManagerSetProxyEmptyHostClearsNonExplicitPoolOnly() {
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "10.0.0.1",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = null,
        )
        assertTrue(ProxyPool.isPoolConfigured())
        assertFalse(ProxyPool.hasExplicitPool)

        // Clearing host while enabled=true must also clear the non-explicit ProxyPool.
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = null,
        )
        assertFalse(ProxyPool.isPoolConfigured())
        assertNull(ProxyManager.getProxy("https://example.com"))

        // An explicit multi-proxy pool must NOT be cleared by an empty single-proxy host.
        ProxyPool.setProxies(
            listOf(
                ProxyPool.ProxyNode(
                    id = "explicit-1",
                    type = Proxy.Type.HTTP,
                    host = "10.0.0.2",
                    port = 8080,
                ),
            ),
            isExplicit = true,
        )
        ProxyManager.setProxy(
            enabled = true,
            type = "http",
            host = "",
            port = 8080,
            username = null,
            password = null,
            bypassHosts = null,
        )
        assertTrue(ProxyPool.isPoolConfigured())
        assertTrue(ProxyPool.hasExplicitPool)
        assertNotNull(ProxyManager.getProxy("https://example.com"))
    }

    @Test
    fun systemBehaviorPluginTracksLiveActivitiesInWeakSet() {
        val channel = mock(MethodChannel::class.java)
        val plugin = SystemBehaviorPlugin(null, channel)
        try {
            SystemBehaviorPlugin.setStopWhenTaskRemoved(true)

            val rootActivity = mock(Activity::class.java)
            `when`(rootActivity.isFinishing).thenReturn(true)
            `when`(rootActivity.isChangingConfigurations).thenReturn(false)
            `when`(rootActivity.isTaskRoot).thenReturn(true)

            val secondActivity = mock(Activity::class.java)
            `when`(secondActivity.isFinishing).thenReturn(true)
            `when`(secondActivity.isChangingConfigurations).thenReturn(false)
            `when`(secondActivity.isTaskRoot).thenReturn(false)

            // Simulate plugin registration occurring after rootActivity.onCreate():
            // rootActivity is observed via onActivityStarted/onActivityResumed, then
            // secondActivity is created.
            plugin.onActivityStarted(rootActivity)
            plugin.onActivityResumed(rootActivity)
            plugin.onActivityCreated(secondActivity, null)

            // Destroying rootActivity while secondActivity is alive must NOT notify taskRemoved.
            plugin.onActivityDestroyed(rootActivity)
            verify(channel, never()).invokeMethod(SystemBehaviorPlugin.METHOD_TASK_REMOVED, null)

            // Recreate rootActivity, then destroy secondActivity (root still alive -> no stop).
            plugin.onActivityCreated(rootActivity, null)
            plugin.onActivityDestroyed(secondActivity)
            verify(channel, never()).invokeMethod(SystemBehaviorPlugin.METHOD_TASK_REMOVED, null)

            // Destroying the last live task-root activity must notify Dart once.
            plugin.onActivityDestroyed(rootActivity)
            verify(channel, times(1)).invokeMethod(SystemBehaviorPlugin.METHOD_TASK_REMOVED, null)
        } finally {
            plugin.dispose()
        }
    }
}
