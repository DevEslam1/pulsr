// test/data/audio/crossfade_manager_coverage_test.dart
//
// Branch coverage for the pure crossfade math (curves, BPM alignment, fade
// preview/audition, transition arbitration) plus the timer-driven fade paths
// (native curve arming, cancellation, dispose) with mocked players.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  late CrossfadeManager manager;
  late MockAudioPlayer playerA;
  late MockAudioPlayer playerB;

  setUp(() {
    manager = CrossfadeManager();
    playerA = MockAudioPlayer();
    playerB = MockAudioPlayer();
    when(() => playerA.setVolume(any())).thenAnswer((_) async {});
    when(() => playerB.setVolume(any())).thenAnswer((_) async {});
    when(() => playerA.stop()).thenAnswer((_) async {});
    when(() => playerB.stop()).thenAnswer((_) async {});
    when(() => playerA.dspSetGainCurve(any(),
        segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
    when(() => playerB.dspSetGainCurve(any(),
        segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
    when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => false);
    when(() => playerB.dspClearGainCurve()).thenAnswer((_) async => false);
  });

  tearDown(() => manager.dispose());

  group('enums and decisions', () {
    test('every curve carries a label and description', () {
      for (final curve in CrossfadeCurve.values) {
        expect(curve.label, isNotEmpty);
        expect(curve.description, isNotEmpty);
      }
    });

    test('TransitionDecision exposes isCrossfade/isGapless', () {
      const fade = TransitionDecision(
        type: TransitionType.crossfade,
        effectiveDuration: Duration(seconds: 3),
        reason: 'x',
      );
      expect(fade.isCrossfade, isTrue);
      expect(fade.isGapless, isFalse);

      const gap = TransitionDecision(
        type: TransitionType.gapless,
        effectiveDuration: Duration.zero,
        reason: 'y',
      );
      expect(gap.isGapless, isTrue);
      expect(gap.isCrossfade, isFalse);
    });
  });

  group('BPM alignment', () {
    test('null, non-finite and out-of-range BPM fall back to the base', () {
      const base = Duration(seconds: 8);
      expect(CrossfadeManager.calculateBpmAlignedDuration(base, null), base);
      expect(
          CrossfadeManager.calculateBpmAlignedDuration(base, double.nan), base);
      expect(CrossfadeManager.calculateBpmAlignedDuration(base, 10.0), base);
      expect(CrossfadeManager.calculateBpmAlignedDuration(base, 500.0), base);
    });

    test('a non-positive base duration collapses to zero', () {
      expect(
        CrossfadeManager.calculateBpmAlignedDuration(Duration.zero, 120.0),
        Duration.zero,
      );
      expect(
        CrossfadeManager.calculateBpmAlignedDuration(
            const Duration(milliseconds: -100), 120.0),
        Duration.zero,
      );
    });

    test('a valid BPM snaps to the nearest beat multiple', () {
      // 120 BPM -> 0.5s per beat; base 8s is exactly 16 beats.
      final aligned =
          CrossfadeManager.calculateBpmAlignedDuration(const Duration(seconds: 8), 120.0);
      expect(aligned, const Duration(seconds: 8));
    });

    test('getEffectiveDuration honours an optional BPM', () {
      manager.duration = const Duration(seconds: 8);
      expect(manager.getEffectiveDuration(), const Duration(seconds: 8));
      expect(manager.getEffectiveDuration(bpm: 120.0),
          const Duration(seconds: 8));
    });

    test('effectiveFadeDuration requires sync enabled, a track id and override',
        () {
      manager.duration = const Duration(seconds: 8);
      manager.bpmOverrides['t1'] = 120.0;

      expect(manager.effectiveFadeDuration(trackId: 't1'),
          const Duration(seconds: 8),
          reason: 'sync disabled');
      manager.bpmSyncEnabled = true;
      expect(manager.effectiveFadeDuration(), const Duration(seconds: 8),
          reason: 'no track id');
      expect(manager.effectiveFadeDuration(trackId: 'missing'),
          const Duration(seconds: 8),
          reason: 'no override');
      expect(manager.effectiveFadeDuration(trackId: 't1'),
          const Duration(seconds: 8));
    });
  });

  group('curve evaluation', () {
    test('evaluateCurve returns 0..1 for every curve and clamps input', () {
      for (final curve in CrossfadeCurve.values) {
        manager.curve = curve;
        expect(manager.evaluateCurve(-1.0), 0.0);
        expect(manager.evaluateCurve(2.0), 1.0);
        final mid = manager.evaluateCurve(0.5);
        expect(mid, inInclusiveRange(0.0, 1.0));
      }
    });

    test('exponential curve is exactly zero at the origin', () {
      manager.curve = CrossfadeCurve.exponential;
      expect(manager.evaluateCurve(0.0), 0.0);
      expect(manager.evaluateCurve(1.0), closeTo(1.0, 1e-9));
    });

    test('djCutDrop is quiet then rises', () {
      manager.curve = CrossfadeCurve.djCutDrop;
      expect(manager.evaluateCurve(0.1), closeTo(0.15, 1e-9));
      expect(manager.evaluateCurve(1.0), closeTo(1.0, 1e-9));
    });
  });

  group('preview and audition', () {
    test('previewFadeCurve returns steps+1 pairs and clamps the count', () {
      expect(manager.previewFadeCurve(steps: 5), hasLength(6));
      // Clamped to at least 2.
      expect(manager.previewFadeCurve(steps: 0), hasLength(3));
    });

    test('auditionCurveProgress emits every step over the duration', () {
      fakeAsync((async) {
        final events = <(double, double)>[];
        final sub = manager
            .auditionCurveProgress(duration: const Duration(seconds: 3), steps: 3)
            .listen(events.add);
        async.elapse(const Duration(seconds: 4));
        expect(events, hasLength(4));
        sub.cancel();
      });
    });
  });

  group('arbitrateTransition', () {
    test('rejects a disabled / sub-100ms crossfade', () {
      final decision = CrossfadeManager.arbitrateTransition(
        configuredCrossfade: Duration.zero,
        remainingTrackDuration: const Duration(seconds: 30),
        isSameDecoderConfig: true,
        isRepeatOne: false,
      );
      expect(decision.isGapless, isTrue);
    });

    test('rejects an under-buffered next track', () {
      final decision = CrossfadeManager.arbitrateTransition(
        configuredCrossfade: const Duration(seconds: 5),
        remainingTrackDuration: const Duration(seconds: 30),
        isSameDecoderConfig: true,
        isRepeatOne: false,
        nextTrackBufferedFraction: 0.2,
      );
      expect(decision.isGapless, isTrue);
    });

    test('rejects a track with under a second remaining', () {
      final decision = CrossfadeManager.arbitrateTransition(
        configuredCrossfade: const Duration(seconds: 5),
        remainingTrackDuration: const Duration(milliseconds: 500),
        isSameDecoderConfig: true,
        isRepeatOne: false,
      );
      expect(decision.isGapless, isTrue);
    });

    test('clamps the fade to remaining minus 500ms', () {
      final clamped = CrossfadeManager.arbitrateTransition(
        configuredCrossfade: const Duration(seconds: 10),
        remainingTrackDuration: const Duration(seconds: 4),
        isSameDecoderConfig: true,
        isRepeatOne: false,
      );
      expect(clamped.isCrossfade, isTrue);
      expect(clamped.effectiveDuration, const Duration(milliseconds: 3500));
      expect(clamped.reason, contains('equalPower'));

      // The "never below 100ms" floor inside the crossfade branch is
      // unreachable: any remaining >= 1s leaves clamp >= 100ms because
      // configured is already >= 100ms (a smaller configured returns gapless
      // above), so only the normal clamp branch can actually be observed.
      final shortRemaining = CrossfadeManager.arbitrateTransition(
        configuredCrossfade: const Duration(seconds: 10),
        remainingTrackDuration: const Duration(seconds: 1),
        isSameDecoderConfig: true,
        isRepeatOne: true,
      );
      expect(shortRemaining.effectiveDuration, const Duration(milliseconds: 500));
      expect(shortRemaining.reason, contains('linear'));
    });
  });

  group('fadeVolume', () {
    test('zero/negative duration jumps straight to the endpoint', () async {
      await manager.fadeVolume(playerA, 0.5, 0.9, Duration.zero,
          manager.nextFadeId());
      verify(() => playerA.setVolume(0.9)).called(1);
    });

    test('stepped fallback runs when the native curve is unavailable', () async {
      final volumes = <double>[];
      when(() => playerA.setVolume(any())).thenAnswer((inv) async {
        volumes.add(inv.positionalArguments[0] as double);
      });

      // A mixed fade (both endpoints audible) always uses the stepped path.
      await manager.fadeVolume(playerA, 0.4, 0.8,
          const Duration(milliseconds: 30), manager.nextFadeId());
      expect(volumes, isNotEmpty);
      expect(volumes.last, closeTo(0.8, 1e-9));
    });

    test('pure fade-out arms a native curve and clears it at the end', () {
      fakeAsync((async) {
        var armed = false;
        when(() => playerA.dspSetGainCurve(any(),
                segmentMs: any(named: 'segmentMs')))
            .thenAnswer((_) async {
          armed = true;
          return true;
        });
        when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => true);

        unawaited(manager.fadeVolume(playerA, 1.0, 0.0,
            const Duration(milliseconds: 50), manager.nextFadeId()));
        async.elapse(const Duration(milliseconds: 120));
        expect(armed, isTrue);
        verify(() => playerA.setVolume(0.0)).called(1);
      });
    });

    test('pure fade-in arms the curve then pins the target volume', () {
      fakeAsync((async) {
        when(() => playerA.dspSetGainCurve(any(),
            segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => true);
        when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => true);

        unawaited(manager.fadeVolume(playerA, 0.0, 0.8,
            const Duration(milliseconds: 40), manager.nextFadeId()));
        async.elapse(const Duration(milliseconds: 100));
        verify(() => playerA.setVolume(0.8)).called(greaterThanOrEqualTo(1));
      });
    });
  });

  group('crossfadeVolumes', () {
    test('zero duration lands both players on their endpoints', () async {
      await manager.crossfadeVolumes(
        active: playerA,
        inactive: playerB,
        fromActiveVol: 0.7,
        toInactiveVol: 0.6,
        duration: Duration.zero,
        fadeId: manager.nextFadeId(),
      );
      verify(() => playerA.setVolume(0.0)).called(1);
      verify(() => playerB.setVolume(0.6)).called(1);
    });

    test('stepped dual-player fade ends on exact endpoints', () async {
      final active = <double>[];
      final inactive = <double>[];
      when(() => playerA.setVolume(any())).thenAnswer((inv) async {
        active.add(inv.positionalArguments[0] as double);
      });
      when(() => playerB.setVolume(any())).thenAnswer((inv) async {
        inactive.add(inv.positionalArguments[0] as double);
      });

      await manager.crossfadeVolumes(
        active: playerA,
        inactive: playerB,
        fromActiveVol: 1.0,
        toInactiveVol: 1.0,
        duration: const Duration(milliseconds: 40),
        fadeId: manager.nextFadeId(),
      );
      expect(active.last, closeTo(0.0, 1e-9));
      expect(inactive.last, closeTo(1.0, 1e-9));
    });
  });

  group('cancellation and lifecycle', () {
    test('cancel with no active fade only clears curves', () async {
      await manager.cancel(playerA, playerB);
      verify(() => playerA.dspClearGainCurve()).called(1);
      verify(() => playerB.dspClearGainCurve()).called(1);
      verifyNever(() => playerA.stop());
    });

    test('cancel an active crossfade resets state and restores volume',
        () async {
      manager.beginCrossfade(4);
      manager.crossfadeGlitchCount = 0;
      await manager.cancel(playerA, playerB, restoreVolume: 0.5);
      expect(manager.isCrossfading, isFalse);
      expect(manager.pendingIndex, isNull);
      verify(() => playerA.stop()).called(1);
      verify(() => playerA.setVolume(0.5)).called(1);
      verify(() => playerB.setVolume(0.5)).called(1);
    });

    test('beginCrossfade completes a previous dangling completer', () {
      manager.beginCrossfade(1);
      manager.beginCrossfade(2);
      expect(manager.pendingIndex, 2);
      manager.finishCrossfade();
      expect(manager.isCrossfading, isFalse);
    });

    test('waitForActiveCrossfade times out without throwing', () {
      fakeAsync((async) {
        manager.beginCrossfade(1);
        var done = false;
        manager.waitForActiveCrossfade().then((_) => done = true);
        async.elapse(const Duration(seconds: 3));
        expect(done, isTrue);
      });
    });

    test('dispose clears an armed outgoing curve and pending completer', () {
      when(() => playerA.dspSetGainCurve(any(),
          segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => true);
      when(() => playerA.dspClearGainCurve()).thenAnswer((_) async => true);

      // Manually mark an outgoing armed curve through the public getter path.
      fakeAsync((async) {
        manager.beginCrossfade(1);
        unawaited(manager.crossfadeVolumes(
          active: playerA,
          inactive: playerB,
          fromActiveVol: 1.0,
          toInactiveVol: 1.0,
          duration: const Duration(milliseconds: 200),
          fadeId: manager.currentFadeId,
        ));
        async.elapse(const Duration(milliseconds: 20));
        manager.dispose();
        verify(() => playerA.dspClearGainCurve()).called(greaterThanOrEqualTo(1));
        async.elapse(const Duration(milliseconds: 300));
      });
    });

    test('protect serialises concurrent actions', () async {
      final order = <int>[];
      final first = manager.protect(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(1);
      });
      final second = manager.protect(() async {
        order.add(2);
      });
      await Future.wait([first, second]);
      expect(order, [1, 2]);
    });
  });
}
