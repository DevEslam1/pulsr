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
        PulsrOutputRouting.register(playerA);
        PulsrOutputRouting.register(playerB);
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

    @Test
    @SuppressWarnings("unchecked")
    public void decodedOwnersUsesWeakReferencesAndPrunesClearedEntries() throws Exception {
        final androidx.media3.exoplayer.audio.AudioSink inner =
                mock(androidx.media3.exoplayer.audio.AudioSink.class);
        final PulsrAudioSink sink = new PulsrAudioSink(
                org.robolectric.RuntimeEnvironment.getApplication(),
                () -> false, () -> false, () -> 50, () -> false, () -> playerA, p -> {}, null,
                (nativeMode, floatMode) -> new PulsrAudioSink.Inner(inner, null, null, null));
        final androidx.media3.common.Format pcm16 = new androidx.media3.common.Format.Builder()
                .setSampleMimeType(androidx.media3.common.MimeTypes.AUDIO_RAW)
                .setSampleRate(48000).setChannelCount(2)
                .setPcmEncoding(androidx.media3.common.C.ENCODING_PCM_16BIT).build();
        sink.configure(pcm16, 0, null);

        final Field ownersField = PulsrOutputRouting.class.getDeclaredField("decodedOwners");
        ownersField.setAccessible(true);
        final java.util.Map<PulsrAudioSink, java.lang.ref.WeakReference<ExoPlayer>> owners =
                (java.util.Map<PulsrAudioSink, java.lang.ref.WeakReference<ExoPlayer>>)
                        ownersField.get(null);
        assertTrue(owners.get(sink) instanceof java.lang.ref.WeakReference);
        assertTrue(owners.get(sink).get() == playerA);

        // Simulate GC clearing the ExoPlayer reference; snapshot must prune the entry.
        owners.put(sink, new java.lang.ref.WeakReference<>(null));
        org.junit.Assert.assertArrayEquals(new int[] {0, 0, 0},
                PulsrOutputRouting.decodedPcmSnapshot(playerA));
        assertFalse(owners.containsKey(sink));
        sink.release();
    }

    @Test
    public void capturingAudioOutputProviderCapturesAudioTrackBeforeReflection() throws Exception {
        final android.content.Context context = org.robolectric.RuntimeEnvironment.getApplication();
        final PulsrOutputRouting.CapturingAudioOutputProvider provider =
                PulsrOutputRouting.createCapturingOutputProvider(context);
        final androidx.media3.exoplayer.audio.DefaultAudioSink sink =
                new androidx.media3.exoplayer.audio.DefaultAudioSink.Builder(context)
                        .setAudioOutputProvider(provider)
                        .build();
        PulsrOutputRouting.observe(sink, provider);
        try {
            final androidx.media3.exoplayer.audio.AudioOutputProvider.OutputConfig config =
                    new androidx.media3.exoplayer.audio.AudioOutputProvider.OutputConfig.Builder()
                            .setEncoding(androidx.media3.common.C.ENCODING_PCM_16BIT)
                            .setSampleRate(48000)
                            .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_STEREO)
                            .setBufferSize(4096)
                            .build();
            final androidx.media3.exoplayer.audio.AudioOutput output = provider.getAudioOutput(config);
            assertTrue(output instanceof androidx.media3.exoplayer.audio.AudioTrackAudioOutput);
            final android.media.AudioTrack captured = provider.getCapturedTrack();
            org.junit.Assert.assertNotNull(captured);
            assertTrue(captured == ((androidx.media3.exoplayer.audio.AudioTrackAudioOutput) output).getAudioTrack());
            org.junit.Assert.assertArrayEquals(
                    new int[] {0, 48000, android.media.AudioFormat.ENCODING_PCM_16BIT},
                    PulsrOutputRouting.snapshot());

            output.release();
            provider.release();
            org.junit.Assert.assertNull(provider.getCapturedTrack());
        } finally {
            PulsrOutputRouting.unobserve(sink);
            sink.release();
        }
    }
}
