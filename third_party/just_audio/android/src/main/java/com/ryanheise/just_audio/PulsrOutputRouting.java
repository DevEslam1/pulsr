package com.ryanheise.just_audio;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import android.os.Build;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.audio.AudioOutput;
import androidx.media3.exoplayer.audio.AudioOutputProvider;
import androidx.media3.exoplayer.audio.AudioTrackAudioOutput;
import androidx.media3.exoplayer.audio.AudioTrackAudioOutputProvider;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioOutputProvider;
import java.lang.ref.WeakReference;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/** App-owned media routing. Preferences and measured routes are deliberately separate. */
@androidx.media3.common.util.UnstableApi
public final class PulsrOutputRouting {
    private static final String TAG = "PulsrOutputRouting";
    private static final Set<ExoPlayer> players =
            Collections.newSetFromMap(new WeakHashMap<>());
    // Use explicit-lifetime sets for sinks: WeakHashMap risks silent GC-collection
    // of active sinks if the renderer holds the only strong reference internally.
    private static final Set<DefaultAudioSink> sinks = new HashSet<>();
    private static final Set<AAudioAudioSink> nativeSinks = new HashSet<>();
    private static final Map<PulsrAudioSink, WeakReference<ExoPlayer>> decodedOwners =
            new WeakHashMap<>();
    private static final Map<DefaultAudioSink, CapturingAudioOutputProvider> capturedProviders =
            new WeakHashMap<>();

    static final class CapturingAudioOutputProvider extends ForwardingAudioOutputProvider {
        @Nullable private volatile WeakReference<AudioTrack> latestTrack;

        CapturingAudioOutputProvider(AudioOutputProvider delegate) {
            super(delegate);
        }

        @Override
        public AudioOutput getAudioOutput(OutputConfig config) throws InitializationException {
            AudioOutput output = super.getAudioOutput(config);
            if (output instanceof AudioTrackAudioOutput) {
                latestTrack = new WeakReference<>(((AudioTrackAudioOutput) output).getAudioTrack());
            }
            return output;
        }

        @Override
        public void release() {
            latestTrack = null;
            super.release();
        }

        @Nullable
        AudioTrack getCapturedTrack() {
            final WeakReference<AudioTrack> ref = latestTrack;
            return ref == null ? null : ref.get();
        }
    }

    static CapturingAudioOutputProvider createCapturingOutputProvider(Context context) {
        return createCapturingOutputProvider(context, null);
    }

    static CapturingAudioOutputProvider createCapturingOutputProvider(
            Context context,
            @Nullable DefaultAudioSink.AudioTrackBufferSizeProvider bufferSizeProvider) {
        captureDebugFlag(context);
        AudioTrackAudioOutputProvider.Builder builder =
                new AudioTrackAudioOutputProvider.Builder(context);
        if (bufferSizeProvider != null) {
            builder.setAudioTrackBufferSizeProvider(bufferSizeProvider);
        }
        return new CapturingAudioOutputProvider(builder.build());
    }

