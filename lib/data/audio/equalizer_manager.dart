// lib/data/audio/equalizer_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueNotifier, listEquals;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/platform_capabilities.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/models/reverb_preset.dart';
import 'async_lock.dart';
import 'audio_effects_channel.dart';
import 'comparison_slot.dart';
import 'dsp_param_ranges.dart';
import 'eq_frequency_validation.dart';
import 'eq_preset_schema_validator.dart';
import 'headphone_profiles_repository.dart';
import 'ir_file_parser.dart';
import 'live_prog_slider_persistence.dart';
import 'optimized_dsp_pipeline.dart';

export 'comparison_slot.dart';
export 'async_lock.dart' show AsyncLock;

part 'equalizer_preset_ops.dart';
part 'equalizer_snapshot_ops.dart';
part 'equalizer_effect_ops.dart';
part 'equalizer_restore_ops.dart';

/// Per-band Q for a graphic EQ, derived from the band spacing so adjacent
/// peaking filters sum to (approximately) the drawn curve instead of piling up.
///
/// A fixed Q=1.414 is only correct for octave spacing (10-band). For the dense
/// 32/64-band curves (~1/3- and ~1/6-octave) a Q of 1.414 makes each ~1-octave-
/// wide filter overlap 3-6 neighbours, so a flat set of boosts overshoots the
/// target by ~3-6x and pushes the downstream true-peak limiter into pumping.
///
/// Q = 2^(b/2) / (2^b - 1), where b is the local spacing in octaves — the
/// classic constant-Q graphic-EQ relation (b=1 -> 1.414, b=1/3 -> ~4.3,
/// b=1/6 -> ~8.7). Edge bands use their single neighbour; interior bands use
/// the average of both neighbours. Result is clamped to a sane filter range.
List<double> graphicEqQs(List<double> freqs) {
  final n = freqs.length;
  if (n == 0) return const <double>[];
  if (n == 1) return <double>[1.414];
  double octaves(double fLo, double fHi) =>
      (fLo > 0 && fHi > 0) ? (math.log(fHi / fLo) / math.ln2) : 1.0;
  double qForOctaves(double b) {
    if (!b.isFinite || b <= 0) return 1.414;
    final twoB = math.pow(2.0, b).toDouble();
    if (twoB <= 1.0) return 1.414;
    final q = math.pow(2.0, b / 2).toDouble() / (twoB - 1.0);
    return q.clamp(0.3, 12.0).toDouble();
  }

  final qs = <double>[];
  for (var i = 0; i < n; i++) {
    final double b;
    if (i == 0) {
      b = octaves(freqs[0], freqs[1]);
    } else if (i == n - 1) {
      b = octaves(freqs[n - 2], freqs[n - 1]);
    } else {
      b = 0.5 * octaves(freqs[i - 1], freqs[i + 1]);
    }
    qs.add(qForOctaves(b));
  }
  return qs;
}

/// Numeric DSP-parameter sanitation lives in `dsp_param_ranges.dart`:
/// [DspParamRanges] is the single source of truth for every parameter's valid
/// range, and [clampFinite] / [DspRange.clamp] are the NaN/Inf-safe clamps the
/// setters use. Dart's `num.clamp` propagates NaN, so numeric setters must
/// finite-guard before clamping or garbage reaches native (mirrors the native
/// `clampFinite` sanitizers in DspParams.h / AudioDspEngine).
class EqualizerManager {
  /// Native `ParametricEQ::MAX_BANDS` (android/app/src/main/cpp/ParametricEQ.h).
  static const int equalizerMaxNativeBands = 64;

  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;
  final AudioEffectsChannel _effectsChannel = AudioEffectsChannel();
  Timer? _saveDebounce;
  Timer? _bandGainDebounce;
  final Map<int, double> _pendingBandGains = {};
  final _effectsLock =
      AsyncLock(); // Serializes concurrent effect state changes
  SharedPreferences? _cachedPrefs;
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  /// Per-effect truthful status: a key is present only while the most recent
  /// native apply attempt was rejected (unsupported capability, build failure,
  /// or no attached session). The UI reads this so an ON control cannot
  /// silently mean "no audible effect". Updated without persisting or logging
  /// on every failure — only on a status transition.
  final ValueNotifier<Map<String, String>> effectStatusNotifier =
      ValueNotifier<Map<String, String>>(const {});

  void _recordEffectOutcome(String effectKey, bool applied) {
    // Never touch effectStatusNotifier once disposed: dispose() calls
    // effectStatusNotifier.dispose(), after which writing .value throws.
    if (_isDisposed) return;
    final current = effectStatusNotifier.value;
    if (applied) {
      if (current.containsKey(effectKey)) {
        final next = Map<String, String>.from(current)..remove(effectKey);
        effectStatusNotifier.value = Map.unmodifiable(next);
      }
      return;
    }
    if (current.containsKey(effectKey)) return; // already known; no log spam
    final next = Map<String, String>.from(current)..[effectKey] = 'notApplied';
    effectStatusNotifier.value = Map.unmodifiable(next);
    ErrorLogger.log(
      'Effect "$effectKey" reported it could not be applied by the audio engine '
      '(unsupported, build failure, or unavailable session)',
      category: 'EqualizerManager',
    );
  }

  EqPreset currentPreset = EqPreset.defaultPresets.first;
  bool isEnabled = false;

  /// Active EQ band count: 10, 32 or 64. Single source of truth for the band
  /// plan. [is32BandMode] is kept as a derived alias so older call sites (the
  /// audio handler, tests) keep compiling; it means "not the 10-band plan".
  int eqBandCount = 10;
  bool get is32BandMode => eqBandCount != 10;
  double preampDb = 0.0;

  double volumeBoost = 0.0; // 0.0 -> 1.0, maps to 0-1000 mB

  bool isVirtualizerEnabled = false;
  double virtualizerStrength = 0.0; // 0.0 to 1.0

  bool isDynamicsEnabled = false;
  DynamicsPreset dynamicsPreset = DynamicsPreset.off;
  bool _isDynamicsBypassed = false;
  bool get isDynamicsBypassed => _isDynamicsBypassed;

  /// Effective dynamics state the UI must mirror: the stage is only audible
  /// when it is both enabled and not bypassed. Exposing the conjunction keeps
  /// the toggle from showing ON while the native stage is muted.
  bool get isDynamicsEffectivelyEnabled =>
      isDynamicsEnabled && !_isDynamicsBypassed;

  bool isSpatializerEnabled = false;

  // Tier 1 & Tier 2 & Tier 3 Native DSP features
  bool isCrossfeedEnabled = false;
  double crossfeedDelayUs = 350.0; // 200 - 700 us
  double crossfeedFeedDb = -9.0; // -15 to -6 dB
  double crossfeedFcut = 650.0; // 200 - 2000 Hz (Custom-mode cutoff)
  int crossfeedMode =
      0; // 0=Bs2bDefault, 1=Bs2bChuMoy, 2=Bs2bJanMeier, 3=Custom

  bool isLimiterEnabled = false;
  double limiterThresholdDb = -0.2;
  double limiterReleaseMs = 50.0;
  double limiterLookaheadMs = 3.0;

  // Visual Compressor Knobs
  double compressorRatio = 3.0;
  double compressorAttackMs = 15.0;
  double compressorMakeupGainDb = 0.0;

  /// True once the user has saved compressor knobs (or changed them this
  /// session). Until then the HAL is left on its brickwall defaults.
  bool _hasStoredCompressorParams = false;

  /// Ratio / attack / make-up are honored by the Android HAL
  /// DynamicsProcessing limiter; the native C++ stage is a brickwall limiter
  /// with no ratio/attack/make-up concept, so the sliders are gated when the
  /// HAL engine is unavailable.
  bool get isCompressorAdvancedParamsSupported => isDynamicsSupported;

  bool isReverbEnabled = false;

  /// Wire value of a [ReverbPreset] — the ordinal the native convolution
  /// reverb synthesizes an impulse response for.
  int reverbPreset = ReverbPreset.studio.wireValue;
  double reverbWetDry = 0.20;
  double reverbPredelayMs = 0.0; // 0 - 150 ms
  double reverbDamping = 0.5; // 0.0 - 1.0 (HF absorption)

  double stereoBalance = 0.0; // -1.0 to +1.0
  bool monoMix = false;
  bool isSincResamplerEnabled = false;

  // Phase 1 DSP expansion stages
  bool isSaturationEnabled = false;
  double saturationDrive = 0.3; // 0.0 - 1.0
  double saturationMix = 0.5; // 0.0 - 1.0 wet/dry
  double saturationTilt = 0.3; // 0.0 - 1.0 HF pre-emphasis
  int saturationMode = 0; // 0=Tape, 1=Tube, 2=Analog Class-A
  bool saturationMultiband = false;

  bool isStereoWidthEnabled = false;
  double stereoWidth = 1.0; // 0.0 mono … 1.0 normal … 2.0 widened
  bool stereoWidthMultiband = false;
  double stereoWidthLow = 1.0;
  double stereoWidthMid = 1.0;
  double stereoWidthHigh = 1.0;
  double stereoWidthLowCrossoverHz = 160.0;
  double stereoWidthHighCrossoverHz = 2500.0;

  bool isLoudnessContourEnabled = false;
  double loudnessContourIntensity = 0.0; // 0.0 - 1.0
  double loudnessVolumeLinear = 1.0; // current volume-stage value (0..1)

  bool isSubCrossoverEnabled = false;
  double subCrossoverCornerHz = 80.0; // 60 - 150 Hz
  double subCrossoverSlopeDbPerOct = 24.0; // 12 or 24 dB/oct
  double subCrossoverGain = 0.8; // 0.0 - 1.0
  bool subCrossoverBassMono = false;
  bool subCrossoverAntiPop = true;

  bool isDynamicEqEnabled = false;
  List<DynamicEqBandConfig> dynamicEqBands = const [DynamicEqBandConfig()];

  // Native C++ 4-Band Multiband Compressor
  bool isMultibandCompressorEnabled = false;
  List<MultibandCompressorBandConfig> multibandCompressorBands = const [
    MultibandCompressorBandConfig(
        thresholdDb: -20.0,
        ratio: 2.5,
        attackMs: 20.0,
        releaseMs: 120.0,
        kneeDb: 6.0,
        makeupGainDb: 0.0),
    MultibandCompressorBandConfig(
        thresholdDb: -18.0,
        ratio: 2.0,
        attackMs: 15.0,
        releaseMs: 100.0,
        kneeDb: 6.0,
        makeupGainDb: 0.0),
    MultibandCompressorBandConfig(
        thresholdDb: -16.0,
        ratio: 1.8,
        attackMs: 10.0,
        releaseMs: 80.0,
        kneeDb: 4.0,
        makeupGainDb: 0.0),
    MultibandCompressorBandConfig(
        thresholdDb: -14.0,
        ratio: 1.5,
        attackMs: 5.0,
        releaseMs: 60.0,
        kneeDb: 4.0,
        makeupGainDb: 0.0),
  ];
  double multibandCompressorF0 = 160.0;
  double multibandCompressorF1 = 1000.0;
  double multibandCompressorF2 = 5000.0;

  // ViPER-modeled Dynamic System / Dynamic Bass
  bool isDynamicBassEnabled = false;
  double dynamicBassStrength = 1.0;
  int dynamicBassXLow = 100;
  int dynamicBassXHigh = 5600;
  int dynamicBassYLow = 40;
  int dynamicBassYHigh = 80;
  double dynamicBassSideGainLow = 0.10;
  double dynamicBassSideGainHigh = 0.50;
  int dynamicBassPreset = 0;

