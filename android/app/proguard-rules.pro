# Jaudiotagger ProGuard Rules
-keep class org.jaudiotagger.** { *; }
-dontwarn org.jaudiotagger.**

# Audio Service ProGuard Rules
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

# Just Audio ProGuard Rules
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.ryanheise.just_audio.**

# OnAudioQuery ProGuard Rules
-keep class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.on_audio_query.**

# SQLite3 and Drift ProGuard Rules
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# Path Provider Rules
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# Android Media & App Rules
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.pulsr.music.** { *; }
