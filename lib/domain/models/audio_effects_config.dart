// lib/domain/models/audio_effects_config.dart

enum DynamicsPreset {
  off('Direct', 'No compression or dynamics processing applied'),
  studioPunch(
      'Studio Punch', 'Modern punchy dynamics with transient snap & limiting'),
  warmAnalog(
      'Warm Analog', 'Gentle tube-style warmth with rich low-mid presence'),
  vocalFocus(
      'Vocal Focus', 'Crisp vocal presence with vocal intelligibility boost'),
  nightLeveller(
      'Night Leveller', 'Smooths volume peaks for comfortable quiet listening'),
  bassTightener(
      'Bass Tightener', 'Controls sub-bass rumble for tight, punchy low-end');

  final String label;
  final String description;

  const DynamicsPreset(this.label, this.description);
}

// Note (H-6): the legacy HAL CustomDynamicsPreset was removed because its
// thresholdOverride / ratioOverride / postGainOverride were never transmitted to
// native — only the preset name was sent. Custom (user-tuned) dynamics are now
// owned by the native 4-band Multiband Compressor via setMultibandCompressorBand,
// which carries threshold/ratio/attack/release/knee/makeup per band and is the
// single source of truth for user-edited dynamics.


class AudioEffectsConfig {
  final bool isVirtualizerEnabled;
  final double virtualizerStrength; // 0.0 to 1.0 (maps to 0 - 1000 in Android)
  final bool isDynamicsEnabled;
  final DynamicsPreset dynamicsPreset;
  final bool isDynamicsBypassed;
  // Phase 1 DSP expansion stages
  final bool isSaturationEnabled;
  final double saturationDrive; // 0.0 to 1.0
  final double saturationMix; // 0.0 to 1.0 wet/dry
  final double saturationTilt; // 0.0 to 1.0 HF pre-emphasis
  final int saturationMode; // 0=Tape, 1=Tube, 2=Analog Class-A
  final bool isStereoWidthEnabled;
  final double stereoWidth; // 0.0 mono … 1.0 normal … 2.0 widened
  final bool stereoWidthMultiband;
  final double stereoWidthLow;
  final double stereoWidthMid;
  final double stereoWidthHigh;
  final double stereoWidthLowCrossoverHz;
  final double stereoWidthHighCrossoverHz;
  final bool isLoudnessContourEnabled;
  final double loudnessContourIntensity; // 0.0 to 1.0
  final bool isSubCrossoverEnabled;
  final double subCrossoverCornerHz; // 60 to 150
  final double subCrossoverSlopeDbPerOct; // 12 or 24
  final double subCrossoverGain; // 0.0 to 1.0
  final bool subCrossoverBassMono;
  final bool subCrossoverAntiPop;
  final bool isDynamicEqEnabled;
  final List<DynamicEqBandConfig> dynamicEqBands;
  final bool isMultibandCompressorEnabled;
  final List<MultibandCompressorBandConfig> multibandCompressorBands;
  final bool isDynamicBassEnabled;
  final double dynamicBassStrength;
  final int dynamicBassXLow;
  final int dynamicBassXHigh;
  final int dynamicBassYLow;
  final int dynamicBassYHigh;
  final double dynamicBassSideGainLow;
  final double dynamicBassSideGainHigh;
  final int dynamicBassPreset;

  const AudioEffectsConfig({
    this.isVirtualizerEnabled = false,
    this.virtualizerStrength = 0.0,
    this.isDynamicsEnabled = false,
    this.dynamicsPreset = DynamicsPreset.off,
    this.isDynamicsBypassed = false,
    this.isSaturationEnabled = false,
    this.saturationDrive = 0.3,
    this.saturationMix = 0.5,
    this.saturationTilt = 0.3,
    this.saturationMode = 0,
    this.isStereoWidthEnabled = false,
    this.stereoWidth = 1.0,
    this.stereoWidthMultiband = false,
    this.stereoWidthLow = 1.0,
    this.stereoWidthMid = 1.0,
    this.stereoWidthHigh = 1.0,
    this.stereoWidthLowCrossoverHz = 160.0,
    this.stereoWidthHighCrossoverHz = 2500.0,
    this.isLoudnessContourEnabled = false,
    this.loudnessContourIntensity = 0.0,
    this.isSubCrossoverEnabled = false,
    this.subCrossoverCornerHz = 80.0,
    this.subCrossoverSlopeDbPerOct = 24.0,
    this.subCrossoverGain = 0.8,
    this.subCrossoverBassMono = false,
    this.subCrossoverAntiPop = true,
    this.isDynamicEqEnabled = false,
    this.dynamicEqBands = const [],
    this.isMultibandCompressorEnabled = false,
    this.multibandCompressorBands = const [],
    this.isDynamicBassEnabled = false,
    this.dynamicBassStrength = 1.0,
    this.dynamicBassXLow = 100,
    this.dynamicBassXHigh = 5600,
    this.dynamicBassYLow = 40,
    this.dynamicBassYHigh = 80,
    this.dynamicBassSideGainLow = 0.10,
    this.dynamicBassSideGainHigh = 0.50,
    this.dynamicBassPreset = 0,
  });

