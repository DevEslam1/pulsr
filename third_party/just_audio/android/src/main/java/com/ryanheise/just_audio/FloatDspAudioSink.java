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
    // Pre-sized so handleBuffer never allocates in steady state.
    private static final int PRESIZE_SAMPLES = 32768;

    private final NativeDspAudioProcessor processor;
    private final boolean forceFloatForPcm16;
    private boolean processFloat;
    private int inputEncoding;
    // Reusable conversion staging: direct float bytes + a reusable decode array.
    private ByteBuffer converted;
    private FloatBuffer convertedFloats;
    private float[] decodeScratch;
    private ByteBuffer pendingOutput;
    private ByteBuffer pendingInput;
    // Last configured (sampleRate, channelCount, pcmEncoding) so a gapless
    // same-format configure can skip the processor configure/flush cycle.
    private int lastSampleRate = -1;
    private int lastChannelCount = -1;
    private int lastPcmEncoding = C.ENCODING_INVALID;
    private boolean loggedRemainder;

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
        super(delegate);
        this.processor = processor;
        this.forceFloatForPcm16 = forceFloatForPcm16;
        if (this.processor != null) {
            this.processor.setFloatOutput(true);
        }
    }

    @Override
    public void configure(Format format, int bufferSize, int[] outputChannels)
            throws ConfigurationException {
        pendingOutput = null;
        pendingInput = null;
        inputEncoding = format.pcmEncoding;

        final int encoding = format.pcmEncoding;
        final boolean supported = encoding == C.ENCODING_PCM_FLOAT
                || encoding == C.ENCODING_PCM_16BIT
                || encoding == C.ENCODING_PCM_24BIT
                || encoding == C.ENCODING_PCM_32BIT;
        // A 16-bit source may bypass the wrapper when the caller opts out of
        // forcing float for PCM16 (bit-perfect / DSP-off).
        final boolean bypass16 = !forceFloatForPcm16 && encoding == C.ENCODING_PCM_16BIT;

        if (processor == null || !supported || bypass16) {
            if (processor != null && !supported) {
                // Once per configure: an unsupported encoding silently bypasses
                // the whole DSP chain, which is worth surfacing.
                Log.w(TAG, "Unsupported PCM encoding " + encoding
                        + "; native DSP bypassed for this format");
            }
            processFloat = false;
            super.configure(format, bufferSize, outputChannels);
            return;
        }

        // Gapless same-format transition: the processor is still active with the
        // same input format, so do NOT configure/flush it (that would reset the
        // native state and regenerate the reverb IR). Pending buffers are
        // cleared above.
        final boolean sameFormat = processFloat
                && format.sampleRate == lastSampleRate
                && format.channelCount == lastChannelCount
                && encoding == lastPcmEncoding;
        if (sameFormat) {
            super.configure(format.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build(),
                    bufferSize, outputChannels);
            return;
        }

        try {
            processor.configure(new AudioProcessor.AudioFormat(
                    format.sampleRate, format.channelCount, C.ENCODING_PCM_FLOAT));
            processor.flush();
            processFloat = processor.isActive();
        } catch (AudioProcessor.UnhandledAudioFormatException e) {
            throw new ConfigurationException(e, format);
        }
        if (processFloat) {
            lastSampleRate = format.sampleRate;
            lastChannelCount = format.channelCount;
            lastPcmEncoding = encoding;
            ensureConvertCapacity(PRESIZE_SAMPLES);
        }
        super.configure(processFloat
                ? format.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
                : format, bufferSize, outputChannels);
    }

    @Override
    public boolean handleBuffer(ByteBuffer input, long presentationTimeUs, int accessUnits)
            throws InitializationException, WriteException {
        if (!input.hasRemaining()) return true;
        if (!processFloat || processor == null) {
            return super.handleBuffer(input, presentationTimeUs, accessUnits);
        }
        if (pendingOutput == null) {
            ByteBuffer pcm = input.duplicate().order(ByteOrder.nativeOrder());
            if (inputEncoding != C.ENCODING_PCM_FLOAT) {
                pcm = convertToFloat(pcm);
            }
            processor.queueInput(pcm);
            if (pcm.hasRemaining()) {
                // Never silently leave bytes unconsumed: surface it once, then
                // drop the remainder explicitly.
                if (!loggedRemainder) {
                    loggedRemainder = true;
                    Log.w(TAG, "processor left " + pcm.remaining()
                            + " bytes unconsumed; dropping the remainder");
                }
                pcm.position(pcm.limit());
            }
            pendingOutput = processor.getOutput();
            pendingInput = input;
        } else if (pendingInput != input) {
            throw new IllegalStateException("Retry the same PCM buffer until the sink consumes it");
        }
        if (!super.handleBuffer(pendingOutput, presentationTimeUs, accessUnits)) return false;
        input.position(input.limit());
        pendingOutput = null;
        pendingInput = null;
        return true;
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
        pendingOutput = null;
        pendingInput = null;
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
        pendingOutput = null;
        pendingInput = null;
        converted = null;
        convertedFloats = null;
        decodeScratch = null;
        lastSampleRate = -1;
        lastChannelCount = -1;
        lastPcmEncoding = C.ENCODING_INVALID;
        if (processFloat && processor != null) processor.reset();
        processFloat = false;
        super.reset();
    }

    /**
     * Bulk-converts a non-float PCM buffer into the reusable direct float
     * staging buffer. 24-bit keeps the existing little-endian unpacking.
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
            for (int i = 0; i < samples; i++) {
                final int b0 = pcm.get() & 0xff;
                final int b1 = pcm.get() & 0xff;
                final int b2 = pcm.get();
                final int value = (b0 << 8) | (b1 << 16) | (b2 << 24);
                out[i] = (float) (value / 2147483648.0);
            }
        } else {
            final IntBuffer ints = pcm.asIntBuffer();
            for (int i = 0; i < samples; i++) {
                out[i] = ints.get(i) / 2147483648f;
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
}
