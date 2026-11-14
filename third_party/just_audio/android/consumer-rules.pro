# Keep Media3 DefaultAudioSink/AudioTrackAudioOutput members accessed by
# PulsrOutputRouting fallback reflection when R8 minification runs.
-keepclassmembers class androidx.media3.exoplayer.audio.DefaultAudioSink {
    androidx.media3.exoplayer.audio.AudioOutput audioOutput;
    android.media.AudioTrack audioTrack;
}
-keepclassmembers class androidx.media3.exoplayer.audio.AudioTrackAudioOutput {
    android.media.AudioTrack audioTrack;
    public android.media.AudioTrack getAudioTrack();
}