  AudioEffectsConfig copyWith({
    bool? isVirtualizerEnabled,
    double? virtualizerStrength,
    bool? isDynamicsEnabled,
    DynamicsPreset? dynamicsPreset,
    bool? isDynamicsBypassed,
    bool? isSaturationEnabled,
    double? saturationDrive,
    double? saturationMix,
    double? saturationTilt,
    int? saturationMode,
    bool? isStereoWidthEnabled,
    double? stereoWidth,
    bool? stereoWidthMultiband,
    double? stereoWidthLow,
    double? stereoWidthMid,
    double? stereoWidthHigh,
    double? stereoWidthLowCrossoverHz,
    double? stereoWidthHighCrossoverHz,
    bool? isLoudnessContourEnabled,
    double? loudnessContourIntensity,
    bool? isSubCrossoverEnabled,
    double? subCrossoverCornerHz,
    double? subCrossoverSlopeDbPerOct,
    double? subCrossoverGain,
    bool? subCrossoverBassMono,
    bool? subCrossoverAntiPop,
    bool? isDynamicEqEnabled,
    List<DynamicEqBandConfig>? dynamicEqBands,
    bool? isMultibandCompressorEnabled,
    List<MultibandCompressorBandConfig>? multibandCompressorBands,
    bool? isDynamicBassEnabled,
    double? dynamicBassStrength,
    int? dynamicBassXLow,
    int? dynamicBassXHigh,
    int? dynamicBassYLow,
    int? dynamicBassYHigh,
    double? dynamicBassSideGainLow,
    double? dynamicBassSideGainHigh,
    int? dynamicBassPreset,
  }) {
    return AudioEffectsConfig(
      isVirtualizerEnabled: isVirtualizerEnabled ?? this.isVirtualizerEnabled,
      virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
      isDynamicsEnabled: isDynamicsEnabled ?? this.isDynamicsEnabled,
      dynamicsPreset: dynamicsPreset ?? this.dynamicsPreset,
      isDynamicsBypassed: isDynamicsBypassed ?? this.isDynamicsBypassed,
      isSaturationEnabled: isSaturationEnabled ?? this.isSaturationEnabled,
      saturationDrive: saturationDrive ?? this.saturationDrive,
      saturationMix: saturationMix ?? this.saturationMix,
      saturationTilt: saturationTilt ?? this.saturationTilt,
      saturationMode: saturationMode ?? this.saturationMode,
      isStereoWidthEnabled: isStereoWidthEnabled ?? this.isStereoWidthEnabled,
      stereoWidth: stereoWidth ?? this.stereoWidth,
      stereoWidthMultiband: stereoWidthMultiband ?? this.stereoWidthMultiband,
      stereoWidthLow: stereoWidthLow ?? this.stereoWidthLow,
      stereoWidthMid: stereoWidthMid ?? this.stereoWidthMid,
      stereoWidthHigh: stereoWidthHigh ?? this.stereoWidthHigh,
      stereoWidthLowCrossoverHz:
          stereoWidthLowCrossoverHz ?? this.stereoWidthLowCrossoverHz,
      stereoWidthHighCrossoverHz:
          stereoWidthHighCrossoverHz ?? this.stereoWidthHighCrossoverHz,
      isLoudnessContourEnabled:
          isLoudnessContourEnabled ?? this.isLoudnessContourEnabled,
      loudnessContourIntensity:
          loudnessContourIntensity ?? this.loudnessContourIntensity,
      isSubCrossoverEnabled: isSubCrossoverEnabled ?? this.isSubCrossoverEnabled,
      subCrossoverCornerHz: subCrossoverCornerHz ?? this.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct:
          subCrossoverSlopeDbPerOct ?? this.subCrossoverSlopeDbPerOct,
      subCrossoverGain: subCrossoverGain ?? this.subCrossoverGain,
      subCrossoverBassMono: subCrossoverBassMono ?? this.subCrossoverBassMono,
      subCrossoverAntiPop: subCrossoverAntiPop ?? this.subCrossoverAntiPop,
      isDynamicEqEnabled: isDynamicEqEnabled ?? this.isDynamicEqEnabled,
      dynamicEqBands: dynamicEqBands ?? this.dynamicEqBands,
      isMultibandCompressorEnabled:
          isMultibandCompressorEnabled ?? this.isMultibandCompressorEnabled,
      multibandCompressorBands:
          multibandCompressorBands ?? this.multibandCompressorBands,
      isDynamicBassEnabled:
          isDynamicBassEnabled ?? this.isDynamicBassEnabled,
      dynamicBassStrength:
          dynamicBassStrength ?? this.dynamicBassStrength,
      dynamicBassXLow: dynamicBassXLow ?? this.dynamicBassXLow,
      dynamicBassXHigh: dynamicBassXHigh ?? this.dynamicBassXHigh,
      dynamicBassYLow: dynamicBassYLow ?? this.dynamicBassYLow,
      dynamicBassYHigh: dynamicBassYHigh ?? this.dynamicBassYHigh,
      dynamicBassSideGainLow:
          dynamicBassSideGainLow ?? this.dynamicBassSideGainLow,
      dynamicBassSideGainHigh:
          dynamicBassSideGainHigh ?? this.dynamicBassSideGainHigh,
      dynamicBassPreset: dynamicBassPreset ?? this.dynamicBassPreset,
    );
  }
}

