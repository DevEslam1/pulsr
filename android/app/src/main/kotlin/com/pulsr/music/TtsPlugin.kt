package com.pulsr.music

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
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
 * * `speak` {text, volume, duckAudio, voiceId?, localeId?} -> Boolean:
 *   QUEUE_FLUSH speech. With `duckAudio` the engine asks the platform for
 *   transient audio focus with ducking, so music keeps playing quietly.
 * * `stop` -> Boolean: stops immediately, abandons focus and drops the queue.
 * * `voices` -> List<Map{id, name, localeCode, quality}>: installed voices.
 * * `isSpeaking` -> Boolean: live speech state.
 *
 * The engine is created lazily on the first `init`, because constructing it
 * binds a system speech service and the plugin is attached during app startup.
 * Resolved voices are cached per (voiceId, localeId) pair so selecting a voice
 * does not enumerate the engine's voice list for every utterance.
 */
class TtsPlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    internal var context: Context? = null
    private var tts: TextToSpeech? = null
    internal var ttsFactory: (Context, TextToSpeech.OnInitListener) -> TextToSpeech = { ctx, listener ->
        TextToSpeech(ctx, listener)
    }
    private var audioManager: AudioManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var state: InitState = InitState.IDLE
    private val pendingInitResults = mutableListOf<Result>()

    /**
     * Incremented on every init attempt and on dispose. Callbacks carrying an
     * older token are ignored, so a late onInit after shutdown cannot resurrect
     * a released engine or double-complete a Result.
     */
    private var generation = 0
    private var disposed = false

    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false
    private var activeUtteranceId: String? = null

    private var voiceCacheKey: String? = null
    private var cachedVoice: Voice? = null
    private var cachedDefaultLocale: Locale? = null

    private val speechAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private val utteranceListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) {
            // Ducking focus must be released when the sentence ends, or the
            // music stays attenuated until the next announcement.
            releaseFocusFor(utteranceId)
        }

        override fun onError(utteranceId: String?) {
            releaseFocusFor(utteranceId)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            releaseFocusFor(utteranceId)
        }
    }

    private enum class InitState { IDLE, INITIALIZING, READY, UNAVAILABLE }

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        context = binding.applicationContext
        audioManager =
            binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        disposed = false
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also { created ->
            created.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        dispose()
        context = null
        audioManager = null
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
        disposed = true
        generation++
        channel?.setMethodCallHandler(null)
        channel = null
        completePending(false)
        val engine = tts
        tts = null
        state = InitState.IDLE
        // stop/shutdown can throw on a half-initialised engine; teardown must
        // never surface that as a crash.
        runCatching { engine?.stop() }
        runCatching { engine?.shutdown() }
        activeUtteranceId = null
        abandonFocusNow()
        voiceCacheKey = null
        cachedVoice = null
        cachedDefaultLocale = null
    }

    private fun initialize(result: Result) {
        if (disposed) {
            result.success(false)
            return
        }
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
        val token = ++generation
        val engine = try {
            ttsFactory(appContext) { code -> handleInit(token, code) }
        } catch (e: Exception) {
            Log.w(TAG, "TextToSpeech constructor failed: ${e.message}")
            // Invalidate the token and complete everyone waiting, including
            // the result just queued.
            generation++
            state = InitState.UNAVAILABLE
            completePending(false)
            return
        }
        tts = engine
        if (state == InitState.UNAVAILABLE) {
            // Defensive: an engine that reported failure before the field was
            // assigned must not stay bound to the speech service.
            runCatching { engine.shutdown() }
            tts = null
        }
    }

    private fun handleInit(token: Int, code: Int) {
        mainHandler.post {
            if (disposed || token != generation) {
                // Late callback from a disposed or superseded engine.
                return@post
            }
            val engine = tts
            if (code == TextToSpeech.SUCCESS && engine != null) {
                state = InitState.READY
                configureEngine(engine)
                completePending(true)
            } else {
                state = InitState.UNAVAILABLE
                runCatching { engine?.shutdown() }
                tts = null
                Log.w(TAG, "TextToSpeech init failed with code $code")
                completePending(false)
            }
        }
    }

    private fun completePending(success: Boolean) {
        val results = pendingInitResults.toList()
        pendingInitResults.clear()
        for (pending in results) {
            runCatching { pending.success(success) }
        }
    }

    private fun configureEngine(engine: TextToSpeech) {
        runCatching {
            engine.setAudioAttributes(speechAttributes)
            engine.setOnUtteranceProgressListener(utteranceListener)
            voiceCacheKey = null
            cachedVoice = null
            cachedDefaultLocale = null
            // Resolve the device locale once at init, never per utterance.
            val deviceLocale = Locale.getDefault()
            if (engine.isLanguageAvailable(deviceLocale) >= TextToSpeech.LANG_AVAILABLE) {
                engine.language = deviceLocale
                cachedDefaultLocale = deviceLocale
            }
        }.onFailure { error ->
            Log.w(TAG, "Speech attribute setup failed: ${error.message}")
        }
    }

    private fun speak(call: MethodCall, result: Result) {
        val engine = tts
        if (disposed || state != InitState.READY || engine == null) {
            result.success(false)
            return
        }
        val text = call.argument<String>("text").orEmpty()
        if (text.isBlank()) {
            result.success(false)
            return
        }
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1f)
        val duckAudio = call.argument<Boolean>("duckAudio") ?: false
        try {
            applyVoice(engine, call.argument<String>("voiceId"), call.argument<String>("localeId"))
            if (duckAudio) {
                requestDuckFocus()
            } else {
                // A previous announcement may still hold ducking focus even
                // though this one must not duck.
                abandonFocusNow()
            }
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
            }
            val utteranceId = "announce-${UUID.randomUUID()}"
            activeUtteranceId = utteranceId
            val queued = engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            if (queued != TextToSpeech.SUCCESS) {
                activeUtteranceId = null
                abandonFocusNow()
            }
            result.success(queued == TextToSpeech.SUCCESS)
        } catch (e: Exception) {
            // Never leave the Dart future pending because the platform threw.
            Log.w(TAG, "Speak failed: ${e.message}")
            activeUtteranceId = null
            abandonFocusNow()
            runCatching { result.success(false) }
        }
    }

    private fun stopSpeech(): Boolean {
        activeUtteranceId = null
        abandonFocusNow()
        val engine = tts ?: return false
        return runCatching { engine.stop() == TextToSpeech.SUCCESS }.getOrDefault(false)
    }

    private fun isSpeaking(): Boolean = runCatching { tts?.isSpeaking ?: false }.getOrDefault(false)

    /**
     * Applies the requested voice, resolving the engine voice list at most once
     * per (voiceId, localeId) pair.
     *
     * A failed resolution is cached too, so an uninstalled voice id cannot make
     * every utterance re-enumerate `engine.voices`.
     */
    private fun applyVoice(engine: TextToSpeech, voiceId: String?, localeId: String?) {
        val key = "${voiceId.orEmpty()}|${localeId.orEmpty()}"
        if (key == voiceCacheKey) {
            val cached = cachedVoice
            if (cached != null) {
                runCatching { engine.voice = cached }
            }
            return
        }
        runCatching {
            val hasVoiceChoice = !voiceId.isNullOrEmpty()
            val hasLocaleChoice = !localeId.isNullOrEmpty()
            if (!hasVoiceChoice && !hasLocaleChoice) {
                // configureEngine() already selected the device locale. Some
                // OEM engines throw from setVoice(null), so touching the voice
                // here silenced every announcement on those devices.
                cachedVoice = null
                voiceCacheKey = key
                return
            }
            val requestedVoice = if (hasVoiceChoice) {
                // Some engines expose a null entry in the voice set; use an
                // explicit null-safe access so the platform type cannot
                // reintroduce the NPE.
                engine.voices?.firstOrNull { voice -> voice?.name == voiceId }
            } else {
                null
            }
            if (requestedVoice != null) {
                val applied = runCatching { engine.voice = requestedVoice }.isSuccess
                cachedVoice = if (applied) requestedVoice else null
                voiceCacheKey = key
                if (!applied) {
                    Log.w(
                        TAG,
                        "Voice '$voiceId' was rejected by the engine; using the default voice"
                    )
                }
                return
            }
            if (hasVoiceChoice) {
                Log.w(TAG, "Voice $voiceId is not installed; using the default voice")
            }
            val requestedLocale = if (hasLocaleChoice) {
                Locale.forLanguageTag(localeId!!)
            } else {
                null
            }
            if (requestedLocale != null &&
                engine.isLanguageAvailable(requestedLocale) >= TextToSpeech.LANG_AVAILABLE
            ) {
                val applied = runCatching { engine.language = requestedLocale }.isSuccess
                cachedVoice = null
                voiceCacheKey = key
                if (!applied) {
                    Log.w(
                        TAG,
                        "Locale '$localeId' was rejected by the engine; using the default locale"
                    )
                }
                return
            }
            // Explicit choice unavailable: fall back to the init-time locale
            // without calling setVoice(null).
            cachedVoice = null
            voiceCacheKey = key
            val defaultLocale = cachedDefaultLocale
            if (defaultLocale != null) {
                runCatching { engine.language = defaultLocale }
            }
        }.onFailure { error ->
            Log.w(TAG, "Voice selection failed for '$voiceId'", error)
        }
    }

    private fun requestDuckFocus() {
        val manager = audioManager ?: return
        if (focusHeld) return
        val request = focusRequest ?: AudioFocusRequest.Builder(
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
        )
            .setAudioAttributes(speechAttributes)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener { }
            .build()
            .also { focusRequest = it }
        val granted = runCatching { manager.requestAudioFocus(request) }
            .getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocusNow() {
        val manager = audioManager
        val request = focusRequest
        if (focusHeld && manager != null && request != null) {
            runCatching { manager.abandonAudioFocusRequest(request) }
        }
        focusHeld = false
    }

    private fun releaseFocusFor(utteranceId: String?) {
        mainHandler.post {
            // A done/error callback from the previous sentence must not release
            // the ducking focus a newer utterance already acquired.
            if (activeUtteranceId != null && activeUtteranceId != utteranceId) {
                return@post
            }
            activeUtteranceId = null
            abandonFocusNow()
        }
    }

    private fun voices(): List<Map<String, Any>> {
        if (disposed || state != InitState.READY) return emptyList()
        val engine = tts ?: return emptyList()
        val installed = runCatching { engine.voices }.getOrNull() ?: return emptyList()
        return installed.mapNotNull { voice -> voice?.toMap() }
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
