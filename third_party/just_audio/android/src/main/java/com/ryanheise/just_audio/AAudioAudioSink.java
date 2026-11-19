package com.ryanheise.just_audio;

import android.os.Build;
import android.os.SystemClock;
import android.util.Log;
import android.media.AudioDeviceInfo;
import android.media.AudioFormat;

import androidx.media3.common.AudioAttributes;
import androidx.media3.common.AuxEffectInfo;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.exoplayer.audio.AudioSink;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.IntBuffer;

/**
 * Pulsr fork: Media3 {@link AudioSink} backed by a native AAudio stream.
 *
 * <p>Direct output requests the source sample rate through AAudio. Exclusive
 * requests fail if unavailable and lock PCM volume to unity. Explicit shared
 * mode permits software volume and makes no downstream bit-perfect guarantee. The DSP
 * processor chain is bypassed in this mode by design - this sink is the
 * bit-perfect alternative path, not a DSP replacement.
 *
 * <p>v1 scope (documented limitations): PCM 16-bit / float / 24-bit packed,
 * 1-2 channels, speed &amp; pitch pinned to 1.0 (PulsrAudioSink suspends
 * AAUDIO mode and swaps to the AudioTrack path when non-default speed/pitch or
 * silence skipping is requested), no tunneling/offload/aux effects. Any stream
 * the sink cannot honour must be declined via {@link #supportsFormat} so the
 * player keeps using the DefaultAudioSink path.
 */
@androidx.media3.common.util.UnstableApi
public final class AAudioAudioSink implements AudioSink {
    private static final String TAG = "PulsrAAudioSink";

    /** Seam over the JNI bridge so sink logic is testable without native code. */
    interface Bridge {
        long openForDevice(int sampleRate, int channelCount, int encoding,
                boolean preferExclusive, int targetBufferMs, int deviceId);
        int getDeviceId(long handle);
        void close(long handle);
        int write(long handle, ByteBuffer buffer, int offset, int length);
        void play(long handle);
        void pause(long handle);
        void flush(long handle);
        long getFramesRead(long handle);
        long getFramesWritten(long handle);
        boolean isExclusive(long handle);
        void setVolume(long handle, float volume);
        void setBitPerfect(long handle, boolean bitPerfect, boolean dop);
        boolean isBitPerfectSink(long handle);
    }

    private static final Bridge NATIVE_BRIDGE = new Bridge() {
        @Override public long openForDevice(int sampleRate, int channelCount, int encoding,
                boolean preferExclusive, int targetBufferMs, int deviceId) {
            return AaudioNativeBridge.nativeOpenForDevice(sampleRate, channelCount, encoding,
                    preferExclusive, targetBufferMs, deviceId);
        }
        @Override public int getDeviceId(long handle) {
            return AaudioNativeBridge.nativeGetDeviceId(handle);
        }
        @Override public void close(long handle) { AaudioNativeBridge.nativeClose(handle); }
        @Override public int write(long handle, ByteBuffer buffer, int offset, int length) {
            return AaudioNativeBridge.nativeWrite(handle, buffer, offset, length);
        }
        @Override public void play(long handle) { AaudioNativeBridge.nativePlay(handle); }
        @Override public void pause(long handle) { AaudioNativeBridge.nativePause(handle); }
        @Override public void flush(long handle) { AaudioNativeBridge.nativeFlush(handle); }
        @Override public long getFramesRead(long handle) {
            return AaudioNativeBridge.nativeGetFramesRead(handle);
        }
        @Override public long getFramesWritten(long handle) {
            return AaudioNativeBridge.nativeGetFramesWritten(handle);
        }
        @Override public boolean isExclusive(long handle) {
            return AaudioNativeBridge.nativeIsExclusive(handle);
        }
        @Override public void setVolume(long handle, float volume) {
            AaudioNativeBridge.nativeSetVolume(handle, volume);
        }
        @Override public void setBitPerfect(long handle, boolean bitPerfect, boolean dop) {
            AaudioNativeBridge.nativeSetBitPerfect(handle, bitPerfect, dop);
        }
        @Override public boolean isBitPerfectSink(long handle) {
            return AaudioNativeBridge.nativeIsBitPerfectSink(handle);
        }
    };

    interface ClockMs {
        long elapsedRealtime();
    }

