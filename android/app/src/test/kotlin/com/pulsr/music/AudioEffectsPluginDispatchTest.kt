package com.pulsr.music

import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoMoreInteractions
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.TIRAMISU])
class AudioEffectsPluginDispatchTest {
    @Test
    fun dacVoicingDefaultsReachTheNativeDspHandlers() {
        val plugin = AudioEffectsPlugin()
        val paramsResult = mock(MethodChannel.Result::class.java)
        val enabledResult = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(
            MethodCall("setDacVoicingParams", mapOf("character" to 0, "voicingAmount" to 0.0)),
            paramsResult,
        )
        plugin.onMethodCall(
            MethodCall("setDacVoicingEnabled", mapOf("enabled" to false)),
            enabledResult,
        )

        verify(paramsResult).success(true)
        verify(enabledResult).success(true)
        verifyNoMoreInteractions(paramsResult, enabledResult)
    }

    @Test
    fun bitPerfectBypassIsNotVetoedByExternalSystemEffects() {
        val plugin = AudioEffectsPlugin()

        // No native engine and no vendor effect controller in this process: the
        // only thing that could refuse is an app-owned HAL stage, and there is
        // none. An external/unknown system-effect verdict must never turn a
        // request the app itself applied into a failure (that was the bug: OEM
        // phones and the "leave on" policy could never enable Bit-Perfect).
        val enable = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(
            MethodCall("setBypassDspForBitPerfect", mapOf("bypass" to true)),
            enable,
        )
        verify(enable).success(true)
        verifyNoMoreInteractions(enable)

        val disable = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(
            MethodCall("setBypassDspForBitPerfect", mapOf("bypass" to false)),
            disable,
        )
        verify(disable).success(true)
        verifyNoMoreInteractions(disable)
    }

    @Test
    @Config(sdk = [34])
    fun hiResDacAndUsbPluginsFailClosedWithoutCapabilitiesOrHardware() {
        val ctx = RuntimeEnvironment.getApplication()
        val messenger = mock(BinaryMessenger::class.java)
        val hires = HiResDacPlugin(ctx, messenger)

        // Android 14+ without confirmed mixer attributes or direct USB stream
        // must report bit-perfect unsupported rather than an optimistic true.
        val supportedResult = mock(MethodChannel.Result::class.java)
        hires.onMethodCall(MethodCall("isBitPerfectSupported", null), supportedResult)
        verify(supportedResult).success(false)

        // DoP/Native DSD probe must never infer nativeDsd without kernel/raw DSD
        // support and must report dop=false with no USB DAC attached.
        val dopResult = mock(MethodChannel.Result::class.java)
        hires.onMethodCall(MethodCall("getDopCapabilities", null), dopResult)
        val dopCaptor = ArgumentCaptor.forClass(Map::class.java)
        verify(dopResult).success(dopCaptor.capture())
        val dopMap = dopCaptor.value
        assertEquals(false, dopMap["dop"])
        assertEquals(false, dopMap["nativeDsd"])

        // resetHardwareVolume cleanly reports no_device instead of dropping Result.
        val usb = UsbExclusivePlugin(ctx, messenger)
        val latch = CountDownLatch(1)
        val resetResult = mock(MethodChannel.Result::class.java)
        doAnswer {
            latch.countDown()
            null
        }.`when`(resetResult).success(any())
        usb.onMethodCall(MethodCall("resetHardwareVolume", null), resetResult)
        val deadline = System.currentTimeMillis() + 3000
        while (latch.count > 0 && System.currentTimeMillis() < deadline) {
            Shadows.shadowOf(Looper.getMainLooper()).idle()
            latch.await(20, TimeUnit.MILLISECONDS)
        }
        assertTrue(latch.await(0, TimeUnit.MILLISECONDS))
        val resetCaptor = ArgumentCaptor.forClass(Map::class.java)
        verify(resetResult).success(resetCaptor.capture())
        assertNotNull(resetCaptor.value["error"])
        assertFalse(resetCaptor.value.isEmpty())
    }

    @Test
    fun custodyReportAndTelemetryFallbackReportHonestZeroAndNineteenSlots() {
        val plugin = AudioEffectsPlugin()

        val custodyResult = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("getChainOfCustodyReport", null), custodyResult)
        val custodyCaptor = ArgumentCaptor.forClass(Map::class.java)
        verify(custodyResult).success(custodyCaptor.capture())
        assertEquals(0, custodyCaptor.value["bufferSize"])

        val telemetryResult = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("getTelemetry", null), telemetryResult)
        val telemetryCaptor = ArgumentCaptor.forClass(List::class.java)
        verify(telemetryResult).success(telemetryCaptor.capture())
        assertEquals(19, telemetryCaptor.value.size)
    }

    @Test
    fun systemAudioEffectsControllerRestoresPriorEnabledStateOnRelease() {
        val ctx = RuntimeEnvironment.getApplication()
        val controller = SystemAudioEffectsController(ctx)

        class FakeHandle(override var enabled: Boolean) : SystemAudioEffectsController.ManagedEffectHandle {
            var released = false
            override fun hasControl(): Boolean = true
            override fun release() {
                released = true
            }
        }

        val wasEnabledEffect = FakeHandle(enabled = false)
        val wasDisabledEffect = FakeHandle(enabled = false)

        controller.registerManagedEffectForTesting(wasEnabledEffect, priorEnabled = true)
        controller.registerManagedEffectForTesting(wasDisabledEffect, priorEnabled = false)

        controller.release()

        assertEquals(true, wasEnabledEffect.enabled)
        assertEquals(true, wasEnabledEffect.released)
        assertEquals(false, wasDisabledEffect.enabled)
        assertEquals(true, wasDisabledEffect.released)
    }
}
