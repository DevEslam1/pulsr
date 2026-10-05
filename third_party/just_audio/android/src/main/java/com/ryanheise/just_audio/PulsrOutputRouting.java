package com.ryanheise.just_audio;

import android.media.AudioDeviceInfo;
import android.media.AudioTrack;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.audio.DefaultAudioSink;
import java.lang.reflect.Field;
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
    private static boolean reflectionWarningLogged = false;

    private static Field getAudioTrackField() {
        if (audioTrackField != null) return audioTrackField;
        try {
            Field field = DefaultAudioSink.class.getDeclaredField("audioTrack");
            field.setAccessible(true);
            audioTrackField = field;
            return field;
        } catch (ReflectiveOperationException e) {
            if (!reflectionWarningLogged) {
                android.util.Log.w("PulsrOutputRouting",
                    "Media3 DefaultAudioSink.audioTrack reflection unavailable; telemetry will degrade gracefully", e);
                reflectionWarningLogged = true;
            }
            return null;
        }
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
        try {
            for (ExoPlayer player : players.keySet()) player.setPreferredAudioDevice(device);
            preferred = device;
            return true;
        } catch (RuntimeException failure) { return false; }
    }

    /** [device ID, app AudioTrack rate, PCM encoding]. Zero means unverified.
     * This describes the app stream, not a claim about the downstream DAC/mixer.
     */
    public static synchronized boolean isPlaying() {
        for (AAudioAudioSink sink : nativeSinks) {
            if (sink.isPlaying() && sink.measuredStream()[1] > 0) return true;
        }
        try {
            Field field = getAudioTrackField();
            if (field == null) return false;
            for (DefaultAudioSink sink : sinks) {
                AudioTrack track = (AudioTrack) field.get(sink);
                if (track != null && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return true;
            }
        } catch (ReflectiveOperationException | RuntimeException ignored) {}
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
        try {
            Field field = getAudioTrackField();
            if (field == null) return nativeFallback != null ? nativeFallback : new int[] {0, 0, 0};
            AudioTrack fallback = null;
            for (DefaultAudioSink sink : sinks) {
                AudioTrack track = (AudioTrack) field.get(sink);
                if (track == null || track.getState() != AudioTrack.STATE_INITIALIZED) continue;
                fallback = track;
                if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) return snapshot(track);
            }
            if (fallback != null) return snapshot(fallback);
        } catch (ReflectiveOperationException | RuntimeException unavailable) {
            // Media3 internals may change. Unknown is safer than an invented format.
        }
        return nativeFallback != null ? nativeFallback : new int[] {0, 0, 0};
    }

    private static int[] snapshot(AudioTrack track) {
        AudioDeviceInfo routed = track.getRoutedDevice();
        return new int[] {routed == null ? 0 : routed.getId(), track.getSampleRate(), track.getAudioFormat()};
    }
}
