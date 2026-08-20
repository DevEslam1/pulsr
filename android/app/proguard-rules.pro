# Jaudiotagger ProGuard Rules
-keep class org.jaudiotagger.** { *; }
-dontwarn org.jaudiotagger.**

# Audio Service ProGuard Rules
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

# Flutter and Native Media
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**
-keep class com.pulsr.music.** { *; }