  // ViPER-DDC
  bool isViperDdcEnabled = false;
  String viperDdcProfileName = '';
  String viperDdcContent = '';

  // Arbitrary Response EQ (EqualizerAPO GraphicEq)
  bool isArbitraryEqEnabled = false;
  String arbitraryEqString = '';
  // Linear-phase FIR variant (constant group delay = FIR_TAPS/2, exact phase
  // match at the cost of pre-ringing); false = minimum-phase (default).
  bool arbitraryEqLinearPhase = false;

  // Live Programmable DSP (EEL script)
  bool isLiveProgEnabled = false;
  String liveProgCode = '';
  final Map<int, double> liveProgSliders = {};

  double reverbCrossChannel = 0.0;
  List<double> customImpulseResponse = const [];

  /// DSP engine routing: 'native' | 'oem' | 'auto'. Single source of truth —
  /// SettingsCubit persists to the same PrefsKeys.dspPreference key.
  String dspPreference = 'native';

  /// Test/compat override for the legacy DynamicsProcessing mirror.
  /// null (default) => mirror follows [dspPreference]: disabled when 'native'
  /// owns the curve (single-application guarantee, defect 13-01), enabled
  /// otherwise as a fallback for old APKs / OEM path.
  bool? debugForceLegacyMirror;

  /// True when the legacy 10-band postEq mirror must be written alongside the
  /// native parametric stage. When false and the native bulk write ACKs, the
  /// legacy write is skipped so the curve is applied exactly once.
  bool get legacyMirrorEnabled =>
      debugForceLegacyMirror ?? dspPreference != 'native';

  /// Bit-perfect bypass mirror. Owned here so reattach/route resync restores
  /// it (previously only pushed once from SettingsCubit and lost on resync).
  bool isBitPerfectBypass = false;

  /// TPDF dither mirror (native stage; skipped on BT routes automatically).
  bool isDitherEnabled = false;
  int ditherTargetBitDepth = 16;

  /// Whether the current output route is Bluetooth. Updated from the existing
  /// route-change hook so dither pushes stop claiming a wired route while a BT
  /// device is active (the native side uses this to skip dithering).
  bool isBluetoothRoute = false;

  /// Bluetooth Hi-Res opt-in: when true the native dither stage is permitted on
  /// a BT route (otherwise it is skipped, since the lossy codec re-quantises).
  bool isBluetoothDitherEnabled = false;

  bool get isVirtualizerSupported => _effectsChannel.isVirtualizerSupported;
  bool get isDynamicsSupported => _effectsChannel.isDynamicsSupported;
  bool get isBassBoostSupported => _effectsChannel.isBassBoostSupported;
  bool get isVolumeBoostSupported => _effectsChannel.isVolumeBoostSupported;

  HeadphoneProfile? selectedHeadphoneProfile;

  List<double> customFrequencies = List.from(EqPreset.centerFrequencies);
  List<double> custom32Frequencies = List.from(EqPreset.iso32BandFrequencies);
  List<double> custom64Frequencies = List.from(EqPreset.iso64Frequencies);

  // A/B/C/D Comparison Slots
  ComparisonSlot activeComparisonSlot = ComparisonSlot.slotA;
  final Map<ComparisonSlot, EqPreset> comparisonSlots = {
    ComparisonSlot.slotA: EqPreset.defaultPresets.first,
    ComparisonSlot.slotB: EqPreset.defaultPresets[1],
    ComparisonSlot.slotC: EqPreset.defaultPresets[2],
    ComparisonSlot.slotD: EqPreset.defaultPresets[3],
  };

  EqualizerManager({this.loudnessEnhancerA, this.loudnessEnhancerB});

  /// NaN/Inf-safe clamp for values read back from SharedPreferences.
  static double _finiteClamp(double v, double lo, double hi, double fallback) {
    if (!v.isFinite) return fallback;
    return v < lo ? lo : (v > hi ? hi : v);
  }

  /// Last values successfully written, so a save only touches changed keys
  /// (the full map is ~100 keys incl. large strings, rewritten every 350 ms
  /// while a slider is dragged).
  final Map<String, dynamic> _lastPersisted = <String, dynamic>{};

  /// Prefs are untrusted input (older builds, manual edits, corrupt writes).
  /// Only the setters clamped before; restore pushed raw values to native.
  void _sanitizeRestoredState() {
    volumeBoost = DspParamRanges.volumeBoost
        .clampRaw(volumeBoost.isFinite ? volumeBoost : 0.0);
    virtualizerStrength = _finiteClamp(virtualizerStrength, 0.0, 1.0, 0.0);
    crossfeedDelayUs = _finiteClamp(crossfeedDelayUs, 200.0, 700.0, 350.0);
    crossfeedFeedDb = _finiteClamp(crossfeedFeedDb, -15.0, -6.0, -9.0);
    crossfeedFcut = _finiteClamp(crossfeedFcut, 200.0, 2000.0, 650.0);
    crossfeedMode =
        crossfeedMode < 0 ? 0 : (crossfeedMode > 3 ? 3 : crossfeedMode);
    reverbWetDry = _finiteClamp(reverbWetDry, 0.0, 1.0, 0.20);
    reverbPredelayMs = _finiteClamp(reverbPredelayMs, 0.0, 150.0, 0.0);
    reverbDamping = _finiteClamp(reverbDamping, 0.0, 1.0, 0.5);
    stereoBalance = _finiteClamp(stereoBalance, -1.0, 1.0, 0.0);
    stereoWidth = _finiteClamp(stereoWidth, 0.0, 2.0, 1.0);
    stereoWidthLow = _finiteClamp(stereoWidthLow, 0.0, 2.0, 1.0);
    stereoWidthMid = _finiteClamp(stereoWidthMid, 0.0, 2.0, 1.0);
    stereoWidthHigh = _finiteClamp(stereoWidthHigh, 0.0, 2.0, 1.0);
    saturationDrive = DspParamRanges.saturationDrive
        .clampRaw(saturationDrive.isFinite ? saturationDrive : 0.3);
    saturationMix = DspParamRanges.saturationMix
        .clampRaw(saturationMix.isFinite ? saturationMix : 0.5);
    saturationTilt = DspParamRanges.saturationTilt
        .clampRaw(saturationTilt.isFinite ? saturationTilt : 0.3);
    saturationMode = DspParamRanges.saturationMode.clamp(saturationMode);
    loudnessContourIntensity = DspParamRanges.loudnessContourIntensity.clampRaw(
        loudnessContourIntensity.isFinite ? loudnessContourIntensity : 0.0);
    subCrossoverCornerHz = DspParamRanges.subCrossoverCornerHz
        .clampRaw(subCrossoverCornerHz.isFinite ? subCrossoverCornerHz : 80.0);
    subCrossoverGain = DspParamRanges.subCrossoverGain
        .clampRaw(subCrossoverGain.isFinite ? subCrossoverGain : 0.8);
    subCrossoverSlopeDbPerOct = subCrossoverSlopeDbPerOct < 18.0 ? 12.0 : 24.0;
    dynamicBassStrength = DspParamRanges.dynamicBassStrength
        .clampRaw(dynamicBassStrength.isFinite ? dynamicBassStrength : 1.0);
    dynamicBassPreset =
        DspParamRanges.dynamicBassPreset.clamp(dynamicBassPreset);
    dynamicBassXLow = DspParamRanges.dynamicBassXLow.clamp(dynamicBassXLow);
    dynamicBassXHigh = DspParamRanges.dynamicBassXHigh.clamp(dynamicBassXHigh);
    dynamicBassYLow = DspParamRanges.dynamicBassYLow.clamp(dynamicBassYLow);
    dynamicBassYHigh = DspParamRanges.dynamicBassYHigh.clamp(dynamicBassYHigh);
    dynamicBassSideGainLow = DspParamRanges.dynamicBassSideGainLow.clampRaw(
        dynamicBassSideGainLow.isFinite ? dynamicBassSideGainLow : 0.10);
    dynamicBassSideGainHigh = DspParamRanges.dynamicBassSideGainHigh.clampRaw(
        dynamicBassSideGainHigh.isFinite ? dynamicBassSideGainHigh : 0.50);
    // Crossovers must stay strictly ordered; reset to defaults if a stored
    // set is inverted/non-finite (setMultibandCompressor enforces this too).
    if (!multibandCompressorF0.isFinite ||
        !multibandCompressorF1.isFinite ||
        !multibandCompressorF2.isFinite ||
        multibandCompressorF1 <= multibandCompressorF0 ||
        multibandCompressorF2 <= multibandCompressorF1) {
      multibandCompressorF0 = 160.0;
      multibandCompressorF1 = 1000.0;
      multibandCompressorF2 = 5000.0;
    }
  }

