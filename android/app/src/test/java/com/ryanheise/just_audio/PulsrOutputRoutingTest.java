package com.ryanheise.just_audio;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import androidx.media3.exoplayer.ExoPlayer;

import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.lang.reflect.Field;
import java.util.Set;

/** Routing registry tests: no stale sinks, and one bad player cannot abort a route. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class PulsrOutputRoutingTest {

    private final ExoPlayer playerA = mock(ExoPlayer.class);
    private final ExoPlayer playerB = mock(ExoPlayer.class);

    @After
    public void tearDown() {
        PulsrOutputRouting.unregister(playerA);
        PulsrOutputRouting.unregister(playerB);
        PulsrOutputRouting.select(null);
    }

    @Test
    public void selectStillRoutesRemainingPlayersWhenOneThrows() {
        // Start from a known (null) preference so register() is not the call
        // that throws.
        PulsrOutputRouting.select(null);
        PulsrOutputRouting.register(playerA, false);
        PulsrOutputRouting.register(playerB, false);
        doThrow(new IllegalStateException("released"))
                .when(playerA).setPreferredAudioDevice(any());

        assertFalse(PulsrOutputRouting.select(null));
        verify(playerB, atLeastOnce()).setPreferredAudioDevice(null);
    }

    @Test
    public void observeAndUnobserveRemoveSinkReferences() throws Exception {
        // AAudioAudioSink is final and constructible without touching native
        // code, so it serves as a real registry member here.
        final AAudioAudioSink sink = new AAudioAudioSink(false, 50);
        PulsrOutputRouting.observe(sink);
        assertTrue(nativeSinks().contains(sink));
        PulsrOutputRouting.unobserve(sink);
        assertFalse(nativeSinks().contains(sink));
    }

    @Test
    public void decodedTelemetryIsPerPlayerAcrossDefaultAndAaudioAndClearsAtReset() throws Exception {
        androidx.media3.common.Format pcm24 = new androidx.media3.common.Format.Builder()
                .setSampleMimeType(androidx.media3.common.MimeTypes.AUDIO_RAW)
                .setSampleRate(44100).setChannelCount(2)
                .setPcmEncoding(androidx.media3.common.C.ENCODING_PCM_24BIT).build();
        androidx.media3.common.Format pcm16 = pcm24.buildUpon().setSampleRate(48000)
                .setPcmEncoding(androidx.media3.common.C.ENCODING_PCM_16BIT).build();
        androidx.media3.exoplayer.audio.AudioSink first = mock(androidx.media3.exoplayer.audio.AudioSink.class);
        androidx.media3.exoplayer.audio.AudioSink second = mock(androidx.media3.exoplayer.audio.AudioSink.class);
        PulsrAudioSink a = new PulsrAudioSink(org.robolectric.RuntimeEnvironment.getApplication(),
                () -> false, () -> false, () -> 50, () -> false, () -> playerA, p -> {}, null,
                (nativeMode, floatMode) -> new PulsrAudioSink.Inner(first, null, null, null));
        PulsrAudioSink b = new PulsrAudioSink(org.robolectric.RuntimeEnvironment.getApplication(),
                () -> true, () -> false, () -> 50, () -> false, () -> playerB, p -> {}, null,
                (nativeMode, floatMode) -> new PulsrAudioSink.Inner(second, null, null, null));
        a.configure(pcm24, 0, null);
        a.play();
        b.configure(pcm16, 0, null);
        org.junit.Assert.assertArrayEquals(new int[] {pcm24.pcmEncoding, 44100, 2},
                PulsrOutputRouting.decodedPcmSnapshot());
        org.junit.Assert.assertArrayEquals(new int[] {pcm16.pcmEncoding, 48000, 2},
                PulsrOutputRouting.decodedPcmSnapshot(playerB));
        b.play();
        org.junit.Assert.assertArrayEquals(new int[] {0, 0, 0}, PulsrOutputRouting.decodedPcmSnapshot());
        a.pause();
        org.junit.Assert.assertArrayEquals(new int[] {pcm16.pcmEncoding, 48000, 2},
                PulsrOutputRouting.decodedPcmSnapshot());
        b.reset();
        org.junit.Assert.assertArrayEquals(new int[] {0, 0, 0}, PulsrOutputRouting.decodedPcmSnapshot(playerB));
        a.release();
        b.release();
        org.junit.Assert.assertArrayEquals(new int[] {0, 0, 0}, PulsrOutputRouting.decodedPcmSnapshot());
    }

    @SuppressWarnings("unchecked")
    private static Set<AAudioAudioSink> nativeSinks() throws Exception {
        final Field field = PulsrOutputRouting.class.getDeclaredField("nativeSinks");
        field.setAccessible(true);
        return (Set<AAudioAudioSink>) field.get(null);
    }
}
