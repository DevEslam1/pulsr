package com.ryanheise.just_audio;

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
 * 1-2 channels, speed &amp; pitch pinned to 1.0 (requests are ignored with a
 * log), no silence skipping, no tunneling/offload/aux effects. Any stream the
 * sink cannot honour must be declined via {@link #supportsFormat} so the
 * player keeps using the DefaultAudioSink path.
 */
@androidx.media3.common.util.UnstableApi
public final class AAudioAudioSink implements AudioSink {
    private static final String TAG = "PulsrAAudioSink";

    private Listener listener;
    private Format configuredFormat;
    private int targetBufferMs;
    private final boolean preferExclusive;

    private long handle = 0L;
    private int sampleRate;
    private int channelCount;
    // Tracks the PCM encoding of the currently-open stream so handleBuffer
    // can convert 32-bit int samples to float32 before writing.
    private int pcmEncoding = C.ENCODING_PCM_FLOAT;
    // Reusable scratch buffer for 32-bit → float32 conversion. Allocated
    // lazily in handleBuffer and grown on demand; never shrunk.
    private ByteBuffer pcm32ScratchBuffer;

    private float volume = 1.0f;
    private PlaybackParameters playbackParameters = PlaybackParameters.DEFAULT;
    private AudioAttributes audioAttributes = AudioAttributes.DEFAULT;
    private boolean skipSilenceEnabled = false;
    private int audioSessionId = C.AUDIO_SESSION_ID_UNSET;

    private volatile boolean playing = false;
    private volatile int[] measuredStream = new int[] {0, 0, 0};
    private int preferredDeviceId = 0;
    private int openedDeviceId = 0;
    private boolean routePending = false;

    int[] measuredStream() { return measuredStream; }
    boolean isPlaying() { return playing; }

    @Override
    public void setPreferredDevice(AudioDeviceInfo device) {
        int id = device == null ? 0 : device.getId();
        if (id == preferredDeviceId) return;
        preferredDeviceId = id;
        routePending = handle != 0L;
    }

    private boolean eosWritten = false;
    private boolean handledEndOfStream = false;
    // Position base: the presentation time of the first buffer written after
    // the last (re)configuration/discontinuity, per the AudioSink contract.
    private boolean pendingBasePosition = true;
    private long basePositionUs = 0L;

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
            case C.ENCODING_PCM_24BIT:
            case C.ENCODING_PCM_32BIT:
                // 32-bit integer PCM is accepted and converted to float32
                // in-sink before being written to the AAudio stream.
                return SINK_FORMAT_SUPPORTED_DIRECTLY;
            default:
                // Compressed/encoded and exotic PCM stay on DefaultAudioSink.
                return SINK_FORMAT_UNSUPPORTED;
        }
    }

    @Override
    public long getCurrentPositionUs(boolean sourceEnded) {
        if (handle == 0L || sampleRate <= 0) {
            return CURRENT_POSITION_NOT_SET;
        }
        long framesWritten = AaudioNativeBridge.nativeGetFramesWritten(handle);
        long framesRead = AaudioNativeBridge.nativeGetFramesRead(handle);
        if (framesRead > framesWritten) {
            framesRead = framesWritten;
        }
        long positionUs = basePositionUs
                + (long) (framesRead * (1_000_000.0 / sampleRate));
        if (!sourceEnded) {
            // Never report beyond what the app has actually written.
            long maxUs = basePositionUs
                    + (long) (framesWritten * (1_000_000.0 / sampleRate));
            if (positionUs > maxUs) positionUs = maxUs;
        }
        return positionUs;
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSizeSize,
            int[] outputChannels) throws ConfigurationException {
        if (outputChannels != null) {
            throw new ConfigurationException(
                "AAudio sink does not support channel remapping", inputFormat);
        }
        if (getFormatSupport(inputFormat) == SINK_FORMAT_UNSUPPORTED) {
            throw new ConfigurationException(
                "Unsupported PCM format for AAudio sink", inputFormat);
        }
        int encoding;
        if (inputFormat.pcmEncoding == C.ENCODING_PCM_16BIT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_I16;
        } else if (inputFormat.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            encoding = AaudioNativeBridge.ENCODING_PCM_FLOAT;
        } else if (inputFormat.pcmEncoding == C.ENCODING_PCM_32BIT) {
            // 32-bit integer → float32: AAudio natively accepts float; we
            // convert in handleBuffer so the stream opens as float.
            encoding = AaudioNativeBridge.ENCODING_PCM_FLOAT;
        } else {
            encoding = AaudioNativeBridge.ENCODING_PCM_I24_PACKED;
        }
        // Close any stream from a previous configuration before reopening.
        closeHandle();
        long newHandle;
        try {
            newHandle = AaudioNativeBridge.nativeOpenForDevice(inputFormat.sampleRate,
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
        routePending = false;
        measuredStream = new int[] {AaudioNativeBridge.nativeGetDeviceId(handle),
                inputFormat.sampleRate, inputFormat.pcmEncoding == C.ENCODING_PCM_24BIT
                    ? AudioFormat.ENCODING_PCM_24BIT_PACKED
                    : inputFormat.pcmEncoding == C.ENCODING_PCM_32BIT
                        ? AudioFormat.ENCODING_PCM_32BIT
                        : inputFormat.pcmEncoding};
        configuredFormat = inputFormat;
        sampleRate = inputFormat.sampleRate;
        channelCount = inputFormat.channelCount;
        pcmEncoding = inputFormat.pcmEncoding;
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        AaudioNativeBridge.nativeSetVolume(handle, volume);
        if (!playing) AaudioNativeBridge.nativePause(handle);
        Log.i(TAG, "AAudio sink configured: " + sampleRate + "Hz/" + channelCount
                + "ch pcm=" + inputFormat.pcmEncoding
                + " exclusive=" + AaudioNativeBridge.nativeIsExclusive(handle));
    }

    @Override
    public void play() {
        playing = true;
        if (handle != 0L) AaudioNativeBridge.nativePlay(handle);
    }

    @Override
    public void handleDiscontinuity() {
        // The next handleBuffer re-bases the position timeline.
        pendingBasePosition = true;
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationStartUs,
            int encodedAccessUnitCount) throws InitializationException,
            WriteException {
        if (routePending && configuredFormat != null) {
            routePending = false;
            Format previousFormat = configuredFormat;
            int previousDevice = openedDeviceId;
            try {
                configure(previousFormat, 0, null);
            } catch (ConfigurationException refused) {
                preferredDeviceId = previousDevice;
                try {
                    configure(previousFormat, 0, null);
                } catch (ConfigurationException restoreFailed) {
                    if (listener != null) listener.onAudioSinkError(restoreFailed);
                }
                if (listener != null) listener.onAudioSinkError(refused);
                if (handle == 0L) {
                    // Do not proceed to write into a dead stream handle
                    return false;
                }
            }
        }
        if (handle == 0L) {
            throw new InitializationException(0,
                    configuredFormat != null ? configuredFormat.sampleRate : 0,
                    configuredFormat != null ? configuredFormat.channelCount : 0,
                    configuredFormat != null ? configuredFormat.pcmEncoding : 0,
                    configuredFormat, /* isRecoverable= */ false,
                    /* audioTrackException= */ null);
        }
        if (pendingBasePosition) {
            basePositionUs = presentationStartUs;
            pendingBasePosition = false;
        }
        int remaining = buffer.remaining();
        if (remaining == 0) {
            return true;
        }

        // 32-bit int PCM → float32 conversion path.
        // The stream was opened as ENCODING_PCM_FLOAT; convert before writing.
        final ByteBuffer writeBuffer;
        if (pcmEncoding == C.ENCODING_PCM_32BIT) {
            writeBuffer = convert32BitToFloat(buffer);
            remaining = writeBuffer.remaining();
        } else {
            writeBuffer = buffer;
        }

        if (!writeBuffer.isDirect()) {
            // Media3 hands the sink direct buffers; be defensive anyway.
            ByteBuffer direct = ByteBuffer.allocateDirect(remaining);
            direct.put(writeBuffer.duplicate());
            direct.flip();
            int written = AaudioNativeBridge.nativeWrite(handle, direct, 0,
                    remaining);
            if (written < 0) {
                throw new WriteException(-1, configuredFormat,
                        /* isRecoverable= */ true);
            }
            updateMeasuredRoute();
            if (pcmEncoding == C.ENCODING_PCM_32BIT) {
                // Advance the original int32 buffer proportionally
                // (1 float32 out per 1 int32 in, same sample count).
                buffer.position(buffer.limit());
            } else {
                buffer.position(buffer.position() + written);
            }
            return !buffer.hasRemaining();
        }
        int offset = writeBuffer.position();
        int written = AaudioNativeBridge.nativeWrite(handle, writeBuffer, offset,
                remaining);
        if (written < 0) {
            throw new WriteException(-1, configuredFormat,
                    /* isRecoverable= */ true);
        }
        updateMeasuredRoute();
        if (pcmEncoding == C.ENCODING_PCM_32BIT) {
            buffer.position(buffer.limit());
        } else {
            buffer.position(offset + written);
        }
        return !buffer.hasRemaining();
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
            pcm32ScratchBuffer.putFloat(ints.get(i) / 2147483648f); // ÷ 2^31
        }
        pcm32ScratchBuffer.flip();
        return pcm32ScratchBuffer;
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        if (handle == 0L || eosWritten) {
            return;
        }
        eosWritten = true;
        handledEndOfStream = true;
    }

    @Override
    public boolean isEnded() {
        return handledEndOfStream && handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        >= AaudioNativeBridge.nativeGetFramesWritten(handle);
    }

    @Override
    public boolean hasPendingData() {
        return handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        < AaudioNativeBridge.nativeGetFramesWritten(handle);
    }

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
        this.audioSessionId = audioSessionId;
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
    public void setVolume(float volume) {
        this.volume = volume;
        if (handle != 0L) {
            AaudioNativeBridge.nativeSetVolume(handle, volume);
        }
    }

    @Override
    public void pause() {
        playing = false;
        if (handle != 0L) AaudioNativeBridge.nativePause(handle);
    }

    @Override
    public void flush() {
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        if (handle != 0L) AaudioNativeBridge.nativeFlush(handle);
        if (playing && handle != 0L) AaudioNativeBridge.nativePlay(handle);
    }

    @Override
    public void reset() {
        closeHandle();
        eosWritten = false;
        handledEndOfStream = false;
        pendingBasePosition = true;
        configuredFormat = null;
        sampleRate = 0;
        channelCount = 0;
        // Release the off-heap direct buffer so the native allocator can reclaim
        // the memory immediately (GC does not deterministically collect direct
        // ByteBuffers on Android). Null pcmEncoding so a stale 32-bit format
        // from a previous stream cannot bleed into a newly opened one.
        pcm32ScratchBuffer = null;
        pcmEncoding = C.ENCODING_PCM_FLOAT;
    }

    @Override
    public void release() {
        closeHandle();
    }

    private void updateMeasuredRoute() {
        int device = AaudioNativeBridge.nativeGetDeviceId(handle);
        int[] previous = measuredStream;
        if (previous[0] != device) measuredStream = new int[] {device, previous[1], previous[2]};
    }

    private void closeHandle() {
        measuredStream = new int[] {0, 0, 0};
        if (handle != 0L) {
            long toClose = handle;
            handle = 0L;
            try {
                AaudioNativeBridge.nativeClose(toClose);
            } catch (UnsatisfiedLinkError e) {
                Log.w(TAG, "nativeClose failed: " + e.getMessage());
            }
        }
    }
}
