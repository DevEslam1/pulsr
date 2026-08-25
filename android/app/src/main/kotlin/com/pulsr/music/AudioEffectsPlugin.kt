package com.pulsr.music

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

data class MbcBandConfig(
    val cutoffFrequency: Float,
    val attackTime: Float,
    val releaseTime: Float,
    val ratio: Float,
    val threshold: Float,
    val kneeWidth: Float,
    val postGain: Float
)

data class LimiterConfig(
    val attackTime: Float,
    val releaseTime: Float,
    val ratio: Float,
    val threshold: Float,
    val postGain: Float
)

data class DynamicsPresetConfig(
    val name: String,
    val label: String,
    val description: String,
    val bands: List<MbcBandConfig>,
    val limiter: LimiterConfig
)

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

    // Graphic EQ state. The EQ is a 10-band DynamicsProcessing postEq bound to the
    // same session as the dynamics compressor, so a single engine owns both.
    private var isEqEnabled = false
    private var eqBandCount = DEFAULT_EQ_FREQS.size
    private var eqCenterFreqs = DEFAULT_EQ_FREQS.copyOf()
    private var eqBandGains = DoubleArray(DEFAULT_EQ_FREQS.size)
    private var eqPreampDb = 0.0

    companion object {
        const val TAG = "AudioEffectsPlugin"
        const val CHANNEL_NAME = "com.pulsr.music/audio_effects"
        private const val CHANNEL_COUNT = 2 // Stereo
        private const val MBC_BAND_COUNT = 3

        // ISO standard octave centers for a 10-band graphic equalizer.
        private val DEFAULT_EQ_FREQS = doubleArrayOf(
            32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
        )
        private var cachedSupportedEffects: Array<AudioEffect.Descriptor>? = null

        val DYNAMICS_PRESETS: Map<String, DynamicsPresetConfig> = mapOf(
            "studioPunch" to DynamicsPresetConfig(
                name = "studioPunch",
                label = "Studio Punch",
                description = "Modern punchy dynamics with transient snap & limiting",
                bands = listOf(
                    MbcBandConfig(cutoffFrequency = 200f, attackTime = 15f, releaseTime = 90f, ratio = 3.5f, threshold = -18f, kneeWidth = 4f, postGain = 2.0f),
                    MbcBandConfig(cutoffFrequency = 3500f, attackTime = 20f, releaseTime = 120f, ratio = 2.5f, threshold = -16f, kneeWidth = 6f, postGain = 1.0f),
                    MbcBandConfig(cutoffFrequency = 20000f, attackTime = 10f, releaseTime = 80f, ratio = 2.0f, threshold = -14f, kneeWidth = 6f, postGain = 1.5f)
                ),
                limiter = LimiterConfig(attackTime = 2f, releaseTime = 60f, ratio = 10f, threshold = -1.0f, postGain = 0.5f)
            ),
            "warmAnalog" to DynamicsPresetConfig(
                name = "warmAnalog",
                label = "Warm Analog",
                description = "Gentle tube-style warmth with rich low-mid presence",
                bands = listOf(
                    MbcBandConfig(cutoffFrequency = 300f, attackTime = 40f, releaseTime = 200f, ratio = 2.0f, threshold = -20f, kneeWidth = 10f, postGain = 2.5f),
                    MbcBandConfig(cutoffFrequency = 4000f, attackTime = 35f, releaseTime = 180f, ratio = 1.8f, threshold = -18f, kneeWidth = 8f, postGain = 1.0f),
                    MbcBandConfig(cutoffFrequency = 20000f, attackTime = 25f, releaseTime = 150f, ratio = 1.5f, threshold = -16f, kneeWidth = 8f, postGain = 0.0f)
                ),
                limiter = LimiterConfig(attackTime = 5f, releaseTime = 100f, ratio = 6f, threshold = -1.5f, postGain = 0.0f)
            ),
            "vocalFocus" to DynamicsPresetConfig(
                name = "vocalFocus",
                label = "Vocal Focus",
                description = "Crisp vocal presence with vocal intelligibility boost",
                bands = listOf(
                    MbcBandConfig(cutoffFrequency = 250f, attackTime = 30f, releaseTime = 120f, ratio = 2.0f, threshold = -15f, kneeWidth = 6f, postGain = 0.0f),
                    MbcBandConfig(cutoffFrequency = 4500f, attackTime = 15f, releaseTime = 80f, ratio = 3.0f, threshold = -22f, kneeWidth = 4f, postGain = 3.0f),
                    MbcBandConfig(cutoffFrequency = 20000f, attackTime = 8f, releaseTime = 60f, ratio = 3.5f, threshold = -18f, kneeWidth = 4f, postGain = 0.5f)
                ),
                limiter = LimiterConfig(attackTime = 2f, releaseTime = 50f, ratio = 8f, threshold = -1.0f, postGain = 0.0f)
            ),
            "nightLeveller" to DynamicsPresetConfig(
                name = "nightLeveller",
                label = "Night Leveller",
                description = "Smooths volume peaks for comfortable quiet listening",
                bands = listOf(
                    MbcBandConfig(cutoffFrequency = 200f, attackTime = 20f, releaseTime = 150f, ratio = 4.0f, threshold = -24f, kneeWidth = 8f, postGain = 1.0f),
                    MbcBandConfig(cutoffFrequency = 3500f, attackTime = 20f, releaseTime = 150f, ratio = 4.0f, threshold = -24f, kneeWidth = 8f, postGain = 1.0f),
                    MbcBandConfig(cutoffFrequency = 20000f, attackTime = 15f, releaseTime = 120f, ratio = 4.0f, threshold = -22f, kneeWidth = 8f, postGain = 1.0f)
                ),
                limiter = LimiterConfig(attackTime = 1f, releaseTime = 150f, ratio = 12f, threshold = -3.0f, postGain = 0.0f)
            ),
            "bassTightener" to DynamicsPresetConfig(
                name = "bassTightener",
                label = "Bass Tightener",
                description = "Controls sub-bass rumble for tight, punchy low-end",
                bands = listOf(
                    MbcBandConfig(cutoffFrequency = 160f, attackTime = 8f, releaseTime = 60f, ratio = 5.0f, threshold = -20f, kneeWidth = 4f, postGain = 2.5f),
                    MbcBandConfig(cutoffFrequency = 3500f, attackTime = 25f, releaseTime = 100f, ratio = 1.5f, threshold = -15f, kneeWidth = 6f, postGain = 0.5f),
                    MbcBandConfig(cutoffFrequency = 20000f, attackTime = 20f, releaseTime = 90f, ratio = 1.5f, threshold = -15f, kneeWidth = 6f, postGain = 0.5f)
                ),
                limiter = LimiterConfig(attackTime = 2f, releaseTime = 50f, ratio = 8f, threshold = -1.0f, postGain = 0.5f)
            )
        )

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

                "setEqEnabled" -> {
                    setEqEnabledState(call.argument<Boolean>("enabled") ?: false)
                    result.success(true)
                }

                "setEqBands" -> {
                    val freqs = call.argument<List<Double>>("frequencies")
                    setEqBandsLayout(freqs)
                    result.success(true)
                }

                "setEqBandGain" -> {
                    val index = call.argument<Int>("index") ?: -1
                    val gainDb = call.argument<Double>("gainDb") ?: 0.0
                    setEqBandGainValue(index, gainDb)
                    result.success(true)
                }

                "setEqBandGains" -> {
                    val gains = call.argument<List<Double>>("gains")
                    setEqGainsValue(gains)
                    result.success(true)
                }

                "setEqPreamp" -> {
                    setEqPreampValue(call.argument<Double>("preampDb") ?: 0.0)
                    result.success(true)
                }

                "isDynamicsSupported" -> {
                    result.success(isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING))
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
                    val dynamicsSupported = isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING)
                    val caps = mapOf(
                        "hasEqualizer" to dynamicsSupported,
                        "eqBandCount" to if (dynamicsSupported) eqBandCount else 0,
                        "eqCenterFrequencies" to eqCenterFreqs.toList(),
                        "hasAudioEffects" to true,
                        "hasTagEditor" to true,
                        "hasRingtoneManager" to true,
                        "hasVisualizer" to true,
                        "hasAppWidget" to true,
                        "isVolumeBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER),
                        "isBassBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST),
                        "isDynamicsSupported" to dynamicsSupported,
                        "isVirtualizerSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER)
                    )
                    result.success(caps)
                }

                "releaseEffects" -> {
                    releaseEffects()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "MethodChannel error handling ${call.method}: ${e.message}", e)
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
                Log.w(TAG, "Virtualizer initialization failed: ${e.message}")
            }
        }
    }

    private fun setVirtualizerState(enabled: Boolean) {
        isVirtualizerEnabled = enabled
        ensureVirtualizer()
        try {
            virtualizer?.enabled = enabled
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set virtualizer enabled: ${e.message}")
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
            Log.w(TAG, "Failed to set virtualizer strength: ${e.message}")
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
                Log.w(TAG, "LoudnessEnhancer init failed, retrying in 500ms: ${e.message}")
                Handler(Looper.getMainLooper()).postDelayed({
                    try {
                        if (loudnessEnhancer == null && currentAudioSessionId != 0) {
                            loudnessEnhancer = LoudnessEnhancer(currentAudioSessionId)
                            if (volumeBoostMilliBels > 0) {
                                loudnessEnhancer?.setTargetGain(volumeBoostMilliBels)
                            }
                            loudnessEnhancer?.enabled = volumeBoostMilliBels > 0
                        }
                    } catch (e2: Exception) {
                        Log.e(TAG, "LoudnessEnhancer retry failed: ${e2.message}")
                    }
                }, 500)
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
            Log.w(TAG, "Failed to set volume boost: ${e.message}")
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
                Log.w(TAG, "BassBoost initialization failed: ${e.message}")
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
            Log.w(TAG, "Failed to set bass boost: ${e.message}")
        }
    }

    // ---- Graphic EQ + Dynamics Engine ------------------------------------

    private fun updateEqInPlace() {
        val dp = dynamicsProcessing ?: return buildDynamicsProcessing()
        try {
            for (ch in 0 until CHANNEL_COUNT) {
                val eq = dp.getPostEqByChannelIndex(ch)
                for (i in 0 until eqBandCount) {
                    val band = eq.getBand(i)
                    band.cutoffFrequency = eqCenterFreqs[i].toFloat()
                    band.gain = if (isEqEnabled) eqBandGains[i].toFloat() else 0f
                    band.isEnabled = true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "In-place EQ update failed, falling back to rebuild: ${e.message}")
            buildDynamicsProcessing()
        }
    }

    private fun updatePreampInPlace() {
        val dp = dynamicsProcessing ?: return
        try {
            val preampDb = if (isEqEnabled) eqPreampDb.toFloat() else 0f
            // Apply preamp to the limiter's postGain instead of inputGain
            // to avoid driving the MBC stage into unwanted compression
            val baseLimiterGain = if (isDynamicsEnabled && currentDynamicsPreset != "off") {
                DYNAMICS_PRESETS[currentDynamicsPreset]?.limiter?.postGain ?: 0f
            } else {
                0f
            }
            for (ch in 0 until CHANNEL_COUNT) {
                val limiter = dp.getLimiterByChannelIndex(ch)
                limiter.postGain = baseLimiterGain + preampDb
            }
        } catch (e: Exception) {
            Log.w(TAG, "Preamp update failed: ${e.message}")
        }
    }

    private fun setDynamicsPresetState(preset: String, enabled: Boolean) {
        currentDynamicsPreset = preset
        isDynamicsEnabled = enabled
        val dp = dynamicsProcessing
        if (dp != null) {
            configureDynamicsInPlace(dp, preset, enabled)
        } else {
            buildDynamicsProcessing()
        }
    }

    private fun configureDynamicsInPlace(
        dp: DynamicsProcessing,
        presetName: String,
        enabled: Boolean
    ) {
        val config = DYNAMICS_PRESETS[presetName]
        if (config == null || !enabled) {
            neutralizeDynamics(dp)
            return
        }
        try {
            val preampDb = if (isEqEnabled) eqPreampDb.toFloat() else 0f
            for (ch in 0 until CHANNEL_COUNT) {
                val mbc = dp.getMbcByChannelIndex(ch)
                for (i in 0 until minOf(MBC_BAND_COUNT, config.bands.size)) {
                    val band = mbc.getBand(i)
                    val cfg = config.bands[i]
                    band.cutoffFrequency = cfg.cutoffFrequency
                    band.attackTime = cfg.attackTime
                    band.releaseTime = cfg.releaseTime
                    band.ratio = cfg.ratio
                    band.threshold = cfg.threshold
                    band.kneeWidth = cfg.kneeWidth
                    band.postGain = cfg.postGain
                    band.isEnabled = true
                }
                val limiter = dp.getLimiterByChannelIndex(ch)
                val limCfg = config.limiter
                limiter.attackTime = limCfg.attackTime
                limiter.releaseTime = limCfg.releaseTime
                limiter.ratio = limCfg.ratio
                limiter.threshold = limCfg.threshold
                limiter.postGain = limCfg.postGain + preampDb
                limiter.isEnabled = true
            }
        } catch (e: Exception) {
            Log.w(TAG, "In-place dynamics configuration failed, falling back to rebuild: ${e.message}")
            buildDynamicsProcessing()
        }
    }

    private fun neutralizeDynamics(dp: DynamicsProcessing) {
        try {
            val preampDb = if (isEqEnabled) eqPreampDb.toFloat() else 0f
            for (ch in 0 until CHANNEL_COUNT) {
                val mbc = dp.getMbcByChannelIndex(ch)
                for (i in 0 until MBC_BAND_COUNT) {
                    mbc.getBand(i).isEnabled = false
                }
                val limiter = dp.getLimiterByChannelIndex(ch)
                limiter.isEnabled = false
                limiter.postGain = preampDb
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to neutralize dynamics: ${e.message}")
        }
    }

    private fun setEqEnabledState(enabled: Boolean) {
        isEqEnabled = enabled
        val dp = dynamicsProcessing
        if (dp != null) {
            updateEqInPlace()
            updatePreampInPlace()
        } else {
            buildDynamicsProcessing()
        }
    }

    private fun setEqBandsLayout(freqs: List<Double>?) {
        if (freqs != null && freqs.isNotEmpty()) {
            eqCenterFreqs = DoubleArray(freqs.size) { freqs[it] }
            eqBandCount = freqs.size
            if (eqBandGains.size != eqBandCount) eqBandGains = DoubleArray(eqBandCount)
        }
        // Band count change requires engine rebuild
        buildDynamicsProcessing()
    }

    private fun setEqGainsValue(gains: List<Double>?) {
        if (gains == null) return
        for (i in 0 until minOf(gains.size, eqBandCount)) eqBandGains[i] = gains[i]
        updateEqInPlace()
    }

    private fun setEqBandGainValue(index: Int, gainDb: Double) {
        if (index < 0 || index >= eqBandCount) return
        eqBandGains[index] = gainDb
        updateEqInPlace()
    }

    private fun setEqPreampValue(preampDb: Double) {
        eqPreampDb = preampDb
        updatePreampInPlace()
    }

    private fun buildPostEq(): DynamicsProcessing.Eq {
        val eq = DynamicsProcessing.Eq(true, true, eqBandCount)
        for (i in 0 until eqBandCount) {
            val band = eq.getBand(i)
            band.cutoffFrequency = eqCenterFreqs[i].toFloat()
            band.gain = if (isEqEnabled) eqBandGains[i].toFloat() else 0f
            band.isEnabled = true
        }
        return eq
    }

    private fun buildDynamicsProcessing() {
        val oldDp = dynamicsProcessing
        dynamicsProcessing = null

        if (currentAudioSessionId == 0) {
            try { oldDp?.release() } catch (_: Exception) {}
            return
        }

        val dynamicsActive = isDynamicsEnabled && currentDynamicsPreset != "off"
        if (!isEqEnabled && !dynamicsActive) {
            try { oldDp?.release() } catch (_: Exception) {}
            return
        }

        try {
            val builder = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                CHANNEL_COUNT,
                false, // preEq
                0,
                true,  // mbc
                MBC_BAND_COUNT,
                true,  // postEq — 10-band graphic EQ
                eqBandCount,
                true   // limiter
            )
            builder.setPreferredFrameDuration(10f)
            builder.setPostEqAllChannelsTo(buildPostEq())

            val config = builder.build()
            val dp = DynamicsProcessing(0, currentAudioSessionId, config)

            if (dynamicsActive) {
                configureDynamicsInPlace(dp, currentDynamicsPreset, true)
            } else {
                neutralizeDynamics(dp)
            }

            dp.enabled = true
            dynamicsProcessing = dp
        } catch (e: Exception) {
            Log.w(TAG, "DynamicsProcessing build failed: ${e.message}")
            dynamicsProcessing = null
        } finally {
            try { oldDp?.release() } catch (_: Exception) {}
        }
    }

    private fun getSpatializerInfo(): Map<String, Any> {
        val result = mutableMapOf<String, Any>(
            "isSupported" to false,
            "isEnabled" to false,
            "isHeadTrackerAvailable" to false
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2) {
            try {
                val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                if (audioManager != null) {
                    val spatializer = audioManager.spatializer
                    result["isSupported"] = spatializer.isAvailable
                    result["isEnabled"] = spatializer.isEnabled
                    result["isHeadTrackerAvailable"] = spatializer.isHeadTrackerAvailable
                }
            } catch (e: Exception) {
                Log.w(TAG, "Spatializer query error: ${e.message}")
            }
        }

        return result
    }

    private fun setSpatializerState(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2) {
            try {
                val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val spatializer = audioManager?.spatializer
                if (spatializer != null && spatializer.isAvailable) {
                    // Hardware Spatializer detected; engage virtualizer supplement for wider staging
                    setVirtualizerState(enabled)
                    if (enabled && virtualizerStrength <= 0) {
                        setVirtualizerStrengthValue(600)
                    }
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "Spatializer hardware check failed, falling back: ${e.message}")
            }
        }
        // Fallback: virtualizer-only stereo field widening
        setVirtualizerState(enabled)
        if (enabled && virtualizerStrength <= 0) {
            setVirtualizerStrengthValue(800)
        }
    }

    private fun recreateEffects() {
        // Build new effects before releasing old ones for gapless transition
        val oldVirtualizer = virtualizer
        val oldLoudnessEnhancer = loudnessEnhancer
        val oldBassBoost = bassBoost
        val oldDynamics = dynamicsProcessing

        virtualizer = null
        loudnessEnhancer = null
        bassBoost = null
        dynamicsProcessing = null
        cachedSupportedEffects = null

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

        buildDynamicsProcessing()

        // Release old instances safely
        try { oldVirtualizer?.release() } catch (_: Exception) {}
        try { oldLoudnessEnhancer?.release() } catch (_: Exception) {}
        try { oldBassBoost?.release() } catch (_: Exception) {}
        try { oldDynamics?.release() } catch (_: Exception) {}
    }

    fun releaseEffects() {
        try {
            virtualizer?.enabled = false
            virtualizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Virtualizer cleanup error: ${e.message}")
        }
        virtualizer = null

        try {
            loudnessEnhancer?.enabled = false
            loudnessEnhancer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "LoudnessEnhancer cleanup error: ${e.message}")
        }
        loudnessEnhancer = null

        try {
            bassBoost?.enabled = false
            bassBoost?.release()
        } catch (e: Exception) {
            Log.w(TAG, "BassBoost cleanup error: ${e.message}")
        }
        bassBoost = null

        try {
            dynamicsProcessing?.enabled = false
            dynamicsProcessing?.release()
        } catch (e: Exception) {
            Log.w(TAG, "DynamicsProcessing cleanup error: ${e.message}")
        }
        dynamicsProcessing = null
        cachedSupportedEffects = null
    }

    private fun isEffectTypeSupported(effectType: UUID): Boolean {
        return try {
            val effects = cachedSupportedEffects ?: AudioEffect.queryEffects()?.also {
                cachedSupportedEffects = it
            } ?: return false
            effects.any { it.type == effectType }
        } catch (e: Exception) {
            Log.w(TAG, "Effect support query failed: ${e.message}")
            false
        }
    }
}
