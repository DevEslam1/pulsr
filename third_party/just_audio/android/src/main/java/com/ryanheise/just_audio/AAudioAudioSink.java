package com.ryanheise.just_audio;

import android.util.Log;

import androidx.media3.common.AudioAttributes;
import androidx.media3.common.AuxEffectInfo;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.exoplayer.audio.AudioSink;

import java.nio.ByteBuffer;

/**
 * Pulsr fork: Media3 {@link AudioSink} backed by a native AAudio stream.
 *
 * <p>"Direct" bit-perfect output: opens a per-stream AAudio path (EXCLUSIVE
 * sharing attempted first, SHARED fallback) at the source sample rate so the
 * OS mixer never resamples, and writes PCM straight to the device. The DSP
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

    private float volume = 1.0f;
    private PlaybackParameters playbackParameters = PlaybackParameters.DEFAULT;
    private AudioAttributes audioAttributes = AudioAttributes.DEFAULT;
    private boolean skipSilenceEnabled = false;
    private int audioSessionId = C.AUDIO_SESSION_ID_UNSET;

    private boolean playing = false;
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
        long framesRead = AaudioNativeBridge.nativeGetFramesRead(handle);
        long positionUs = basePositionUs
                + (long) (framesRead * (1_000_000.0 / sampleRate));
        if (!sourceEnded) {
            // Never report beyond what the app has actually written.
            long framesWritten = AaudioNativeBridge.nativeGetFramesWritten(handle);
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
        } else {
            encoding = AaudioNativeBridge.ENCODING_PCM_I24_PACKED;
        }
        // Close any stream from a previous configuration before reopening.
        closeHandle();
        long newHandle = AaudioNativeBridge.nativeOpen(inputFormat.sampleRate,
                inputFormat.channelCount, encoding, preferExclusive,
                targetBufferMs);
        if (newHandle == 0L) {
            throw new ConfigurationException(
                "AAudio stream could not be opened for "
                    + inputFormat.sampleRate + "Hz/" + inputFormat.channelCount
                    + "ch", inputFormat);
        }
        handle = newHandle;
        configuredFormat = inputFormat;
        sampleRate = inputFormat.sampleRate;
        channelCount = inputFormat.channelCount;
        AaudioNativeBridge.nativeSetVolume(handle, volume);
        Log.i(TAG, "AAudio sink configured: " + sampleRate + "Hz/" + channelCount
                + "ch exclusive=" + AaudioNativeBridge.nativeIsExclusive(handle));
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
        if (!buffer.isDirect()) {
            // Media3 hands the sink direct buffers; be defensive anyway.
            ByteBuffer direct = ByteBuffer.allocateDirect(remaining);
            direct.put(buffer.duplicate());
            direct.flip();
            int written = AaudioNativeBridge.nativeWrite(handle, direct, 0,
                    remaining);
            if (written != remaining) {
                throw new WriteException(-1, configuredFormat,
                        /* isRecoverable= */ false);
            }
            return true;
        }
        int offset = buffer.position();
        int written = AaudioNativeBridge.nativeWrite(handle, buffer, offset,
                remaining);
        if (written != remaining) {
            throw new WriteException(-1, configuredFormat,
                    /* isRecoverable= */ false);
        }
        buffer.position(buffer.limit());
        return true;
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        if (handle == 0L || eosWritten) {
            return;
        }
        eosWritten = true;
        // Block until the device has consumed everything written.
        long deadline = android.os.SystemClock.elapsedRealtime() + 5000;
        while (handle != 0L
                && AaudioNativeBridge.nativeGetFramesRead(handle)
                        < AaudioNativeBridge.nativeGetFramesWritten(handle)) {
            if (android.os.SystemClock.elapsedRealtime() > deadline) {
                Log.w(TAG, "playToEndOfStream timed out waiting for drain");
                break;
            }
            android.os.SystemClock.sleep(10);
        }
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
        this.skipSilenceEnabled = skipSilenceEnabled;
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
    }

    @Override
    public void release() {
        closeHandle();
    }

    private void closeHandle() {
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
