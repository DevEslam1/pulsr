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
    public void directAdvertisesFloatToPlatformDecoderEvenWithoutFloatPreference() {
        Flag aaudio = new Flag(true);
        Flag floatMode = new Flag(false);
        PulsrAudioSink sink = newSink(aaudio, floatMode, new Fallbacks(aaudio, floatMode), new Factory());
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY,
                sink.getFormatSupport(FORMAT.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build()));
    }

    @Test
    public void listenerTargetAndContinuousStateAreInstalledBeforeConfigure() throws Exception {
        Flag aaudio = new Flag(false);
        Flag floatMode = new Flag(true);
        Factory factory = new Factory();
        List<NativeDspAudioProcessor> active = new ArrayList<>();
        NativeDspAudioProcessor first = new NativeDspAudioProcessor();
        NativeDspAudioProcessor next = new NativeDspAudioProcessor();
        AudioSink firstSink = mock(AudioSink.class);
        AudioSink nextSink = mock(AudioSink.class);
        org.mockito.Mockito.doAnswer(call -> {
            assertEquals(first, active.get(active.size() - 1));
            assertEquals(96000, first.getTapSrcTargetRate());
            return null;
        }).when(firstSink).configure(any(), anyInt(), any());
        Field transitionGain = NativeDspAudioProcessor.class.getDeclaredField("transitionGain");
        transitionGain.setAccessible(true);
        org.mockito.Mockito.doAnswer(call -> {
            assertEquals(next, active.get(active.size() - 1));
            assertEquals(96000, next.getTapSrcTargetRate());
            assertEquals(0.25f, transitionGain.getFloat(next), 0f);
            return null;
        }).when(nextSink).configure(any(), anyInt(), any());
        factory.queue.add(new PulsrAudioSink.Inner(firstSink, null, null, first));
        factory.queue.add(new PulsrAudioSink.Inner(nextSink, null, null, next));
        PulsrAudioSink sink = new PulsrAudioSink(RuntimeEnvironment.getApplication(), aaudio,
                new Flag(true), new IntValue(50), floatMode, () -> null, processor -> {
                    active.add(processor);
                    if (processor != null) processor.setTapSrcTargetRate(96000);
                }, new Fallbacks(aaudio, floatMode), factory);
        sink.configure(FORMAT, 0, null);
        transitionGain.setFloat(first, 0.25f);
        sink.applyPendingMode(true);
        assertEquals(next, active.get(active.size() - 1));
        sink.release();
    }

    @Test
    public void failedCandidatesRestoreListenerToOldProcessorBeforeRelease() throws Exception {
        Flag aaudio = new Flag(false);
        Flag floatMode = new Flag(false);
        Factory factory = new Factory();
        List<NativeDspAudioProcessor> active = new ArrayList<>();
        NativeDspAudioProcessor old = new NativeDspAudioProcessor();
        AudioSink original = mock(AudioSink.class);
        factory.queue.add(new PulsrAudioSink.Inner(original, null, null, old));
        PulsrAudioSink sink = new PulsrAudioSink(RuntimeEnvironment.getApplication(), aaudio,
                new Flag(true), new IntValue(50), floatMode, () -> null, active::add,
                new Fallbacks(aaudio, floatMode), factory);
        sink.configure(FORMAT, 0, null);
        for (int i = 0; i < 2; i++) {
            AudioSink rejected = mock(AudioSink.class);
            NativeDspAudioProcessor rejectedProcessor = new NativeDspAudioProcessor();
            doThrow(new AudioSink.ConfigurationException("refused", FORMAT))
                    .when(rejected).configure(any(), anyInt(), any());
            org.mockito.Mockito.doAnswer(call -> {
                assertEquals(old, active.get(active.size() - 1));
                return null;
            }).when(rejected).release();
            factory.queue.add(new PulsrAudioSink.Inner(rejected, null, null, rejectedProcessor));
        }
        floatMode.value = true;
        sink.applyPendingMode(false);
        assertEquals(old, active.get(active.size() - 1));
        verify(original, org.mockito.Mockito.never()).release();
        sink.release();
    }

    @Test
    public void runtimeFloatInitializationAndWriteFailuresUseDefaultWithoutRenegotiation() throws Exception {
        for (boolean initialization : new boolean[] {true, false}) {
            Flag aaudio = new Flag(false);
            Flag floatMode = new Flag(true);
            Fallbacks fallbacks = new Fallbacks(aaudio, floatMode);
            Factory factory = new Factory();
            AudioSink rejected = mock(AudioSink.class);
            AudioSink standard = mock(AudioSink.class);
            factory.queue.add(holder(rejected));
            factory.queue.add(holder(standard));
            PulsrAudioSink sink = newSink(aaudio, floatMode, fallbacks, factory);
            sink.configure(FORMAT, 0, null);
            ByteBuffer source = ByteBuffer.allocateDirect(32);
            source.position(8);
            if (initialization) {
                when(rejected.handleBuffer(any(), anyLong(), anyInt())).thenThrow(
                        new AudioSink.InitializationException("AudioTrack initialization failed", 0,
                                FORMAT, false, null));
            } else {
                when(rejected.handleBuffer(any(), anyLong(), anyInt())).thenThrow(
                        new AudioSink.WriteException(-1, FORMAT, true));
            }
            when(standard.handleBuffer(any(), anyLong(), anyInt())).thenAnswer(call -> {
                assertEquals(8, ((ByteBuffer) call.getArgument(0)).position());
                return true;
            });
            assertTrue(sink.handleBuffer(source, 55L, 1));
            assertFalse(floatMode.value);
            assertEquals(1, fallbacks.floatRejected);
            sink.applyPendingMode(false);
            assertEquals(2, factory.requestedFloat.size());
            assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_WITH_TRANSCODING,
                    sink.getFormatSupport(FORMAT.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build()));
            verify(standard).handleBuffer(source, 55L, 1);
            sink.release();
        }
    }

    @Test
    public void srcFailureReconfiguresAtSourceRateAndRetriesUnchangedInput() throws Exception {
        Flag aaudio = new Flag(false);
        Flag floatMode = new Flag(true);
        Factory factory = new Factory();
        AudioSink failed = mock(AudioSink.class);
        AudioSink restored = mock(AudioSink.class);
        NativeDspAudioProcessor failedProcessor = new NativeDspAudioProcessor();
        NativeDspAudioProcessor restoredProcessor = new NativeDspAudioProcessor();
        factory.queue.add(new PulsrAudioSink.Inner(failed, null, null, failedProcessor));
        factory.queue.add(new PulsrAudioSink.Inner(restored, null, null, restoredProcessor));
        PulsrAudioSink sink = new PulsrAudioSink(RuntimeEnvironment.getApplication(), aaudio,
                new Flag(true), new IntValue(50), floatMode, () -> null,
                p -> { if (p != null) p.setTapSrcTargetRate(96000); },
                new Fallbacks(aaudio, floatMode), factory);
        org.mockito.Mockito.doAnswer(call -> {
            assertEquals(0, restoredProcessor.getTapSrcTargetRate());
            return null;
        }).when(restored).configure(any(), anyInt(), any());
        sink.configure(FORMAT, 0, null);
        when(failed.handleBuffer(any(), anyLong(), anyInt())).thenThrow(
                new NativeDspAudioProcessor.TapSrcException("native failed", null));
        when(restored.handleBuffer(any(), anyLong(), anyInt())).thenReturn(true);
        ByteBuffer source = ByteBuffer.allocateDirect(16);
        source.position(4);
        assertTrue(sink.handleBuffer(source, 10L, 1));
        assertEquals(4, source.position());
        assertEquals(0, restoredProcessor.getTapSrcTargetRate());
        assertTrue(floatMode.value);
        sink.release();
    }

    /** Real Media3 negotiation with only DSP sample processing replaced. */
    private static class CopyProcessor extends NativeDspAudioProcessor {
        ByteBuffer output;
        boolean rejectNextInput;
        @Override protected androidx.media3.common.audio.AudioProcessor.AudioFormat onConfigure(
                androidx.media3.common.audio.AudioProcessor.AudioFormat input) { return input; }
        @Override protected void onFlush() {}
        @Override public void queueInput(ByteBuffer input) {
            output = ByteBuffer.allocateDirect(input.remaining()).order(java.nio.ByteOrder.nativeOrder());
            output.put(input).flip();
        }
        @Override public void queueInput(ByteBuffer input, ByteBuffer original, int depth, int rate) {
            queueInput(input);
        }
        @Override public ByteBuffer getOutput() { return output; }
    }

    private static final class RecordingSink extends androidx.media3.exoplayer.audio.ForwardingAudioSink {
        final List<Format> formats = new ArrayList<>();
        final List<Integer> sizes = new ArrayList<>();
        final List<Integer> writeRates = new ArrayList<>();
        final List<Long> times = new ArrayList<>();
        final List<Integer> units = new ArrayList<>();
        final java.io.ByteArrayOutputStream accepted = new java.io.ByteArrayOutputStream();
        int nextWriteBytes = Integer.MAX_VALUE;
        boolean rejectNextWrite;
        RecordingSink() { super(new AAudioAudioSink(false, 50)); }
        @Override public void configure(Format format, int size, int[] channels) {
            formats.add(format);
            sizes.add(size);
        }
        @Override public boolean handleBuffer(ByteBuffer input, long time, int accessUnits)
                throws WriteException {
            if (rejectNextWrite) {
                rejectNextWrite = false;
                throw new WriteException(-1, formats.get(formats.size() - 1), true);
            }
            writeRates.add(formats.get(formats.size() - 1).sampleRate);
            times.add(time);
            units.add(accessUnits);
            int take = Math.min(nextWriteBytes, input.remaining());
            nextWriteBytes = Integer.MAX_VALUE;
            for (int i = 0; i < take; i++) accepted.write(input.get());
            return !input.hasRemaining();
        }
    }

    private static ByteBuffer stereo16(int... samples) {
        ByteBuffer result = ByteBuffer.allocateDirect(samples.length * 2)
                .order(java.nio.ByteOrder.nativeOrder());
        for (int sample : samples) result.putShort((short) sample);
        return (ByteBuffer) result.flip();
    }

    @Test
    public void fallbackDrainsOldRateTailBeforeApplyingQueuedSourceConfiguration() throws Exception {
        Flag aaudio = new Flag(false);
        Flag floatMode = new Flag(true);
        Factory factory = new Factory();
        RecordingSink oldTrack = new RecordingSink();
        RecordingSink replacementTrack = new RecordingSink();
        CopyProcessor oldProcessor = new CopyProcessor();
        CopyProcessor replacementProcessor = new CopyProcessor();
        factory.queue.add(new PulsrAudioSink.Inner(
                new FloatDspAudioSink(oldTrack, oldProcessor), null, null, oldProcessor));
        factory.queue.add(new PulsrAudioSink.Inner(
                new FloatDspAudioSink(replacementTrack, replacementProcessor, true, true),
                null, null, replacementProcessor));
        PulsrAudioSink sink = newSink(aaudio, floatMode, new Fallbacks(aaudio, floatMode), factory);
        sink.configure(FORMAT.buildUpon().setSampleRate(44100).build(), 111, null);
        ByteBuffer source = stereo16(16384, -16384, 8192, -8192);
        oldTrack.nextWriteBytes = 8;
        assertFalse(sink.handleBuffer(source, 90L, 2));
        assertEquals(0, source.position());
        sink.configure(FORMAT.buildUpon().setSampleRate(96000).build(), 222, new int[] {1});
        oldTrack.rejectNextWrite = true;
        assertTrue(sink.handleBuffer(source, 999L, 7));
        assertEquals(source.limit(), source.position());
        assertEquals(java.util.Arrays.asList(44100), replacementTrack.writeRates);
        assertEquals(java.util.Arrays.asList(90L), replacementTrack.times);
        assertEquals(java.util.Arrays.asList(2), replacementTrack.units);
        assertEquals(java.util.Arrays.asList(111, 222), replacementTrack.sizes);
        assertEquals(44100, replacementTrack.formats.get(0).sampleRate);
        assertEquals(2, replacementTrack.formats.get(0).channelCount);
        assertEquals(96000, replacementTrack.formats.get(1).sampleRate);
        assertEquals(1, replacementTrack.formats.get(1).channelCount);
        assertTrue(sink.handleBuffer(stereo16(4096, -4096), 100L, 1));
        assertEquals(java.util.Arrays.asList(44100, 96000), replacementTrack.writeRates);
        ByteBuffer written = ByteBuffer.wrap(replacementTrack.accepted.toByteArray())
                .order(java.nio.ByteOrder.nativeOrder());
        assertEquals(6, written.remaining());
        assertEquals(8192, written.getShort());
        assertEquals(-8192, written.getShort());
        assertEquals(-4096, written.getShort());
        sink.release();
    }

    @Test
    public void freshPacked24StreamUsesItsOwnFrameWidthAndTrimmingAfterModeChange() throws Exception {
        for (boolean initiallyFloat : new boolean[] {true, false}) {
            Flag aaudio = new Flag(false);
            Flag floatMode = new Flag(initiallyFloat);
            Factory factory = new Factory();
            RecordingSink oldTrack = new RecordingSink();
            RecordingSink nextTrack = new RecordingSink();
            CopyProcessor oldProcessor = new CopyProcessor();
            CopyProcessor nextProcessor = new CopyProcessor();
            factory.queue.add(new PulsrAudioSink.Inner(
                    new FloatDspAudioSink(oldTrack, oldProcessor, true, !initiallyFloat),
                    null, null, oldProcessor));
            factory.queue.add(new PulsrAudioSink.Inner(
                    new FloatDspAudioSink(nextTrack, nextProcessor, true, initiallyFloat),
                    null, null, nextProcessor));
            PulsrAudioSink sink = newSink(aaudio, floatMode, new Fallbacks(aaudio, floatMode), factory);
            sink.configure(FORMAT.buildUpon().setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
            assertTrue(sink.handleBuffer(stereo16(0, 0, 8192, -8192, 16384, -16384), 0L, 1));
            floatMode.value = !initiallyFloat;
            sink.configure(FORMAT.buildUpon().setPcmEncoding(C.ENCODING_PCM_24BIT)
                    .setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
            ByteBuffer source = ByteBuffer.allocateDirect(18);
            source.put(new byte[] {0, 0, 0, 0, 0, 0,
                    0, 0, 64, 0, 0, (byte) 192,
                    0, 0, 32, 0, 0, (byte) 224}).flip();
            assertTrue(sink.handleBuffer(source, 100L, 1));
            assertEquals(18, source.position());
            ByteBuffer written = ByteBuffer.wrap(nextTrack.accepted.toByteArray())
                    .order(java.nio.ByteOrder.nativeOrder());
            assertEquals(initiallyFloat ? 4 : 8, written.remaining());
            if (initiallyFloat) {
                assertEquals(16384, written.getShort());
                assertEquals(-16384, written.getShort());
            } else {
                assertEquals(0.5f, written.getFloat(), 0f);
                assertEquals(-0.5f, written.getFloat(), 0f);
            }
            sink.playToEndOfStream();
            assertEquals(initiallyFloat ? 4 : 8, nextTrack.accepted.size());
            sink.release();
        }
    }

    private static ByteBuffer encodedFrames(int encoding, int... samples16) {
        int bytes = encoding == C.ENCODING_PCM_16BIT ? 2 : encoding == C.ENCODING_PCM_24BIT ? 3 : 4;
        ByteBuffer result = ByteBuffer.allocateDirect(samples16.length * bytes)
                .order(java.nio.ByteOrder.nativeOrder());
        for (int sample : samples16) {
            if (bytes == 2) result.putShort((short) sample);
            else if (bytes == 3) result.put((byte) 0).put((byte) sample).put((byte) (sample >> 8));
            else result.putInt(sample << 16);
        }
        return (ByteBuffer) result.flip();
    }

    @Test
    public void forcedAaudioReplacementRetainsPaddingAndDoesNotRepeatEncoderDelay() throws Exception {
        for (int encoding : new int[] {C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT}) {
            Flag aaudio = new Flag(true);
            Flag floatMode = new Flag(false);
            Factory factory = new Factory();
            AAudioAudioSink old = new AAudioAudioSink(false, 50);
            AAudioAudioSink replacement = new AAudioAudioSink(false, 50);
            AAudioAudioSinkTest.FakeBridge oldBridge = new AAudioAudioSinkTest.FakeBridge();
            AAudioAudioSinkTest.FakeBridge nextBridge = new AAudioAudioSinkTest.FakeBridge();
            int frameBytes = encoding == C.ENCODING_PCM_16BIT ? 4
                    : encoding == C.ENCODING_PCM_24BIT ? 6 : 8;
            oldBridge.writeResult = nextBridge.writeResult = frameBytes;
            old.setBridgeForTest(oldBridge);
            replacement.setBridgeForTest(nextBridge);
            factory.queue.add(new PulsrAudioSink.Inner(old, null, old, null));
            factory.queue.add(new PulsrAudioSink.Inner(replacement, null, replacement, null));
            PulsrAudioSink sink = newSink(aaudio, floatMode, new Fallbacks(aaudio, floatMode), factory);
            sink.configure(FORMAT.buildUpon().setPcmEncoding(encoding)
                    .setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
            assertTrue(sink.handleBuffer(encodedFrames(encoding,
                    0, 0, 4096, -4096, 8192, -8192), 0L, 1));
            sink.applyPendingMode(true);
            ByteBuffer next = encodedFrames(encoding, 16384, -16384);
            assertTrue(sink.handleBuffer(next, 100L, 1));
            assertEquals(frameBytes, next.position());
            byte[] expected = encoding == C.ENCODING_PCM_16BIT
                    ? new byte[] {0, 32, 0, (byte) 224}
                    : encoding == C.ENCODING_PCM_24BIT
                            ? new byte[] {0, 0, 32, 0, 0, (byte) 224}
                            : new byte[] {0, 0, (byte) 128, 62, 0, 0, (byte) 128, (byte) 190};
            org.junit.Assert.assertArrayEquals(expected, nextBridge.writtenBytes);
            sink.playToEndOfStream();
            org.junit.Assert.assertArrayEquals(expected, nextBridge.writtenBytes);
            sink.release();
        }
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
