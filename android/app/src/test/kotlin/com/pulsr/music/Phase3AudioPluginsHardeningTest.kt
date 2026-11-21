package com.pulsr.music

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.media.AudioManager
import android.media.AudioRecord
import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.doThrow
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import java.io.File
import java.lang.reflect.Modifier
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class Phase3AudioPluginsHardeningTest {

    companion object {
        init {
            System.setProperty("net.bytebuddy.experimental", "true")
        }
    }

    @get:Rule
    val tempFolder = TemporaryFolder()

    // ---- Task 9: UsbSysfs decimal busnum/devnum parsing ----

    @Test
    fun usbSysfsMatchesDecimalDevnumAndBusnumTenAndAbove() {
        val sysfsRoot = tempFolder.newFolder("sys_usb_devices")
        writeSysfsDevice(sysfsRoot, "1-1", busnum = "1\n", devnum = "10\n", speed = "480\n")
        writeSysfsDevice(sysfsRoot, "1-2", busnum = "1\n", devnum = "16\n", speed = "12\n")
        writeSysfsDevice(sysfsRoot, "10-1", busnum = "10\n", devnum = "12\n", speed = "5000\n")
        writeSysfsDevice(sysfsRoot, "16-1", busnum = "16\n", devnum = "18\n", speed = "1.5\n")

        // devnum=10 must match sysfs devnum "10" (480 Mbps), not fail because 0x10 == 16.
        val dev10 = mockUsbDevice("/dev/bus/usb/001/010")
        assertEquals(mapOf("mbps" to 480.0), UsbSysfs.busSpeedMbps(dev10, sysfsRoot))

        // devnum=16 must match sysfs devnum "16" (12 Mbps), not sysfs "10" (0x10 == 16).
        val dev16 = mockUsbDevice("/dev/bus/usb/001/016")
        assertEquals(mapOf("mbps" to 12.0), UsbSysfs.busSpeedMbps(dev16, sysfsRoot))

        // busnum=10, devnum=12 must match decimal "10"/"12" (5000 Mbps), not "16"/"18".
        val bus10Dev12 = mockUsbDevice("/dev/bus/usb/010/012")
        assertEquals(mapOf("mbps" to 5000.0), UsbSysfs.busSpeedMbps(bus10Dev12, sysfsRoot))
    }

    @Test
    fun usbSysfsRejectsNonDecimalHexDigitsInBusnumOrDevnum() {
        val sysfsRoot = tempFolder.newFolder("sys_usb_hex")
        writeSysfsDevice(sysfsRoot, "1-hex", busnum = "1\n", devnum = "1a\n", speed = "480\n")

        // 0x1a == 26; decimal parser must reject "1a" rather than treating it as 26.
        val dev26 = mockUsbDevice("/dev/bus/usb/001/026")
        val result = UsbSysfs.busSpeedMbps(dev26, sysfsRoot)
        assertNull(result["mbps"])
        assertEquals("speed_not_published", result["detail"])
    }

    // ---- Task 10: AudioEffectsPlugin reverb lock, DVC rollback, DAC Voicing degraded ----

    @Test
    fun audioEffectsPluginUsesDedicatedReverbNativeLock() {
        val plugin = AudioEffectsPlugin()
        val stateLockField = AudioEffectsPlugin::class.java.getDeclaredField("stateLock").apply {
            isAccessible = true
        }
        val reverbLockField = AudioEffectsPlugin::class.java.getDeclaredField("reverbNativeLock").apply {
            isAccessible = true
        }
        assertNotSame(stateLockField.get(plugin), reverbLockField.get(plugin))
    }

    @Test
    fun dacVoicingDebugStatusReflectsAutoDegradedStageBit() {
        val plugin = AudioEffectsPlugin()

        plugin.autoDegradedStagesOverrideForTest = 0
        assertFalse(fetchDacVoicingDegradedFlag(plugin))

        // Clear cached debug report by toggling DAC voicing enabled, then set STAGE_DAC_VOICING.
        plugin.onMethodCall(
            MethodCall("setDacVoicingEnabled", mapOf("enabled" to true)),
            mock(MethodChannel.Result::class.java),
        )
        plugin.autoDegradedStagesOverrideForTest = AudioEffectsPlugin.STAGE_DAC_VOICING
        assertTrue(fetchDacVoicingDegradedFlag(plugin))

        // Unrelated degraded bit must not flag DAC Voicing as degraded.
        plugin.onMethodCall(
            MethodCall("setDacVoicingEnabled", mapOf("enabled" to false)),
            mock(MethodChannel.Result::class.java),
        )
        plugin.autoDegradedStagesOverrideForTest = AudioEffectsPlugin.STAGE_REVERB
        assertFalse(fetchDacVoicingDegradedFlag(plugin))
    }

    @Test
    fun dvcActivationRollsBackWhenSetStreamVolumeThrows() {
        val plugin = AudioEffectsPlugin()
        val app = RuntimeEnvironment.getApplication()
        val audioManager = mock(AudioManager::class.java)
        `when`(audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).thenReturn(15)
        `when`(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)).thenReturn(9)
        doThrow(SecurityException("DND restricted"))
            .`when`(audioManager)
            .setStreamVolume(AudioManager.STREAM_MUSIC, 15, 0)

        val mockContext = mock(Context::class.java)
        `when`(mockContext.getSystemService(Context.AUDIO_SERVICE)).thenReturn(audioManager)
        `when`(mockContext.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))
            .thenReturn(app.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))

        setField(plugin, "context", mockContext)
        setField(plugin, "dvcEnabled", true)
        setField(plugin, "dvcActive", false)
        setField(plugin, "dvcSavedSystemVolume", -1)
        setField(plugin, "dvcGain", 1.0)

        val activated = plugin.applyDvcRuntimeState(true)

        assertFalse(activated)
        assertEquals(false, getField(plugin, "dvcActive"))
        assertEquals(false, getField(plugin, "dvcEnabled"))
        assertEquals(-1, getField(plugin, "dvcSavedSystemVolume"))
        assertEquals(1.0, getField(plugin, "dvcGain"))
    }

    @Test
    fun dvcActivationSucceedsAndPinsVolumeWhenSetStreamVolumeSucceeds() {
        val plugin = AudioEffectsPlugin()
        val app = RuntimeEnvironment.getApplication()
        val audioManager = mock(AudioManager::class.java)
        `when`(audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).thenReturn(15)
        `when`(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)).thenReturn(9)

        val mockContext = mock(Context::class.java)
        `when`(mockContext.getSystemService(Context.AUDIO_SERVICE)).thenReturn(audioManager)
        `when`(mockContext.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))
            .thenReturn(app.getSharedPreferences("pulsr_dvc_prefs", Context.MODE_PRIVATE))

        setField(plugin, "context", mockContext)
        setField(plugin, "dvcEnabled", true)
        setField(plugin, "dvcActive", false)

        val activated = plugin.applyDvcRuntimeState(true)

        assertTrue(activated)
        assertEquals(true, getField(plugin, "dvcActive"))
        assertEquals(true, getField(plugin, "dvcEnabled"))
        assertEquals(9, getField(plugin, "dvcSavedSystemVolume"))
        assertEquals(9.0 / 15.0, getField(plugin, "dvcGain") as Double, 1e-9)
        verify(audioManager).setStreamVolume(AudioManager.STREAM_MUSIC, 15, 0)
    }

    // ---- Task 11: HiResDacPlugin off-main-thread dispatch & disposed guards ----

    @Test
    fun hiResDacProbeMethodsDispatchOffMainThreadAndReplyOnMainHandler() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = HiResDacPlugin(ctx, messenger)
        try {
            val cases = listOf(
                MethodCall("setBitPerfectMode", mapOf("enabled" to true)),
                MethodCall("setBitPerfectModeDetailed", mapOf("enabled" to true)),
                MethodCall("getBluetoothCodecInfo", null),
                MethodCall("getDirectCapabilities", null),
                MethodCall("getUsbDacCapabilities", null),
            )

            val replies = mutableMapOf<String, Any?>()
            for (call in cases) {
                val latch = CountDownLatch(1)
                val result = mock(MethodChannel.Result::class.java)
                doAnswer { invocation ->
                    replies[call.method] = invocation.getArgument(0)
                    latch.countDown()
                    null
                }.`when`(result).success(any())

                plugin.onMethodCall(call, result)
                // Because replies are posted back onto mainHandler from probeHandler,
                // nothing should have replied synchronously before the main looper idles.
                verifyNoInteractions(result)

                awaitWithMainLooperIdle(latch)
                assertTrue("Timed out awaiting ${call.method}", latch.await(0, TimeUnit.MILLISECONDS))
                verify(result).success(any())
            }

            assertEquals(false, replies["setBitPerfectMode"])
            val detailed = replies["setBitPerfectModeDetailed"] as Map<*, *>
            assertEquals(false, detailed["success"])
            assertTrue(detailed.containsKey("reason"))
            assertTrue(detailed.containsKey("sinkBitDepth"))
            assertTrue(detailed.containsKey("sinkSampleRate"))
            assertTrue(replies["getBluetoothCodecInfo"] is Map<*, *>)
            val direct = replies["getDirectCapabilities"] as Map<*, *>
            assertTrue(direct["directFormats"] is List<*>)
            val usbDac = replies["getUsbDacCapabilities"] as Map<*, *>
            assertTrue(usbDac.containsKey("usbAudioClass"))
            assertTrue(usbDac.containsKey("usbDacLabel"))
        } finally {
            plugin.dispose()
        }
    }

    @Test
    fun hiResDacDisposedGuardsBlockRoutePollAndNotifyRunnable() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = HiResDacPlugin(ctx, messenger)
        val sink = mock(EventChannel.EventSink::class.java)

        plugin.dispose()
        // Even if an eventSink were somehow still visible, disposed=true must short-circuit.
        setField(plugin, "eventSink", sink)

        val routePoll = getField(plugin, "routePoll") as Runnable
        val notifyRunnable = getField(plugin, "notifyRunnable") as Runnable
        routePoll.run()
        notifyRunnable.run()
        Shadows.shadowOf(Looper.getMainLooper()).idle()

        verifyNoInteractions(sink)
    }

    @Test
    fun hiResDacTargetOutputFormatOffloadsToProbeThreadWhenBitPerfectRequestedAndPreservesFastPaths() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = HiResDacPlugin(ctx, messenger)
        try {
            // 1. Invalid formats fail synchronously with INVALID_FORMAT
            val invalidResult = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("setTargetOutputFormat", mapOf("sampleRate" to 12345, "bitDepth" to 16)),
                invalidResult,
            )
            verify(invalidResult).error("INVALID_FORMAT", "Unsupported target sample rate or bit depth", null)

            // 2. When !bitPerfectRequested and non-zero format, returns false synchronously
            setField(plugin, "bitPerfectRequested", false)
            val nonZeroWithoutBpResult = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("setTargetOutputFormat", mapOf("sampleRate" to 96000, "bitDepth" to 24)),
                nonZeroWithoutBpResult,
            )
            verify(nonZeroWithoutBpResult).success(false)

            // 3. Fast-path when format is unchanged and mixerAttributesApplied == true
            setField(plugin, "bitPerfectRequested", true)
            setField(plugin, "targetSampleRate", 96000)
            setField(plugin, "targetBitDepth", 24)
            setField(plugin, "mixerAttributesApplied", true)
            val unchangedResult = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(
                MethodCall("configureTargetAudio", mapOf("sampleRate" to 96000, "bitDepth" to 24)),
                unchangedResult,
            )
            verify(unchangedResult).success(true)

            // 4. When bitPerfectRequested == true, dispatches asynchronously to probeHandler
            // and replies on mainHandler (not synchronously)
            setField(plugin, "targetSampleRate", 48000)
            setField(plugin, "targetBitDepth", 16)
            setField(plugin, "mixerAttributesApplied", false)
            setField(plugin, "bitPerfectRequested", true)

            for (method in listOf("setTargetOutputFormat", "configureTargetAudio")) {
                val asyncResult = mock(MethodChannel.Result::class.java)
                val latch = CountDownLatch(1)
                var reply: Any? = null
                doAnswer { invocation ->
                    reply = invocation.getArgument(0)
                    latch.countDown()
                    null
                }.`when`(asyncResult).success(any())

                plugin.onMethodCall(
                    MethodCall(method, mapOf("sampleRate" to 96000, "bitDepth" to 24)),
                    asyncResult,
                )
                // Nothing should have replied synchronously before the probe & main loopers run
                verifyNoInteractions(asyncResult)

                awaitWithMainLooperIdle(latch)
                assertTrue("Timed out awaiting $method async completion", latch.await(0, TimeUnit.MILLISECONDS))
                verify(asyncResult).success(any())
                assertTrue("Reply must be a Boolean", reply is Boolean)
            }
        } finally {
            plugin.dispose()
        }
    }

    // ---- Task 12: RoomCorrectionPlugin volatile eventSink & stop->join->release order ----

    @Test
    fun roomCorrectionEventSinkIsVolatile() {
        val field = RoomCorrectionPlugin::class.java.getDeclaredField("eventSink")
        assertTrue(
            "RoomCorrectionPlugin.eventSink must be @Volatile",
            Modifier.isVolatile(field.modifiers),
        )
    }

    @Test
    fun roomCorrectionStopRecordingStopsAndJoinsCaptureThreadBeforeRelease() {
        val ctor = RoomCorrectionPlugin::class.java.getDeclaredConstructor(Context::class.java).apply {
            isAccessible = true
        }
        val plugin = ctor.newInstance(RuntimeEnvironment.getApplication())
        try {
            val events = Collections.synchronizedList(mutableListOf<String>())
            val stopCalledLatch = CountDownLatch(1)
            val releasedLatch = CountDownLatch(1)

            val mockRecord = mock(AudioRecord::class.java)
            doAnswer {
                events.add("stop")
                stopCalledLatch.countDown()
                null
            }.`when`(mockRecord).stop()
            doAnswer {
                events.add("release")
                releasedLatch.countDown()
                null
            }.`when`(mockRecord).release()

            val fakeCaptureThread = Thread {
                while (stopCalledLatch.count > 0) {
                    try {
                        stopCalledLatch.await(2, TimeUnit.SECONDS)
                    } catch (_: InterruptedException) {}
                }
                events.add("thread_exited")
            }.apply { start() }

            setField(plugin, "audioRecord", mockRecord)
            setField(plugin, "captureThread", fakeCaptureThread)
            (getField(plugin, "capturing") as AtomicBoolean).set(true)

            val stopMethod = RoomCorrectionPlugin::class.java.getDeclaredMethod(
                "stopRecording",
                AudioRecord::class.java,
            ).apply { isAccessible = true }
            stopMethod.invoke(plugin, *arrayOfNulls<Any>(1))

            assertTrue("Timed out waiting for release()", releasedLatch.await(3, TimeUnit.SECONDS))
            assertEquals(listOf("stop", "thread_exited", "release"), events.toList())
        } finally {
            plugin.cleanup()
        }
    }

    // ---- Task 13: UsbExclusivePlugin hardwareVolume no-fallback & incremental silence sleep ----

    @Test
    fun usbExclusiveAwaitQuirkSilenceSleepsIn50msIncrementsAndAbortsOnDetachOrDispose() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = UsbExclusivePlugin(ctx, messenger)
        try {
            // 1. Stays attached across full 120ms -> slices [50, 50, 20].
            val fullSlices = mutableListOf<Long>()
            assertTrue(
                plugin.awaitQuirkSilence(
                    silenceMs = 120,
                    stepMs = 50L,
                    sleepFn = { fullSlices.add(it) },
                    isAttached = { true },
                    isDisposed = { false },
                ),
            )
            assertEquals(listOf(50L, 50L, 20L), fullSlices)

            // 2. Detaches after 2nd 50ms slice -> aborts before sleeping remaining 150ms.
            val detachSlices = mutableListOf<Long>()
            assertFalse(
                plugin.awaitQuirkSilence(
                    silenceMs = 250,
                    stepMs = 50L,
                    sleepFn = { detachSlices.add(it) },
                    isAttached = { detachSlices.size < 2 },
                    isDisposed = { false },
                ),
            )
            assertEquals(listOf(50L, 50L), detachSlices)

            // 3. Disposed after 1st slice -> aborts immediately.
            val disposeSlices = mutableListOf<Long>()
            assertFalse(
                plugin.awaitQuirkSilence(
                    silenceMs = 250,
                    stepMs = 50L,
                    sleepFn = { disposeSlices.add(it) },
                    isAttached = { true },
                    isDisposed = { disposeSlices.size >= 1 },
                ),
            )
            assertEquals(listOf(50L), disposeSlices)
        } finally {
            plugin.dispose()
        }
    }

    @Test
    fun usbExclusiveSetUac2HardwareVolumeTrustsHardwareVolumeFailureWithoutFallbackLoop() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val plugin = UsbExclusivePlugin(ctx, messenger)
        try {
            val mockDevice = mock(UsbDevice::class.java)
            `when`(mockDevice.deviceId).thenReturn(42)
            val mockUsbManager = mock(UsbManager::class.java)
            `when`(mockUsbManager.hasPermission(mockDevice)).thenReturn(true)
            `when`(mockUsbManager.deviceList).thenReturn(hashMapOf("dac" to mockDevice))

            val mockConn = mock(UsbDeviceConnection::class.java)
            val featureUnit = UsbAudioControlParser.FeatureUnitVolume(
                unitId = 2,
                interfaceNumber = 0,
                channels = 2,
                volumeOnMaster = true,
            )
            val parsed = UsbAudioControlParser.Result(
                uacVersion = UsbAudioControlParser.UAC2,
                volumeUnit = featureUnit,
                streamingInterface = 1,
                controlInterface = 0,
            )
            // Transport that refuses every write so hardwareVolume.setDb(...) returns false.
            val refusingTransfer = UsbControlTransfer { _, _, _, _, _ -> -1 }
            val hwVol = UsbHardwareVolume(UsbAudioControlParser.UAC2, featureUnit, refusingTransfer)

            val rangeClass = Class.forName("com.pulsr.music.UsbExclusivePlugin\$Uac2RangeSnapshot")
            val rangeCtor = rangeClass.getDeclaredConstructor(
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                List::class.java,
                Boolean::class.javaPrimitiveType,
            ).apply { isAccessible = true }
            val rangeSnapshot = rangeCtor.newInstance(-15360, 0, 256, 2, 0, listOf(0), true)

            setField(plugin, "usbManager", mockUsbManager)
            setField(plugin, "openedDevice", mockDevice)
            setField(plugin, "connection", mockConn)
            setField(plugin, "parsedResult", parsed)
            setField(plugin, "hardwareVolume", hwVol)
            setField(plugin, "uac2RangeSnapshot", rangeSnapshot)
            setField(plugin, "uac2RangeDeviceId", 42)

            val setVolMethod = UsbExclusivePlugin::class.java.getDeclaredMethod(
                "setUac2HardwareVolumeInternal",
                Double::class.javaPrimitiveType,
            ).apply { isAccessible = true }
            val ok = setVolMethod.invoke(plugin, 0.5) as Boolean

            assertFalse(ok)
            // Must NOT fall through to a raw controlTransfer UAC_SET_CUR loop on mockConn.
            verify(mockConn, never()).controlTransfer(
                anyInt(), anyInt(), anyInt(), anyInt(), any(), anyInt(), anyInt(),
            )
        } finally {
            plugin.dispose()
        }
    }

    // ---- Task 14: VisualizerPlugin in-flight gate & cleanup reference clearing ----

    @Test
    fun visualizerPluginDropsOverlappingFftFramesAndClearsReferencesOnCleanup() {
        val plugin = VisualizerPlugin()
        val sink = mock(EventChannel.EventSink::class.java)
        val emittedLatch = CountDownLatch(1)
        doAnswer {
            emittedLatch.countDown()
            null
        }.`when`(sink).success(any())

        setField(plugin, "appContext", RuntimeEnvironment.getApplication())
        plugin.onListen(null, sink)

        // Occupy the single-threaded FFT executor so the first dispatched FFT job stays in-flight.
        val executor = getField(plugin, "fftExecutor") as ExecutorService
        val blockerStarted = CountDownLatch(1)
        val releaseBlocker = CountDownLatch(1)
        executor.execute {
            blockerStarted.countDown()
            releaseBlocker.await(3, TimeUnit.SECONDS)
        }
        assertTrue(blockerStarted.await(2, TimeUnit.SECONDS))

        val sampleFft = ByteArray(16) { it.toByte() }
        assertTrue("First FFT frame should be accepted", plugin.dispatchFftFrame(sampleFft))
        assertFalse("Second FFT frame while first is in-flight must be dropped", plugin.dispatchFftFrame(sampleFft))

        releaseBlocker.countDown()
        awaitWithMainLooperIdle(emittedLatch)
        assertTrue("First FFT frame should emit to sink", emittedLatch.await(0, TimeUnit.MILLISECONDS))
        verify(sink, times(1)).success(any())

        // Wait for the single-threaded executor to finish the first job's finally { fftInFlight.set(false) }.
        val drained = CountDownLatch(1)
        executor.execute { drained.countDown() }
        assertTrue("FFT executor should drain cleanly", drained.await(2, TimeUnit.SECONDS))

        // After the first job completes, the gate must open for subsequent frames.
        assertTrue("Subsequent FFT frame should be accepted after completion", plugin.dispatchFftFrame(sampleFft))

        plugin.cleanup()
        assertNull(getField(plugin, "eventSink"))
        assertNull(getField(plugin, "appContext"))
    }

    // ---- Helpers ----

    private fun writeSysfsDevice(root: File, name: String, busnum: String, devnum: String, speed: String) {
        val dir = File(root, name).apply { mkdirs() }
        File(dir, "busnum").writeText(busnum)
        File(dir, "devnum").writeText(devnum)
        File(dir, "speed").writeText(speed)
    }

    private fun mockUsbDevice(deviceName: String): UsbDevice {
        val device = mock(UsbDevice::class.java)
        `when`(device.deviceName).thenReturn(deviceName)
        return device
    }

    private fun fetchDacVoicingDegradedFlag(plugin: AudioEffectsPlugin): Boolean {
        val result = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("getDspDebugStatus", null), result)
        val captor = ArgumentCaptor.forClass(Map::class.java)
        verify(result).success(captor.capture())
        val stages = captor.value["stages"] as List<*>
        val dacStage = stages
            .map { it as Map<*, *> }
            .first { it["name"] == "DAC Voicing (Oversampled Reconstruction)" }
        return dacStage["isDegraded"] as Boolean
    }

    private fun awaitWithMainLooperIdle(latch: CountDownLatch, timeoutMs: Long = 3000L) {
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
