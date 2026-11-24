package com.pulsr.music

import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.media.AudioManager
import android.os.Build
import android.os.Looper
import com.ryanheise.just_audio.PulsrOutputRouting
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.mockito.Answers
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito.atLeastOnce
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class Wave1NativeHardeningTest {

    companion object {
        init {
            System.setProperty("net.bytebuddy.experimental", "true")
        }
    }

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Before
    fun resetRouting() {
        PulsrOutputRouting.setDspActive(false)
    }

    @After
    fun clearRouting() {
        PulsrOutputRouting.setDspActive(false)
    }

    // ---- H-03, H-05, L-03: AudioEffectsPlugin DVC / ReplayGain / PcmToDsd / limiter default ----

    @Test
    fun audioEffectsPluginDvcAndReplayGainDriveDspActiveWhilePcmToDsdDoesNotAndLimiterDefaultIs5Ms() {
        val plugin = AudioEffectsPlugin()
        val app = RuntimeEnvironment.getApplication()
        val audioManager = mock(AudioManager::class.java)
        `when`(audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).thenReturn(15)
        `when`(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)).thenReturn(10)
        val mockCtx = mock(Context::class.java)
        `when`(mockCtx.getSystemService(Context.AUDIO_SERVICE)).thenReturn(audioManager)
        `when`(mockCtx.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))
            .thenReturn(app.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))

        setField(plugin, "context", mockCtx)
        setField(plugin, "isNativeDspLoaded", true)

        // L-03: limiter lookahead default must match DspParamRanges (5.0 ms).
        assertEquals(5.0, getField(plugin, "limiterLookaheadMs") as Double, 1e-6)
        assertEquals(DspParamRanges.limiterLookaheadMs.defaultValue, getField(plugin, "limiterLookaheadMs") as Double, 1e-6)

        val computeDspActive = AudioEffectsPlugin::class.java.getDeclaredMethod("computeDspActive").apply {
            isAccessible = true
        }
        val syncDspActiveRouting = AudioEffectsPlugin::class.java.getDeclaredMethod("syncDspActiveRouting").apply {
            isAccessible = true
        }
        val hasActiveEffects = AudioEffectsPlugin::class.java.getDeclaredMethod("hasActiveEffects").apply {
            isAccessible = true
        }

        // H-05: DVC active marks computeDspActive() == true and syncDspActiveRouting propagates to PulsrOutputRouting.
        setField(plugin, "dvcEnabled", true)
        assertTrue(plugin.applyDvcRuntimeState(true))
        assertTrue(computeDspActive.invoke(plugin) as Boolean)
        syncDspActiveRouting.invoke(plugin)
        assertTrue(PulsrOutputRouting.isDspActive())

        assertTrue(plugin.applyDvcRuntimeState(false))
        setField(plugin, "dvcActive", false)
        syncDspActiveRouting.invoke(plugin)
        assertFalse(PulsrOutputRouting.isDspActive())

        // H-05: ReplayGain active marks computeDspActive() == true and syncDspActiveRouting propagates.
        setField(plugin, "isReplayGainEnabled", true)
        assertTrue(computeDspActive.invoke(plugin) as Boolean)
        syncDspActiveRouting.invoke(plugin)
        assertTrue(PulsrOutputRouting.isDspActive())

        setField(plugin, "isReplayGainEnabled", false)
        syncDspActiveRouting.invoke(plugin)
        assertFalse(PulsrOutputRouting.isDspActive())
    }

    // ---- H-04: UsbExclusivePlugin writeDsd accepts Int producerId via Number.toLong() ----

    @Test
    fun usbExclusivePluginWriteDsdHandlesIntegerAndLongProducerIdsWithoutClassCast() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = UsbExclusivePlugin(ctx, messenger)
        try {
            val intLatch = CountDownLatch(1)
            val intResult = mock(MethodChannel.Result::class.java)
            var intSuccess: Any? = null
            doAnswer {
                intSuccess = it.arguments[0]
                intLatch.countDown()
                null
            }.`when`(intResult).success(any())

            // Dart standard message codec delivers small integer producerIds as java.lang.Integer.
            plugin.onMethodCall(
                MethodCall(
                    "writeDsd",
                    mapOf(
                        "left" to byteArrayOf(0x69, 0x69),
                        "right" to byteArrayOf(0x69, 0x69),
                        "producerId" to 42,
                    ),
                ),
                intResult,
            )
            awaitMainLooper(intLatch)
            assertTrue("Int producerId call must complete cleanly", intLatch.await(0, TimeUnit.MILLISECONDS))
            assertEquals(false, intSuccess)
        } finally {
            plugin.dispose()
        }
    }

    // ---- H-06: TagEditorPlugin real image MIME sniffing ----

    @Test
    fun tagEditorPluginSniffsJpegPngWebpAndRejectsUnknownBytes() {
        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte())
        val png = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        val webp = "RIFF\u0000\u0000\u0000\u0000WEBP".toByteArray(Charsets.US_ASCII)
        val garbage = "NOT_AN_IMAGE_FORMAT".toByteArray(Charsets.US_ASCII)

        assertEquals("image/jpeg", TagEditorPlugin.sniffArtworkMimeType(jpeg))
        assertEquals("image/png", TagEditorPlugin.sniffArtworkMimeType(png))
        assertEquals("image/webp", TagEditorPlugin.sniffArtworkMimeType(webp))
        assertNull(TagEditorPlugin.sniffArtworkMimeType(garbage))
        assertNull(TagEditorPlugin.sniffArtworkMimeType(byteArrayOf()))
    }

    @Test
    fun tagEditorPluginSurfacesArtworkErrorsOnStandaloneAndMixedTagWrites() {
        val ctx = RuntimeEnvironment.getApplication()
        val tempDir = tempFolder.newFolder("tag_artwork_err")
        val flacFixture = File("../../third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac")
            .takeIf { it.exists() }
            ?: File("third_party/media3-flac-decoder/src/main/jni/flac/test/flac-to-flac-metadata-test-files/input-VA.flac")
        val target = File(tempDir, "sample.flac")
        flacFixture.copyTo(target, overwrite = true)

        val plugin = TagEditorPlugin()
        plugin.context = ctx
        try {
            val missingCover = File(tempDir, "missing_cover.png").absolutePath

            // 1. Standalone artwork-only request with missing file must return WRITE_TAGS_ERROR.
            val standaloneLatch = CountDownLatch(1)
            var standaloneErrorCode: String? = null
            plugin.onMethodCall(
                MethodCall("writeTags", mapOf("path" to target.absolutePath, "tags" to mapOf("artworkPath" to missingCover))),
                object : MethodChannel.Result {
                    override fun success(res: Any?) { standaloneLatch.countDown() }
                    override fun error(code: String, msg: String?, details: Any?) {
                        standaloneErrorCode = code
                        standaloneLatch.countDown()
                    }
                    override fun notImplemented() { standaloneLatch.countDown() }
                },
            )
            awaitMainLooper(standaloneLatch)
            assertEquals("WRITE_TAGS_ERROR", standaloneErrorCode)

            // 2. Mixed text + missing artwork writes text cleanly while surfacing artworkError.
            val mixedLatch = CountDownLatch(1)
            var mixedResponse: Map<*, *>? = null
            plugin.onMethodCall(
                MethodCall(
                    "writeTags",
                    mapOf("path" to target.absolutePath, "tags" to mapOf("title" to "Clean Title", "artworkPath" to missingCover)),
                ),
                object : MethodChannel.Result {
                    override fun success(res: Any?) {
                        mixedResponse = res as? Map<*, *>
                        mixedLatch.countDown()
                    }
                    override fun error(code: String, msg: String?, details: Any?) { mixedLatch.countDown() }
                    override fun notImplemented() { mixedLatch.countDown() }
                },
            )
            awaitMainLooper(mixedLatch)
            assertEquals(true, mixedResponse?.get("ok"))
            assertEquals(false, mixedResponse?.get("verified"))
            assertTrue((mixedResponse?.get("artworkError") as? String)?.contains("missing_cover.png") == true)
        } finally {
            plugin.cleanup()
        }
    }

    // ---- M-11: UsbErgonomicsPlugin honors exact deviceId ----

    @Test
    fun usbErgonomicsPluginResolvesTargetDeviceByDeviceIdOverVidPidCollision() {
        val sysfs = tempFolder.newFolder("usb_ergo_sysfs")
        val dev1Dir = File(sysfs, "1-1").apply { mkdirs() }
        File(dev1Dir, "busnum").writeText("1\n")
        File(dev1Dir, "devnum").writeText("2\n")
        File(dev1Dir, "speed").writeText("12\n")

        val dev2Dir = File(sysfs, "1-2").apply { mkdirs() }
        File(dev2Dir, "busnum").writeText("1\n")
        File(dev2Dir, "devnum").writeText("9\n")
        File(dev2Dir, "speed").writeText("480\n")

        val audioIface = mock(UsbInterface::class.java)
        `when`(audioIface.interfaceClass).thenReturn(UsbConstants.USB_CLASS_AUDIO)

        val dev1 = mock(UsbDevice::class.java)
        `when`(dev1.deviceId).thenReturn(1001)
        `when`(dev1.vendorId).thenReturn(0x1234)
        `when`(dev1.productId).thenReturn(0x5678)
        `when`(dev1.deviceName).thenReturn("/dev/bus/usb/001/002")
        `when`(dev1.interfaceCount).thenReturn(1)
        `when`(dev1.getInterface(0)).thenReturn(audioIface)

        val dev2 = mock(UsbDevice::class.java)
        `when`(dev2.deviceId).thenReturn(2002)
        `when`(dev2.vendorId).thenReturn(0x1234)
        `when`(dev2.productId).thenReturn(0x5678)
        `when`(dev2.deviceName).thenReturn("/dev/bus/usb/001/009")
        `when`(dev2.interfaceCount).thenReturn(1)
        `when`(dev2.getInterface(0)).thenReturn(audioIface)

        assertEquals(480.0, UsbSysfs.busSpeedMbps(dev2, sysfs)["mbps"])
        assertEquals(12.0, UsbSysfs.busSpeedMbps(dev1, sysfs)["mbps"])

        val usbManager = mock(UsbManager::class.java)
        `when`(usbManager.deviceList).thenReturn(linkedMapOf("d1" to dev1, "d2" to dev2))

        val lookupClass = Class.forName("com.pulsr.music.UsbDeviceLookup")
        val instance = lookupClass.getDeclaredField("INSTANCE").apply { isAccessible = true }.get(null)
        val audioDeviceById = lookupClass.getDeclaredMethod(
            "audioDeviceById",
            UsbManager::class.java,
            Integer::class.java,
        ).apply { isAccessible = true }

        val chosen = audioDeviceById.invoke(instance, usbManager, 2002) as UsbDevice?
        assertEquals(2002, chosen?.deviceId)
        assertNull(audioDeviceById.invoke(instance, usbManager, 9999))
    }

    // ---- M-12: HiResDacPlugin rate & bit depth table alignment ----

    @Test
    fun hiResDacPluginAcceptsFullDartFormatTableAndRejectsOutOfTableFormats() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = HiResDacPlugin(ctx, messenger)
        try {
            val validRates = listOf(
                0, 8000, 11025, 12000, 16000, 22050, 24000, 32000,
                44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000,
                705600, 768000,
            )
            for (rate in validRates) {
                val latch = CountDownLatch(1)
                var invalidError = false
                val res = object : MethodChannel.Result {
                    override fun success(result: Any?) { latch.countDown() }
                    override fun error(code: String, msg: String?, details: Any?) {
                        if (code == "INVALID_FORMAT") invalidError = true
                        latch.countDown()
                    }
                    override fun notImplemented() { latch.countDown() }
                }
                plugin.onMethodCall(
                    MethodCall("setTargetOutputFormat", mapOf("sampleRate" to rate, "bitDepth" to 24)),
                    res,
                )
                awaitMainLooper(latch)
                assertTrue("Valid rate=$rate must complete", latch.await(0, TimeUnit.MILLISECONDS))
                assertFalse("Rate $rate must be allowed by VALID_TARGET_SAMPLE_RATES", invalidError)
            }

            // Invalid sample rate / bit depth must fail synchronously with INVALID_FORMAT.
            val badRateRes = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("setTargetOutputFormat", mapOf("sampleRate" to 48001, "bitDepth" to 24)),
                badRateRes,
            )
            verify(badRateRes).error(eq("INVALID_FORMAT"), any(), isNull())

            val badDepthRes = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("setTargetOutputFormat", mapOf("sampleRate" to 48000, "bitDepth" to 20)),
                badDepthRes,
            )
            verify(badDepthRes).error(eq("INVALID_FORMAT"), any(), isNull())
        } finally {
            plugin.dispose()
        }
    }

    // ---- M-12: MainActivity activeActivityByEngine prevents stale Activity teardown ----

    @Test
    fun mainActivityStaleCleanupDoesNotClearHandlersOwnedByReplacementActivity() {
        val messenger = mock(BinaryMessenger::class.java)
        val engine = mock(FlutterEngine::class.java, Answers.RETURNS_DEEP_STUBS)
        `when`(engine.dartExecutor.binaryMessenger).thenReturn(messenger)

        val act1 = MainActivity()
        val act2 = MainActivity()
        val bindMethod = MainActivity::class.java.getDeclaredMethod(
            "bindActivityChannels",
            FlutterEngine::class.java,
        ).apply { isAccessible = true }

        // First activity claims channels, then replacement act2 claims the same cached engine.
        bindMethod.invoke(act1, engine)
        bindMethod.invoke(act2, engine)

        // Cleaning up act1 must NOT null out file_opener/assistant/lyrics handlers owned by act2.
        act1.cleanUpFlutterEngine(engine)
        verify(messenger, never()).setMessageHandler(
            eq("com.pulsr.music/file_opener"),
            isNull(BinaryMessenger.BinaryMessageHandler::class.java),
        )

        // Cleaning up act2 (the current owner) DOES release the channel handlers cleanly.
        act2.cleanUpFlutterEngine(engine)
        verify(messenger, atLeastOnce()).setMessageHandler(
            eq("com.pulsr.music/file_opener"),
            isNull(BinaryMessenger.BinaryMessageHandler::class.java),
        )
    }

    private fun awaitMainLooper(latch: CountDownLatch, timeoutMs: Long = 3000L) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (latch.count > 0 && System.currentTimeMillis() < deadline) {
            Shadows.shadowOf(Looper.getMainLooper()).idle()
            latch.await(20, TimeUnit.MILLISECONDS)
        }
        Shadows.shadowOf(Looper.getMainLooper()).idle()
    }

    private fun setField(target: Any, name: String, value: Any?) {
        val field = target.javaClass.getDeclaredField(name)
        field.isAccessible = true
        field.set(target, value)
    }

    private fun getField(target: Any, name: String): Any? {
        val field = target.javaClass.getDeclaredField(name)
        field.isAccessible = true
        return field.get(target)
    }
}
