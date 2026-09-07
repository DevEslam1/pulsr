import 'dart:async';
import 'dart:math' as math;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  late CrossfadeManager crossfadeManager;
  late MockAudioPlayer mockPlayerA;
  late MockAudioPlayer mockPlayerB;

  setUp(() {
    crossfadeManager = CrossfadeManager();
    mockPlayerA = MockAudioPlayer();
    mockPlayerB = MockAudioPlayer();

    when(() => mockPlayerA.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayerB.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayerA.stop()).thenAnswer((_) async {});
    when(() => mockPlayerB.stop()).thenAnswer((_) async {});
    // Native gain-ramp API: unstubbed calls resolve to null, which the
    // manager treats as "unsupported" and falls back to stepped volume.
    when(() => mockPlayerA.dspSetGainCurve(any(),
        segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
    when(() => mockPlayerB.dspSetGainCurve(any(),
        segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
    when(() => mockPlayerA.dspClearGainCurve()).thenAnswer((_) async => false);
    when(() => mockPlayerB.dspClearGainCurve()).thenAnswer((_) async => false);
  });

  tearDown(() {
    crossfadeManager.dispose();
  });

  group('CrossfadeManager Concurrency & Atomic Fade Token', () {
    test('nextFadeId increments atomically', () {
      final id1 = crossfadeManager.nextFadeId();
      final id2 = crossfadeManager.nextFadeId();
      expect(id2, equals(id1 + 1));
      expect(crossfadeManager.currentFadeId, equals(id2));
    });

    test('protect runs actions exclusively via Mutex', () async {
      final executionOrder = <int>[];

      final future1 = crossfadeManager.protect(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        executionOrder.add(1);
      });

      final future2 = crossfadeManager.protect(() async {
        executionOrder.add(2);
      });

      await Future.wait([future1, future2]);
      expect(executionOrder, equals([1, 2]));
    });

    test('fadeVolume completes immediately if duration is Duration.zero',
        () async {
      await crossfadeManager.fadeVolume(
        mockPlayerA,
        0.0,
        1.0,
        Duration.zero,
        crossfadeManager.currentFadeId,
      );

      verify(() => mockPlayerA.setVolume(1.0)).called(1);
    });

    test('fadeVolume executes equal-power curve transitions', () async {
      final volumes = <double>[];
      when(() => mockPlayerA.setVolume(any())).thenAnswer((inv) async {
        volumes.add(inv.positionalArguments[0] as double);
      });

      final fadeId = crossfadeManager.nextFadeId();
      await crossfadeManager.fadeVolume(
        mockPlayerA,
        0.0,
        1.0,
        const Duration(milliseconds: 80),
        fadeId,
      );

      expect(volumes.isNotEmpty, isTrue);
      expect(volumes.last, equals(1.0));
      // Equal power curve increases monotonically
      for (int i = 1; i < volumes.length; i++) {
        expect(volumes[i], greaterThanOrEqualTo(volumes[i - 1]));
      }
    });

    test('cancel bumps fadeId and stops inactive player', () async {
      final initialFadeId = crossfadeManager.currentFadeId;
      crossfadeManager.beginCrossfade(3);
      expect(crossfadeManager.isCrossfading, isTrue);
      expect(crossfadeManager.pendingIndex, equals(3));

      await crossfadeManager.cancel(mockPlayerA, mockPlayerB,
          restoreVolume: 0.8);

      expect(crossfadeManager.isCrossfading, isFalse);
      expect(crossfadeManager.pendingIndex, isNull);
      expect(crossfadeManager.currentFadeId, greaterThan(initialFadeId));
      verify(() => mockPlayerA.stop()).called(1);
      verify(() => mockPlayerA.setVolume(0.8)).called(1);
      verify(() => mockPlayerB.setVolume(0.8)).called(1);
    });

    test('waitForActiveCrossfade completes when finishCrossfade is called',
        () async {
      crossfadeManager.beginCrossfade(1);
      bool finished = false;

      unawaited(crossfadeManager.waitForActiveCrossfade().then((_) {
        finished = true;
      }));

      expect(finished, isFalse);
      crossfadeManager.finishCrossfade();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(finished, isTrue);
    });
  });

  group('Gain Pair Math (all 5 curves)', () {
    const curves = CrossfadeCurve.values;
    const samples = 101;

    List<(double, double)> pairsFor(CrossfadeCurve curve,
        {bool isRepeatOne = false}) {
      final mgr = CrossfadeManager()..curve = curve;
      return [
        for (int i = 0; i < samples; i++)
          mgr.evaluateGainPair(i / (samples - 1), isRepeatOne: isRepeatOne)
      ];
    }

    test('endpoints are exact for every curve: f=0 -> (1,0), f=1 -> (0,1)',
        () {
      for (final curve in curves) {
        final pairs = pairsFor(curve);
        expect(pairs.first.$1, closeTo(1.0, 1e-9),
            reason: '${curve.name} f=0 oldGain');
        expect(pairs.first.$2, closeTo(0.0, 1e-9),
            reason: '${curve.name} f=0 newGain');
        expect(pairs.last.$1, closeTo(0.0, 1e-9),
            reason: '${curve.name} f=1 oldGain');
        expect(pairs.last.$2, closeTo(1.0, 1e-9),
            reason: '${curve.name} f=1 newGain');
      }
    });

    test('repeat-one always returns the linear pair (1-f, f) regardless of '
        'the selected curve', () {
      for (final curve in curves) {
        final mgr = CrossfadeManager()..curve = curve;
        for (int i = 0; i <= 10; i++) {
          final f = i / 10;
          final (oldGain, newGain) =
              mgr.evaluateGainPair(f, isRepeatOne: true);
          expect(oldGain, closeTo(1.0 - f, 1e-9),
              reason: '${curve.name} f=$f');
          expect(newGain, closeTo(f, 1e-9), reason: '${curve.name} f=$f');
        }
      }
    });

    test('equal-power raw pair keeps constant acoustic power (cos²+sin²=1)',
        () {
      final pairs = pairsFor(CrossfadeCurve.equalPower);
      for (final (oldGain, newGain) in pairs) {
        expect(oldGain * oldGain + newGain * newGain, closeTo(1.0, 1e-9));
      }
    });

    test('fade-in side is monotonically non-decreasing for every curve', () {
      for (final curve in curves) {
        final pairs = pairsFor(curve);
        for (int i = 1; i < pairs.length; i++) {
          expect(pairs[i].$2, greaterThanOrEqualTo(pairs[i - 1].$2 - 1e-12),
              reason: '${curve.name} newGain at sample $i');
        }
      }
    });

    test('fade-out side is monotonically non-increasing for every curve', () {
      for (final curve in curves) {
        final pairs = pairsFor(curve);
        for (int i = 1; i < pairs.length; i++) {
          expect(pairs[i].$1, lessThanOrEqualTo(pairs[i - 1].$1 + 1e-12),
              reason: '${curve.name} oldGain at sample $i');
        }
      }
    });
  });

  group('Sum-Safe Gain Pair (anti-clip ceiling)', () {
    const curves = CrossfadeCurve.values;
    const samples = 201;
    // Tiny epsilon for floating-point rounding, far below audibility.
    const eps = 1e-9;

    test('oldGain + newGain never exceeds the ceiling for any curve', () {
      for (final curve in curves) {
        final mgr = CrossfadeManager()..curve = curve;
        for (int i = 0; i < samples; i++) {
          final f = i / (samples - 1);
          final (oldGain, newGain) = mgr.evaluateSumSafeGainPair(f);
          expect(oldGain + newGain, lessThanOrEqualTo(1.0 + eps),
              reason: '${curve.name} sum at f=$f must be <= 1.0 (anti-clip)');
          expect(oldGain, inInclusiveRange(0.0, 1.0),
              reason: '${curve.name} oldGain range at f=$f');
          expect(newGain, inInclusiveRange(0.0, 1.0),
              reason: '${curve.name} newGain range at f=$f');
        }
      }
    });

    test('endpoints stay exact because raw sums equal 1.0 there', () {
      for (final curve in curves) {
        final mgr = CrossfadeManager()..curve = curve;
        final (o0, n0) = mgr.evaluateSumSafeGainPair(0.0);
        final (o1, n1) = mgr.evaluateSumSafeGainPair(1.0);
        expect(o0, closeTo(1.0, 1e-9));
        expect(n0, closeTo(0.0, 1e-9));
        expect(o1, closeTo(0.0, 1e-9));
        expect(n1, closeTo(1.0, 1e-9));
      }
    });

    test('sum-safe fade-in remains monotonic for equal-power', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      double prev = 0.0;
      for (int i = 0; i <= samples; i++) {
        final (_, newGain) = mgr.evaluateSumSafeGainPair(i / samples);
        expect(newGain, greaterThanOrEqualTo(prev - 1e-12),
            reason: 'scaled newGain at sample $i');
        prev = newGain;
      }
    });

    test('sum-safe scaling reduces the equal-power midpoint peak from '
        'sqrt(2) to the ceiling', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      final raw = mgr.evaluateGainPair(0.5);
      expect(raw.$1 + raw.$2, closeTo(math.sqrt2, 1e-9));

      final (oldGain, newGain) = mgr.evaluateSumSafeGainPair(0.5);
      expect(oldGain + newGain, closeTo(1.0, 1e-9));
      // Ceiling keeps the pair power-balanced: both sides equal at midpoint.
      expect(oldGain, closeTo(newGain, 1e-9));
    });

    test('linear curve is untouched by the ceiling (sum is already 1.0)', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.linear;
      for (int i = 0; i < samples; i++) {
        final f = i / (samples - 1);
        final raw = mgr.evaluateGainPair(f);
        final safe = mgr.evaluateSumSafeGainPair(f);
        expect(safe.$1, closeTo(raw.$1, 1e-12));
        expect(safe.$2, closeTo(raw.$2, 1e-12));
      }
    });

    test('custom ceiling below 1.0 is honoured', () {
      final mgr = CrossfadeManager()..curve = CrossfadeCurve.equalPower;
      for (int i = 0; i < samples; i++) {
        final (oldGain, newGain) =
            mgr.evaluateSumSafeGainPair(i / (samples - 1), sumCeiling: 0.8);
        expect(oldGain + newGain, lessThanOrEqualTo(0.8 + eps));
      }
    });
  });

  group('fadeVolume curve correctness', () {
    test('equal-power fade-out follows the complementary cos shape, not '
        'the mirrored 1-sin shape', () {
      fakeAsync((async) {
        final volumes = <double>[];
        when(() => mockPlayerA.setVolume(any())).thenAnswer((inv) async {
          volumes.add(inv.positionalArguments[0] as double);
        });

        crossfadeManager.curve = CrossfadeCurve.equalPower;
        final fadeId = crossfadeManager.nextFadeId();
        unawaited(crossfadeManager.fadeVolume(
          mockPlayerA,
          1.0,
          0.0,
          const Duration(milliseconds: 100),
          fadeId,
        ));

        // Drives the 10 ms fade timer deterministically: ticks land at
        // exactly 10..100 ms, so every recorded volume maps to a known
        // curve fraction (no wall-clock jitter).
        async.elapse(const Duration(milliseconds: 100));

        expect(volumes, isNotEmpty);
        expect(volumes.last, closeTo(0.0, 1e-9),
            reason: 'fade-out must end at exact 0.0');

        // Every tick must equal the true equal-power complementary shape
        // cos(f·π/2). The old mirrored bug interpolated the fade-IN shape
        // as 1 - sin(f·π/2), which dove to ~0.29 at the midpoint (~10 dB
        // below the intended cos(45°) ≈ 0.707).
        for (int i = 0; i < math.min(volumes.length - 1, 10); i++) {
          final f = (i + 1) / 10;
          final expected = math.cos(f * (math.pi / 2));
          expect(volumes[i], closeTo(expected, 1e-6),
              reason: 'tick ${i + 1} (f=$f) must follow cos, got '
                  '${volumes[i]} (mirrored would be ${1 - math.sin(f * (math.pi / 2))})');
        }

        // Monotonically non-increasing overall.
        for (int i = 1; i < volumes.length; i++) {
          expect(volumes[i], lessThanOrEqualTo(volumes[i - 1] + 1e-9),
              reason: 'fade-out must not rise at step $i');
        }
      });
    });

    test('fade-out with duration zero lands exactly on the endpoint', () async {
      await crossfadeManager.fadeVolume(
        mockPlayerA,
        0.8,
        0.0,
        Duration.zero,
        crossfadeManager.currentFadeId,
      );
      verify(() => mockPlayerA.setVolume(0.0)).called(1);
    });
  });

  group('crossfadeVolumes (dual-player)', () {
    test('stepped fallback keeps summed player volumes <= 1.0 and lands on '
        'exact endpoints', () async {
      final activeVolumes = <double>[];
      final inactiveVolumes = <double>[];
      when(() => mockPlayerA.setVolume(any())).thenAnswer((inv) async {
        activeVolumes.add(inv.positionalArguments[0] as double);
      });
      when(() => mockPlayerB.setVolume(any())).thenAnswer((inv) async {
        inactiveVolumes.add(inv.positionalArguments[0] as double);
      });

      crossfadeManager.curve = CrossfadeCurve.equalPower;
      final fadeId = crossfadeManager.nextFadeId();
      await crossfadeManager.crossfadeVolumes(
        active: mockPlayerA,
        inactive: mockPlayerB,
        fromActiveVol: 1.0,
        toInactiveVol: 1.0,
        duration: const Duration(milliseconds: 60),
        fadeId: fadeId,
      );

      expect(activeVolumes, isNotEmpty);
      // Anti-clip invariant: both players at full-scale peaks can never sum
      // above 1.0 at any tick (per-tick gains sampled by the timers).
      for (int i = 0; i < math.min(activeVolumes.length, inactiveVolumes.length); i++) {
        expect(activeVolumes[i] + inactiveVolumes[i],
            lessThanOrEqualTo(1.0 + 1e-9),
            reason: 'summed tick $i exceeds full scale');
      }
      // Exact endpoints.
      expect(activeVolumes.last, closeTo(0.0, 1e-9));
      expect(inactiveVolumes.last, closeTo(1.0, 1e-9));
    });

    test('native path arms per-sample curves on both players and steps no '
        'volumes', () async {
      final curvesArmed = <MockAudioPlayer, List<double>>{};
      when(() => mockPlayerA.dspSetGainCurve(any(),
          segmentMs: any(named: 'segmentMs'))).thenAnswer((inv) async {
        curvesArmed[mockPlayerA] =
            (inv.positionalArguments[0] as List).cast<double>();
        return true;
      });
      when(() => mockPlayerB.dspSetGainCurve(any(),
          segmentMs: any(named: 'segmentMs'))).thenAnswer((inv) async {
        curvesArmed[mockPlayerB] =
            (inv.positionalArguments[0] as List).cast<double>();
        return true;
      });

      crossfadeManager.curve = CrossfadeCurve.equalPower;
      final fadeId = crossfadeManager.nextFadeId();
      await crossfadeManager.crossfadeVolumes(
        active: mockPlayerA,
        inactive: mockPlayerB,
        fromActiveVol: 0.9,
        toInactiveVol: 0.8,
        duration: const Duration(milliseconds: 60),
        fadeId: fadeId,
      );

      final oldCurve = curvesArmed[mockPlayerA]!;
      final newCurve = curvesArmed[mockPlayerB]!;
      expect(oldCurve.first, closeTo(1.0, 1e-9));
      expect(oldCurve.last, closeTo(0.0, 1e-9));
      expect(newCurve.first, closeTo(0.0, 1e-9));
      expect(newCurve.last, closeTo(1.0, 1e-9));

      // Native ramp: base volumes are pinned, not stepped. The incoming
      // player gets exactly its target once during the fade, then the exact
      // endpoint write; the outgoing player only gets the final 0.0.
      verify(() => mockPlayerB.setVolume(0.8)).called(2);
      verify(() => mockPlayerA.setVolume(0.0)).called(1);
      verifyNever(() => mockPlayerA.setVolume(
          any(that: inInclusiveRange(0.001, 0.999))));
    });

    test('cancel clears native curves before restoring volumes', () async {
      crossfadeManager.beginCrossfade(2);
      await crossfadeManager.cancel(mockPlayerA, mockPlayerB,
          restoreVolume: 0.7);
      verify(() => mockPlayerA.dspClearGainCurve()).called(1);
      verify(() => mockPlayerB.dspClearGainCurve()).called(1);
      verify(() => mockPlayerA.setVolume(0.7)).called(1);
      verify(() => mockPlayerB.setVolume(0.7)).called(1);
    });
  });
}
