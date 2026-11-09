package com.ryanheise.just_audio;

import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.ShortBuffer;

/**
 * Media3 omits custom processors on float output; tap high-resolution PCM here
 * and feed it through {@link NativeDspAudioProcessor}.
 *
 * <p><b>Contract.</b> The delegate {@link AudioSink} must be built with
 * {@code enableFloatOutput(true)} and the {@link NativeDspAudioProcessor} must
 * NOT also be in the delegate's AudioProcessor chain. With float output the
 * delegate is built with no processors, so this wrapper is the only path into
 * the native DSP chain; if the processor were also in the chain, 16-bit audio
 * would be processed twice.
 *
 * <p>16-bit input is converted to float here and re-quantised back to 16-bit
 * by the processor, unless {@code forceFloatForPcm16} is false, in which case a
 * 16-bit source bypasses the wrapper entirely and stays a native 16-bit
 * AudioTrack.
 */
@androidx.media3.common.util.UnstableApi
final class FloatDspAudioSink extends ForwardingAudioSink {
    private static final String TAG = "FloatDspAudioSink";
    // Decoded input telemetry is session-scoped in PulsrAudioSink/PulsrOutputRouting.
    // Pre-sized so handleBuffer never allocates in steady state.
    private static final int PRESIZE_SAMPLES = 32768;

    private final NativeDspAudioProcessor processor;
    private final boolean forceFloatForPcm16;
    private final boolean pcm16Boundary;
    private ByteBuffer quantizedOutput;
    private boolean processFloat;
    private int inputEncoding;
    // Reusable conversion staging: direct float bytes + a reusable decode array.
    private ByteBuffer converted;
    private FloatBuffer convertedFloats;
    private float[] decodeScratch;
    private ByteBuffer pendingOutput;
    private ByteBuffer pendingInput;
    private int pendingInputEnd;
    private long pendingPresentationTimeUs;
    private int pendingAccessUnits;
    private AudioProcessor.AudioFormat processorOutputFormat = AudioProcessor.AudioFormat.NOT_SET;
    // Last configured (sampleRate, channelCount, pcmEncoding) so a gapless
    // same-format configure can skip the processor configure/flush cycle.
    private int lastSampleRate = -1;
    private int lastChannelCount = -1;
    private int lastPcmEncoding = C.ENCODING_INVALID;
    private PcmFrameEditor frameEditor;
    private Format lastInputFormat;
    private Format configuredOutputFormat;
    private int lastBufferSize;
    private boolean eosQueued;
    private Format deferredFormat;
    private int deferredBufferSize;
    private int[] deferredChannels;

    /** Shared byte-preserving gapless editor; no conversion precedes the native tee. */
    static final class PcmFrameEditor {
        final int sampleBytes;
        final int inputFrameBytes;
        final int outputFrameBytes;
        final int[] channels;
        final boolean remapped;
        final int initialDelayBytes;
        int delayBytes;
        byte[] tail;
        int tailSize;
        ByteBuffer staging;
        byte[] nextTail;
        int nextTailSize;
        int nextDelay;
        boolean started;

        PcmFrameEditor(Format format, int[] mapping) {
            sampleBytes = format.pcmEncoding == C.ENCODING_PCM_16BIT ? 2
                    : format.pcmEncoding == C.ENCODING_PCM_24BIT ? 3 : 4;
            inputFrameBytes = sampleBytes * format.channelCount;
            channels = mapping == null ? null : mapping.clone();
            boolean changed = mapping != null && mapping.length != format.channelCount;
            if (mapping != null) {
                if (mapping.length == 0) throw new IllegalArgumentException("Empty channel map");
                for (int i = 0; i < mapping.length; i++) {
                    if (mapping[i] < 0 || mapping[i] >= format.channelCount)
                        throw new IllegalArgumentException("Invalid channel map");
                    changed |= mapping[i] != i;
                }
            }
            remapped = changed;
            outputFrameBytes = sampleBytes * (mapping == null ? format.channelCount : mapping.length);
            initialDelayBytes = Math.multiplyExact(Math.max(0, format.encoderDelay), inputFrameBytes);
            delayBytes = initialDelayBytes;
            tail = new byte[Math.multiplyExact(Math.max(0, format.encoderPadding), inputFrameBytes)];
            nextTail = new byte[tail.length];
        }

        boolean edits() { return delayBytes != 0 || tail.length != 0 || remapped; }

