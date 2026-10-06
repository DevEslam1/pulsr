// lib/data/audio/dsp_param_ranges.dart

/// Single source of truth for every DSP parameter's valid range, plus the
/// NaN/Inf-safe clamp helpers the setters use to sanitize incoming values.
///
/// Before this file, each range (min/max + the fallback used when the incoming
/// value is non-finite) was hard-coded inline across the equalizer setters, so
/// the same magic numbers were duplicated — and could silently drift — between
/// [EqualizerManager] (equalizer_manager.dart) and its `part` files. Centralize
/// them here so there is exactly one place to read and change a range.
///
/// IMPORTANT: these ranges must stay numerically identical to what the native
/// engine accepts. They mirror the sanitizers / defaults declared in
/// `android/app/src/main/cpp/DspParams.h` (and the per-stage C++ setters). This
/// is a de-duplication of the existing Dart clamps, NOT a range change — any
/// edit here changes behaviour on both the Dart and (expected) native side and
/// must be made in lockstep with DspParams.h.
library;

/// NaN/Inf-safe clamp. Coerces a non-finite [value] (NaN or ±infinity) to
/// [fallback] (or [min] when no fallback is given), then clamps into
/// [min]..[max]. Dart's `num.clamp` propagates NaN (`clamp(NaN, lo, hi) == NaN`)
/// and happily returns ±infinity, so numeric setters must finite-guard the
/// incoming argument before clamping or garbage reaches native. Mirrors
/// `clampFinite` on the native side (DspParams.h / AudioDspEngine sanitizers).
double clampFinite(double value, double min, double max, {double? fallback}) =>
    (value.isFinite ? value : (fallback ?? min)).clamp(min, max).toDouble();

/// A validated numeric range for one double-valued DSP parameter.
class DspRange {
  /// Inclusive lower bound.
  final double min;

  /// Inclusive upper bound.
  final double max;

  /// Value substituted for a non-finite input before clamping (also the
  /// neutral/engine default for the parameter).
  final double defaultValue;

  const DspRange(this.min, this.max, {this.defaultValue = 0.0});

  /// Finite-guards [value] (NaN/Inf -> [defaultValue]) then clamps into range.
  /// Use at setters that previously called `_clampFinite(v, min, max, fb)`.
  double clamp(double value) =>
      clampFinite(value, min, max, fallback: defaultValue);

  /// Plain clamp with NO finite guard — bit-for-bit equivalent to the inline
  /// `value.clamp(min, max)` it replaces (NaN passes through unchanged). Use
  /// at sites that historically did a bare `.clamp()` without a finite guard,
  /// to keep behaviour numerically identical.
  double clampRaw(double value) => value.clamp(min, max).toDouble();
}

/// A validated integer range for one int-valued DSP parameter (modes, presets,
/// band counts). Integers are always finite, so no NaN guard is needed.
class DspIntRange {
  final int min;
  final int max;
  final int defaultValue;

  const DspIntRange(this.min, this.max, {this.defaultValue = 0});

  int clamp(int value) => value.clamp(min, max);
}

/// The DSP parameter range contract. Grouped by stage; the comments cite the
/// matching struct/field in `android/app/src/main/cpp/DspParams.h`.
abstract final class DspParamRanges {
  // --- Parametric EQ ---------------------------------------------------------
  /// Per-band graphic-EQ gain. App/UI range (DspParams.h EqBandParam.gainDb has
  /// no hard bound; Dart clamps the user-facing graphic bands to ±15 dB).
  static const DspRange eqBandGainDb = DspRange(-15.0, 15.0);

  /// Manual EQ preamp. App/UI range (EqParamSet.preampDb, Dart-clamped ±15 dB).
  static const DspRange preampDb = DspRange(-15.0, 15.0);

  /// Parametric-filter centre frequency (headphone-profile PEQ import).
  static const DspRange eqFilterFrequencyHz =
      DspRange(10.0, 24000.0, defaultValue: 1000.0);

  /// Parametric-filter gain (headphone-profile PEQ import).
  static const DspRange eqFilterGainDb = DspRange(-24.0, 24.0);

  /// Parametric-filter Q (headphone-profile PEQ import). defaultValue is the
  /// Butterworth Q used when the profile omits a finite positive Q. Bounds match
  /// the native ParametricEQ clamp (0.05..30).
  static const DspRange eqFilterQ = DspRange(0.05, 30.0, defaultValue: 1.414);

  // --- Virtualizer -----------------------------------------------------------
  static const DspRange virtualizerStrength = DspRange(0.0, 1.0);

  // --- Crossfeed (DspParams.h CrossfeedParamSet) -----------------------------
  static const DspRange crossfeedDelayUs =
      DspRange(200.0, 700.0, defaultValue: 350.0);
  static const DspRange crossfeedFeedDb =
      DspRange(-15.0, -6.0, defaultValue: -9.0);
  static const DspRange crossfeedFcut =
      DspRange(200.0, 2000.0, defaultValue: 650.0);

