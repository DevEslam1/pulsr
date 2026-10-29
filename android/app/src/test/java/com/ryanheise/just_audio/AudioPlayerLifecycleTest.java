package com.ryanheise.just_audio;

import static org.junit.Assert.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import androidx.media3.exoplayer.ExoPlayer;

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
}