        ByteBuffer prepare(ByteBuffer source) {
            if (source.remaining() % inputFrameBytes != 0)
                throw new IllegalArgumentException("Incomplete PCM frame");
            if (!edits()) return source.duplicate().order(ByteOrder.nativeOrder());
            int skipped = Math.min(delayBytes, source.remaining());
            nextDelay = delayBytes - skipped;
            int available = tailSize + source.remaining() - skipped;
            int emitBytes = Math.max(0, available - tail.length);
            int outputBytes = emitBytes / inputFrameBytes * outputFrameBytes;
            if (staging == null || staging.capacity() < outputBytes)
                staging = ByteBuffer.allocateDirect(Math.max(16384, outputBytes)).order(ByteOrder.nativeOrder());
            staging.clear();
            for (int f = 0; f < emitBytes; f += inputFrameBytes) {
                int count = outputFrameBytes / sampleBytes;
                for (int c = 0; c < count; c++) {
                    int channel = channels == null ? c : channels[c];
                    for (int b = 0; b < sampleBytes; b++)
                        staging.put(byteAt(source, skipped, f + channel * sampleBytes + b));
                }
            }
            nextTailSize = available - emitBytes;
            for (int i = 0; i < nextTailSize; i++)
                nextTail[i] = byteAt(source, skipped, emitBytes + i);
            staging.flip();
            return staging;
        }

        private byte byteAt(ByteBuffer source, int skipped, int index) {
            return index < tailSize ? tail[index]
                    : source.get(source.position() + skipped + index - tailSize);
        }

        void commit() {
            if (!edits()) return;
            started = true;
            delayBytes = nextDelay;
            byte[] old = tail;
            tail = nextTail;
            nextTail = old;
            tailSize = nextTailSize;
        }

        void flush() { tailSize = 0; delayBytes = started ? 0 : initialDelayBytes; }
        void endOfStream() { tailSize = 0; }
    }

    FloatDspAudioSink(AudioSink delegate, NativeDspAudioProcessor processor) {
        this(delegate, processor, true);
    }

    /**
     * @param forceFloatForPcm16 when true (default), 16-bit PCM is routed through
     *     the native DSP chain as float. When false, 16-bit sources bypass the
     *     wrapper and remain a native 16-bit AudioTrack (bit-perfect / DSP-off).
     */
    FloatDspAudioSink(AudioSink delegate, NativeDspAudioProcessor processor,
            boolean forceFloatForPcm16) {
        this(delegate, processor, forceFloatForPcm16, false);
    }

    FloatDspAudioSink(AudioSink delegate, NativeDspAudioProcessor processor,
            boolean forceFloatForPcm16, boolean pcm16Boundary) {
        super(delegate);
        this.processor = processor;
        this.forceFloatForPcm16 = forceFloatForPcm16;
        this.pcm16Boundary = pcm16Boundary;
        if (this.processor != null) {
            this.processor.setFloatOutput(true);
        }
    }

    @Override
    public int getFormatSupport(Format format) {
        if (processor != null && format.pcmEncoding == C.ENCODING_PCM_32BIT) {
            int support = super.getFormatSupport(
                    format.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build());
            // Float has only 24 significant bits. Accept playback, never claim
            // a direct/exact int32 path merely because both containers are 4 bytes.
            return support == SINK_FORMAT_UNSUPPORTED ? support
                    : SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
        }
        return super.getFormatSupport(format);
    }

    @Override
    public boolean supportsFormat(Format format) {
        return getFormatSupport(format) != SINK_FORMAT_UNSUPPORTED;
    }