    private Bridge bridge = NATIVE_BRIDGE;
    private static volatile int globalDeviceApiLevelForTest = -1;
    private int deviceApiLevelForTest = -1;
    private ClockMs clockMs = SystemClock::elapsedRealtime;

    /** Test seam; production always uses NATIVE_BRIDGE. */
    void setBridgeForTest(Bridge bridge) {
        this.bridge = bridge;
    }

    /** Test seam to exercise pre-API-31 behavior under Robolectric SDK 33. */
    void setDeviceApiLevelForTest(int apiLevel) {
        this.deviceApiLevelForTest = apiLevel;
    }

    static void setDeviceApiLevelOverrideForTest(int apiLevel) {
        globalDeviceApiLevelForTest = apiLevel;
    }

    static int deviceApiLevel() {
        return globalDeviceApiLevelForTest >= 0 ? globalDeviceApiLevelForTest : Build.VERSION.SDK_INT;
    }

    /** Test seam to advance elapsed time deterministically during drain tests. */
    void setClockForTest(ClockMs clockMs) {
        this.clockMs = clockMs != null ? clockMs : SystemClock::elapsedRealtime;
    }

    private Listener listener;
    private Format configuredFormat;
    private int targetBufferMs;
    private final boolean preferExclusive;

    private long handle = 0L;
    private int sampleRate;
    private int channelCount;
    // Tracks the PCM encoding of the currently-open stream so handleBuffer
    // knows whether 32-bit int samples pass through raw (API 31+ exclusive)
    // or must be transcoded to float32 before writing.
    private int pcmEncoding = C.ENCODING_PCM_FLOAT;
    private boolean transcodingPcm32 = false;

    /**
     * API level gating AAudio PCM encodings. Honours the per-instance test
     * seam, otherwise the process-wide override or the platform level.
     */
    private int apiLevel() {
        return deviceApiLevelForTest >= 0 ? deviceApiLevelForTest : deviceApiLevel();
    }

    private boolean useNativeInt32() {
        return preferExclusive && apiLevel() >= 31;
    }
    // Reusable scratch buffer for 32-bit → float32 conversion. Allocated
    // lazily in handleBuffer and grown on demand; never shrunk.
    private ByteBuffer pcm32ScratchBuffer;
    private ByteBuffer nonDirectScratchBuffer;
    private FloatDspAudioSink.PcmFrameEditor frameEditor;
    private ByteBuffer pendingEditedInput;
    private ByteBuffer pendingEditedOutput;
    private int pendingEditedEnd;
    private long pendingEditedTimeUs;
    private int pendingEditedUnits;

    boolean hasStagedInput() { return pendingEditedInput != null; }
    FloatDspAudioSink.PcmFrameEditor frameEditor() { return frameEditor; }
    void adoptFrameEditor(FloatDspAudioSink.PcmFrameEditor editor) { frameEditor = editor; }

    private float volume = 1.0f;
    // App-level bit-perfect / DoP request mirrored from PulsrAudioSink. Cached
    // so the per-buffer push is free and only a change reaches JNI.
    private boolean bitPerfectRequested = false;
    private boolean dopRequested = false;
    private boolean bitPerfectUnconfirmedLogged = false;
    private boolean bitPerfectJniUnavailable = false;
    private PlaybackParameters playbackParameters = PlaybackParameters.DEFAULT;
    private AudioAttributes audioAttributes = AudioAttributes.DEFAULT;
    private boolean skipSilenceEnabled = false;

    private volatile boolean playing = false;
    private volatile int[] measuredStream = new int[] {0, 0, 0};
    // nativeGetDeviceId() is a JNI call behind a global shared lock, so the
    // measured route is refreshed at most every 32 buffers instead of on every
    // write. configure() and a pending route change force the next query.
    private static final int ROUTE_QUERY_INTERVAL_BUFFERS = 32;
    private int buffersSinceRouteQuery;
    private boolean forceRouteQuery = true;
    private int preferredDeviceId = 0;
    private int openedDeviceId = 0;
    private int openedEncoding = 0;
    private boolean openedPreferExclusive = false;
    private int openedTargetBufferMs = 0;
    private boolean routePending = false;
    private Format pendingConfigureFormat;
    private int pendingConfigureBufferSize;
    private int[] pendingConfigureOutputChannels;
    private long drainDeadlineElapsedMs;

