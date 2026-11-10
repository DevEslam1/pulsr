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
}
