package com.ryanheise.just_audio;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.os.Build;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.AuxEffectInfo;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.util.Clock;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.common.util.Util;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.PlayerId;
import androidx.media3.exoplayer.audio.AudioOffloadSupport;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;

import java.nio.ByteBuffer;

/**
 * Pulsr fork: stable Media3 sink whose inner backend can be swapped live.
 *
 * <p>Changing the output mode (16-bit &lt;-&gt; float &lt;-&gt; AAudio Direct) used to
 * release the whole ExoPlayer and re-prepare the media source, which restarted
 * the decoder/HTTP fetch, interrupted playback and could drop pending Dart
 * futures. The renderer now keeps this wrapper for the lifetime of the player
 * and only the inner sink is rebuilt. A swap requested from the app thread is
 * delivered through {@link ExoPlayer#createMessage} so it runs on the playback
 * thread, serialised with renderer calls; an AAudio failure inside configure or
 * handleBuffer falls back to the DefaultAudioSink in place and retries.
 *
 * <p>The wrapper caches every sink setting the renderer applies so a fresh
 * inner sink can be configured with the same state (listener, attributes,
 * session, volume, parameters, skip-silence, preferred device, EOS).
 */
@UnstableApi
final class PulsrAudioSink implements AudioSink, OutputSinkControl {
    private static final String TAG = "PulsrAudioSink";

    private enum Mode { DEFAULT, FLOAT, AAUDIO }

    /** Small functional interfaces (avoid java.util.function below API 24). */
    interface BooleanFlag { boolean get(); }
    interface IntFlag { int get(); }
    interface PlayerSupplier { ExoPlayer get(); }
    interface ProcessorListener { void onActiveProcessorChanged(NativeDspAudioProcessor processor); }
    interface FallbackListener {
        void onAaudioRejected(String reason, Exception cause);

        void onFloatRejected(String reason, Exception cause);
    }

    interface InnerFactory {
        Inner create(boolean aaudio, boolean floatMode);
    }

    /** Concrete refs for the routing registry plus the DSP processor (if any). */
    static final class Inner {
        final AudioSink sink;
        @Nullable final DefaultAudioSink defaultSink;
        @Nullable final AAudioAudioSink nativeSink;
        @Nullable final NativeDspAudioProcessor processor;

        Inner(AudioSink sink, @Nullable DefaultAudioSink defaultSink,
              @Nullable AAudioAudioSink nativeSink,
              @Nullable NativeDspAudioProcessor processor) {
            this.sink = sink;
            this.defaultSink = defaultSink;
            this.nativeSink = nativeSink;
            this.processor = processor;
        }
    }

    private final Context context;
    private final BooleanFlag aaudioEnabled;
    private final BooleanFlag preferExclusive;
    private final IntFlag targetBufferMs;
    private final BooleanFlag floatEnabled;
    private final PlayerSupplier playerSupplier;
    private final ProcessorListener processorListener;
    private final FallbackListener fallbackListener;
    @Nullable private final InnerFactory innerFactory;

    // State the renderer has applied; replayed onto every new inner sink.
    @Nullable private Listener listener;
    @Nullable private PlayerId playerId;
    @Nullable private Clock clock;
    @Nullable private AudioAttributes audioAttributes;
    private int audioSessionId = C.AUDIO_SESSION_ID_UNSET;
    @Nullable private AuxEffectInfo auxEffectInfo;
    @Nullable private AudioDeviceInfo preferredDevice;
    private PlaybackParameters playbackParameters = PlaybackParameters.DEFAULT;
    private boolean skipSilenceEnabled;
    private float volume = 1f;
    private boolean playWhenReady;
    private boolean tunnelingEnabled;
    private long outputStreamOffsetUs = C.TIME_UNSET;
    private int offloadMode = OFFLOAD_MODE_DISABLED;
    private int offloadDelayFrames;
    private int offloadPaddingFrames;
    private boolean enableAudioTrackPlaybackParams;
    private boolean released;

    // Current configuration and inner sink.
    @Nullable private Format format;
    private int bufferSize;
    @Nullable private int[] outputChannels;
    private boolean endOfStreamQueued;
    @Nullable private Inner currentInner;
    @Nullable private Mode mode;
    @Nullable private AudioSink inner;

