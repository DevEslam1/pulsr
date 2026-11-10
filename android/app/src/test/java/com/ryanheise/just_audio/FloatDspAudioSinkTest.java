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
        final List<Byte> accepted = new ArrayList<>();
        boolean rejectNextWrite;

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
                int accessUnits) throws WriteException {
            if (rejectNextWrite) {
                rejectNextWrite = false;
                throw new WriteException(-1, configuredFormats.get(configuredFormats.size() - 1), true);
            }
            writeCount++;
            writtenTimes.add(presentationTimeUs);
            writtenUnits.add(accessUnits);
            int[] next = consumption.isEmpty()
                    ? new int[] {buffer.remaining(), 1} : consumption.poll();
            for (int i = 0; i < next[0]; i++) accepted.add(buffer.get());
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
        @Override public long getAudioTrackBufferSizeUs() { return C.TIME_UNSET; }
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

        @Override public void queueInput(ByteBuffer inputBuffer, ByteBuffer original,
                int sourceBitDepth, int sourceSampleRate) {
            queueInput(inputBuffer);
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

    /** Overrides JNI only: real processor float expansion/raw eligibility run. */
    private static class NativeDecision extends NativeDspAudioProcessor {
        int calls;
        int sourceDepth;
        int sourceRate;
        int sourceOffset;
        byte[] raw;
        final List<Float> metered = new ArrayList<>();
        boolean perfect = true;
        boolean exclusiveSilence;
        ByteBuffer receivedGains;
        int srcResult;
        boolean srcThrows;
        int prepared;
        int released;
        @Override boolean isNativeAvailableForConfiguration() { return true; }
        @Override boolean isBitPerfectNative() { return perfect; }
        @Override void prepareTapSrc(int source, int destination, int channels) { prepared++; }
        @Override public void releaseUsbProducer() { released++; }
        @Override int resampleTapBlock(ByteBuffer input, int frames, int channels,
                ByteBuffer output, int maxFrames, int source, int destination) {
            if (srcThrows) throw new IllegalStateException("JNI SRC rejected");
            return srcResult;
        }
        @Override int processNativeBlock(ByteBuffer floatBytes, int frames, int channels,
                ByteBuffer gains, ByteBuffer source, int offset, int depth, int rate) {
            calls++;
            for (int i = 0; i < frames * channels; i++) metered.add(floatBytes.getFloat(i * 4));
            sourceDepth = depth;
            sourceRate = rate;
            sourceOffset = offset;
            raw = null;
            if (source != null) {
                raw = new byte[frames * channels * (depth / 8)];
                ByteBuffer nativeView = source.duplicate();
                nativeView.position(offset);
                nativeView.get(raw);
            }
            receivedGains = gains;
            return exclusiveSilence ? Integer.MIN_VALUE : perfect ? -frames : frames;
        }
    }

    @Test
    public void unityCurveRetainsOriginalPcm32ForNativeDecision() throws Exception {
        NativeDecision processor = new NativeDecision();
        FakeSink sink = new FakeSink();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        wrapper.configure(source(48000, 2, C.ENCODING_PCM_32BIT), 0, null);
        java.lang.reflect.Field curve = NativeDspAudioProcessor.class.getDeclaredField("rampGains");
        curve.setAccessible(true);
        curve.set(processor, new float[] {1f, 1f});
        java.lang.reflect.Field segment = NativeDspAudioProcessor.class.getDeclaredField("rampSegmentMs");
        segment.setAccessible(true);
        segment.setInt(processor, 10);
        ByteBuffer input = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        input.putInt(0x40000001).putInt(0x40000003).flip();
        assertTrue(wrapper.handleBuffer(input, 0L, 1));
        org.junit.Assert.assertNotNull(processor.receivedGains);
        assertEquals(1f, processor.receivedGains.getFloat(0), 0f);
        assertEquals(32, processor.sourceDepth);
        ByteBuffer raw = ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder());
        assertEquals(0x40000001, raw.getInt());
        assertEquals(0x40000003, raw.getInt());
    }

    @Test
    public void exclusiveRejectionEmitsSeparateSilenceWithoutOverwritingSource() throws Exception {
        for (boolean floatOutput : new boolean[] {false, true}) {
            NativeDecision processor = new NativeDecision();
            processor.perfect = false;
            processor.setFloatOutput(floatOutput);
            processor.configure(new AudioFormat(48000, 2,
                    floatOutput ? C.ENCODING_PCM_FLOAT : C.ENCODING_PCM_16BIT));
            processor.flush();
            processor.queueInput(ByteBuffer.allocateDirect(128).order(ByteOrder.nativeOrder()));
            assertEquals(128, processor.getOutput().remaining());
            processor.exclusiveSilence = true;
            ByteBuffer storage = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder());
            if (floatOutput) storage.putFloat(0.25f).putFloat(-0.5f);
            else storage.putShort((short) 8192).putShort((short) -16384);
            final int sourceLength = storage.position();
            storage.putInt(0x12345678).putInt(0x76543210);
            storage.flip().limit(sourceLength);
            ByteBuffer original = storage.asReadOnlyBuffer().order(ByteOrder.nativeOrder());
            processor.queueInput(storage, original, floatOutput ? 32 : 16, 48000);
            ByteBuffer output = processor.getOutput();
            assertEquals(sourceLength, output.remaining());
            while (output.hasRemaining()) assertEquals(0, output.get());
            assertEquals(sourceLength, storage.position());
            assertEquals(0, original.position());
            if (floatOutput) {
                assertEquals(0.25f, original.getFloat(0), 0f);
                assertEquals(-0.5f, original.getFloat(4), 0f);
            } else {
                assertEquals(8192, original.getShort(0));
                assertEquals(-16384, original.getShort(2));
            }
            ByteBuffer retained = storage.duplicate().order(ByteOrder.nativeOrder());
            retained.clear();
            assertEquals(0x12345678, retained.getInt(sourceLength));
            assertEquals(0x76543210, retained.getInt(sourceLength + 4));
        }
    }

    @Test
    public void originalInt32LowBitsReachNativeDecisionBeforeAndAcrossPartialWrites() throws Exception {
        NativeDecision processor = new NativeDecision();
        FakeSink sink = new FakeSink();
        sink.consumption.add(new int[] {4, 0});
        sink.consumption.add(new int[] {4, 1});
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        wrapper.configure(source(44100, 2, C.ENCODING_PCM_32BIT), 0, null);
        ByteBuffer input = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder());
        input.position(8);
        input.putInt(0x40000000).putInt(0x40000001).flip().position(8);
        assertFalse(wrapper.handleBuffer(input, 90L, 1));
        assertEquals(8, input.position());
        assertEquals(32, processor.sourceDepth);
        assertEquals(44100, processor.sourceRate);
        assertEquals(8, processor.sourceOffset);
        ByteBuffer delivered = ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder());
        assertEquals(0x40000000, delivered.getInt());
        assertEquals(0x40000001, delivered.getInt());
        assertEquals(processor.metered.get(0), processor.metered.get(1), 0f);
        assertTrue(wrapper.handleBuffer(input, 99L, 2));
        assertEquals(1, processor.calls);
        assertEquals(16, input.position());
    }

    @Test
    public void pcm16AutomaticallyCarriesOriginalButFloatHasNoIntegerOriginal() throws Exception {
        NativeDecision processor = new NativeDecision();
        processor.configure(new AudioFormat(48000, 1, C.ENCODING_PCM_16BIT));
        processor.flush();
        ByteBuffer input = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder());
        input.putShort((short) 123).putShort((short) -234).flip();
        processor.queueInput(input);
        assertEquals(16, processor.sourceDepth);
        assertEquals(123, ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder()).getShort());
        processor.setFloatOutput(true);
        processor.configure(new AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT));
        processor.flush();
        processor.queueInput(ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder()));
        assertEquals(0, processor.sourceDepth);
        org.junit.Assert.assertNull(processor.raw);
    }

    @Test
    public void srcFailureAndInvalidNativeResultNeverConsumeSourceButZeroPrimingDoes() throws Exception {
        for (int mode = 0; mode < 3; mode++) {
            NativeDecision processor = new NativeDecision();
            processor.perfect = false;
            processor.srcThrows = mode == 0;
            processor.srcResult = mode == 1 ? -1 : 0;
            processor.setTapSrcTargetRate(48000);
            FakeSink sink = new FakeSink();
            FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
            wrapper.configure(source(44100, 2, C.ENCODING_PCM_24BIT), 0, null);
            assertEquals(1, processor.prepared);
            ByteBuffer input = ByteBuffer.allocateDirect(6);
            try {
                assertTrue(wrapper.handleBuffer(input, 0L, 1));
                assertEquals(2, mode);
                assertEquals(6, input.position());
            } catch (NativeDspAudioProcessor.TapSrcException expected) {
                assertTrue(mode < 2);
                assertEquals(0, input.position());
            }
            assertEquals(0, sink.writeCount);
        }
    }

    @Test
    public void gaplessTrimAndChannelMapRetainIntegerPrecisionAtNativeBoundary() throws Exception {
        NativeDecision processor = new NativeDecision();
        FakeSink sink = new FakeSink();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        Format format = source(48000, 2, C.ENCODING_PCM_32BIT).buildUpon()
                .setEncoderDelay(1).setEncoderPadding(1).build();
        wrapper.configure(format, 0, null);
        wrapper.flush(); // Initial flush must not erase declared delay.
        ByteBuffer first = ByteBuffer.allocateDirect(24).order(ByteOrder.nativeOrder());
        first.putInt(10).putInt(11).putInt(0x40000001).putInt(0x40000003).putInt(20).putInt(21).flip();
        assertTrue(wrapper.handleBuffer(first, 0, 1));
        ByteBuffer raw = ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder());
        assertEquals(0x40000001, raw.getInt());
        assertEquals(0x40000003, raw.getInt());
        ByteBuffer second = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        second.putInt(30).putInt(31).flip();
        assertTrue(wrapper.handleBuffer(second, 1, 1));
        raw = ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder());
        assertEquals(20, raw.getInt());
        assertEquals(21, raw.getInt());
        wrapper.playToEndOfStream();
        assertEquals("only two program frames reach the engine", 2, processor.calls);
        assertEquals(0, lastConfigured(sink).encoderDelay);
        assertEquals(0, lastConfigured(sink).encoderPadding);

        wrapper.configure(source(48000, 2, C.ENCODING_PCM_24BIT), 0, new int[] {1, 0});
        ByteBuffer packed = ByteBuffer.allocateDirect(6);
        packed.put(new byte[] {1, 0, 64, 2, 0, 64}).flip();
        assertTrue(wrapper.handleBuffer(packed, 0, 1));
        assertEquals(0, processor.sourceDepth);
        org.junit.Assert.assertNull("remapping cannot enable raw USB bypass", processor.raw);
        int n = processor.metered.size();
        assertEquals((float) (0x400002 / 8388608.0), processor.metered.get(n - 2), 0f);
        assertEquals((float) (0x400001 / 8388608.0), processor.metered.get(n - 1), 0f);
    }

    @Test
    public void fallbackTransfersOnlyUnacceptedOutputWithoutRepeatingDsp() throws Exception {
        NativeDecision firstProcessor = new NativeDecision();
        NativeDecision nextProcessor = new NativeDecision();
        FakeSink firstSink = new FakeSink();
        FakeSink nextSink = new FakeSink();
        firstSink.consumption.add(new int[] {4, 0});
        FloatDspAudioSink first = new FloatDspAudioSink(firstSink, firstProcessor);
        FloatDspAudioSink next = new FloatDspAudioSink(nextSink, nextProcessor, true, true);
        Format format = source(48000, 2, C.ENCODING_PCM_32BIT);
        first.configure(format, 0, null);
        next.configure(format, 0, null);
        ByteBuffer input = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        input.putInt(0x20000000).putInt(0x40000001).flip();
        assertFalse(first.handleBuffer(input, 80, 1));
        firstSink.rejectNextWrite = true;
        try { first.handleBuffer(input, 90, 2); org.junit.Assert.fail(); }
        catch (AudioSink.WriteException expected) { assertEquals(0, input.position()); }
        first.transferPendingTo(next);
        assertTrue(next.handleBuffer(input, 100, 3));
        assertEquals(1, firstProcessor.calls);
        assertEquals(0, nextProcessor.calls);
        assertEquals(4, firstSink.accepted.size());
        assertEquals(2, nextSink.accepted.size());
        assertEquals(C.ENCODING_PCM_16BIT, lastConfigured(nextSink).pcmEncoding);
        assertEquals(Long.valueOf(80), nextSink.writtenTimes.get(0));
    }

    @Test
    public void defaultBoundaryDithersBeforeDiscardingInteger24And32LowBits() throws Exception {
        for (int encoding : new int[] {C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT}) {
            NativeDspAudioProcessor unavailable = new NativeDspAudioProcessor() {
                @Override boolean isNativeAvailableForConfiguration() { return false; }
            };
            FakeSink sink = new FakeSink();
            FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, unavailable, true, true);
            wrapper.configure(source(48000, 1, encoding), 0, null);
            assertEquals(C.ENCODING_PCM_16BIT, lastConfigured(sink).pcmEncoding);
            int count = 8000;
            ByteBuffer input = ByteBuffer.allocateDirect(count * (encoding == C.ENCODING_PCM_24BIT ? 3 : 4))
                    .order(ByteOrder.nativeOrder());
            for (int i = 0; i < count; i++) {
                if (encoding == C.ENCODING_PCM_24BIT) input.put((byte) 192).put((byte) 0).put((byte) 0);
                else input.putInt(0x0000c000);
            }
            input.flip();
            assertTrue(wrapper.handleBuffer(input, 0, 1));
            ByteBuffer samples = ByteBuffer.allocate(count * 2).order(ByteOrder.nativeOrder());
            for (byte value : sink.accepted) samples.put(value);
            samples.flip();
            long sum = 0;
            while (samples.hasRemaining()) {
                int sample = samples.getShort();
                assertTrue(sample >= -1 && sample <= 2);
                sum += sample;
            }
            assertEquals("truncating before dither would give zero, not 0.75 LSB", 0.75,
                    sum / (double) count, 0.04);
        }
    }

    @Test
    public void defaultBoundaryHasExactUnity16AndSaturatingFloatWithoutStockTruncation() throws Exception {
        NativeDecision processor = new NativeDecision();
        FakeSink sink = new FakeSink();
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor, true, true);
        wrapper.configure(source(48000, 1, C.ENCODING_PCM_16BIT), 0, null);
        ByteBuffer source = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        source.putShort(Short.MIN_VALUE).putShort((short) -123).putShort((short) 456).putShort(Short.MAX_VALUE).flip();
        byte[] expected = new byte[8];
        source.duplicate().get(expected);
        assertTrue(wrapper.handleBuffer(source, 0, 1));
        byte[] actual = new byte[8];
        for (int i = 0; i < 8; i++) actual[i] = sink.accepted.get(i);
        org.junit.Assert.assertArrayEquals(expected, actual);
        assertEquals(16, processor.sourceDepth);
        sink.accepted.clear();
        wrapper.configure(source(48000, 1, C.ENCODING_PCM_FLOAT), 0, null);
        ByteBuffer floats = ByteBuffer.allocateDirect(8).order(ByteOrder.nativeOrder());
        floats.putFloat(1f).putFloat(-1f).flip();
        assertTrue(wrapper.handleBuffer(floats, 0, 1));
        ByteBuffer result = ByteBuffer.allocate(4).order(ByteOrder.nativeOrder());
        for (byte b : sink.accepted) result.put(b);
        result.flip();
        assertEquals(Short.MAX_VALUE, result.getShort());
        assertEquals(Short.MIN_VALUE, result.getShort());
    }

    @Test
    public void pendingWriteDrainsAtOldRateBeforeNewGaplessConfiguration() throws Exception {
        NativeDecision processor = new NativeDecision();
        FakeSink sink = new FakeSink();
        sink.consumption.add(new int[] {4, 0});
        sink.consumption.add(new int[] {4, 1});
        FloatDspAudioSink wrapper = new FloatDspAudioSink(sink, processor);
        wrapper.configure(source(44100, 2, C.ENCODING_PCM_16BIT), 0, null);
        ByteBuffer old = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder());
        old.putShort((short) 7).putShort((short) 8).flip();
        assertFalse(wrapper.handleBuffer(old, 10, 1));
        wrapper.configure(source(96000, 2, C.ENCODING_PCM_16BIT).buildUpon()
                .setEncoderDelay(1).setEncoderPadding(1).build(), 0, null);
        assertEquals(44100, lastConfigured(sink).sampleRate);
        assertTrue(wrapper.handleBuffer(old, 10, 1));
        assertEquals(96000, lastConfigured(sink).sampleRate);
        assertEquals(1, processor.calls);
        ByteBuffer next = ByteBuffer.allocateDirect(12).order(ByteOrder.nativeOrder());
        next.putShort((short) 1).putShort((short) 2).putShort((short) 10).putShort((short) 11)
                .putShort((short) 20).putShort((short) 21).flip();
        assertTrue(wrapper.handleBuffer(next, 20, 1));
        ByteBuffer raw = ByteBuffer.wrap(processor.raw).order(ByteOrder.nativeOrder());
        assertEquals(10, raw.getShort());
        assertEquals(11, raw.getShort());
    }

    @Test
    public void channelEditorUsesActualSampleByteWidthsForAllSupportedEncodings() {
        for (int encoding : new int[] {C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT,
                C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT}) {
            int bytes = encoding == C.ENCODING_PCM_16BIT ? 2 : encoding == C.ENCODING_PCM_24BIT ? 3 : 4;
            Format format = source(48000, 2, encoding).buildUpon()
                    .setEncoderDelay(1).setEncoderPadding(1).build();
            FloatDspAudioSink.PcmFrameEditor editor = new FloatDspAudioSink.PcmFrameEditor(format, new int[] {1});
            byte[] original = new byte[bytes * 8];
            for (int i = 0; i < original.length; i++) original[i] = (byte) (i * 11 + 3);
            ByteBuffer input = ByteBuffer.allocateDirect(original.length);
            input.put(original).flip();
            ByteBuffer output = editor.prepare(input);
            assertEquals(0, input.position());
            byte[] actual = new byte[bytes * 2];
            output.get(actual);
            byte[] expected = new byte[bytes * 2];
            System.arraycopy(original, bytes * 3, expected, 0, bytes);
            System.arraycopy(original, bytes * 5, expected, bytes, bytes);
            org.junit.Assert.assertArrayEquals(expected, actual);
            editor.commit();
            editor.endOfStream();
            assertEquals(0, editor.tailSize);
        }
    }

    @Test
    public void aaudioGaplessFailureTransfersOnlyUnacceptedFramesAndRetainsPaddingState() throws Exception {
        AAudioAudioSinkTest.FakeBridge bridge = new AAudioAudioSinkTest.FakeBridge();
        bridge.writeResult = 4;
        AAudioAudioSink direct = new AAudioAudioSink(false, 50);
        direct.setBridgeForTest(bridge);
        Format format = source(48000, 2, C.ENCODING_PCM_16BIT).buildUpon()
                .setEncoderDelay(1).setEncoderPadding(1).build();
        direct.configure(format, 0, null);
        ByteBuffer input = ByteBuffer.allocateDirect(16).order(ByteOrder.nativeOrder());
        input.putShort((short) 1).putShort((short) 2).putShort((short) 10).putShort((short) 11)
                .putShort((short) 20).putShort((short) 21).putShort((short) 30).putShort((short) 31).flip();
        assertFalse(direct.handleBuffer(input, 77, 1));
        bridge.writeResult = -1;
        try { direct.handleBuffer(input, 99, 2); org.junit.Assert.fail(); }
        catch (AudioSink.WriteException expected) { assertEquals(0, input.position()); }
        NativeDspAudioProcessor unavailable = new NativeDspAudioProcessor() {
            @Override boolean isNativeAvailableForConfiguration() { return false; }
        };
        FakeSink platform = new FakeSink();
        FloatDspAudioSink fallback = new FloatDspAudioSink(platform, unavailable, true, true);
        fallback.configure(format, 0, null);
        direct.transferPendingTo(fallback);
        assertTrue(fallback.handleBuffer(input, 100, 3));
        assertEquals(Long.valueOf(77), platform.writtenTimes.get(0));
        ByteBuffer next = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder());
        next.putShort((short) 40).putShort((short) 41).flip();
        assertTrue(fallback.handleBuffer(next, 120, 1));
        ByteBuffer written = ByteBuffer.allocate(8).order(ByteOrder.nativeOrder());
        for (byte b : platform.accepted) written.put(b);
        written.flip();
        assertEquals(20, written.getShort());
        assertEquals(21, written.getShort());
        assertEquals(30, written.getShort());
        assertEquals(31, written.getShort());
        fallback.playToEndOfStream();
        direct.release();
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
