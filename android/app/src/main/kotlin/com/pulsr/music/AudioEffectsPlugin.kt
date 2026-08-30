package com.pulsr.music

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
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
    // DynamicsProcessing is absent or broken on a sizeable number of Android
    // audio HALs. Keep a session-bound platform EQ as a real-output fallback;
    // the C++ engine is configured here too, but it is not in ExoPlayer's PCM
    // callback and must never be the only audible EQ path.
    private var legacyEqualizer: Equalizer? = null
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

    // Phase 1 DSP expansion stages
    private var isSaturationEnabled = false
    private var saturationDrive = 0.3
    private var saturationMix = 0.5
    private var saturationTilt = 0.3

    private var isStereoWidthEnabled = false
    private var stereoWidth = 1.0

    private var isLoudnessContourEnabled = false
    private var loudnessIntensity = 0.0
    private var loudnessVolumeLinear = 1.0

    private var isSubCrossoverEnabled = false
    private var subCrossoverCornerHz = 80.0
    private var subCrossoverSlopeDbPerOct = 24.0
    private var subCrossoverGain = 0.8

    private var isDynamicEqEnabled = false
    private var dynamicEqBandCount = 1

    private var isSincResamplerEnabled = true
    private var resamplerInRate = 48000.0
    private var resamplerOutRate = 48000.0
    private var dspPreference: String = "native" // "native", "oem", "auto"
    private var _oemWarningLogged = false
    private var isBitPerfectBypassActive = false
    private var bypassSavedStages: Int? = null
    @Volatile private var reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    private fun safeReverbExecute(action: () -> Unit) {
        try {
            reverbExecutor.execute { try { action() } catch (_: Exception) {} }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            try {
                reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
                reverbExecutor.execute { try { action() } catch (_: Exception) {} }
            } catch (_: Exception) {
                android.util.Log.w(TAG, "Reverb executor rejected after recreate: ${e.message}")
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "safeReverbExecute failed: ${e.message}")
        }
    }

    // Deduplication caches for native effect parameter pushes (W7)
    private var lastNativeEqPreamp: Double? = null
    private val lastNativeEqBands = mutableMapOf<Int, String>()
    private var lastNativeEqBandCount: Int? = null
    private var lastNativeEqEnabled: Boolean? = null
    private var lastNativeCrossfeedEnabled: Boolean? = null
    private var lastNativeCrossfeedParams: String? = null
    private var lastNativeLimiterEnabled: Boolean? = null
    private var lastNativeLimiterParams: String? = null
    private var lastNativeReverbEnabled: Boolean? = null
    private var lastNativeReverbPreset: Int? = null
    private var lastNativeReverbWetDry: Float? = null
    private var lastNativeReverbParams: String? = null
    private var lastNativeStereoBalance: Double? = null
    private var lastNativeMonoMix: Boolean? = null
    private var lastNativeResamplerEnabled: Boolean? = null
    private var lastNativeResamplerRates: String? = null
    private var lastNativeSaturationEnabled: Boolean? = null
    private var lastNativeSaturationParams: String? = null
    private var lastNativeStereoWidthEnabled: Boolean? = null
    private var lastNativeStereoWidthParams: Double? = null
    private var lastNativeLoudnessEnabled: Boolean? = null
    private var lastNativeLoudnessParams: String? = null
    private var lastNativeSubCrossoverEnabled: Boolean? = null
    private var lastNativeSubCrossoverParams: String? = null
    private var lastNativeDynamicEqEnabled: Boolean? = null
    private val lastNativeDynamicEqBands = mutableMapOf<Int, String>()

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
    private external fun nativeResyncForTrack(sampleRate: Double, channels: Int)
    private external fun nativeGetAppliedSampleRate(): Double
    private external fun nativeGetLastAppliedGeneration(): Long
    private external fun nativeGetPublishedGeneration(): Long
    private external fun nativeGetPipelineLatencyFrames(): Int
    private external fun nativeSetEqEnabled(enabled: Boolean)
    private external fun nativeSetEqBandCount(count: Int)
    private external fun nativeSetEqBand(index: Int, freq: Double, gainDb: Double, q: Double, type: Int, enabled: Boolean)
    private external fun nativeSetEqBandsBulk(freqs: DoubleArray, gains: DoubleArray, qs: DoubleArray, types: IntArray)
    private external fun nativeSetBandSolo(index: Int, solo: Boolean)
    private external fun nativeSetBandMute(index: Int, mute: Boolean)
    private external fun nativeSetEqPreamp(preampDb: Double)
    private external fun nativeSetCrossfeedEnabled(enabled: Boolean)
    private external fun nativeSetCrossfeedParams(delayUs: Double, feedDb: Double)
    private external fun nativeSetCrossfeedFcut(fcut: Double)
    private external fun nativeSetLimiterEnabled(enabled: Boolean)
    private external fun nativeSetLimiterParams(lookaheadMs: Double, thresholdDb: Double, releaseMs: Double)
    private external fun nativeSetLimiterTruePeak(truePeak: Boolean)
    private external fun nativeSetReverbEnabled(enabled: Boolean)
    private external fun nativeSetReverbPreset(preset: Int)
    private external fun nativeSetReverbWetDry(wetRatio: Float)
    private external fun nativeSetReverbPredelay(predelayMs: Double)
    private external fun nativeSetReverbDamping(damping: Double)
    private external fun nativeLoadImpulseResponse(irSamples: FloatArray, channels: Int): Boolean
    private external fun nativeSetStereoBalance(balance: Double)
    private external fun nativeSetMonoMix(mono: Boolean)
    private external fun nativeSetSincResamplerEnabled(enabled: Boolean)
    private external fun nativeSetSincResamplerRates(inRate: Double, outRate: Double)
    private external fun nativeSetSaturationEnabled(enabled: Boolean)
    private external fun nativeSetSaturationParams(drive: Double, mix: Double, tilt: Double)
    private external fun nativeSetStereoWidthEnabled(enabled: Boolean)
    private external fun nativeSetStereoWidthParams(width: Double)
    private external fun nativeSetLoudnessContourEnabled(enabled: Boolean)
    private external fun nativeSetLoudnessContourParams(intensity: Double, volumeLinear: Double)
    private external fun nativeSetSubCrossoverEnabled(enabled: Boolean)
    private external fun nativeSetSubCrossoverParams(cornerHz: Double, slopeDbPerOct: Double, subGain: Double)
    private external fun nativeSetDynamicEqEnabled(enabled: Boolean)
    private external fun nativeSetDynamicEqBandCount(count: Int)
    private external fun nativeSetDynamicEqBand(
        index: Int, freq: Double, q: Double, thresholdDb: Double, ratio: Double,
        attackMs: Double, releaseMs: Double, maxCutDb: Double, enabled: Boolean
    )
    private external fun nativeProcessAudio(buffer: FloatArray, frames: Int, channels: Int): Int
    private external fun nativeDecodeDsd(dsdL: ByteArray, dsdR: ByteArray, byteCount: Int, dsdRate: Int, targetPcmSampleRate: Int, bitOrder: Int): FloatArray?
    private external fun nativeSetActiveStages(bitmask: Int)
    private external fun nativeSetCacheBudgetBytes(budgetBytes: Long)
    private external fun nativeGetAutoDegradedStages(): Int
    private external fun nativeReset()

    fun configureNativeMemoryBudget(ctx: Context) {
        if (!isNativeDspLoaded) return
        try {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            val memoryInfo = android.app.ActivityManager.MemoryInfo()
            am?.getMemoryInfo(memoryInfo)
            val memClass = am?.memoryClass ?: 256
            val isLowRam = am?.isLowRamDevice == true || memClass < 128 || (memoryInfo.totalMem > 0 && memoryInfo.totalMem < 3L * 1024 * 1024 * 1024)
            // Low-RAM (isLowRamDevice or memoryClass <128 or <3GB) -> 16MB; else 32MB conservative.
            // 16MB comfortably fits the active synthetic IR (~10MB for Cathedral) + 1 cached preset.
            // Inactive presets are evicted and regenerated on-demand (~2-5ms CPU cost upon preset switch).
            // Tradeoff: Memory footprint strictly constrained (<48MB peak RSS) at the cost of transient on-demand CPU synthesis.
            val budgetBytes = if (isLowRam) 16L * 1024 * 1024 else 32L * 1024 * 1024
            nativeSetCacheBudgetBytes(budgetBytes)
            Log.i(TAG, "Configured Native IR cache budget: ${budgetBytes / (1024 * 1024)} MB (isLowRam=$isLowRam)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to configure native memory budget: ${e.message}")
        }
    }

    private var activeDspStages: Int = STAGE_EQ or STAGE_CROSSFEED or STAGE_REVERB or STAGE_PANNER or STAGE_LIMITER or STAGE_RESAMPLER or STAGE_SATURATION or STAGE_WIDTH or STAGE_LOUDNESS or STAGE_CROSSOVER or STAGE_DYNEQ

    @Synchronized
    fun recalculateActiveStages() {
        // Bit-perfect bypass: force zero stages regardless of toggles
        if (isBitPerfectBypassActive) {
            activeDspStages = 0
            if (isNativeDspLoaded) {
                try { nativeSetActiveStages(0) } catch (_: Exception) {}
                try { nativeSetSincResamplerEnabled(false) } catch (_: Exception) {}
            }
            return
        }
        var mask = 0
        // Respect dspPreference: native=only native, oem=disable native EQ, auto=native unless OEM detected
        val useNativeEq = when (dspPreference) {
            "oem" -> false
            "auto" -> {
                val ctx = context
                val hasOem = ctx?.let { getCachedOemInfo(it)["hasOemAudio"] as? Boolean } ?: false
                !hasOem
            }
            else -> true // native
        }
        if (isEqEnabled && useNativeEq) mask = mask or STAGE_EQ
        if (isCrossfeedEnabled) mask = mask or STAGE_CROSSFEED
        if (isReverbEnabled) mask = mask or STAGE_REVERB
        if (abs(stereoBalance) > 0.001 || monoMix) mask = mask or STAGE_PANNER
        if (isLimiterEnabled) mask = mask or STAGE_LIMITER
        // Sinc resampler only if actually needed (rate mismatch) — zero-cost zero-mask when bypassed
        if (isSincResamplerEnabled && Math.abs(resamplerInRate - resamplerOutRate) > 1.0) {
            mask = mask or STAGE_RESAMPLER
        }
        // Phase 1 DSP expansion stages
        if (isSaturationEnabled) mask = mask or STAGE_SATURATION
        if (isStereoWidthEnabled) mask = mask or STAGE_WIDTH
        // Loudness contour needs both a non-zero intensity and a known volume-stage value
        if (isLoudnessContourEnabled && loudnessIntensity > 0.001) mask = mask or STAGE_LOUDNESS
        if (isSubCrossoverEnabled) mask = mask or STAGE_CROSSOVER
        if (isDynamicEqEnabled && dynamicEqBandCount > 0) mask = mask or STAGE_DYNEQ
        activeDspStages = mask

        if (isNativeDspLoaded) {
            try {
                nativeSetActiveStages(activeDspStages)
            } catch (e: Exception) {
                Log.w(TAG, "nativeSetActiveStages failed: ${e.message}")
            }

            val ctx = context
            if (ctx != null && !_oemWarningLogged) {
                try {
                    val oemInfo = getCachedOemInfo(ctx)
                    val hasOemAudio = oemInfo["hasOemAudio"] as? Boolean ?: false
                    if (hasOemAudio && (isEqEnabled || isCrossfeedEnabled)) {
                        Log.w(TAG, "WARNING: OEM audio engine detected alongside native DSP. Double-processing bypassed via native DSP routing.")
                        _oemWarningLogged = true
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
        // Phase 1 DSP expansion stages (must mirror DspStageMask in AudioDspEngine.h)
        const val STAGE_SATURATION = 1 shl 6
        const val STAGE_WIDTH = 1 shl 7
        const val STAGE_LOUDNESS = 1 shl 8
        const val STAGE_CROSSOVER = 1 shl 9
        const val STAGE_DYNEQ = 1 shl 10

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

    private var audioDeviceCallback: Any? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        // Recreate executor if previously shut down
        if (reverbExecutor.isShutdown || reverbExecutor.isTerminated) {
            reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
        }
        configureNativeMemoryBudget(binding.applicationContext)
        // Prefetch OEM info off main thread
        Thread { try { getCachedOemInfo(binding.applicationContext) } catch (_: Exception) {} }.start()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                val callback = object : AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                        mainHandler.postDelayed({
                            if (currentAudioSessionId != 0 && hasActiveEffects()) {
                                recreateEffects()
                            }
                        }, 200L)
                    }

                    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                        mainHandler.postDelayed({
                            if (currentAudioSessionId != 0 && hasActiveEffects()) {
                                recreateEffects()
                            }
                        }, 200L)
                    }
                }
                audioManager.registerAudioDeviceCallback(callback, mainHandler)
                audioDeviceCallback = callback
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val callback = audioDeviceCallback as? AudioDeviceCallback
            val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (callback != null && audioManager != null) {
                try { audioManager.unregisterAudioDeviceCallback(callback) } catch (_: Exception) {}
            }
        }
        audioDeviceCallback = null

        volumeBoostRetryRunnable?.let {
            mainHandler.removeCallbacks(it)
            volumeBoostRetryRunnable = null
        }
        eqUpdateRunnable?.let {
            mainHandler.removeCallbacks(it)
            eqUpdateRunnable = null
        }
        volumeBoostRetryCount = 0
        // Don't shutdown executor permanently; just remove queued tasks for detach
        try { reverbExecutor.shutdown() } catch (_: Exception) {}
        // Clear dedup caches so post-reset values are resent
        lastNativeEqPreamp = null
        lastNativeEqBands.clear()
        lastNativeEqBandCount = null
        lastNativeEqEnabled = null
        lastNativeCrossfeedEnabled = null
        lastNativeCrossfeedParams = null
        lastNativeLimiterEnabled = null
        lastNativeLimiterParams = null
        lastNativeReverbEnabled = null
        lastNativeReverbPreset = null
        lastNativeReverbWetDry = null
        lastNativeReverbParams = null
        lastNativeStereoBalance = null
        lastNativeMonoMix = null
        lastNativeResamplerEnabled = null
        lastNativeResamplerRates = null
        lastNativeSaturationEnabled = null
        lastNativeSaturationParams = null
        lastNativeStereoWidthEnabled = null
        lastNativeStereoWidthParams = null
        lastNativeLoudnessEnabled = null
        lastNativeLoudnessParams = null
        lastNativeSubCrossoverEnabled = null
        lastNativeSubCrossoverParams = null
        lastNativeDynamicEqEnabled = null
        lastNativeDynamicEqBands.clear()
        releaseEffects()
        try { methodChannel.setMethodCallHandler(null) } catch (_: Exception) {}
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

                "resyncForTrack" -> {
                    val sampleRate = call.argument<Double>("sampleRate") ?: 44100.0
                    val channels = call.argument<Int>("channels") ?: 2
                    if (isNativeDspLoaded) {
                        try {
                            nativeResyncForTrack(sampleRate, channels)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeResyncForTrack failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "getDspDebugStatus" -> {
                    if (isNativeDspLoaded) {
                        try {
                            val status = mapOf(
                                "appliedSampleRate" to nativeGetAppliedSampleRate(),
                                "lastAppliedGeneration" to nativeGetLastAppliedGeneration(),
                                "publishedGeneration" to nativeGetPublishedGeneration()
                            )
                            result.success(status)
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
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
                    if (isNativeDspLoaded && lastNativeEqPreamp != preampDb) {
                        lastNativeEqPreamp = preampDb
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
                        val key = "$freq:$gainDb:$q:$type:$enabled"
                        if (lastNativeEqBands[index] != key) {
                            lastNativeEqBands[index] = key
                            try {
                                nativeSetEqBand(index, freq, gainDb, q, type, enabled)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetEqBand failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                "setNativeEqBandsBulk" -> {
                    val freqs = (call.argument<List<Double>>("frequencies") ?: emptyList())
                    val gains = (call.argument<List<Double>>("gains") ?: emptyList())
                    val qs = (call.argument<List<Double>>("qs") ?: freqs.map { 1.414 })
                    val types = (call.argument<List<Int>>("types") ?: freqs.map { 0 })
                    if (isNativeDspLoaded && freqs.isNotEmpty() && freqs.size == gains.size) {
                        try {
                            val freqArr = DoubleArray(freqs.size) { freqs[it] }
                            val gainArr = DoubleArray(gains.size) { gains[it] }
                            val qArr = DoubleArray(qs.size) { qs[it] }
                            val typeArr = IntArray(types.size) { types[it] }
                            // Single JNI hop — clears per-band dedup cache
                            nativeSetEqBandsBulk(freqArr, gainArr, qArr, typeArr)
                            lastNativeEqBandCount = freqs.size
                            // Repopulate dedup cache to avoid stale per-band pushes
                            for (i in freqs.indices) {
                                lastNativeEqBands[i] = "${freqs[i]}:${gains[i]}:${qs[i]}:${types[i]}:true"
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetEqBandsBulk failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setNativeEqBandCount" -> {
                    val count = call.argument<Int>("count") ?: 10
                    if (isNativeDspLoaded && lastNativeEqBandCount != count) {
                        lastNativeEqBandCount = count
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
                    if (isNativeDspLoaded && lastNativeEqEnabled != enabled) {
                        lastNativeEqEnabled = enabled
                        try {
                            nativeSetEqEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetEqEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "getPipelineLatencyFrames" -> {
                    if (isNativeDspLoaded) {
                        try {
                            result.success(nativeGetPipelineLatencyFrames())
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    } else {
                        result.success(0)
                    }
                }

                "setBandSolo" -> {
                    val index = call.argument<Int>("index") ?: -1
                    val solo = call.argument<Boolean>("solo") ?: false
                    if (index >= 0 && isNativeDspLoaded) {
                        try {
                            nativeSetBandSolo(index, solo)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetBandSolo failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setBandMute" -> {
                    val index = call.argument<Int>("index") ?: -1
                    val mute = call.argument<Boolean>("mute") ?: false
                    if (index >= 0 && isNativeDspLoaded) {
                        try {
                            nativeSetBandMute(index, mute)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetBandMute failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // Headphone Crossfeed
                "setCrossfeedEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isCrossfeedEnabled = enabled
                    if (isNativeDspLoaded && lastNativeCrossfeedEnabled != enabled) {
                        lastNativeCrossfeedEnabled = enabled
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
                    val fcut = call.argument<Double>("fcut") ?: 650.0
                    crossfeedDelayUs = delayUs
                    crossfeedFeedDb = feedDb
                    if (isNativeDspLoaded) {
                        val key = "$delayUs:$feedDb:$fcut"
                        if (lastNativeCrossfeedParams != key) {
                            lastNativeCrossfeedParams = key
                            try {
                                nativeSetCrossfeedParams(delayUs, feedDb)
                                nativeSetCrossfeedFcut(fcut)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetCrossfeedParams failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                // Lookahead Brickwall Limiter
                "setLimiterEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isLimiterEnabled = enabled
                    if (isNativeDspLoaded && lastNativeLimiterEnabled != enabled) {
                        lastNativeLimiterEnabled = enabled
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
                    val truePeak = call.argument<Boolean>("truePeakMode") ?: true
                    limiterLookaheadMs = lookaheadMs
                    limiterThresholdDb = thresholdDb
                    limiterReleaseMs = releaseMs
                    if (isNativeDspLoaded) {
                        val key = "$lookaheadMs:$thresholdDb:$releaseMs:$truePeak"
                        if (lastNativeLimiterParams != key) {
                            lastNativeLimiterParams = key
                            try {
                                nativeSetLimiterParams(lookaheadMs, thresholdDb, releaseMs)
                                nativeSetLimiterTruePeak(truePeak)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetLimiterParams failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                // Convolution Reverb
                "setReverbEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isReverbEnabled = enabled
                    if (isNativeDspLoaded && lastNativeReverbEnabled != enabled) {
                        lastNativeReverbEnabled = enabled
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
                    if (isNativeDspLoaded && lastNativeReverbPreset != preset) {
                        lastNativeReverbPreset = preset
                        // Offload IR synthesis off main thread to avoid 50-120ms ANR on Cathedral presets
                        safeReverbExecute {
                            try {
                                nativeSetReverbPreset(preset)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetReverbPreset async failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                "setReverbWetDry" -> {
                    val wetRatio = (call.argument<Double>("wetRatio") ?: 0.2).toFloat()
                    reverbWetDry = wetRatio
                    if (isNativeDspLoaded && lastNativeReverbWetDry != wetRatio) {
                        lastNativeReverbWetDry = wetRatio
                        try {
                            nativeSetReverbWetDry(wetRatio)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetReverbWetDry failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "setReverbParams" -> {
                    val predelayMs = call.argument<Double>("predelayMs") ?: 0.0
                    val damping = call.argument<Double>("damping") ?: 0.5
                    if (isNativeDspLoaded) {
                        val key = "$predelayMs:$damping"
                        if (lastNativeReverbParams != key) {
                            lastNativeReverbParams = key
                            // Damping triggers IR resynthesis — offload
                            safeReverbExecute {
                                try {
                                    nativeSetReverbPredelay(predelayMs)
                                    nativeSetReverbDamping(damping)
                                } catch (e: Exception) {
                                    Log.w(TAG, "nativeSetReverbParams async failed: ${e.message}")
                                }
                            }
                        }
                    }
                    result.success(true)
                }

                "loadImpulseResponse" -> {
                    val irList = call.argument<List<Double>>("irSamples")
                    val channels = call.argument<Int>("channels") ?: 2
                    if (irList != null && isNativeDspLoaded) {
                        // Large IR offloaded to avoid blocking MethodChannel (up to 1M taps)
                        val copy = irList.toList() // detach from Dart memory
                        safeReverbExecute {
                            try {
                                val floatArray = FloatArray(copy.size) { copy[it].toFloat() }
                                val loaded = nativeLoadImpulseResponse(floatArray, channels)
                                if (!loaded) Log.w(TAG, "IR too large or exceeds budget")
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeLoadImpulseResponse async failed: ${e.message}")
                            }
                        }
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }

                "setCacheBudgetBytes" -> {
                    val bytes = (call.argument<Number>("budgetBytes"))?.toLong() ?: (64L * 1024 * 1024)
                    if (isNativeDspLoaded) {
                        try {
                            nativeSetCacheBudgetBytes(bytes)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetCacheBudgetBytes failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                "getAutoDegradedStages" -> {
                    if (isNativeDspLoaded) {
                        try {
                            val stages = nativeGetAutoDegradedStages()
                            result.success(stages)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeGetAutoDegradedStages failed: ${e.message}")
                            result.success(0)
                        }
                    } else {
                        result.success(0)
                    }
                }

                // Stereo Balance & Mono Mix
                "setStereoBalance" -> {
                    val balance = call.argument<Double>("balance") ?: 0.0
                    stereoBalance = balance
                    if (isNativeDspLoaded && lastNativeStereoBalance != balance) {
                        lastNativeStereoBalance = balance
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
                    if (isNativeDspLoaded && lastNativeMonoMix != mono) {
                        lastNativeMonoMix = mono
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
                    if (isNativeDspLoaded && lastNativeResamplerEnabled != enabled) {
                        lastNativeResamplerEnabled = enabled
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
                    resamplerInRate = inRate
                    resamplerOutRate = outRate
                    if (isNativeDspLoaded) {
                        val key = "$inRate:$outRate"
                        if (lastNativeResamplerRates != key) {
                            lastNativeResamplerRates = key
                            try {
                                nativeSetSincResamplerRates(inRate, outRate)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetSincResamplerRates failed: ${e.message}")
                            }
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                // ---- Phase 1 DSP expansion: Harmonic Saturation / Exciter ----
                "setSaturationEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isSaturationEnabled = enabled
                    if (isNativeDspLoaded && lastNativeSaturationEnabled != enabled) {
                        lastNativeSaturationEnabled = enabled
                        try {
                            nativeSetSaturationEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetSaturationEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setSaturationParams" -> {
                    val drive = call.argument<Double>("drive") ?: 0.3
                    val mix = call.argument<Double>("mix") ?: 0.5
                    val tilt = call.argument<Double>("tilt") ?: 0.3
                    saturationDrive = drive
                    saturationMix = mix
                    saturationTilt = tilt
                    if (isNativeDspLoaded) {
                        val key = "$drive:$mix:$tilt"
                        if (lastNativeSaturationParams != key) {
                            lastNativeSaturationParams = key
                            try {
                                nativeSetSaturationParams(drive, mix, tilt)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetSaturationParams failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                // ---- Phase 1 DSP expansion: Stereo Width (Mid/Side) ----
                "setStereoWidthEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isStereoWidthEnabled = enabled
                    if (isNativeDspLoaded && lastNativeStereoWidthEnabled != enabled) {
                        lastNativeStereoWidthEnabled = enabled
                        try {
                            nativeSetStereoWidthEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetStereoWidthEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setStereoWidthParams" -> {
                    val width = call.argument<Double>("width") ?: 1.0
                    stereoWidth = width
                    if (isNativeDspLoaded && lastNativeStereoWidthParams != width) {
                        lastNativeStereoWidthParams = width
                        try {
                            nativeSetStereoWidthParams(width)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetStereoWidthParams failed: ${e.message}")
                        }
                    }
                    result.success(true)
                }

                // ---- Phase 1 DSP expansion: Loudness Contour (Fletcher-Munson) ----
                "setLoudnessContourEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isLoudnessContourEnabled = enabled
                    if (isNativeDspLoaded && lastNativeLoudnessEnabled != enabled) {
                        lastNativeLoudnessEnabled = enabled
                        try {
                            nativeSetLoudnessContourEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetLoudnessContourEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setLoudnessContourParams" -> {
                    val intensity = call.argument<Double>("intensity") ?: 0.0
                    val volumeLinear = call.argument<Double>("volumeLinear") ?: 1.0
                    loudnessIntensity = intensity
                    loudnessVolumeLinear = volumeLinear
                    if (isNativeDspLoaded) {
                        val key = "$intensity:$volumeLinear"
                        if (lastNativeLoudnessParams != key) {
                            lastNativeLoudnessParams = key
                            try {
                                nativeSetLoudnessContourParams(intensity, volumeLinear)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetLoudnessContourParams failed: ${e.message}")
                            }
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                // ---- Phase 1 DSP expansion: Subwoofer / LFE Crossover ----
                "setSubCrossoverEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isSubCrossoverEnabled = enabled
                    if (isNativeDspLoaded && lastNativeSubCrossoverEnabled != enabled) {
                        lastNativeSubCrossoverEnabled = enabled
                        try {
                            nativeSetSubCrossoverEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetSubCrossoverEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setSubCrossoverParams" -> {
                    val cornerHz = call.argument<Double>("cornerHz") ?: 80.0
                    val slopeDbPerOct = call.argument<Double>("slopeDbPerOct") ?: 24.0
                    val subGain = call.argument<Double>("subGain") ?: 0.8
                    subCrossoverCornerHz = cornerHz
                    subCrossoverSlopeDbPerOct = slopeDbPerOct
                    subCrossoverGain = subGain
                    if (isNativeDspLoaded) {
                        val key = "$cornerHz:$slopeDbPerOct:$subGain"
                        if (lastNativeSubCrossoverParams != key) {
                            lastNativeSubCrossoverParams = key
                            try {
                                nativeSetSubCrossoverParams(cornerHz, slopeDbPerOct, subGain)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetSubCrossoverParams failed: ${e.message}")
                            }
                        }
                    }
                    result.success(true)
                }

                // ---- Phase 1 DSP expansion: Dynamic EQ ----
                "setDynamicEqEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isDynamicEqEnabled = enabled
                    if (isNativeDspLoaded && lastNativeDynamicEqEnabled != enabled) {
                        lastNativeDynamicEqEnabled = enabled
                        try {
                            nativeSetDynamicEqEnabled(enabled)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetDynamicEqEnabled failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setDynamicEqBandCount" -> {
                    val count = call.argument<Int>("count") ?: 1
                    val changed = dynamicEqBandCount != count
                    dynamicEqBandCount = count
                    if (isNativeDspLoaded && changed) {
                        try {
                            nativeSetDynamicEqBandCount(count)
                        } catch (e: Exception) {
                            Log.w(TAG, "nativeSetDynamicEqBandCount failed: ${e.message}")
                        }
                    }
                    recalculateActiveStages()
                    result.success(true)
                }

                "setDynamicEqBand" -> {
                    val index = call.argument<Int>("index") ?: 0
                    val freq = call.argument<Double>("frequency") ?: 1000.0
                    val q = call.argument<Double>("q") ?: 2.0
                    val thresholdDb = call.argument<Double>("thresholdDb") ?: -30.0
                    val ratio = call.argument<Double>("ratio") ?: 3.0
                    val attackMs = call.argument<Double>("attackMs") ?: 5.0
                    val releaseMs = call.argument<Double>("releaseMs") ?: 120.0
                    val maxCutDb = call.argument<Double>("maxCutDb") ?: -12.0
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (isNativeDspLoaded) {
                        val key = "$freq:$q:$thresholdDb:$ratio:$attackMs:$releaseMs:$maxCutDb:$enabled"
                        if (lastNativeDynamicEqBands[index] != key) {
                            lastNativeDynamicEqBands[index] = key
                            try {
                                nativeSetDynamicEqBand(index, freq, q, thresholdDb, ratio, attackMs, releaseMs, maxCutDb, enabled)
                            } catch (e: Exception) {
                                Log.w(TAG, "nativeSetDynamicEqBand failed: ${e.message}")
                            }
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
                        "hasHarmonicSaturation" to isNativeDspLoaded,
                        "hasStereoWidth" to isNativeDspLoaded,
                        "hasLoudnessContour" to isNativeDspLoaded,
                        "hasSubCrossover" to isNativeDspLoaded,
                        "hasDynamicEq" to isNativeDspLoaded,
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

                "setDspPreference" -> {
                    val preference = call.argument<String>("preference") ?: "native"
                    dspPreference = preference
                    recalculateActiveStages()
                    // Do not tear down the Android session EQ here. The native
                    // engine is used by explicit PCM clients, while ExoPlayer's
                    // output reaches the earbuds through this AudioEffect
                    // session. Releasing it made the default "native" setting
                    // silently turn the audible EQ off.
                    if (isEqEnabled || (isDynamicsEnabled && currentDynamicsPreset != "off")) {
                        buildDynamicsProcessing()
                    }
                    result.success(true)
                }

                // The native engine is configured by this plugin but is not
                // yet called from just_audio/ExoPlayer's PCM callback. Report
                // that honestly so Flutter can disable non-audible controls.
                "getProcessingCapabilities" -> {
                    result.success(mapOf("isPcmDspAttached" to false))
                }

                "getDspPreference" -> {
                    result.success(dspPreference)
                }

                "setBypassDspForBitPerfect" -> {
                    val bypass = call.argument<Boolean>("bypass") ?: false
                    synchronized(this) {
                    if (bypass != isBitPerfectBypassActive) {
                        if (bypass) bypassSavedStages = activeDspStages
                        isBitPerfectBypassActive = bypass
                        if (bypass) {
                            // Immediately disable virtualizer/loudness/bass + native stages
                            try { virtualizer?.enabled = false } catch (_: Exception) {}
                            try { loudnessEnhancer?.enabled = false } catch (_: Exception) {}
                            try { bassBoost?.enabled = false } catch (_: Exception) {}
                            try { dynamicsProcessing?.enabled = false } catch (_: Exception) {}
                        } else {
                            try { virtualizer?.enabled = isVirtualizerEnabled } catch (_: Exception) {}
                            try { loudnessEnhancer?.enabled = volumeBoostMilliBels > 0 } catch (_: Exception) {}
                            try { bassBoost?.enabled = bassBoostStrength > 0 } catch (_: Exception) {}
                            try { dynamicsProcessing?.enabled = isEqEnabled || isDynamicsEnabled } catch (_: Exception) {}
                        }
                        recalculateActiveStages()
                    }
                    }
                    result.success(true)
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
        val dp = dynamicsProcessing ?: run {
            buildDynamicsProcessing()
            if (dynamicsProcessing == null) updateLegacyEqualizer()
            return
        }
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
        // A disabled EQ must be inaudible immediately, and an enabled EQ must
        // still work on devices that reject DynamicsProcessing.
        updateLegacyEqualizer()
    }

    private fun updateLegacyEqualizer() {
        if (!isEqEnabled || currentAudioSessionId == 0 || dynamicsProcessing != null) {
            try { legacyEqualizer?.enabled = false } catch (_: Exception) {}
            if (dynamicsProcessing != null) {
                try { legacyEqualizer?.release() } catch (_: Exception) {}
                legacyEqualizer = null
            }
            return
        }
        try {
            val eq = legacyEqualizer ?: Equalizer(0, currentAudioSessionId).also {
                legacyEqualizer = it
            }
            val range = eq.bandLevelRange
            for (band in 0 until eq.numberOfBands.toInt()) {
                val hz = eq.getCenterFreq(band.toShort()) / 1000.0
                val nearest = eqCenterFreqs.indices.minByOrNull {
                    abs(kotlin.math.ln(eqCenterFreqs[it] / hz))
                } ?: 0
                // Equalizer has no independent preamp control. Apply it to
                // every band in the fallback so its response matches the
                // DynamicsProcessing implementation as closely as Android
                // permits.
                val levelMb = ((eqBandGains[nearest] + eqPreampDb) * 100.0).toInt()
                    .coerceIn(range[0].toInt(), range[1].toInt())
                eq.setBandLevel(band.toShort(), levelMb.toShort())
            }
            eq.enabled = true
        } catch (e: Exception) {
            Log.w(TAG, "Platform Equalizer fallback unavailable: ${e.message}")
            try { legacyEqualizer?.release() } catch (_: Exception) {}
            legacyEqualizer = null
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
        updateLegacyEqualizer()
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

    // DynamicsProcessing is unsupported on some devices/emulator audio HALs
    // ("AudioEffect: bad parameter value"). After repeated build failures for
    // the same audio session, stop retrying: each failed construction costs
    // time in the audio path and spams the log on every EQ interaction. The
    // latch resets automatically when the audio session changes.
    private var dpBuildFailures = 0
    private var dpBuildFailureSessionId = 0
    private val dpBuildFailureLimit = 3

    private fun buildDynamicsProcessing() {
        val oldDp = dynamicsProcessing
        dynamicsProcessing = null

        if (currentAudioSessionId == 0) {
            try { oldDp?.release() } catch (_: Exception) {}
            updateLegacyEqualizer()
            return
        }

        val dynamicsActive = isDynamicsEnabled && currentDynamicsPreset != "off"
        if (!isEqEnabled && !dynamicsActive) {
            try { oldDp?.release() } catch (_: Exception) {}
            updateLegacyEqualizer()
            return
        }

        if (dpBuildFailureSessionId != currentAudioSessionId) {
            dpBuildFailures = 0
            dpBuildFailureSessionId = currentAudioSessionId
        }
        if (dpBuildFailures >= dpBuildFailureLimit) {
            try { oldDp?.release() } catch (_: Exception) {}
            updateLegacyEqualizer()
            return
        }

        try {
            val builder = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_TIME_RESOLUTION,
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

            dp.enabled = isEqEnabled || dynamicsActive
            dynamicsProcessing = dp
            updateLegacyEqualizer()
        } catch (e: Exception) {
            dpBuildFailures++
            if (dpBuildFailures == 1 || dpBuildFailures == dpBuildFailureLimit) {
                val suffix =
                    if (dpBuildFailures >= dpBuildFailureLimit) {
                        " - unsupported on this device/session, suppressing further attempts"
                    } else {
                        ""
                    }
                Log.w(TAG, "DynamicsProcessing build failed$suffix: ${e.message}")
            }
            dynamicsProcessing = null
            updateLegacyEqualizer()
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
        try { legacyEqualizer?.release() } catch (_: Exception) {}

        virtualizer = null
        loudnessEnhancer = null
        bassBoost = null
        dynamicsProcessing = null
        legacyEqualizer = null
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

        try {
            legacyEqualizer?.enabled = false
            legacyEqualizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Equalizer fallback cleanup error: ${e.message}")
        }
        legacyEqualizer = null
        cachedSupportedEffects = null
    }

    @Synchronized
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
                monoMix ||
                isSaturationEnabled ||
                isStereoWidthEnabled ||
                isLoudnessContourEnabled ||
                isSubCrossoverEnabled ||
                isDynamicEqEnabled
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
