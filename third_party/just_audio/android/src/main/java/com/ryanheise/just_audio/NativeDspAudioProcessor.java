package com.ryanheise.just_audio;

import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

/**
 * Feeds ExoPlayer's PCM stream through Pulsr's native DSP chain (libpulsr_dsp).
 *
 * The library only ever sees 16-bit PCM here: DefaultAudioSink inserts
 * ToInt16PcmAudioProcessor ahead of the chain whenever float output is off,
 * which is always the case for this player.
 */
public class NativeDspAudioProcessor extends BaseAudioProcessor {
    private static final String TAG = "NativeDspAudioProcessor";
    private static final boolean NATIVE_AVAILABLE = loadNativeLibrary();

    private static boolean loadNativeLibrary() {
        try {
            System.loadLibrary("pulsr_dsp");
            return true;
        } catch (UnsatisfiedLinkError | SecurityException e) {
            Log.w(TAG, "libpulsr_dsp unavailable, native DSP stays bypassed: " + e.getMessage());
            return false;
        }
    }

    private static native int nativeProcessDirectFloatBuffer(
            ByteBuffer buffer, int offsetBytes, int frameCount, int channels);

    private static native void nativeResyncForTrack(double sampleRate, int channels);

    private ByteBuffer scratch;
    private FloatBuffer scratchFloats;

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
        if (!NATIVE_AVAILABLE || inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            return AudioFormat.NOT_SET;
        }
        return inputAudioFormat;
    }

    @Override
    public void queueInput(ByteBuffer inputBuffer) {
        int position = inputBuffer.position();
        int limit = inputBuffer.limit();
        int frameCount = (limit - position) / inputAudioFormat.bytesPerFrame;
        if (frameCount <= 0) {
            inputBuffer.position(limit);
            return;
        }
        int channelCount = inputAudioFormat.channelCount;
        FloatBuffer floats = ensureScratch(frameCount * channelCount);

        for (int i = 0; i < frameCount * channelCount; i++) {
            floats.put(i, inputBuffer.getShort(position + i * 2) / 32768f);
        }

        int processed = nativeProcessDirectFloatBuffer(scratch, 0, frameCount, channelCount);
        if (processed <= 0 || processed > frameCount) {
            // Engine declined the block; scratch still holds the untouched input.
            processed = frameCount;
        }

        ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        for (int i = 0; i < processed * channelCount; i++) {
            int sample = Math.round(floats.get(i) * 32768f);
            output.putShort((short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, sample)));
        }
        inputBuffer.position(limit);
        output.flip();
    }

    @Override
    protected void onFlush() {
        if (NATIVE_AVAILABLE && inputAudioFormat.sampleRate > 0) {
            nativeResyncForTrack(inputAudioFormat.sampleRate, inputAudioFormat.channelCount);
        }
    }

    @Override
    protected void onReset() {
        scratch = null;
        scratchFloats = null;
    }

    private FloatBuffer ensureScratch(int sampleCount) {
        if (scratch == null || scratch.capacity() < sampleCount * 4) {
            scratch = ByteBuffer.allocateDirect(sampleCount * 4).order(ByteOrder.nativeOrder());
            scratchFloats = scratch.asFloatBuffer();
        }
        return scratchFloats;
    }
}
