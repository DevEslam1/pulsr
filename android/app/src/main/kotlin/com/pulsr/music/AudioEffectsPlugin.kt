package com.pulsr.music

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.PresetReverb
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
    // HAL-bound PresetReverb — actually audible via the Android AudioEffect session
    private var halReverb: PresetReverb? = null

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

    /// True only once a real PCM buffer has been pushed through
    /// nativeProcessPcmAudio. The C++ stages (crossfeed, saturation, stereo
    /// width, sub crossover, dynamic EQ, loudness contour) are configured but
    /// NOT audible until then: ExoPlayer provides no PCM callback, so nothing
    /// feeds this engine. Reported to Flutter as hasPcmDspPath.
    @Volatile
    private var isPcmSourceConnected = false
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
    @Volatile private var reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor(
        java.util.concurrent.ThreadFactory { r -> Thread(r, "PulsrReverbDSP") }
    )

    private fun safeReverbExecute(action: () -> Unit) {
        try {
            reverbExecutor.execute { try { action() } catch (_: Exception) {} }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            try {
                // Properly shutdown the old executor before creating a new one
                val oldExecutor = reverbExecutor
                Log.w(TAG, "Reverb executor rejected; shutting down old executor and creating new one")
                oldExecutor.shutdown()
                if (!oldExecutor.awaitTermination(2, java.util.concurrent.TimeUnit.SECONDS)) {
                    Log.w(TAG, "Reverb executor did not terminate in time; forcing shutdown")
                    oldExecutor.shutdownNow()
                }
                
                // Create a new executor with proper thread naming
                reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor(
                    java.util.concurrent.ThreadFactory { r -> Thread(r, "PulsrReverbDSP") }
                )
                reverbExecutor.execute { try { action() } catch (_: Exception) {} }
                Log.i(TAG, "Reverb executor successfully recreated and action executed")
            } catch (ex: Exception) {
                Log.w(TAG, "Reverb executor failed to recover: ${ex.message}", ex)
            }
        } catch (e: Exception) {
            Log.w(TAG, "safeReverbExecute failed: ${e.message}", e)
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
    private external fun nativeProcessPcmAudio(buffer: FloatArray, frames: Int, channels: Int): Int
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
            plugin.initPlugin(context.applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
    private var systemAudioEffectsController: SystemAudioEffectsController? = null

    fun initPlugin(appContext: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
        context = appContext
        systemAudioEffectsController = SystemAudioEffectsController(appContext)
        methodChannel = MethodChannel(messenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        // Recreate executor if previously shut down
        if (reverbExecutor.isShutdown || reverbExecutor.isTerminated) {
            Log.i(TAG, "Reverb executor was shut down; creating fresh instance")
            reverbExecutor = java.util.concurrent.Executors.newSingleThreadExecutor(
                java.util.concurrent.ThreadFactory { r -> Thread(r, "PulsrReverbDSP") }
            )
        }
        configureNativeMemoryBudget(appContext)
        // Prefetch OEM info off main thread
        Thread { try { getCachedOemInfo(appContext) } catch (_: Exception) {} }.start()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null && audioDeviceCallback == null) {
                val callback = object : AudioDeviceCallback() {
                    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                        handleAudioDeviceChange(isAdded = true, devices = addedDevices)
                    }

                    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                        handleAudioDeviceChange(isAdded = false, devices = removedDevices)
                    }
                }
                audioManager.registerAudioDeviceCallback(callback, mainHandler)
                audioDeviceCallback = callback
            }
        }
    }

    private fun handleAudioDeviceChange(isAdded: Boolean, devices: Array<out AudioDeviceInfo>?) {
        val deviceTypes = devices?.map { it.type } ?: emptyList()
        Log.i(TAG, "Audio device route changed (${if (isAdded) "added" else "removed"}): types=$deviceTypes")
        val isBluetooth = deviceTypes.any {
            it == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        // BT A2DP needs 500-600ms to negotiate sink; wired/USB is fast (150ms)
        val delayMs = if (isBluetooth) 600L else 150L

        mainHandler.postDelayed({
            if (currentAudioSessionId != 0 && hasActiveEffects()) {
                Log.i(TAG, "Recreating audio effects on route change (sessionId=$currentAudioSessionId)")
                recreateEffects()
            }
            try {
                methodChannel.invokeMethod("onRouteChanged", mapOf(
                    "isAdded" to isAdded,
                    "deviceTypes" to deviceTypes
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send onRouteChanged to Flutter: ${e.message}")
            }
        }, delayMs)
    }

    private fun isHeadphonesConnected(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        return try {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            devices.any { d ->
                d.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                d.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                d.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                d.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                d.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                d.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                d.type == AudioDeviceInfo.TYPE_HEARING_AID ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && (
                    d.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    d.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                ))
            }
        } catch (_: Exception) {
            false
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        initPlugin(binding.applicationContext, binding.binaryMessenger)
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
        systemAudioEffectsController?.release()
        systemAudioEffectsController = null

        volumeBoostRetryRunnable?.let {
            mainHandler.removeCallbacks(it)
            volumeBoostRetryRunnable = null
        }
        eqUpdateRunnable?.let {
            mainHandler.removeCallbacks(it)
            eqUpdateRunnable = null
        }
        volumeBoostRetryCount = 0
        
        // Properly shutdown reverb executor with timeout
        try {
            Log.i(TAG, "Shutting down reverb executor gracefully")
            reverbExecutor.shutdown()
            if (!reverbExecutor.awaitTermination(3, java.util.concurrent.TimeUnit.SECONDS)) {
                Log.w(TAG, "Reverb executor did not terminate in time; forcing shutdown")
                val remaining = reverbExecutor.shutdownNow()
                if (remaining.isNotEmpty()) {
                    Log.w(TAG, "Forcefully shutdown ${remaining.size} remaining reverb tasks")
                }
            } else {
                Log.i(TAG, "Reverb executor shut down cleanly")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error shutting down reverb executor: ${e.message}", e)
            try { reverbExecutor.shutdownNow() } catch (_: Exception) {}
        }
        
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
                    if (sessionId <= 0) {
                        // 0 = "no session yet". Never bind effects to the
                        // global output mix; keep current state untouched.
                        Log.w(TAG, "Ignoring invalid audio session id: $sessionId")
                        result.success(false)
                    } else {
                        val changed = sessionId != currentAudioSessionId
                        currentAudioSessionId = sessionId
                        if (changed) {
                            // Detach + release every old-session AudioEffect
                            // instance, then recreate the chain bound to the
                            // new session. recreateEffects() rebuilds from the
                            // stored native state; Dart re-pushes the full
                            // effect state right after this call returns.
                            recreateEffects()
                        }
                        // Truthful attachment state: true only when the live
                        // session is set and every HAL effect the current
                        // stage configuration wants actually exists on it.
                        result.success(isEffectPipelineAttached())
                    }
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

                "nativeProcessPcmAudio", "nativeProcessAudio" -> {
                    val buffer = call.argument<FloatArray>("buffer")
                    val frameCount = call.argument<Int>("frameCount") ?: 0
                    val channels = call.argument<Int>("channels") ?: 2
                    if (buffer != null && isNativeDspLoaded) {
                        isPcmSourceConnected = true
                        try {
                            val processed = nativeProcessPcmAudio(buffer, frameCount, channels)
                            result.success(processed)
                        } catch (e: Exception) {
                            result.success(0)
                        }
                    } else {
                        result.success(0)
                    }
                }

                // NOTE: the rich DSP debug report lives further down in this
                // when-block (search for the second "getDspDebugStatus"). It
                // used to be shadowed by a native-only branch here, which made
                // the Signal Inspector always report "Session Detached" and 0
                // active stages. Do not re-add another branch for the same
                // method name: Kotlin `when` executes only the first match.

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
                    // HAL path: wire to DynamicsProcessing limiter stage
                    applyHalLimiter()
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
                    // HAL path: update DynamicsProcessing limiter threshold/release
                    applyHalLimiter()
                    result.success(true)
                }

                // Convolution Reverb — HAL path via EnvironmentalReverb + native C++ (for when PCM path lands)
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
                    applyHalReverb()
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
                    // HAL path: update EnvironmentalReverb preset
                    applyHalReverb()
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
                    // HAL path: update EnvironmentalReverb wet level
                    applyHalReverb()
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

                // Stereo Balance & Mono Mix — HAL path via DynamicsProcessing per-channel inputGain
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
                    applyHalBalanceMono()
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
                    applyHalBalanceMono()
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
                        "hasCrossfeed" to (isNativeDspLoaded && isPcmSourceConnected),
                        "hasLookaheadLimiter" to isNativeDspLoaded,
                        "hasConvolutionReverb" to isNativeDspLoaded,
                        "hasSincResampler" to isNativeDspLoaded,
                        "hasDsdDecoder" to isNativeDspLoaded,
                        "hasHarmonicSaturation" to (isNativeDspLoaded && isPcmSourceConnected),
                        "hasStereoWidth" to (isNativeDspLoaded && isPcmSourceConnected),
                        "hasLoudnessContour" to (isNativeDspLoaded && isPcmSourceConnected),
                        "hasSubCrossover" to (isNativeDspLoaded && isPcmSourceConnected),
                        "hasDynamicEq" to (isNativeDspLoaded && isPcmSourceConnected),
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

                "detectSystemEffects" -> {
                    val controller = systemAudioEffectsController ?: context?.let { SystemAudioEffectsController(it) }
                    result.success(controller?.detect() ?: mapOf("status" to "unsupportedDevice", "detectedBundles" to emptyList<String>(), "hasDolbyOrVendor" to false))
                }

                "setSystemEffectsPolicy" -> {
                    val policy = call.argument<String>("policy") ?: "auto"
                    val isHiResOrBitPerfect = call.argument<Boolean>("isHiResOrBitPerfect") ?: isBitPerfectBypassActive
                    val controller = systemAudioEffectsController ?: context?.let { SystemAudioEffectsController(it) }
                    val status = controller?.applyPolicy(policy, isHiResOrBitPerfect) ?: SystemAudioEffectsController.Status.UNSUPPORTED_DEVICE
                    result.success(mapOf("status" to status.value))
                }

                "getSystemEffectsStatus" -> {
                    val controller = systemAudioEffectsController ?: context?.let { SystemAudioEffectsController(it) }
                    result.success(
                        mapOf(
                            "status" to (controller?.getStatus()?.value ?: "unknown"),
                            "detectedBundles" to (controller?.getDetectedBundles() ?: emptyList<String>())
                        )
                    )
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

                // Truthful pipeline attachment state. The native C++ engine is
                // configured by this plugin but is not called from
                // just_audio/ExoPlayer's PCM callback; the AUDIBLE path is the
                // session-bound AudioEffect chain, so report its health so
                // Flutter can surface genuine detachment.
                "getProcessingCapabilities" -> {
                    result.success(
                        mapOf(
                            "isPcmDspAttached" to isEffectPipelineAttached(),
                            "isSessionAttached" to (currentAudioSessionId != 0),
                            "hasPcmDspPath" to isPcmSourceConnected
                        )
                    )
                }

                "getDspPreference" -> {
                    result.success(dspPreference)
                }

                "getDspDebugStatus" -> {
                    val ctx = context
                    val oemInfo = if (ctx != null) getCachedOemInfo(ctx) else mapOf("hasOemAudio" to false, "detectedEngines" to emptyList<String>())
                    val hasOem = oemInfo["hasOemAudio"] as? Boolean ?: false
                    @Suppress("UNCHECKED_CAST")
                    val oemEngines = oemInfo["detectedEngines"] as? List<String> ?: emptyList()

                    val autoDegraded = if (isNativeDspLoaded) {
                        try { nativeGetAutoDegradedStages() } catch (_: Exception) { 0 }
                    } else 0
                    val halAttached = isEffectPipelineAttached()

                    val stagesList = mutableListOf<Map<String, Any?>>()
                    val activeNames = mutableListOf<String>()

                    // 1. Equalizer (DynamicsProcessing or legacy)
                    val halEqSuppressedForReport = isHalEqSuppressed()
                    val eqActive = isEqEnabled && !isBitPerfectBypassActive && !halEqSuppressedForReport && halAttached
                    if (eqActive) activeNames.add("Graphic Equalizer ($eqBandCount Bands, Preamp: ${String.format("%.1f", eqPreampDb)} dB)")
                    stagesList.add(mapOf(
                        "name" to "Graphic Equalizer",
                        "category" to (if (dynamicsProcessing != null) "Android HAL (DynamicsProcessing)" else if (legacyEqualizer != null) "Android HAL (Legacy Equalizer)" else "Native C++"),
                        "isSupported" to (isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING) || isNativeDspLoaded),
                        "isEnabled" to isEqEnabled,
                        "isBypassed" to (isBitPerfectBypassActive || halEqSuppressedForReport),
                        "isDegraded" to (!halAttached && isEqEnabled && !halEqSuppressedForReport || ((autoDegraded and STAGE_EQ) != 0)),
                        "parameters" to mapOf(
                            "bandCount" to eqBandCount,
                            "preampDb" to eqPreampDb,
                            "isDynamicsProcessingAttached" to (dynamicsProcessing != null),
                            "isLegacyEqualizerAttached" to (legacyEqualizer != null),
                            "isHalEqSuppressedForOem" to halEqSuppressedForReport
                        ),
                        "statusDescription" to when {
                            isBitPerfectBypassActive -> "Bypassed by Bit-Perfect"
                            halEqSuppressedForReport -> "Suppressed (OEM engine active — dspPreference=$dspPreference)"
                            isEqEnabled -> "$eqBandCount Bands Active (Preamp: ${String.format("%.1f", eqPreampDb)} dB)"
                            else -> "Disabled"
                        }
                    ))

                    // 2. Dynamics Processing / Multiband Compressor
                    val dynActive = isDynamicsEnabled && currentDynamicsPreset != "off" && !isBitPerfectBypassActive && halAttached
                    if (dynActive) activeNames.add("Dynamics Processing ($currentDynamicsPreset)")
                    stagesList.add(mapOf(
                        "name" to "Dynamics Processing",
                        "category" to "Android HAL (DynamicsProcessing)",
                        "isSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING),
                        "isEnabled" to isDynamicsEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to (!halAttached && isDynamicsEnabled),
                        "parameters" to mapOf(
                            "preset" to currentDynamicsPreset,
                            "isAttached" to (dynamicsProcessing != null)
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isDynamicsEnabled) "Preset: $currentDynamicsPreset" else "Disabled"
                    ))

                    // 3. Virtualizer / Spatializer
                    val virtActive = isVirtualizerEnabled && virtualizerStrength > 0 && !isBitPerfectBypassActive && halAttached
                    if (virtActive) activeNames.add("Virtualizer (Strength: $virtualizerStrength/1000)")
                    stagesList.add(mapOf(
                        "name" to "Virtualizer / Surround",
                        "category" to "Android HAL (Virtualizer)",
                        "isSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_VIRTUALIZER),
                        "isEnabled" to isVirtualizerEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to (!halAttached && isVirtualizerEnabled),
                        "parameters" to mapOf(
                            "strength" to virtualizerStrength.toInt(),
                            "isAttached" to (virtualizer != null)
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isVirtualizerEnabled) "Strength: ${(virtualizerStrength.toDouble() / 10).toInt()}%" else "Disabled"
                    ))

                    // 4. Bass Boost
                    val bbActive = bassBoostStrength > 0 && !isBitPerfectBypassActive && halAttached
                    if (bbActive) activeNames.add("Bass Boost (Strength: $bassBoostStrength/1000)")
                    stagesList.add(mapOf(
                        "name" to "Bass Boost",
                        "category" to "Android HAL (BassBoost)",
                        "isSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_BASS_BOOST),
                        "isEnabled" to (bassBoostStrength > 0),
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to (!halAttached && bassBoostStrength > 0),
                        "parameters" to mapOf(
                            "strength" to bassBoostStrength.toInt(),
                            "isAttached" to (bassBoost != null)
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (bassBoostStrength > 0) "Strength: ${(bassBoostStrength.toDouble() / 10).toInt()}%" else "Disabled"
                    ))

                    // 5. Loudness Enhancer (Volume Boost)
                    val volActive = volumeBoostMilliBels > 0 && !isBitPerfectBypassActive && halAttached
                    if (volActive) activeNames.add("Volume Boost (+${volumeBoostMilliBels / 100.0} dB)")
                    stagesList.add(mapOf(
                        "name" to "Volume Boost / Loudness Enhancer",
                        "category" to "Android HAL (LoudnessEnhancer)",
                        "isSupported" to isEffectTypeSupported(AudioEffect.EFFECT_TYPE_LOUDNESS_ENHANCER),
                        "isEnabled" to (volumeBoostMilliBels > 0),
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to (!halAttached && volumeBoostMilliBels > 0),
                        "parameters" to mapOf(
                            "targetGainMilliBels" to volumeBoostMilliBels,
                            "gainDb" to (volumeBoostMilliBels / 100.0),
                            "isAttached" to (loudnessEnhancer != null)
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (volumeBoostMilliBels > 0) "+${String.format("%.1f", volumeBoostMilliBels / 100.0)} dB" else "Disabled"
                    ))

                    // 6. Lookahead Limiter (Native C++)
                    val limActive = isLimiterEnabled && !isBitPerfectBypassActive
                    if (limActive) activeNames.add("Lookahead Limiter (Thresh: ${limiterThresholdDb}dB, Lookahead: ${limiterLookaheadMs}ms)")
                    stagesList.add(mapOf(
                        "name" to "True-Peak Lookahead Limiter",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isLimiterEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_LIMITER) != 0),
                        "parameters" to mapOf(
                            "thresholdDb" to limiterThresholdDb,
                            "lookaheadMs" to limiterLookaheadMs,
                            "releaseMs" to limiterReleaseMs
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isLimiterEnabled) "Threshold: ${limiterThresholdDb} dB, Lookahead: ${limiterLookaheadMs} ms" else "Disabled"
                    ))

                    // 7. Convolution Reverb (Native C++)
                    val revActive = isReverbEnabled && !isBitPerfectBypassActive
                    if (revActive) activeNames.add("Convolution Reverb (Preset #$reverbPreset, Wet: ${(reverbWetDry * 100).toInt()}%)")
                    stagesList.add(mapOf(
                        "name" to "Convolution Reverb",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isReverbEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_REVERB) != 0),
                        "parameters" to mapOf(
                            "preset" to reverbPreset,
                            "wetDryRatio" to reverbWetDry.toDouble()
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isReverbEnabled) "Preset #$reverbPreset (${(reverbWetDry * 100).toInt()}% Wet)" else "Disabled"
                    ))

                    // 8. Crossfeed BS2B (Native C++)
                    val cfActive = isCrossfeedEnabled && !isBitPerfectBypassActive
                    if (cfActive) activeNames.add("Bauer Crossfeed (${crossfeedDelayUs}µs, ${crossfeedFeedDb}dB)")
                    stagesList.add(mapOf(
                        "name" to "Bauer Binaural Crossfeed",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isCrossfeedEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_CROSSFEED) != 0),
                        "parameters" to mapOf(
                            "delayUs" to crossfeedDelayUs,
                            "feedDb" to crossfeedFeedDb
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isCrossfeedEnabled) "Delay: ${crossfeedDelayUs} µs, Feed: ${crossfeedFeedDb} dB" else "Disabled"
                    ))

                    // 9. Harmonic Saturation (Native C++)
                    val satActive = isSaturationEnabled && !isBitPerfectBypassActive
                    if (satActive) activeNames.add("Harmonic Saturation (Drive: ${(saturationDrive * 100).toInt()}%)")
                    stagesList.add(mapOf(
                        "name" to "Harmonic Saturation (Tanh Exciter)",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isSaturationEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_SATURATION) != 0),
                        "parameters" to mapOf(
                            "drive" to saturationDrive,
                            "mix" to saturationMix
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isSaturationEnabled) "Drive: ${(saturationDrive * 100).toInt()}%, Mix: ${(saturationMix * 100).toInt()}%" else "Disabled"
                    ))

                    // 10. Stereo Width (Native C++)
                    val swActive = isStereoWidthEnabled && !isBitPerfectBypassActive
                    if (swActive) activeNames.add("Stereo Width (M/S: ${(stereoWidth * 100).toInt()}%)")
                    stagesList.add(mapOf(
                        "name" to "Stereo Width (Mid/Side)",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isStereoWidthEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_WIDTH) != 0),
                        "parameters" to mapOf(
                            "width" to stereoWidth
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isStereoWidthEnabled) "Width: ${(stereoWidth * 100).toInt()}%" else "Disabled"
                    ))

                    // 11. Dynamic EQ (Native C++)
                    val deqActive = isDynamicEqEnabled && dynamicEqBandCount > 0 && !isBitPerfectBypassActive
                    if (deqActive) activeNames.add("Dynamic EQ ($dynamicEqBandCount Bands)")
                    stagesList.add(mapOf(
                        "name" to "Dynamic Parametric EQ",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isDynamicEqEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_DYNEQ) != 0),
                        "parameters" to mapOf(
                            "bandCount" to dynamicEqBandCount
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isDynamicEqEnabled) "$dynamicEqBandCount Dynamic Bands" else "Disabled"
                    ))

                    // 12. Sub Crossover (Native C++)
                    val subActive = isSubCrossoverEnabled && !isBitPerfectBypassActive
                    if (subActive) activeNames.add("Sub Crossover (${subCrossoverCornerHz.toInt()} Hz)")
                    stagesList.add(mapOf(
                        "name" to "Subwoofer Crossover",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isSubCrossoverEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_CROSSOVER) != 0),
                        "parameters" to mapOf(
                            "cornerHz" to subCrossoverCornerHz
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isSubCrossoverEnabled) "Cutoff: ${subCrossoverCornerHz.toInt()} Hz" else "Disabled"
                    ))

                    // 13. Loudness Contour (Native C++)
                    val lcActive = isLoudnessContourEnabled && loudnessIntensity > 0.001 && !isBitPerfectBypassActive
                    if (lcActive) activeNames.add("Loudness Contour (${(loudnessIntensity * 100).toInt()}%)")
                    stagesList.add(mapOf(
                        "name" to "Equal-Loudness Contour (Fletcher-Munson)",
                        "category" to "Native C++ Engine",
                        "isSupported" to isNativeDspLoaded,
                        "isEnabled" to isLoudnessContourEnabled,
                        "isBypassed" to isBitPerfectBypassActive,
                        "isDegraded" to ((autoDegraded and STAGE_LOUDNESS) != 0),
                        "parameters" to mapOf(
                            "intensity" to loudnessIntensity
                        ),
                        "statusDescription" to if (isBitPerfectBypassActive) "Bypassed by Bit-Perfect" else if (isLoudnessContourEnabled) "Intensity: ${(loudnessIntensity * 100).toInt()}%" else "Disabled"
                    ))

                    val nativeAppliedSampleRate = if (isNativeDspLoaded) {
                        try { nativeGetAppliedSampleRate() } catch (_: Exception) { 0.0 }
                    } else 0.0
                    val nativeLastAppliedGeneration = if (isNativeDspLoaded) {
                        try { nativeGetLastAppliedGeneration() } catch (_: Exception) { 0 }
                    } else 0
                    val nativePublishedGeneration = if (isNativeDspLoaded) {
                        try { nativeGetPublishedGeneration() } catch (_: Exception) { 0 }
                    } else 0

                    val report = mapOf(
                        "audioSessionId" to currentAudioSessionId,
                        // Truthful: only attached when the HAL chain for the
                        // current stage configuration exists on a live session.
                        "isSessionAttached" to isEffectPipelineAttached(),
                        "dspPreference" to dspPreference,
                        "isBitPerfectBypassActive" to isBitPerfectBypassActive,
                        "isNativeDspLoaded" to isNativeDspLoaded,
                        "appliedSampleRate" to nativeAppliedSampleRate,
                        "lastAppliedGeneration" to nativeLastAppliedGeneration,
                        "publishedGeneration" to nativePublishedGeneration,
                        "activeDspStagesMask" to activeDspStages,
                        "autoDegradedStagesMask" to autoDegraded,
                        "hasOemAudio" to hasOem,
                        "detectedOemEngines" to oemEngines,
                        "stages" to stagesList,
                        "activeEffectNames" to activeNames
                    )
                    Log.d(TAG, "[DSP_DEBUG] Live DSP snapshot requested: ${activeNames.size} active effects, session=$currentAudioSessionId, attached=${report["isSessionAttached"]}, bypass=$isBitPerfectBypassActive")
                    result.success(report)
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
                applyVirtualizerMode()
            } catch (e: Exception) {
                Log.w(TAG, "Virtualizer initialization failed: ${e.message}")
            }
        }
    }

    private fun applyVirtualizerMode() {
        val v = virtualizer ?: return
        try {
            val isHeadphones = isHeadphonesConnected()
            val desiredMode = if (isHeadphones) {
                Virtualizer.VIRTUALIZATION_MODE_BINAURAL
            } else {
                Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL
            }
            if (v.canVirtualize(android.media.AudioFormat.CHANNEL_OUT_STEREO, desiredMode)) {
                v.forceVirtualizationMode(desiredMode)
                Log.d(TAG, "Applied virtualization mode: ${if (isHeadphones) "BINAURAL (earpods/headphones)" else "TRANSAURAL (speaker)"}")
            }
        } catch (e: Exception) {
            Log.d(TAG, "forceVirtualizationMode ignored/unsupported: ${e.message}")
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
            // Ensure DP stays enabled if limiter is active even when EQ is toggled off
            val dynamicsActive = isDynamicsEnabled && currentDynamicsPreset != "off"
            try { dp.enabled = isEqEnabled || dynamicsActive || isLimiterEnabled } catch (_: Exception) {}
        } else {
            buildDynamicsProcessing()
        }
        // A disabled EQ must be inaudible immediately, and an enabled EQ must
        // still work on devices that reject DynamicsProcessing.
        updateLegacyEqualizer()
    }

    private fun updateLegacyEqualizer() {
        val halEqSuppressed = isHalEqSuppressed()
        if (!isEqEnabled || halEqSuppressed || currentAudioSessionId == 0 || dynamicsProcessing != null) {
            try { legacyEqualizer?.enabled = false } catch (_: Exception) {}
            if (dynamicsProcessing != null || halEqSuppressed) {
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

    /**
     * Returns true when the session-bound HAL EQ (DynamicsProcessing postEq / legacy
     * Equalizer) should be suppressed to avoid double-processing through a system-level
     * OEM audio engine (Dolby, Dirac, SoundAlive, etc.).
     *
     * "oem"  → always suppress, user explicitly chose to defer to the OEM engine.
     * "auto" → suppress only when an OEM audio package is actually present; fall back
     *          to native/HAL processing on clean ROMs.
     * "native" → never suppress (default).
     *
     * Note: HAL limiter and balance/mono are NOT suppressed — they don't process the
     * frequency spectrum and therefore don't interact adversely with Dolby-style engines.
     */
    private fun isHalEqSuppressed(): Boolean {
        return when (dspPreference) {
            "oem" -> true
            "auto" -> {
                val ctx = context ?: return false
                getCachedOemInfo(ctx)["hasOemAudio"] as? Boolean ?: false
            }
            else -> false
        }
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
        val needsBalanceMono = monoMix || kotlin.math.abs(stereoBalance) > 0.001
        // When dspPreference is "oem" (or "auto" + OEM detected), suppress the HAL
        // graphic EQ to avoid double-processing through Dolby / Dirac / SoundAlive.
        // Limiter and balance/mono still run through DP — they don't colour the
        // frequency spectrum and are safe alongside system-level OEM engines.
        val halEqSuppressed = isHalEqSuppressed()
        val effectiveEqEnabled = isEqEnabled && !halEqSuppressed
        if (halEqSuppressed && isEqEnabled) {
            Log.i(TAG, "buildDynamicsProcessing: HAL EQ suppressed (dspPreference=$dspPreference) — avoiding double-process with OEM audio engine")
        }
        // Build DynamicsProcessing whenever EQ, dynamics, limiter, or balance/mono are active.
        // Limiter and balance/mono route through the same DynamicsProcessing engine.
        if (!effectiveEqEnabled && !dynamicsActive && !isLimiterEnabled && !needsBalanceMono) {
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
                true,  // postEq — 10-band graphic EQ (may be suppressed for OEM)
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

            // Enable the engine whenever any stage is active (EQ, dynamics, or limiter).
            // Use effectiveEqEnabled so OEM-suppressed EQ doesn't keep DP enabled unnecessarily.
            dp.enabled = effectiveEqEnabled || dynamicsActive || isLimiterEnabled
            dynamicsProcessing = dp
            updateLegacyEqualizer()
            // Wire HAL limiter and balance/mono into the freshly-built DP instance
            applyHalLimiter()
            applyHalBalanceMono()
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
        try { halReverb?.release() } catch (_: Exception) {}

        virtualizer = null
        loudnessEnhancer = null
        bassBoost = null
        dynamicsProcessing = null
        legacyEqualizer = null
        halReverb = null
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
        // Reattach HAL-side effects after session recreate
        applyHalReverb()
        applyHalLimiter()
        applyHalBalanceMono()
    }

    /**
     * Truthful attachment state of the session-bound AudioEffect chain:
     *  - no live session (id 0) -> false;
     *  - no HAL stage requested -> true (nothing to attach);
     *  - otherwise at least one requested HAL effect must exist on the live
     *    session. Creation success is verified via AudioEffect.getId(), which
     *    throws IllegalStateException for effects that failed to construct or
     *    went DEAD; released instances are always nulled out, so non-null plus
     *    a queryable id on the live session is the strongest public-API check.
     */
    private fun isEffectPipelineAttached(): Boolean {
        if (currentAudioSessionId == 0) return false
        val wantsAnyHalStage = isEqEnabled ||
                (isDynamicsEnabled && currentDynamicsPreset != "off") ||
                isVirtualizerEnabled ||
                virtualizerStrength > 0 ||
                volumeBoostMilliBels > 0 ||
                bassBoostStrength > 0 ||
                isReverbEnabled ||
                isLimiterEnabled
        if (!wantsAnyHalStage) return true

        fun healthy(effect: AudioEffect?): Boolean {
            if (effect == null) return false
            return try {
                // AudioEffect.getId() returns the effect's own opaque handle —
                // NOT the session ID. We simply call it: if the effect is
                // dead / released Android throws IllegalStateException, which
                // we catch to signal "not healthy". Any non-throwing return
                // means the effect is alive on the current session.
                effect.id
                true
            } catch (_: Exception) {
                false
            }
        }
        return healthy(dynamicsProcessing) ||
                healthy(legacyEqualizer) ||
                healthy(virtualizer) ||
                healthy(loudnessEnhancer) ||
                healthy(bassBoost) ||
                (halReverb?.let { try { it.id; true } catch (_: Exception) { false } } ?: false)
    }

    // -------------------------------------------------------------------------
    // HAL-bound effect helpers — these create/update Android AudioEffect objects
    // that ARE in the audio session path (audible, unlike the native C++ engine
    // which requires a PCM callback that ExoPlayer does not currently provide).
    // -------------------------------------------------------------------------

    /**
     * Creates or updates the session-bound [PresetReverb] with the current
     * preset mapping. Preset mapping:
     *   0 = Studio Room, 1 = Concert Hall, 2 = Warm Tube (Plate), 3 = Plate, 4 = Custom IR
     * We map to the closest Android PresetReverb preset.
     * Note: PresetReverb does not expose a wet/dry control — reverb is on/off
     * via enabled flag. Wet level control would require EnvironmentalReverb
     * with manual parameter tuning per device, which is fragile.
     */
    private fun applyHalReverb() {
        if (currentAudioSessionId == 0) return
        if (!isReverbEnabled) {
            try { halReverb?.enabled = false } catch (_: Exception) {}
            return
        }
        try {
            val reverb = halReverb ?: PresetReverb(0, currentAudioSessionId).also {
                halReverb = it
            }
            // Map our 0-4 preset index to Android's PresetReverb presets
            val androidPreset: Short = when (reverbPreset) {
                0 -> PresetReverb.PRESET_SMALLROOM   // Studio Room
                1 -> PresetReverb.PRESET_LARGEHALL   // Concert Hall
                2 -> PresetReverb.PRESET_PLATE       // Warm Tube → Plate
                3 -> PresetReverb.PRESET_PLATE       // Plate
                else -> PresetReverb.PRESET_SMALLROOM
            }
            reverb.preset = androidPreset
            reverb.enabled = true
            Log.d(TAG, "HAL reverb applied: preset=$reverbPreset androidPreset=$androidPreset")
        } catch (e: Exception) {
            Log.w(TAG, "applyHalReverb failed: ${e.message}")
            try { halReverb?.release() } catch (_: Exception) {}
            halReverb = null
        }
    }

    /**
     * Wires the user's limiter threshold/release/attack into the
     * [DynamicsProcessing] limiter stage. This means the limiter is audible
     * even without a dynamics preset active. When [isLimiterEnabled] is false
     * the limiter stage is disabled (passthrough).
     */
    private fun applyHalLimiter() {
        val dp = dynamicsProcessing ?: run {
            // If DynamicsProcessing doesn't exist yet, rebuild it — it will
            // call applyHalLimiter internally via buildDynamicsProcessing.
            if (isLimiterEnabled) buildDynamicsProcessing()
            return
        }
        try {
            val preampDb = if (isEqEnabled) eqPreampDb.toFloat() else 0f
            val baseGain = if (isDynamicsEnabled && currentDynamicsPreset != "off") {
                DYNAMICS_PRESETS[currentDynamicsPreset]?.limiter?.postGain ?: 0f
            } else 0f
            for (ch in 0 until CHANNEL_COUNT) {
                val limiter = dp.getLimiterByChannelIndex(ch)
                if (isLimiterEnabled) {
                    // Map lookahead (ms) → attack time (ms). EnvironmentalReverb
                    // has no lookahead; DynamicsProcessing.Limiter uses attackTime.
                    limiter.attackTime = limiterLookaheadMs.toFloat().coerceIn(0.1f, 50f)
                    limiter.releaseTime = limiterReleaseMs.toFloat().coerceIn(10f, 2000f)
                    limiter.ratio = 20f           // Effectively brickwall
                    limiter.threshold = limiterThresholdDb.toFloat().coerceIn(-60f, 0f)
                    limiter.postGain = baseGain + preampDb
                    limiter.isEnabled = true
                } else {
                    limiter.isEnabled = false
                    limiter.postGain = baseGain + preampDb
                }
            }
            Log.d(TAG, "HAL limiter applied: enabled=$isLimiterEnabled threshold=${limiterThresholdDb}dB attack=${limiterLookaheadMs}ms")
        } catch (e: Exception) {
            Log.w(TAG, "applyHalLimiter failed: ${e.message}")
        }
    }

    /**
     * Applies stereo balance and mono-mix via [DynamicsProcessing] per-channel
     * inputGain. Balance -1.0 = full left, 0.0 = center, +1.0 = full right.
     * Uses DynamicsProcessing.getChannelByChannelIndex() + setChannelTo() for
     * real-time gain update on the live session.
     */
    private fun applyHalBalanceMono() {
        val dp = dynamicsProcessing ?: run {
            // Rebuild will call this helper after the DP is created
            if (monoMix || kotlin.math.abs(stereoBalance) > 0.001) buildDynamicsProcessing()
            return
        }
        try {
            if (monoMix) {
                // Both channels at 0 dB inputGain — downstream mixing creates mono
                for (ch in 0 until CHANNEL_COUNT) {
                    val channel = dp.getChannelByChannelIndex(ch)
                    channel.inputGain = 0f
                    dp.setChannelTo(ch, channel)
                }
            } else {
                // Stereo balance: attenuate one channel. balance in [-1, +1]
                // Left = ch 0, Right = ch 1
                val bal = stereoBalance.toFloat().coerceIn(-1f, 1f)
                // At balance=0: L=0dB, R=0dB. At balance=+1: L=-60dB (near silence), R=0dB
                val leftGainDb = if (bal >= 0f) (-60f * bal) else 0f
                val rightGainDb = if (bal <= 0f) (60f * bal) else 0f
                val leftCh = dp.getChannelByChannelIndex(0)
                leftCh.inputGain = leftGainDb
                dp.setChannelTo(0, leftCh)
                val rightCh = dp.getChannelByChannelIndex(1)
                rightCh.inputGain = rightGainDb
                dp.setChannelTo(1, rightCh)
            }
            Log.d(TAG, "HAL balance applied: balance=$stereoBalance mono=$monoMix")
        } catch (e: Exception) {
            Log.w(TAG, "applyHalBalanceMono failed: ${e.message}")
        }
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
            Log.i(TAG, "DynamicsProcessing released successfully")
        } catch (e: Exception) {
            Log.w(TAG, "DynamicsProcessing cleanup error: ${e.message}. Effect may still be attached to session!", e)
        }
        dynamicsProcessing = null

        try {
            legacyEqualizer?.enabled = false
            legacyEqualizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Equalizer fallback cleanup error: ${e.message}")
        }
        legacyEqualizer = null

        try {
            halReverb?.enabled = false
            halReverb?.release()
        } catch (e: Exception) {
            Log.w(TAG, "HAL EnvironmentalReverb cleanup error: ${e.message}")
        }
        halReverb = null

        cachedSupportedEffects = null
        // Full reset: clear the parameter dedup caches so a subsequent
        // re-attach re-pushes every value to the recreated effects / C++
        // engine instead of being filtered out as a duplicate, and re-arm the
        // DynamicsProcessing build-failure latch for the next session.
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
        dpBuildFailures = 0
        dpBuildFailureSessionId = 0
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
