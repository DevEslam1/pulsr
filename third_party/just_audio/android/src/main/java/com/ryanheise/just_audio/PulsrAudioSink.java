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

        default void onAaudioSuspended(String reason, boolean suspended) {}

        default void onTapSrcFailed(Exception cause) {}
    }

    boolean isTapSrcFailed() {
        return tapSrcFailed;
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
    private volatile boolean playWhenReady;
    private boolean tunnelingEnabled;
    private long outputStreamOffsetUs = C.TIME_UNSET;
    private int offloadMode = OFFLOAD_MODE_DISABLED;
    private int offloadDelayFrames;
    private int offloadPaddingFrames;
    private boolean enableAudioTrackPlaybackParams;
    private volatile boolean released;
    private volatile boolean precisionFallback;
    private boolean tapSrcFailed;
    private boolean pendingModeRequested;
    private boolean pendingForce;
    private boolean aaudioSuspendedByParams;
    private String lastSuspensionReason = "speed_requires_audiotrack";
    private int lastReportedFormatSupport = -1;
    @Nullable private NativeDspAudioProcessor continuousState;

    private boolean hasStagedInput() {
        return inner instanceof FloatDspAudioSink && ((FloatDspAudioSink) inner).hasStagedInput()
                || inner instanceof AAudioAudioSink && ((AAudioAudioSink) inner).hasStagedInput();
    }
    private volatile int[] decodedPcm = new int[] {0, 0, 0};

    int[] decodedPcmSnapshot() { return decodedPcm.clone(); }
    boolean isPlayingForTelemetry() { return playWhenReady && format != null && !released; }

    // Current configuration and inner sink.
    @Nullable private volatile Format format;
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

    boolean aaudioBlockedByParams() {
        return (playbackParameters != null && !PlaybackParameters.DEFAULT.equals(playbackParameters))
                || skipSilenceEnabled;
    }

    private String suspensionReasonForParams() {
        if (playbackParameters != null && !PlaybackParameters.DEFAULT.equals(playbackParameters)) {
            return "speed_requires_audiotrack";
        }
        return "skip_silence_requires_audiotrack";
    }

    // VERIFY: speed toggle in bit-perfect mode on a physical device switches cleanly between AAudio and AudioTrack.
    private Mode desiredMode() {
        if (aaudioEnabled.get() && !aaudioBlockedByParams()) return Mode.AAUDIO;
        return floatEnabled.get() && !precisionFallback ? Mode.FLOAT : Mode.DEFAULT;
    }

    /** Called from the app thread; the actual swap runs on the playback thread. */
    @Override
    public void requestModeChange() {
        requestModeChange(false);
    }

    @Override
    public void requestModeChange(boolean force) {
        if (released) return;
        // A new explicit float request may retry a previously rejected route.
        if (!force && floatEnabled.get()) precisionFallback = false;
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
        if (!aaudioEnabled.get()) {
            aaudioSuspendedByParams = false;
        }
        if (released || format == null || currentInner == null) return;
        if (hasStagedInput()) {
            pendingModeRequested = true;
            pendingForce |= force;
            return;
        }
        final Mode desired = desiredMode();
        if (force || desired != mode) {
            try {
                swapTo(desired, true, true);
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
        // VERIFY: on a device with a 24-bit FLAC that the decoder output stays 24-bit/float over AAudio.
        final int support;
        if (!MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)
                || !Util.isEncodingLinearPcm(format.pcmEncoding)) {
            support = SINK_FORMAT_UNSUPPORTED;
        } else if (desiredMode() == Mode.AAUDIO
                && format.sampleRate > 0
                && format.channelCount > 0
                && format.channelCount <= 2) {
            if (format.pcmEncoding == C.ENCODING_PCM_16BIT
                    || format.pcmEncoding == C.ENCODING_PCM_FLOAT
                    || format.pcmEncoding == C.ENCODING_PCM_24BIT
                    || (format.pcmEncoding == C.ENCODING_PCM_32BIT
                            && AAudioAudioSink.deviceApiLevel() >= 31
                            && preferExclusive.get())) {
                support = SINK_FORMAT_SUPPORTED_DIRECTLY;
            } else {
                support = SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
            }
        } else if (format.pcmEncoding == C.ENCODING_PCM_16BIT) {
            support = SINK_FORMAT_SUPPORTED_DIRECTLY;
        } else if (format.pcmEncoding == C.ENCODING_PCM_FLOAT) {
            support = (floatEnabled.get() && !precisionFallback) || aaudioEnabled.get()
                    ? SINK_FORMAT_SUPPORTED_DIRECTLY
                    : SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
        } else {
            support = SINK_FORMAT_SUPPORTED_WITH_TRANSCODING;
        }
        if (support != lastReportedFormatSupport) {
            lastReportedFormatSupport = support;
            Log.i(TAG, "getFormatSupport(mode=" + desiredMode()
                    + ", enc=" + format.pcmEncoding
                    + ", rate=" + format.sampleRate
                    + ", ch=" + format.channelCount
                    + ") -> " + support);
        }
        return support;
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
        decodedPcm = new int[] {inputFormat.pcmEncoding, inputFormat.sampleRate, inputFormat.channelCount};
        PulsrOutputRouting.observeDecoded(this, playerSupplier.get());
        this.bufferSize = specifiedBufferSize;
        this.outputChannels = outputChannels == null ? null : outputChannels.clone();
        this.endOfStreamQueued = false;
        final Mode desired = desiredMode();
        if (currentInner == null || mode != desired) {
            swapTo(desired, false, false);
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
            final Format fmt = format != null ? format : new Format.Builder().build();
            throw new InitializationException(
                    "configure() has not been called", 0, fmt, false, null);
        }
        try {
            boolean consumed = inner.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
            if (pendingModeRequested && !hasStagedInput()) {
                boolean force = pendingForce;
                pendingModeRequested = false;
                pendingForce = false;
                applyPendingMode(force);
            }
            return consumed;
        } catch (NativeDspAudioProcessor.TapSrcException e) {
            // No source or editor state was committed. Reconfigure at source
            // rate; never send wrong-rate passthrough bytes into the old track.
            tapSrcFailed = true;
            if (fallbackListener != null) fallbackListener.onTapSrcFailed(e);
            notifySinkError(e);
            try {
                swapTo(mode, false, true);
            } catch (ConfigurationException failure) {
                throw new InitializationException("Source-rate fallback configuration failed", 0,
                        format, false, failure);
            }
            return inner.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
        } catch (WriteException | InitializationException e) {
            if (mode == Mode.AAUDIO) {
                if (fallbackFromAaudio(e)) {
                    return inner.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount);
                }
            }
            if (mode == Mode.FLOAT) {
                precisionFallback = true;
                notifyFloatRejected(e instanceof InitializationException ? "initialize_failed" : "write_failed", e);
                try {
                    swapTo(Mode.DEFAULT, false, true);
                } catch (ConfigurationException failure) {
                    notifySinkError(failure);
                    throw e;
                }
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
        PlaybackParameters resolved = playbackParameters == null
                ? PlaybackParameters.DEFAULT : playbackParameters;
        this.playbackParameters = resolved;
        final AudioSink previousInner = inner;
        if (desiredMode() != mode) {
            applyPendingMode(false);
        }
        if (inner != null && inner == previousInner
                && !(mode == Mode.AAUDIO && !PlaybackParameters.DEFAULT.equals(resolved))) {
            inner.setPlaybackParameters(resolved);
        }
        if (aaudioSuspendedByParams && aaudioBlockedByParams()) {
            lastSuspensionReason = suspensionReasonForParams();
        }
    }

    @Override
    public PlaybackParameters getPlaybackParameters() {
        return inner != null ? inner.getPlaybackParameters() : playbackParameters;
    }

    @Override
    public void setSkipSilenceEnabled(boolean skipSilenceEnabled) {
        this.skipSilenceEnabled = skipSilenceEnabled;
        final AudioSink previousInner = inner;
        if (desiredMode() != mode) {
            applyPendingMode(false);
        }
        if (inner != null && inner == previousInner
                && !(mode == Mode.AAUDIO && skipSilenceEnabled)) {
            inner.setSkipSilenceEnabled(skipSilenceEnabled);
        }
        if (aaudioSuspendedByParams && aaudioBlockedByParams()) {
            lastSuspensionReason = suspensionReasonForParams();
        }
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
    public long getAudioTrackBufferSizeUs() {
        return inner != null ? inner.getAudioTrackBufferSizeUs() : C.TIME_UNSET;
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
        if (currentInner != null && currentInner.processor != null)
            currentInner.processor.releaseUsbProducer();
    }

    @Override
    public void flush() {
        endOfStreamQueued = false;
        if (inner != null) inner.flush();
        // Default mode inserts the processor in the DefaultAudioSink chain, so
        // Media3 flushes it without FloatDspAudioSink's explicit native reset.
        // Clear the DSP history here after the sink flush (whose onFlush may
        // have re-synced the rate) so a seek cannot replay the old position's
        // reverb tail/limiter envelope. Float mode resets inside its own flush.
        final Inner current = currentInner;
        if (mode == Mode.DEFAULT && current != null && current.processor != null) {
            current.processor.resetNativeState();
        }
    }

    @Override
    public void reset() {
        endOfStreamQueued = false;
        format = null;
        continuousState = null;
        pendingModeRequested = false;
        pendingForce = false;
        tapSrcFailed = false;
        decodedPcm = new int[] {0, 0, 0};
        if (currentInner != null && currentInner.processor != null)
            currentInner.processor.releaseUsbProducer();
        if (inner != null) inner.reset();
    }

    @Override
    public void release() {
        if (released) return;
        released = true;
        continuousState = null;
        aaudioSuspendedByParams = false;
        decodedPcm = new int[] {0, 0, 0};
        PulsrOutputRouting.unobserveDecoded(this);
        if (currentInner != null) {
            releaseInner(currentInner);
            currentInner = null;
        }
        inner = null;
        mode = null;
        if (processorListener != null) processorListener.onActiveProcessorChanged(null);
    }

    // ---- swap mechanics ----

    private void swapTo(Mode desired, boolean internal, boolean sameStream) throws ConfigurationException {
        final Inner previous = currentInner;
        // Error policy (internal) is independent of stream identity: SRC/write
        // fallbacks must retain trimming even when their errors are propagated.
        final Inner continuing = sameStream ? previous : null;
        if (previous != null && previous.processor != null) continuousState = previous.processor;
        // An active exclusive AAudio stream blocks opening another one (and a
        // shared AudioTrack while it runs). Release-first is only required when
        // leaving AAUDIO or entering AAUDIO with preferExclusive; in shared mode
        // or Default <-> Float transitions keep the old sink alive until the
        // candidate is configured so a failed swap can fall back without a gap.
        final boolean leavingAaudio = (mode == Mode.AAUDIO);
        final boolean enteringAaudioExclusive = (desired == Mode.AAUDIO && preferExclusive.get());
        if (currentInner != null && (leavingAaudio || enteringAaudioExclusive)) {
            final Inner old = currentInner;
            currentInner = null;
            inner = null;
            mode = null;
            if (processorListener != null) processorListener.onActiveProcessorChanged(null);
            releaseInner(old);
        }
        Mode appliedMode = desired;
        Inner candidate = null;
        Exception lastFailure = null;
        try {
            candidate = createConfigured(appliedMode, continuing);
        } catch (ConfigurationException | RuntimeException first) {
            lastFailure = first;
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
            }
            if (appliedMode != desired) {
                try {
                    candidate = createConfigured(appliedMode, continuing);
                } catch (ConfigurationException | RuntimeException second) {
                    lastFailure = second;
                    if (appliedMode == Mode.FLOAT) {
                        notifyFloatRejected("configure_failed", second);
                        appliedMode = Mode.DEFAULT;
                        try {
                            candidate = createConfigured(appliedMode, continuing);
                        } catch (ConfigurationException | RuntimeException third) {
                            lastFailure = third;
                        }
                    }
                }
            }
        }
        if (candidate == null && internal && currentInner == null) {
            try {
                candidate = createConfigured(Mode.DEFAULT, null);
                appliedMode = Mode.DEFAULT;
            } catch (ConfigurationException | RuntimeException lastResortFailure) {
                lastFailure = lastResortFailure;
            }
        }
        if (candidate == null) {
            failSwap(lastFailure, internal);
            return;
        }

        final Inner old = currentInner;
        if (sameStream && previous != null && candidate.sink instanceof FloatDspAudioSink) {
            // Continue only the unaccepted tail; carry gapless state across modes.
            if (previous.sink instanceof FloatDspAudioSink)
                ((FloatDspAudioSink) previous.sink).transferPendingTo((FloatDspAudioSink) candidate.sink);
            else if (previous.nativeSink != null)
                previous.nativeSink.transferPendingTo((FloatDspAudioSink) candidate.sink);
        } else if (sameStream && previous != null && candidate.nativeSink != null) {
            if (previous.sink instanceof FloatDspAudioSink)
                candidate.nativeSink.adoptFrameEditor(((FloatDspAudioSink) previous.sink).frameEditor());
            else if (previous.nativeSink != null)
                candidate.nativeSink.adoptFrameEditor(previous.nativeSink.frameEditor());
        }
        currentInner = candidate;
        inner = candidate.sink;
        mode = appliedMode;
        if (processorListener != null) {
            processorListener.onActiveProcessorChanged(
                    appliedMode == Mode.AAUDIO ? null : candidate.processor);
        }
        if (tapSrcFailed && candidate.processor != null) candidate.processor.setTapSrcTargetRate(0);
        if (old != null) releaseInner(old);
        updateAaudioSuspensionNotification(appliedMode);

        if (playWhenReady) inner.play();
        if (endOfStreamQueued) {
            try {
                inner.playToEndOfStream();
            } catch (WriteException e) {
                notifySinkError(e);
            }
        }
    }

    private Inner createConfigured(Mode mode, @Nullable Inner previous) throws ConfigurationException {
        Inner candidate = createInner(mode);
        try {
            applyState(candidate.sink);
            if (continuousState != null && candidate.processor != null)
                continuousState.copyContinuousStateTo(candidate.processor);
            // Listener owns the current device target. Install it BEFORE final
            // configure/flush latches the output rate, including first playback.
            if (processorListener != null) processorListener.onActiveProcessorChanged(candidate.processor);
            if (tapSrcFailed && candidate.processor != null) candidate.processor.setTapSrcTargetRate(0);
            if (previous != null && previous.sink instanceof FloatDspAudioSink
                    && ((FloatDspAudioSink) previous.sink).hasStagedInput()
                    && candidate.sink instanceof FloatDspAudioSink) {
                ((FloatDspAudioSink) previous.sink).configurePendingReplacement(
                        (FloatDspAudioSink) candidate.sink);
            } else {
                candidate.sink.configure(format, bufferSize, outputChannels);
            }
            return candidate;
        } catch (ConfigurationException | RuntimeException failure) {
            if (processorListener != null) processorListener.onActiveProcessorChanged(
                    currentInner == null ? null : currentInner.processor);
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
            swapTo(desiredMode(), true, true);
        } catch (ConfigurationException e) {
            notifySinkError(e);
            return false;
        }
        return inner != null;
    }

    private void updateAaudioSuspensionNotification(Mode appliedMode) {
        if (!aaudioEnabled.get()) {
            aaudioSuspendedByParams = false;
            return;
        }
        if (aaudioBlockedByParams() && appliedMode != Mode.AAUDIO) {
            final String reason = suspensionReasonForParams();
            lastSuspensionReason = reason;
            if (!aaudioSuspendedByParams) {
                aaudioSuspendedByParams = true;
                if (fallbackListener != null) {
                    fallbackListener.onAaudioSuspended(reason, true);
                }
            }
        } else if (aaudioSuspendedByParams && appliedMode == Mode.AAUDIO) {
            aaudioSuspendedByParams = false;
            if (fallbackListener != null) {
                fallbackListener.onAaudioSuspended(lastSuspensionReason, false);
            }
        }
    }

    private void notifyAaudioRejected(String reason, Exception cause) {
        Log.w(TAG, "AAudio output rejected (" + reason + "); falling back", cause);
        if (fallbackListener != null) {
            fallbackListener.onAaudioRejected(reason, cause);
        }
    }

    private void notifyFloatRejected(String reason, Exception cause) {
        precisionFallback = true;
        Log.w(TAG, "Float output rejected (" + reason + "); using dithered PCM16 (not bit-perfect)", cause);
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
        // Own the high-resolution path even for DEFAULT: Media3's stock
        // converter discards PCM24/32 low bytes before custom DSP can see them.
        NativeDspAudioProcessor processor = new NativeDspAudioProcessor();
        processor.setFloatOutput(true);
        DefaultAudioSink defaultSink = new DefaultAudioSink.Builder(context)
                .setEnableFloatOutput(requested == Mode.FLOAT)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .setAudioProcessors(new androidx.media3.common.audio.AudioProcessor[0])
                .build();
        PulsrOutputRouting.observe(defaultSink);
        AudioSink outer = new FloatDspAudioSink(
                defaultSink, processor, true, requested == Mode.DEFAULT, true);
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