    @Override
    public void configure(Format format, int bufferSize, int[] outputChannels)
            throws ConfigurationException {
        if (pendingInput != null) {
            deferredFormat = format;
            deferredBufferSize = bufferSize;
            deferredChannels = outputChannels == null ? null : outputChannels.clone();
            return;
        }
        final int encoding = format.pcmEncoding;
        final boolean sameInput = processFloat
                && format.sampleRate == lastSampleRate
                && format.channelCount == lastChannelCount
                && encoding == lastPcmEncoding;
        inputEncoding = encoding;
        // Telemetry is owned by PulsrAudioSink per player, not last configure globals.
        Log.i(TAG, "decoded PCM " + pcmEncodingName(encoding)
                + " @ " + format.sampleRate + " Hz, " + format.channelCount + "ch");

        final boolean supported = encoding == C.ENCODING_PCM_FLOAT
                || encoding == C.ENCODING_PCM_16BIT
                || encoding == C.ENCODING_PCM_24BIT
                || encoding == C.ENCODING_PCM_32BIT;
        final boolean bypass16 = !forceFloatForPcm16 && encoding == C.ENCODING_PCM_16BIT;
        if (processor == null || !supported || bypass16) {
            frameEditor = null;
            lastInputFormat = format;
            if (processor != null && !supported) {
                Log.w(TAG, "Unsupported PCM encoding " + encoding
                        + "; native DSP bypassed for this format");
            }
            pendingOutput = null;
            pendingInput = null;
            processFloat = false;
            processorOutputFormat = AudioProcessor.AudioFormat.NOT_SET;
            super.configure(format, bufferSize, outputChannels);
            return;
        }

        try {
            // An identical configure during a partial write is negotiation, not
            // a new stream: keep its tail and declared trimming state.
            if (pendingInput == null || frameEditor == null) {
                frameEditor = new PcmFrameEditor(format, outputChannels);
            }
        } catch (IllegalArgumentException | ArithmeticException e) {
            throw new ConfigurationException(e, format);
        }
        lastInputFormat = format;
        lastBufferSize = bufferSize;
        eosQueued = false;
        final int mappedChannels = outputChannels == null ? format.channelCount : outputChannels.length;
        final AudioProcessor.AudioFormat output;
        try {
            // Re-evaluate even on identical decoded input: the SRC target or
            // native bit-perfect policy may have changed since the last track.
            output = processor.configure(new AudioProcessor.AudioFormat(
                    format.sampleRate, mappedChannels, C.ENCODING_PCM_FLOAT));
        } catch (AudioProcessor.UnhandledAudioFormatException e) {
            throw new ConfigurationException(e, format);
        }
        final boolean active = !output.equals(AudioProcessor.AudioFormat.NOT_SET)
                && processor.isActive();
        final boolean sameFormat = sameInput && active && output.equals(processorOutputFormat);
        if (!sameFormat) {
            pendingOutput = null;
            pendingInput = null;
            processor.flush();
        }
        processFloat = active;
        processorOutputFormat = active ? output : AudioProcessor.AudioFormat.NOT_SET;
        if (active) {
            lastSampleRate = format.sampleRate;
            lastChannelCount = format.channelCount;
            lastPcmEncoding = encoding;
            ensureConvertCapacity(PRESIZE_SAMPLES);
            if (encoding == C.ENCODING_PCM_32BIT) {
                Log.w(TAG, "int32 PCM converted to float32 (24 significant bits); not bit-perfect");
            }
        }
        try {
            configuredOutputFormat = format.buildUpon()
                    .setSampleRate(active ? output.sampleRate : format.sampleRate)
                    .setChannelCount(active ? output.channelCount : mappedChannels)
                    .setPcmEncoding(pcm16Boundary ? C.ENCODING_PCM_16BIT : (active ? output.encoding : encoding))
                    .setEncoderDelay(0).setEncoderPadding(0).build();
            super.configure(configuredOutputFormat, bufferSize, null);
        } catch (RuntimeException e) {
            throw new ConfigurationException(e, format);
        }
    }