    int[] measuredStream() { return measuredStream; }
    boolean isPlaying() { return playing; }

    @Override
    public void setPreferredDevice(AudioDeviceInfo device) {
        setPreferredDeviceId(device == null ? 0 : device.getId());
    }

    void setPreferredDeviceId(int id) {
        if (id == preferredDeviceId) return;
        preferredDeviceId = id;
        routePending = handle != 0L;
        // Report the new route on the first buffer after the change.
        forceRouteQuery = true;
        buffersSinceRouteQuery = 0;
    }

    private boolean eosWritten = false;
    private boolean handledEndOfStream = false;
    // Position base: the presentation time of the first buffer written after
    // the last (re)configuration/discontinuity, per the AudioSink contract.
    private boolean pendingBasePosition = true;
    private long basePositionUs = 0L;
    // Frames already written when the position timeline was last re-based.
    // Without this, frames read from the previous stream (or before a gapless
    // discontinuity) are added to the new base position, jumping the timeline.
    private long baseFramesWritten = 0L;

    public AAudioAudioSink(boolean preferExclusive, int targetBufferMs) {
        this.preferExclusive = preferExclusive;
        this.targetBufferMs = targetBufferMs;
    }

    @Override
    public void setListener(Listener listener) {
        this.listener = listener;
    }

    @Override
    public boolean supportsFormat(Format format) {
        return getFormatSupport(format) != SINK_FORMAT_UNSUPPORTED;
    }

    @Override
    public int getFormatSupport(Format format) {
        if (format.sampleRate <= 0 || format.channelCount <= 0
                || format.channelCount > 2) {
            return SINK_FORMAT_UNSUPPORTED;
        }
        switch (format.pcmEncoding) {
            case C.ENCODING_PCM_16BIT:
            case C.ENCODING_PCM_FLOAT:
                return SINK_FORMAT_SUPPORTED_DIRECTLY;
            case C.ENCODING_PCM_24BIT:
                // AAUDIO_FORMAT_PCM_I24_PACKED only exists from API 31, and
                // handleBuffer has no 24 -> float transcode, so below 31 this
                // is unsupported rather than WITH_TRANSCODING.
                return apiLevel() >= 31 ? SINK_FORMAT_SUPPORTED_DIRECTLY
                        : SINK_FORMAT_UNSUPPORTED;
            case C.ENCODING_PCM_32BIT:
                if (useNativeInt32()) {
                    return SINK_FORMAT_SUPPORTED_DIRECTLY;
                }
                // Below API 31 (no AAUDIO_FORMAT_PCM_I32) or in shared mode,
                // int32 -> float32 keeps only 24 significant bits. Exclusive
                // mode declines rather than silently transcode; shared mode
                // plays it and says so.
                return preferExclusive ? SINK_FORMAT_UNSUPPORTED
                        : SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
            default:
                // Compressed/encoded and exotic PCM stay on DefaultAudioSink.
                return SINK_FORMAT_UNSUPPORTED;
        }
    }

    @Override
    public long getCurrentPositionUs(boolean sourceEnded) {
        // After configure/flush/discontinuity the timeline has been re-based but
        // the new base presentation time is not known until the next buffer:
        // reporting the old base here would expose a stale position.
        if (handle == 0L || sampleRate <= 0 || pendingBasePosition) {
            return CURRENT_POSITION_NOT_SET;
        }
        long framesWritten = bridge.getFramesWritten(handle);
        long framesRead = bridge.getFramesRead(handle);
        if (framesRead > framesWritten) {
            framesRead = framesWritten;
        }
        long deltaRead = Math.max(0L, framesRead - baseFramesWritten);
        long positionUs = basePositionUs
                + (long) (deltaRead * (1_000_000.0 / sampleRate));
        if (!sourceEnded) {
            // Never report beyond what the app has actually written since the
            // timeline base.
            long deltaWritten = Math.max(0L, framesWritten - baseFramesWritten);
            long maxUs = basePositionUs
                    + (long) (deltaWritten * (1_000_000.0 / sampleRate));
            if (positionUs > maxUs) positionUs = maxUs;
        }
        return positionUs;
    }

