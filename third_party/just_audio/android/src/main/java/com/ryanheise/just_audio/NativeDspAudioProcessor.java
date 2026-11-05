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
            long engineHandle, ByteBuffer buffer, int offsetBytes, int frameCount, int channels,
            ByteBuffer gainBuffer);
    private static native int nativeResampleTap(
            long engineHandle, ByteBuffer inBuffer, int inFrames, int channels,
            ByteBuffer outBuffer, int maxOutFrames, double srcRate, double dstRate);
    private static native boolean nativeIsBitPerfect(long engineHandle);
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

    // Pulsr fork: tap-side SRC. The app pushes the current device output rate
    // (AudioManager PROPERTY_OUTPUT_SAMPLE_RATE / route probe); when it differs
    // from the source rate this processor declares it as its OUTPUT rate and
    // converts ahead of the native DSP chain (64-tap Blackman-Harris polyphase),
    // so the shared AudioTrack opens at the device rate and AudioFlinger's
    // resampler stays out of the signal path. 0 (default) = disabled: the
    // historical behaviour where AudioTrack opens at the source rate.
    private volatile int tapSrcTargetRate = 0;
    // Playback-thread mirror: true while the configured format is converted.
    private boolean tapSrcActive = false;

    /**
     * Sets the device output sample rate for tap-side SRC. A change takes
     * effect on the next configure (the media3 pipeline fixes formats then).
     */
    public void setTapSrcTargetRate(int rate) {
        this.tapSrcTargetRate = (rate >= 8000 && rate <= 768000) ? rate : 0;
    }

    public int getTapSrcTargetRate() {
        return tapSrcTargetRate;
    }

    public boolean isTapSrcActive() {
        return tapSrcActive;
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
    // players ramp independently. The per-frame gain is computed here but
    // applied INSIDE the native engine (ahead of its dither/noise-shaping
    // stage) via the gainBuffer argument of nativeProcessDirectFloatBuffer, so
    // the limiter/EQ still see the un-attenuated signal, the ramp can only
    // attenuate (gains are clamped to [0, 1]), and the gain never scales
    // already noise-shaped output. Java applies the gain itself only when the
    // native engine did not run (fallback path).
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

    /**
     * Carries an in-flight gain ramp / transition fade onto a replacement
     * processor when the output mode swaps its inner sink. Without this a
     * mode switch mid-fade would drop the envelope and jump to unity.
     * Runs on the playback thread; the method-channel thread may arm a curve
     * concurrently on either instance, hence both ramp locks.
     */
    void copyContinuousStateTo(NativeDspAudioProcessor target) {
        if (target == null || target == this) return;
        synchronized (rampLock) {
            synchronized (target.rampLock) {
                target.rampGains = rampGains == null ? null : rampGains.clone();
                target.rampSegmentMs = rampSegmentMs;
                target.rampPosFrames = rampPosFrames;
                target.staticGain = staticGain;
            }
        }
        target.transitionMuted = transitionMuted;
        target.transitionGain = transitionGain;
        target.tapSrcTargetRate = tapSrcTargetRate;
    }

    public boolean setTransitionMuted(boolean muted) {
        // Only claim success when the mute can actually be rendered: the DSP
        // chain must be configured and its native engine alive. Otherwise the
        // caller (a profile-change fade) should proceed unmuted instead of
        // polling a gain that can never move.
        if (!isNativeReady()) return false;
        transitionMuted = muted;
        return true;
    }
    public float getTransitionGain() { return transitionGain; }
    private FloatBuffer scratchFloats;

    @Override
    protected AudioFormat onConfigure(AudioFormat inputAudioFormat) {
        // Negotiate only. Media3 may configure while old output is pending;
        // the processing format becomes live on flush, not during negotiation.
        if (!isNativeAvailableForConfiguration()) {
            return AudioFormat.NOT_SET;
        }
        // 16-bit is the historical path and stays accepted unconditionally.
        // Float is only accepted when the opt-in float path is enabled; when it
        // is off this returns NOT_SET exactly as before, so ExoPlayer inserts
        // ToInt16PcmAudioProcessor ahead of the chain.
        final boolean accepted = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT
                || (floatOutputEnabled && inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT);
        if (!accepted) {
            return AudioFormat.NOT_SET;
        }
        // Tap-side SRC: declare the device rate as this processor's output rate
        // so the AudioTrack opens there and the conversion happens ahead of the
        // DSP chain. Never for bit-perfect playback: resampled bytes cannot be
        // sample-identical to the source, and the bit-perfect fast path copies
        // the ORIGINAL input bytes, which would then play at the wrong rate.
        final int target = tapSrcTargetRate;
        if (target >= 8000 && target <= 768000
                && inputAudioFormat.sampleRate > 0
                && target != inputAudioFormat.sampleRate
                && !isBitPerfectNative()) {
            return new AudioFormat(target, inputAudioFormat.channelCount,
                    inputAudioFormat.encoding);
        }
        return inputAudioFormat;
    }

    // Package-private configuration seams let host tests exercise the actual
    // format negotiation without loading an Android JNI library.
    boolean isNativeAvailableForConfiguration() {
        return NATIVE_AVAILABLE && nativeEngineHandle.get() != 0;
    }

    boolean isBitPerfectNative() {
        engineLock.readLock().lock();
        try {
            final long handle = nativeEngineHandle.get();
            if (handle == 0) return false;
            try {
                return nativeIsBitPerfect(handle);
            } catch (RuntimeException | UnsatisfiedLinkError e) {
                return false;
            }
        } finally {
            engineLock.readLock().unlock();
        }
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

        // ---- Tap-side SRC (input side of the DSP chain) ----
        // Runs BEFORE the engine so the whole chain (EQ coefficients, dither)
        // works at the declared output rate and dither stays the last stage.
        // Zero output (SRC priming or an unavailable engine) must not emit
        // source-rate bytes into a sink configured at the destination rate.
        int emitFrames = frameCount;
        FloatBuffer emitFloats = floats;
        ByteBuffer emitNativeBuffer = scratch;
        if (tapSrcActive) {
            final double ratio = (double) outputAudioFormat.sampleRate
                    / (double) inputAudioFormat.sampleRate;
            final int maxOut = (int) Math.ceil(frameCount * ratio)
                    + (int) Math.ceil(64.0 * ratio) + 32;
            FloatBuffer resampled = ensureResampleScratch(maxOut * channelCount);
            int got = 0;
            engineLock.readLock().lock();
            try {
                final long handle = nativeEngineHandle.get();
                if (handle != 0) {
                    try {
                        got = nativeResampleTap(handle, scratch, frameCount, channelCount,
                                resampleScratch, maxOut,
                                inputAudioFormat.sampleRate, outputAudioFormat.sampleRate);
                    } catch (RuntimeException | UnsatisfiedLinkError e) {
                        logJniFailureOnce("nativeResampleTap", e);
                    }
                }
            } finally {
                engineLock.readLock().unlock();
            }
            emitFrames = got > 0 && got <= maxOut ? got : 0;
            emitFloats = resampled;
            emitNativeBuffer = resampleScratch;
        }

        // ---- Transport gain, computed BEFORE the native call ----
        // The per-frame gain (crossfade/sleep curve x profile transition fade)
        // is handed to the engine so it lands ahead of the native dither /
        // noise-shaping stage instead of scaling already-shaped output. When
        // no gain is active we pass null and the bit-perfect raw-copy fast
        // path stays available.
        //
        // Segment frames are computed from the CURRENT processing rate (the
        // tap-SRC output rate when converting, else the input rate), published
        // by onConfigure, so a reconfigure between arm and buffer is respected.
        final int curSampleRate = sampleRate > 0 ? sampleRate
                : (inputAudioFormat.sampleRate > 0 ? inputAudioFormat.sampleRate : 48000);
        float[] curve;
        int segFrames;
        long startPos;
        float idleGain;
        boolean gainActive;
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
            gainActive = curve != null || Math.abs(idleGain - 1.0f) > 0.0001f;
            // Consume the frames we are about to emit. When the curve is
            // exhausted it transitions into a static gain equal to its last
            // value, so a fade-out stays silent and a fade-in becomes
            // transparent instead of leaving a stale curve behind. A held
            // static gain now persists through bit-perfect blocks too (the
            // engine applies it on the bypass path), so the old one-block
            // ramp-to-unity — which resurrected audio after a completed sleep
            // fade-out — is gone.
            if (curve != null) {
                rampPosFrames += emitFrames;
                if (rampPosFrames >= (long) (curve.length - 1) * segFrames) {
                    staticGain = curve[curve.length - 1];
                    rampGains = null;
                    rampSegmentMs = 0;
                    rampPosFrames = 0;
                }
            }
        }
        if (transitionMuted || Math.abs(transitionGain - 1.0f) > 0.0001f) {
            gainActive = true;
        }

        FloatBuffer gains = null;
        float profileGain = transitionGain;
        if (gainActive) {
            gains = ensureGainScratch(emitFrames);
            final int lastIdx = curve == null ? 0 : curve.length - 1;
            final float profileTarget = transitionMuted ? 0.0f : 1.0f;
            final float profileStep = 1.0f / Math.max(1, curSampleRate * 0.04f);
            for (int f = 0; f < emitFrames; f++) {
                profileGain = profileTarget < profileGain
                        ? Math.max(profileTarget, profileGain - profileStep)
                        : Math.min(profileTarget, profileGain + profileStep);
                float gain = idleGain;
                if (curve != null) {
                    // Piecewise-linear interpolation between curve points, per frame.
                    double exact = (startPos + f) / (double) segFrames;
                    int seg = (int) exact;
                    if (seg >= lastIdx) {
                        gain = curve[lastIdx];
                    } else {
                        float frac = (float) (exact - seg);
                        gain = curve[seg] + (curve[seg + 1] - curve[seg]) * frac;
                    }
                }
                gains.put(f, gain * profileGain);
            }
            transitionGain = profileGain;
        }

        int processed = emitFrames;
        boolean bitPerfect = false;
        // Frames whose gain the engine already applied. Anything at or beyond
        // this count (engine absent, declined, or processed only a head) gets
        // the gain in the Java output loop below.
        int nativeGainedFrames = 0;
        if (NATIVE_AVAILABLE) {
            // Read side: release() (write side) cannot destroy the engine while
            // we are inside the native call.
            engineLock.readLock().lock();
            try {
                final long handle = nativeEngineHandle.get();
                if (handle != 0) {
                    try {
                        processed = nativeProcessDirectFloatBuffer(
                                handle, emitNativeBuffer, 0, emitFrames, channelCount,
                                gains == null ? null : gainScratch);
                        bitPerfect = processed < 0;
                        if (bitPerfect) processed = -processed;
                        // Any positive return means the engine ran and applied
                        // the gain buffer itself (on every path, including the
                        // bit-perfect bypass).
                        if (processed > 0 && gains != null) {
                            nativeGainedFrames = processed;
                        }
                    } catch (RuntimeException | UnsatisfiedLinkError e) {
                        // A JNI RuntimeException must never escape queueInput.
                        logJniFailureOnce("nativeProcessDirectFloatBuffer", e);
                        processed = emitFrames;
                        bitPerfect = false;
                    }
                }
            } finally {
                engineLock.readLock().unlock();
            }
        }
        if (processed <= 0 || processed > emitFrames) {
            // Engine declined the block; the emit buffer still holds its input.
            processed = emitFrames;
            bitPerfect = false;
            nativeGainedFrames = 0;
        } else if (processed < emitFrames) {
            // The engine processed only part of the block. Never drop the tail:
            // the un-processed remainder is still the original input in the
            // emit buffer, so emit the whole block (processed head + raw tail)
            // and apply the gain to the un-gained tail in the output loop.
            if (!loggedShortProcess) {
                loggedShortProcess = true;
                Log.w(TAG, "nativeProcess returned " + processed + " of " + emitFrames
                        + " frames; passing the remainder through unprocessed");
            }
            nativeGainedFrames = processed;
            processed = emitFrames;
            bitPerfect = false;
        }
        // Tap SRC already voided sample identity with the decoded source; the
        // raw-copy fast path would also emit source-rate bytes into an
        // output-rate AudioTrack.
        if (tapSrcActive) {
            bitPerfect = false;
        }

        final boolean outputIsFloat = outputAudioFormat.encoding == C.ENCODING_PCM_FLOAT;
        ByteBuffer output = replaceOutputBuffer(processed * outputAudioFormat.bytesPerFrame);
        if (bitPerfect && gains == null) {
            // No curve and unity static gain were already verified under
            // rampLock above, and the engine confirmed sample-identical bypass:
            // emit the decoded bytes verbatim.
            ByteBuffer original = inputBuffer.duplicate();
            original.limit(position + processed * inputAudioFormat.bytesPerFrame);
            output.put(original);
            output.flip();
            inputBuffer.position(limit);
            return;
        }

        final int gainedSamples = nativeGainedFrames * channelCount;
        for (int i = 0; i < processed * channelCount; i++) {
            float value = emitFloats.get(i);
            if (gains != null && i >= gainedSamples) {
                // Fallback: the engine did not run (or ran only a head), so the
                // transport gain is applied here — still before the 16-bit
                // requantiser's own dither.
                value *= gains.get(i / channelCount);
            }
            if (outputIsFloat) {
                // Emit straight float32: no 16-bit re-quantisation after DSP.
                output.putFloat(value);
            } else {
                output.putShort(Pcm16Quantizer.fromFloat(value));
            }
        }
        inputBuffer.position(limit);
        output.flip();
    }

    @Override
    protected void onFlush() {
        tapSrcActive = inputAudioFormat.sampleRate > 0 && outputAudioFormat.sampleRate > 0
                && inputAudioFormat.sampleRate != outputAudioFormat.sampleRate;
        // The engine runs at the PROCESSING rate: the tap-SRC output rate when
        // converting, else the input rate. Coefficients, dither and the gain
        // curve all live at that rate.
        final int sr = tapSrcActive ? outputAudioFormat.sampleRate
                : inputAudioFormat.sampleRate;
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
        tapSrcActive = false;
        scratch = null;
        scratchFloats = null;
        gainScratch = null;
        gainScratchFloats = null;
        resampleScratch = null;
        resampleScratchFloats = null;
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

    // Direct buffer of per-frame transport gains handed to the native engine
    // (one float per frame). Grown like `scratch`; only written on the playback
    // thread while a gain is active.
    private ByteBuffer gainScratch;
    private FloatBuffer gainScratchFloats;

    private FloatBuffer ensureGainScratch(int frameCount) {
        if (gainScratch == null || gainScratch.capacity() < frameCount * 4) {
            int targetBytes = Math.max(frameCount * 4,
                    gainScratch == null ? 4096 : gainScratch.capacity() * 2);
            gainScratch = ByteBuffer.allocateDirect(targetBytes).order(ByteOrder.nativeOrder());
            gainScratchFloats = gainScratch.asFloatBuffer();
        }
        return gainScratchFloats;
    }

    // Direct buffer holding the tap-SRC output block fed to the native engine.
    private ByteBuffer resampleScratch;
    private FloatBuffer resampleScratchFloats;

    private FloatBuffer ensureResampleScratch(int sampleCount) {
        if (resampleScratch == null || resampleScratch.capacity() < sampleCount * 4) {
            int targetBytes = Math.max(sampleCount * 4,
                    resampleScratch == null ? 16384 : resampleScratch.capacity() * 2);
            resampleScratch = ByteBuffer.allocateDirect(targetBytes).order(ByteOrder.nativeOrder());
            resampleScratchFloats = resampleScratch.asFloatBuffer();
        }
        return resampleScratchFloats;
    }
}
