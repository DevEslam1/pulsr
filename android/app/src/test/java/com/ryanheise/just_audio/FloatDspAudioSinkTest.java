package com.ryanheise.just_audio;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.AudioProcessor.AudioFormat;
import androidx.media3.exoplayer.audio.AudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/**
 * Sink-wrapper contract tests. Hand-written fakes rather than mocks: Media3's
 * BaseAudioProcessor.configure/flush are final, so the format propagation under
 * test can only be observed by running the real base-class negotiation.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 33)
public class FloatDspAudioSinkTest {

    /** Records what the wrapper actually hands the platform sink. */
    private static final class FakeSink implements AudioSink {
        final List<Format> configuredFormats = new ArrayList<>();
        final List<Long> writtenTimes = new ArrayList<>();
        final List<Integer> writtenUnits = new ArrayList<>();
        final Deque<int[]> consumption = new ArrayDeque<>();
        int writeCount;
        int formatSupport = SINK_FORMAT_SUPPORTED_DIRECTLY;

        @Override public void setListener(AudioSink.Listener listener) {}
        @Override public boolean supportsFormat(Format format) { return true; }
        @Override public int getFormatSupport(Format format) { return formatSupport; }
        @Override public long getCurrentPositionUs(boolean sourceEnded) {
            return CURRENT_POSITION_NOT_SET;
        }
        @Override public void configure(Format format, int bufferSize, int[] outputChannels) {
            configuredFormats.add(format);
        }
        @Override public void play() {}
        @Override public void handleDiscontinuity() {}
        @Override public boolean handleBuffer(ByteBuffer buffer, long presentationTimeUs,
                int accessUnits) {
            writeCount++;
            writtenTimes.add(presentationTimeUs);
            writtenUnits.add(accessUnits);
            int[] next = consumption.isEmpty()
                    ? new int[] {buffer.remaining(), 1} : consumption.poll();
            buffer.position(buffer.position() + next[0]);
            return next[1] == 1;
        }
        @Override public void playToEndOfStream() {}
        @Override public boolean isEnded() { return false; }
        @Override public boolean hasPendingData() { return false; }
        @Override public void setPlaybackParameters(androidx.media3.common.PlaybackParameters p) {}
        @Override public androidx.media3.common.PlaybackParameters getPlaybackParameters() {
            return androidx.media3.common.PlaybackParameters.DEFAULT;
        }
        @Override public void setSkipSilenceEnabled(boolean enabled) {}
        @Override public boolean getSkipSilenceEnabled() { return false; }
        @Override public void setAudioAttributes(androidx.media3.common.AudioAttributes a) {}
        @Override public androidx.media3.common.AudioAttributes getAudioAttributes() { return null; }
        @Override public void setAudioSessionId(int audioSessionId) {}
        @Override public void setAuxEffectInfo(androidx.media3.common.AuxEffectInfo info) {}
        @Override public void enableTunnelingV21() {}
        @Override public void disableTunneling() {}
        @Override public void setVolume(float volume) {}
        @Override public void pause() {}
        @Override public void flush() {}
        @Override public void reset() {}
    }

    /** Processor stand-in that keeps Media3's real final configure/flush flow. */
    private static class FakeProcessor extends NativeDspAudioProcessor {
        AudioFormat output = new AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT);
        boolean bitPerfect;
        int flushCount;
        int configureCount;
        int queueCount;
        int floatsToConsume = Integer.MAX_VALUE;
        ByteBuffer nextOutput = AudioProcessor.EMPTY_BUFFER;
        final List<AudioFormat> requests = new ArrayList<>();
        final List<Float> receivedFloats = new ArrayList<>();

        @Override boolean isNativeAvailableForConfiguration() { return true; }
        @Override boolean isBitPerfectNative() { return bitPerfect; }

        @Override protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
            configureCount++;
            requests.add(inputAudioFormat);
            return output;
        }

        @Override protected void onFlush() { flushCount++; }

        @Override public void queueInput(ByteBuffer inputBuffer) {
            queueCount++;
            int take = Math.min(inputBuffer.remaining() / 4, floatsToConsume);
            for (int i = 0; i < take; i++) receivedFloats.add(inputBuffer.getFloat());
        }

        @Override public ByteBuffer getOutput() {
            ByteBuffer result = nextOutput.duplicate();
            nextOutput.position(nextOutput.limit());
            return result;
        }
    }

    private static Format source(int rate, int channels, int encoding) {
        return new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
                .setSampleRate(rate).setChannelCount(channels).setPcmEncoding(encoding).build();
    }

    private static Format lastConfigured(FakeSink sink) {
        return sink.configuredFormats.get(sink.configuredFormats.size() - 1);
    }

    @Test
    public void propagatesProcessorOutputRateChannelsAndEncodingToTheSink() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        processor.output = new AudioFormat(48000, 1, C.ENCODING_PCM_16BIT);
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);

        wrapper.configure(source(44100, 2, C.ENCODING_PCM_24BIT), 4096, null);

        Format actual = lastConfigured(sink);
        assertEquals("resampled output must not be played at the source rate",
                48000, actual.sampleRate);
        assertEquals(1, actual.channelCount);
        assertEquals(C.ENCODING_PCM_16BIT, actual.pcmEncoding);
        assertEquals(new AudioFormat(44100, 2, C.ENCODING_PCM_FLOAT), processor.requests.get(0));
    }

    @Test
    public void identicalDecodedInputStillReNegotiatesTheOutputTarget() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        Format input = source(44100, 2, C.ENCODING_PCM_FLOAT);

        processor.output = new AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT);
        wrapper.configure(input, 0, null);
        assertEquals(48000, lastConfigured(sink).sampleRate);

        // SRC target or bit-perfect policy changed between tracks while the
        // decoded header stayed identical: the stale rate must not survive.
        processor.output = new AudioFormat(96000, 2, C.ENCODING_PCM_FLOAT);
        wrapper.configure(input, 0, null);
        assertEquals(96000, lastConfigured(sink).sampleRate);
        assertEquals(2, processor.flushCount);

        processor.output = new AudioFormat(44100, 2, C.ENCODING_PCM_FLOAT);
        processor.bitPerfect = true;
        wrapper.configure(input, 0, null);
        assertEquals(44100, lastConfigured(sink).sampleRate);
    }

    @Test
    public void declinedAndUnsupportedFormatsPassThroughUnmodified() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);

        Format unsupported = source(44100, 2, C.ENCODING_PCM_8BIT);
        wrapper.configure(unsupported, 0, null);
        assertEquals(unsupported, lastConfigured(sink));
        assertEquals(0, processor.configureCount);
        ByteBuffer raw = ByteBuffer.allocateDirect(12);
        assertTrue(wrapper.handleBuffer(raw, 55L, 1));
        assertEquals(1, sink.writeCount);

        processor.output = AudioFormat.NOT_SET;
        Format inactive = source(44100, 2, C.ENCODING_PCM_24BIT);
        wrapper.configure(inactive, 0, null);
        assertEquals(inactive, lastConfigured(sink));
        ByteBuffer afterDecline = ByteBuffer.allocateDirect(12);
        assertTrue(wrapper.handleBuffer(afterDecline, 56L, 1));
        assertEquals("declined formats must never enter the DSP chain", 2, sink.writeCount);
        assertEquals(0, processor.queueCount);
    }

    @Test
    public void emptySrcOutputConsumesInputWithoutWritingTheSink() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        processor.floatsToConsume = 2;
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        wrapper.configure(source(44100, 2, C.ENCODING_PCM_FLOAT), 0, null);

        ByteBuffer input = ByteBuffer.allocateDirect(8);
        assertTrue("SRC priming is not an AudioTrack write", wrapper.handleBuffer(input, 77L, 1));
        assertEquals(8, input.position());
        assertEquals(0, sink.writeCount);
    }

    @Test
    public void partialSinkWriteKeepsPendingOutputAndOriginalTimestamp() throws Exception {
        FakeSink sink = new FakeSink();
        sink.consumption.add(new int[] {8, 0});
        sink.consumption.add(new int[] {8, 1});
        FakeProcessor processor = new FakeProcessor();
        ByteBuffer output = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder());
        output.putFloat(1f).putFloat(2f).putFloat(3f).putFloat(4f).flip();
        processor.nextOutput = output;
        processor.floatsToConsume = 4;
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        Format input = source(44100, 2, C.ENCODING_PCM_16BIT);
        wrapper.configure(input, 0, null);

        ByteBuffer pcm = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        pcm.putShort((short) 1).putShort((short) 2).putShort((short) 3).putShort((short) 4).flip();
        assertFalse(wrapper.handleBuffer(pcm, 123456L, 1));
        assertEquals("source bytes stay until the sink drains them", 0, pcm.position());

        // A gapless reconfigure with the identical negotiated format must neither
        // discard the pending tail nor reset the native engine.
        wrapper.configure(input, 0, null);
        assertEquals(1, processor.flushCount);
        assertTrue(wrapper.handleBuffer(pcm, 999999L, 2));
        assertEquals(pcm.limit(), pcm.position());
        assertEquals("retry must reuse the buffered output, not re-process", 1,
                processor.queueCount);
        assertEquals(List.of(123456L, 123456L), sink.writtenTimes);
        assertEquals(List.of(1, 1), sink.writtenUnits);
    }

    @Test
    public void partialProcessorConsumptionAdvancesOnlyConsumedSourceBytes() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        processor.floatsToConsume = 2;
        ByteBuffer output = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder());
        output.putFloat(1f).putFloat(2f).flip();
        processor.nextOutput = output;
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        wrapper.configure(source(44100, 2, C.ENCODING_PCM_24BIT), 0, null);

        ByteBuffer input = ByteBuffer.allocateDirect(12);
        assertFalse(wrapper.handleBuffer(input, 0L, 1));
        assertEquals("one stereo 24-bit frame at a time", 6, input.position());
        processor.floatsToConsume = 2;
        assertTrue(wrapper.handleBuffer(input, 0L, 1));
        assertEquals(12, input.position());
        assertEquals("the tail must be re-fed, never dropped", 2, processor.queueCount);
        assertEquals(1, sink.writeCount);
    }

    @Test
    public void optingOutOfFloatForPcm16KeepsRawBytesUntouched() throws Exception {
        FakeSink sink = new FakeSink();
        FakeProcessor processor = new FakeProcessor();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor, false);
        Format format = source(44100, 2, C.ENCODING_PCM_16BIT);
        wrapper.configure(format, 0, null);

        ByteBuffer raw = ByteBuffer.allocateDirect(8);
        assertTrue(wrapper.handleBuffer(raw, 10L, 1));
        assertEquals(format, lastConfigured(sink));
        assertEquals(0, processor.configureCount);
        assertEquals(8, raw.position());
        assertEquals(1, sink.writeCount);
    }

    @Test
    public void int32IsNeverClaimedAsAnExactPath() throws Exception {
        FakeSink sink = new FakeSink();
        sink.formatSupport = AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY;
        FakeProcessor processor = new FakeProcessor();
        processor.floatsToConsume = 2;
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        Format pcm32 = source(44100, 2, C.ENCODING_PCM_32BIT);

        assertEquals("float32 cannot carry every int32 value",
                AudioSink.SINK_FORMAT_SUPPORTED_WITH_TRANSCODING, wrapper.getFormatSupport(pcm32));

        wrapper.configure(pcm32, 0, null);
        assertEquals(C.ENCODING_PCM_FLOAT, lastConfigured(sink).pcmEncoding);
        ByteBuffer input = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        input.putInt(0x40000000).putInt(0x40000001).flip();
        assertTrue(wrapper.handleBuffer(input, 0L, 1));
        assertEquals(2, processor.receivedFloats.size());
        assertEquals("adjacent int32 codes collapse into one float",
                processor.receivedFloats.get(0), processor.receivedFloats.get(1), 0f);
    }

    @Test
    public void nativeSrcNegotiationLatchesRateOnFlushAndTracksBitPerfectToggles()
            throws Exception {
        final boolean[] bitPerfect = {false};
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor() {
            @Override boolean isNativeAvailableForConfiguration() { return true; }
            @Override boolean isBitPerfectNative() { return bitPerfect[0]; }
        };
        processor.setFloatOutput(true);
        FakeSink sink = new FakeSink();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        Format input = source(44100, 2, C.ENCODING_PCM_FLOAT);

        processor.setTapSrcTargetRate(48000);
        wrapper.configure(input, 0, null);
        assertEquals(48000, lastConfigured(sink).sampleRate);
        assertTrue(processor.isTapSrcActive());

        processor.setTapSrcTargetRate(96000);
        assertEquals("a pending target must not move the live stream",
                1, sink.configuredFormats.size());
        wrapper.configure(input, 0, null);
        assertEquals(96000, lastConfigured(sink).sampleRate);

        bitPerfect[0] = true;
        wrapper.configure(input, 0, null);
        assertEquals(44100, lastConfigured(sink).sampleRate);
        assertFalse(processor.isTapSrcActive());

        bitPerfect[0] = false;
        wrapper.configure(input, 0, null);
        assertEquals(96000, lastConfigured(sink).sampleRate);
        assertTrue(processor.isTapSrcActive());

        processor.setTapSrcTargetRate(0);
        wrapper.configure(input, 0, null);
        assertEquals(44100, lastConfigured(sink).sampleRate);
        assertFalse(processor.isTapSrcActive());
        wrapper.reset();
        processor.release();
    }
}
