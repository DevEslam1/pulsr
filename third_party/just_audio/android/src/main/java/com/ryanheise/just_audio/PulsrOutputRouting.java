package com.ryanheise.just_audio;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import android.os.Build;
import android.util.Log;
import androidx.annotation.Nullable;
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
        captureDebugFlag(context);
        return new CapturingAudioOutputProvider(
                new AudioTrackAudioOutputProvider.Builder(context).build());
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

    /** [device ID, app AudioTrack rate, PCM encoding]. Zero means unverified.
     * This describes the app stream, not a claim about the downstream DAC/mixer.
     */
    public static synchronized boolean isPlaying() {
        for (AAudioAudioSink sink : nativeSinks) {
            if (sink.isPlaying() && sink.measuredStream()[1] > 0) return true;
        }
        for (DefaultAudioSink sink : sinks) {
            AudioTrack track = getAudioTrackFromSink(sink);
            if (track != null && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return true;
        }
        return false;
    }

    /**
     * Decoded PCM truth probe: [encoding, sampleRate, channels] of the last
     * Media3 float-tap configure, or zeros when it has not run yet.
     */
    public static synchronized int[] decodedPcmSnapshot() {
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
            if (!sink.isPlayingForTelemetry()) continue;
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

    public static synchronized int[] snapshot() {
        int[] nativeFallback = null;
        for (AAudioAudioSink sink : nativeSinks) {
            int[] measured = sink.measuredStream();
            if (measured[1] == 0) continue;
            nativeFallback = measured;
            if (sink.isPlaying()) return measured;
        }
        AudioTrack fallback = null;
        for (DefaultAudioSink sink : sinks) {
            AudioTrack track = getAudioTrackFromSink(sink);
            if (track == null || track.getState() != AudioTrack.STATE_INITIALIZED) continue;
            fallback = track;
            if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return snapshot(track);
        }
        if (fallback != null) return snapshot(fallback);
        return nativeFallback != null ? nativeFallback : new int[] {0, 0, 0};
    }

    private static int[] snapshot(AudioTrack track) {
        AudioDeviceInfo routed = Build.VERSION.SDK_INT >= 24 ? track.getRoutedDevice() : null;
        return new int[] {routed == null ? 0 : routed.getId(), track.getSampleRate(), track.getAudioFormat()};
    }
}
