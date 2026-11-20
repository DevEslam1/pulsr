package com.pulsr.music

/**
 * Kotlin mirror of `lib/data/audio/dsp_param_ranges.dart` (DspParamRanges) and of
 * `android/app/src/main/cpp/DspParamRanges.h`.
 *
 * Item 4 of the DSP contract: before this object every layer re-clamped the same
 * parameter with its own literals — the limiter threshold stopped at -30 dB here
 * while the native contract accepted -60, the dynamic EQ cut/boost was -24..24 in
 * C++ but -48..48 in the sanitizer, and the dose threshold was capped at 10 in
 * JNI, 100 here and 0.1..100 in the sanitizer. Whichever layer was narrowest
 * silently won, so the DSP inspector could report a value the engine never ran.
 *
 * Rules (identical to the Dart table):
 *  - [Range.min]/[Range.max] must be accepted verbatim by SanitizeSnapshot and by
 *    the owning native stage.
 *  - A non-finite input takes [Range.defaultValue].
 *  - `DspParamRangesContractTest` parses the Dart file and fails if any number
 *    here drifts from it.
 */
internal object DspParamRanges {

    data class Range(val min: Double, val max: Double, val defaultValue: Double) {
        /** NaN/Inf -> [defaultValue], then clamp into [min]..[max]. */
        fun clamp(value: Double): Double {
            if (!value.isFinite()) return defaultValue
            return value.coerceIn(min, max)
        }
    }

    // --- Parametric EQ -----------------------------------------------------
    /** User-facing graphic-band gain (native accepts ±30, UI offers ±15). */
    val eqBandGainDb = Range(-15.0, 15.0, 0.0)

    /** Manual EQ preamp (native accepts -60..24, UI offers ±15). */
    val preampDb = Range(-15.0, 15.0, 0.0)

    /** Parametric band centre frequency (headphone-profile PEQ import). */
    val eqFilterFrequencyHz = Range(10.0, 24000.0, 1000.0)
    val eqFilterGainDb = Range(-24.0, 24.0, 0.0)
    val eqFilterQ = Range(0.05, 30.0, 1.414)

    // --- Crossfeed ---------------------------------------------------------
    // The native stage can delay 50..2000 us; the custom panel offers 200..700,
    // and that narrower product range is the contract.
    val crossfeedDelayUs = Range(200.0, 700.0, 350.0)
    val crossfeedFeedDb = Range(-15.0, -6.0, -9.0)
    val crossfeedFcut = Range(200.0, 2000.0, 650.0)

    // --- Lookahead limiter -------------------------------------------------
    val limiterThresholdDb = Range(-60.0, 0.0, -0.2)
    val limiterReleaseMs = Range(1.0, 1000.0, 50.0)
    val limiterLookaheadMs = Range(0.0, 20.0, 5.0)

    // --- Visual compressor / multiband band knobs --------------------------
    val compressorRatio = Range(1.0, 20.0, 3.0)
    val compressorAttackMs = Range(0.1, 200.0, 15.0)
    val compressorMakeupGainDb = Range(0.0, 24.0, 0.0)

    val multibandThresholdDb = Range(-60.0, 0.0, -18.0)
    val multibandRatio = Range(1.0, 20.0, 2.0)
    val multibandAttackMs = Range(0.1, 200.0, 15.0)
    val multibandReleaseMs = Range(5.0, 1000.0, 100.0)
    val multibandKneeDb = Range(0.0, 12.0, 3.0)

    /** Deliberately non-negative: attenuation belongs to the EQ preamp. */
    val multibandMakeupGainDb = Range(0.0, 24.0, 0.0)

    // --- Sub crossover -----------------------------------------------------
    /** Bass-management corner; the stage accepts 20..500, the UI offers 60..150. */
    val subCrossoverCornerHz = Range(60.0, 150.0, 80.0)
    val subCrossoverGain = Range(0.0, 1.0, 0.8)

