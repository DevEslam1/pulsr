package com.pulsr.music

import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoMoreInteractions
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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
}