  void _debouncedSavePreferences() {
    if (_restoringFromDegrade) {
      // BUG-22: restoreFromDegrade persists the merged state once at the end;
      // intermediate debounced writes during the restore would race it.
      return;
    }
    if (_isDegradedForPower) {
      // BUG-04: capture the user's changes instead of silently dropping them.
      // Diffing against the post-degrade baseline stores only the touched keys
      // so restore can merge them without re-disabling untouched stages.
      final baseline = _degradeBaselinePrefs;
      if (baseline != null) {
        final current = _buildSavePreferencesMap();
        final delta = <String, dynamic>{};
        for (final entry in current.entries) {
          if (baseline[entry.key] != entry.value) {
            delta[entry.key] = entry.value;
          }
        }
        _pendingDegradePrefs = delta.isEmpty ? null : delta;
      }
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      _savePreferences();
    });
  }

  Future<void> init() async {
    _cachedPrefs = await SharedPreferences.getInstance();
    await _effectsChannel.init();
    await _effectsLock.lock(() => _restorePreferences());
  }

  List<double> get activeFrequencies => eqBandCount == 64
      ? custom64Frequencies
      : (eqBandCount == 32 ? custom32Frequencies : customFrequencies);

  Future<void> _savePreferences() async {
    // Battery degrade must never clobber saved ON prefs — covers both the
    // debounced path and direct await _savePreferences() call sites.
    if (_isDegradedForPower) return;
    // Serialize concurrent preference writes to prevent torn reads/writes
    // when multiple effects are toggled rapidly.
    await _effectsLock.lock(() => _performSavePreferences());
  }

  Map<String, dynamic> _buildSavePreferencesMap() {
    return <String, dynamic>{
      PrefsKeys.eqEnabled: isEnabled,
      PrefsKeys.eq32BandMode: is32BandMode,
      PrefsKeys.eqBandCount: eqBandCount,
      PrefsKeys.eqPresetName: currentPreset.name,
      PrefsKeys.eqGains: json.encode(currentPreset.gains),
      PrefsKeys.eqCustomFrequencies: json.encode(customFrequencies),
      PrefsKeys.eqCustom32Frequencies: json.encode(custom32Frequencies),
      PrefsKeys.eqCustom64Frequencies: json.encode(custom64Frequencies),
      PrefsKeys.eqBassBoost: currentPreset.bassBoost,
      PrefsKeys.eqPreamp: preampDb,
      PrefsKeys.eqVolumeBoost: volumeBoost,
      PrefsKeys.eqVirtualizerEnabled: isVirtualizerEnabled,
      PrefsKeys.eqVirtualizerStrength: virtualizerStrength,
      PrefsKeys.eqDynamicsPreset: dynamicsPreset.name,
      PrefsKeys.eqDynamicsEnabled: isDynamicsEnabled,
      PrefsKeys.eqDynamicsBypassed: _isDynamicsBypassed,
      PrefsKeys.eqSpatializerEnabled: isSpatializerEnabled,
      PrefsKeys.crossfeedEnabled: isCrossfeedEnabled,
      PrefsKeys.crossfeedDelayUs: crossfeedDelayUs,
      PrefsKeys.crossfeedFeedDb: crossfeedFeedDb,
      PrefsKeys.crossfeedFcut: crossfeedFcut,
      PrefsKeys.crossfeedMode: crossfeedMode,
      PrefsKeys.lookaheadLimiterEnabled: isLimiterEnabled,
      PrefsKeys.lookaheadLimiterThresholdDb: limiterThresholdDb,
      PrefsKeys.lookaheadLimiterReleaseMs: limiterReleaseMs,
      PrefsKeys.lookaheadLimiterLookaheadMs: limiterLookaheadMs,
      // Only written once the user edits the compressor, so a fresh install
      // never has these keys and keeps the native brickwall defaults.
      if (_hasStoredCompressorParams) ...{
        PrefsKeys.compressorRatio: compressorRatio,
        PrefsKeys.compressorAttackMs: compressorAttackMs,
        PrefsKeys.compressorMakeupGainDb: compressorMakeupGainDb,
      },
      PrefsKeys.convolutionReverbEnabled: isReverbEnabled,
      PrefsKeys.convolutionReverbPreset: reverbPreset,
      PrefsKeys.convolutionReverbWetDry: reverbWetDry,
      PrefsKeys.convolutionReverbPredelayMs: reverbPredelayMs,
      PrefsKeys.convolutionReverbDamping: reverbDamping,
      PrefsKeys.stereoBalance: stereoBalance,
      PrefsKeys.monoMix: monoMix,
      PrefsKeys.sincResamplerEnabled: isSincResamplerEnabled,
      PrefsKeys.saturationEnabled: isSaturationEnabled,
      PrefsKeys.saturationDrive: saturationDrive,
      PrefsKeys.saturationMix: saturationMix,
      PrefsKeys.saturationTilt: saturationTilt,
      PrefsKeys.saturationMode: saturationMode,
      PrefsKeys.saturationMultiband: saturationMultiband,
      PrefsKeys.stereoWidthEnabled: isStereoWidthEnabled,
      PrefsKeys.stereoWidth: stereoWidth,
      PrefsKeys.stereoWidthMultiband: stereoWidthMultiband,
      PrefsKeys.stereoWidthLow: stereoWidthLow,
      PrefsKeys.stereoWidthMid: stereoWidthMid,
      PrefsKeys.stereoWidthHigh: stereoWidthHigh,
      PrefsKeys.stereoWidthLowCrossoverHz: stereoWidthLowCrossoverHz,
      PrefsKeys.stereoWidthHighCrossoverHz: stereoWidthHighCrossoverHz,
      PrefsKeys.loudnessContourEnabled: isLoudnessContourEnabled,
      PrefsKeys.loudnessContourIntensity: loudnessContourIntensity,
      PrefsKeys.subCrossoverEnabled: isSubCrossoverEnabled,
      PrefsKeys.subCrossoverCornerHz: subCrossoverCornerHz,
      PrefsKeys.subCrossoverSlopeDbPerOct: subCrossoverSlopeDbPerOct,
      PrefsKeys.subCrossoverGain: subCrossoverGain,
      PrefsKeys.subCrossoverBassMono: subCrossoverBassMono,
      PrefsKeys.subCrossoverAntiPop: subCrossoverAntiPop,
      PrefsKeys.dynamicEqEnabled: isDynamicEqEnabled,
      PrefsKeys.dynamicEqBands: json.encode(
        dynamicEqBands.map((b) => b.toJson()).toList(),
      ),
      PrefsKeys.reverbCrossChannel: reverbCrossChannel,
      PrefsKeys.multibandCompressorEnabled: isMultibandCompressorEnabled,
      PrefsKeys.multibandCompressorF0: multibandCompressorF0,
      PrefsKeys.multibandCompressorF1: multibandCompressorF1,
      PrefsKeys.multibandCompressorF2: multibandCompressorF2,
      PrefsKeys.multibandCompressorBands: json.encode(
        multibandCompressorBands.map((b) => b.toJson()).toList(),
      ),
      PrefsKeys.dynamicBassEnabled: isDynamicBassEnabled,
      PrefsKeys.dynamicBassStrength: dynamicBassStrength,
      PrefsKeys.dynamicBassXLow: dynamicBassXLow,
      PrefsKeys.dynamicBassXHigh: dynamicBassXHigh,
      PrefsKeys.dynamicBassYLow: dynamicBassYLow,
      PrefsKeys.dynamicBassYHigh: dynamicBassYHigh,
      PrefsKeys.dynamicBassSideGainLow: dynamicBassSideGainLow,
      PrefsKeys.dynamicBassSideGainHigh: dynamicBassSideGainHigh,
      PrefsKeys.dynamicBassPreset: dynamicBassPreset,
      PrefsKeys.viperDdcEnabled: isViperDdcEnabled,
      PrefsKeys.viperDdcProfileName: viperDdcProfileName,
      PrefsKeys.viperDdcContent: viperDdcContent,
      PrefsKeys.arbitraryEqEnabled: isArbitraryEqEnabled,
      PrefsKeys.arbitraryEqString: arbitraryEqString,
      PrefsKeys.arbitraryEqLinearPhase: arbitraryEqLinearPhase,
      PrefsKeys.liveProgEnabled: isLiveProgEnabled,
      PrefsKeys.liveProgCode: liveProgCode,
      PrefsKeys.liveProgSliders: encodeLiveProgSliders(liveProgSliders),
      PrefsKeys.dspPreference: dspPreference,
      PrefsKeys.ditherEnabled: isDitherEnabled,
      PrefsKeys.ditherTargetBitDepth: ditherTargetBitDepth,
    };
  }

  Future<void> _performSavePreferences() async {
    if (_isDisposed) return;
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      final batch = _buildSavePreferencesMap();

      final changedEntries = batch.entries
          .where((e) =>
              !_lastPersisted.containsKey(e.key) ||
              _lastPersisted[e.key] != e.value)
          .toList(growable: false);
      await Future.wait(changedEntries.map((entry) {
        if (entry.value is bool) {
          return prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is double) {
          return prefs.setDouble(entry.key, entry.value as double);
        } else if (entry.value is int) {
          return prefs.setInt(entry.key, entry.value as int);
        } else if (entry.value is String) {
          return prefs.setString(entry.key, entry.value as String);
        }
        return Future.value(true);
      }));
      for (final e in changedEntries) {
        _lastPersisted[e.key] = e.value;
      }
      // Single atomic pass — batch loop above already persisted everything.
      if (selectedHeadphoneProfile != null) {
        await prefs.setString(
          PrefsKeys.eqHeadphoneProfileId,
          selectedHeadphoneProfile!.id,
        );
      } else {
        await prefs.remove(PrefsKeys.eqHeadphoneProfileId);
      }
    } catch (e, st) {
      if (!_isDisposed) {
        ErrorLogger.log(
          'Failed to save equalizer preferences',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }
  }

  void _performSavePreferencesSync() {
    final prefs = _cachedPrefs;
    if (prefs == null || _isDegradedForPower) return;
    try {
      final batch = _buildSavePreferencesMap();
      for (final entry in batch.entries) {
        if (entry.value is bool) {
          unawaited(prefs.setBool(entry.key, entry.value as bool));
        } else if (entry.value is double) {
          unawaited(prefs.setDouble(entry.key, entry.value as double));
        } else if (entry.value is int) {
          unawaited(prefs.setInt(entry.key, entry.value as int));
        } else if (entry.value is String) {
          unawaited(prefs.setString(entry.key, entry.value as String));
        }
      }
      if (selectedHeadphoneProfile != null) {
        unawaited(prefs.setString(
          PrefsKeys.eqHeadphoneProfileId,
          selectedHeadphoneProfile!.id,
        ));
      } else {
        unawaited(prefs.remove(PrefsKeys.eqHeadphoneProfileId));
      }
    } catch (_) {}
  }

  /// Switches the active band plan to [count] bands (10, 32 or 64),
  /// interpolating the current curve onto the new centers and re-pushing the
  /// whole plan to the native parametric EQ in a single bulk hop.
  Future<void> setBandMode(int count) async {
    if (count != 10 && count != 32 && count != 64) {
      ErrorLogger.log(
        'Rejected unsupported EQ band count $count (need 10, 32 or 64)',
        category: 'EqualizerManager',
      );
      return;
    }
    final int oldBandCount = eqBandCount;
    eqBandCount = count;
    final targetFreqs = activeFrequencies;
    _pendingBandGains.removeWhere((k, _) => k < 0 || k >= targetFreqs.length);

    final Map<int, List<double>> updatedBandsMap =
        Map<int, List<double>>.from(currentPreset.bandsMap);
    final interpolated = EqPreset.interpolateGains(
      currentPreset.gains,
      targetFrequencies: targetFreqs,
      bandsMap: updatedBandsMap,
      currentBandCount: oldBandCount,
    );
    currentPreset = currentPreset.copyWith(
      gains: interpolated,
      bandsMap: updatedBandsMap,
    );
    // The active slot otherwise kept the OLD band count's gains, so switching
    // away and back restored a wrong-length curve.
    comparisonSlots[activeComparisonSlot] = currentPreset;

    if (PlatformCapabilities.isAndroid) {
      // Single bulk JNI hop (was 32 hops, 150-300ms jank) + fallback for legacy 10-band path.
      // Single-application (13-01): skip legacy mirror when native ACKs and owns the curve.
      final nativeOk = await _pushNativeBands(targetFreqs);
      if (!nativeOk) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures = <Future<bool>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              graphicEqQs(targetFreqs)[i],
            ),
          );
          if (futures.length >= 8) {
            await Future.wait(futures);
            futures.clear();
          }
        }
        if (futures.isNotEmpty) await Future.wait(futures);
      }
      if (legacyMirrorEnabled || !nativeOk) {
        if (count == 10) {
          await _effectsChannel.setEqBands(targetFreqs);
          await _effectsChannel.setEqBandGains(currentPreset.gains);
        } else {
          final tenBandGains = EqPreset.interpolateGains(
            currentPreset.gains,
            targetFrequencies: customFrequencies,
          );
          await _effectsChannel.setEqBands(customFrequencies);
          await _effectsChannel.setEqBandGains(tenBandGains);
        }
      }
    }
    _debouncedSavePreferences();
  }

  /// Backwards-compatible alias: `true` selects the 32-band plan, `false` the
  /// 10-band plan. New code should call [setBandMode] directly.
  Future<void> set32BandMode(bool enabled) => setBandMode(enabled ? 32 : 10);

  Future<void> setEnabled(bool enabled) async {
    final previous = isEnabled;
    isEnabled = enabled;
    try {
      await _effectsChannel.setEqEnabled(enabled);
      await _effectsChannel.setNativeEqEnabled(enabled);
      if (enabled) {
        await applyCurrentPreset();
      }
      await _savePreferences();
      _syncPipeline();
    } catch (e, st) {
      isEnabled = previous;
      _syncPipeline();
      ErrorLogger.log(
        'Failed to toggle equalizer state ($enabled)',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) => setEnabled(enabled);
  Future<void> applyPreset(EqPreset preset) => setPreset(preset);
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      setHeadphoneProfile(profile);

  Future<void> setPreset(EqPreset preset) async {
    selectedHeadphoneProfile = null;
    final targetFreqs = activeFrequencies;
    final gains = EqPreset.interpolateGains(
      preset.gains,
      targetFrequencies: targetFreqs,
    );
    final previousPreset = currentPreset;
    final previousSlotPreset = comparisonSlots[activeComparisonSlot];
    currentPreset = preset.copyWith(gains: gains);
    comparisonSlots[activeComparisonSlot] = currentPreset;
    try {
      await applyCurrentPreset();
      await setBassBoost(preset.bassBoost);
      _debouncedSavePreferences();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to apply EQ preset ${preset.name}; rolling back in-memory state',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      currentPreset = previousPreset;
      if (previousSlotPreset != null) {
        comparisonSlots[activeComparisonSlot] = previousSlotPreset;
      }
      rethrow;
    }
  }

  Future<void> setBandGain(int index, double gain) async {
    if (index < 0 || index >= currentPreset.gains.length) return;
    if (!gain.isFinite) return;
    selectedHeadphoneProfile = null;

    final newGains = List<double>.from(currentPreset.gains);
    newGains[index] = DspParamRanges.eqBandGainDb.clampRaw(gain);
    currentPreset = currentPreset.copyWith(name: 'Custom', gains: newGains);
    comparisonSlots[activeComparisonSlot] = currentPreset;

    // Coalesce rapid slider drags: apply state immediately, push to native
    // at most once per 60ms.
    _pendingBandGains[index] = newGains[index];
    _bandGainDebounce?.cancel();
    _bandGainDebounce = Timer(const Duration(milliseconds: 60), () {
      final pending = Map<int, double>.from(_pendingBandGains);
      _pendingBandGains.clear();
      unawaited(_flushBandGains(pending));
    });
    _debouncedSavePreferences();
  }

  Future<void> _flushBandGains(Map<int, double> pending) async {
    if (pending.isEmpty) return;
    await _effectsLock.lock(() async {
      final targetFreqs = activeFrequencies;
      _pendingBandGains.removeWhere((k, _) => k < 0 || k >= targetFreqs.length);
      // Guard against mode-switch race: drop stale indices instead of RangeError.
      final valid = Map<int, double>.fromEntries(
        pending.entries.where((e) => e.key >= 0 && e.key < targetFreqs.length),
      );
      if (valid.isEmpty) return;
      try {
        if (PlatformCapabilities.isAndroid && isEnabled) {
          if (eqBandCount != 10) {
            var nativeOk = true;
            for (final entry in valid.entries) {
              final ok = await _effectsChannel.setNativeEqBand(
                entry.key,
                targetFreqs[entry.key],
                entry.value,
                graphicEqQs(targetFreqs)[entry.key],
              );
              if (!ok) nativeOk = false;
            }
            // Single-application: skip the interpolated legacy mirror when the
            // native stage ACKed and owns the curve (defect 13-01).
            if (!nativeOk || legacyMirrorEnabled) {
              final tenBandGains = EqPreset.interpolateGains(
                currentPreset.gains,
                targetFrequencies: customFrequencies,
              );
              await _effectsChannel.setEqBandGains(tenBandGains);
            }
          } else {
            for (final entry in valid.entries) {
              await _effectsChannel.setEqBandGain(entry.key, entry.value);
              await _effectsChannel.setNativeEqBand(
                entry.key,
                targetFreqs[entry.key],
                entry.value,
                graphicEqQs(targetFreqs)[entry.key],
              );
            }
          }
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to flush band gains',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    });
  }

  Future<void> setPreamp(double preampDb) async {
    // Finite-guard before clamp: a NaN would otherwise survive clamp() and
    // reach native (mirrors setBandGain's isFinite guard). Range lives in the
    // central contract (DspParamRanges.preampDb) so UI, setter and native stay
    // in lockstep.
    this.preampDb = DspParamRanges.preampDb.clamp(preampDb);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setEqPreamp(this.preampDb);
    }
    _debouncedSavePreferences();
  }

  /// Pushes the active curve to the native EQ in one hop. A selected
  /// parametric headphone profile is pushed as its true filters; the flat
  /// graphic gains would otherwise overwrite it on every re-apply (enable
  /// toggle, band-mode change, session reattach, route resync).
  Future<bool> _pushNativeBands(List<double> targetFreqs) async {
    final profile = selectedHeadphoneProfile;
    if (profile != null &&
        profile.hasParametricFilters &&
        await _applyParametricProfile(profile)) {
      return true;
    }
    return _effectsChannel.setNativeEqBandsBulk(
      frequencies: targetFreqs,
      gains: currentPreset.gains,
      qs: graphicEqQs(targetFreqs),
    );
  }

  Future<void> applyCurrentPreset() async {
    if (!isEnabled) return;
    final targetFreqs = activeFrequencies;
    if (PlatformCapabilities.isAndroid) {
      // Prefer bulk path — single generation publish, zero per-band JNI overhead.
      // Single-application guarantee (13-01): when native owns the curve
      // (dspPreference 'native') and bulk ACKs, skip the legacy postEq mirror
      // so gains are not applied twice. The mirror is kept only as a fallback
      // for old APKs / OEM routing or when explicitly forced for tests.
      final nativeOk = await _pushNativeBands(targetFreqs);
      if (nativeOk) {
        if (legacyMirrorEnabled) {
          if (eqBandCount == 10) {
            await _effectsChannel.setEqBands(targetFreqs);
            await _effectsChannel.setEqBandGains(currentPreset.gains);
          } else {
            final tenBandGains = EqPreset.interpolateGains(
              currentPreset.gains,
              targetFrequencies: customFrequencies,
            );
            await _effectsChannel.setEqBands(customFrequencies);
            await _effectsChannel.setEqBandGains(tenBandGains);
          }
        }
        return;
      }
      ErrorLogger.log(
        'Native bulk EQ apply failed; falling back to per-band writes',
        category: 'DSP',
      );
      // Fallback to legacy per-band if bulk unavailable (old APK)
      if (eqBandCount != 10) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures = <Future<bool>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              graphicEqQs(targetFreqs)[i],
            ),
          );
          if (futures.length >= 8) {
            await Future.wait(futures);
            futures.clear();
          }
        }
        if (futures.isNotEmpty) await Future.wait(futures);
      } else {
        await _effectsChannel.setEqBands(targetFreqs);
        await _effectsChannel.setEqBandGains(currentPreset.gains);
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures2 = <Future<bool>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures2.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              graphicEqQs(targetFreqs)[i],
            ),
          );
          if (futures2.length >= 8) {
            await Future.wait(futures2);
            futures2.clear();
          }
        }
        if (futures2.isNotEmpty) await Future.wait(futures2);
      }
    }
  }

  // --- A/B/C/D 4-SLOT COMPARISON ---

  // --- PRESET SLOTS / JSON IO / A-B / CUSTOM FREQUENCIES ---
  // Extracted to equalizer_preset_ops.dart (fat-file ratchet 01-4).
  // A/B staging stays here: extensions cannot hold instance fields.
  List<double> _abComparisonGains = [];
  bool isAbComparisonActive = false;

  Future<void> onAppPaused() async {
    _saveDebounce?.cancel();
    await _savePreferences();
  }

  Future<void> setVolumeBoost(double value) async {
    final preampDb = selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = DspParamRanges.volumeBoost.clampRaw(value);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = DspParamRanges.volumeBoost.clampRaw((6.0 - preampDb) / 10.0);
    }
    volumeBoost = safeValue;
    final milliBels = (volumeBoost * 1000).round();
    if (PlatformCapabilities.isAndroid) {
      final applied = await _effectsChannel.setVolumeBoost(milliBels);
      _recordEffectOutcome('volumeBoost', applied || volumeBoost <= 0.0);
    }
    _debouncedSavePreferences();
  }

  Future<void> setHeadphoneProfile(HeadphoneProfile? profile) async {
    final prevPreset = currentPreset;
    final prevProfile = selectedHeadphoneProfile;
    try {
      if (profile != null) {
        final bool isParametric = profile.hasParametricFilters;
        if (profile.gains.isEmpty && !isParametric) {
          ErrorLogger.log(
            'Headphone profile has empty gains — ignoring',
            category: 'EqualizerManager',
          );
          return;
        }
        if (profile.gains.any((g) => !g.isFinite)) {
          ErrorLogger.log(
            'Headphone profile contains non-finite gains — ignoring',
            category: 'EqualizerManager',
          );
          return;
        }
        final targetFreqs = activeFrequencies;
        // Derive the display/fallback gain curve from the true filters when the
        // profile carries them, so the graph and the legacy postEq mirror stay
        // consistent with what the native parametric engine plays.
        final sourceGains = isParametric
            ? profile.gainsFromFilters(centers: targetFreqs)
            : profile.gains;
        final gains = EqPreset.interpolateGains(
          sourceGains,
          targetFrequencies: targetFreqs,
        );
        currentPreset = EqPreset(
          name: profile.name,
          gains: gains,
          bassBoost: profile.bassBoost,
        );
        comparisonSlots[activeComparisonSlot] = currentPreset;
        selectedHeadphoneProfile = profile;
        // Parametric profiles bypass the flat 10/32/64 graphic path and drive
        // the native 64-band parametric EQ directly with real freq/Q/gain/type.
        if (isParametric) {
          final applied = await _applyParametricProfile(profile);
          if (!applied) {
            // Native PEQ unavailable: fall back to the graphic-gain path using
            // the filter-derived curve so the correction still applies.
            await applyCurrentPreset();
          }
        } else {
          await applyCurrentPreset();
        }
        await setBassBoost(profile.bassBoost);
        // Prefer the filter-derived safe headroom; fall back to the stored
        // preamp for legacy gain-curve profiles.
        final preamp =
            isParametric ? profile.computeSafePreamp() : profile.preampGain;
        await setPreamp(preamp);
      } else {
        selectedHeadphoneProfile = null;
        await setPreamp(0.0);
      }
    } catch (e, st) {
      currentPreset = prevPreset;
      comparisonSlots[activeComparisonSlot] = prevPreset;
      selectedHeadphoneProfile = prevProfile;
      ErrorLogger.log(
        'Failed to apply headphone profile',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
    _debouncedSavePreferences();
  }

  /// Pushes a profile's true parametric filters into the native 64-band EQ.
  /// Returns true only when the native bulk call ACKs, so the caller can fall
  /// back to the graphic-gain path on devices/paths without native PEQ.
  Future<bool> _applyParametricProfile(HeadphoneProfile profile) async {
    if (!PlatformCapabilities.isAndroid) return false;
    final filters = profile.filters;
    if (filters.isEmpty) return false;
    if (filters.length > equalizerMaxNativeBands) {
      ErrorLogger.log(
        'Profile ${profile.id} has ${filters.length} filters, '
        'exceeding the native $equalizerMaxNativeBands-band limit',
        category: 'EqualizerManager',
      );
      return false;
    }
    final frequencies = <double>[];
    final gains = <double>[];
    final qs = <double>[];
    final types = <int>[];
    for (final f in filters) {
      if (!f.frequency.isFinite || f.frequency <= 0 || !f.gain.isFinite) {
        continue;
      }
      frequencies.add(DspParamRanges.eqFilterFrequencyHz.clampRaw(f.frequency));
      gains.add(DspParamRanges.eqFilterGainDb.clampRaw(f.gain));
      qs.add(f.q.isFinite && f.q > 0
          ? DspParamRanges.eqFilterQ.clampRaw(f.q)
          : DspParamRanges.eqFilterQ.defaultValue);
      types.add(f.filterType);
    }
    if (frequencies.isEmpty) return false;
    final ok = await _effectsChannel.setNativeEqBandsBulk(
      frequencies: frequencies,
      gains: gains,
      qs: qs,
      types: types,
    );
    return ok;
  }

  bool _isDegradedForPower = false;
  bool _savedReverbEnabled = false;
  bool _savedCrossfeedEnabled = false;
  bool _savedSaturationEnabled = false;
  bool _savedStereoWidthEnabled = false;
  bool _savedLoudnessContourEnabled = false;
  bool _savedSubCrossoverEnabled = false;
  bool _savedDynamicEqEnabled = false;
  bool _savedDynamicsEnabled = false;
  bool _savedLimiterEnabled = false;
  bool _savedViperDdcEnabled = false;
  bool _savedArbitraryEqEnabled = false;
  bool _savedLiveProgEnabled = false;
  DynamicsPreset _savedDynamicsPreset = DynamicsPreset.off;

  /// A snapshot recall that arrived while battery-degraded. Held here (an
  /// extension cannot own fields) so [restoreFromDegrade] can apply it once the
  /// heavy stages are allowed back — see [EqualizerSnapshotOps.applyEffectsState].
  Map<String, dynamic>? _pendingDegradeEffectsSnapshot;

  /// BUG-04: deltas the user made to any pref while battery-degraded. Merged
  /// back in [restoreFromDegrade] so those changes are neither dropped nor
  /// clobbered by the pre-degrade snapshot.
  Map<String, dynamic>? _pendingDegradePrefs;

  /// The degraded-state pref map captured at the end of [degradeToEssentials],
  /// used to distinguish a user change from the degrade itself.
  Map<String, dynamic>? _degradeBaselinePrefs;

  /// BUG-22: true while [restoreFromDegrade] runs, so its intermediate setters
  /// do not schedule debounced saves over the final merged write.
  bool _restoringFromDegrade = false;

  bool get isDegradedForPower => _isDegradedForPower;

  /// Temporarily disables heavy DSP stages (reverb, crossfeed, saturation,
  /// stereo width, loudness contour, sub crossover, dynamic eq, dynamics, limiter,
  /// viper ddc, arbitrary eq, live prog) to conserve battery while preserving the core equalizer.
  Future<void> degradeToEssentials() async {
    if (_isDegradedForPower) return;
    _isDegradedForPower = true;
    _savedReverbEnabled = isReverbEnabled;
    _savedCrossfeedEnabled = isCrossfeedEnabled;
    _savedSaturationEnabled = isSaturationEnabled;
    _savedStereoWidthEnabled = isStereoWidthEnabled;
    _savedLoudnessContourEnabled = isLoudnessContourEnabled;
    _savedSubCrossoverEnabled = isSubCrossoverEnabled;
    _savedDynamicEqEnabled = isDynamicEqEnabled;
    _savedDynamicsEnabled = isDynamicsEnabled;
    _savedDynamicsPreset = dynamicsPreset;
    _savedLimiterEnabled = isLimiterEnabled;
    _savedViperDdcEnabled = isViperDdcEnabled;
    _savedArbitraryEqEnabled = isArbitraryEqEnabled;
    _savedLiveProgEnabled = isLiveProgEnabled;

    try {
      if (_savedReverbEnabled) await setReverb(false);
      if (_savedCrossfeedEnabled) await setCrossfeed(false);
      if (_savedSaturationEnabled) await setSaturation(false);
      if (_savedStereoWidthEnabled) await setStereoWidth(false);
      if (_savedLoudnessContourEnabled) await setLoudnessContour(false);
      if (_savedSubCrossoverEnabled) await setSubCrossover(false);
      if (_savedDynamicEqEnabled) await setDynamicEq(false);
      if (_savedDynamicsEnabled) {
        await setDynamicsPreset(dynamicsPreset, enabled: false);
      }
      if (_savedLimiterEnabled) await setLookaheadLimiter(false);
      if (_savedViperDdcEnabled) await setViperDdc(false);
      if (_savedArbitraryEqEnabled) await setArbitraryEq(false);
      if (_savedLiveProgEnabled) await setLiveProg(false);
    } catch (e, st) {
      // A throwing stage used to skip the baseline capture below, which made
      // _debouncedSavePreferences drop every later user change while degraded.
      ErrorLogger.log('degradeToEssentials stage failed',
          error: e, stackTrace: st, category: 'EqualizerManager');
    }
    // Capture the degraded state as the diff baseline AFTER disabling, so the
    // disable pass itself is never mistaken for a user change.
    _pendingDegradePrefs = null;
    _degradeBaselinePrefs = _buildSavePreferencesMap();
    _syncPipeline();
  }

  /// Restores DSP stages that were disabled during low power mode.
  Future<void> restoreFromDegrade() async {
    if (!_isDegradedForPower) return;
    _isDegradedForPower = false;
    _restoringFromDegrade = true;
    // Keys the user changed while degraded; those stages must keep the user's
    // value instead of reverting to the pre-degrade snapshot (BUG-04).
    final changed = _pendingDegradePrefs?.keys.toSet() ?? const <String>{};

    try {
      if (_savedReverbEnabled &&
          !changed.contains(PrefsKeys.convolutionReverbEnabled)) {
        await setReverb(true);
      }
      if (_savedCrossfeedEnabled &&
          !changed.contains(PrefsKeys.crossfeedEnabled)) {
        await setCrossfeed(true);
      }
      if (_savedSaturationEnabled &&
          !changed.contains(PrefsKeys.saturationEnabled)) {
        await setSaturation(true);
      }
      if (_savedStereoWidthEnabled &&
          !changed.contains(PrefsKeys.stereoWidthEnabled)) {
        await setStereoWidth(true);
      }
      if (_savedLoudnessContourEnabled &&
          !changed.contains(PrefsKeys.loudnessContourEnabled)) {
        await setLoudnessContour(true);
      }
      if (_savedSubCrossoverEnabled &&
          !changed.contains(PrefsKeys.subCrossoverEnabled)) {
        await setSubCrossover(true);
      }
      if (_savedDynamicEqEnabled &&
          !changed.contains(PrefsKeys.dynamicEqEnabled)) {
        await setDynamicEq(true);
      }
      if (_savedDynamicsEnabled &&
          !changed.contains(PrefsKeys.eqDynamicsEnabled)) {
        await setDynamicsPreset(_savedDynamicsPreset, enabled: true);
      }
      if (_savedLimiterEnabled &&
          !changed.contains(PrefsKeys.lookaheadLimiterEnabled)) {
        await setLookaheadLimiter(true);
      }
      if (_savedViperDdcEnabled &&
          !changed.contains(PrefsKeys.viperDdcEnabled)) {
        await setViperDdc(true);
      }
      // Re-pass the stored curves/code: the setters only (re)load native
      // content when it is supplied, otherwise just the enable flag is pushed
      // and the stage comes back empty.
      if (_savedArbitraryEqEnabled &&
          !changed.contains(PrefsKeys.arbitraryEqEnabled)) {
        await setArbitraryEq(
          true,
          eqString: arbitraryEqString.isNotEmpty ? arbitraryEqString : null,
        );
      }
      if (_savedLiveProgEnabled &&
          !changed.contains(PrefsKeys.liveProgEnabled)) {
        await setLiveProg(
          true,
          code: liveProgCode.isNotEmpty ? liveProgCode : null,
        );
      }
      // A snapshot recalled while degraded was deferred; apply it now that the
      // heavy stages are permitted again so the user's recall is not lost.
      final pending = _pendingDegradeEffectsSnapshot;
      _pendingDegradeEffectsSnapshot = null;
      if (pending != null) {
        await applyEffectsState(pending);
      }
    } catch (e, st) {
      ErrorLogger.log('restoreFromDegrade stage failed',
          error: e, stackTrace: st, category: 'EqualizerManager');
    } finally {
      // Must run even if a stage throws: a stuck _restoringFromDegrade
      // silently disabled ALL preference saving for the rest of the session.
      _pendingDegradePrefs = null;
      _degradeBaselinePrefs = null;
      _restoringFromDegrade = false;
    }
    // Persist the merged result exactly once (BUG-04/22).
    await _savePreferences();
    _syncPipeline();
  }

  // --- PHASE 1 DSP EXPANSION STAGES ---

  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
    int? mode,
    bool? multiband,
  }) async {
    if (drive != null) {
      saturationDrive = DspParamRanges.saturationDrive.clampRaw(drive);
    }
    if (mix != null) saturationMix = DspParamRanges.saturationMix.clampRaw(mix);
    if (tilt != null) {
      saturationTilt = DspParamRanges.saturationTilt.clampRaw(tilt);
    }
    if (mode != null) {
      saturationMode = DspParamRanges.saturationMode.clamp(mode);
    }
    if (multiband != null) saturationMultiband = multiband;
    final prevEnabled = isSaturationEnabled;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSaturationParams(
        saturationDrive,
        saturationMix,
        saturationTilt,
        mode: saturationMode,
      );
      if (multiband != null) {
        await _effectsChannel.setSaturationMultiband(saturationMultiband);
      }
      if (enabled != prevEnabled) {
        await _effectsChannel.setSaturationEnabled(enabled);
      }
    }
    isSaturationEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setSaturationMultiband(bool multiband) async {
    saturationMultiband = multiband;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSaturationMultiband(multiband);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  // --- JAMESDSP FEATURE PARITY STAGES ---

  Future<void> setViperDdc(
    bool enabled, {
    String? profileName,
    List<double>? coeffs,
    String? ddcContent,
  }) async {
    final prevDdcContent = viperDdcContent;
    final prevDdcName = viperDdcProfileName;
    if (profileName != null) viperDdcProfileName = profileName;
    final resolvedContent = ddcContent ??
        (coeffs != null && coeffs.isNotEmpty ? coeffs.join(' ') : null);
    if (resolvedContent != null && resolvedContent.isNotEmpty) {
      viperDdcContent = resolvedContent;
    }
    if (PlatformCapabilities.isAndroid) {
      if (viperDdcContent.isNotEmpty && enabled) {
        final loaded = await _effectsChannel.loadViperDdc(
          ddcContent: viperDdcContent,
          profileName: viperDdcProfileName,
        );
        if (!loaded) {
          // Roll back: the rejected profile would otherwise be saved and
          // re-pushed on every reattach.
          viperDdcContent = prevDdcContent;
          viperDdcProfileName = prevDdcName;
          throw StateError('ViPER-DDC profile was rejected');
        }
      } else if (resolvedContent != null && resolvedContent.isNotEmpty) {
        final loaded = await _effectsChannel.loadViperDdc(
          ddcContent: resolvedContent,
          profileName: profileName ?? viperDdcProfileName,
        );
        if (!loaded) {
          // Roll back: the rejected profile would otherwise be saved and
          // re-pushed on every reattach.
          viperDdcContent = prevDdcContent;
          viperDdcProfileName = prevDdcName;
          throw StateError('ViPER-DDC profile was rejected');
        }
      }
      await _effectsChannel.setViperDdcEnabled(enabled);
    }
    isViperDdcEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Sets the loudness contour. The contour lift is computed against
  /// [loudnessVolumeLinear], which is kept in sync with the playback volume
  /// stage via [updateLoudnessVolume].
  ///
  /// On a genuine OFF->ON transition the driving volume is seeded from the
  /// ANDROID system STREAM_MUSIC volume so the equal-loudness lift engages
  /// against the hardware level, not the in-app software slider (which
  /// defaults to 100% and left the contour inert). The audio handler keeps it
  /// in sync afterwards from the onSystemVolumeChanged stream.
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    final wasEnabled = isLoudnessContourEnabled;
    if (intensity != null) {
      loudnessContourIntensity =
          DspParamRanges.loudnessContourIntensity.clampRaw(intensity);
    }
    if (enabled && !wasEnabled && PlatformCapabilities.isAndroid) {
      // Query once on enable. getSystemMusicVolume returns 1.0 when
      // unavailable, which gates the lift off (the safe default); the previous
      // software-fed [loudnessVolumeLinear] is only overwritten with a finite
      // in-range reading, so an error leaves the existing value as fallback.
      try {
        final sysRatio = await _effectsChannel.getSystemMusicVolume();
        if (sysRatio.isFinite && sysRatio >= 0.0) {
          loudnessVolumeLinear =
              DspParamRanges.volumeLinear.clampRaw(sysRatio);
        }
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to seed loudness contour from system volume',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLoudnessContourParams(
        loudnessContourIntensity,
        loudnessVolumeLinear,
      );
      await _effectsChannel.setLoudnessContourEnabled(enabled);
    }
    isLoudnessContourEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  bool autoLoudnessContour = true;
  bool _autoLoudnessEngaged = false;
  double autoLoudnessLowThreshold = 0.3;
  double autoLoudnessHighThreshold = 0.5;

  /// Pushes the current volume-stage value to the engine so the loudness
  /// contour follows the listening level. Automatically toggles loudness contour
  /// on when volume drops below 0.3 and off when it rises above 0.5.
  Future<void> updateLoudnessVolume(double volumeLinear) async {
    loudnessVolumeLinear = DspParamRanges.volumeLinear.clampRaw(volumeLinear);
    if (autoLoudnessContour && !_isDegradedForPower && !isBitPerfectBypass) {
      if (loudnessVolumeLinear <= autoLoudnessLowThreshold &&
          !isLoudnessContourEnabled) {
        _autoLoudnessEngaged = true;
        await setLoudnessContour(true, intensity: 0.6);
      } else if (loudnessVolumeLinear >= autoLoudnessHighThreshold &&
          _autoLoudnessEngaged) {
        _autoLoudnessEngaged = false;
        await setLoudnessContour(false);
      }
    }
    if (PlatformCapabilities.isAndroid && isLoudnessContourEnabled) {
      await _effectsChannel.setLoudnessContourParams(
        loudnessContourIntensity,
        loudnessVolumeLinear,
      );
    }
  }

  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
    bool? bassMono,
    bool? antiPop,
  }) async {
    if (cornerHz != null) {
      subCrossoverCornerHz =
          DspParamRanges.subCrossoverCornerHz.clampRaw(cornerHz);
    }
    if (slopeDbPerOct != null) {
      subCrossoverSlopeDbPerOct = slopeDbPerOct < 18.0 ? 12.0 : 24.0;
    }
    if (gain != null) {
      subCrossoverGain = DspParamRanges.subCrossoverGain.clampRaw(gain);
    }
    if (bassMono != null) subCrossoverBassMono = bassMono;
    if (antiPop != null) subCrossoverAntiPop = antiPop;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSubCrossoverParams(
        subCrossoverCornerHz,
        subCrossoverSlopeDbPerOct,
        subCrossoverGain,
        bassMono: subCrossoverBassMono,
        antiPop: subCrossoverAntiPop,
      );
      await _effectsChannel.setSubCrossoverEnabled(enabled);
    }
    isSubCrossoverEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setDynamicEq(bool enabled) async {
    if (PlatformCapabilities.isAndroid) {
      await _pushDynamicEqConfig();
      await _effectsChannel.setDynamicEqEnabled(enabled);
    }
    isDynamicEqEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    if (index < 0 || index >= dynamicEqBands.length) {
      ErrorLogger.log(
        'Rejected DynamicEQ band index $index (0..${dynamicEqBands.length - 1})',
        category: 'EqualizerManager',
      );
      return;
    }
    // Sanitize to the ranges the native DynamicEQ stage honors (see
    // DynamicEQ::setBand) so the stored Dart state never diverges from what
    // the DSP actually applies.
    final sanitized = band.sanitized();
    final bands = List<DynamicEqBandConfig>.from(dynamicEqBands);
    bands[index] = sanitized;
    dynamicEqBands = bands;
    if (PlatformCapabilities.isAndroid && isDynamicEqEnabled) {
      await _effectsChannel.setDynamicEqBand(
        index,
        frequency: sanitized.frequency,
        q: sanitized.q,
        thresholdDb: sanitized.thresholdDb,
        ratio: sanitized.ratio,
        attackMs: sanitized.attackMs,
        releaseMs: sanitized.releaseMs,
        maxCutDb: sanitized.maxCutDb,
        maxBoostDb: sanitized.maxBoostDb,
        mode: sanitized.mode,
        filterType: sanitized.filterType,
        enabled: sanitized.enabled,
      );
    }
    _debouncedSavePreferences();
  }

  Future<void> addDynamicEqBand() async {
    if (dynamicEqBands.length >= 8) return;
    final bands = List<DynamicEqBandConfig>.from(dynamicEqBands);
    bands.add(const DynamicEqBandConfig());
    dynamicEqBands = bands;
    if (PlatformCapabilities.isAndroid && isDynamicEqEnabled) {
      await _pushDynamicEqConfig();
    }
    _debouncedSavePreferences();
  }

  Future<void> removeDynamicEqBand(int index) async {
    if (index < 0 || index >= dynamicEqBands.length) {
      ErrorLogger.log(
        'Rejected DynamicEQ band removal at index $index',
        category: 'EqualizerManager',
      );
      return;
    }
    final bands = List<DynamicEqBandConfig>.from(dynamicEqBands);
    bands.removeAt(index);
    dynamicEqBands = bands;
    if (PlatformCapabilities.isAndroid && isDynamicEqEnabled) {
      await _pushDynamicEqConfig();
    }
    _debouncedSavePreferences();
  }

  /// Pushes band count + every band (bulk) so the native DynamicEQ stage
  /// matches the Dart-side band list atomically.
  Future<void> _pushDynamicEqConfig() async {
    if (!PlatformCapabilities.isAndroid) return;
    await _effectsChannel.setDynamicEqBandCount(dynamicEqBands.length);
    for (int i = 0; i < dynamicEqBands.length; i++) {
      final band = dynamicEqBands[i];
      await _effectsChannel.setDynamicEqBand(
        i,
        frequency: band.frequency,
        q: band.q,
        thresholdDb: band.thresholdDb,
        ratio: band.ratio,
        attackMs: band.attackMs,
        releaseMs: band.releaseMs,
        maxCutDb: band.maxCutDb,
        maxBoostDb: band.maxBoostDb,
        mode: band.mode,
        filterType: band.filterType,
        enabled: band.enabled,
      );
    }
  }

  Future<void> setMultibandCompressor(
    bool enabled, {
    List<MultibandCompressorBandConfig>? bands,
    double? f0,
    double? f1,
    double? f2,
  }) async {
    if (bands != null) multibandCompressorBands = List.from(bands);
    if (f0 != null) {
      multibandCompressorF0 = DspParamRanges.multibandCompressorF0.clampRaw(f0);
    }
    if (f1 != null) {
      multibandCompressorF1 = DspParamRanges.multibandCompressorF1.clampRaw(f1);
    }
    if (f2 != null) {
      multibandCompressorF2 = DspParamRanges.multibandCompressorF2.clampRaw(f2);
    }
    // Crossovers must stay strictly ordered (f0 < f1 < f2); individual
    // clamps alone allow inversions such as f0=500 > f1=200.
    if (multibandCompressorF1 <= multibandCompressorF0) {
      multibandCompressorF1 = DspParamRanges.multibandCompressorF1
          .clampRaw(multibandCompressorF0 + 50.0);
    }
    if (multibandCompressorF2 <= multibandCompressorF1) {
      multibandCompressorF2 = DspParamRanges.multibandCompressorF2
          .clampRaw(multibandCompressorF1 + 500.0);
    }
    // Second pass: the clamps above can themselves collapse the ordering at
    // the range edges, so pull the lower crossover down instead.
    if (multibandCompressorF1 <= multibandCompressorF0) {
      multibandCompressorF0 = DspParamRanges.multibandCompressorF0
          .clampRaw(multibandCompressorF1 - 50.0);
    }
    if (multibandCompressorF2 <= multibandCompressorF1) {
      multibandCompressorF1 = DspParamRanges.multibandCompressorF1
          .clampRaw(multibandCompressorF2 - 500.0);
    }
    if (PlatformCapabilities.isAndroid) {
      await _pushMultibandCompressorConfig();
      await _effectsChannel.setMultibandCompressorEnabled(enabled);
    }
    isMultibandCompressorEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setMultibandCompressorBand(
    int index,
    MultibandCompressorBandConfig band,
  ) async {
    if (index < 0 || index >= multibandCompressorBands.length) {
      ErrorLogger.log(
        'Rejected multiband compressor band index $index',
        category: 'EqualizerManager',
      );
      return;
    }
    final bands =
        List<MultibandCompressorBandConfig>.from(multibandCompressorBands);
    bands[index] = band;
    multibandCompressorBands = bands;
    if (PlatformCapabilities.isAndroid && isMultibandCompressorEnabled) {
      await _effectsChannel.setMultibandCompressorBand(
        index,
        thresholdDb: band.thresholdDb,
        ratio: band.ratio,
        attackMs: band.attackMs,
        releaseMs: band.releaseMs,
        kneeDb: band.kneeDb,
        makeupGainDb: band.makeupGainDb,
        enabled: band.enabled,
      );
    }
    _debouncedSavePreferences();
  }

  Future<void> _pushMultibandCompressorConfig() async {
    if (!PlatformCapabilities.isAndroid) return;
    await _effectsChannel.setMultibandCompressorCrossovers(
      f0: multibandCompressorF0,
      f1: multibandCompressorF1,
      f2: multibandCompressorF2,
    );
    for (int i = 0; i < multibandCompressorBands.length; i++) {
      final band = multibandCompressorBands[i];
      await _effectsChannel.setMultibandCompressorBand(
        i,
        thresholdDb: band.thresholdDb,
        ratio: band.ratio,
        attackMs: band.attackMs,
        releaseMs: band.releaseMs,
        kneeDb: band.kneeDb,
        makeupGainDb: band.makeupGainDb,
        enabled: band.enabled,
      );
    }
  }

  // --- NATIVE C++ DYNAMIC BASS (DYNAMIC SYSTEM) ---

  Future<void> setDynamicBass({
    required bool enabled,
    double? strength,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
    int? preset,
  }) async {
    if (strength != null) {
      dynamicBassStrength =
          DspParamRanges.dynamicBassStrength.clampRaw(strength);
    }
    if (preset != null) {
      dynamicBassPreset = DspParamRanges.dynamicBassPreset.clamp(preset);
    }
    if (dynamicBassPreset > 0) {
      if (xLow != null ||
          xHigh != null ||
          yLow != null ||
          yHigh != null ||
          sideGainLow != null ||
          sideGainHigh != null) {
        ErrorLogger.log(
          'Custom DynamicBass values ignored while preset $dynamicBassPreset is active',
          category: 'EqualizerManager',
        );
      }
      final p = DynamicBassConfig.builtinPresets.firstWhere(
        (it) => it.id == dynamicBassPreset,
        orElse: () => DynamicBassConfig.builtinPresets.first,
      );
      dynamicBassXLow = p.xLow;
      dynamicBassXHigh = p.xHigh;
      dynamicBassYLow = p.yLow;
      dynamicBassYHigh = p.yHigh;
      dynamicBassSideGainLow = p.sideGainLow;
      dynamicBassSideGainHigh = p.sideGainHigh;
    } else {
      if (xLow != null) {
        dynamicBassXLow = DspParamRanges.dynamicBassXLow.clamp(xLow);
      }
      if (xHigh != null) {
        dynamicBassXHigh = DspParamRanges.dynamicBassXHigh.clamp(xHigh);
      }
      if (yLow != null) {
        dynamicBassYLow = DspParamRanges.dynamicBassYLow.clamp(yLow);
      }
      if (yHigh != null) {
        dynamicBassYHigh = DspParamRanges.dynamicBassYHigh.clamp(yHigh);
      }
      if (sideGainLow != null) {
        dynamicBassSideGainLow =
            DspParamRanges.dynamicBassSideGainLow.clampRaw(sideGainLow);
      }
      if (sideGainHigh != null) {
        dynamicBassSideGainHigh =
            DspParamRanges.dynamicBassSideGainHigh.clampRaw(sideGainHigh);
      }
    }

    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setDynamicBassParams(
        enabled: enabled,
        strength: dynamicBassStrength,
        xLow: dynamicBassXLow,
        xHigh: dynamicBassXHigh,
        yLow: dynamicBassYLow,
        yHigh: dynamicBassYHigh,
        sideGainLow: dynamicBassSideGainLow,
        sideGainHigh: dynamicBassSideGainHigh,
        devicePreset: dynamicBassPreset,
      );
    }
    isDynamicBassEnabled = enabled;
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Owned bypass: stores state, pushes to native (with DoP mirror), and
  /// syncs the pipeline mirror so reattach/route resync restores it.
  Future<void> setBypassDspForBitPerfect(bool bypass, {bool? isDop}) async {
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setBypassDspForBitPerfect(bypass, isDop: isDop);
    }
    isBitPerfectBypass = bypass;
    _syncPipeline();
  }

  /// Level-Matched A/B Bypass: instant level-matched A/B comparison without volume drop.
  Future<void> setBypassCompare({
    required bool bypass,
    double gainCompensationDb = 0.0,
  }) async {
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setBypassCompare(
        bypass: bypass,
        gainCompensationDb: gainCompensationDb,
      );
    }
  }

  /// Owned DSP-preference routing. Persisted to the same key SettingsCubit
  /// uses, so both writers converge instead of diverging.
  Future<void> setDspPreference(String preference) async {
    final p = preference.toLowerCase();
    dspPreference = (p == 'oem' || p == 'auto') ? p : 'native';
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setDspPreference(dspPreference);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// TPDF dither toggle (native stage; auto-skipped on BT routes unless
  /// [allowBluetoothDither] is set by the Bluetooth Hi-Res opt-in).
  Future<void> setDither(bool enabled,
      {int? targetBitDepth, bool? allowBluetoothDither}) async {
    isDitherEnabled = enabled;
    if (targetBitDepth != null &&
        (targetBitDepth == 16 ||
            targetBitDepth == 24 ||
            targetBitDepth == 32)) {
      ditherTargetBitDepth = targetBitDepth;
    }
    if (allowBluetoothDither != null) {
      isBluetoothDitherEnabled = allowBluetoothDither;
    }
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setDitherParams(
        enabled: isDitherEnabled,
        targetBitDepth: ditherTargetBitDepth,
        isBluetooth: isBluetoothRoute,
        allowBluetoothDither: isBluetoothDitherEnabled,
      );
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Mirrors all locally-owned flags into the attached pipeline inspector.
  void _syncPipeline() {
    _dspPipeline?.updateState(
      isEqEnabled: isEnabled,
      isArbitraryEqEnabled: isArbitraryEqEnabled,
      isViperDdcEnabled: isViperDdcEnabled,
      isDynamicEqEnabled: isDynamicEqEnabled,
      isMultibandCompressorEnabled: isMultibandCompressorEnabled,
      isCrossfeedEnabled: isCrossfeedEnabled,
      isReverbEnabled: isReverbEnabled,
      stereoBalance: stereoBalance,
      isMonoMix: monoMix,
      isSaturationEnabled: isSaturationEnabled,
      isLiveProgEnabled: isLiveProgEnabled,
      isStereoWidthEnabled: isStereoWidthEnabled,
      isSubCrossoverEnabled: isSubCrossoverEnabled,
      isDynamicBassEnabled: isDynamicBassEnabled,
      isLoudnessContourEnabled: isLoudnessContourEnabled,
      isLimiterEnabled: isLimiterEnabled,
      bitPerfectBypass: isBitPerfectBypass,
    );
  }

  OptimizedDspPipeline? _dspPipeline;

  /// Attaches the DSP pipeline so native latency syncs automatically update the pipeline.
  void attachDspPipeline(OptimizedDspPipeline pipeline) {
    _dspPipeline = pipeline;
    _syncPipeline();
  }

  Future<int> syncNativeLatency(double sampleRate,
      {OptimizedDspPipeline? dspPipeline, double? outputRate}) async {
    if (!PlatformCapabilities.isAndroid) return 0;
    try {
      final frames = await _effectsChannel.getPipelineLatencyFrames();
      // Track-rate -> device-rate conversion. Only push when the device rate
      // is known: pushing (rate, rate) forces a permanent resampler bypass,
      // which skips needed 44.1k <-> 48k conversion.
      if (isSincResamplerEnabled &&
          outputRate != null &&
          outputRate > 0 &&
          sampleRate > 0) {
        await _effectsChannel.setSincResamplerRates(sampleRate, outputRate);
      }
      (dspPipeline ?? _dspPipeline)
          ?.updateNativeLatency(frames: frames, sampleRate: sampleRate);
      return frames;
    } catch (_) {
      return 0;
    }
  }

  /// Serializes re-attach + resync operations so concurrent session ids and
  /// route changes can never race release/recreate on the native side.
  Future<void> _reattachChain = Future<void>.value();
  int? _pendingReattachSessionId;
  int? _lastAppliedSessionId;

  /// Last audio session the HAL chain was successfully bound to.
  /// Exposed for diagnostics; written on reattach success, cleared on failure.
  int? get lastAppliedSessionId => _lastAppliedSessionId;

  /// Re-attaches all active effects to a new [sessionId] that ExoPlayer
  /// creates after `stop()` + `setAudioSource()`. This is called every time
  /// the player establishes a new audio session (e.g. on every track change
  /// when using `playSongAt`, or after restoring from a background kill).
  ///
  /// Unlike [_restorePreferences] this does NOT reload prefs from disk — it
  /// uses the already-live in-memory state, making it safe to call on the
  /// hot path without any I/O.
  ///
  /// Ordering contract (release -> setAudioSessionId -> re-apply):
  ///   1. `releaseEffects()` detaches every old-session AudioEffect instance
  ///      (and clears native dedup caches so the re-push below is applied).
  ///   2. `setAudioSessionId(sessionId)` recreates the HAL effect chain bound
  ///      to the new session.
  ///   3. The full current effect state (enabled flags, band count, bands,
  ///      presets) is re-pushed so nothing survives from the old session.
  ///
  /// Idempotence: a repeated event for the session id that is already applied
  /// does not release/recreate anything. Concurrent calls are serialized and
  /// collapsed — if a newer id arrives while an older one is still applying,
  /// only the newest one is ultimately applied.
  Future<void> reapplyToSession(int sessionId) async {
    if (!PlatformCapabilities.isAndroid) {
      return;
    }
    if (sessionId <= 0) {
      return; // 0 = no session yet; never attach to the global mix
    }
    _pendingReattachSessionId = sessionId;
    // Serialize the reattach through _effectsLock (not just _reattachChain) so a
    // release -> re-push cannot interleave with a concurrent _flushBandGains or
    // _savePreferences, both of which already hold _effectsLock. _runReattach /
    // _pushFullEffectState push native via _effectsChannel directly and never
    // re-enter _effectsLock, so this cannot deadlock. _reattachChain still
    // collapses rapid session ids down to the newest.
    _reattachChain = _reattachChain
        .then((_) => _effectsLock.lock(() => _runReattach()))
        .catchError((
      Object e,
      StackTrace st,
    ) {
      ErrorLogger.log(
        'reapplyToSession chain failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    });
    await _reattachChain;
  }

  /// Re-pushes the full current effect state onto the LIVE session without
  /// releasing or recreating any effect. Used on audio route changes
  /// (Bluetooth <-> speaker) where the session id stays the same but the HAL
  /// chain was re-initialized by the platform, and after interruptions that
  /// ended the audio focus. Idempotent and safe to call repeatedly.
  Future<void> resyncActiveEffects() async {
    if (!PlatformCapabilities.isAndroid) return;
    // Same locking rationale as reapplyToSession: push the full state under
    // _effectsLock so it cannot interleave with a band-gain flush / pref write.
    _reattachChain = _reattachChain
        .then((_) => _effectsLock.lock(() => _pushFullEffectState()))
        .catchError((Object e, StackTrace st) {
      ErrorLogger.log(
        'resyncActiveEffects failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    });
    await _reattachChain;
  }

  Future<void> _runReattach() async {
    final sessionId = _pendingReattachSessionId;
    _pendingReattachSessionId = null;
    // null = a newer queued call already applied the collapsed newest id.
    if (sessionId == null) return;
    if (sessionId <= 0) {
      ErrorLogger.log(
        'Skipping reattach: invalid session ID $sessionId',
        category: 'EqualizerManager',
      );
      return;
    }
    // FIX M-11: ExoPlayer can reuse same session ID after underrun/gapless;
    // always reapply to ensure effects survive AudioTrack recreation.
    // We still gate on an identical full-state fingerprint below if needed.
    try {
      ErrorLogger.log(
        'Reattaching effects to session $sessionId',
        category: 'EqualizerManager',
      );
      await _effectsChannel.releaseEffects();
      ErrorLogger.log('Released old effects', category: 'EqualizerManager');
      await _effectsChannel.setAudioSessionId(sessionId);
      ErrorLogger.log(
        'Set audio session ID: $sessionId',
        category: 'EqualizerManager',
      );
      await _pushFullEffectState();
      ErrorLogger.log(
        'Pushed full effect state to session $sessionId',
        category: 'EqualizerManager',
      );
      // Mark applied only on success so a later same-id event can retry a
      // failed attach (e.g. channel timeout while the HAL was still settling).
      _lastAppliedSessionId = sessionId;
      ErrorLogger.log(
        'Successfully reattached to session $sessionId',
        category: 'EqualizerManager',
      );
    } catch (e, st) {
      ErrorLogger.log(
        'reapplyToSession($sessionId) failed',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      _lastAppliedSessionId = null; // Reset so next attempt will retry
    }
  }

  /// Pushes every active effect (enabled flags, band count, bands, presets)
  /// to the native stack. Assumes the session is already established — either
  /// after [_runReattach] recreated it or after a route change.
  Future<void> _pushFullEffectState() async {
    // Always initialize the baseline EQ effect chain so AudioEffect instances
    // are created and attached to the session. This ensures isSessionAttached=true.
    // The EQ will be enabled/disabled based on actual state.
    final futures = <Future<void>>[];

    // Routing truth first: preference + bypass + dither must precede stage
    // pushes, otherwise a reattach re-enables stages that bypass should mute.
    try {
      await _effectsChannel.setDspPreference(dspPreference);
      await _effectsChannel.setBypassDspForBitPerfect(isBitPerfectBypass);
      await _effectsChannel.setDitherParams(
        enabled: isDitherEnabled,
        targetBitDepth: ditherTargetBitDepth,
        isBluetooth: isBluetoothRoute,
        allowBluetoothDither: isBluetoothDitherEnabled,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to push routing truth (preference/bypass/dither)',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }

    if (isBitPerfectBypass) {
      // In Bit-Perfect bypass mode, all DSP stages must remain completely disabled.
      // Skipping the remaining stage pushes avoids wasting JNI roundtrips and prevents
      // transient leakage before the native bypass gate takes full effect.
      return;
    }

    // Initialize EQ chain with current band configuration and enable state
    try {
      final freqs = activeFrequencies;
      await _effectsChannel.setNativeEqBandCount(freqs.length);

      if (isEnabled) {
        await applyCurrentPreset();
      }

      await _effectsChannel.setEqEnabled(isEnabled);
      await _effectsChannel.setNativeEqEnabled(isEnabled);
      // Native eqPreampDb resets to 0 whenever the plugin is re-created.
      // Restore the persisted manual preamp, falling back to the headphone
      // profile preamp only when no manual value was stored.
      final storedPreamp = preampDb;
      final effectivePreamp = storedPreamp != 0.0
          ? storedPreamp
          : (selectedHeadphoneProfile?.preampGain ?? 0.0);
      await _effectsChannel.setEqPreamp(effectivePreamp);
      if (storedPreamp == 0.0) preampDb = effectivePreamp;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to initialize EQ chain',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
      // Continue even if EQ init fails - other effects may still work
    }

    if (currentPreset.bassBoost > 0) {
      // Direct channel call to avoid _debouncedSavePreferences thrash on hot path (track change)
      final milliBels =
          (currentPreset.bassBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setBassBoost(milliBels));
    }
    if (volumeBoost > 0) {
      final milliBels = (volumeBoost.clamp(0.0, 1.0) * 1000).round();
      futures.add(_effectsChannel.setVolumeBoost(milliBels));
    }
    if (isVirtualizerEnabled && _effectsChannel.isVirtualizerSupported) {
      // FIX M-9: skip no-op IPC when virtualizer is not supported
      futures.add(_effectsChannel.setVirtualizerEnabled(true));
      futures.add(_effectsChannel.setVirtualizerStrength(virtualizerStrength));
    }
    if (isSpatializerEnabled) {
      // Guarded fallback: on devices without a Spatializer API this also
      // re-asserts the virtualizer, so reattach matches the public setter.
      futures.add(_applySpatializerWithFallback(true));
    }
    if (isCrossfeedEnabled) {
      futures.add(
        _effectsChannel.setCrossfeedParams(
          crossfeedDelayUs,
          crossfeedFeedDb,
          fcut: crossfeedFcut,
        ),
      );
      futures.add(_effectsChannel.setCrossfeedMode(crossfeedMode));
      futures.add(_effectsChannel.setCrossfeedEnabled(true));
    }
    if (isLimiterEnabled) {
      futures.add(
        _effectsChannel.setLimiterParams(
          limiterLookaheadMs,
          limiterThresholdDb,
          limiterReleaseMs,
          ratio: _hasStoredCompressorParams ? compressorRatio : null,
          attackMs: _hasStoredCompressorParams ? compressorAttackMs : null,
          makeupGainDb:
              _hasStoredCompressorParams ? compressorMakeupGainDb : null,
        ),
      );
      futures.add(_effectsChannel.setLimiterEnabled(true));
    }
    if (isReverbEnabled) {
      futures.add(_effectsChannel.setReverbWetDry(reverbWetDry));
      futures.add(
        _effectsChannel.setReverbParams(
          predelayMs: reverbPredelayMs,
          damping: reverbDamping,
          crossChannel: reverbCrossChannel,
        ),
      );
      if (reverbPreset == ReverbPreset.custom.wireValue &&
          customImpulseResponse.isNotEmpty) {
        futures.add(_effectsChannel.loadImpulseResponse(customImpulseResponse));
      } else {
        futures.add(_effectsChannel.setReverbPreset(reverbPreset));
      }
      futures.add(_effectsChannel.setReverbEnabled(true));
    }
    if (stereoBalance != 0.0) {
      futures.add(_effectsChannel.setStereoBalance(stereoBalance));
    }
    if (monoMix) futures.add(_effectsChannel.setMonoMix(true));
    // Re-assert the resampler so a user-disabled resampler stays disabled
    // after a reattach/route change instead of silently reverting to ON.
    futures.add(
      _effectsChannel.setSincResamplerEnabled(isSincResamplerEnabled),
    );
    if (isSaturationEnabled) {
      futures.add(
        _effectsChannel.setSaturationParams(
          saturationDrive,
          saturationMix,
          saturationTilt,
          mode: saturationMode,
        ),
      );
      futures.add(
        _effectsChannel.setSaturationMultiband(saturationMultiband),
      );
      futures.add(_effectsChannel.setSaturationEnabled(true));
    }
    if (isStereoWidthEnabled) {
      futures.add(
        _effectsChannel.setStereoWidthParams(
          stereoWidth,
          multiband: stereoWidthMultiband,
          lowWidth: stereoWidthLow,
          midWidth: stereoWidthMid,
          highWidth: stereoWidthHigh,
          lowCrossoverHz: stereoWidthLowCrossoverHz,
          highCrossoverHz: stereoWidthHighCrossoverHz,
        ),
      );
      futures.add(_effectsChannel.setStereoWidthEnabled(true));
    }
    if (isLoudnessContourEnabled) {
      futures.add(
        _effectsChannel.setLoudnessContourParams(
          loudnessContourIntensity,
          loudnessVolumeLinear,
        ),
      );
      futures.add(_effectsChannel.setLoudnessContourEnabled(true));
    }
    if (isSubCrossoverEnabled) {
      futures.add(
        _effectsChannel.setSubCrossoverParams(
          subCrossoverCornerHz,
          subCrossoverSlopeDbPerOct,
          subCrossoverGain,
          bassMono: subCrossoverBassMono,
          antiPop: subCrossoverAntiPop,
        ),
      );
      futures.add(_effectsChannel.setSubCrossoverEnabled(true));
    }
    if (isDynamicEqEnabled) {
      futures.add(_pushDynamicEqConfig());
      futures.add(_effectsChannel.setDynamicEqEnabled(true));
    }
    if (isMultibandCompressorEnabled) {
      futures.add(_pushMultibandCompressorConfig());
      futures.add(
        _effectsChannel.setMultibandCompressorEnabled(true),
      );
    }
    if (isDynamicBassEnabled) {
      futures.add(
        _effectsChannel.setDynamicBassParams(
          enabled: true,
          strength: dynamicBassStrength,
          xLow: dynamicBassXLow,
          xHigh: dynamicBassXHigh,
          yLow: dynamicBassYLow,
          yHigh: dynamicBassYHigh,
          sideGainLow: dynamicBassSideGainLow,
          sideGainHigh: dynamicBassSideGainHigh,
          devicePreset: dynamicBassPreset,
        ),
      );
    }
    if (isViperDdcEnabled) {
      if (viperDdcContent.isNotEmpty) {
        futures.add(_effectsChannel.loadViperDdc(
          ddcContent: viperDdcContent,
          profileName: viperDdcProfileName,
        ));
      }
      futures.add(_effectsChannel.setViperDdcEnabled(true));
    }
    if (isArbitraryEqEnabled && arbitraryEqString.isNotEmpty) {
      futures.add(_effectsChannel.loadArbitraryEq(
        eqString: arbitraryEqString,
        linearPhase: arbitraryEqLinearPhase,
      ));
      futures.add(_effectsChannel.setArbitraryEqEnabled(true));
    }
    if (isLiveProgEnabled && liveProgCode.isNotEmpty) {
      futures.add(_effectsChannel.loadLiveProgCode(liveProgCode));
      futures.add(_effectsChannel.setLiveProgEnabled(true));
      for (final entry in liveProgSliders.entries) {
        futures.add(_effectsChannel.setLiveProgSlider(entry.key, entry.value));
      }
    }

    // Partial-failure tolerance: one failing effect must not abort the rest.
    // FIX-H02: Wrap Future.wait in try/catch without rethrowing so one failure does not abort other effects
    if (futures.isNotEmpty) {
      try {
        await Future.wait(
          futures.map(
            (f) => f.then<void>((_) {}).catchError((Object e) {
              ErrorLogger.log(
                'Effect push failed (continuing with remaining effects)',
                error: e,
                category: 'EqualizerManager',
              );
            }),
          ),
          eagerError: false,
        );
      } catch (e, st) {
        ErrorLogger.log(
          'Future.wait failed while reapplying effects',
          error: e,
          stackTrace: st,
          category: 'EqualizerManager',
        );
      }
    }

    // Dynamics last: recalculateActiveStages may disable the OEM engine.
    if (isDynamicsEnabled && !_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
    }

    if (isReverbEnabled || isViperDdcEnabled || isArbitraryEqEnabled) {
      await _effectsChannel.sendWarmupBuffer(durationMs: 100);
    }

    // Readback verification to catch parameter drift
    try {
      final verified = await _effectsChannel.verifyState();
      if (verified != null) {
        bool matches = true;
        if (verified.containsKey('eqEnabled') &&
            verified['eqEnabled'] != isEnabled) {
          matches = false;
        }
        if (verified.containsKey('preampDb') && verified['preampDb'] is num) {
          final diff =
              ((verified['preampDb'] as num).toDouble() - preampDb).abs();
          if (diff > 1e-4) matches = false;
        }
        if (!matches) {
          // Re-push once
          await _effectsChannel.setEqEnabled(isEnabled);
          await _effectsChannel.setEqPreamp(preampDb);
          final recheck = await _effectsChannel.verifyState();
          if (recheck != null) {
            final recheckPreamp =
                (recheck['preampDb'] as num?)?.toDouble() ?? preampDb;
            if ((recheckPreamp - preampDb).abs() > 1e-4 ||
                recheck['eqEnabled'] != isEnabled) {
              ErrorLogger.log(
                'DSP parameter readback verification mismatch after retry',
                category: 'EqualizerManager',
              );
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log(
        'DSP readback verification error',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }

    unawaited(_effectsChannel.getAutoDegradedStages());
  }

  void dispose() {
    _isDisposed = true;
    // Flush pending work instead of dropping it: disposing mid-drag
    // otherwise loses the last ~60ms of slider movement and ~350ms of prefs.
    if (_pendingBandGains.isNotEmpty) {
      final pending = Map<int, double>.from(_pendingBandGains);
      _pendingBandGains.clear();
      unawaited(_flushBandGains(pending));
    }
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _bandGainDebounce?.cancel();
    _bandGainDebounce = null;
    _performSavePreferencesSync();
    try {
      effectStatusNotifier.dispose();
    } catch (_) {}
  }
}