    PulsrAudioSink(Context context, BooleanFlag aaudioEnabled, BooleanFlag preferExclusive,
            IntFlag targetBufferMs, BooleanFlag floatEnabled, PlayerSupplier playerSupplier,
            ProcessorListener processorListener, FallbackListener fallbackListener) {
        this(context, aaudioEnabled, preferExclusive, targetBufferMs, floatEnabled,
                playerSupplier, processorListener, fallbackListener, null);
    }

    PulsrAudioSink(Context context, BooleanFlag aaudioEnabled, BooleanFlag preferExclusive,
            IntFlag targetBufferMs, BooleanFlag floatEnabled, PlayerSupplier playerSupplier,
            ProcessorListener processorListener, FallbackListener fallbackListener,
            @Nullable InnerFactory innerFactory) {
        this.context = context;
        this.aaudioEnabled = aaudioEnabled;
        this.preferExclusive = preferExclusive;
        this.targetBufferMs = targetBufferMs;
        this.floatEnabled = floatEnabled;
        this.playerSupplier = playerSupplier;
        this.processorListener = processorListener;
        this.fallbackListener = fallbackListener;
        this.innerFactory = innerFactory;
    }

    void setEnableAudioTrackPlaybackParams(boolean enabled) {
        enableAudioTrackPlaybackParams = enabled;
    }

    private Mode desiredMode() {
        if (aaudioEnabled.get()) return Mode.AAUDIO;
        return floatEnabled.get() ? Mode.FLOAT : Mode.DEFAULT;
    }

    /** Called from the app thread; the actual swap runs on the playback thread. */
    @Override
    public void requestModeChange() {
        requestModeChange(false);
    }

    @Override
    public void requestModeChange(boolean force) {
        if (released) return;
        final ExoPlayer player = playerSupplier.get();
        if (player == null) return;
        final boolean forceSwap = force;
        try {
            player.createMessage((messageType, payload) -> applyPendingMode(forceSwap)).send();
        } catch (RuntimeException e) {
            // Player released between the check and the send, or wrong thread.
            Log.w(TAG, "Could not schedule audio output mode change", e);
        }
    }

    /** Runs on the playback thread; also directly callable from unit tests. */
    void applyPendingMode(boolean force) {
        if (released || format == null || currentInner == null) return;
        final Mode desired = desiredMode();
        if (force || desired != mode) {
            try {
                swapTo(desired, true);
            } catch (ConfigurationException | RuntimeException e) {
                // A message target must never throw into the playback thread.
                notifySinkError(e);
            }
        }
    }

    // ---- AudioSink ----

    @Override
    public void setListener(Listener listener) {
        this.listener = listener;
        if (inner != null) inner.setListener(listener);
    }

    @Override
    public void setPlayerId(@Nullable PlayerId playerId) {
        this.playerId = playerId;
        if (inner != null) inner.setPlayerId(playerId);
    }

    @Override
    public void setClock(Clock clock) {
        this.clock = clock;
        if (inner != null) inner.setClock(clock);
    }

    @Override
    public boolean supportsFormat(Format format) {
        return getFormatSupport(format) != SINK_FORMAT_UNSUPPORTED;
    }