    private boolean hasQueuedFrames() {
        if (handle == 0L) return false;
        long read = bridge.getFramesRead(handle);
        long written = bridge.getFramesWritten(handle);
        return read >= 0L && written > read;
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSize,
            int[] outputChannels) throws ConfigurationException {
        if (outputChannels != null) {
            throw new ConfigurationException(
                "AAudio sink does not support channel remapping", inputFormat);
        }
        if (getFormatSupport(inputFormat) == SINK_FORMAT_UNSUPPORTED) {
            throw new ConfigurationException(
                "Unsupported PCM format for AAudio sink", inputFormat);
        }
        // A (re)configured stream must report its route on the first buffer.
        forceRouteQuery = true;
        buffersSinceRouteQuery = 0;
        final boolean useNative32 = useNativeInt32();
        final int encoding;
        if (inputFormat.pcmEncoding == C.ENCODING_PCM_16BIT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_I16;
        } else if (inputFormat.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_FLOAT;
        } else if (inputFormat.pcmEncoding == C.ENCODING_PCM_32BIT) {
            encoding = useNative32
                    ? AaudioNativeBridge.ENCODING_PCM_I32
                    : AaudioNativeBridge.ENCODING_PCM_FLOAT;
        } else {
            encoding = AaudioNativeBridge.ENCODING_PCM_I24_PACKED;
        }
        // Trimming removes declared non-program frames without changing samples.
        final FloatDspAudioSink.PcmFrameEditor nextEditor;
        try {
            nextEditor = new FloatDspAudioSink.PcmFrameEditor(inputFormat, null);
        } catch (IllegalArgumentException | ArithmeticException e) {
            throw new ConfigurationException(e, inputFormat);
        }
        final boolean sameStreamParams = handle != 0L
                && !routePending
                && pendingConfigureFormat == null
                && inputFormat.sampleRate == sampleRate
                && inputFormat.channelCount == channelCount
                && encoding == openedEncoding
                && preferredDeviceId == openedDeviceId
                && preferExclusive == openedPreferExclusive
                && targetBufferMs == openedTargetBufferMs;
        if (sameStreamParams) {
            frameEditor = nextEditor;
            configuredFormat = inputFormat;
            pcmEncoding = inputFormat.pcmEncoding;
            transcodingPcm32 = (inputFormat.pcmEncoding == C.ENCODING_PCM_32BIT && !useNative32);
            pendingEditedInput = null;
            pendingEditedOutput = null;
            eosWritten = false;
            handledEndOfStream = false;
            pendingBasePosition = true;
            return;
        }
        if (handle != 0L && !routePending && hasQueuedFrames()) {
            pendingConfigureFormat = inputFormat;
            pendingConfigureBufferSize = specifiedBufferSize;
            pendingConfigureOutputChannels = null;
            drainDeadlineElapsedMs = clockMs.elapsedRealtime()
                    + Math.max(targetBufferMs * 2L, 500L);
            return;
        }
        pendingConfigureFormat = null;
        pendingConfigureOutputChannels = null;
        pendingConfigureBufferSize = 0;
        drainDeadlineElapsedMs = 0L;
        frameEditor = nextEditor;
        pendingEditedInput = null;
        pendingEditedOutput = null;
        // Close any stream from a previous configuration before reopening.
        // VERIFY: nativeClose drain semantics and gapless 44.1->96 kHz album transition over USB DAC.
        closeHandle();
        long newHandle;
        try {
            newHandle = bridge.openForDevice(inputFormat.sampleRate,
                    inputFormat.channelCount, encoding, preferExclusive,
                    targetBufferMs, preferredDeviceId);
        } catch (UnsatisfiedLinkError e) {
            throw new ConfigurationException(e, inputFormat);
        }
        if (newHandle == 0L) {
            throw new ConfigurationException(
                "AAudio stream could not be opened for "
                    + inputFormat.sampleRate + "Hz/" + inputFormat.channelCount
                    + "ch", inputFormat);
        }
        handle = newHandle;
        openedDeviceId = preferredDeviceId;
        openedEncoding = encoding;
        openedPreferExclusive = preferExclusive;
        openedTargetBufferMs = targetBufferMs;
        routePending = false;
        // Report what the stream was actually OPENED as, not what the decoder
        // handed us: an int32 input arriving here is a float stream.
        measuredStream = new int[] {bridge.getDeviceId(handle), inputFormat.sampleRate,
                encoding == AaudioNativeBridge.ENCODING_PCM_I16 ? AudioFormat.ENCODING_PCM_16BIT
                    : encoding == AaudioNativeBridge.ENCODING_PCM_I24_PACKED
                        ? AudioFormat.ENCODING_PCM_24BIT_PACKED
                        : encoding == AaudioNativeBridge.ENCODING_PCM_I32
                            ? AudioFormat.ENCODING_PCM_32BIT
                            : AudioFormat.ENCODING_PCM_FLOAT};
        configuredFormat = inputFormat;
        sampleRate = inputFormat.sampleRate;
        channelCount = inputFormat.channelCount;
        pcmEncoding = inputFormat.pcmEncoding;
        transcodingPcm32 = (inputFormat.pcmEncoding == C.ENCODING_PCM_32BIT && !useNative32);
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        baseFramesWritten = 0L;
        bridge.setVolume(handle, volume);
        // The native flag is per stream: re-assert the cached request on open.
        bitPerfectUnconfirmedLogged = false;
        pushBitPerfectToNative();
        if (playing) bridge.play(handle);
        else bridge.pause(handle);
        Log.i(TAG, "AAudio sink configured: " + sampleRate + "Hz/" + channelCount
                + "ch pcm=" + inputFormat.pcmEncoding
                + " exclusive=" + bridge.isExclusive(handle));
    }

