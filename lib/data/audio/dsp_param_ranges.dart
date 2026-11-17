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

/// The DSP parameter range contract — the AUTHORITATIVE table.
///
/// Every stage that clamps a DSP parameter must use these numbers, and the same
/// numbers are mirrored in `android/app/src/main/cpp/DspParamRanges.h` (native
/// sanitizer + per-stage clamps) and in `AudioEffectsPlugin.kt` (`DspParamRanges`
/// object). Two tests keep the three in lockstep:
///  * `android/app/src/test/kotlin/.../DspParamRangesContractTest.kt` parses this
///    file and asserts the Kotlin object equals it.
///  * `android/app/src/test/cpp/test_param_ranges.cpp` feeds every bound through
///    `SanitizeSnapshot` and the owning stage clamp and asserts nothing is
///    modified.
///
/// Where a stage can do more than the UI offers, the UI's narrower range wins and
/// the reason is documented on the entry. A value listed here is a promise: no
/// layer may silently narrow it further.
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
  /// bs2b "custom" delay. The native stage can do 50..2000 µs; the custom panel
  /// never offers more than 700 µs, and that narrower product range is the
  /// contract (the stage clamp was widened to it).
  static const DspRange crossfeedDelayUs =
      DspRange(200.0, 700.0, defaultValue: 350.0);
  static const DspRange crossfeedFeedDb =
      DspRange(-15.0, -6.0, defaultValue: -9.0);
  static const DspRange crossfeedFcut =
      DspRange(200.0, 2000.0, defaultValue: 650.0);

  /// 0=Bs2bDefault, 1=Bs2bChuMoy, 2=Bs2bJanMeier, 3=Custom (CrossfeedMode).
  static const DspIntRange crossfeedMode = DspIntRange(0, 3);

  // --- Lookahead limiter (DspParams.h LimiterParamSet) -----------------------
  /// Also used by the headphone-safety limiter, whose ceiling can be -40 dB.
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
  /// Bass-management corner. The stage accepts 20..500 Hz; the UI only offers
  /// 60..150 Hz, which is the contract (a 500 Hz "sub" corner is not a
  /// subwoofer split).
  static const DspRange subCrossoverCornerHz =
      DspRange(60.0, 150.0, defaultValue: 80.0);
  static const DspRange subCrossoverGain =
      DspRange(0.0, 1.0, defaultValue: 0.8);

  /// Native SubCrossover implements Linkwitz-Riley 2nd/4th order only, so the
  /// UI's continuous-looking slope is quantized to 12 or 24 dB/oct. Non-finite
  /// input falls back to the native default (24) instead of propagating NaN.
  static double normalizeSubCrossoverSlope(double value) {
    if (!value.isFinite) return 24.0;
    return value < 18.0 ? 12.0 : 24.0;
  }

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

  // --- Dynamic EQ (DspParams.h DynamicEqBandParam) ---------------------------
  /// Band centre frequency. The native stage additionally clamps to 0.45*fs
  /// (physical Nyquist guard, not a contract narrowing).
  static const DspRange dynamicEqFrequencyHz =
      DspRange(20.0, 20000.0, defaultValue: 1000.0);

  /// Agreed maximum Q is 20 (UI + Kotlin). The native stage used to stop at 12
  /// and the sanitizer accepted 100; neither extreme was reachable from the UI.
  static const DspRange dynamicEqQ = DspRange(0.1, 20.0, defaultValue: 2.0);

  static const DspRange dynamicEqThresholdDb =
      DspRange(-80.0, 0.0, defaultValue: -30.0);

  /// 1..20: a ratio below 1 would invert the expander/compressor direction, so
  /// the old sanitizer floor of 0.1 was never honoured by the stage.
  static const DspRange dynamicEqRatio = DspRange(1.0, 20.0, defaultValue: 3.0);

  static const DspRange dynamicEqAttackMs =
      DspRange(0.1, 200.0, defaultValue: 5.0);
  static const DspRange dynamicEqReleaseMs =
      DspRange(5.0, 2000.0, defaultValue: 120.0);

  /// ±48 dB is the widest documented cut/boost contract; the old stage clamp of
  /// ±24 dB silently halved a legal UI value.
  static const DspRange dynamicEqMaxCutDb =
      DspRange(-48.0, 0.0, defaultValue: -12.0);
  static const DspRange dynamicEqMaxBoostDb =
      DspRange(0.0, 48.0, defaultValue: 12.0);

  // --- Multiband compressor (DspParams.h MultibandBandParam) -----------------
  // These are the same numbers as the `compressor*` knobs above; both names are
  // kept because the visual compressor UI and the multiband engine section each
  // read their own alias. They must never drift apart.
  static const DspRange multibandThresholdDb =
      DspRange(-60.0, 0.0, defaultValue: -18.0);
  static const DspRange multibandRatio = DspRange(1.0, 20.0, defaultValue: 2.0);
  static const DspRange multibandAttackMs =
      DspRange(0.1, 200.0, defaultValue: 15.0);

  /// Native release is capped at 1000 ms (a 2 s release reads as a level drift,
  /// not compression) — a genuine stage limit, so the contract follows it.
  static const DspRange multibandReleaseMs =
      DspRange(5.0, 1000.0, defaultValue: 100.0);
  static const DspRange multibandKneeDb = DspRange(0.0, 12.0, defaultValue: 3.0);

  /// Deliberately non-negative: applying a *negative* makeup is the EQ preamp's
  /// job, and the old Kotlin -24..24 range was silently clamped to >= 0 here.
  static const DspRange multibandMakeupGainDb = DspRange(0.0, 24.0);

  // --- Headphone safety (DspParams.h HeadphoneSafetyParamSet) ----------------
  /// Weekly-dose multiplier. JNI used to cap at 10, Kotlin allowed 100 and the
  /// sanitizer 0.1..100; 0.1..100 is the widest range the UI can express, so all
  /// three now share it.
  static const DspRange safetyDoseThreshold =
      DspRange(0.1, 100.0, defaultValue: 1.0);
  static const DspRange safetyCeilingDb =
      DspRange(-40.0, 0.0, defaultValue: -6.0);

  // --- Bit-perfect / dither (DspParams.h BitPerfectParamSet / DitherParamSet) -
  /// Direct-USB software attenuation. 1.0 is the only bit-exact value.
  static const DspRange directUsbGain = DspRange(0.0, 1.0, defaultValue: 1.0);

  /// Dither only exists for integer PCM depths; anything else falls back to 16
  /// (a zero/other depth would silently disable the quantiser).
  static const List<int> ditherBitDepths = <int>[16, 24, 32];

  /// Returns [value] when it is a supported dither depth, else 16.
  static int normalizeDitherBitDepth(int value) =>
      ditherBitDepths.contains(value) ? value : 16;
}