    // --- Multichannel LFE crossover & ChannelManager -----------------------
    val lfeCrossoverHz = Range(40.0, 200.0, 80.0)
    val lfeLowPassHz = Range(60.0, 250.0, 120.0)
    val lfeGainDb = Range(-12.0, 12.0, 0.0)
    val channelManagerTrimDb = Range(-30.0, 12.0, 0.0)
    val channelManagerDelayMs = Range(0.0, 50.0, 0.0)

    // --- Dynamic EQ --------------------------------------------------------
    val dynamicEqFrequencyHz = Range(20.0, 20000.0, 1000.0)
    val dynamicEqQ = Range(0.1, 20.0, 2.0)
    val dynamicEqThresholdDb = Range(-80.0, 0.0, -30.0)
    val dynamicEqRatio = Range(1.0, 20.0, 3.0)
    val dynamicEqAttackMs = Range(0.1, 200.0, 5.0)
    val dynamicEqReleaseMs = Range(5.0, 2000.0, 120.0)
    val dynamicEqMaxCutDb = Range(-48.0, 0.0, -12.0)
    val dynamicEqMaxBoostDb = Range(0.0, 48.0, 12.0)

    // --- Headphone safety --------------------------------------------------
    val safetyDoseThreshold = Range(0.1, 100.0, 1.0)
    val safetyCeilingDb = Range(-40.0, 0.0, -6.0)

    // --- Bit-perfect / dither ---------------------------------------------
    val directUsbGain = Range(0.0, 1.0, 1.0)

    /** Dither exists only for integer PCM depths; anything else means 16. */
    val ditherBitDepths = intArrayOf(16, 24, 32)

    fun normalizeDitherBitDepth(value: Int): Int =
        if (value == 16 || value == 24 || value == 32) value else 16

    /**
     * Flattened view for [DspParamRangesContractTest]: every name that must be
     * numerically identical to the Dart table.
     */
    val shared: Map<String, Range> = mapOf(
        "eqBandGainDb" to eqBandGainDb,
        "preampDb" to preampDb,
        "eqFilterFrequencyHz" to eqFilterFrequencyHz,
        "eqFilterGainDb" to eqFilterGainDb,
        "eqFilterQ" to eqFilterQ,
        "crossfeedDelayUs" to crossfeedDelayUs,
        "crossfeedFeedDb" to crossfeedFeedDb,
        "crossfeedFcut" to crossfeedFcut,
        "limiterThresholdDb" to limiterThresholdDb,
        "limiterReleaseMs" to limiterReleaseMs,
        "limiterLookaheadMs" to limiterLookaheadMs,
        "compressorRatio" to compressorRatio,
        "compressorAttackMs" to compressorAttackMs,
        "compressorMakeupGainDb" to compressorMakeupGainDb,
        "multibandThresholdDb" to multibandThresholdDb,
        "multibandRatio" to multibandRatio,
        "multibandAttackMs" to multibandAttackMs,
        "multibandReleaseMs" to multibandReleaseMs,
        "multibandKneeDb" to multibandKneeDb,
        "multibandMakeupGainDb" to multibandMakeupGainDb,
        "subCrossoverCornerHz" to subCrossoverCornerHz,
        "subCrossoverGain" to subCrossoverGain,
        "lfeCrossoverHz" to lfeCrossoverHz,
        "lfeLowPassHz" to lfeLowPassHz,
        "lfeGainDb" to lfeGainDb,
        "channelManagerTrimDb" to channelManagerTrimDb,
        "channelManagerDelayMs" to channelManagerDelayMs,
        "dynamicEqFrequencyHz" to dynamicEqFrequencyHz,
        "dynamicEqQ" to dynamicEqQ,
        "dynamicEqThresholdDb" to dynamicEqThresholdDb,
        "dynamicEqRatio" to dynamicEqRatio,
        "dynamicEqAttackMs" to dynamicEqAttackMs,
        "dynamicEqReleaseMs" to dynamicEqReleaseMs,
        "dynamicEqMaxCutDb" to dynamicEqMaxCutDb,
        "dynamicEqMaxBoostDb" to dynamicEqMaxBoostDb,
        "safetyDoseThreshold" to safetyDoseThreshold,
        "safetyCeilingDb" to safetyCeilingDb,
        "directUsbGain" to directUsbGain,
    )
}