    @Override
    public void play() {
        playing = true;
        if (handle != 0L) bridge.play(handle);
    }

    @Override
    public void handleDiscontinuity() {
        // The next handleBuffer re-bases the position timeline.
        pendingBasePosition = true;
    }

    private void applyPendingConfigure() throws ConfigurationException {
        Format nextFormat = pendingConfigureFormat;
        int nextBufferSize = pendingConfigureBufferSize;
        int[] nextChannels = pendingConfigureOutputChannels;
        pendingConfigureFormat = null;
        pendingConfigureOutputChannels = null;
        pendingConfigureBufferSize = 0;
        drainDeadlineElapsedMs = 0L;
        closeHandle();
        configure(nextFormat, nextBufferSize, nextChannels);
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationStartUs,
            int encodedAccessUnitCount) throws InitializationException,
            WriteException {
        if (pendingConfigureFormat != null) {
            if (!routePending && hasQueuedFrames()
                    && clockMs.elapsedRealtime() < drainDeadlineElapsedMs) {
                return false;
            }
            Format targetFormat = pendingConfigureFormat;
            try {
                applyPendingConfigure();
            } catch (ConfigurationException e) {
                throw new InitializationException("Pending AAudio reconfigure failed", 0,
                        targetFormat, false, e);
            }
        }
        if (routePending && configuredFormat != null && pendingEditedOutput == null) {
            FloatDspAudioSink.PcmFrameEditor previousEditor = frameEditor;
            Format previousFormat = configuredFormat;
            int previousDevice = openedDeviceId;
            try {
                // Keep routePending=true so configure() forces a close+reopen.
                configure(previousFormat, 0, null);
            } catch (ConfigurationException refused) {
                routePending = false;
                preferredDeviceId = previousDevice;
                boolean restored = false;
                Exception errorToReport = refused;
                try {
                    configure(previousFormat, 0, null);
                    restored = (handle != 0L);
                } catch (ConfigurationException restoreFailed) {
                    errorToReport = restoreFailed;
                }
                if (!restored && listener != null) {
                    listener.onAudioSinkError(errorToReport);
                }
                if (handle == 0L) {
                    // Do not proceed to write into a dead stream handle
                    return false;
                }
            }
            frameEditor = previousEditor;
        }
        if (handle == 0L) {
            throw new InitializationException("AAudio stream is not open", 0,
                    configuredFormat, false, null);
        }
        if (pendingBasePosition) {
            basePositionUs = presentationStartUs;
            baseFramesWritten = bridge.getFramesWritten(handle);
            pendingBasePosition = false;
        }
        int remaining = buffer.remaining();
        if (remaining == 0) {
            return true;
        }

        if (pendingEditedOutput != null || (frameEditor != null && frameEditor.edits())) {
            if (pendingEditedOutput == null) {
                ByteBuffer edited = frameEditor.prepare(buffer);
                pendingEditedOutput = transcodingPcm32
                        ? convert32BitToFloat(edited) : edited;
                pendingEditedInput = buffer;
                pendingEditedEnd = buffer.limit();
                pendingEditedTimeUs = presentationStartUs;
                pendingEditedUnits = encodedAccessUnitCount;
                frameEditor.commit();
            } else if (pendingEditedInput != buffer) {
                throw new IllegalStateException("Retry the same PCM buffer");
            }
            if (pendingEditedOutput.hasRemaining()) {
                int written = bridge.write(handle, pendingEditedOutput,
                        pendingEditedOutput.position(), pendingEditedOutput.remaining());
                if (written < 0 || written > pendingEditedOutput.remaining())
                    throw new WriteException(-1, configuredFormat, true);
                pendingEditedOutput.position(pendingEditedOutput.position() + written);
                updateMeasuredRoute();
                if (pendingEditedOutput.hasRemaining()) return false;
            }
            buffer.position(pendingEditedEnd);
            pendingEditedOutput = null;
            pendingEditedInput = null;
            return true;
        }

        // 32-bit int PCM → float32 conversion path when native I32 is unavailable/shared.
        final ByteBuffer writeBuffer;
        if (transcodingPcm32) {
            writeBuffer = convert32BitToFloat(buffer);
            remaining = writeBuffer.remaining();
            if (remaining == 0) {
                buffer.position(buffer.limit());
                return true;
            }
        } else {
            writeBuffer = buffer;
        }

        if (!writeBuffer.isDirect()) {
            // Media3 hands the sink direct buffers; be defensive anyway.
            // Reuse a class-level staging buffer instead of allocating a new
            // direct buffer for every buffer.
            if (nonDirectScratchBuffer == null
                    || nonDirectScratchBuffer.capacity() < remaining) {
                nonDirectScratchBuffer = ByteBuffer.allocateDirect(
                        Math.max(remaining, 65536)).order(ByteOrder.nativeOrder());
            }
            nonDirectScratchBuffer.clear();
            nonDirectScratchBuffer.put(writeBuffer.duplicate());
            nonDirectScratchBuffer.flip();
            int written = bridge.write(handle, nonDirectScratchBuffer, 0,
                    remaining);
            if (written < 0 || written > remaining) {
                throw new WriteException(-1, configuredFormat,
                        /* isRecoverable= */ true);
            }
            updateMeasuredRoute();
            if (!advanceAfterPcmWrite(buffer, written)) return false;
            return !buffer.hasRemaining();
        }
        int offset = writeBuffer.position();
        int written = bridge.write(handle, writeBuffer, offset,
                remaining);
        if (written < 0 || written > remaining) {
            throw new WriteException(-1, configuredFormat,
                    /* isRecoverable= */ true);
        }
        updateMeasuredRoute();
        if (!advanceAfterPcmWrite(buffer, written)) return false;
        return !buffer.hasRemaining();
    }

