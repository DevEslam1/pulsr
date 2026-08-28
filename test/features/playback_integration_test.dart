import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

void main() {
  group('Playback Integration Tests (Crossfade & Sleep Timer)', () {
    test('CrossfadeManager evaluates all curves within [0.0, 1.0] range', () {
      final manager = CrossfadeManager();

      for (final curve in CrossfadeCurve.values) {
        manager.curve = curve;
        expect(manager.evaluateCurve(0.0), closeTo(0.0, 0.01),
            reason: '${curve.name} at 0.0 should be 0');
        expect(manager.evaluateCurve(1.0), closeTo(1.0, 0.01),
            reason: '${curve.name} at 1.0 should be 1');

        for (double t = 0.0; t <= 1.0; t += 0.1) {
          final val = manager.evaluateCurve(t);
          expect(val, greaterThanOrEqualTo(-0.001));
          expect(val, lessThanOrEqualTo(1.001));
        }
      }
    });

    test(
        'CrossfadeManager calculateBpmAlignedDuration returns clamped duration',
        () {
      // 120 BPM = 0.5s per beat * 4 = 2.0s
      final aligned = CrossfadeManager.calculateBpmAlignedDuration(
        const Duration(seconds: 2),
        120.0,
      );
      expect(aligned.inMilliseconds, equals(2000));

      // Out of bounds BPM (e.g. 30 BPM) returns baseDuration unchanged
      final outOfBounds = CrossfadeManager.calculateBpmAlignedDuration(
        const Duration(seconds: 3),
        30.0,
      );
      expect(outOfBounds.inMilliseconds, equals(3000));
    });

    test('Equal power crossfade curve preserves constant acoustic loudness',
        () {
      final manager = CrossfadeManager()..curve = CrossfadeCurve.equalPower;

      for (double t = 0.0; t <= 1.0; t += 0.1) {
        final fadeOut = math.cos(t * (math.pi / 2));
        final fadeIn = manager.evaluateCurve(t);

        final powerSum = (fadeOut * fadeOut) + (fadeIn * fadeIn);
        expect(powerSum, closeTo(1.0, 0.05),
            reason: 'Power sum at t=$t should preserve constant power');
      }
    });

    test('PlayerState correctly sets sleep timer duration', () {
      const state = PlayerState(
        sleepTimerRemaining: Duration(minutes: 15),
        isPlaying: true,
      );

      expect(state.sleepTimerRemaining, equals(const Duration(minutes: 15)));
      expect(state.isPlaying, isTrue);
    });
  });
}
