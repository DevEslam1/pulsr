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

# Preserve the measured app AudioTrack field used by the output diagnostics.
-keepclassmembers class androidx.media3.exoplayer.audio.DefaultAudioSink { android.media.AudioTrack audioTrack; }

# Play Core (Deferred Components) - suppress warnings for unbundled optional classes
-dontwarn com.google.android.play.core.**


# Permission Handler ProGuard Rules
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Flutter Secure Storage ProGuard Rules
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# Flutter InAppWebView ProGuard Rules
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**

# Shared Preferences ProGuard Rules
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# shared_preferences_android 2.5.0+ uses Pigeon JNI bindings that look up Kotlin
# runtime classes by hardcoded name. R8 renaming them breaks every prefs call in
# release builds (NoSuchMethodError), causing lost onboarding/settings state.
# See flutter/flutter#194649.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }

# Additional Flutter Plugins
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**
-keep class dev.fluttercommunity.plus.** { *; }
-dontwarn dev.fluttercommunity.plus.**
-keep class io.flutter.plugins.videoplayer.** { *; }
-dontwarn io.flutter.plugins.videoplayer.**
-keep class io.material.plugins.dynamic_color.** { *; }
-dontwarn io.material.plugins.dynamic_color.**