    /**
     * Advances the source buffer by the bytes the native write accepted, keeping
     * it sample aligned. Returns false when a 32-bit -> float write stopped
     * mid-sample: the trailing 1-3 bytes stay unconsumed so handleBuffer reports
     * the buffer as not consumed and Media3 retries, instead of silently
     * dropping source bytes that were never written.
     */
    private boolean advanceAfterPcmWrite(ByteBuffer buffer, int written) {
        if (transcodingPcm32) {
            // int32 -> float is 1:1 in samples (4 bytes in, 4 bytes out), so a
            // partial native write advances the source by the same byte count,
            // never past a sample boundary that was not written.
            final int aligned = written & ~3;
            buffer.position(buffer.position() + aligned);
            return aligned == written;
        }
        buffer.position(buffer.position() + written);
        return true;
    }

    /**
     * Converts a 32-bit integer PCM buffer to float32 in a reusable direct
     * scratch buffer. Normalises by ÷2^31 so full-scale maps to ±1.0f.
     * The returned buffer is ready to read (position=0, limit=floatBytes).
     */
    private ByteBuffer convert32BitToFloat(ByteBuffer src) {
        final int samples = src.remaining() / 4;
        final int floatBytes = samples * 4;
        if (pcm32ScratchBuffer == null || pcm32ScratchBuffer.capacity() < floatBytes) {
            pcm32ScratchBuffer = ByteBuffer.allocateDirect(
                    Math.max(floatBytes, 65536)).order(ByteOrder.nativeOrder());
        }
        pcm32ScratchBuffer.clear();
        final IntBuffer ints = src.duplicate().order(ByteOrder.nativeOrder()).asIntBuffer();
        for (int i = 0; i < samples; i++) {
            // Widen to double before scaling so all 24 bits of float mantissa
            // precision survive; int / float rounds through float first.
            pcm32ScratchBuffer.putFloat(
                    (float) (ints.get(i) * (1.0 / 2147483648.0))); // ÷ 2^31
        }
        pcm32ScratchBuffer.flip();
        return pcm32ScratchBuffer;
    }

