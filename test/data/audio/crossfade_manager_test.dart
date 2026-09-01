import 'dart:async';
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
    when(() => mockPlayerA.processingState).thenReturn(ProcessingState.ready);
    when(() => mockPlayerB.processingState).thenReturn(ProcessingState.ready);
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
}