  /// 0=Bs2bDefault, 1=Bs2bChuMoy, 2=Bs2bJanMeier, 3=Custom (CrossfeedMode).
  static const DspIntRange crossfeedMode = DspIntRange(0, 3);

  // --- Lookahead limiter (DspParams.h LimiterParamSet) -----------------------
  static const DspRange limiterThresholdDb =
      DspRange(-60.0, 0.0, defaultValue: -0.2);
  static const DspRange limiterReleaseMs =
      DspRange(1.0, 1000.0, defaultValue: 50.0);
  static const DspRange limiterLookaheadMs =
      DspRange(0.0, 20.0, defaultValue: 5.0);

  // --- Visual compressor knobs (HAL DynamicsProcessing / MultibandBandParam) -
  static const DspRange compressorRatio =
      DspRange(1.0, 20.0, defaultValue: 3.0);
  static const DspRange compressorAttackMs =
      DspRange(0.1, 200.0, defaultValue: 15.0);
  static const DspRange compressorMakeupGainDb = DspRange(0.0, 24.0);

  // --- Convolution reverb (DspParams.h ReverbParamSet) -----------------------
  static const DspRange reverbWetDry = DspRange(0.0, 1.0, defaultValue: 0.20);
  static const DspRange reverbPredelayMs = DspRange(0.0, 150.0);
  static const DspRange reverbDamping = DspRange(0.0, 1.0, defaultValue: 0.5);
  static const DspRange reverbCrossChannel = DspRange(0.0, 1.0);

  // --- Panner (DspParams.h PannerParamSet) -----------------------------------
  static const DspRange stereoBalance = DspRange(-1.0, 1.0);

  // --- Volume boost (0..1 -> 0..1000 mB) -------------------------------------
  static const DspRange volumeBoost = DspRange(0.0, 1.0);

  // --- Harmonic saturation (DspParams.h SaturationParamSet) ------------------
  static const DspRange saturationDrive = DspRange(0.0, 1.0, defaultValue: 0.3);
  static const DspRange saturationMix = DspRange(0.0, 1.0, defaultValue: 0.5);
  static const DspRange saturationTilt = DspRange(0.0, 1.0, defaultValue: 0.3);

  /// 0=Tape, 1=Tube, 2=Analog Class-A.
  static const DspIntRange saturationMode = DspIntRange(0, 2);

  // --- Stereo width (DspParams.h StereoWidthParamSet) ------------------------
  // NOTE: the stereo-width setters live in equalizer_preset_ops.dart (owned by
  // another workstream); these entries document the contract for when that file
  // adopts it.
  static const DspRange stereoWidth = DspRange(0.0, 2.0, defaultValue: 1.0);
  static const DspRange stereoWidthBand = DspRange(0.0, 2.0, defaultValue: 1.0);
  static const DspRange stereoWidthLowCrossoverHz =
      DspRange(40.0, 1000.0, defaultValue: 160.0);
  static const DspRange stereoWidthHighCrossoverHz =
      DspRange(1000.0, 10000.0, defaultValue: 2500.0);

  // --- Loudness contour (DspParams.h LoudnessContourParamSet) ----------------
  static const DspRange loudnessContourIntensity = DspRange(0.0, 1.0);
  static const DspRange volumeLinear = DspRange(0.0, 1.0, defaultValue: 1.0);

  // --- Sub crossover (DspParams.h SubCrossoverParamSet) ----------------------
  static const DspRange subCrossoverCornerHz =
      DspRange(60.0, 150.0, defaultValue: 80.0);
  static const DspRange subCrossoverGain =
      DspRange(0.0, 1.0, defaultValue: 0.8);

  // --- Multiband compressor crossovers (DspParams.h MultibandCompressorParamSet)
  static const DspRange multibandCompressorF0 =
      DspRange(40.0, 500.0, defaultValue: 160.0);
  static const DspRange multibandCompressorF1 =
      DspRange(200.0, 4000.0, defaultValue: 1000.0);
  static const DspRange multibandCompressorF2 =
      DspRange(1000.0, 16000.0, defaultValue: 5000.0);

  // --- Dynamic bass (DspParams.h DynamicBassParamSet) ------------------------
  static const DspRange dynamicBassStrength =
      DspRange(0.0, 8.0, defaultValue: 1.0);
  static const DspIntRange dynamicBassPreset = DspIntRange(0, 9);
  static const DspIntRange dynamicBassXLow = DspIntRange(20, 2400);
  static const DspIntRange dynamicBassXHigh = DspIntRange(500, 12000);
  static const DspIntRange dynamicBassYLow = DspIntRange(20, 200);
  static const DspIntRange dynamicBassYHigh = DspIntRange(30, 300);
  static const DspRange dynamicBassSideGainLow = DspRange(0.0, 1.0);
  static const DspRange dynamicBassSideGainHigh = DspRange(0.0, 1.0);
}