    void transferPendingTo(FloatDspAudioSink target) {
        target.acceptPreparedPcm(pendingEditedOutput,
                transcodingPcm32 ? C.ENCODING_PCM_FLOAT : pcmEncoding,
                pendingEditedInput, pendingEditedEnd, pendingEditedTimeUs, pendingEditedUnits, frameEditor);
        pendingEditedOutput = null;
        pendingEditedInput = null;
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        if (handle == 0L || eosWritten) {
            return;
        }
        if (pendingEditedOutput != null && pendingEditedInput != null) {
            try {
                if (!handleBuffer(pendingEditedInput, pendingEditedTimeUs, pendingEditedUnits)) return;
            } catch (InitializationException e) {
                WriteException failure = new WriteException(-1, configuredFormat, true);
                failure.initCause(e);
                throw failure;
            }
        }
        if (frameEditor != null) frameEditor.endOfStream();
        eosWritten = true;
        handledEndOfStream = true;
    }

    @Override
    public boolean isEnded() {
        return pendingEditedOutput == null && handledEndOfStream && handle != 0L
                && bridge.getFramesRead(handle)
                        >= bridge.getFramesWritten(handle);
    }

    @Override
    public boolean hasPendingData() {
        return pendingEditedOutput != null || (handle != 0L
                && bridge.getFramesRead(handle)
                        < bridge.getFramesWritten(handle));
    }

    // PulsrAudioSink suspends AAUDIO and swaps to the AudioTrack path whenever
    // non-default speed/pitch or skip-silence is active.
    @Override
    public void setPlaybackParameters(PlaybackParameters playbackParameters) {
        if (playbackParameters.speed != 1.0f
                || playbackParameters.pitch != 1.0f) {
            Log.w(TAG, "AAudio sink v1 ignores speed/pitch changes; "
                    + "playback continues at 1.0x");
        }
        this.playbackParameters = PlaybackParameters.DEFAULT;
    }

    @Override
    public PlaybackParameters getPlaybackParameters() {
        return playbackParameters;
    }

    // PulsrAudioSink suspends AAUDIO and swaps to the AudioTrack path when enabled.
    @Override
    public void setSkipSilenceEnabled(boolean skipSilenceEnabled) {
        this.skipSilenceEnabled = false;
        if (listener != null) {
            listener.onSkipSilenceEnabledChanged(false);
        }
    }

    @Override
    public boolean getSkipSilenceEnabled() {
        return skipSilenceEnabled;
    }

    @Override
    public void setAudioAttributes(AudioAttributes audioAttributes) {
        this.audioAttributes = audioAttributes;
    }

    @Override
    public AudioAttributes getAudioAttributes() {
        return audioAttributes;
    }

    @Override
    public void setAudioSessionId(int audioSessionId) {
        // Audio session IDs are not used on the native AAudio stream; no-op.
    }

    @Override
    public void setAuxEffectInfo(AuxEffectInfo auxEffectInfo) {
        // No aux effects on the native path.
    }

    @Override
    public void enableTunnelingV21() {
        // Tunneling is incompatible with the direct PCM path; no-op.
    }

    @Override
    public void disableTunneling() {
        // No-op.
    }

    @Override
    public long getAudioTrackBufferSizeUs() {
        return C.TIME_UNSET;
    }

    @Override
    public void setVolume(float volume) {
        this.volume = volume;
        if (handle != 0L) {
            bridge.setVolume(handle, volume);
        }
    }

