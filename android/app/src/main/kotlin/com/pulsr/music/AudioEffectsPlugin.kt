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
import kotlin.math.abs

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
    private val mainHandler = Handler(Looper.getMainLooper())
    private var volumeBoostRetryRunnable: Runnable? = null
    private var volumeBoostRetryCount = 0
    private val MAX_VOLUME_BOOST_RETRIES = 3

    // Graphic EQ state. The EQ is a 10-band DynamicsProcessing postEq bound to the
    // same session as the dynamics compressor, so a single engine owns both.
    private var isEqEnabled = false
    private var eqBandCount = DEFAULT_EQ_FREQS.size
    private var eqCenterFreqs = DEFAULT_EQ_FREQS.copyOf()
    private var eqBandGains = DoubleArray(DEFAULT_EQ_FREQS.size)
    private var eqPreampDb = 0.0

    // Native DSP Engine states
    private var isNativeDspLoaded = false
    private var isCrossfeedEnabled = false
    private var crossfeedDelayUs = 350.0
    private var crossfeedFeedDb = -9.0

    private var isLimiterEnabled = false
    private var limiterLookaheadMs = 3.0
    private var limiterThresholdDb = -0.2
    private var limiterReleaseMs = 50.0

    private var isReverbEnabled = false
    private var reverbPreset = 0
    private var reverbWetDry = 0.2f

    private var stereoBalance = 0.0
    private var monoMix = false

    private var isSincResamplerEnabled = true

    init {
        try {
            System.loadLibrary("pulsr_dsp")
            isNativeDspLoaded = true
            Log.i(TAG, "Native DSP engine loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Failed to load native DSP library: ${e.message}")
            isNativeDspLoaded = false
        } catch (e: Exception) {
            Log.w(TAG, "Error loading native DSP library: ${e.message}")
            isNativeDspLoaded = false
        }
    }

    // JNI Declarations
    private external fun nativeSetSampleRate(sampleRate: Double)
    private external fun nativeSetEqEnabled(enabled: Boolean)
    private external fun nativeSetEqBandCount(count: Int)
    private external fun nativeSetEqBand(index: Int, freq: Double, gainDb: Double, q: Double, type: Int, enabled: Boolean)
    private external fun nativeSetEqPreamp(preampDb: Double)
    private external fun nativeSetCrossfeedEnabled(enabled: Boolean)
    private external fun nativeSetCrossfeedParams(delayUs: Double, feedDb: Double)
    private external fun nativeSetLimiterEnabled(enabled: Boolean)
    private external fun nativeSetLimiterParams(lookaheadMs: Double, thresholdDb: Double, releaseMs: Double)
    private external fun nativeSetReverbEnabled(enabled: Boolean)
    private external fun nativeSetReverbPreset(preset: Int)
    private external fun nativeSetReverbWetDry(wetRatio: Float)
    private external fun nativeLoadImpulseResponse(irSamples: FloatArray)
    private external fun nativeSetStereoBalance(balance: Double)
    private external fun nativeSetMonoMix(mono: Boolean)
    private external fun nativeSetSincResamplerEnabled(enabled: Boolean)
    private external fun nativeSetSincResamplerRates(inRate: Double, outRate: Double)
    private external fun nativeProcessAudio(buffer: FloatArray, frames: Int, channels: Int): Int
    private external fun nativeDecodeDsd(dsdL: ByteArray, dsdR: ByteArray, byteCount: Int, dsdRate: Int, targetPcmSampleRate: Int, bitOrder: Int): FloatArray?
    private external fun nativeSetActiveStages(bitmask: Int)
    private external fun nativeReset()

    private var activeDspStages: Int = STAGE_EQ or STAGE_CROSSFEED or STAGE_REVERB or STAGE_PANNER or STAGE_LIMITER or STAGE_RESAMPLER

    fun recalculateActiveStages() {
        var mask = 0
        if (isEqEnabled) mask = mask or STAGE_EQ
        if (isCrossfeedEnabled) mask = mask or STAGE_CROSSFEED
        if (isReverbEnabled) mask = mask or STAGE_REVERB
        if (abs(stereoBalance) > 0.001 || monoMix) mask = mask or STAGE_PANNER
        if (isLimiterEnabled) mask = mask or STAGE_LIMITER
        if (isSincResamplerEnabled) mask = mask or STAGE_RESAMPLER
        activeDspStages = mask

        if (isNativeDspLoaded) {
            try {
                nativeSetActiveStages(activeDspStages)
            } catch (e: Exception) {
                Log.w(TAG, "nativeSetActiveStages failed: ${e.message}")
            }

            val ctx = context
            if (ctx != null) {
                try {
                    val oemInfo = getCachedOemInfo(ctx)
                    val hasOemAudio = oemInfo["hasOemAudio"] as? Boolean ?: false
                    if (hasOemAudio && (isEqEnabled || isCrossfeedEnabled)) {
                        Log.w(TAG, "WARNING: OEM audio engine detected alongside native DSP. Double-processing may cause artifacts.")
                    }
                } catch (_: Exception) {}
            }
        }
    }

    companion object {
        const val STAGE_EQ = 1 shl 0
        const val STAGE_CROSSFEED = 1 shl 1
        const val STAGE_REVERB = 1 shl 2
        const val STAGE_PANNER = 1 shl 3
        const val STAGE_LIMITER = 1 shl 4
        const val STAGE_RESAMPLER = 1 shl 5

        const val TAG = "AudioEffectsPlugin"
        const val CHANNEL_NAME = "com.pulsr.music/audio_effects"
        private const val CHANNEL_COUNT = 2 // Stereo
        private const val MBC_BAND_COUNT = 3

        // ISO standard octave centers for a 10-band graphic equalizer.
        private val DEFAULT_EQ_FREQS = doubleArrayOf(
            32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
        )
        private var cachedSupportedEffects: Array<AudioEffect.Descriptor>? = null
        private var cachedOemInfo: Map<String, Any?>? = null

        fun getCachedOemInfo(context: Context): Map<String, Any?> {
            cachedOemInfo?.let { return it }
            val info = detectOemAudioProcessing(context)
            cachedOemInfo = info
            return info
        }

        private val DOLBY_PACKAGES = listOf(
            "com.dolby.daxservice",
            "com.dolby.daxappui",
            "com.dolby",
            "com.atmos.daxservice",
            "com.motorola.dolby.dolbyui",
            "com.lenovo.dolby"
        )

        private val XIAOMI_AUDIO_PACKAGES = listOf(
            "com.miui.soundfx",
            "com.xiaomi.misound",
            "com.miui.audioeffect"
        )

        private val REALME_AUDIO_PACKAGES = listOf(
            "com.realme.soundfx",
            "com.oplus.soundfx",
            "com.oneplus.soundfx"
        )

        private val SAMSUNG_AUDIO_PACKAGES = listOf(
            "com.sec.android.app.soundalive",
            "com.samsung.android.soundalive"
        )

        private val DIRAC_AUDIO_PACKAGES = listOf(
            "com.dirac.audio",
            "com.dirac.soundfx",
            "com.dirac.acs"
        )

        private val DTS_AUDIO_PACKAGES = listOf(
            "com.dts.dtsxultra",
            "com.dts.freeform",
            "com.dts.audio"
        )

        private val SONY_AUDIO_PACKAGES = listOf(
            "com.sonyericsson.soundenhancement",
            "com.sonymobile.soundenhancement"
        )

        private val ASUS_AUDIO_PACKAGES = listOf(
            "com.asus.audiowizard"
        )

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

        fun detectOemAudioProcessing(ctx: Context): Map<String, Any?> {
            val pm = ctx.packageManager
            val detected = mutableListOf<String>()

            fun checkPackages(packages: List<String>, label: String) {
                for (pkg in packages) {
                    try {
                        val appInfo = pm.getApplicationInfo(pkg, 0)
                        if (appInfo.enabled) {
                            if (!detected.contains(label)) {
                                detected.add(label)
                            }
                            break
                        }
                    } catch (_: Exception) {}
                }
            }

            checkPackages(DOLBY_PACKAGES, "Dolby Atmos")
            checkPackages(XIAOMI_AUDIO_PACKAGES, "Xiaomi Sound")
            checkPackages(REALME_AUDIO_PACKAGES, "Realme / OPPO Sound")
            checkPackages(SAMSUNG_AUDIO_PACKAGES, "Samsung SoundAlive")
            checkPackages(DIRAC_AUDIO_PACKAGES, "Dirac Audio")
            checkPackages(DTS_AUDIO_PACKAGES, "DTS Audio")
            checkPackages(SONY_AUDIO_PACKAGES, "Sony DSEE / Sound Enhancement")
            checkPackages(ASUS_AUDIO_PACKAGES, "Asus AudioWizard")

            // Also query system audio effect descriptors for OEM effects
            try {
                val effects = AudioEffect.queryEffects()
                if (effects != null) {
                    for (desc in effects) {
                        val name = desc.name?.lowercase() ?: ""
                        val implementor = desc.implementor?.lowercase() ?: ""
                        if ((name.contains("dolby") || implementor.contains("dolby")) && !detected.contains("Dolby Atmos")) {
                            detected.add("Dolby Atmos")
                        } else if ((name.contains("dirac") || implementor.contains("dirac")) && !detected.contains("Dirac Audio")) {
                            detected.add("Dirac Audio")
                        } else if ((name.contains("dts") || implementor.contains("dts")) && !detected.contains("DTS Audio")) {
                            detected.add("DTS Audio")
                        } else if ((name.contains("soundalive") || implementor.contains("samsung")) && !detected.contains("Samsung SoundAlive")) {
                            detected.add("Samsung SoundAlive")
                        } else if ((name.contains("misound") || name.contains("miui")) && !detected.contains("Xiaomi Sound")) {
                            detected.add("Xiaomi Sound")
                        }
                    }
                }
            } catch (_: Exception) {}

            return mapOf(
                "hasOemAudio" to detected.isNotEmpty(),
                "detectedEngines" to detected,
                "recommendDisableEq" to detected.isNotEmpty(),
                "warningMessage" to if (detected.isNotEmpty()) {
                    "Detected ${detected.joinToString(", ")}. System-level audio enhancement is active on your device. Consider disabling system sound effects or Pulsr EQ to avoid double-processing and distortion."
                } else null
            )
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        volumeBoostRetryRunnable?.let {
            mainHandler.removeCallbacks(it)
            volumeBoostRetryRunnable = null
        }
        volumeBoostRetryCount = 0
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
                    val milliBels = (call.argument<Int>("milliBels") ?: 0).coerceIn(0, 1000)
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
                    recalculateActiveStages()
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
                    val preampDb = call.argument<Double>("preampDb") ?: 0.0
                    setEqPreampValue(preampDb)
                    if (isNativeDspLoaded) {
                        try { nativeSetEqPreamp(preampDb) } catch (_: Exception) {}
                    }
                    result.success(true)
                }

                // Native DSP Parametric EQ Methods
                "setNativeEqBand" -> {
                    val index = call.argument<Int>("index") ?: 0
                    val freq = call.argument<Double>("frequency") ?: 1000.0
                    val gainDb = call.argument<Double>("gainDb") ?: 0.0
                    val q = call.argument<Double>("q") ?: 1.0
                    val type = call.argument<Int>("type") ?: 0
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetEqBand(index, freq, gainDb, q, type, enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetEqBand failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setNativeEqBandCount" -> {
                    val count = call.argument<Int>("count") ?: 10
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetEqBandCount(count)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetEqBandCount failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setNativeEqEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isEqEnabled = enabled
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetEqEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetEqEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                // Headphone Crossfeed
                "setCrossfeedEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isCrossfeedEnabled = enabled
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetCrossfeedEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetCrossfeedEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setCrossfeedParams" -> {
                    val delayUs = call.argument<Double>("delayUs") ?: 350.0
                    val feedDb = call.argument<Double>("feedDb") ?: -9.0
                    crossfeedDelayUs = delayUs
                    crossfeedFeedDb = feedDb
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetCrossfeedParams(delayUs, feedDb)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetCrossfeedParams failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // Lookahead Brickwall Limiter
                "setLimiterEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isLimiterEnabled = enabled
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetLimiterEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetLimiterEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setLimiterParams" -> {
                    val lookaheadMs = call.argument<Double>("lookaheadMs") ?: 3.0
                    val thresholdDb = call.argument<Double>("thresholdDb") ?: -0.2
                    val releaseMs = call.argument<Double>("releaseMs") ?: 50.0
                    limiterLookaheadMs = lookaheadMs
                    limiterThresholdDb = thresholdDb
                    limiterReleaseMs = releaseMs
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetLimiterParams(lookaheadMs, thresholdDb, releaseMs)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetLimiterParams failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // Convolution Reverb
                "setReverbEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isReverbEnabled = enabled
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetReverbEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetReverbEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setReverbPreset" -> {
                    val preset = call.argument<Int>("preset") ?: 0
                    reverbPreset = preset
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetReverbPreset(preset)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetReverbPreset failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setReverbWetDry" -> {
                    val wetRatio = (call.argument<Double>("wetRatio") ?: 0.2).toFloat()
                    reverbWetDry = wetRatio
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetReverbWetDry(wetRatio)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetReverbWetDry failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "loadImpulseResponse" -> {
                    val irList = call.argument<List<Double>>("irSamples")
                    if (irList != null && isNativeDspLoaded) {
                        try {
                            val floatArray = FloatArray(irList.size) { irList[it].toFloat() }
                            nativeLoadImpulseResponse(floatArray)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeLoadImpulseResponse failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // Stereo Balance & Mono Mix
                "setStereoBalance" -> {
                    val balance = call.argument<Double>("balance") ?: 0.0
                    stereoBalance = balance
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetStereoBalance(balance)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetStereoBalance failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setMonoMix" -> {
                    val mono = call.argument<Boolean>("mono") ?: false
                    monoMix = mono
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetMonoMix(mono)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetMonoMix failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                // Sinc Resampler
                "setSincResamplerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    isSincResamplerEnabled = enabled
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetSincResamplerEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetSincResamplerEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setSincResamplerRates" -> {
                    val inRate = call.argument<Double>("inRate") ?: 44100.0
                    val outRate = call.argument<Double>("outRate") ?: 48000.0
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetSincResamplerRates(inRate, outRate)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetSincResamplerRates failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // DSD Decoding
                "decodeDsd" -> {
                    val dsdL = call.argument<ByteArray>("dsdL")
                    val dsdR = call.argument<ByteArray>("dsdR")
                    val byteCount = call.argument<Int>("byteCount") ?: (dsdL?.size ?: 0)
                    val dsdRate = call.argument<Int>("dsdRate") ?: 64
                    val targetRate = call.argument<Int>("targetSampleRate") ?: 176400
                    val bitOrder = call.argument<Int>("bitOrder") ?: 0 // 0 = MSB (DSF), 1 = LSB (DFF)

                    if (dsdL != null && dsdR != null && isNativeDspLoaded) {
                        try {
                            val pcmFloats = nativeDecodeDsd(dsdL, dsdR, byteCount, dsdRate, targetRate, bitOrder)
                            result.success(pcmFloats?.toList())
                        } catch (e: Exception) {
                            result.error("DSD_DECODE_ERROR", e.message, null)
                        }
                    } else {
                        result.success(null)
                    }
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

                "hasActiveEffects" -> {
                    result.success(hasActiveEffects())
                }

                "isOffloadAllowed" -> {
                    result.success(!hasActiveEffects())
                }

                "getCapabilities" -> {
                    val dynamicsSupported = isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING)
                    val caps = mapOf(
                        "hasEqualizer" to (dynamicsSupported || isNativeDspLoaded),
                        "hasNativeDsp" to isNativeDspLoaded,
                        "hasNativeParametricEq" to isNativeDspLoaded,
                        "hasCrossfeed" to isNativeDspLoaded,
                        "hasLookaheadLimiter" to isNativeDspLoaded,
                        "hasConvolutionReverb" to isNativeDspLoaded,
                        "hasSincResampler" to isNativeDspLoaded,
                        "hasDsdDecoder" to isNativeDspLoaded,
                        "eqBandCount" to if (isNativeDspLoaded) 32 else (if (dynamicsSupported) eqBandCount else 0),
                        "eqCenterFrequencies" to eqCenterFreqs.toList(),
                        "hasAudioEffects" to true,
                        "hasTagEditor" to true,
                        "hasRingtoneManager" to true,
                        "hasVisualizer" to true,
                        "hasAppWidget" to true,
                        "isVolumeBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER),
                        "isBassBoostSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST),
                        "isDynamicsSupported" to dynamicsSupported,
                        "isVirtualizerSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER),
                        "isFloatOutputSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP),
                        "isHardwareOffloadSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    )
                    result.success(caps)
                }

                "detectOemAudio" -> {
                    val ctx = context
                    if (ctx != null) {
                        result.success(detectOemAudioProcessing(ctx))
                    } else {
                        result.success(mapOf("hasOemAudio" to false, "detectedEngines" to emptyList<String>()))
                    }
                }

                "releaseEffects" -> {
                    releaseEffects()
                    if (isNativeDspLoaded) {
                        try { nativeReset() } catch (_: Exception) {}
                    }
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
        if (loudnessEnhancer == null && currentAudioSessionId > 0) {
            try {
                loudnessEnhancer = LoudnessEnhancer(currentAudioSessionId)
                if (volumeBoostMilliBels > 0) {
                    loudnessEnhancer?.setTargetGain(volumeBoostMilliBels)
                }
                loudnessEnhancer?.enabled = volumeBoostMilliBels > 0
                volumeBoostRetryCount = 0 // Reset on success
            } catch (e: Exception) {
                if (volumeBoostRetryCount < MAX_VOLUME_BOOST_RETRIES) {
                    volumeBoostRetryCount++
                    val delay = 500L * volumeBoostRetryCount
                    Log.w(TAG, "LoudnessEnhancer init failed (attempt $volumeBoostRetryCount/$MAX_VOLUME_BOOST_RETRIES), retrying in ${delay}ms: ${e.message}")
                    volumeBoostRetryRunnable?.let { mainHandler.removeCallbacks(it) }
                    val weakThis = java.lang.ref.WeakReference(this)
                    val runnable = Runnable {
                        val plugin = weakThis.get()
                        if (plugin != null && plugin.context != null) {
                            plugin.ensureVolumeBoost()
                        }
                    }
                    volumeBoostRetryRunnable = runnable
                    mainHandler.postDelayed(runnable, delay)
                } else {
                    Log.e(TAG, "LoudnessEnhancer init failed after $MAX_VOLUME_BOOST_RETRIES retries: ${e.message}")
                    volumeBoostRetryRunnable = null
                }
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
            val shouldKeepLimiter = isDynamicsEnabled && currentDynamicsPreset != "off"
            for (ch in 0 until CHANNEL_COUNT) {
                val mbc = dp.getMbcByChannelIndex(ch)
                for (i in 0 until MBC_BAND_COUNT) {
                    mbc.getBand(i).isEnabled = false
                }
                val limiter = dp.getLimiterByChannelIndex(ch)
                if (!shouldKeepLimiter) {
                    limiter.isEnabled = false
                    limiter.postGain = preampDb
                }
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
            val oldBandCount = eqBandCount
            eqCenterFreqs = DoubleArray(freqs.size) { freqs[it] }
            eqBandCount = freqs.size
            if (eqBandGains.size != eqBandCount) eqBandGains = DoubleArray(eqBandCount)
            if (oldBandCount == eqBandCount && dynamicsProcessing != null) {
                updateEqInPlace()
                return
            }
        }
        // Band count change requires engine rebuild
        buildDynamicsProcessing()
    }

    private fun setEqGainsValue(gains: List<Double>?) {
        if (gains == null) return
        for (i in 0 until minOf(gains.size, eqBandCount)) eqBandGains[i] = gains[i]
        updateEqInPlace()
    }

    private var eqUpdateRunnable: Runnable? = null

    private fun setEqBandGainValue(index: Int, gainDb: Double) {
        if (index < 0 || index >= eqBandCount) return
        eqBandGains[index] = gainDb
        eqUpdateRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable { updateEqInPlace() }
        eqUpdateRunnable = r
        mainHandler.postDelayed(r, 20L)
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
            val nativeBufferMs = try {
                val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                val nativeRate = audioManager?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48000
                val nativeFrames = audioManager?.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull() ?: 192
                (nativeFrames.toDouble() / nativeRate * 1000).toFloat().coerceIn(5f, 20f)
            } catch (_: Exception) { 10f }
            builder.setPreferredFrameDuration(nativeBufferMs)
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
                    try {
                        val setEnabledMethod = spatializer.javaClass.getMethod("setEnabled", Boolean::class.javaPrimitiveType)
                        setEnabledMethod.invoke(spatializer, enabled)
                    } catch (_: Exception) {
                        // Some OEM ROMs or API revisions might not expose setEnabled directly
                    }
                    Log.i(TAG, "Hardware Spatializer ${if (enabled) "enabled" else "disabled"}")
                    return  // Don't fall through to virtualizer
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
        // Release old instances BEFORE creating new ones to prevent audio session conflicts
        try { virtualizer?.release() } catch (_: Exception) {}
        try { loudnessEnhancer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        try { dynamicsProcessing?.release() } catch (_: Exception) {}

        virtualizer = null
        loudnessEnhancer = null
        bassBoost = null
        dynamicsProcessing = null
        cachedSupportedEffects = runCatching { AudioEffect.queryEffects() }.getOrNull()

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
    }

    fun releaseEffects() {
        volumeBoostRetryRunnable?.let {
            mainHandler.removeCallbacks(it)
            volumeBoostRetryRunnable = null
        }
        volumeBoostRetryCount = 0
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

    fun hasActiveEffects(): Boolean {
        return isEqEnabled ||
                (isDynamicsEnabled && currentDynamicsPreset != "off") ||
                (isVirtualizerEnabled && virtualizerStrength > 0) ||
                (volumeBoostMilliBels > 0) ||
                (bassBoostStrength > 0) ||
                isCrossfeedEnabled ||
                isLimiterEnabled ||
                isReverbEnabled ||
                (abs(stereoBalance) > 0.001) ||
                monoMix
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
