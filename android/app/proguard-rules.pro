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

# Sentry Crash Reporting
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep class io.sentry.** { *; }
-dontwarn io.sentry.**

# Home Widget
-keep class es.antonborri.home_widget.** { *; }
-dontwarn es.antonborri.home_widget.**

# Kotlin Coroutines
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

# NewPipeExtractor -- present only in the ytm/dev flavors, absent from prod.
# Rhino compiles YouTube's player JS at runtime and resolves classes
# reflectively, so it must not be minified. The extractor reflects into
# nanojson/jsoup on its deserialization paths.
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.** { *; }
-dontwarn org.mozilla.javascript.**
-keep class org.schabi.newpipe.extractor.** { *; }
-dontwarn org.schabi.newpipe.extractor.**
-keep class com.grack.nanojson.** { *; }
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**
# Rhino optionally binds javax.script and java.beans; neither exists on Android.
-dontwarn javax.script.**
-dontwarn java.beans.**
-dontwarn org.mozilla.javascript.tools.**

