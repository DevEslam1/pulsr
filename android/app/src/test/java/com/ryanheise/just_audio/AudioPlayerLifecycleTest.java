package com.ryanheise.just_audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import androidx.media3.common.C;
import androidx.media3.exoplayer.ExoPlayer;

import java.util.ArrayList;
import java.util.List;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.lang.reflect.Field;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/** Output-toggle/dispose lifecycle: no ExoPlayer teardown, no dropped Results. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class AudioPlayerLifecycleTest {

    private static int nextId = 0;

    private static AudioPlayer newPlayer() {
        return new AudioPlayer(
                RuntimeEnvironment.getApplication(),
                mock(BinaryMessenger.class),
                "lifecycle-" + (++nextId),
                null,
                null,
                null,
                false,
                false);
    }

    private static AudioPlayer newProbeAcceptingPlayer() {
        return new AudioPlayer(
                RuntimeEnvironment.getApplication(),
                mock(BinaryMessenger.class),
                "lifecycle-probe-" + (++nextId),
                null,
                null,
                null,
                false,
                false) {
            @Override
            boolean isAaudioOutputSupported() {
                return true;
            }

            @Override
            boolean probeAaudioOutput(int sampleRate, int channels, int targetBufferMs,
                    boolean preferExclusive) {
                return true;
            }
        };
    }

    private static void setField(Object target, String name, Object value)
            throws Exception {
        final Field field = AudioPlayer.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(target, value);
    }

    private static Object getField(Object target, String name) throws Exception {
        final Field field = AudioPlayer.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static Map<String, Object> aaudioArgs() {
        final Map<String, Object> args = new HashMap<>();
        args.put("enabled", true);
        args.put("preferExclusive", true);
        args.put("targetBufferMs", 150);
        // A concrete rate skips the second-rate native probe.
        args.put("sampleRate", 48000);
        return args;
    }

    @Test
    public void floatToggleBeforeInitializationIsRememberedWithoutBuildingPlayer()
            throws Exception {
        final AudioPlayer player = newPlayer();
        final MethodChannel.Result result = mock(MethodChannel.Result.class);

        player.onMethodCall(new MethodCall("dspSetFloatOutput",
                Collections.singletonMap("enabled", true)), result);

        verify(result).success(true);
        assertNull(getField(player, "player"));
    }

    @Test
    public void floatToggleDuringLoadDoesNotReleasePlayerOrDropPrepareResult()
            throws Exception {
        final AudioPlayer player = newPlayer();
        final ExoPlayer exo = mock(ExoPlayer.class);
        final OutputSinkControl sink = mock(OutputSinkControl.class);
        final MethodChannel.Result prepareResult = mock(MethodChannel.Result.class);
        setField(player, "player", exo);
        setField(player, "sinkWrapper", sink);
        setField(player, "processingState", AudioPlayer.ProcessingState.loading);
        setField(player, "prepareResult", prepareResult);
        final MethodChannel.Result result = mock(MethodChannel.Result.class);

        player.onMethodCall(new MethodCall("dspSetFloatOutput",
                Collections.singletonMap("enabled", true)), result);

        verify(sink).requestModeChange();
        verify(exo, never()).release();
        verify(prepareResult, never()).success(any());
        verify(prepareResult, never()).error(anyString(), anyString(), any());
        verify(result).success(true);
    }

    @Test
    public void aaudioToggleSwapsSinkWithoutReleasingPlayer() throws Exception {
        final AudioPlayer player = newProbeAcceptingPlayer();
        final ExoPlayer exo = mock(ExoPlayer.class);
        final OutputSinkControl sink = mock(OutputSinkControl.class);
        final MethodChannel.Result prepareResult = mock(MethodChannel.Result.class);
        setField(player, "player", exo);
        setField(player, "sinkWrapper", sink);
        setField(player, "processingState", AudioPlayer.ProcessingState.loading);
        setField(player, "prepareResult", prepareResult);
        final MethodChannel.Result result = mock(MethodChannel.Result.class);

        player.onMethodCall(new MethodCall("dspSetAaudioOutput", aaudioArgs()), result);

        verify(sink).requestModeChange(false);
        verify(exo, never()).release();
        verify(prepareResult, never()).success(any());
        verify(result).success(true);
    }

    @Test
    public void disposeCompletesPendingSeekResult() throws Exception {
        final AudioPlayer player = newPlayer();
        final MethodChannel.Result seekResult = mock(MethodChannel.Result.class);
        setField(player, "seekResult", seekResult);

        player.dispose();

        verify(seekResult).success(any());
    }

    @Test
    public void disposeReleasesPlayerAndSinkWrapper() throws Exception {
        final AudioPlayer player = newPlayer();
        final ExoPlayer exo = mock(ExoPlayer.class);
        final OutputSinkControl sink = mock(OutputSinkControl.class);
        setField(player, "player", exo);
        setField(player, "sinkWrapper", sink);

        player.dispose();
        player.dispose();

        verify(exo).release();
        verify(sink).release();
    }

    @Test
    public void aaudioProbePrefersCompatibleEncodingAndFallsBackFromRejectedFormats()
            throws Exception {
        final List<Integer> probedEncodings = new ArrayList<>();
        final AudioPlayer player = new AudioPlayer(
                RuntimeEnvironment.getApplication(),
                mock(BinaryMessenger.class),
                "lifecycle-enc-" + (++nextId),
                null,
                null,
                null,
                false,
                false) {
            @Override
            boolean isAaudioOutputSupported() {
                return true;
            }

            @Override
            int probeSingleAaudioEncoding(int sampleRate, int channels, int nativeEncoding,
                    int targetBufferMs, boolean preferExclusive) {
                probedEncodings.add(nativeEncoding);
                return nativeEncoding == AaudioNativeBridge.ENCODING_PCM_I16 ? 1 : 0;
            }
        };

        final Map<String, Object> args = aaudioArgs();
        args.put("pcmEncoding", C.ENCODING_PCM_FLOAT);
        final MethodChannel.Result result = mock(MethodChannel.Result.class);
        player.onMethodCall(new MethodCall("dspSetAaudioOutput", args), result);

        verify(result).success(true);
        assertEquals(2, probedEncodings.size());
        assertEquals(Integer.valueOf(AaudioNativeBridge.ENCODING_PCM_FLOAT),
                probedEncodings.get(0));
        assertEquals(Integer.valueOf(AaudioNativeBridge.ENCODING_PCM_I16),
                probedEncodings.get(1));
        assertEquals(Boolean.TRUE, getField(player, "aaudioOutputEnabled"));
    }

    @Test
    public void tapSrcFailureLatchesZeroRateUntilDifferentRateOrDispose() throws Exception {
        final AudioPlayer player = newPlayer();
        final List<Integer> firstRates = new ArrayList<>();
        final NativeDspAudioProcessor first = new NativeDspAudioProcessor() {
            @Override
            public void setTapSrcTargetRate(int rate) {
                super.setTapSrcTargetRate(rate);
                firstRates.add(rate);
            }
        };
        final List<Integer> secondRates = new ArrayList<>();
        final NativeDspAudioProcessor second = new NativeDspAudioProcessor() {
            @Override
            public void setTapSrcTargetRate(int rate) {
                super.setTapSrcTargetRate(rate);
                secondRates.add(rate);
            }
        };
        player.onActiveDspProcessorChanged(first);

        player.onMethodCall(new MethodCall("dspSetTapSrcRate",
                Collections.singletonMap("rate", 96000)), mock(MethodChannel.Result.class));
        assertEquals(96000, first.getTapSrcTargetRate());

        // Once tap-SRC fails, current/subsequent processors and same-rate re-sends force 0.
        player.onTapSrcFailed(new RuntimeException("tap src failed"));
        assertEquals(0, first.getTapSrcTargetRate());

        player.onActiveDspProcessorChanged(second);
        assertEquals(0, second.getTapSrcTargetRate());

        player.onMethodCall(new MethodCall("dspSetTapSrcRate",
                Collections.singletonMap("rate", 96000)), mock(MethodChannel.Result.class));
        assertEquals(java.util.Arrays.asList(0, 0), secondRates);

        // Sending a different rate clears the latch and applies the new rate.
        player.onMethodCall(new MethodCall("dspSetTapSrcRate",
                Collections.singletonMap("rate", 48000)), mock(MethodChannel.Result.class));
        assertEquals(48000, second.getTapSrcTargetRate());

        // Dispose also clears the latch.
        player.onTapSrcFailed(new RuntimeException("tap src failed again"));
        assertEquals(Boolean.TRUE, getField(player, "tapSrcFailed"));
        player.dispose();
        assertEquals(Boolean.FALSE, getField(player, "tapSrcFailed"));
    }
}
