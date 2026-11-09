package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import com.pulsr.music.AudioEffectsPlugin;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** Runs the actual Media3 PCM tap and JNI engine through repeated ON/OFF cycles. */
public final class NativeDspSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static ByteBuffer pcm16() {
        ByteBuffer buffer = ByteBuffer.allocateDirect(65536 * 2).order(ByteOrder.nativeOrder());
        for (int sample = Short.MIN_VALUE; sample <= Short.MAX_VALUE; sample++) {
            buffer.putShort((short) sample);
        }
        return buffer.flip();
    }

    private static float[] renderWarmth(NativeDspAudioProcessor processor,
            int rate, double drive, double mix, double tilt) throws Exception {
        processor.configure(new AudioProcessor.AudioFormat(rate, 2, C.ENCODING_PCM_FLOAT));
        processor.flush();
        processor.setGainCurve(new double[] {1, 1}, 1);
        AudioEffectsPlugin.nativeSetSaturationParams(drive, mix, tilt, 0, false);
        AudioEffectsPlugin.nativeSetSaturationEnabled(true);
        AudioEffectsPlugin.nativeSetActiveStages(1 << 6);
        int frames = rate / 10;
        float[] measured = new float[frames];
        for (int block = 0; block < 10; ++block) {
            ByteBuffer input = ByteBuffer.allocateDirect(frames * 8).order(ByteOrder.nativeOrder());
            for (int frame = 0; frame < frames; ++frame) {
                double time = (block * frames + frame) / (double) rate;
                float sample = (float) (0.25 * Math.sin(2 * Math.PI * 400 * time)
                        + 0.08 * Math.sin(2 * Math.PI * 1200 * time));
                input.putFloat(sample).putFloat(sample);
            }
            processor.queueInput(input.flip());
            ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
            check(output.remaining() == frames * 8, "warmth must preserve frame count");
            for (int frame = 0; frame < frames; ++frame) {
                float left = output.getFloat(), right = output.getFloat();
                check(Float.isFinite(left) && Math.abs(left) <= 1, "warmth must stay finite/bounded");
                check(left == right, "warmth must preserve matched stereo input");
                measured[frame] = left;
            }
        }
        return measured;
    }

    private static void checkQuranWarmth(NativeDspAudioProcessor processor) throws Exception {
        for (int rate : new int[] {44100, 48000}) {
            for (double drive : new double[] {0.15, 0.18, 0.20, 0.22}) {
                float[] zero = renderWarmth(processor, rate, drive, 0, 0.3);
                float[] middle = renderWarmth(processor, rate, drive, 0.3, 0.3);
                float[] maximum = renderWarmth(processor, rate, drive, 0.6, 0.3);
                double deltaMiddle = 0, deltaMaximum = 0, energy = 0;
                for (int i = 0; i < zero.length; ++i) {
                    deltaMiddle += Math.pow(middle[i] - zero[i], 2);
                    deltaMaximum += Math.pow(maximum[i] - zero[i], 2);
                    energy += zero[i] * zero[i];
                }
                double ratio = Math.sqrt(deltaMaximum / energy);
                check(ratio > 0.001, "Quran warmth at profile drive must change PCM");
                check(deltaMaximum > deltaMiddle * 2.5,
                        "increasing warmth must increase its measured contribution");
                System.out.println("Warmth " + rate + "Hz drive=" + drive
                        + " measured relative PCM difference=" + ratio);
            }
        }
        AudioEffectsPlugin.nativeSetSaturationEnabled(false);
        AudioEffectsPlugin.nativeSetActiveStages(0);
    }

    private static void checkTapSrc(NativeDspAudioProcessor processor) throws Exception {
        AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
        AudioEffectsPlugin.nativeSetActiveStages(0);
        processor.setFloatOutput(true);
        processor.setGainCurve(new double[] {1, 1}, 1);
        for (int[] rates : new int[][] {{44100, 48000}, {96000, 48000}, {48000, 8000}}) {
            processor.setTapSrcTargetRate(rates[1]);
            AudioProcessor.AudioFormat format = processor.configure(
                    new AudioProcessor.AudioFormat(rates[0], 2, C.ENCODING_PCM_FLOAT));
            check(format.sampleRate == rates[1], "tap SRC must declare its actual destination rate");
            processor.flush();
            check(processor.isTapSrcActive(), "tap SRC must be active after configure/flush");
            int outputFrames = 0;
            float last = 0;
            for (int block = 0; block < 24; block++) {
                ByteBuffer input = ByteBuffer.allocateDirect(2048 * 8).order(ByteOrder.nativeOrder());
                for (int frame = 0; frame < 2048; frame++) input.putFloat(0.25f).putFloat(0.25f);
                input.flip();
                processor.queueInput(input);
                check(!input.hasRemaining(), "successful SRC must consume its source");
                ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
                check(output.remaining() % 8 == 0, "SRC output must contain whole stereo frames");
                outputFrames += output.remaining() / 8;
                while (output.hasRemaining()) {
                    float left = output.getFloat(), right = output.getFloat();
                    check(Float.isFinite(left) && Math.abs(left) < 1, "SRC output must remain finite/bounded");
                    check(left == right, "SRC must preserve matched stereo channels");
                    last = left;
                }
            }
            double expectedFrames = 24 * 2048.0 * rates[1] / rates[0];
            check(Math.abs(outputFrames - expectedFrames) < 2048,
                    "SRC frame count must follow the declared conversion ratio");
            check(Math.abs(last - 0.25f) < 0.002f, "SRC must preserve steady-state unity gain");
        }
        processor.setTapSrcTargetRate(48000);
        processor.configure(new AudioProcessor.AudioFormat(6000, 2, C.ENCODING_PCM_FLOAT));
        processor.flush();
        ByteBuffer rejected = ByteBuffer.allocateDirect(64 * 8).order(ByteOrder.nativeOrder());
        for (int frame = 0; frame < 64; frame++) rejected.putFloat(0.25f).putFloat(0.25f);
        rejected.flip();
        try {
            processor.queueInput(rejected);
            throw new AssertionError("failed native SRC preparation must reject rather than prime");
        } catch (NativeDspAudioProcessor.TapSrcException expected) {
            check(rejected.position() == 0, "native SRC rejection must retain the source block");
        }
        AudioEffectsPlugin.nativeSetBitPerfectParams(true, false);
        processor.configure(new AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_FLOAT));
        processor.flush();
        check(!processor.isTapSrcActive(), "bit-perfect bypass must suppress tap SRC");
        processor.setTapSrcTargetRate(0);
        AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
    }

    public static void main(String[] args) throws Exception {
        check(AaudioNativeBridge.ensureAvailable(), "library must load");
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        processor.configure(new AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_16BIT));
        processor.flush();
        try {
            for (boolean bypass : new boolean[] {true, false, true, false}) {
                AudioEffectsPlugin.nativeSetActiveStages(bypass ? -1 : 0);
                AudioEffectsPlugin.nativeSetBitPerfectParams(bypass, false);
                for (double gain : new double[] {1, 0.5, 0}) {
                    processor.setGainCurve(new double[] {gain, gain}, 1);
                    ByteBuffer input = pcm16();
                    processor.queueInput(input);
                    ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
                    check(output.remaining() == 65536 * 2, "frame count must survive toggle");
                    for (int sample = Short.MIN_VALUE; sample <= Short.MAX_VALUE; sample++) {
                        double expected = sample * gain;
                        short actual = output.getShort();
                        double tolerance = expected == Math.rint(expected) ? 0 : 1.5;
                        check(Math.abs(actual - expected) <= tolerance,
                                "PCM16 mismatch bypass=" + bypass + " gain=" + gain
                                        + " sample=" + sample + " expected=" + expected + " actual=" + actual);
                    }
                }
            }
            processor.setFloatOutput(true);
            processor.configure(new AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT));
            processor.flush();
            AudioEffectsPlugin.nativeSetBitPerfectParams(true, false);
            AudioEffectsPlugin.nativeSetActiveStages(-1);
            processor.setGainCurve(new double[] {1, 1}, 1);
            int[] patterns = {0, 0x80000000, 0x3f800000, 0xbf800000, 0x7fc01234, 0x7f800000};
            ByteBuffer floats = ByteBuffer.allocateDirect(patterns.length * 4).order(ByteOrder.nativeOrder());
            for (int pattern : patterns) floats.putInt(pattern);
            floats.flip();
            processor.queueInput(floats);
            ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
            for (int pattern : patterns) check(output.getInt() == pattern, "float bypass must preserve every bit");
            AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
            AudioEffectsPlugin.nativeSetActiveStages(0);
            for (int rate : new int[] {44100, 48000}) {
                processor.configure(new AudioProcessor.AudioFormat(rate, 2, C.ENCODING_PCM_FLOAT));
                processor.flush();
                processor.setGainCurve(new double[] {0.5, 0.5}, 20);
                for (boolean muted : new boolean[] {true, false, true, false}) {
                    check(processor.setTransitionMuted(muted), "profile fade must be accepted");
                    int frames = rate / 20; // 50ms covers the entire 40ms fade.
                    ByteBuffer constant = ByteBuffer.allocateDirect(frames * 8).order(ByteOrder.nativeOrder());
                    for (int i = 0; i < frames * 2; ++i) constant.putFloat(0.5f);
                    processor.queueInput(constant.flip());
                    ByteBuffer faded = processor.getOutput().order(ByteOrder.nativeOrder());
                    float previous = muted ? 0.25f : 0.0f;
                    for (int frame = 0; frame < frames; ++frame) {
                        float left = faded.getFloat(), right = faded.getFloat();
                        check(left == right, "profile fade must preserve stereo balance");
                        check(Math.abs(left - previous) < 0.0002f,
                                "profile fade step rate=" + rate + " muted=" + muted
                                        + " frame=" + frame + " previous=" + previous + " actual=" + left);
                        check(left >= 0 && left <= 0.25001f, "sleep/crossfade gain must remain composed");
                        previous = left;
                    }
                    check(Math.abs(previous - (muted ? 0 : 0.25f)) < 0.00001f, "profile fade endpoint must be exact");
                    check(processor.getTransitionGain() == (muted ? 0 : 1), "fade acknowledgement must report rendered endpoint");
                }
            }
            checkQuranWarmth(processor);
            checkTapSrc(processor);
        } finally {
            AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
            AudioEffectsPlugin.nativeSetActiveStages(0);
            processor.release();
        }
        System.out.println("PASS: Java/JNI PCM16 unity bypass, effective transport gain/mute, float bit identity, profile fades, and configured tap SRC");
    }
}
