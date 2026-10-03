package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import com.pulsr.music.AudioEffectsPlugin;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Exercises the production float wrapper without requiring an AudioTrack. */
public final class FloatSinkSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static final class CaptureSink extends ForwardingAudioSink {
        ByteBuffer captured;
        boolean partial;
        int encoding;
        CaptureSink() { super(new AAudioAudioSink(false, 20)); }
        @Override public void configure(Format format, int size, int[] channels) {
            encoding = format.pcmEncoding;
        }
        @Override public boolean handleBuffer(ByteBuffer input, long time, int units) {
            if (!partial) {
                captured = ByteBuffer.allocate(input.remaining()).order(ByteOrder.nativeOrder());
                captured.putInt(input.getInt());
                partial = true;
                return false;
            }
            captured.put(input);
            captured.flip();
            partial = false;
            return true;
        }
        @Override public void flush() { partial = false; }
        @Override public void reset() { partial = false; }
    }

    public static void main(String[] args) throws Exception {
        check(AaudioNativeBridge.ensureAvailable(), "library must load");
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        processor.setFloatOutput(true);
        CaptureSink capture = new CaptureSink();
        FloatDspAudioSink sink = new FloatDspAudioSink(capture, processor);
        int[] encodings = {C.ENCODING_PCM_FLOAT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT};
        try {
            for (int encoding : encodings) {
                sink.configure(new Format.Builder().setSampleMimeType("audio/raw")
                        .setSampleRate(48000).setChannelCount(2).setPcmEncoding(encoding).build(), 0, null);
                check(capture.encoding == C.ENCODING_PCM_FLOAT, "delegate must receive float PCM");
                for (boolean bypass : new boolean[] {true, false, true, false}) {
                    AudioEffectsPlugin.nativeSetActiveStages(bypass ? -1 : 0);
                    AudioEffectsPlugin.nativeSetBitPerfectParams(bypass, false);
                    processor.setGainCurve(new double[] {0.5, 0.5}, 1);
                    ByteBuffer input = ByteBuffer.allocateDirect(24).order(ByteOrder.nativeOrder());
                    for (float sample : new float[] {0.5f, -0.5f, 0.25f, -0.25f}) {
                        if (encoding == C.ENCODING_PCM_FLOAT) input.putFloat(sample);
                        else if (encoding == C.ENCODING_PCM_32BIT) input.putInt((int) (sample * 2147483648.0));
                        else {
                            int value = (int) (sample * 8388608.0);
                            input.put((byte) value).put((byte) (value >> 8)).put((byte) (value >> 16));
                        }
                    }
                    input.flip();
                    check(!sink.handleBuffer(input, 0, 1), "partial delegate write must be retried");
                    check(input.position() == 0, "partial write must retain source buffer");
                    check(sink.hasPendingData(), "pending output must be visible");
                    check(sink.handleBuffer(input, 0, 1), "retry must finish");
                    check(!input.hasRemaining(), "source must be consumed after retry");
                    for (float sample : new float[] {0.5f, -0.5f, 0.25f, -0.25f}) {
                        float expected = sample * (bypass ? 1f : 0.5f);
                        check(capture.captured.getFloat() == expected, "float DSP toggle or duplicate processing failure");
                    }
                }
            }
            sink.flush();
            sink.reset();
        } finally {
            AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
            AudioEffectsPlugin.nativeSetActiveStages(0);
            processor.release();
        }
        System.out.println("PASS: production float sink PCM24/PCM32/float ON/OFF/ON/OFF and partial-write retries");
    }
}