    @Override
    public boolean handleBuffer(ByteBuffer input, long presentationTimeUs, int accessUnits)
            throws InitializationException, WriteException {
        if (!input.hasRemaining()) return true;
        if ((!processFloat || processor == null) && frameEditor == null) {
            return super.handleBuffer(input, presentationTimeUs, accessUnits);
        }
        if (pendingOutput == null) {
            final boolean edited = frameEditor != null && frameEditor.edits();
            ByteBuffer original = frameEditor == null ? input.duplicate().order(ByteOrder.nativeOrder())
                    : frameEditor.prepare(input);
            ByteBuffer pcm = original.duplicate().order(ByteOrder.nativeOrder());
            final int sampleBytes = inputEncoding == C.ENCODING_PCM_16BIT ? 2
                    : inputEncoding == C.ENCODING_PCM_24BIT ? 3 : 4;
            if (processFloat && processor != null) {
                if (inputEncoding != C.ENCODING_PCM_FLOAT) pcm = convertToFloat(pcm);
                final int pcmStart = pcm.position();
                if (inputEncoding == C.ENCODING_PCM_FLOAT || (frameEditor != null && frameEditor.remapped)) {
                    processor.queueInput(pcm);
                } else {
                    // Capture BEFORE conversion; packed conversion advances only its own view.
                    processor.queueInput(pcm, original, sampleBytes * 8, lastInputFormat.sampleRate);
                }
                pendingInputEnd = edited ? input.limit()
                        : input.position() + (pcm.position() - pcmStart) / 4 * sampleBytes;
                pendingOutput = boundaryOutput(processor.getOutput(), processorOutputFormat.encoding);
            } else {
                pendingInputEnd = input.limit();
                pendingOutput = boundaryOutput(pcm, inputEncoding);
            }
            if (edited) frameEditor.commit();
            pendingInput = input;
            pendingPresentationTimeUs = presentationTimeUs;
            pendingAccessUnits = accessUnits;
        } else if (pendingInput != input) {
            throw new IllegalStateException("Retry the same PCM buffer until the sink consumes it");
        }
        // An SRC may buffer input without emitting frames yet. Empty output is
        // not an AudioSink write, but the consumed source bytes still advance.
        if (pendingOutput.hasRemaining() && !super.handleBuffer(pendingOutput,
                pendingPresentationTimeUs, pendingAccessUnits)) return false;
        input.position(pendingInputEnd);
        pendingOutput = null;
        pendingInput = null;
        try {
            applyDeferredConfiguration();
        } catch (ConfigurationException e) {
            throw new InitializationException(0, lastInputFormat.sampleRate, lastInputFormat.channelCount,
                    lastInputFormat.pcmEncoding, lastInputFormat.pcmEncoding, lastInputFormat, false, e);
        }
        return !input.hasRemaining();
    }

    private void applyDeferredConfiguration() throws ConfigurationException {
        if (deferredFormat == null) return;
        Format next = deferredFormat;
        int[] channels = deferredChannels;
        deferredFormat = null;
        PcmFrameEditor previous = frameEditor;
        Format previousFormat = lastInputFormat;
        configure(next, deferredBufferSize, channels);
        if (previous != null && next.equals(previousFormat)
                && java.util.Arrays.equals(previous.channels, channels)) frameEditor = previous;
    }

