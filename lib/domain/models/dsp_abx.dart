// lib/domain/models/dsp_abx.dart
import 'dart:math';

/// Minimal blind A/B/X helper for DSP validation.
/// Shuffles trial order so UI tests can verify unbiased comparison,
/// and exposes a null-test gain check used by automated tests.
class DspAbxHelper {
  DspAbxHelper({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Returns a shuffled list containing [trialsPerOption] copies of 'A' and 'B'.
  List<String> shuffledTrials({int trialsPerOption = 5}) {
    final trials = <String>[
      for (var i = 0; i < trialsPerOption; i++) ...['A', 'B'],
    ];
    trials.shuffle(_random);
    return trials;
  }

  /// Null-test: two identical gain pairs must sum to the same total.
  static bool gainsNull((double, double) a, (double, double) b,
      {double epsilon = 1e-9}) {
    return ((a.$1 + a.$2) - (b.$1 + b.$2)).abs() <= epsilon;
  }
}
