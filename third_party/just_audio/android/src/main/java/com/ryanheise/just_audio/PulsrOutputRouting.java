package com.ryanheise.just_audio;

import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;

/** App-owned media routing. Preferences and measured routes are deliberately separate. */
@androidx.media3.common.util.UnstableApi
public final class PulsrOutputRouting {
    private static final Map<ExoPlayer, Boolean> players = new WeakHashMap<>();
    // Use explicit-lifetime sets for sinks: WeakHashMap risks silent GC-collection
    // of active sinks if the renderer holds the only strong reference internally.
    private static final Set<DefaultAudioSink> sinks = new HashSet<>();
    private static final Set<AAudioAudioSink> nativeSinks = new HashSet<>();
    private static AudioDeviceInfo preferred;
    private static Field audioTrackField;
    private static Field audioOutputField;
    private static Method getAudioTrackMethod;
    private static boolean reflectionLookupDone = false;
    private static boolean reflectionWarningLogged = false;

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
            android.util.Log.w("PulsrOutputRouting",
                "Media3 DefaultAudioSink reflection unavailable; output-device telemetry will return [0,0,0].");
            android.util.Log.e("PulsrOutputRouting",
                "TELEMETRY_DEGRADED: DefaultAudioSink fields (audioTrack/audioOutput) lookup failed.");
        }
    }

    private static AudioTrack getAudioTrackFromSink(DefaultAudioSink sink) {
        if (sink == null) return null;
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
                    try {
                        Field f = audioOutput.getClass().getDeclaredField("audioTrack");
                        f.setAccessible(true);
                        Object obj = f.get(audioOutput);
                        if (obj instanceof AudioTrack) return (AudioTrack) obj;
                    } catch (Exception ignored) {}
                }
            } catch (Exception ignored) {}
        }

        return null;
    }

    private PulsrOutputRouting() {}

    public static synchronized void register(ExoPlayer player, boolean aaudio) {
        players.put(player, aaudio);
        player.setPreferredAudioDevice(preferred);
    }

    public static synchronized void unregister(ExoPlayer player) { players.remove(player); }

    public static synchronized void observe(DefaultAudioSink sink) { sinks.add(sink); }

    public static synchronized void unobserve(DefaultAudioSink sink) { sinks.remove(sink); }

    public static synchronized void observe(AAudioAudioSink sink) { nativeSinks.add(sink); }

    public static synchronized void unobserve(AAudioAudioSink sink) { nativeSinks.remove(sink); }

    public static synchronized boolean select(AudioDeviceInfo device) {
        // Best-effort per player: one released/failed player must neither abort
        // the routing of the remaining players nor leave the stored
        // preference disagreeing with the iteration.
        boolean allApplied = true;
        for (ExoPlayer player : players.keySet()) {
            try {
                player.setPreferredAudioDevice(device);
            } catch (RuntimeException failure) {
                allApplied = false;
            }
        }
        preferred = device;
        return allApplied;
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
        AudioDeviceInfo routed = track.getRoutedDevice();
        return new int[] {routed == null ? 0 : routed.getId(), track.getSampleRate(), track.getAudioFormat()};
    }
}
