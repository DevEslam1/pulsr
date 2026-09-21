// lib/data/audio/equalizer_manager.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueNotifier;
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
import 'eq_frequency_validation.dart';
import 'headphone_profiles_repository.dart';
import 'ir_file_parser.dart';
import 'live_prog_slider_persistence.dart';
import 'optimized_dsp_pipeline.dart';

export 'comparison_slot.dart';
export 'async_lock.dart' show AsyncLock;

part 'equalizer_preset_ops.dart';
part 'equalizer_snapshot_ops.dart';

class EqualizerManager {
  final AndroidLoudnessEnhancer? loudnessEnhancerA;
  final AndroidLoudnessEnhancer? loudnessEnhancerB;
  final AudioEffectsChannel _effectsChannel = AudioEffectsChannel();
  Timer? _saveDebounce;
  Timer? _bandGainDebounce;
  final Map<int, double> _pendingBandGains = {};
  final _effectsLock =
      AsyncLock(); // Serializes concurrent effect state changes

  /// Per-effect truthful status: a key is present only while the most recent
  /// native apply attempt was rejected (unsupported capability, build failure,
  /// or no attached session). The UI reads this so an ON control cannot
  /// silently mean "no audible effect". Updated without persisting or logging
  /// on every failure — only on a status transition.
  final ValueNotifier<Map<String, String>> effectStatusNotifier =
      ValueNotifier<Map<String, String>>(const {});