    /** Quantize once, after DSP, never by dropping packed integer low bytes. */
    private ByteBuffer boundaryOutput(ByteBuffer output, int encoding) {
        if (!pcm16Boundary || encoding == C.ENCODING_PCM_16BIT) return output;
        int bytes = encoding == C.ENCODING_PCM_24BIT ? 3 : 4;
        int samples = output.remaining() / bytes;
        if (quantizedOutput == null || quantizedOutput.capacity() < samples * 2)
            quantizedOutput = ByteBuffer.allocateDirect(Math.max(16384, samples * 2)).order(ByteOrder.nativeOrder());
        quantizedOutput.clear();
        ByteBuffer input = output.duplicate().order(ByteOrder.nativeOrder());
        for (int i = 0; i < samples; i++) {
            if (encoding == C.ENCODING_PCM_FLOAT) {
                quantizedOutput.putShort(Pcm16Quantizer.fromFloat(input.getFloat()));
            } else {
                int code;
                if (bytes == 3) {
                    code = (input.get() & 0xff) | ((input.get() & 0xff) << 8) | (input.get() << 16);
                } else {
                    code = input.getInt();
                }
                double scaled = code / (bytes == 3 ? 256.0 : 65536.0);
                double dither = 0;
                if (scaled != Math.rint(scaled)) {
                    java.util.concurrent.ThreadLocalRandom rng = java.util.concurrent.ThreadLocalRandom.current();
                    dither = rng.nextDouble() - rng.nextDouble();
                }
                long quantized = Math.round(scaled + dither);
                quantizedOutput.putShort((short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, quantized)));
            }
        }
        quantizedOutput.flip();
        return quantizedOutput;
    }

    void acceptPreparedPcm(ByteBuffer pcm, int encoding, ByteBuffer input, int inputEnd,
            long timeUs, int units, PcmFrameEditor editor) {
        frameEditor = editor;
        if (pcm == null) return;
        ByteBuffer view = pcm.duplicate().order(ByteOrder.nativeOrder());
        if (processFloat && processor != null) {
            if (encoding == C.ENCODING_PCM_FLOAT) {
                processor.queueInput(view);
            } else {
                int previousEncoding = inputEncoding;
                inputEncoding = encoding;
                ByteBuffer floats = convertToFloat(view.duplicate().order(ByteOrder.nativeOrder()));
                inputEncoding = previousEncoding;
                processor.queueInput(floats, view, editor.sampleBytes * 8, lastInputFormat.sampleRate);
            }
            pendingOutput = boundaryOutput(processor.getOutput(), processorOutputFormat.encoding);
        } else {
            pendingOutput = boundaryOutput(view, encoding);
        }
        pendingInput = input;
        pendingInputEnd = inputEnd;
        pendingPresentationTimeUs = timeUs;
        pendingAccessUnits = units;
    }

    boolean hasStagedInput() { return pendingInput != null; }
    PcmFrameEditor frameEditor() { return frameEditor; }

    /** Configure the track for already-processed bytes, not the queued source. */
    void configurePendingReplacement(FloatDspAudioSink target) throws ConfigurationException {
        target.configure(lastInputFormat, lastBufferSize, frameEditor.channels);
        if (target.configuredOutputFormat.sampleRate != configuredOutputFormat.sampleRate
                || target.configuredOutputFormat.channelCount != configuredOutputFormat.channelCount) {
            // A new route/SRC target affects future input only. Its old-rate tail
            // must still reach the replacement track at the rate it was produced.
            target.deferredFormat = lastInputFormat;
            target.deferredBufferSize = lastBufferSize;
            target.deferredChannels = frameEditor.channels;
            target.configurePendingTrack(configuredOutputFormat);
        }
    }

    private void configurePendingTrack(Format pendingFormat) throws ConfigurationException {
        configuredOutputFormat = configuredOutputFormat.buildUpon()
                .setSampleRate(pendingFormat.sampleRate)
                .setChannelCount(pendingFormat.channelCount).build();
        super.configure(configuredOutputFormat, lastBufferSize, null);
    }

    void transferPendingTo(FloatDspAudioSink target) {
        if (deferredFormat != null) {
            target.deferredFormat = deferredFormat;
            target.deferredBufferSize = deferredBufferSize;
            target.deferredChannels = deferredChannels;
            deferredFormat = null;
            deferredChannels = null;
        }
        target.pendingOutput = pendingOutput == null ? null : target.boundaryOutput(pendingOutput,
                pcm16Boundary ? C.ENCODING_PCM_16BIT
                        : (processFloat ? processorOutputFormat.encoding : inputEncoding));
        target.pendingInput = pendingInput;
        target.pendingInputEnd = pendingInputEnd;
        target.pendingPresentationTimeUs = pendingPresentationTimeUs;
        target.pendingAccessUnits = pendingAccessUnits;
        target.frameEditor = frameEditor;
        pendingOutput = null;
        pendingInput = null;
    }

    @Override
    public void pause() {
        if (processor != null) processor.releaseUsbProducer();
        super.pause();
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        // Last declared padding is intentionally discarded, not emitted as music.
        if (!eosQueued && frameEditor != null) frameEditor.endOfStream();
        eosQueued = true;
        if (pendingOutput != null && pendingOutput.hasRemaining()) {
            try {
                if (!super.handleBuffer(pendingOutput, pendingPresentationTimeUs, pendingAccessUnits)) return;
            } catch (InitializationException e) {
                WriteException failure = new WriteException(-1, lastInputFormat, true);
                failure.initCause(e);
                throw failure;
            }
            if (pendingInput != null) pendingInput.position(pendingInputEnd);
            pendingOutput = null;
            pendingInput = null;
        }
        super.playToEndOfStream();
    }

    @Override
    public boolean hasPendingData() {
        return pendingOutput != null || super.hasPendingData();
    }

    @Override
    public boolean isEnded() {
        return pendingOutput == null && super.isEnded();
    }

    @Override
    public void flush() {
        eosQueued = false;
        if (frameEditor != null) frameEditor.flush();
        pendingOutput = null;
        pendingInput = null;
        try { applyDeferredConfiguration(); }
        catch (ConfigurationException e) { throw new IllegalStateException("Deferred PCM configuration failed", e); }
        if (processFloat && processor != null) {
            processor.flush();
            // Seek/discontinuity: clear the native engine state (filter history,
            // reverb tails, limiter envelopes) so audio from the old position
            // cannot bleed into the new one. Does not regenerate the reverb IR.
            processor.resetNativeState();
        }
        super.flush();
    }

    @Override
    public void reset() {
        frameEditor = null;
        deferredFormat = null;
        deferredChannels = null;
        quantizedOutput = null;
        lastInputFormat = null;
        eosQueued = false;
        if (processor != null) processor.releaseUsbProducer();
        pendingOutput = null;
        pendingInput = null;
        converted = null;
        convertedFloats = null;
        decodeScratch = null;
        lastSampleRate = -1;
        lastChannelCount = -1;
        lastPcmEncoding = C.ENCODING_INVALID;
        processorOutputFormat = AudioProcessor.AudioFormat.NOT_SET;
        if (processFloat && processor != null) processor.reset();
        processFloat = false;
        super.reset();
    }

    /**
     * Bulk-converts a non-float PCM buffer into the reusable direct float
     * staging buffer.
     *
     * <ul>
     *   <li>16-bit: sign-extended short → float via ÷32768.
     *   <li>24-bit: corrected LE packed unpack (b0|b1«8|b2«16, arithmetic
     *       sign-extended via «8»8) then ÷2^23. The previous implementation
     *       had a wrong byte-shift order that produced tonal distortion on
     *       24-bit FLAC files (BUG-1 fix).
     *   <li>32-bit: int32 → float via ÷2^31.
     * </ul>
     */
    private ByteBuffer convertToFloat(ByteBuffer pcm) {
        final int sampleBytes = inputEncoding == C.ENCODING_PCM_16BIT ? 2
                : (inputEncoding == C.ENCODING_PCM_24BIT ? 3 : 4);
        final int samples = pcm.remaining() / sampleBytes;
        ensureConvertCapacity(samples);
        final float[] out = decodeScratch;
        if (inputEncoding == C.ENCODING_PCM_16BIT) {
            final ShortBuffer shorts = pcm.asShortBuffer();
            for (int i = 0; i < samples; i++) {
                out[i] = shorts.get(i) / 32768f;
            }
        } else if (inputEncoding == C.ENCODING_PCM_24BIT) {
            // Correct little-endian packed 24-bit (PCM_24BIT_PACKED) unpack:
            // bytes arrive as [LSB, MID, MSB]; assemble as b0 | (b1<<8) | (b2<<16),
            // then arithmetic-sign-extend to 32-bit via a left/right 8-bit shift,
            // and normalise by 2^23 (not 2^31) so full-scale → ±1.0f exactly.
            for (int i = 0; i < samples; i++) {
                final int b0 = pcm.get() & 0xff;   // LSB  (bits  7..0 of sample)
                final int b1 = pcm.get() & 0xff;   // MID  (bits 15..8 of sample)
                final int b2 = pcm.get() & 0xff;   // MSB  (bits 23..16 of sample, unsigned first)
                // Pack into the lower 24 bits, then sign-extend to 32-bit via
                // a paired arithmetic-shift (works on all Java VMs).
                final int unsigned24 = b0 | (b1 << 8) | (b2 << 16);
                final int signed32   = (unsigned24 << 8) >> 8;   // arithmetic sign-extend
                out[i] = (float) (signed32 / 8388608.0);         // ÷ 2^23
            }
        } else {
            final IntBuffer ints = pcm.asIntBuffer();
            for (int i = 0; i < samples; i++) {
                // Scaling via double does NOT preserve int32 low bits: the
                // final float still has only 24 significant bits. This is an
                // explicitly lossy playback path, not an exact integer bypass.
                out[i] = (float) (ints.get(i) * (1.0 / 2147483648.0));
            }
        }
        converted.clear();
        convertedFloats.clear();
        convertedFloats.put(out, 0, samples);
        converted.limit(samples * 4);
        converted.position(0);
        return converted;
    }

    private void ensureConvertCapacity(int samples) {
        if (converted != null && decodeScratch != null
                && converted.capacity() >= samples * 4 && decodeScratch.length >= samples) {
            return;
        }
        final int capacitySamples = Math.max(samples, PRESIZE_SAMPLES);
        converted = ByteBuffer.allocateDirect(capacitySamples * 4).order(ByteOrder.nativeOrder());
        convertedFloats = converted.asFloatBuffer();
        decodeScratch = new float[capacitySamples];
    }

    /** Human-readable name for a C.ENCODING_PCM_* value (hi-res truth probe). */
    static String pcmEncodingName(int encoding) {
        switch (encoding) {
            case C.ENCODING_PCM_16BIT: return "16-bit";
            case C.ENCODING_PCM_24BIT: return "24-bit";
            case C.ENCODING_PCM_32BIT: return "32-bit";
            case C.ENCODING_PCM_FLOAT: return "float";
            default: return "enc#" + encoding;
        }
    }
}
