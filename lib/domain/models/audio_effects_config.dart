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

class AudioEffectsConfig {
  final bool isVirtualizerEnabled;
  final double virtualizerStrength; // 0.0 to 1.0 (maps to 0 - 1000 in Android)
  final bool isDynamicsEnabled;
  final DynamicsPreset dynamicsPreset;

  const AudioEffectsConfig({
    this.isVirtualizerEnabled = false,
    this.virtualizerStrength = 0.0,
    this.isDynamicsEnabled = false,
    this.dynamicsPreset = DynamicsPreset.off,
  });

  AudioEffectsConfig copyWith({
    bool? isVirtualizerEnabled,
    double? virtualizerStrength,
    bool? isDynamicsEnabled,
    DynamicsPreset? dynamicsPreset,
  }) {
    return AudioEffectsConfig(
      isVirtualizerEnabled: isVirtualizerEnabled ?? this.isVirtualizerEnabled,
      virtualizerStrength: virtualizerStrength ?? this.virtualizerStrength,
      isDynamicsEnabled: isDynamicsEnabled ?? this.isDynamicsEnabled,
      dynamicsPreset: dynamicsPreset ?? this.dynamicsPreset,
    );
  }
}