    private static void captureDebugFlag(@Nullable Context context) {
        if (context == null) return;
        ApplicationInfo info = context.getApplicationInfo();
        if (info != null) {
            debugBuild = (info.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        }
    }

    static synchronized void observeDecoded(PulsrAudioSink sink, @Nullable ExoPlayer player) {
        if (player == null) {
            decodedOwners.remove(sink);
        } else {
            decodedOwners.put(sink, new WeakReference<>(player));
        }
    }

    static synchronized void unobserveDecoded(PulsrAudioSink sink) { decodedOwners.remove(sink); }
    private static AudioDeviceInfo preferred;
    private static Field audioTrackField;
    private static Field audioOutputField;
    private static Field audioOutputTrackField;
    private static Method getAudioTrackMethod;
    private static boolean reflectionLookupDone = false;
    private static boolean audioOutputReflectionDone = false;
    private static boolean reflectionWarningLogged = false;
    private static boolean trackMissLogged = false;
    private static volatile boolean debugBuild = false;
    // App-level bit-perfect / DSD-over-PCM request. Deliberately outside
    // snapshot(): this is what the app asks for, not what the sink achieved,
    // and the native sink may still refuse to assert it.
    private static volatile boolean bitPerfectRequested = false;
    private static volatile boolean dopRequested = false;

    private static synchronized void ensureReflectionInitialized() {
        if (reflectionLookupDone) return;
        reflectionLookupDone = true;

        try {
            audioTrackField = DefaultAudioSink.class.getDeclaredField("audioTrack");
            audioTrackField.setAccessible(true);
        } catch (NoSuchFieldException ignored) {}

        try {
            audioOutputField = DefaultAudioSink.class.getDeclaredField("audioOutput");
            audioOutputField.setAccessible(true);
        } catch (NoSuchFieldException ignored) {}

        if (audioTrackField == null && audioOutputField == null && !reflectionWarningLogged) {
            reflectionWarningLogged = true;
            Log.w(TAG,
                "Media3 DefaultAudioSink reflection unavailable; output-device telemetry will return [0,0,0].");
            Log.e(TAG,
                "TELEMETRY_DEGRADED: DefaultAudioSink fields (audioTrack/audioOutput) lookup failed.");
        }
    }

    @Nullable
    private static AudioTrack getAudioTrackFromSink(DefaultAudioSink sink) {
        if (sink == null) return null;
        final CapturingAudioOutputProvider provider = capturedProviders.get(sink);
        if (provider != null) {
            final AudioTrack captured = provider.getCapturedTrack();
            if (captured != null) return captured;
        }

        final AudioTrack reflected = getAudioTrackViaReflection(sink);
        if (reflected != null) return reflected;

        if (!trackMissLogged && (debugBuild || Log.isLoggable(TAG, Log.DEBUG))) {
            trackMissLogged = true;
            Log.d(TAG, "Unable to read AudioTrack from DefaultAudioSink via provider or reflection.");
        }
        return null;
    }

    @Nullable
    private static AudioTrack getAudioTrackViaReflection(DefaultAudioSink sink) {
        ensureReflectionInitialized();

        if (audioTrackField != null) {
            try {
                Object obj = audioTrackField.get(sink);
                if (obj instanceof AudioTrack) return (AudioTrack) obj;
            } catch (Exception ignored) {}
        }

        if (audioOutputField != null) {
            try {
                Object audioOutput = audioOutputField.get(sink);
                if (audioOutput != null) {
                    if (getAudioTrackMethod == null) {
                        try {
                            getAudioTrackMethod = audioOutput.getClass().getMethod("getAudioTrack");
                            getAudioTrackMethod.setAccessible(true);
                        } catch (Exception ignored) {}
                    }
                    if (getAudioTrackMethod != null) {
                        Object obj = getAudioTrackMethod.invoke(audioOutput);
                        if (obj instanceof AudioTrack) return (AudioTrack) obj;
                    }
                    if (!audioOutputReflectionDone) {
                        audioOutputReflectionDone = true;
                        try {
                            audioOutputTrackField =
                                    audioOutput.getClass().getDeclaredField("audioTrack");
                            audioOutputTrackField.setAccessible(true);
                        } catch (Exception ignored) {}
                    }
                    if (audioOutputTrackField != null) {
                        try {
                            Object obj = audioOutputTrackField.get(audioOutput);
                            if (obj instanceof AudioTrack) return (AudioTrack) obj;
                        } catch (Exception ignored) {}
                    }
                }
            } catch (Exception ignored) {}
        }

        return null;
    }

    private PulsrOutputRouting() {}

    public static synchronized void register(ExoPlayer player) {
        players.add(player);
        player.setPreferredAudioDevice(preferred);
    }

    public static synchronized void unregister(ExoPlayer player) { players.remove(player); }

    public static synchronized void observe(DefaultAudioSink sink) {
        observe(sink, null);
    }

    static synchronized void observe(DefaultAudioSink sink,
            @Nullable CapturingAudioOutputProvider provider) {
        sinks.add(sink);
        if (provider != null) {
            capturedProviders.put(sink, provider);
        }
    }

    public static synchronized void unobserve(DefaultAudioSink sink) {
        sinks.remove(sink);
        capturedProviders.remove(sink);
    }

    public static synchronized void observe(AAudioAudioSink sink) { nativeSinks.add(sink); }

    public static synchronized void unobserve(AAudioAudioSink sink) { nativeSinks.remove(sink); }

    public static synchronized boolean select(AudioDeviceInfo device) {
        // Best-effort per player: one released/failed player must neither abort
        // the routing of the remaining players nor leave the stored
        // preference disagreeing with the iteration.
        boolean allApplied = true;
        for (ExoPlayer player : players) {
            try {
                player.setPreferredAudioDevice(device);
            } catch (RuntimeException failure) {
                allApplied = false;
            }
        }
        preferred = device;
        AudioPlayer.clearAaudioProbeCache();
        return allApplied;
    }

    /** Returns the selected preferred output device ID, or 0 for system default. */
    public static synchronized int preferredDeviceId() {
        return preferred == null ? 0 : preferred.getId();
    }

    /** Records the app-level bit-perfect request mirrored onto AAudio sinks. */
    public static void setBitPerfectRequested(boolean requested) {
        bitPerfectRequested = requested;
    }

    /** True while the app has asked for bit-perfect AAudio output. */
    public static boolean isBitPerfectRequested() {
        return bitPerfectRequested;
    }

    /** Records the app-level DoP request mirrored onto AAudio sinks. */
    public static void setDopRequested(boolean requested) {
        dopRequested = requested;
    }

    /** True while the app has asked for a DSD-over-PCM carrier. */
    public static boolean isDopRequested() {
        return dopRequested;
    }

    /** True while a registered AAudio or AudioTrack stream is playing. */
    public static synchronized boolean isPlaying() {
        for (AAudioAudioSink sink : nativeSinks) {
            if (sink.isPlaying() && sink.measuredStream()[1] > 0) return true;
        }
        for (DefaultAudioSink sink : sinks) {
            AudioTrack track = getAudioTrackFromSink(sink);
            try {
                if (track != null && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return true;
            } catch (IllegalStateException released) {
                // Track released concurrently by the playback thread; skip it.
            }
        }
        return false;
    }

    /**
     * Decoded PCM truth probe: [encoding, sampleRate, channels] of the last
     * Media3 float-tap configure, or zeros when it has not run yet.
     */
    public static synchronized int[] decodedPcmSnapshot() {
        return decodedPcmSnapshotInternal(/*includePaused=*/false);
    }

    /**
     * Same as {@link #decodedPcmSnapshot()}, but falls back to a single
     * configured-but-paused sink when no sink is actively playing. Needed when
     * negotiating exclusive mixer attributes inside a paused policy transition
     * (otherwise the paused sink reports [0, 0, 0] and forces the DAC's max rate).
     */
    public static synchronized int[] decodedPcmSnapshotIncludingPaused() {
        int[] playing = decodedPcmSnapshotInternal(/*includePaused=*/false);
        if (playing[1] > 0) return playing;
        return decodedPcmSnapshotInternal(/*includePaused=*/true);
    }

    private static int[] decodedPcmSnapshotInternal(boolean includePaused) {
        PulsrAudioSink active = null;
        final Iterator<Map.Entry<PulsrAudioSink, WeakReference<ExoPlayer>>> it =
                decodedOwners.entrySet().iterator();
        while (it.hasNext()) {
            final Map.Entry<PulsrAudioSink, WeakReference<ExoPlayer>> entry = it.next();
            if (entry.getValue() == null || entry.getValue().get() == null) {
                it.remove();
                continue;
            }
            final PulsrAudioSink sink = entry.getKey();
            if (includePaused ? !sink.hasConfiguredStreamForTelemetry() : !sink.isPlayingForTelemetry()) {
                continue;
            }
            // During crossfade there is no unique active session. Unknown is
            // safer than mixing one player's decoder with another's output.
            if (active != null) return new int[] {0, 0, 0};
            active = sink;
        }
        return active == null ? new int[] {0, 0, 0} : active.decodedPcmSnapshot();
    }

    public static synchronized int[] decodedPcmSnapshot(@Nullable ExoPlayer player) {
        if (player == null) return new int[] {0, 0, 0};
        final Iterator<Map.Entry<PulsrAudioSink, WeakReference<ExoPlayer>>> it =
                decodedOwners.entrySet().iterator();
        while (it.hasNext()) {
            final Map.Entry<PulsrAudioSink, WeakReference<ExoPlayer>> entry = it.next();
            final ExoPlayer owner = entry.getValue() == null ? null : entry.getValue().get();
            if (owner == null) {
                it.remove();
                continue;
            }
            if (owner == player) return entry.getKey().decodedPcmSnapshot();
        }
        return new int[] {0, 0, 0};
    }

    /** True while a native AAudio sink is registered (playing or idle). */
    public static synchronized boolean hasAaudioSink() {
        return !nativeSinks.isEmpty();
    }

    /**
     * Observed app stream: [device ID, app stream rate, PCM encoding, decoded
     * input encoding, 1 when the integer bit-perfect bypass is active for this
     * stream else 0]. Zero means unverified.
     *
     * <p>Elements 3 and 4 are read from the {@link PulsrAudioSink} that produced
     * elements 0..2, so they belong to this stream; when that attribution is
     * ambiguous (for example during a crossfade) they stay 0 rather than mix one
     * player's decoder with another's output. Element 3 holds Media3
     * {@code C.ENCODING_PCM_*} values, which are numerically identical to
     * {@code AudioFormat.ENCODING_*} for PCM. This describes the app stream, not
     * a claim about the downstream DAC/mixer.
     */
    public static synchronized int[] snapshot() {
        int[] nativeFallback = null;
        PulsrAudioSink nativeFallbackOwner = null;
        for (AAudioAudioSink sink : nativeSinks) {
            int[] measured = sink.measuredStream();
            if (measured[1] == 0) continue;
            nativeFallback = measured;
            nativeFallbackOwner = ownerOf(sink);
            if (sink.isPlaying()) return withDecodedPath(measured, nativeFallbackOwner);
        }
        AudioTrack fallback = null;
        PulsrAudioSink fallbackOwner = null;
        for (DefaultAudioSink sink : sinks) {
            AudioTrack track = getAudioTrackFromSink(sink);
            try {
                if (track == null || track.getState() != AudioTrack.STATE_INITIALIZED) continue;
                if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING)
                    return snapshot(track, ownerOf(sink));
                fallback = track;
                fallbackOwner = ownerOf(sink);
            } catch (IllegalStateException released) {
                // Track released concurrently by the playback thread; skip it.
            }
        }
        if (fallback != null) {
            try {
                return snapshot(fallback, fallbackOwner);
            } catch (IllegalStateException released) {
                // fall through to native/zero result
            }
        }
        return nativeFallback != null ? withDecodedPath(nativeFallback, nativeFallbackOwner)
                : new int[] {0, 0, 0, C.ENCODING_INVALID, 0};
    }

    private static int[] snapshot(AudioTrack track, @Nullable PulsrAudioSink owner) {
        AudioDeviceInfo routed = Build.VERSION.SDK_INT >= 24 ? track.getRoutedDevice() : null;
        return withDecodedPath(new int[] {routed == null ? 0 : routed.getId(),
                track.getSampleRate(), track.getAudioFormat()}, owner);
    }

    /**
     * Keeps elements 0..2 of {@code base} exactly and appends the owning sink's
     * decoded input encoding plus the integer-bypass flag. A null owner (no
     * measured stream or an ambiguous one) leaves both new elements at 0.
     */
    private static int[] withDecodedPath(int[] base, @Nullable PulsrAudioSink owner) {
        return new int[] {
                base.length > 0 ? base[0] : 0,
                base.length > 1 ? base[1] : 0,
                base.length > 2 ? base[2] : 0,
                owner == null ? C.ENCODING_INVALID : owner.inputPcmEncodingForTelemetry(),
                owner != null && owner.integerBypassActiveForTelemetry() ? 1 : 0,
        };
    }

    /** The player whose live inner backend is {@code innerSink}, or null if none. */
    @Nullable
    private static PulsrAudioSink ownerOf(@Nullable Object innerSink) {
        if (innerSink == null) return null;
        PulsrAudioSink owner = null;
        for (PulsrAudioSink candidate : decodedOwners.keySet()) {
            if (!candidate.ownsInnerSink(innerSink)) continue;
            // Two players claiming one backend would mean a half-finished swap;
            // report unknown instead of guessing.
            if (owner != null) return null;
            owner = candidate;
        }
        return owner;
    }
}
