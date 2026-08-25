// lib/domain/models/audio_effects_config.dart

enum DynamicsPreset {
  off('Direct', 'No compression or dynamics processing applied'),
  studioPunch('Studio Punch', 'Modern punchy dynamics with transient snap & limiting'),
  warmAnalog('Warm Analog', 'Gentle tube-style warmth with rich low-mid presence'),
  vocalFocus('Vocal Focus', 'Crisp vocal presence with vocal intelligibility boost'),
  nightLeveller('Night Leveller', 'Smooths volume peaks for comfortable quiet listening'),
  bassTightener('Bass Tightener', 'Controls sub-bass rumble for tight, punchy low-end');

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

  const AudioEffectsConfig({
    this.isVirtualizerEnabled = false,
    this.virtualizerStrength = 0.0,
    this.isDynamicsEnabled = false,
    this.dynamicsPreset = DynamicsPreset.off,
    this.isDynamicsBypassed = false,
  });

  AudioEffectsConfig copyWith({
    bool? isVirtualizerEnabled,
    double? virtualizerStrength,
    bool? isDynamicsEnabled,
    DynamicsPreset? dynamicsPreset,
    bool? isDynamicsBypassed,
  }) {
    return AudioEffectsConfig(
      isVirtualizerEnabled: isVirtualizerEnabled ?? this.isVirtualizerEnabled,
      virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
      isDynamicsEnabled: isDynamicsEnabled ?? this.isDynamicsEnabled,
      dynamicsPreset: dynamicsPreset ?? this.dynamicsPreset,
      isDynamicsBypassed: isDynamicsBypassed ?? this.isDynamicsBypassed,
    );
  }
}
