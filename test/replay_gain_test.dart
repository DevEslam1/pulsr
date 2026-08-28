import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

double calculateReplayGainMultiplier(double? replayGainDb,
    {double baseVolume = 1.0}) {
  if (replayGainDb == null || replayGainDb == 0.0) return baseVolume;
  final mult = math.pow(10.0, replayGainDb / 20.0);
  return (baseVolume * mult).clamp(0.0, 1.0).toDouble();
}

void main() {
  group('ReplayGain Calculation Tests', () {
    test('Null or 0 dB gain preserves base volume', () {
      expect(calculateReplayGainMultiplier(null), equals(1.0));
      expect(calculateReplayGainMultiplier(0.0), equals(1.0));
      expect(calculateReplayGainMultiplier(null, baseVolume: 0.8), equals(0.8));
    });

    test('-6 dB gain halves the linear amplitude approximately', () {
      final volume = calculateReplayGainMultiplier(-6.0206);
      expect(volume, closeTo(0.5, 0.01));
    });

    test('+6 dB gain doubles linear amplitude and clamps to 1.0 max', () {
      final volume = calculateReplayGainMultiplier(6.0, baseVolume: 0.4);
      expect(volume, closeTo(0.8, 0.05));

      final clamped = calculateReplayGainMultiplier(12.0, baseVolume: 1.0);
      expect(clamped, equals(1.0));
    });
  });
}
