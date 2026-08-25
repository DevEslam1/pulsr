// lib/domain/models/eq_preset.dart
import 'dart:math' as math;

class EqBand {
  final int index;
  final double centerFrequency; // in Hz, one of EqPreset.centerFrequencies
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
  final List<double> gains; // Gains for the 10 bands in dB
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

  /// ISO 10-band graphic-EQ centers (Hz). These are the fixed centers driven
  /// through the native DynamicsProcessing postEq.
  static const List<double> centerFrequencies = [
    32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];

  /// The 5-band centers used by Pulsr before the 10-band migration. Kept only
  /// so old saved gains / bundled headphone profiles can be up-sampled.
  static const List<double> legacyFrequencies = [60, 230, 910, 3600, 14000];

  /// Maps [source] gains onto the 10 [centerFrequencies] via linear
  /// interpolation in log-frequency space. A list already of length 10 is
  /// returned unchanged; a length-5 list is treated as the legacy layout;
  /// any other length is spread evenly across the target span.
  static List<double> interpolateGains(List<double> source) {
    final n = centerFrequencies.length;
    if (source.length == n) return List<double>.from(source);
    if (source.isEmpty) return List<double>.filled(n, 0.0);
    if (source.length == 1) return List<double>.filled(n, source.first);

    final srcFreqs = source.length == legacyFrequencies.length
        ? legacyFrequencies
        : _logSpread(source.length);

    return [for (final f in centerFrequencies) _interpAtLogFreq(f, srcFreqs, source)];
  }

  static double _interpAtLogFreq(double freq, List<double> freqs, List<double> gains) {
    final logF = math.log(freq);
    if (logF <= math.log(freqs.first)) return gains.first;
    if (logF >= math.log(freqs.last)) return gains.last;
    for (int i = 0; i < freqs.length - 1; i++) {
      final lo = math.log(freqs[i]);
      final hi = math.log(freqs[i + 1]);
      if (logF >= lo && logF <= hi) {
        final t = (logF - lo) / (hi - lo);
        return gains[i] + (gains[i + 1] - gains[i]) * t;
      }
    }
    return gains.last;
  }

  static List<double> _logSpread(int count) {
    final logLo = math.log(centerFrequencies.first);
    final logHi = math.log(centerFrequencies.last);
    return [
      for (int i = 0; i < count; i++)
        math.exp(logLo + (logHi - logLo) * (i / (count - 1))),
    ];
  }

  static const List<EqPreset> defaultPresets = [
    EqPreset(name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], bassBoost: 0.0),
    EqPreset(name: 'Bass Boost', gains: [7, 6.5, 5, 3, 1, 0, 0, 0, 0, 0], bassBoost: 0.5),
    EqPreset(name: 'Rock', gains: [5, 4, 2.5, 0, -1, -1, 0.5, 2.5, 4, 4.5], bassBoost: 0.2),
    EqPreset(name: 'Pop', gains: [-1, -0.5, 0.5, 2, 3.5, 4, 3, 1.5, 0, -1], bassBoost: 0.1),
    EqPreset(name: 'Jazz', gains: [3.5, 3, 2, 1, -0.5, -1, 0, 1.5, 3, 3.5], bassBoost: 0.1),
    EqPreset(name: 'Electronic', gains: [6, 5.5, 4, 2, 0, -0.5, 0.5, 2.5, 4.5, 5], bassBoost: 0.4),
    EqPreset(name: 'Vocal Boost', gains: [-3, -2.5, -1, 1, 3.5, 4.5, 4, 2, 0.5, -0.5], bassBoost: 0.0),
    EqPreset(name: 'Classical', gains: [4, 3.5, 2.5, 1, 0, -0.5, 0, 1.5, 3, 3.5], bassBoost: 0.0),
  ];
}