  void _recordEffectOutcome(String effectKey, bool applied) {
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
  int crossfeedMode = 0; // 0=Bs2bDefault, 1=Bs2bChuMoy, 2=Bs2bJanMeier, 3=Custom

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
  bool isSincResamplerEnabled = true;

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
    MultibandCompressorBandConfig(thresholdDb: -20.0, ratio: 2.5, attackMs: 20.0, releaseMs: 120.0, kneeDb: 6.0, makeupGainDb: 0.0),
    MultibandCompressorBandConfig(thresholdDb: -18.0, ratio: 2.0, attackMs: 15.0, releaseMs: 100.0, kneeDb: 6.0, makeupGainDb: 0.0),
    MultibandCompressorBandConfig(thresholdDb: -16.0, ratio: 1.8, attackMs: 10.0, releaseMs: 80.0, kneeDb: 4.0, makeupGainDb: 0.0),
    MultibandCompressorBandConfig(thresholdDb: -14.0, ratio: 1.5, attackMs: 5.0, releaseMs: 60.0, kneeDb: 4.0, makeupGainDb: 0.0),
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

  void _debouncedSavePreferences() {
    if (_isDegradedForPower) return; // battery degrade must not clobber saved ON prefs
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      _savePreferences();
    });
  }

  Future<void> init() async {
    await _effectsChannel.init();
    await _effectsLock.lock(() => _restorePreferences());
  }

  List<double> get activeFrequencies => eqBandCount == 64
      ? custom64Frequencies
      : (eqBandCount == 32 ? custom32Frequencies : customFrequencies);

  Future<void> _restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled = prefs.getBool(PrefsKeys.eqEnabled) ?? false;
      // Band-count migration: prefer the explicit count key; fall back to the
      // legacy boolean (true => 32) so existing installs keep their mode.
      final storedBandCount = prefs.getInt(PrefsKeys.eqBandCount);
      if (storedBandCount != null &&
          (storedBandCount == 10 ||
              storedBandCount == 32 ||
              storedBandCount == 64)) {
        eqBandCount = storedBandCount;
      } else if (prefs.getBool(PrefsKeys.eq32BandMode) ??
          (prefs.getBool('eq_32_band_mode') ?? false)) {
        eqBandCount = 32;
      } else {
        eqBandCount = 10;
      }
      final presetName = prefs.getString(PrefsKeys.eqPresetName) ?? 'Flat';
      final gainsJson = prefs.getString(PrefsKeys.eqGains);
      final bass = prefs.getDouble(PrefsKeys.eqBassBoost) ?? 0.0;
      volumeBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost) ?? 0.0;

      final customFreqsJson = prefs.getString(PrefsKeys.eqCustomFrequencies);
      if (customFreqsJson != null) {
        try {
          final decodedFreqs =
              (json.decode(customFreqsJson) as List<dynamic>)
                  .map((e) => (e as num).toDouble())
                  .toList();
          if (decodedFreqs.length == 10 &&
              decodedFreqs.every((f) => f.isFinite && f > 0)) {
            customFrequencies = decodedFreqs;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }
      final custom32Json = prefs.getString(PrefsKeys.eqCustom32Frequencies);
      if (custom32Json != null) {
        try {
          final decoded32 = (json.decode(custom32Json) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded32.length == 32 &&
              decoded32.every((f) => f.isFinite && f > 0)) {
            custom32Frequencies = decoded32;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom 32-band EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }
      final custom64Json = prefs.getString(PrefsKeys.eqCustom64Frequencies);
      if (custom64Json != null) {
        try {
          final decoded64 = (json.decode(custom64Json) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList();
          if (decoded64.length == 64 &&
              decoded64.every((f) => f.isFinite && f > 0)) {
            custom64Frequencies = decoded64;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode custom 64-band EQ frequencies',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      final targetFreqs = activeFrequencies;
      List<double> gains = List<double>.filled(targetFreqs.length, 0.0);
      bool gainsLoaded = false;
      if (gainsJson != null) {
        try {
          final decoded = json.decode(gainsJson) as List<dynamic>;
          final parsedGains =
              decoded.map((e) => (e as num).toDouble()).toList();
          if (parsedGains.isNotEmpty) {
            gains = EqPreset.interpolateGains(
              parsedGains,
              targetFrequencies: targetFreqs,
            );
            gainsLoaded = gains.length == targetFreqs.length;
          }
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode equalizer gains from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      if (!gainsLoaded) {
        final match = EqPreset.defaultPresets.where(
          (p) => p.name == presetName,
        );
        if (match.isNotEmpty) {
          gains = EqPreset.interpolateGains(
            match.first.gains,
            targetFrequencies: targetFreqs,
          );
        } else {
          gains = List<double>.filled(targetFreqs.length, 0.0);
        }
      }

      currentPreset = EqPreset(name: presetName, gains: gains, bassBoost: bass);
      comparisonSlots[ComparisonSlot.slotA] = currentPreset;
      preampDb =
          (prefs.getDouble(PrefsKeys.eqPreamp) ?? 0.0).clamp(-15.0, 15.0);

      isVirtualizerEnabled =
          prefs.getBool(PrefsKeys.eqVirtualizerEnabled) ?? false;
      virtualizerStrength =
          prefs.getDouble(PrefsKeys.eqVirtualizerStrength) ?? 0.0;

      final dynPresetStr =
          prefs.getString(PrefsKeys.eqDynamicsPreset) ??
          DynamicsPreset.off.name;
      dynamicsPreset = DynamicsPreset.values.firstWhere(
        (d) => d.name == dynPresetStr,
        orElse: () => DynamicsPreset.off,
      );
      isDynamicsEnabled = prefs.getBool(PrefsKeys.eqDynamicsEnabled) ?? false;
      _isDynamicsBypassed =
          prefs.getBool(PrefsKeys.eqDynamicsBypassed) ?? false;

      isSpatializerEnabled =
          prefs.getBool(PrefsKeys.eqSpatializerEnabled) ?? false;

      isCrossfeedEnabled = prefs.getBool(PrefsKeys.crossfeedEnabled) ?? false;
      crossfeedDelayUs = prefs.getDouble(PrefsKeys.crossfeedDelayUs) ?? 350.0;
      crossfeedFeedDb = prefs.getDouble(PrefsKeys.crossfeedFeedDb) ?? -9.0;
      crossfeedMode = prefs.getInt(PrefsKeys.crossfeedMode) ?? 0;

      isLimiterEnabled =
          prefs.getBool(PrefsKeys.lookaheadLimiterEnabled) ?? false;
      limiterThresholdDb =
          prefs.getDouble(PrefsKeys.lookaheadLimiterThresholdDb) ?? -0.2;
      limiterReleaseMs =
          prefs.getDouble(PrefsKeys.lookaheadLimiterReleaseMs) ?? 50.0;
      limiterLookaheadMs =
          prefs.getDouble(PrefsKeys.lookaheadLimiterLookaheadMs) ?? 3.0;
      compressorRatio = prefs.getDouble(PrefsKeys.compressorRatio) ?? 3.0;
      compressorAttackMs =
          prefs.getDouble(PrefsKeys.compressorAttackMs) ?? 15.0;
      compressorMakeupGainDb =
          prefs.getDouble(PrefsKeys.compressorMakeupGainDb) ?? 0.0;
      // Only forward compressor knobs to the HAL when the user actually saved
      // them: the native brickwall limiter defaults must not silently turn into
      // a 3:1 / 15 ms compressor for users who never opened the sheet.
      _hasStoredCompressorParams = prefs.containsKey(PrefsKeys.compressorRatio) ||
          prefs.containsKey(PrefsKeys.compressorAttackMs) ||
          prefs.containsKey(PrefsKeys.compressorMakeupGainDb);

      isReverbEnabled =
          prefs.getBool(PrefsKeys.convolutionReverbEnabled) ?? false;
      // A stored `custom` reverb is only valid if its impulse response can be
      // reloaded from the persisted WAV path. Re-apply it here; if reloading
      // fails (file gone/corrupt), fall back honestly to the default room
      // instead of leaving the UI claiming "Custom (Loaded)" with no IR.
      final storedReverb = ReverbPreset.fromWireValue(
          prefs.getInt(PrefsKeys.convolutionReverbPreset) ??
              ReverbPreset.studio.wireValue);
      if (storedReverb == ReverbPreset.custom) {
        final irPath = prefs.getString(PrefsKeys.customReverbIrPath);
        var customIrRestored = false;
        if (irPath != null && irPath.isNotEmpty) {
          try {
            final samples = await IrFileParser.parseWavFile(File(irPath));
            if (samples.isNotEmpty &&
                await _effectsChannel.loadImpulseResponse(samples)) {
              reverbPreset = ReverbPreset.custom.wireValue;
              customIrRestored = true;
            }
          } catch (e, st) {
            ErrorLogger.log(
              'Failed to restore custom reverb IR from $irPath',
              error: e,
              stackTrace: st,
              category: 'EqualizerManager',
            );
          }
        }
        if (!customIrRestored) {
          reverbPreset = ReverbPreset.studio.wireValue;
        }
      } else {
        reverbPreset = storedReverb.wireValue;
      }
      reverbWetDry = prefs.getDouble(PrefsKeys.convolutionReverbWetDry) ?? 0.20;

      stereoBalance = prefs.getDouble(PrefsKeys.stereoBalance) ?? 0.0;
      monoMix = prefs.getBool(PrefsKeys.monoMix) ?? false;
      isSincResamplerEnabled =
          prefs.getBool(PrefsKeys.sincResamplerEnabled) ?? true;

      // Phase 1 DSP expansion stages (missing keys = neutral defaults)
      isSaturationEnabled = prefs.getBool(PrefsKeys.saturationEnabled) ?? false;
      saturationDrive = prefs.getDouble(PrefsKeys.saturationDrive) ?? 0.3;
      saturationMix = prefs.getDouble(PrefsKeys.saturationMix) ?? 0.5;
      saturationTilt = prefs.getDouble(PrefsKeys.saturationTilt) ?? 0.3;
      saturationMode = prefs.getInt(PrefsKeys.saturationMode) ?? 0;
      saturationMultiband =
          prefs.getBool(PrefsKeys.saturationMultiband) ?? false;

      isStereoWidthEnabled =
          prefs.getBool(PrefsKeys.stereoWidthEnabled) ?? false;
      stereoWidth = prefs.getDouble(PrefsKeys.stereoWidth) ?? 1.0;
      stereoWidthMultiband =
          prefs.getBool(PrefsKeys.stereoWidthMultiband) ?? false;
      stereoWidthLow = prefs.getDouble(PrefsKeys.stereoWidthLow) ?? 1.0;
      stereoWidthMid = prefs.getDouble(PrefsKeys.stereoWidthMid) ?? 1.0;
      stereoWidthHigh = prefs.getDouble(PrefsKeys.stereoWidthHigh) ?? 1.0;
      stereoWidthLowCrossoverHz =
          prefs.getDouble(PrefsKeys.stereoWidthLowCrossoverHz) ?? 160.0;
      stereoWidthHighCrossoverHz =
          prefs.getDouble(PrefsKeys.stereoWidthHighCrossoverHz) ?? 2500.0;

      isLoudnessContourEnabled =
          prefs.getBool(PrefsKeys.loudnessContourEnabled) ?? false;
      loudnessContourIntensity =
          prefs.getDouble(PrefsKeys.loudnessContourIntensity) ?? 0.0;

      isSubCrossoverEnabled =
          prefs.getBool(PrefsKeys.subCrossoverEnabled) ?? false;
      subCrossoverCornerHz =
          prefs.getDouble(PrefsKeys.subCrossoverCornerHz) ?? 80.0;
      subCrossoverSlopeDbPerOct =
          prefs.getDouble(PrefsKeys.subCrossoverSlopeDbPerOct) ?? 24.0;
      subCrossoverGain = prefs.getDouble(PrefsKeys.subCrossoverGain) ?? 0.8;
      subCrossoverBassMono =
          prefs.getBool(PrefsKeys.subCrossoverBassMono) ?? false;
      subCrossoverAntiPop =
          prefs.getBool(PrefsKeys.subCrossoverAntiPop) ?? true;

      isDynamicEqEnabled = prefs.getBool(PrefsKeys.dynamicEqEnabled) ?? false;
      reverbCrossChannel = prefs.getDouble(PrefsKeys.reverbCrossChannel) ?? 0.0;

      isMultibandCompressorEnabled =
          prefs.getBool(PrefsKeys.multibandCompressorEnabled) ?? false;
      multibandCompressorF0 =
          prefs.getDouble(PrefsKeys.multibandCompressorF0) ?? 160.0;
      multibandCompressorF1 =
          prefs.getDouble(PrefsKeys.multibandCompressorF1) ?? 1000.0;
      multibandCompressorF2 =
          prefs.getDouble(PrefsKeys.multibandCompressorF2) ?? 5000.0;
      final mbcJson = prefs.getString(PrefsKeys.multibandCompressorBands);
      if (mbcJson != null) {
        try {
          final decoded = (json.decode(mbcJson) as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(MultibandCompressorBandConfig.fromJson)
              .toList();
          if (decoded.isNotEmpty) multibandCompressorBands = decoded;
        } catch (_) {}
      }
      isDynamicBassEnabled =
          prefs.getBool(PrefsKeys.dynamicBassEnabled) ?? false;
      dynamicBassStrength =
          prefs.getDouble(PrefsKeys.dynamicBassStrength) ?? 1.0;
      dynamicBassXLow =
          prefs.getInt(PrefsKeys.dynamicBassXLow) ?? 100;
      dynamicBassXHigh =
          prefs.getInt(PrefsKeys.dynamicBassXHigh) ?? 5600;
      dynamicBassYLow =
          prefs.getInt(PrefsKeys.dynamicBassYLow) ?? 40;
      dynamicBassYHigh =
          prefs.getInt(PrefsKeys.dynamicBassYHigh) ?? 80;
      dynamicBassSideGainLow =
          prefs.getDouble(PrefsKeys.dynamicBassSideGainLow) ?? 0.10;
      dynamicBassSideGainHigh =
          prefs.getDouble(PrefsKeys.dynamicBassSideGainHigh) ?? 0.50;
      dynamicBassPreset =
          prefs.getInt(PrefsKeys.dynamicBassPreset) ?? 0;
      isViperDdcEnabled =
          prefs.getBool(PrefsKeys.viperDdcEnabled) ?? false;
      viperDdcProfileName =
          prefs.getString(PrefsKeys.viperDdcProfileName) ?? '';
      viperDdcContent =
          prefs.getString(PrefsKeys.viperDdcContent) ?? '';
      isArbitraryEqEnabled =
          prefs.getBool(PrefsKeys.arbitraryEqEnabled) ?? false;
      arbitraryEqString =
          prefs.getString(PrefsKeys.arbitraryEqString) ?? '';
      arbitraryEqLinearPhase =
          prefs.getBool(PrefsKeys.arbitraryEqLinearPhase) ?? false;
      isLiveProgEnabled =
          prefs.getBool(PrefsKeys.liveProgEnabled) ?? false;
      liveProgCode =
          prefs.getString(PrefsKeys.liveProgCode) ?? '';
      liveProgSliders
        ..clear()
        ..addAll(
            decodeLiveProgSliders(prefs.getString(PrefsKeys.liveProgSliders)));      dspPreference = prefs.getString(PrefsKeys.dspPreference) ?? 'native';
      if (dspPreference != 'native' &&
          dspPreference != 'oem' &&
          dspPreference != 'auto') {
        dspPreference = 'native';
      }
      final bitPerfect =
          prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false;
      final bypassDsp =
          prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true;
      isBitPerfectBypass = bitPerfect && bypassDsp;
      isDitherEnabled = prefs.getBool(PrefsKeys.ditherEnabled) ?? false;
      ditherTargetBitDepth =
          prefs.getInt(PrefsKeys.ditherTargetBitDepth) ?? 16;
      if (ditherTargetBitDepth != 16 &&
          ditherTargetBitDepth != 24 &&
          ditherTargetBitDepth != 32) {
        ditherTargetBitDepth = 16;
      }
      if (PlatformCapabilities.isAndroid) {
        await _effectsChannel.setDspPreference(dspPreference);
        await _effectsChannel.setBypassDspForBitPerfect(isBitPerfectBypass);
        // Restore dither too: it was previously loaded into in-memory state
        // but never pushed, so a saved-ON dither did nothing until toggled.
        if (isDitherEnabled) {
          await _effectsChannel.setDitherParams(
            enabled: true,
            targetBitDepth: ditherTargetBitDepth,
            isBluetooth: isBluetoothRoute,
          );
        }
      }
      if (isBitPerfectBypass) {
        _syncPipeline();
        return;
      }
      final dynEqJson = prefs.getString(PrefsKeys.dynamicEqBands);
      if (dynEqJson != null) {
        try {
          final decoded =
              (json.decode(dynEqJson) as List<dynamic>)
                  .whereType<Map<String, dynamic>>()
                  .map(DynamicEqBandConfig.fromJson)
                  .toList();
          if (decoded.isNotEmpty) dynamicEqBands = decoded;
        } catch (e, st) {
          ErrorLogger.log(
            'Failed to decode dynamic EQ bands from prefs',
            error: e,
            stackTrace: st,
            category: 'EqualizerManager',
          );
        }
      }

      final profileId = prefs.getString(PrefsKeys.eqHeadphoneProfileId);
      if (profileId != null) {
        await HeadphoneProfilesRepository().loadProfiles();
        selectedHeadphoneProfile = HeadphoneProfilesRepository().getProfileById(
          profileId,
        );
      }

      // Batch native effect enables to avoid sound-drop dropout (requires EQ off/on to fix)
      // Previously each await toggled DynamicsProcessing causing 20+ JNI hops on audio thread during playback.
      // Now batch independent effects together and defer DynamicsProcessing last to prevent double-processing bypass churn.
      final pendingFutures = <Future<void>>[];
      if (isEnabled) {
        // Apply preset first without enabling, then enable atomically
        await applyCurrentPreset();
        pendingFutures.add(_effectsChannel.setEqEnabled(true));
        pendingFutures.add(_effectsChannel.setNativeEqEnabled(true));
      }
      if (currentPreset.bassBoost > 0) {
        pendingFutures.add(setBassBoost(currentPreset.bassBoost));
      }
      if (volumeBoost > 0) {
        pendingFutures.add(setVolumeBoost(volumeBoost));
      }
      if (preampDb != 0.0) {
        pendingFutures.add(_effectsChannel.setEqPreamp(preampDb));
      }
      if (_effectsChannel.isVirtualizerSupported) {
        pendingFutures.add(_effectsChannel.setVirtualizerEnabled(isVirtualizerEnabled));
        if (isVirtualizerEnabled) {
          pendingFutures.add(
            _effectsChannel.setVirtualizerStrength(virtualizerStrength),
          );
        }
      }
      
      pendingFutures.add(_applySpatializerWithFallback(isSpatializerEnabled));
      
      if (isCrossfeedEnabled) {
        pendingFutures.add(
          _effectsChannel.setCrossfeedParams(crossfeedDelayUs, crossfeedFeedDb),
        );
        pendingFutures.add(_effectsChannel.setCrossfeedMode(crossfeedMode));
      }
      pendingFutures.add(_effectsChannel.setCrossfeedEnabled(isCrossfeedEnabled));
      
      if (isLimiterEnabled) {
        pendingFutures.add(
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
      }
      pendingFutures.add(_effectsChannel.setLimiterEnabled(isLimiterEnabled));
      
      if (isReverbEnabled) {
        pendingFutures.add(_effectsChannel.setReverbPreset(reverbPreset));
        pendingFutures.add(_effectsChannel.setReverbWetDry(reverbWetDry));
        if (reverbCrossChannel > 0.0) {
          pendingFutures.add(
            _effectsChannel.setReverbCrossChannel(reverbCrossChannel),
          );
        }
      }
      pendingFutures.add(_effectsChannel.setReverbEnabled(isReverbEnabled));
      
      if (stereoBalance != 0.0) {
        pendingFutures.add(_effectsChannel.setStereoBalance(stereoBalance));
      }
      pendingFutures.add(_effectsChannel.setMonoMix(monoMix));
      pendingFutures.add(_effectsChannel.setSincResamplerEnabled(isSincResamplerEnabled));

      if (isSaturationEnabled) {
        pendingFutures.add(
          _effectsChannel.setSaturationParams(
            saturationDrive,
            saturationMix,
            saturationTilt,
            mode: saturationMode,
          ),
        );
        pendingFutures.add(
          _effectsChannel.setSaturationMultiband(saturationMultiband),
        );
      }
      pendingFutures.add(_effectsChannel.setSaturationEnabled(isSaturationEnabled));

      if (isStereoWidthEnabled) {
        pendingFutures.add(
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
      }
      pendingFutures.add(_effectsChannel.setStereoWidthEnabled(isStereoWidthEnabled));

      if (isLoudnessContourEnabled) {
        pendingFutures.add(
          _effectsChannel.setLoudnessContourParams(
            loudnessContourIntensity,
            loudnessVolumeLinear,
          ),
        );
      }
      pendingFutures.add(_effectsChannel.setLoudnessContourEnabled(isLoudnessContourEnabled));

      if (isSubCrossoverEnabled) {
        pendingFutures.add(
          _effectsChannel.setSubCrossoverParams(
            subCrossoverCornerHz,
            subCrossoverSlopeDbPerOct,
            subCrossoverGain,
            bassMono: subCrossoverBassMono,
            antiPop: subCrossoverAntiPop,
          ),
        );
      }
      pendingFutures.add(_effectsChannel.setSubCrossoverEnabled(isSubCrossoverEnabled));

      if (isDynamicEqEnabled) {
        pendingFutures.add(_pushDynamicEqConfig());
      }
      pendingFutures.add(_effectsChannel.setDynamicEqEnabled(isDynamicEqEnabled));

      if (isMultibandCompressorEnabled) {
        pendingFutures.add(_pushMultibandCompressorConfig());
      }
      pendingFutures.add(
        _effectsChannel.setMultibandCompressorEnabled(isMultibandCompressorEnabled),
      );

      pendingFutures.add(
        _effectsChannel.setDynamicBassParams(
          enabled: isDynamicBassEnabled,
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

      if (isViperDdcEnabled && viperDdcContent.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadViperDdc(
          ddcContent: viperDdcContent,
          profileName: viperDdcProfileName,
        ));
      }
      pendingFutures.add(_effectsChannel.setViperDdcEnabled(isViperDdcEnabled));

      if (isArbitraryEqEnabled && arbitraryEqString.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadArbitraryEq(
          eqString: arbitraryEqString,
          linearPhase: arbitraryEqLinearPhase,
        ));
      }
      pendingFutures.add(_effectsChannel.setArbitraryEqEnabled(isArbitraryEqEnabled));

      if (isLiveProgEnabled && liveProgCode.isNotEmpty) {
        pendingFutures.add(_effectsChannel.loadLiveProgCode(liveProgCode));
        for (final entry in liveProgSliders.entries) {
          pendingFutures
              .add(_effectsChannel.setLiveProgSlider(entry.key, entry.value));
        }
      }
      pendingFutures.add(_effectsChannel.setLiveProgEnabled(isLiveProgEnabled));
      // Dynamics last — it triggers recalculateActiveStages which disables OEM engine; doing it last prevents intermediate dropout
      // Log individual failures so failed effect stages are diagnosable while allowing remaining stages to complete
      if (pendingFutures.isNotEmpty) {
        final results = await Future.wait(
          pendingFutures.map(
            (f) => f.then((_) => true).catchError((Object e, StackTrace st) {
              ErrorLogger.log(
                'Failed to restore audio effect preference',
                error: e,
                stackTrace: st,
                category: 'EqualizerManager',
              );
              return false;
            }),
          ),
        );
        final failCount = results.where((r) => !r).length;
        if (failCount > 0) {
          ErrorLogger.log(
            '$failCount/${pendingFutures.length} audio effects failed to restore',
            category: 'EqualizerManager',
          );
        }
      }
      if (isDynamicsEnabled && !_isDynamicsBypassed) {
        // Small delay lets AudioTrack stabilize before DynamicsProcessing rebuild (fixes sound drops needing EQ toggle)
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _effectsChannel.setDynamicsPreset(dynamicsPreset, true);
      }
      _syncPipeline();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to restore equalizer preferences',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> _savePreferences() async {
    // Battery degrade must never clobber saved ON prefs — covers both the
    // debounced path and direct await _savePreferences() call sites.
    if (_isDegradedForPower) return;
    // Serialize concurrent preference writes to prevent torn reads/writes
    // when multiple effects are toggled rapidly.
    await _effectsLock.lock(() => _performSavePreferences());
  }

  Future<void> _performSavePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Atomic write pattern: collect all changes, then commit in single transaction
      // This prevents partial updates if app crashes mid-write.
      final batch = <String, dynamic>{
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

      // Atomic commit: all-or-nothing write pattern
      for (final entry in batch.entries) {
        if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is double) {
          await prefs.setDouble(entry.key, entry.value as double);
        } else if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        } else if (entry.value is String) {
          await prefs.setString(entry.key, entry.value as String);
        }
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
      ErrorLogger.log(
        'Failed to save equalizer preferences',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
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
    
    final Map<int, List<double>> updatedBandsMap = Map<int, List<double>>.from(currentPreset.bandsMap);
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

    if (PlatformCapabilities.isAndroid) {
      // Single bulk JNI hop (was 32 hops, 150-300ms jank) + fallback for legacy 10-band path.
      // Single-application (13-01): skip legacy mirror when native ACKs and owns the curve.
      final nativeOk = await _effectsChannel.setNativeEqBandsBulk(
        frequencies: targetFreqs,
        gains: currentPreset.gains,
      );
      if (!nativeOk) {
        await _effectsChannel.setNativeEqBandCount(targetFreqs.length);
        final futures = <Future<bool>>[];
        for (int i = 0; i < targetFreqs.length; i++) {
          futures.add(
            _effectsChannel.setNativeEqBand(
              i,
              targetFreqs[i],
              currentPreset.gains[i],
              1.414,
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
  Future<void> set32BandMode(bool enabled) =>
      setBandMode(enabled ? 32 : 10);

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
    currentPreset = preset.copyWith(gains: gains);
    comparisonSlots[activeComparisonSlot] = currentPreset;
    await applyCurrentPreset();
    await setBassBoost(preset.bassBoost);
    _debouncedSavePreferences();
  }

  Future<void> setBandGain(int index, double gain) async {
    if (index < 0 || index >= currentPreset.gains.length) return;
    if (!gain.isFinite) return;
    selectedHeadphoneProfile = null;

    final newGains = List<double>.from(currentPreset.gains);
    newGains[index] = gain.clamp(-15.0, 15.0);
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
                1.414,
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
                1.414,
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
    this.preampDb = preampDb.clamp(-15.0, 15.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setEqPreamp(this.preampDb);
    }
    _debouncedSavePreferences();
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
      final nativeOk = await _effectsChannel.setNativeEqBandsBulk(
        frequencies: targetFreqs,
        gains: currentPreset.gains,
      );
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
              1.414,
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
              1.414,
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
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
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
        if (profile.gains.isEmpty) {
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
        final gains = EqPreset.interpolateGains(
          profile.gains,
          targetFrequencies: targetFreqs,
        );
        currentPreset = EqPreset(
          name: profile.name,
          gains: gains,
          bassBoost: profile.bassBoost,
        );
        comparisonSlots[activeComparisonSlot] = currentPreset;
        selectedHeadphoneProfile = profile;
        await applyCurrentPreset();
        await setBassBoost(profile.bassBoost);
        await setPreamp(profile.preampGain);
      } else {
        selectedHeadphoneProfile = null;
        await setPreamp(0.0);
      }
    } catch (e, st) {
      currentPreset = prevPreset;
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

  Future<void> setVirtualizerEnabled(bool enabled) async {
    // FIX M-9: skip no-op IPC when virtualizer is not supported
    if (!_effectsChannel.isVirtualizerSupported) return;
    
    final previous = isVirtualizerEnabled;
    isVirtualizerEnabled = enabled;
    try {
      final applied = await _effectsChannel.setVirtualizerEnabled(enabled);
      if (enabled) {
        _recordEffectOutcome('virtualizer', applied);
        // Never leave the toggle ON when the engine rejected the request.
        if (!applied) isVirtualizerEnabled = previous;
      } else {
        _recordEffectOutcome('virtualizer', true);
      }
      await _savePreferences();
    } catch (e, st) {
      isVirtualizerEnabled = previous;
      _recordEffectOutcome('virtualizer', false);
      ErrorLogger.log(
        'Failed to set virtualizer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  Future<void> setVirtualizerStrength(double strength) async {
    // FIX M-9: skip no-op IPC when virtualizer is not supported
    if (!_effectsChannel.isVirtualizerSupported) return;
    
    virtualizerStrength = strength.clamp(0.0, 1.0);
    final applied = await _effectsChannel.setVirtualizerStrength(
      virtualizerStrength,
    );
    _recordEffectOutcome('virtualizer', applied || virtualizerStrength <= 0.0);
    await _savePreferences();
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    dynamicsPreset = preset;
    if (enabled != null) {
      isDynamicsEnabled = enabled;
    } else if (preset == DynamicsPreset.off) {
      isDynamicsEnabled = false;
    } else {
      isDynamicsEnabled = true;
    }
    if (!_isDynamicsBypassed) {
      final applied = await _effectsChannel.setDynamicsPreset(
        dynamicsPreset,
        isDynamicsEnabled,
      );
      final wantsDynamics = isDynamicsEnabled && preset != DynamicsPreset.off;
      // A rejected "off" still reaches the desired disabled state; only an
      // enabled-but-rejected preset is a genuine "not applied".
      _recordEffectOutcome('dynamics', applied || !wantsDynamics);
    }
    await _savePreferences();
  }

  Future<void> toggleDynamicsBypass() async {
    _isDynamicsBypassed = !_isDynamicsBypassed;
    if (_isDynamicsBypassed) {
      await _effectsChannel.setDynamicsPreset(DynamicsPreset.off, false);
    } else {
      await _effectsChannel.setDynamicsPreset(
        dynamicsPreset,
        isDynamicsEnabled,
      );
    }
    await _savePreferences();
  }

  bool get isSpatializerSupported => _effectsChannel.isSpatializerSupported;
  bool get isHeadTrackerAvailable => _effectsChannel.isHeadTrackerAvailable;

  /// Applies the spatializer enable flag, then falls back to the hardware
  /// virtualizer when the device has no Spatializer API. Uses the channel
  /// directly (never [_savePreferences]) so it is safe to call from within
  /// [_restorePreferences] while [_effectsLock] is held, and from the public
  /// setter, restore and reattach paths alike.
  Future<bool> _applySpatializerWithFallback(bool enabled) async {
    final applied = await _effectsChannel.setSpatializerEnabled(enabled);
    if (enabled && !_effectsChannel.isSpatializerSupported) {
      if (!isVirtualizerEnabled) {
        isVirtualizerEnabled = true;
        _recordEffectOutcome(
          'virtualizer',
          await _effectsChannel.setVirtualizerEnabled(true),
        );
        if (virtualizerStrength < 0.3) {
          virtualizerStrength = 0.7;
          _recordEffectOutcome(
            'virtualizer',
            await _effectsChannel.setVirtualizerStrength(virtualizerStrength),
          );
        }
      }
    }
    return applied;
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    final previous = isSpatializerEnabled;
    isSpatializerEnabled = enabled;
    try {
      final applied = await _applySpatializerWithFallback(enabled);
      if (enabled) {
        _recordEffectOutcome('spatializer', applied);
        if (!applied) isSpatializerEnabled = previous;
      } else {
        _recordEffectOutcome('spatializer', true);
      }
      await _savePreferences();
    } catch (e, st) {
      isSpatializerEnabled = previous;
      _recordEffectOutcome('spatializer', false);
      ErrorLogger.log(
        'Failed to set spatializer enabled',
        error: e,
        stackTrace: st,
        category: 'EqualizerManager',
      );
    }
  }

  bool get hasOemAudio => _effectsChannel.hasOemAudio;
  List<String> get detectedOemEngines => _effectsChannel.detectedOemEngines;

  Future<void> setCrossfeed(
    bool enabled, {
    double? delayUs,
    double? feedDb,
    double? fcut,
    int? mode,
  }) async {
    isCrossfeedEnabled = enabled;
    if (delayUs != null) {
      crossfeedDelayUs = delayUs.clamp(200.0, 700.0);
    }
    if (feedDb != null) {
      crossfeedFeedDb = feedDb.clamp(-15.0, -6.0);
    }
    if (fcut != null) {
      crossfeedFcut = fcut.clamp(200.0, 2000.0);
    }
    if (mode != null) crossfeedMode = mode.clamp(0, 3);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setCrossfeedParams(
        crossfeedDelayUs,
        crossfeedFeedDb,
        fcut: crossfeedFcut,
      );
      await _effectsChannel.setCrossfeedMode(crossfeedMode);
      await _effectsChannel.setCrossfeedEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setCrossfeedMode(int mode) async {
    crossfeedMode = mode.clamp(0, 3);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setCrossfeedMode(crossfeedMode);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setLookaheadLimiter(
    bool enabled, {
    double? thresholdDb,
    double? releaseMs,
    double? lookaheadMs,
  }) async {
    isLimiterEnabled = enabled;
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (lookaheadMs != null) limiterLookaheadMs = lookaheadMs;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        limiterLookaheadMs,
        limiterThresholdDb,
        limiterReleaseMs,
      );
      await _effectsChannel.setLimiterEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setCompressorParams({
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? makeupGainDb,
  }) async {
    if (thresholdDb != null) limiterThresholdDb = thresholdDb;
    if (ratio != null) compressorRatio = ratio;
    if (attackMs != null) compressorAttackMs = attackMs;
    if (releaseMs != null) limiterReleaseMs = releaseMs;
    if (makeupGainDb != null) compressorMakeupGainDb = makeupGainDb;

    // Any explicit edit marks the compressor knobs as user-owned so restore
    // and reattach keep forwarding them to the HAL.
    _hasStoredCompressorParams = true;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLimiterParams(
        limiterLookaheadMs,
        limiterThresholdDb,
        limiterReleaseMs,
        ratio: compressorRatio,
        attackMs: compressorAttackMs,
        makeupGainDb: compressorMakeupGainDb,
      );
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setReverb(
    bool enabled, {
    int? preset,
    double? wetDry,
    double? predelayMs,
    double? damping,
  }) async {
    isReverbEnabled = enabled;
    if (preset != null) {
      // Wire values are ReverbPreset ordinals (0..N); anything else has no
      // synthesizable IR on the native side, so clamp instead of forwarding
      // garbage that would silently produce the wrong room.
      reverbPreset =
          preset.clamp(0, ReverbPreset.values.length - 1);
    }
    if (wetDry != null) reverbWetDry = wetDry.clamp(0.0, 1.0);
    if (predelayMs != null) reverbPredelayMs = predelayMs.clamp(0.0, 150.0);
    if (damping != null) reverbDamping = damping.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      if (preset != null) await _effectsChannel.setReverbPreset(preset);
      // FIX M-7: always sync wet/dry after preset change so DSP is not stale
      await _effectsChannel.setReverbWetDry(wetDry ?? reverbWetDry);
      // Predelay, damping and cross-channel share one native call; push the
      // current values so a preset change never leaves them stale.
      await _effectsChannel.setReverbParams(
        predelayMs: reverbPredelayMs,
        damping: reverbDamping,
        crossChannel: reverbCrossChannel,
      );
      await _effectsChannel.setReverbEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Loads a user-supplied impulse response. Returns true only when the native
  /// side accepted it, so callers never flip the UI to "Custom (Loaded)" on a
  /// failed load.
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (irSamples.isEmpty) {
      ErrorLogger.log(
        'Cannot load an empty impulse response',
        category: 'EqualizerManager',
      );
      return false;
    }
    if (!PlatformCapabilities.isAndroid) {
      isReverbEnabled = true;
      reverbPreset = ReverbPreset.custom.wireValue;
      _debouncedSavePreferences();
      _syncPipeline();
      return true;
    }
    final loaded = await _effectsChannel.loadImpulseResponse(irSamples);
    if (!loaded) {
      ErrorLogger.log(
        'Custom impulse response rejected by native DSP',
        category: 'EqualizerManager',
      );
      return false;
    }
    isReverbEnabled = true;
    // Must be `custom`: any synthesizable ordinal makes the native side
    // build its own IR on the next re-apply and discard the loaded one.
    reverbPreset = ReverbPreset.custom.wireValue;
    customImpulseResponse = List<double>.unmodifiable(irSamples);
    await _effectsChannel.setReverbEnabled(true);
    _debouncedSavePreferences();
    _syncPipeline();
    return true;
  }

  Future<int> getPipelineLatencyFrames() =>
      _effectsChannel.getPipelineLatencyFrames();
  Future<void> setBandSolo(int index, bool solo) =>
      _effectsChannel.setBandSolo(index, solo);
  Future<void> setBandMute(int index, bool mute) =>
      _effectsChannel.setBandMute(index, mute);

  Future<void> setStereoBalance(double balance) async {
    stereoBalance = balance.clamp(-1.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setStereoBalance(stereoBalance);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setMonoMix(bool mono) async {
    monoMix = mono;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setMonoMix(mono);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setSincResampler(bool enabled) async {
    isSincResamplerEnabled = enabled;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSincResamplerEnabled(enabled);
    }
    _debouncedSavePreferences();
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
    _syncPipeline();
  }

  /// Restores DSP stages that were disabled during low power mode.
  Future<void> restoreFromDegrade() async {
    if (!_isDegradedForPower) return;
    _isDegradedForPower = false;

    if (_savedReverbEnabled) await setReverb(true);
    if (_savedCrossfeedEnabled) await setCrossfeed(true);
    if (_savedSaturationEnabled) await setSaturation(true);
    if (_savedStereoWidthEnabled) await setStereoWidth(true);
    if (_savedLoudnessContourEnabled) await setLoudnessContour(true);
    if (_savedSubCrossoverEnabled) await setSubCrossover(true);
    if (_savedDynamicEqEnabled) await setDynamicEq(true);
    if (_savedDynamicsEnabled) {
      await setDynamicsPreset(_savedDynamicsPreset, enabled: true);
    }
    if (_savedLimiterEnabled) await setLookaheadLimiter(true);
    if (_savedViperDdcEnabled) await setViperDdc(true);
    // Re-pass the stored curves/code: the setters only (re)load native
    // content when it is supplied, otherwise just the enable flag is pushed
    // and the stage comes back empty.
    if (_savedArbitraryEqEnabled) {
      await setArbitraryEq(
        true,
        eqString: arbitraryEqString.isNotEmpty ? arbitraryEqString : null,
      );
    }
    if (_savedLiveProgEnabled) {
      await setLiveProg(
        true,
        code: liveProgCode.isNotEmpty ? liveProgCode : null,
      );
    }
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
    isSaturationEnabled = enabled;
    if (drive != null) saturationDrive = drive.clamp(0.0, 1.0);
    if (mix != null) saturationMix = mix.clamp(0.0, 1.0);
    if (tilt != null) saturationTilt = tilt.clamp(0.0, 1.0);
    if (mode != null) saturationMode = mode.clamp(0, 2);
    if (multiband != null) saturationMultiband = multiband;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setSaturationParams(
        saturationDrive,
        saturationMix,
        saturationTilt,
        mode: saturationMode,
      );
      await _effectsChannel.setSaturationMultiband(saturationMultiband);
      await _effectsChannel.setSaturationEnabled(enabled);
    }
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
    isViperDdcEnabled = enabled;
    if (profileName != null) viperDdcProfileName = profileName;
    final resolvedContent =
        ddcContent ?? (coeffs != null && coeffs.isNotEmpty ? coeffs.join(' ') : null);
    if (resolvedContent != null && resolvedContent.isNotEmpty) {
      viperDdcContent = resolvedContent;
    }
    if (PlatformCapabilities.isAndroid) {
      if (viperDdcContent.isNotEmpty && enabled) {
        await _effectsChannel.loadViperDdc(
          ddcContent: viperDdcContent,
          profileName: viperDdcProfileName,
        );
      } else if (resolvedContent != null && resolvedContent.isNotEmpty) {
        await _effectsChannel.loadViperDdc(
          ddcContent: resolvedContent,
          profileName: profileName ?? viperDdcProfileName,
        );
      }
      await _effectsChannel.setViperDdcEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Sets the loudness contour. The contour lift is computed against
  /// [loudnessVolumeLinear], which is kept in sync with the playback volume
  /// stage via [updateLoudnessVolume].
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    isLoudnessContourEnabled = enabled;
    if (intensity != null) loudnessContourIntensity = intensity.clamp(0.0, 1.0);
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setLoudnessContourParams(
        loudnessContourIntensity,
        loudnessVolumeLinear,
      );
      await _effectsChannel.setLoudnessContourEnabled(enabled);
    }
    _debouncedSavePreferences();
    _syncPipeline();
  }

  /// Pushes the current volume-stage value to the engine so the loudness
  /// contour follows the listening level. Called by AudioHandler on volume
  /// changes and applied on session reattach.
  Future<void> updateLoudnessVolume(double volumeLinear) async {
    loudnessVolumeLinear = volumeLinear.clamp(0.0, 1.0);
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
    isSubCrossoverEnabled = enabled;
    if (cornerHz != null) subCrossoverCornerHz = cornerHz.clamp(60.0, 150.0);
    if (slopeDbPerOct != null) {
      subCrossoverSlopeDbPerOct = slopeDbPerOct < 18.0 ? 12.0 : 24.0;
    }
    if (gain != null) subCrossoverGain = gain.clamp(0.0, 1.0);
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
    _debouncedSavePreferences();
    _syncPipeline();
  }

  Future<void> setDynamicEq(bool enabled) async {
    isDynamicEqEnabled = enabled;
    if (PlatformCapabilities.isAndroid) {
      await _pushDynamicEqConfig();
      await _effectsChannel.setDynamicEqEnabled(enabled);
    }
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
    final sanitized = DynamicEqBandConfig(
      frequency: band.frequency.clamp(20.0, 20000.0),
      q: band.q.clamp(0.1, 12.0),
      thresholdDb: band.thresholdDb.clamp(-80.0, 0.0),
      ratio: band.ratio.clamp(1.0, 20.0),
      attackMs: band.attackMs.clamp(0.1, 200.0),
      releaseMs: band.releaseMs.clamp(5.0, 2000.0),
      maxCutDb: band.maxCutDb.clamp(-24.0, 0.0),
      maxBoostDb: band.maxBoostDb.clamp(0.0, 24.0),
      mode: band.mode.clamp(0, 1),
      filterType: band.filterType.clamp(0, 2),
      enabled: band.enabled,
    );
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
    isMultibandCompressorEnabled = enabled;
    if (bands != null) multibandCompressorBands = List.from(bands);
    if (f0 != null) multibandCompressorF0 = f0.clamp(40.0, 500.0);
    if (f1 != null) multibandCompressorF1 = f1.clamp(200.0, 4000.0);
    if (f2 != null) multibandCompressorF2 = f2.clamp(1000.0, 16000.0);
    // Crossovers must stay strictly ordered (f0 < f1 < f2); individual
    // clamps alone allow inversions such as f0=500 > f1=200.
    if (multibandCompressorF1 <= multibandCompressorF0) {
      multibandCompressorF1 =
          (multibandCompressorF0 + 50.0).clamp(200.0, 4000.0);
    }
    if (multibandCompressorF2 <= multibandCompressorF1) {
      multibandCompressorF2 =
          (multibandCompressorF1 + 500.0).clamp(1000.0, 16000.0);
    }
    // Second pass: the clamps above can themselves collapse the ordering at
    // the range edges, so pull the lower crossover down instead.
    if (multibandCompressorF1 <= multibandCompressorF0) {
      multibandCompressorF0 =
          (multibandCompressorF1 - 50.0).clamp(40.0, 500.0);
    }
    if (multibandCompressorF2 <= multibandCompressorF1) {
      multibandCompressorF1 =
          (multibandCompressorF2 - 500.0).clamp(200.0, 4000.0);
    }
    if (PlatformCapabilities.isAndroid) {
      await _pushMultibandCompressorConfig();
      await _effectsChannel.setMultibandCompressorEnabled(enabled);
    }
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
    isDynamicBassEnabled = enabled;
    if (strength != null) dynamicBassStrength = strength.clamp(0.0, 8.0);
    if (preset != null) dynamicBassPreset = preset.clamp(0, 9);
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
      if (xLow != null) dynamicBassXLow = xLow.clamp(20, 2400);
      if (xHigh != null) dynamicBassXHigh = xHigh.clamp(500, 12000);
      if (yLow != null) dynamicBassYLow = yLow.clamp(20, 200);
      if (yHigh != null) dynamicBassYHigh = yHigh.clamp(30, 300);
      if (sideGainLow != null) dynamicBassSideGainLow = sideGainLow.clamp(0.0, 1.0);
      if (sideGainHigh != null) dynamicBassSideGainHigh = sideGainHigh.clamp(0.0, 1.0);
    }

    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setDynamicBassParams(
        enabled: isDynamicBassEnabled,
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
    _debouncedSavePreferences();
    _syncPipeline();
  }


  /// Owned bypass: stores state, pushes to native (with DoP mirror), and
  /// syncs the pipeline mirror so reattach/route resync restores it.
  Future<void> setBypassDspForBitPerfect(bool bypass, {bool? isDop}) async {
    isBitPerfectBypass = bypass;
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setBypassDspForBitPerfect(bypass, isDop: isDop);
    }
    _syncPipeline();
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

  /// TPDF dither toggle (native stage; auto-skipped on BT routes).
  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {
    isDitherEnabled = enabled;
    if (targetBitDepth != null &&
        (targetBitDepth == 16 ||
            targetBitDepth == 24 ||
            targetBitDepth == 32)) {
      ditherTargetBitDepth = targetBitDepth;
    }
    if (PlatformCapabilities.isAndroid) {
      await _effectsChannel.setDitherParams(
        enabled: isDitherEnabled,
        targetBitDepth: ditherTargetBitDepth,
        isBluetooth: isBluetoothRoute,
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
    _reattachChain = _reattachChain.then((_) => _runReattach()).catchError((
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
    _reattachChain = _reattachChain
        .then((_) => _pushFullEffectState())
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
    if (sessionId == null || sessionId <= 0) {
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
        _effectsChannel.setCrossfeedParams(crossfeedDelayUs, crossfeedFeedDb),
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
      if (reverbCrossChannel > 0.0) {
        futures.add(
          _effectsChannel.setReverbCrossChannel(reverbCrossChannel),
        );
      }
      if (reverbPreset == ReverbPreset.custom.wireValue &&
          customImpulseResponse.isNotEmpty) {
        futures.add(
            _effectsChannel.loadImpulseResponse(customImpulseResponse));
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
    unawaited(_effectsChannel.getAutoDegradedStages());
  }

  void dispose() {
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
    unawaited(_savePreferences());
    try {
      effectStatusNotifier.dispose();
    } catch (_) {}
  }
}
