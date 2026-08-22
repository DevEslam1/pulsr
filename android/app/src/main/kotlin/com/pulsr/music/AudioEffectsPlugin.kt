package com.pulsr.music

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

class AudioEffectsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private var context: Context? = null

    private var virtualizer: Virtualizer? = null
    private var dynamicsProcessing: DynamicsProcessing? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null

    private var isVirtualizerEnabled = false
    private var virtualizerStrength: Short = 0

    private var volumeBoostMilliBels: Int = 0
    private var bassBoostStrength: Short = 0

    private var isDynamicsEnabled = false
    private var currentDynamicsPreset = "off"
    private var currentAudioSessionId = 0

    companion object {
        const val CHANNEL_NAME = "com.pulsr.music/audio_effects"
        private var cachedSupportedEffects: Array<AudioEffect.Descriptor>? = null

        fun registerWith(flutterEngine: FlutterEngine, context: Context): AudioEffectsPlugin {
            val plugin = AudioEffectsPlugin()
            plugin.context = context
            plugin.methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            plugin.methodChannel.setMethodCallHandler(plugin)
            return plugin
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseEffects()
        methodChannel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "setAudioSessionId" -> {
                    val sessionId = call.argument<Int>("audioSessionId") ?: 0
                    currentAudioSessionId = sessionId
                    recreateEffects()
                    result.success(true)
                }

                "setVirtualizerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setVirtualizerState(enabled)
                    result.success(true)
                }

                "setVirtualizerStrength" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    setVirtualizerStrengthValue(strength)
                    result.success(true)
                }

                "setVolumeBoost" -> {
                    val milliBels = call.argument<Int>("milliBels") ?: 0
                    setVolumeBoost(milliBels)
                    result.success(true)
                }

                "isVolumeBoostSupported" -> {
                    val supported = isEffectTypeSupported(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER)
                    result.success(supported)
                }

                "setBassBoost" -> {
                    val strength = call.argument<Int>("strength") ?: 0
                    setBassBoostStrengthValue(strength)
                    result.success(true)
                }

                "isBassBoostSupported" -> {
                    val supported = isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST)
                    result.success(supported)
                }

                "setDynamicsPreset" -> {
                    val preset = call.argument<String>("preset") ?: "off"
                    val enabled = call.argument<Boolean>("enabled") ?: (preset != "off")
                    setDynamicsPresetState(preset, enabled)
                    result.success(true)
                }

                "isDynamicsSupported" -> {
                    val supported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING)
                    } else {
                        false
                    }
                    result.success(supported)
                }

                "isVirtualizerSupported" -> {
                    val supported = isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER)
                    result.success(supported)
                }

                "getSpatializerState" -> {
                    val spatialInfo = getSpatializerInfo()
                    result.success(spatialInfo)
                }

                "setSpatializerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setSpatializerState(enabled)
                    result.success(true)
                }

                "getCapabilities" -> {
                    val caps = mapOf(
                        "hasEqualizer" to true,
                        "hasAudioEffects" to true,
                        "hasTagEditor" to true,
                        "hasRingtoneManager" to true,
                        "hasVisualizer" to true,
                        "hasAppWidget" to true,
                        "isVolumeBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER),
                        "isBassBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST),
                        "isDynamicsSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING)),
                        "isVirtualizerSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER)
                    )
                    result.success(caps)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_EFFECT_ERROR", e.message, null)
        }
    }

    private fun ensureVirtualizer() {
        if (virtualizer == null && currentAudioSessionId != 0) {
            try {
                virtualizer = Virtualizer(0, currentAudioSessionId)
                if (virtualizer?.strengthSupported == true && virtualizerStrength > 0) {
                    virtualizer?.setStrength(virtualizerStrength)
                }
                virtualizer?.enabled = isVirtualizerEnabled
            } catch (e: Exception) {
                android.util.Log.w("AudioEffectsPlugin", "Virtualizer initialization failed: ${e.message}")
            }
        }
    }

    private fun setVirtualizerState(enabled: Boolean) {
        isVirtualizerEnabled = enabled
        ensureVirtualizer()
        try {
            virtualizer?.enabled = enabled
        } catch (e: Exception) {
            android.util.Log.w("AudioEffectsPlugin", "Failed to set virtualizer enabled: ${e.message}")
        }
    }

    private fun setVirtualizerStrengthValue(strength: Int) {
        val clamped = strength.coerceIn(0, 1000).toShort()
        virtualizerStrength = clamped
        ensureVirtualizer()
        try {
            if (virtualizer?.strengthSupported == true) {
                virtualizer?.setStrength(clamped)
            }
        } catch (e: Exception) {
            android.util.Log.w("AudioEffectsPlugin", "Failed to set virtualizer strength: ${e.message}")
        }
    }

    private fun ensureVolumeBoost() {
        if (loudnessEnhancer == null && currentAudioSessionId != 0) {
            try {
                loudnessEnhancer = LoudnessEnhancer(currentAudioSessionId)
                if (volumeBoostMilliBels > 0) {
                    loudnessEnhancer?.setTargetGain(volumeBoostMilliBels)
                }
                loudnessEnhancer?.enabled = volumeBoostMilliBels > 0
            } catch (e: Exception) {
                android.util.Log.w("AudioEffectsPlugin", "LoudnessEnhancer initialization failed: ${e.message}")
            }
        }
    }

    private fun setVolumeBoost(milliBels: Int) {
        volumeBoostMilliBels = milliBels.coerceIn(0, 1000)
        ensureVolumeBoost()
        try {
            loudnessEnhancer?.setTargetGain(volumeBoostMilliBels)
            loudnessEnhancer?.enabled = volumeBoostMilliBels > 0
        } catch (e: Exception) {
            android.util.Log.w("AudioEffectsPlugin", "Failed to set volume boost: ${e.message}")
        }
    }

    private fun ensureBassBoost() {
        if (bassBoost == null && currentAudioSessionId != 0) {
            try {
                bassBoost = BassBoost(0, currentAudioSessionId)
                if (bassBoost?.strengthSupported == true && bassBoostStrength > 0) {
                    bassBoost?.setStrength(bassBoostStrength)
                }
                bassBoost?.enabled = bassBoostStrength > 0
            } catch (e: Exception) {
                android.util.Log.w("AudioEffectsPlugin", "BassBoost initialization failed: ${e.message}")
            }
        }
    }

    private fun setBassBoostStrengthValue(strength: Int) {
        val clamped = strength.coerceIn(0, 1000).toShort()
        bassBoostStrength = clamped
        ensureBassBoost()
        try {
            if (bassBoost?.strengthSupported == true) {
                bassBoost?.setStrength(clamped)
            }
            bassBoost?.enabled = clamped > 0
        } catch (e: Exception) {
            android.util.Log.w("AudioEffectsPlugin", "Failed to set bass boost: ${e.message}")
        }
    }

    private fun setDynamicsPresetState(preset: String, enabled: Boolean) {
        currentDynamicsPreset = preset
        isDynamicsEnabled = enabled

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return
        }

        if (!enabled || preset == "off") {
            try {
                dynamicsProcessing?.enabled = false
            } catch (_: Exception) {}
            return
        }

        try {
            applyDynamicsPreset(preset)
        } catch (e: Exception) {
            android.util.Log.w("AudioEffectsPlugin", "DynamicsProcessing configuration failed: ${e.message}")
        }
    }

    private fun applyDynamicsPreset(preset: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        if (currentAudioSessionId == 0) return

        try {
            dynamicsProcessing?.release()
        } catch (_: Exception) {}
        dynamicsProcessing = null

        // Setup 3-band Multiband Compressor (Low, Mid, High)
        val channelCount = 2 // Stereo
        val mbcBandCount = 3

        val builder = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            channelCount,
            false, // preEq
            0,
            true,  // mbc
            mbcBandCount,
            false, // postEq
            0,
            true   // limiter
        )
        builder.setPreferredFrameDuration(10f)

        val config = builder.build()

        // Configure bands & limiter based on preset
        for (ch in 0 until channelCount) {
            val mbc = config.getMbcByChannelIndex(ch)
            val limiter = config.getLimiterByChannelIndex(ch)

            when (preset) {
                "studioPunch" -> {
                    // Low: Punchy kick & bass
                    val band0 = mbc.getBand(0)
                    band0.cutoffFrequency = 200f
                    band0.attackTime = 15f
                    band0.releaseTime = 90f
                    band0.ratio = 3.5f
                    band0.threshold = -18f
                    band0.kneeWidth = 4f
                    band0.postGain = 2.0f
                    band0.isEnabled = true

                    // Mid: Vocal & snare clarity
                    val band1 = mbc.getBand(1)
                    band1.cutoffFrequency = 3500f
                    band1.attackTime = 20f
                    band1.releaseTime = 120f
                    band1.ratio = 2.5f
                    band1.threshold = -16f
                    band1.kneeWidth = 6f
                    band1.postGain = 1.0f
                    band1.isEnabled = true

                    // High: Air & cymbals
                    val band2 = mbc.getBand(2)
                    band2.cutoffFrequency = 20000f
                    band2.attackTime = 10f
                    band2.releaseTime = 80f
                    band2.ratio = 2.0f
                    band2.threshold = -14f
                    band2.kneeWidth = 6f
                    band2.postGain = 1.5f
                    band2.isEnabled = true

                    limiter.isEnabled = true
                    limiter.attackTime = 2f
                    limiter.releaseTime = 60f
                    limiter.ratio = 10f
                    limiter.threshold = -1.0f
                    limiter.postGain = 0.5f
                }

                "warmAnalog" -> {
                    // Warm low-mids, smooth gentle compression
                    val band0 = mbc.getBand(0)
                    band0.cutoffFrequency = 300f
                    band0.attackTime = 40f
                    band0.releaseTime = 200f
                    band0.ratio = 2.0f
                    band0.threshold = -20f
                    band0.kneeWidth = 10f
                    band0.postGain = 2.5f
                    band0.isEnabled = true

                    val band1 = mbc.getBand(1)
                    band1.cutoffFrequency = 4000f
                    band1.attackTime = 35f
                    band1.releaseTime = 180f
                    band1.ratio = 1.8f
                    band1.threshold = -18f
                    band1.kneeWidth = 8f
                    band1.postGain = 1.0f
                    band1.isEnabled = true

                    val band2 = mbc.getBand(2)
                    band2.cutoffFrequency = 20000f
                    band2.attackTime = 25f
                    band2.releaseTime = 150f
                    band2.ratio = 1.5f
                    band2.threshold = -16f
                    band2.kneeWidth = 8f
                    band2.postGain = 0.0f
                    band2.isEnabled = true

                    limiter.isEnabled = true
                    limiter.attackTime = 5f
                    limiter.releaseTime = 100f
                    limiter.ratio = 6f
                    limiter.threshold = -1.5f
                    limiter.postGain = 0.0f
                }

                "vocalFocus" -> {
                    // Vocal presence & de-essing
                    val band0 = mbc.getBand(0)
                    band0.cutoffFrequency = 250f
                    band0.attackTime = 30f
                    band0.releaseTime = 120f
                    band0.ratio = 2.0f
                    band0.threshold = -15f
                    band0.kneeWidth = 6f
                    band0.postGain = 0.0f
                    band0.isEnabled = true

                    val band1 = mbc.getBand(1)
                    band1.cutoffFrequency = 4500f
                    band1.attackTime = 15f
                    band1.releaseTime = 80f
                    band1.ratio = 3.0f
                    band1.threshold = -22f
                    band1.kneeWidth = 4f
                    band1.postGain = 3.0f
                    band1.isEnabled = true

                    val band2 = mbc.getBand(2)
                    band2.cutoffFrequency = 20000f
                    band2.attackTime = 8f
                    band2.releaseTime = 60f
                    band2.ratio = 3.5f
                    band2.threshold = -18f
                    band2.kneeWidth = 4f
                    band2.postGain = 0.5f
                    band2.isEnabled = true

                    limiter.isEnabled = true
                    limiter.attackTime = 2f
                    limiter.releaseTime = 50f
                    limiter.ratio = 8f
                    limiter.threshold = -1.0f
                    limiter.postGain = 0.0f
                }

                "nightLeveller" -> {
                    // Smooth wide dynamics for quiet environments
                    val band0 = mbc.getBand(0)
                    band0.cutoffFrequency = 200f
                    band0.attackTime = 20f
                    band0.releaseTime = 150f
                    band0.ratio = 4.0f
                    band0.threshold = -24f
                    band0.kneeWidth = 8f
                    band0.postGain = 1.0f
                    band0.isEnabled = true

                    val band1 = mbc.getBand(1)
                    band1.cutoffFrequency = 3500f
                    band1.attackTime = 20f
                    band1.releaseTime = 150f
                    band1.ratio = 4.0f
                    band1.threshold = -24f
                    band1.kneeWidth = 8f
                    band1.postGain = 1.0f
                    band1.isEnabled = true

                    val band2 = mbc.getBand(2)
                    band2.cutoffFrequency = 20000f
                    band2.attackTime = 15f
                    band2.releaseTime = 120f
                    band2.ratio = 4.0f
                    band2.threshold = -22f
                    band2.kneeWidth = 8f
                    band2.postGain = 1.0f
                    band2.isEnabled = true

                    limiter.isEnabled = true
                    limiter.attackTime = 1f
                    limiter.releaseTime = 150f
                    limiter.ratio = 12f
                    limiter.threshold = -3.0f
                    limiter.postGain = 0.0f
                }

                "bassTightener" -> {
                    // Fast attack on sub frequencies, unmuddy low end
                    val band0 = mbc.getBand(0)
                    band0.cutoffFrequency = 160f
                    band0.attackTime = 8f
                    band0.releaseTime = 60f
                    band0.ratio = 5.0f
                    band0.threshold = -20f
                    band0.kneeWidth = 4f
                    band0.postGain = 2.5f
                    band0.isEnabled = true

                    val band1 = mbc.getBand(1)
                    band1.cutoffFrequency = 3500f
                    band1.attackTime = 25f
                    band1.releaseTime = 100f
                    band1.ratio = 1.5f
                    band1.threshold = -15f
                    band1.kneeWidth = 6f
                    band1.postGain = 0.5f
                    band1.isEnabled = true

                    val band2 = mbc.getBand(2)
                    band2.cutoffFrequency = 20000f
                    band2.attackTime = 20f
                    band2.releaseTime = 90f
                    band2.ratio = 1.5f
                    band2.threshold = -15f
                    band2.kneeWidth = 6f
                    band2.postGain = 0.5f
                    band2.isEnabled = true

                    limiter.isEnabled = true
                    limiter.attackTime = 2f
                    limiter.releaseTime = 50f
                    limiter.ratio = 8f
                    limiter.threshold = -1.0f
                    limiter.postGain = 0.5f
                }

                else -> return
            }
        }

        dynamicsProcessing = DynamicsProcessing(0, currentAudioSessionId, config)
        dynamicsProcessing?.enabled = true
    }

    private fun getSpatializerInfo(): Map<String, Any> {
        val result = mutableMapOf<String, Any>(
            "isSupported" to false,
            "isEnabled" to false,
            "isHeadTrackerAvailable" to false
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2) { // Android 12L / API 32+ (Spatializer class)
            try {
                val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    val spatializer = audioManager.spatializer
                    result["isSupported"] = spatializer.isAvailable
                    result["isEnabled"] = spatializer.isEnabled
                    result["isHeadTrackerAvailable"] = spatializer.isHeadTrackerAvailable
                }
            } catch (e: Exception) {
                android.util.Log.w("AudioEffectsPlugin", "Spatializer query error: ${e.message}")
            }
        }

        return result
    }

    private fun setSpatializerState(enabled: Boolean) {
        // Public API compliant: engage hardware 3D surround sound via Virtualizer
        setVirtualizerState(enabled)
        if (enabled && virtualizerStrength <= 0) {
            setVirtualizerStrengthValue(800)
        }
    }

    private fun recreateEffects() {
        // Always release — stale instances are bound to the dead session
        try { virtualizer?.release() } catch (_: Exception) {}
        try { loudnessEnhancer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        virtualizer = null
        loudnessEnhancer = null
        bassBoost = null

        if (isVirtualizerEnabled || virtualizerStrength > 0) {
            setVirtualizerState(isVirtualizerEnabled)
            setVirtualizerStrengthValue(virtualizerStrength.toInt())
        }

        if (volumeBoostMilliBels > 0) {
            setVolumeBoost(volumeBoostMilliBels)
        }

        if (bassBoostStrength > 0) {
            setBassBoostStrengthValue(bassBoostStrength.toInt())
        }

        if (isDynamicsEnabled && currentDynamicsPreset != "off") {
            setDynamicsPresetState(currentDynamicsPreset, isDynamicsEnabled)
        }
    }

    fun releaseEffects() {
        try {
            virtualizer?.enabled = false
            virtualizer?.release()
        } catch (_: Exception) {}
        virtualizer = null

        try {
            loudnessEnhancer?.enabled = false
            loudnessEnhancer?.release()
        } catch (_: Exception) {}
        loudnessEnhancer = null

        try {
            bassBoost?.enabled = false
            bassBoost?.release()
        } catch (_: Exception) {}
        bassBoost = null

        try {
            dynamicsProcessing?.enabled = false
            dynamicsProcessing?.release()
        } catch (_: Exception) {}
        dynamicsProcessing = null
    }

    private fun isEffectTypeSupported(effectType: UUID): Boolean {
        return try {
            val effects = cachedSupportedEffects ?: AudioEffect.queryEffects()?.also {
                cachedSupportedEffects = it
            } ?: return false
            effects.any { it.type == effectType }
        } catch (_: Exception) {
            false
        }
    }
}