/// One dynamic-EQ band. Supports both Cut and Boost modes, with Peaking,
/// Low-Shelf, and High-Shelf filter types.
class DynamicEqBandConfig {
  final double frequency;
  final double q;
  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double maxCutDb; // <= 0
  final double maxBoostDb; // >= 0
  final int mode; // 0=Cut, 1=Boost
  final int filterType; // 0=Peaking, 1=LowShelf, 2=HighShelf
  final bool enabled;

  const DynamicEqBandConfig({
    this.frequency = 1000.0,
    this.q = 2.0,
    this.thresholdDb = -30.0,
    this.ratio = 3.0,
    this.attackMs = 5.0,
    this.releaseMs = 120.0,
    this.maxCutDb = -12.0,
    this.maxBoostDb = 12.0,
    this.mode = 0,
    this.filterType = 0,
    this.enabled = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DynamicEqBandConfig &&
          runtimeType == other.runtimeType &&
          frequency == other.frequency &&
          q == other.q &&
          thresholdDb == other.thresholdDb &&
          ratio == other.ratio &&
          attackMs == other.attackMs &&
          releaseMs == other.releaseMs &&
          maxCutDb == other.maxCutDb &&
          maxBoostDb == other.maxBoostDb &&
          mode == other.mode &&
          filterType == other.filterType &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(frequency, q, thresholdDb, ratio, attackMs,
      releaseMs, maxCutDb, maxBoostDb, mode, filterType, enabled);

  DynamicEqBandConfig copyWith({
    double? frequency,
    double? q,
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? maxCutDb,
    double? maxBoostDb,
    int? mode,
    int? filterType,
    bool? enabled,
  }) {
    return DynamicEqBandConfig(
      frequency: frequency ?? this.frequency,
      q: q ?? this.q,
      thresholdDb: thresholdDb ?? this.thresholdDb,
      ratio: ratio ?? this.ratio,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      maxCutDb: maxCutDb ?? this.maxCutDb,
      maxBoostDb: maxBoostDb ?? this.maxBoostDb,
      mode: mode ?? this.mode,
      filterType: filterType ?? this.filterType,
      enabled: enabled ?? this.enabled,
    );
  }

  factory DynamicEqBandConfig.fromJson(Map<String, dynamic> json) {
    return DynamicEqBandConfig(
      frequency: (json['frequency'] as num?)?.toDouble() ?? 1000.0,
      q: (json['q'] as num?)?.toDouble() ?? 2.0,
      thresholdDb: (json['thresholdDb'] as num?)?.toDouble() ?? -30.0,
      ratio: (json['ratio'] as num?)?.toDouble() ?? 3.0,
      attackMs: (json['attackMs'] as num?)?.toDouble() ?? 5.0,
      releaseMs: (json['releaseMs'] as num?)?.toDouble() ?? 120.0,
      maxCutDb: ((json['maxCutDb'] as num?)?.toDouble() ?? -12.0)
          .clamp(-96.0, 0.0)
          .toDouble(),
      maxBoostDb: ((json['maxBoostDb'] as num?)?.toDouble() ?? 12.0)
          .clamp(0.0, 96.0)
          .toDouble(),
      mode: (json['mode'] as num?)?.toInt() ?? 0,
      filterType: (json['filterType'] as num?)?.toInt() ?? 0,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency,
        'q': q,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'maxCutDb': maxCutDb,
        'maxBoostDb': maxBoostDb,
        'mode': mode,
        'filterType': filterType,
        'enabled': enabled,
      };
}

/// One band of the Native C++ 4-Band Multiband Compressor.
class MultibandCompressorBandConfig {
  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double kneeDb;
  final double makeupGainDb;
  final bool enabled;

  const MultibandCompressorBandConfig({
    this.thresholdDb = -20.0,
    this.ratio = 2.0,
    this.attackMs = 20.0,
    this.releaseMs = 100.0,
    this.kneeDb = 6.0,
    this.makeupGainDb = 0.0,
    this.enabled = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultibandCompressorBandConfig &&
          runtimeType == other.runtimeType &&
          thresholdDb == other.thresholdDb &&
          ratio == other.ratio &&
          attackMs == other.attackMs &&
          releaseMs == other.releaseMs &&
          kneeDb == other.kneeDb &&
          makeupGainDb == other.makeupGainDb &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(thresholdDb, ratio, attackMs, releaseMs, kneeDb,
      makeupGainDb, enabled);

  MultibandCompressorBandConfig copyWith({
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? kneeDb,
    double? makeupGainDb,
    bool? enabled,
  }) {
    return MultibandCompressorBandConfig(
      thresholdDb: thresholdDb ?? this.thresholdDb,
      ratio: ratio ?? this.ratio,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      kneeDb: kneeDb ?? this.kneeDb,
      makeupGainDb: makeupGainDb ?? this.makeupGainDb,
      enabled: enabled ?? this.enabled,
    );
  }

  factory MultibandCompressorBandConfig.fromJson(Map<String, dynamic> json) {
    return MultibandCompressorBandConfig(
      thresholdDb: (json['thresholdDb'] as num?)?.toDouble() ?? -20.0,
      ratio: (json['ratio'] as num?)?.toDouble() ?? 2.0,
      attackMs: (json['attackMs'] as num?)?.toDouble() ?? 20.0,
      releaseMs: (json['releaseMs'] as num?)?.toDouble() ?? 100.0,
      kneeDb: (json['kneeDb'] as num?)?.toDouble() ?? 6.0,
      makeupGainDb: (json['makeupGainDb'] as num?)?.toDouble() ?? 0.0,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'kneeDb': kneeDb,
        'makeupGainDb': makeupGainDb,
        'enabled': enabled,
      };
}

/// Modeled after ViPER4Android's Dynamic System / Dynamic Bass.
class DynamicBassConfig {
  final bool enabled;
  final double strength; // 1.0 to 8.0
  final int xLow;
  final int xHigh;
  final int yLow;
  final int yHigh;
  final double sideGainLow;
  final double sideGainHigh;
  final int preset; // 0 = Custom, 1..9 = Builtin presets

  const DynamicBassConfig({
    this.enabled = false,
    this.strength = 1.0,
    this.xLow = 100,
    this.xHigh = 5600,
    this.yLow = 40,
    this.yHigh = 80,
    this.sideGainLow = 0.10,
    this.sideGainHigh = 0.50,
    this.preset = 0,
  });

  DynamicBassConfig copyWith({
    bool? enabled,
    double? strength,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
    int? preset,
  }) {
    return DynamicBassConfig(
      enabled: enabled ?? this.enabled,
      strength: strength ?? this.strength,
      xLow: xLow ?? this.xLow,
      xHigh: xHigh ?? this.xHigh,
      yLow: yLow ?? this.yLow,
      yHigh: yHigh ?? this.yHigh,
      sideGainLow: sideGainLow ?? this.sideGainLow,
      sideGainHigh: sideGainHigh ?? this.sideGainHigh,
      preset: preset ?? this.preset,
    );
  }

  factory DynamicBassConfig.fromJson(Map<String, dynamic> json) {
    return DynamicBassConfig(
      enabled: (json['enabled'] as bool?) ?? false,
      strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
      xLow: (json['xLow'] as num?)?.toInt() ?? 100,
      xHigh: (json['xHigh'] as num?)?.toInt() ?? 5600,
      yLow: (json['yLow'] as num?)?.toInt() ?? 40,
      yHigh: (json['yHigh'] as num?)?.toInt() ?? 80,
      sideGainLow: (json['sideGainLow'] as num?)?.toDouble() ?? 0.10,
      sideGainHigh: (json['sideGainHigh'] as num?)?.toDouble() ?? 0.50,
      preset: (json['preset'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'strength': strength,
        'xLow': xLow,
        'xHigh': xHigh,
        'yLow': yLow,
        'yHigh': yHigh,
        'sideGainLow': sideGainLow,
        'sideGainHigh': sideGainHigh,
        'preset': preset,
      };

  static const List<DynamicBassPresetItem> builtinPresets = [
    DynamicBassPresetItem(
      id: 1,
      name: 'Extreme Headphone v2',
      xLow: 140,
      xHigh: 6200,
      yLow: 40,
      yHigh: 60,
      sideGainLow: 0.10,
      sideGainHigh: 0.80,
    ),
    DynamicBassPresetItem(
      id: 2,
      name: 'High-End Headphone v2',
      xLow: 180,
      xHigh: 5800,
      yLow: 55,
      yHigh: 80,
      sideGainLow: 0.10,
      sideGainHigh: 0.70,
    ),
    DynamicBassPresetItem(
      id: 3,
      name: 'Common Headphone v2',
      xLow: 300,
      xHigh: 5600,
      yLow: 60,
      yHigh: 105,
      sideGainLow: 0.10,
      sideGainHigh: 0.50,
    ),
    DynamicBassPresetItem(
      id: 4,
      name: 'Low-End Headphone v2',
      xLow: 600,
      xHigh: 5400,
      yLow: 60,
      yHigh: 105,
      sideGainLow: 0.10,
      sideGainHigh: 0.20,
    ),
    DynamicBassPresetItem(
      id: 5,
      name: 'Common Earphone v2',
      xLow: 100,
      xHigh: 5600,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.50,
      sideGainHigh: 0.50,
    ),
    DynamicBassPresetItem(
      id: 6,
      name: 'Extreme Headphone v1',
      xLow: 1200,
      xHigh: 6200,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.0,
      sideGainHigh: 0.20,
    ),
    DynamicBassPresetItem(
      id: 7,
      name: 'High-End Headphone v1',
      xLow: 1000,
      xHigh: 6200,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.0,
      sideGainHigh: 0.10,
    ),
    DynamicBassPresetItem(
      id: 8,
      name: 'Common Headphone v1',
      xLow: 800,
      xHigh: 6200,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.10,
      sideGainHigh: 0.0,
    ),
    DynamicBassPresetItem(
      id: 9,
      name: 'Common Earphone v1',
      xLow: 400,
      xHigh: 6200,
      yLow: 40,
      yHigh: 80,
      sideGainLow: 0.10,
      sideGainHigh: 0.0,
    ),
  ];
}

class DynamicBassPresetItem {
  final int id;
  final String name;
  final int xLow;
  final int xHigh;
  final int yLow;
  final int yHigh;
  final double sideGainLow;
  final double sideGainHigh;

  const DynamicBassPresetItem({
    required this.id,
    required this.name,
    required this.xLow,
    required this.xHigh,
    required this.yLow,
    required this.yHigh,
    required this.sideGainLow,
    required this.sideGainHigh,
  });
}