    @Override
    public int getFormatSupport(Format format) {
        // The wrapper always feeds the inner DefaultAudioSink via float (or lets
        // AAudio accept/convert), so the wrapper advertises exactly what the
        // DefaultAudioSink path can transcode. AAudio restrictions are handled at
        // configure time with an in-place fallback instead of rejecting here.
        if (!MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)) {
            return SINK_FORMAT_UNSUPPORTED;
        }
        if (!Util.isEncodingLinearPcm(format.pcmEncoding)) {
            return SINK_FORMAT_UNSUPPORTED;
        }
        if (format.pcmEncoding == C.ENCODING_PCM_16BIT) {
            return SINK_FORMAT_SUPPORTED_DIRECTLY;
        }
        if (format.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            return floatEnabled.get()
                    ? SINK_FORMAT_SUPPORTED_DIRECTLY
                    : SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
        }
        return SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
    }

    @Override
    public AudioOffloadSupport getFormatOffloadSupport(Format format) {
        if (inner != null) return inner.getFormatOffloadSupport(format);
        return AudioOffloadSupport.DEFAULT_UNSUPPORTED;
    }

    @Override
    public long getCurrentPositionUs(boolean sourceEnded) {
        if (inner == null) return CURRENT_POSITION_NOT_SET;
        return inner.getCurrentPositionUs(sourceEnded);
    }

    @Override
    public void configure(Format inputFormat, int specifiedBufferSize,
            @Nullable int[] outputChannels) throws ConfigurationException {
        if (released) throw new IllegalStateException("PulsrAudioSink released");
        this.format = inputFormat;
        this.bufferSize = specifiedBufferSize;
        this.outputChannels = outputChannels == null ? null : outputChannels.clone();
        this.endOfStreamQueued = false;
        final Mode desired = desiredMode();
        if (currentInner == null || mode != desired) {
            swapTo(desired, false);
        } else {
            inner.configure(inputFormat, specifiedBufferSize, this.outputChannels);
        }
    }

    @Override
    public void play() {
        playWhenReady = true;
        if (inner != null) inner.play();
    }

    @Override
    public void handleDiscontinuity() {
        if (inner != null) inner.handleDiscontinuity();
    }

    @Override
    public boolean handleBuffer(ByteBuffer buffer, long presentationTimeUs,
            int encodedAccessUnitCount) throws InitializationException, WriteException {
        if (inner == null) {
            throw new IllegalStateException("configure() has not been called");
        }
        try {
            return inner.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
        } catch (WriteException | InitializationException e) {
            if (mode == Mode.AAUDIO && fallbackFromAaudio(e)) {
                return inner.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
            }
            throw e;
        }
    }

    @Override
    public void playToEndOfStream() throws WriteException {
        endOfStreamQueued = true;
        if (inner != null) inner.playToEndOfStream();
    }

    @Override
    public boolean isEnded() {
        return inner != null && inner.isEnded();
    }

    @Override
    public boolean hasPendingData() {
        return inner != null && inner.hasPendingData();
    }

    @Override
    public void setPlaybackParameters(PlaybackParameters playbackParameters) {
        this.playbackParameters = playbackParameters;
        if (inner != null) inner.setPlaybackParameters(playbackParameters);
    }

    @Override
    public PlaybackParameters getPlaybackParameters() {
        return inner != null ? inner.getPlaybackParameters() : playbackParameters;
    }

    @Override
    public void setSkipSilenceEnabled(boolean skipSilenceEnabled) {
        this.skipSilenceEnabled = skipSilenceEnabled;
        if (inner != null) inner.setSkipSilenceEnabled(skipSilenceEnabled);
    }

    @Override
    public boolean getSkipSilenceEnabled() {
        return skipSilenceEnabled;
    }

    @Override
    public void setAudioAttributes(AudioAttributes audioAttributes) {
        this.audioAttributes = audioAttributes;
        if (inner != null) inner.setAudioAttributes(audioAttributes);
    }

    @Nullable
    @Override
    public AudioAttributes getAudioAttributes() {
        return audioAttributes;
    }

    @Override
    public void setAudioSessionId(int audioSessionId) {
        this.audioSessionId = audioSessionId;
        if (inner != null) inner.setAudioSessionId(audioSessionId);
    }

    @Override
    public void setAuxEffectInfo(AuxEffectInfo auxEffectInfo) {
        this.auxEffectInfo = auxEffectInfo;
        if (inner != null) inner.setAuxEffectInfo(auxEffectInfo);
    }

    @Override
    public void setPreferredDevice(@Nullable AudioDeviceInfo audioDeviceInfo) {
        this.preferredDevice = audioDeviceInfo;
        if (inner != null) inner.setPreferredDevice(audioDeviceInfo);
    }

    @Override
    public void setOutputStreamOffsetUs(long outputStreamOffsetUs) {
        this.outputStreamOffsetUs = outputStreamOffsetUs;
        if (inner != null) inner.setOutputStreamOffsetUs(outputStreamOffsetUs);
    }

    @Override
    public void setOffloadMode(int offloadMode) {
        this.offloadMode = offloadMode;
        if (inner != null) inner.setOffloadMode(offloadMode);
    }

    @Override
    public void setOffloadDelayPadding(int delayInFrames, int paddingInFrames) {
        this.offloadDelayFrames = delayInFrames;
        this.offloadPaddingFrames = paddingInFrames;
        if (inner != null) inner.setOffloadDelayPadding(delayInFrames, paddingInFrames);
    }

    @Override
    public void enableTunnelingV21() {
        tunnelingEnabled = true;
        if (inner != null) inner.enableTunnelingV21();
    }

    @Override
    public void disableTunneling() {
        tunnelingEnabled = false;
        if (inner != null) inner.disableTunneling();
    }

    @Override
    public void setVolume(float volume) {
        this.volume = volume;
        if (inner != null) inner.setVolume(volume);
    }

    @Override
    public void pause() {
        playWhenReady = false;
        if (inner != null) inner.pause();
    }

    @Override
    public void flush() {
        endOfStreamQueued = false;
        if (inner != null) inner.flush();
    }

    @Override
    public void reset() {
        endOfStreamQueued = false;
        format = null;
        if (inner != null) inner.reset();
    }

    @Override
    public void release() {
        if (released) return;
        released = true;
        if (currentInner != null) {
            releaseInner(currentInner);
            currentInner = null;
        }
        inner = null;
        mode = null;
        if (processorListener != null) processorListener.onActiveProcessorChanged(null);
    }

    // ---- swap mechanics ----

    private void swapTo(Mode desired, boolean internal) throws ConfigurationException {
        // An active exclusive AAudio stream blocks opening another one (and a
        // shared AudioTrack while it runs). When either side of the transition
        // is AAudio, stop the old backend first; the fallback chain below still
        // guarantees a DefaultAudioSink if the new backend is refused. The
        // Default <-> Float transition keeps the old sink alive until the new
        // one is configured, so a failed swap can fall back without a gap.
        if (currentInner != null && (mode == Mode.AAUDIO || desired == Mode.AAUDIO)) {
            final Inner old = currentInner;
            currentInner = null;
            inner = null;
            mode = null;
            releaseInner(old);
        }
        Mode appliedMode = desired;
        Inner candidate;
        try {
            candidate = createConfigured(appliedMode);
        } catch (ConfigurationException | RuntimeException first) {
            if (desired == Mode.AAUDIO) {
                // The fallback listener flips the player's AAudio preference;
                // then honour the still-requested float/16-bit mode.
                notifyAaudioRejected("configure_failed", first);
                appliedMode = desiredMode();
                if (appliedMode == Mode.AAUDIO) {
                    appliedMode = floatEnabled.get() ? Mode.FLOAT : Mode.DEFAULT;
                }
            } else if (desired == Mode.FLOAT) {
                // Float is an enhancement; degrade to the historical 16-bit
                // sink instead of failing playback.
                notifyFloatRejected("configure_failed", first);
                appliedMode = Mode.DEFAULT;
            } else {
                failSwap(first, internal);
                return;
            }
            try {
                candidate = createConfigured(appliedMode);
            } catch (ConfigurationException | RuntimeException second) {
                if (appliedMode == Mode.FLOAT) {
                    notifyFloatRejected("configure_failed", second);
                    appliedMode = Mode.DEFAULT;
                    try {
                        candidate = createConfigured(appliedMode);
                    } catch (ConfigurationException | RuntimeException third) {
                        failSwap(third, internal);
                        return;
                    }
                } else {
                    failSwap(second, internal);
                    return;
                }
            }
        }

        // Carry any in-flight gain ramp/transition fade onto the replacement
        // DSP chain so a mode switch mid-fade does not jump to unity.
        if (candidate.processor != null && currentInner != null
                && currentInner.processor != null
                && currentInner.processor != candidate.processor) {
            currentInner.processor.copyContinuousStateTo(candidate.processor);
        }

        final Inner old = currentInner;
        currentInner = candidate;
        inner = candidate.sink;
        mode = appliedMode;
        if (processorListener != null) {
            processorListener.onActiveProcessorChanged(
                    appliedMode == Mode.AAUDIO ? null : candidate.processor);
        }
        if (old != null) releaseInner(old);

        if (playWhenReady) inner.play();
        if (endOfStreamQueued) {
            try {
                inner.playToEndOfStream();
            } catch (WriteException e) {
                notifySinkError(e);
            }
        }
    }

    private Inner createConfigured(Mode mode) throws ConfigurationException {
        Inner candidate = createInner(mode);
        try {
            applyState(candidate.sink);
            candidate.sink.configure(format, bufferSize, outputChannels);
            return candidate;
        } catch (ConfigurationException | RuntimeException failure) {
            releaseInner(candidate);
            throw failure;
        }
    }

    private void failSwap(Exception failure, boolean internal)
            throws ConfigurationException {
        if (internal) {
            notifySinkError(failure);
            return;
        }
        if (failure instanceof ConfigurationException) {
            throw (ConfigurationException) failure;
        }
        throw new ConfigurationException(failure, format);
    }

    private boolean fallbackFromAaudio(Exception cause) {
        notifyAaudioRejected("write_failed", cause);
        if (desiredMode() == Mode.AAUDIO) {
            // The player did not flip its preference (e.g. listener unavailable);
            // avoid an infinite AAudio retry loop.
            return false;
        }
        try {
            swapTo(desiredMode(), true);
        } catch (ConfigurationException e) {
            notifySinkError(e);
            return false;
        }
        return inner != null;
    }

    private void notifyAaudioRejected(String reason, Exception cause) {
        Log.w(TAG, "AAudio output rejected (" + reason + "); falling back", cause);
        if (fallbackListener != null) {
            fallbackListener.onAaudioRejected(reason, cause);
        }
    }

    private void notifyFloatRejected(String reason, Exception cause) {
        Log.w(TAG, "Float output rejected (" + reason + "); keeping current sink", cause);
        if (fallbackListener != null) {
            fallbackListener.onFloatRejected(reason, cause);
        }
    }

    private void notifySinkError(Exception e) {
        if (listener != null) listener.onAudioSinkError(e);
    }

    private void applyState(AudioSink sink) {
        if (listener != null) sink.setListener(listener);
        if (playerId != null) sink.setPlayerId(playerId);
        if (clock != null) sink.setClock(clock);
        if (audioAttributes != null) sink.setAudioAttributes(audioAttributes);
        if (audioSessionId != C.AUDIO_SESSION_ID_UNSET) sink.setAudioSessionId(audioSessionId);
        if (auxEffectInfo != null) sink.setAuxEffectInfo(auxEffectInfo);
        if (playbackParameters != null) sink.setPlaybackParameters(playbackParameters);
        sink.setSkipSilenceEnabled(skipSilenceEnabled);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && preferredDevice != null) {
            sink.setPreferredDevice(preferredDevice);
        }
        sink.setVolume(volume);
        if (outputStreamOffsetUs != C.TIME_UNSET) {
            sink.setOutputStreamOffsetUs(outputStreamOffsetUs);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            sink.setOffloadMode(offloadMode);
            sink.setOffloadDelayPadding(offloadDelayFrames, offloadPaddingFrames);
        }
        if (tunnelingEnabled) sink.enableTunnelingV21();
    }

    private Inner createInner(Mode requested) {
        if (innerFactory != null) {
            return innerFactory.create(requested == Mode.AAUDIO, requested == Mode.FLOAT);
        }
        if (requested == Mode.AAUDIO) {
            AAudioAudioSink nativeSink = new AAudioAudioSink(
                    preferExclusive.get(), targetBufferMs.get());
            PulsrOutputRouting.observe(nativeSink);
            return new Inner(nativeSink, null, nativeSink, null);
        }
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        processor.setFloatOutput(requested == Mode.FLOAT);
        DefaultAudioSink defaultSink = new DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(requested == Mode.FLOAT)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .setAudioProcessors(requested == Mode.FLOAT
                        ? new androidx.media3.common.audio.AudioProcessor[0]
                        : new androidx.media3.common.audio.AudioProcessor[] { processor })
                .build();
        PulsrOutputRouting.observe(defaultSink);
        AudioSink outer = requested == Mode.FLOAT
                ? new FloatDspAudioSink(defaultSink, processor)
                : defaultSink;
        return new Inner(outer, defaultSink, null, processor);
    }

    private void releaseInner(Inner holder) {
        if (holder.nativeSink != null) PulsrOutputRouting.unobserve(holder.nativeSink);
        if (holder.defaultSink != null) PulsrOutputRouting.unobserve(holder.defaultSink);
        try {
            holder.sink.release();
        } catch (RuntimeException e) {
            Log.w(TAG, "Inner sink release failed: " + e.getMessage());
        }
        if (holder.processor != null) {
            try {
                holder.processor.release();
            } catch (RuntimeException e) {
                Log.w(TAG, "Processor release failed: " + e.getMessage());
            }
        }
    }
}
