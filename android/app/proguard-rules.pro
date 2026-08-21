# Jaudiotagger ProGuard Rules
-keep class org.jaudiotagger.** { *; }
-dontwarn org.jaudiotagger.**

# Audio Service ProGuard Rules
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

# Media and App Rules
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**
-keep class com.pulsr.music.** { *; }
