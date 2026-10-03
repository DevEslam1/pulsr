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

    public static void main(String[] args) throws Exception {
        check(AaudioNativeBridge.ensureAvailable(), "library must load");
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        processor.configure(new AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_16BIT));
        processor.flush();
        try {
            // The native engine bypasses all stages; Java must also bypass its ramp.
            for (boolean bypass : new boolean[] {true, false, true, false}) {
                // Arm every native stage when bypassing; isolate the Java gain
                // ramp when processing so a limiter delay cannot mask the test.
                AudioEffectsPlugin.nativeSetActiveStages(bypass ? -1 : 0);
                AudioEffectsPlugin.nativeSetBitPerfectParams(bypass, false);
                processor.setGainCurve(new double[] {0.5, 0.5}, 1);
                ByteBuffer input = pcm16();
                processor.queueInput(input);
                ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
                check(output.remaining() == 65536 * 2, "frame count must survive toggle");
                for (int sample = Short.MIN_VALUE; sample <= Short.MAX_VALUE; sample++) {
                    short expected = bypass ? (short) sample : Pcm16Quantizer.fromFloat(sample / 32768f * 0.5f);
                    short actual = output.getShort();
                    check(actual == expected, "PCM16 mismatch bypass=" + bypass + " sample=" + sample + " expected=" + expected + " actual=" + actual);
                }
            }
            processor.setFloatOutput(true);
            processor.configure(new AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT));
            processor.flush();
            AudioEffectsPlugin.nativeSetBitPerfectParams(true, false);
            AudioEffectsPlugin.nativeSetActiveStages(-1);
            processor.setGainCurve(new double[] {0.2, 0.2}, 1);
            int[] patterns = {0, 0x80000000, 0x3f800000, 0xbf800000, 0x7fc01234, 0x7f800000};
            ByteBuffer floats = ByteBuffer.allocateDirect(patterns.length * 4).order(ByteOrder.nativeOrder());
            for (int pattern : patterns) floats.putInt(pattern);
            floats.flip();
            processor.queueInput(floats);
            ByteBuffer output = processor.getOutput().order(ByteOrder.nativeOrder());
            for (int pattern : patterns) check(output.getInt() == pattern, "float bypass must preserve every bit");
        } finally {
            AudioEffectsPlugin.nativeSetBitPerfectParams(false, false);
            AudioEffectsPlugin.nativeSetActiveStages(0);
            processor.release();
        }
        System.out.println("PASS: actual Java/JNI PCM16 ON/OFF/ON/OFF and float bitwise bypass, including gain-ramp suppression");
    }
}
