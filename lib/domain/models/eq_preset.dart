// lib/domain/models/eq_preset.dart

class EqBand {
  final int index;
  final double centerFrequency; // in Hz, e.g. 60, 230, 910, 3600, 14000
  final double gain; // in dB, typically -15.0 to 15.0

  const EqBand({
    required this.index,
    required this.centerFrequency,
    required this.gain,
  });

  EqBand copyWith({double? gain}) {
    return EqBand(
      index: index,
      centerFrequency: centerFrequency,
      gain: gain ?? this.gain,
    );
  }
}

class EqPreset {
  final String name;
  final List<double> gains; // Gains for 5 bands in dB
  final double bassBoost; // 0.0 to 1.0

  const EqPreset({
    required this.name,
    required this.gains,
    this.bassBoost = 0.0,
  });

  EqPreset copyWith({
    String? name,
    List<double>? gains,
    double? bassBoost,
  }) {
    return EqPreset(
      name: name ?? this.name,
      gains: gains ?? this.gains,
      bassBoost: bassBoost ?? this.bassBoost,
    );
  }

  static const List<EqPreset> defaultPresets = [
    EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0], bassBoost: 0.0),
    EqPreset(name: 'Bass Boost', gains: [6, 4, 1, 0, 0], bassBoost: 0.5),
    EqPreset(name: 'Rock', gains: [4.5, 2.5, -1.0, 2.0, 4.0], bassBoost: 0.2),
    EqPreset(name: 'Pop', gains: [-1.0, 2.0, 4.0, 2.0, -1.0], bassBoost: 0.1),
    EqPreset(name: 'Jazz', gains: [3.0, 1.5, -1.5, 2.5, 3.5], bassBoost: 0.1),
    EqPreset(name: 'Electronic', gains: [5.0, 3.5, 0.0, 2.5, 4.5], bassBoost: 0.4),
    EqPreset(name: 'Vocal Boost', gains: [-2.0, 1.0, 4.5, 3.0, 0.5], bassBoost: 0.0),
    EqPreset(name: 'Classical', gains: [4.0, 2.5, 0.0, 2.5, 3.5], bassBoost: 0.0),
  ];
}
