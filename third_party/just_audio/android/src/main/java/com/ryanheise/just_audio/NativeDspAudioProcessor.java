package com.ryanheise.just_audio;

import android.os.Build;
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
 * <p>Default (16-bit) mode: DefaultAudioSink inserts ToInt16PcmAudioProcessor
 * ahead of the chain, so this processor reads {@code ENCODING_PCM_16BIT},
 * expands it to float for the native engine and re-quantises the result back to
 * 16-bit — exactly the historical behaviour.
 *
 * <p>Float mode (opt-in, off by default): when {@link #setFloatOutput(boolean)}
 * is enabled and the sink offers {@code ENCODING_PCM_FLOAT}, the decoded float
 * samples go straight to the native engine (it already processes arbitrary
 * float blocks) and are emitted as float again, avoiding the per-sample 16-bit
 * re-quantisation at the end of the chain. If the sink still delivers 16-bit,
 * the processor transparently keeps the 16-bit behaviour so playback is never
 * interrupted.
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

    private static native long nativeCreateEngine();
    private static native void nativeDestroyEngine(long engineHandle);
    private static native void nativeResetEngine(long engineHandle);
    private static native int nativeProcessDirectFloatBuffer(
            long engineHandle, ByteBuffer buffer, int offsetBytes, int frameCount, int channels);
    private static native void nativeResyncForTrack(
            long engineHandle, double sampleRate, int channels);

    private long nativeEngineHandle = 0;

    // Pulsr fork: opt-in 24/32-bit float path. Off by default so the sink
    // pipeline (and therefore the audible result) is byte-identical to the
    // historical 16-bit-only behaviour unless the user enables it.
    private volatile boolean floatOutputEnabled = false;

    /**
     * Enables/disables the float32 DSP path. Safe to call before or after the
     * sink is configured; a change after configuration only takes effect when
     * the sink is rebuilt (the media3 pipeline fixes its encodings at
     * configure time).
     */
    public void setFloatOutput(boolean enabled) {
        // Float AudioTrack output exists from API 21; minSdk is well above it,
        // but degrading to 16-bit is cheaper than risking a silent sink.
        this.floatOutputEnabled = enabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP;
    }

    public boolean isFloatOutputEnabled() {
        return floatOutputEnabled;
    }

    public NativeDspAudioProcessor() {
        if (NATIVE_AVAILABLE) {
            try {
                nativeEngineHandle = nativeCreateEngine();
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeCreateEngine failed: " + e.getMessage());
                nativeEngineHandle = 0;
            }
        }
    }

    public void release() {
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            long handle = nativeEngineHandle;
            nativeEngineHandle = 0;
            try {
                nativeDestroyEngine(handle);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeDestroyEngine failed: " + e.getMessage());
            }
        }
    }

    @Override
    protected void finalize() throws Throwable {
        try {
            release();
        } finally {
            super.finalize();
        }
    }

    // ---- Pulsr fork: sample-accurate gain ramp ----
    // Per-instance state (one processor per AudioPlayer) so the two crossfade
    // players ramp independently. Applied AFTER the native DSP chain so the
    // limiter/EQ still see the un-attenuated signal and the ramp can only
    // attenuate (gains are clamped to [0, 1]).
    private final Object rampLock = new Object();
    private float[] rampGains = null;   // null => no ramp armed (transparent unity)
    private int rampSegmentFrames = 0;  // frames covered by one curve segment
    private long rampPosFrames = 0;     // frames consumed since the curve started
    private float staticGain = 1.0f;    // gain applied when no curve is armed

    /**
     * Arms a piecewise-linear gain curve applied per-sample from the next
     * queued buffer. The first gain takes effect immediately, one gain per
     * {@code segmentMs}, and the last gain is held once the curve is exhausted
     * (it becomes the static gain until {@link #clearGainCurve()} is called).
     *
     * @return true if the curve was armed (native DSP chain active), false if
     *         the caller must fall back to stepped setVolume().
     */
    public boolean setGainCurve(double[] gains, int segmentMs) {
        if (!NATIVE_AVAILABLE || gains == null || gains.length == 0 || segmentMs <= 0) {
            return false;
        }
        double sampleRate = inputAudioFormat.sampleRate;
        if (sampleRate <= 0) sampleRate = 48000.0; // sink not configured yet; close enough
        int segFrames = Math.max(1, (int) Math.round(sampleRate * segmentMs / 1000.0));
        float[] curve = new float[gains.length];
        for (int i = 0; i < gains.length; i++) {
            float g = (float) gains[i];
            curve[i] = Math.max(0.0f, Math.min(1.0f, g));
        }
        synchronized (rampLock) {
            rampGains = curve;
            rampSegmentFrames = segFrames;
            rampPosFrames = 0;
            staticGain = curve[0]; // first curve gain applies immediately
        }
        return true;
    }

    /**
     * Drops any armed curve and restores transparent unity gain.
     *
     * @return true if the state was reset (native DSP chain active).
     */
    public boolean clearGainCurve() {
        if (!NATIVE_AVAILABLE) {
            return false;
        }
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentFrames = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        return true;
    }

    private ByteBuffer scratch;
    private FloatBuffer scratchFloats;

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
        if (!NATIVE_AVAILABLE) {
            return AudioFormat.NOT_SET;
        }
        // 16-bit is the historical path and stays accepted unconditionally.
        if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            return inputAudioFormat;
        }
        // Float is only accepted when the opt-in float path is enabled; when it
        // is off this returns NOT_SET exactly as before, so ExoPlayer inserts
        // ToInt16PcmAudioProcessor ahead of the chain.
        if (floatOutputEnabled && inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) {
            return inputAudioFormat;
        }
        return AudioFormat.NOT_SET;
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

        final int channelCount = inputAudioFormat.channelCount;
        final boolean inputIsFloat = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        FloatBuffer floats = ensureScratch(frameCount * channelCount);

        if (inputIsFloat) {
            for (int i = 0; i < frameCount * channelCount; i++) {
                floats.put(i, inputBuffer.getFloat(position + i * 4));
            }
        } else {
            for (int i = 0; i < frameCount * channelCount; i++) {
                floats.put(i, inputBuffer.getShort(position + i * 2) / 32768f);
            }
        }

        int processed = frameCount;
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            try {
                processed = nativeProcessDirectFloatBuffer(
                        nativeEngineHandle, scratch, 0, frameCount, channelCount);
            } catch (UnsatisfiedLinkError e) {
                processed = frameCount;
            }
        }
        if (processed <= 0 || processed > frameCount) {
            // Engine declined the block; scratch still holds the untouched input.
            processed = frameCount;
        }

        // Snapshot ramp state and consume the frames we are about to emit.
        // When the curve is exhausted it transitions into a static gain equal
        // to its last value, so a fade-out stays silent and a fade-in becomes
        // transparent instead of leaving a stale curve behind.
        float[] curve;
        int segFrames;
        long startPos;
        float idleGain;
        synchronized (rampLock) {
            curve = rampGains;
            segFrames = rampSegmentFrames;
            startPos = rampPosFrames;
            idleGain = staticGain;
            if (curve != null) {
                rampPosFrames += processed;
                if (rampPosFrames >= (long) (curve.length - 1) * segFrames) {
                    staticGain = curve[curve.length - 1];
                    rampGains = null;
                    rampSegmentFrames = 0;
                    rampPosFrames = 0;
                }
            }
        }

        final int lastIdx = curve == null ? 0 : curve.length - 1;
        final boolean outputIsFloat = outputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        for (int i = 0; i < processed * channelCount; i++) {
            float gain = idleGain;
            if (curve != null) {
                // Piecewise-linear interpolation between curve points, per frame.
                long frame = i / channelCount;
                double exact = (startPos + frame) / (double) segFrames;
                int seg = (int) exact;
                if (seg >= lastIdx) {
                    gain = curve[lastIdx];
                } else {
                    float frac = (float) (exact - seg);
                    gain = curve[seg] + (curve[seg + 1] - curve[seg]) * frac;
                }
            }
            float value = floats.get(i) * gain;
            if (outputIsFloat) {
                // Emit straight float32: no 16-bit re-quantisation after DSP.
                output.putFloat(value);
            } else {
                float scaled = value * (value < 0.0f ? 32768f : 32767f);
                int sample = Math.round(scaled);
                output.putShort((short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, sample)));
            }
        }
        inputBuffer.position(limit);
        output.flip();
    }

    @Override
    protected void onFlush() {
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0 && inputAudioFormat.sampleRate > 0) {
            try {
                nativeResyncForTrack(nativeEngineHandle, inputAudioFormat.sampleRate, inputAudioFormat.channelCount);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeResyncForTrack failed: " + e.getMessage());
            }
        }
        synchronized (rampLock) {
            if (rampGains == null) {
                staticGain = 1.0f;
            }
        }
        // Media3/ExoPlayer flushes on ordinary seeks within the same stream,
        // not only on genuinely new sources. Do NOT reset an in-flight curve
        // (rampPosFrames > 0), otherwise a seek snaps an active fade-out back
        // to full volume (rampGains[0]). A newly armed curve already sets
        // rampPosFrames = 0 and staticGain = rampGains[0] in setGainCurve().
    }

    @Override
    protected void onReset() {
        scratch = null;
        scratchFloats = null;
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentFrames = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        if (NATIVE_AVAILABLE && nativeEngineHandle != 0) {
            try {
                nativeResetEngine(nativeEngineHandle);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeResetEngine failed: " + e.getMessage());
            }
        }
    }

    private FloatBuffer ensureScratch(int sampleCount) {
        if (scratch == null || scratch.capacity() < sampleCount * 4) {
            scratch = ByteBuffer.allocateDirect(sampleCount * 4).order(ByteOrder.nativeOrder());
            scratchFloats = scratch.asFloatBuffer();
        }
        return scratchFloats;
    }
}