    /**
     * Mirrors the app-level bit-perfect/DoP request onto the native stream.
     * Cached here because the caller pushes it per buffer: JNI is only reached
     * when the pair changes or a new stream is opened.
     */
    void setBitPerfect(boolean bitPerfect, boolean dop) {
        if (bitPerfectRequested == bitPerfect && dopRequested == dop) return;
        bitPerfectRequested = bitPerfect;
        dopRequested = dop;
        bitPerfectUnconfirmedLogged = false;
        pushBitPerfectToNative();
    }

    /**
     * Sends the cached request to the open stream. An unconfirmed sink or a
     * missing JNI export degrades the verdict; it must never fail playback.
     */
    private void pushBitPerfectToNative() {
        final long current = handle;
        if (current == 0L || bitPerfectJniUnavailable) return;
        try {
            bridge.setBitPerfect(current, bitPerfectRequested, dopRequested);
            if (bitPerfectRequested && !bridge.isBitPerfectSink(current)
                    && !bitPerfectUnconfirmedLogged) {
                bitPerfectUnconfirmedLogged = true;
                Log.w(TAG, "AAudio stream did not assert bit-perfect output (dop="
                        + dopRequested + "); Bit-Perfect output cannot be certified");
            }
        } catch (UnsatisfiedLinkError e) {
            // Older libpulsr_dsp builds lack this export: stop calling it
            // instead of throwing UnsatisfiedLinkError out of configure().
            bitPerfectJniUnavailable = true;
            Log.w(TAG, "AAudio bit-perfect JNI unavailable: " + e.getMessage());
        }
    }

    @Override
    public void pause() {
        playing = false;
        if (handle != 0L) bridge.pause(handle);
    }

    @Override
    public void flush() {
        pendingEditedInput = null;
        pendingEditedOutput = null;
        if (frameEditor != null) frameEditor.flush();
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        baseFramesWritten = 0L;
        if (pendingConfigureFormat != null) {
            try {
                applyPendingConfigure();
            } catch (ConfigurationException e) {
                if (listener != null) listener.onAudioSinkError(e);
            }
            return;
        }
        if (handle != 0L) bridge.flush(handle);
        if (playing && handle != 0L) bridge.play(handle);
    }

    @Override
    public void reset() {
        pendingEditedInput = null;
        pendingEditedOutput = null;
        pendingConfigureFormat = null;
        pendingConfigureOutputChannels = null;
        pendingConfigureBufferSize = 0;
        drainDeadlineElapsedMs = 0L;
        frameEditor = null;
        closeHandle();
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        baseFramesWritten = 0L;
        configuredFormat = null;
        sampleRate = 0;
        channelCount = 0;
        // Release the off-heap direct buffer so the native allocator can reclaim
        // the memory immediately (GC does not deterministically collect direct
        // ByteBuffers on Android). Null pcmEncoding so a stale 32-bit format
        // from a previous stream cannot bleed into a newly opened one.
        pcm32ScratchBuffer = null;
        nonDirectScratchBuffer = null;
        pcmEncoding = C.ENCODING_PCM_FLOAT;
        transcodingPcm32 = false;
    }

    @Override
    public void release() {
        closeHandle();
    }

    private void updateMeasuredRoute() {
        // At most one native query per ROUTE_QUERY_INTERVAL_BUFFERS, unless
        // configure() or a route change asked for a fresh reading.
        if (!forceRouteQuery
                && ++buffersSinceRouteQuery < ROUTE_QUERY_INTERVAL_BUFFERS) {
            return;
        }
        forceRouteQuery = false;
        buffersSinceRouteQuery = 0;
        int device = bridge.getDeviceId(handle);
        int[] previous = measuredStream;
        if (previous[0] != device) measuredStream = new int[] {device, previous[1], previous[2]};
    }

    private void closeHandle() {
        measuredStream = new int[] {0, 0, 0};
        openedDeviceId = 0;
        openedEncoding = 0;
        openedPreferExclusive = false;
        openedTargetBufferMs = 0;
        if (handle != 0L) {
            long toClose = handle;
            handle = 0L;
            try {
                bridge.close(toClose);
            } catch (RuntimeException | UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeClose failed: " + e.getMessage());
            }
        }
    }
}
