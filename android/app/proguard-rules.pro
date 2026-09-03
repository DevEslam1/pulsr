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

# SQLite3, Drift and SQLCipher ProGuard Rules
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**
-keep class sqlite3.** { *; }
-dontwarn sqlite3.**

# Path Provider Rules
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# Android Media & App Rules
-keep class androidx.media.** { *; }
-dontwarn androidx.media.**
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep all Pulsr application classes, companions, and methods
-keep class com.pulsr.music.** { *; }
-keepclassmembers class com.pulsr.music.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
# Keep the JNI bridge classes
-keep class com.pulsr.music.NativeAudioBridge { *; }
-keep class com.pulsr.music.AudioEffectsPlugin { *; }
# Keep DSP param classes used by JNI
-keep class com.pulsr.music.dsp.** { *; }

# Android WebView & JavascriptInterface (PoToken WebView & BotGuard)
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class android.webkit.** { *; }
-dontwarn android.webkit.**

# Sentry Crash Reporting
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Home Widget
-keep class es.antonborri.home_widget.** { *; }
-dontwarn es.antonborri.home_widget.**

# Kotlin Coroutines & Reflect
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Firebase & Google Play Services Rules
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Google Protobuf
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Rhino & Scripting Engine Rules
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn org.mozilla.**
-keep class org.mozilla.** { *; }
-dontwarn org.mozilla.javascript.**
-keep class org.mozilla.javascript.** { *; }
