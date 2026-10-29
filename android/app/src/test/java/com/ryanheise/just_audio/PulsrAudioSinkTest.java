package com.ryanheise.just_audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.exoplayer.audio.AudioSink;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Lifecycle tests for the swappable sink (no ExoPlayer required). */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class PulsrAudioSinkTest {

    private static final Format FORMAT = new Format.Builder()
            .setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setSampleRate(48000)
            .setChannelCount(2)
            .setPcmEncoding(C.ENCODING_PCM_16BIT)
            .build();

    private static final class Flag implements PulsrAudioSink.BooleanFlag {
        boolean value;
        Flag(boolean value) { this.value = value; }
        @Override public boolean get() { return value; }
    }

    private static final class IntValue implements PulsrAudioSink.IntFlag {
        int value;
        IntValue(int value) { this.value = value; }
        @Override public int get() { return value; }
    }

    private static final class Fallbacks implements PulsrAudioSink.FallbackListener {
        final Flag aaudio;
        final Flag floatMode;
        int aaudioRejected;
        int floatRejected;

        Fallbacks(Flag aaudio, Flag floatMode) {
            this.aaudio = aaudio;
            this.floatMode = floatMode;
        }

        @Override public void onAaudioRejected(String reason, Exception cause) {
            aaudioRejected++;
            aaudio.value = false;
        }

        @Override public void onFloatRejected(String reason, Exception cause) {
            floatRejected++;
            floatMode.value = false;
        }
    }

    private static final class Factory implements PulsrAudioSink.InnerFactory {
        final ArrayDeque<PulsrAudioSink.Inner> queue = new ArrayDeque<>();
        final List<Boolean> requestedAaudio = new ArrayList<>();
        final List<Boolean> requestedFloat = new ArrayList<>();

        @Override public PulsrAudioSink.Inner create(boolean aaudio, boolean floatMode) {
            requestedAaudio.add(aaudio);
            requestedFloat.add(floatMode);
            if (queue.isEmpty()) throw new AssertionError("unexpected sink creation");
            return queue.removeFirst();
        }
    }

    private static PulsrAudioSink.Inner holder(AudioSink sink) {
        return new PulsrAudioSink.Inner(sink, null, null, null);
    }

    private PulsrAudioSink newSink(Flag aaudio, Flag floatMode, Fallbacks fallbacks,
            Factory factory) {
        return new PulsrAudioSink(
                RuntimeEnvironment.getApplication(),
                aaudio,
                new Flag(true),
                new IntValue(150),
                floatMode,
                () -> null,
                processor -> {},
                fallbacks,
                factory);
    }

    @Test
    public void configureAppliesCachedStateToInnerSink() throws Exception {
        final Flag aaudio = new Flag(false);
        final Flag floatMode = new Flag(false);
        final Factory factory = new Factory();
        final AudioSink first = mock(AudioSink.class);
        factory.queue.add(holder(first));
        final PulsrAudioSink sink = newSink(aaudio, floatMode,
                new Fallbacks(aaudio, floatMode), factory);

        sink.setVolume(0.5f);
        sink.setSkipSilenceEnabled(true);
        sink.configure(FORMAT, 0, null);

        verify(first).setVolume(0.5f);
        verify(first).setSkipSilenceEnabled(true);
        verify(first).configure(FORMAT, 0, null);
        assertEquals(1, factory.requestedFloat.size());
        assertFalse(factory.requestedFloat.get(0));
        assertFalse(factory.requestedAaudio.get(0));
    }

    @Test
    public void modeChangeReleasesOldInnerAndReplaysSettings() throws Exception {
        final Flag aaudio = new Flag(false);
        final Flag floatMode = new Flag(false);
        final Fallbacks fallbacks = new Fallbacks(aaudio, floatMode);
        final Factory factory = new Factory();
        final AudioSink first = mock(AudioSink.class);
        final AudioSink second = mock(AudioSink.class);
        factory.queue.add(holder(first));
        final PulsrAudioSink sink = newSink(aaudio, floatMode, fallbacks, factory);
        sink.setVolume(0.25f);
        sink.setSkipSilenceEnabled(true);
        sink.configure(FORMAT, 0, null);

        floatMode.value = true;
        factory.queue.add(holder(second));
        sink.applyPendingMode(false);

        verify(first).release();
        verify(second).configure(FORMAT, 0, null);
        verify(second).setVolume(0.25f);
        verify(second).setSkipSilenceEnabled(true);
        assertEquals(2, factory.requestedFloat.size());
        assertTrue(factory.requestedFloat.get(1));
    }

    @Test
    public void swapReplaysQueuedEndOfStream() throws Exception {
        final Flag aaudio = new Flag(false);
        final Flag floatMode = new Flag(false);
        final Factory factory = new Factory();
        final AudioSink first = mock(AudioSink.class);
        final AudioSink second = mock(AudioSink.class);
        factory.queue.add(holder(first));
        final PulsrAudioSink sink = newSink(aaudio, floatMode,
                new Fallbacks(aaudio, floatMode), factory);
        sink.configure(FORMAT, 0, null);
        sink.playToEndOfStream();

        floatMode.value = true;
        factory.queue.add(holder(second));
        sink.applyPendingMode(false);

        verify(second).playToEndOfStream();
    }

    @Test
    public void aaudioConfigureFailureFallsBackToDefaultInPlace() throws Exception {
        final Flag aaudio = new Flag(true);
        final Flag floatMode = new Flag(false);
        final Fallbacks fallbacks = new Fallbacks(aaudio, floatMode);
        final Factory factory = new Factory();
        final AudioSink nativeSink = mock(AudioSink.class);
        final AudioSink defaultSink = mock(AudioSink.class);
        doThrow(new AudioSink.ConfigurationException("no exclusive", FORMAT))
                .when(nativeSink).configure(any(Format.class), anyInt(), any());
        factory.queue.add(holder(nativeSink));
        factory.queue.add(holder(defaultSink));
        final PulsrAudioSink sink = newSink(aaudio, floatMode, fallbacks, factory);

        sink.configure(FORMAT, 0, null);

        assertEquals(1, fallbacks.aaudioRejected);
        assertFalse(aaudio.value);
        verify(nativeSink).release();
        verify(defaultSink).configure(FORMAT, 0, null);
        assertTrue(factory.requestedAaudio.get(0));
        assertFalse(factory.requestedAaudio.get(1));
    }

    @Test
    public void aaudioWriteFailureRetriesBufferOnDefaultSink() throws Exception {
        final Flag aaudio = new Flag(true);
        final Flag floatMode = new Flag(false);
        final Fallbacks fallbacks = new Fallbacks(aaudio, floatMode);
        final Factory factory = new Factory();
        final AudioSink nativeSink = mock(AudioSink.class);
        final AudioSink defaultSink = mock(AudioSink.class);
        factory.queue.add(holder(nativeSink));
        factory.queue.add(holder(defaultSink));
        final PulsrAudioSink sink = newSink(aaudio, floatMode, fallbacks, factory);
        sink.configure(FORMAT, 0, null);

        final ByteBuffer buffer = ByteBuffer.allocateDirect(64);
        when(nativeSink.handleBuffer(any(), anyLong(), anyInt()))
                .thenThrow(new AudioSink.WriteException(0, FORMAT, true));
        when(defaultSink.handleBuffer(any(), anyLong(), anyInt())).thenReturn(true);

        assertTrue(sink.handleBuffer(buffer, 1_000_000L, 0));
        verify(defaultSink).handleBuffer(buffer, 1_000_000L, 0);
        assertEquals(1, fallbacks.aaudioRejected);
    }

    @Test
    public void releaseUnobservesNativeInnerSinkFromRoutingRegistry() throws Exception {
        final Flag aaudio = new Flag(true);
        final Flag floatMode = new Flag(false);
        final Fallbacks fallbacks = new Fallbacks(aaudio, floatMode);
        final Factory factory = new Factory();
        final AAudioAudioSink nativeSink = new AAudioAudioSink(false, 50);
        nativeSink.setBridgeForTest(new AAudioAudioSinkTest.FakeBridge());
        PulsrOutputRouting.observe(nativeSink);
        factory.queue.add(new PulsrAudioSink.Inner(nativeSink, null, nativeSink, null));
        final PulsrAudioSink sink = newSink(aaudio, floatMode, fallbacks, factory);
        sink.configure(FORMAT, 0, null);

        sink.release();

        assertFalse(nativeSinks().contains(nativeSink));
    }

    @SuppressWarnings("unchecked")
    private static Set<AAudioAudioSink> nativeSinks() throws Exception {
        final Field field = PulsrOutputRouting.class.getDeclaredField("nativeSinks");
        field.setAccessible(true);
        return (Set<AAudioAudioSink>) field.get(null);
    }

    @Test
    public void releaseIsIdempotentAndReleasesInnerOnce() throws Exception {
        final Flag aaudio = new Flag(false);
        final Flag floatMode = new Flag(false);
        final Factory factory = new Factory();
        final AudioSink first = mock(AudioSink.class);
        factory.queue.add(holder(first));
        final PulsrAudioSink sink = newSink(aaudio, floatMode,
                new Fallbacks(aaudio, floatMode), factory);
        sink.configure(FORMAT, 0, null);

        sink.release();
        sink.release();

        verify(first, times(1)).release();
    }
}
