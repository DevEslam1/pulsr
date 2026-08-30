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

class CustomDynamicsPreset {
  final String id;
  final String name;
  final DynamicsPreset basePreset;
  final double? thresholdOverride;
  final double? ratioOverride;
  final double? postGainOverride;

  const CustomDynamicsPreset({
    required this.id,
    required this.name,
    required this.basePreset,
    this.thresholdOverride,
    this.ratioOverride,
    this.postGainOverride,
  });

  factory CustomDynamicsPreset.fromJson(Map<String, dynamic> json) {
    return CustomDynamicsPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      basePreset: DynamicsPreset.values.firstWhere(
        (d) => d.name == json['basePreset'],
        orElse: () => DynamicsPreset.studioPunch,
      ),
      thresholdOverride: (json['thresholdOverride'] as num?)?.toDouble(),
      ratioOverride: (json['ratioOverride'] as num?)?.toDouble(),
      postGainOverride: (json['postGainOverride'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'basePreset': basePreset.name,
        if (thresholdOverride != null) 'thresholdOverride': thresholdOverride,
        if (ratioOverride != null) 'ratioOverride': ratioOverride,
        if (postGainOverride != null) 'postGainOverride': postGainOverride,
      };
}

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
  final bool isStereoWidthEnabled;
  final double stereoWidth; // 0.0 mono … 1.0 normal … 2.0 widened
  final bool isLoudnessContourEnabled;
  final double loudnessContourIntensity; // 0.0 to 1.0
  final bool isSubCrossoverEnabled;
  final double subCrossoverCornerHz; // 60 to 150
  final double subCrossoverSlopeDbPerOct; // 12 or 24
  final double subCrossoverGain; // 0.0 to 1.0
  final bool isDynamicEqEnabled;
  final List<DynamicEqBandConfig> dynamicEqBands;

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
    this.isStereoWidthEnabled = false,
    this.stereoWidth = 1.0,
    this.isLoudnessContourEnabled = false,
    this.loudnessContourIntensity = 0.0,
    this.isSubCrossoverEnabled = false,
    this.subCrossoverCornerHz = 80.0,
    this.subCrossoverSlopeDbPerOct = 24.0,
    this.subCrossoverGain = 0.8,
    this.isDynamicEqEnabled = false,
    this.dynamicEqBands = const [],
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
    bool? isStereoWidthEnabled,
    double? stereoWidth,
    bool? isLoudnessContourEnabled,
    double? loudnessContourIntensity,
    bool? isSubCrossoverEnabled,
    double? subCrossoverCornerHz,
    double? subCrossoverSlopeDbPerOct,
    double? subCrossoverGain,
    bool? isDynamicEqEnabled,
    List<DynamicEqBandConfig>? dynamicEqBands,
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
      isStereoWidthEnabled: isStereoWidthEnabled ?? this.isStereoWidthEnabled,
      stereoWidth: stereoWidth ?? this.stereoWidth,
      isLoudnessContourEnabled:
          isLoudnessContourEnabled ?? this.isLoudnessContourEnabled,
      loudnessContourIntensity:
          loudnessContourIntensity ?? this.loudnessContourIntensity,
      isSubCrossoverEnabled: isSubCrossoverEnabled ?? this.isSubCrossoverEnabled,
      subCrossoverCornerHz: subCrossoverCornerHz ?? this.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct:
          subCrossoverSlopeDbPerOct ?? this.subCrossoverSlopeDbPerOct,
      subCrossoverGain: subCrossoverGain ?? this.subCrossoverGain,
      isDynamicEqEnabled: isDynamicEqEnabled ?? this.isDynamicEqEnabled,
      dynamicEqBands: dynamicEqBands ?? this.dynamicEqBands,
    );
  }
}

/// One dynamic-EQ band. Mirrors the native `DynamicEqBandParam` struct:
/// the band engages (cuts) only while signal energy inside the band exceeds
/// [thresholdDb]. Cut-only — boost is intentionally not supported.
class DynamicEqBandConfig {
  final double frequency;
  final double q;
  final double thresholdDb;
  final double ratio;
  final double attackMs;
  final double releaseMs;
  final double maxCutDb; // <= 0
  final bool enabled;

  const DynamicEqBandConfig({
    this.frequency = 1000.0,
    this.q = 2.0,
    this.thresholdDb = -30.0,
    this.ratio = 3.0,
    this.attackMs = 5.0,
    this.releaseMs = 120.0,
    this.maxCutDb = -12.0,
    this.enabled = true,
  });

  DynamicEqBandConfig copyWith({
    double? frequency,
    double? q,
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? maxCutDb,
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
      maxCutDb: (json['maxCutDb'] as num?)?.toDouble() ?? -12.0,
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
        'enabled': enabled,
      };
}
