package com.pulsr.music

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Locale
import java.util.UUID

/**
 * Speaks track announcements through the platform [TextToSpeech] engine.
 *
 * Channel: `com.pulsr.music/tts`.
 *
 * * `init` -> Boolean: whether the engine is ready. Safe to call repeatedly.
 * * `speak` {text, volume, voiceId?, localeId?} -> Boolean: QUEUE_FLUSH speech.
 * * `stop` -> Boolean: stops immediately and drops queued utterances.
 * * `voices` -> List<Map{id, name, localeCode, quality}>: installed voices.
 * * `isSpeaking` -> Boolean: live speech state.
 *
 * The engine is created lazily on the first `init`, because constructing it
 * binds a system speech service and the plugin is attached during app startup.
 */
class TtsPlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var tts: TextToSpeech? = null
    private var state: InitState = InitState.IDLE
    private val pendingInitResults = mutableListOf<Result>()

    private enum class InitState { IDLE, INITIALIZING, READY, UNAVAILABLE }

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also { created ->
            created.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        dispose()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> initialize(result)
            "speak" -> speak(call, result)
            "stop" -> result.success(stopSpeech())
            "voices" -> result.success(voices())
            "isSpeaking" -> result.success(isSpeaking())
            else -> result.notImplemented()
        }
    }

    /** Stops speech and releases the native engine. Safe to call more than once. */
    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        val pending = pendingInitResults.toList()
        pendingInitResults.clear()
        for (result in pending) {
            result.success(false)
        }
        tts?.stop()
        tts?.shutdown()
        tts = null
        state = InitState.IDLE
    }

    private fun initialize(result: Result) {
        when (state) {
            InitState.READY -> {
                result.success(true)
                return
            }
            InitState.UNAVAILABLE -> {
                result.success(false)
                return
            }
            InitState.INITIALIZING -> {
                pendingInitResults.add(result)
                return
            }
            InitState.IDLE -> Unit
        }
        val appContext = context
        if (appContext == null) {
            state = InitState.UNAVAILABLE
            result.success(false)
            return
        }
        state = InitState.INITIALIZING
        pendingInitResults.add(result)
        // onInit is posted to the main looper, so the assignment below always
        // lands before handleInit runs.
        val engine = TextToSpeech(appContext) { code -> handleInit(code) }
        tts = engine
        if (state == InitState.UNAVAILABLE) {
            // Defensive: an engine that reported failure before the field was
            // assigned must not stay bound to the speech service.
            engine.shutdown()
            tts = null
        }
    }

    private fun handleInit(code: Int) {
        val ready = code == TextToSpeech.SUCCESS
        if (ready) {
            state = InitState.READY
            applySpeechAttributes()
        } else {
            state = InitState.UNAVAILABLE
            tts?.shutdown()
            tts = null
            Log.w(TAG, "TextToSpeech init failed with code $code")
        }
        val results = pendingInitResults.toList()
        pendingInitResults.clear()
        for (pending in results) {
            pending.success(ready)
        }
    }

    private fun applySpeechAttributes() {
        val engine = tts ?: return
        runCatching {
            engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            val deviceLocale = Locale.getDefault()
            if (engine.isLanguageAvailable(deviceLocale) >= TextToSpeech.LANG_AVAILABLE) {
                engine.language = deviceLocale
            }
        }.onFailure { error ->
            Log.w(TAG, "Speech attribute setup failed: ${error.message}")
        }
    }

    private fun speak(call: MethodCall, result: Result) {
        val engine = tts
        if (state != InitState.READY || engine == null) {
            result.success(false)
            return
        }
        val text = call.argument<String>("text").orEmpty()
        if (text.isBlank()) {
            result.success(false)
            return
        }
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1f)
        applyVoice(engine, call.argument<String>("voiceId"), call.argument<String>("localeId"))
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        }
        val utteranceId = "announce-${UUID.randomUUID()}"
        val queued = engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        result.success(queued == TextToSpeech.SUCCESS)
    }

    private fun stopSpeech(): Boolean {
        val engine = tts
        if (engine == null) return false
        return engine.stop() == TextToSpeech.SUCCESS
    }

    private fun isSpeaking(): Boolean = tts?.isSpeaking ?: false

    private fun applyVoice(engine: TextToSpeech, voiceId: String?, localeId: String?) {
        runCatching {
            if (!voiceId.isNullOrEmpty()) {
                val match = engine.voices?.firstOrNull { voice -> voice.name == voiceId }
                if (match != null) {
                    engine.voice = match
                    return
                }
                Log.w(TAG, "Voice $voiceId is not installed; keeping the current voice")
            }
            if (!localeId.isNullOrEmpty()) {
                val locale = Locale.forLanguageTag(localeId)
                if (engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) {
                    engine.voice = null
                    engine.language = locale
                }
            }
        }.onFailure { error ->
            Log.w(TAG, "Voice selection failed: ${error.message}")
        }
    }

    private fun voices(): List<Map<String, Any>> {
        if (state != InitState.READY) return emptyList()
        val engine = tts ?: return emptyList()
        val installed = runCatching { engine.voices }.getOrNull() ?: return emptyList()
        return installed.mapNotNull { voice -> voice.toMap() }
    }

    private fun Voice.toMap(): Map<String, Any>? {
        val voiceName: String = name ?: return null
        if (voiceName.isEmpty()) return null
        return mapOf(
            "id" to voiceName,
            "name" to voiceName,
            "localeCode" to (locale?.toLanguageTag() ?: ""),
            "quality" to qualityLabel(quality)
        )
    }

    private fun qualityLabel(quality: Int): String = when (quality) {
        Voice.QUALITY_VERY_LOW -> "veryLow"
        Voice.QUALITY_LOW -> "low"
        Voice.QUALITY_NORMAL -> "normal"
        Voice.QUALITY_HIGH -> "high"
        Voice.QUALITY_VERY_HIGH -> "veryHigh"
        else -> "unknown"
    }

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/tts"
        private const val TAG = "TtsPlugin"

        /**
         * Registers the plugin on [engine].
         *
         * Must run on the platform main thread; the announcements wiring calls
         * it once from the engine-scoped plugin setup, never per Activity, so a
         * single speech engine serves the whole app process.
         */
        fun register(engine: FlutterEngine): TtsPlugin {
            val plugin = TtsPlugin()
            engine.plugins.add(plugin)
            return plugin
        }
    }
}
