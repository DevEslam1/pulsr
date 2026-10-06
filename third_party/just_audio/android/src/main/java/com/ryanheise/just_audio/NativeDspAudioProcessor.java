package com.ryanheise.just_audio;

import android.os.Build;
import android.util.Log;
import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.BaseAudioProcessor;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.locks.ReentrantReadWriteLock;

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

    // Lifetime safety. The playback thread takes the READ side around every JNI
    // call (queueInput/onFlush/onReset/resetNativeState); release() takes the
    // WRITE side so it can never destroy the engine while a native call is in
    // flight. The handle is an AtomicLong so release()/finalize()/Cleaner are
    // idempotent via getAndSet(0) and can never double-destroy.
    private final AtomicLong nativeEngineHandle = new AtomicLong(0);
    private final ReentrantReadWriteLock engineLock = new ReentrantReadWriteLock();

    // Volatile mirror of the configured input sample rate, written on the
    // playback thread (onConfigure/onFlush) and read from the method-channel
    // thread (setGainCurve) without touching the non-volatile AudioFormat.
    private volatile int sampleRate = 0;
    // Last (sampleRate, channelCount) pushed to nativeResyncForTrack. Playback
    // thread only. Lets onFlush skip a resync when nothing changed, so a
    // same-rate seek/gapless transition does not regenerate the reverb IR.
    private int lastResyncSampleRate = -1;
    private int lastResyncChannels = -1;

    private boolean loggedJniFailure = false;
    private boolean loggedShortProcess = false;
    private volatile Object cleanToken;

    // Cleaner on API 33+; loaded lazily so older runtimes never resolve the
    // java.lang.ref.Cleaner class. The token is kept as Object on purpose so
    // this class does not link Cleaner on pre-33 devices.
    private static final class CleanerHolder {
        static final java.lang.ref.Cleaner CLEANER = java.lang.ref.Cleaner.create();
        static Object register(Object target, AtomicLong handle) {
            return CLEANER.register(target, new EngineDestroyer(handle));
        }
        static void clean(Object token) {
            if (token != null) {
                ((java.lang.ref.Cleaner.Cleanable) token).clean();
            }
        }
    }

    private static final class EngineDestroyer implements Runnable {
        private final AtomicLong handle;
        EngineDestroyer(AtomicLong handle) { this.handle = handle; }
        @Override public void run() {
            long h = handle.getAndSet(0);
            if (h != 0 && NATIVE_AVAILABLE) {
                try {
                    nativeDestroyEngine(h);
                } catch (RuntimeException | UnsatisfiedLinkError e) {
                    Log.w(TAG, "nativeDestroyEngine (cleaner) failed: " + e.getMessage());
                }
            }
        }
    }

    private void logJniFailureOnce(String call, Throwable t) {
        if (!loggedJniFailure) {
            loggedJniFailure = true;
            Log.w(TAG, call + " failed; passing audio through unprocessed: " + t.getMessage());
        }
    }

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
                nativeEngineHandle.set(nativeCreateEngine());
            } catch (RuntimeException | UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeCreateEngine failed: " + e.getMessage());
                nativeEngineHandle.set(0);
            }
        }
        // API 33+: deterministic cleanup via Cleaner instead of relying on
        // finalize(). Older runtimes keep finalize() (below), which calls the
        // same idempotent release().
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && nativeEngineHandle.get() != 0) {
            cleanToken = CleanerHolder.register(this, nativeEngineHandle);
        }
    }

    public void release() {
        // Write lock: waits for any in-flight native call (read side) before
        // destroying. getAndSet(0) makes release()/finalize()/Cleaner mutually
        // idempotent, so the engine can never be double-destroyed.
        engineLock.writeLock().lock();
        try {
            long h = nativeEngineHandle.getAndSet(0);
            if (h != 0 && NATIVE_AVAILABLE) {
                try {
                    nativeDestroyEngine(h);
                } catch (RuntimeException | UnsatisfiedLinkError e) {
                    Log.w(TAG, "nativeDestroyEngine failed: " + e.getMessage());
                }
            }
            Object token = cleanToken;
            cleanToken = null;
            if (token != null) {
                CleanerHolder.clean(token);
            }
        } finally {
            engineLock.writeLock().unlock();
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
    private int rampSegmentMs = 0;      // duration of one curve segment, ms
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
        if (!isNativeReady() || gains == null || gains.length == 0 || segmentMs <= 0) {
            return false;
        }
        float[] curve = new float[gains.length];
        for (int i = 0; i < gains.length; i++) {
            float g = (float) gains[i];
            curve[i] = Math.max(0.0f, Math.min(1.0f, g));
        }
        synchronized (rampLock) {
            rampGains = curve;
            // Segment frames are derived in queueInput from the CURRENT input
            // sample rate (see below), never captured here: the sink may be
            // reconfigured between arming and the next buffer.
            rampSegmentMs = segmentMs;
            rampPosFrames = 0;
            staticGain = curve[0]; // first curve gain applies immediately
        }
        return true;
    }

    /**
     * True only when the processor is configured and active AND the native
     * engine is alive. {@link #setGainCurve} / {@link #clearGainCurve} return
     * this so callers fall back to stepped {@code setVolume()} whenever the sink
     * bypassed the processor.
     */
    private boolean isNativeReady() {
        if (!NATIVE_AVAILABLE || !isActive()) return false;
        engineLock.readLock().lock();
        try {
            return nativeEngineHandle.get() != 0;
        } finally {
            engineLock.readLock().unlock();
        }
    }

    /**
     * Drops any armed curve and restores transparent unity gain.
     *
     * @return true if the native DSP chain is active.
     */
    public boolean clearGainCurve() {
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentMs = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        return isNativeReady();
    }

    private ByteBuffer scratch;
    // Independent of the sleep/crossfade curve: profile edits may temporarily
    // fade the complete chain without replacing another owner's envelope.
    private volatile boolean transitionMuted;
    private volatile float transitionGain = 1.0f;
    public boolean setTransitionMuted(boolean muted) {
        transitionMuted = muted;
        return NATIVE_AVAILABLE;
    }
    public float getTransitionGain() { return transitionGain; }
    private FloatBuffer scratchFloats;

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
        // Publish the rate for the method-channel thread and force the next
        // onFlush to push this format to the native engine.
        sampleRate = inputAudioFormat.sampleRate;
        lastResyncSampleRate = -1;
        lastResyncChannels = -1;
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
        boolean bitPerfect = false;
        if (NATIVE_AVAILABLE) {
            // Read side: release() (write side) cannot destroy the engine while
            // we are inside the native call.
            engineLock.readLock().lock();
            try {
                final long handle = nativeEngineHandle.get();
                if (handle != 0) {
                    try {
                        processed = nativeProcessDirectFloatBuffer(
                                handle, scratch, 0, frameCount, channelCount);
                        bitPerfect = processed < 0;
                        if (bitPerfect) processed = -processed;
                    } catch (RuntimeException | UnsatisfiedLinkError e) {
                        // A JNI RuntimeException must never escape queueInput.
                        logJniFailureOnce("nativeProcessDirectFloatBuffer", e);
                        processed = frameCount;
                        bitPerfect = false;
                    }
                }
            } finally {
                engineLock.readLock().unlock();
            }
        }
        if (processed <= 0 || processed > frameCount) {
            // Engine declined the block; scratch still holds the untouched input.
            processed = frameCount;
            bitPerfect = false;
        } else if (processed < frameCount) {
            // The engine processed only part of the block. Never drop the tail:
            // the un-processed remainder is still the original input in scratch,
            // so emit the whole block (processed head + raw tail) through the
            // gain path.
            if (!loggedShortProcess) {
                loggedShortProcess = true;
                Log.w(TAG, "nativeProcess returned " + processed + " of " + frameCount
                        + " frames; passing the remainder through unprocessed");
            }
            processed = frameCount;
            bitPerfect = false;
        }

        boolean hasActiveGainCurve;
        synchronized (rampLock) {
            hasActiveGainCurve = (rampGains != null || Math.abs(staticGain - 1.0f) > 0.0001f);
        }
        if (transitionMuted || Math.abs(transitionGain - 1.0f) > 0.0001f) {
            hasActiveGainCurve = true;
        }

        if (bitPerfect && !hasActiveGainCurve) {
            clearGainCurve();
            ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
            ByteBuffer original = inputBuffer.duplicate();
            original.limit(position + processed * inputAudioFormat.bytesPerFrame);
            output.put(original);
            output.flip();
            inputBuffer.position(limit);
            return;
        }

        // Snapshot ramp state and consume the frames we are about to emit.
        // When the curve is exhausted it transitions into a static gain equal
        // to its last value, so a fade-out stays silent and a fade-in becomes
        // transparent instead of leaving a stale curve behind.
        float[] curve;
        int segFrames;
        long startPos;
        float idleGain;
        // Segment frames are computed from the CURRENT input rate, not captured
        // when the curve was armed, so a reconfigure between arm and buffer is
        // respected.
        final int curSampleRate = inputAudioFormat.sampleRate > 0
                ? inputAudioFormat.sampleRate : sampleRate;
        synchronized (rampLock) {
            curve = rampGains;
            if (curve != null) {
                final double sr = curSampleRate > 0 ? curSampleRate : 48000.0;
                segFrames = Math.max(1,
                        (int) Math.round(sr * (double) rampSegmentMs / 1000.0));
            } else {
                segFrames = 0;
            }
            startPos = rampPosFrames;
            idleGain = staticGain;
            if (curve != null) {
                rampPosFrames += processed;
                if (rampPosFrames >= (long) (curve.length - 1) * segFrames) {
                    staticGain = curve[curve.length - 1];
                    rampGains = null;
                    rampSegmentMs = 0;
                    rampPosFrames = 0;
                }
            } else if (bitPerfect && Math.abs(staticGain - 1.0f) > 0.0001f) {
                staticGain = 1.0f;
            }
        }

        final int lastIdx = curve == null ? 0 : curve.length - 1;
        final boolean outputIsFloat = outputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        float profileGain = transitionGain;
        final float profileTarget = transitionMuted ? 0.0f : 1.0f;
        final float profileStep = 1.0f / Math.max(1, inputAudioFormat.sampleRate * 0.04f);
        for (int i = 0; i < processed * channelCount; i++) {
            if (i % channelCount == 0) {
                profileGain = profileTarget < profileGain
                        ? Math.max(profileTarget, profileGain - profileStep)
                        : Math.min(profileTarget, profileGain + profileStep);
            }
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
            } else if (bitPerfect && Math.abs(idleGain - 1.0f) > 0.0001f) {
                float frac = (float) (i / channelCount) / Math.max(1, processed);
                gain = idleGain + (1.0f - idleGain) * frac;
            }
            float value = floats.get(i) * gain * profileGain;
            if (outputIsFloat) {
                // Emit straight float32: no 16-bit re-quantisation after DSP.
                output.putFloat(value);
            } else {
                output.putShort(Pcm16Quantizer.fromFloat(value));
            }
        }
        transitionGain = profileGain;
        inputBuffer.position(limit);
        output.flip();
    }

    @Override
    protected void onFlush() {
        final int sr = inputAudioFormat.sampleRate;
        final int ch = inputAudioFormat.channelCount;
        // Publish the rate for other threads (setGainCurve).
        sampleRate = sr;
        if (NATIVE_AVAILABLE && sr > 0) {
            engineLock.readLock().lock();
            try {
                final long handle = nativeEngineHandle.get();
                // Only resync when the format actually changed. A seek at the
                // same rate must not regenerate the reverb IR / allocate.
                if (handle != 0 && (sr != lastResyncSampleRate || ch != lastResyncChannels)) {
                    try {
                        nativeResyncForTrack(handle, sr, ch);
                        lastResyncSampleRate = sr;
                        lastResyncChannels = ch;
                    } catch (RuntimeException | UnsatisfiedLinkError e) {
                        Log.w(TAG, "nativeResyncForTrack failed: " + e.getMessage());
                    }
                }
            } finally {
                engineLock.readLock().unlock();
            }
        }
        // NOTE: a completed fade-out (rampGains == null, staticGain == 0) is
        // deliberately NOT reset to unity here. onFlush also runs for gapless
        // configure transitions, and resetting would make a finished sleep
        // fade-out jump back to full volume across the transition. staticGain is
        // only cleared by an explicit clearGainCurve() or a full onReset().
        // An in-flight curve (rampPosFrames > 0) is likewise preserved.
    }

    @Override
    protected void onReset() {
        transitionMuted = false;
        transitionGain = 1.0f;
        scratch = null;
        scratchFloats = null;
        synchronized (rampLock) {
            rampGains = null;
            rampSegmentMs = 0;
            rampPosFrames = 0;
            staticGain = 1.0f;
        }
        resetNativeEngineLocked();
        lastResyncSampleRate = -1;
        lastResyncChannels = -1;
    }

    /**
     * Clears the native engine's processing state (filter history, reverb tails,
     * limiter envelopes) without reconfiguring it. Called by
     * {@code FloatDspAudioSink.flush()} on seek/discontinuity so a reverb tail
     * from the old position cannot bleed into the new one. Does not regenerate
     * the reverb IR.
     */
    public void resetNativeState() {
        resetNativeEngineLocked();
        lastResyncSampleRate = -1;
        lastResyncChannels = -1;
    }

    private void resetNativeEngineLocked() {
        if (!NATIVE_AVAILABLE) return;
        engineLock.readLock().lock();
        try {
            final long handle = nativeEngineHandle.get();
            if (handle != 0) {
                try {
                    nativeResetEngine(handle);
                } catch (RuntimeException | UnsatisfiedLinkError e) {
                    Log.w(TAG, "nativeResetEngine failed: " + e.getMessage());
                }
            }
        } finally {
            engineLock.readLock().unlock();
        }
    }

    private FloatBuffer ensureScratch(int sampleCount) {
        if (scratch == null || scratch.capacity() < sampleCount * 4) {
            int targetBytes = Math.max(sampleCount * 4, scratch == null ? 16384 : scratch.capacity() * 2);
            scratch = ByteBuffer.allocateDirect(targetBytes).order(ByteOrder.nativeOrder());
            scratchFloats = scratch.asFloatBuffer();
        }
        return scratchFloats;
    }
}
