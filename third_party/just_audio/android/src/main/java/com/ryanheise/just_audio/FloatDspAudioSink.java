package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Media3 omits custom processors on float output; tap high-resolution PCM here. */
@androidx.media3.common.util.UnstableApi
final class FloatDspAudioSink extends ForwardingAudioSink {
    private final NativeDspAudioProcessor processor;
    private boolean processFloat;
    private int inputEncoding;
    private ByteBuffer converted;
    private ByteBuffer pendingOutput;
    private ByteBuffer pendingInput;

    FloatDspAudioSink(AudioSink delegate, NativeDspAudioProcessor processor) {
        super(delegate);
        this.processor = processor;
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
        processFloat = inputEncoding == C.ENCODING_PCM_FLOAT
                || inputEncoding == C.ENCODING_PCM_24BIT
                || inputEncoding == C.ENCODING_PCM_32BIT;
        if (processFloat) {
            try {
                processor.configure(new AudioProcessor.AudioFormat(
                        format.sampleRate, format.channelCount, C.ENCODING_PCM_FLOAT));
                processor.flush();
                processFloat = processor.isActive();
            } catch (AudioProcessor.UnhandledAudioFormatException e) {
                throw new ConfigurationException(e, format);
            }
        }
        super.configure(processFloat
                ? format.buildUpon().setPcmEncoding(C.ENCODING_PCM_FLOAT).build()
                : format, bufferSize, outputChannels);
    }

    @Override
    public boolean handleBuffer(ByteBuffer input, long presentationTimeUs, int accessUnits)
            throws InitializationException, WriteException {
        if (!processFloat) return super.handleBuffer(input, presentationTimeUs, accessUnits);
        if (pendingOutput == null) {
            ByteBuffer pcm = input.duplicate().order(ByteOrder.nativeOrder());
            if (inputEncoding != C.ENCODING_PCM_FLOAT) {
                int sampleBytes = inputEncoding == C.ENCODING_PCM_16BIT ? 2
                        : (inputEncoding == C.ENCODING_PCM_24BIT ? 3 : 4);
                int samples = pcm.remaining() / sampleBytes;
                int outputBytes = samples * 4;
                if (converted == null || converted.capacity() < outputBytes) {
                    converted = ByteBuffer.allocateDirect(outputBytes).order(ByteOrder.nativeOrder());
                }
                converted.clear();
                for (int i = 0; i < samples; i++) {
                    float floatVal;
                    if (inputEncoding == C.ENCODING_PCM_16BIT) {
                        floatVal = pcm.getShort() / 32768.0f;
                    } else if (inputEncoding == C.ENCODING_PCM_24BIT) {
                        int value = ((pcm.get() & 0xff) << 8) | ((pcm.get() & 0xff) << 16) | (pcm.get() << 24);
                        floatVal = (float) (value / 2147483648.0);
                    } else {
                        int value = pcm.getInt();
                        floatVal = (float) (value / 2147483648.0);
                    }
                    converted.putFloat(floatVal);
                }
                converted.flip();
                pcm = converted;
            }
            processor.queueInput(pcm);
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
        if (processFloat) processor.flush();
        super.flush();
    }

    @Override
    public void reset() {
        pendingOutput = null;
        pendingInput = null;
        converted = null;
        if (processFloat) processor.reset();
        processFloat = false;
        super.reset();
    }
}
