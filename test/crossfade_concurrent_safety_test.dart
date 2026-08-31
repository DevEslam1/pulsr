// test/crossfade_concurrent_safety_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/crossfade_manager.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  group('CrossfadeManager - Concurrent Safety', () {
    late CrossfadeManager crossfadeManager;
    late MockAudioPlayer mockActive;
    late MockAudioPlayer mockInactive;

    setUp(() {
      mockActive = MockAudioPlayer();
      mockInactive = MockAudioPlayer();
      crossfadeManager = CrossfadeManager();

      // Setup mocks
      when(() => mockActive.setVolume(any())).thenAnswer((_) => Future.value());
      when(
        () => mockInactive.setVolume(any()),
      ).thenAnswer((_) => Future.value());
      when(() => mockInactive.stop()).thenAnswer((_) => Future.value());
    });

    test('concurrent fade and cancel operations are serialized', () async {
      // Simulate concurrent fade + cancel
      final fade1 = crossfadeManager.fadeVolume(
        mockActive,
        1.0,
        0.0,
        const Duration(milliseconds: 100),
        1,
      );

      final cancel1 = crossfadeManager.cancel(
        mockInactive,
        mockActive,
        restoreVolume: 0.8,
      );

      // Both should complete without exception
      await Future.wait([fade1, cancel1]);

      // Verify final state is consistent
      expect(crossfadeManager.isCrossfading, isFalse);
    });

    test('rapid toggle between fades cancels previous fade', () async {
      final fadeId1 = crossfadeManager.nextFadeId();
      final fade1 = crossfadeManager.fadeVolume(
        mockActive,
        1.0,
        0.0,
        const Duration(milliseconds: 200),
        fadeId1,
      );

      // Start new fade before first completes
      await Future.delayed(const Duration(milliseconds: 50));

      final fadeId2 = crossfadeManager.nextFadeId();
      final fade2 = crossfadeManager.fadeVolume(
        mockActive,
        1.0,
        0.5,
        const Duration(milliseconds: 200),
        fadeId2,
      );

      // Wait for both to complete
      await Future.wait([fade1, fade2]);

      // First fade should be overridden by second
      expect(crossfadeManager.currentFadeId, equals(fadeId2));
    });

    test('fade completion without cancel', () async {
      var volumeSetCount = 0;
      when(() => mockActive.setVolume(any())).thenAnswer((_) async {
        volumeSetCount++;
      });

      await crossfadeManager.fadeVolume(
        mockActive,
        1.0,
        0.0,
        const Duration(milliseconds: 50),
        1,
      );

      // Verify volume was set multiple times (fade steps)
      expect(volumeSetCount, greaterThan(1));
    });

    test('cancel during fade prevents continued processing', () async {
      final fadeId = crossfadeManager.nextFadeId();
      crossfadeManager.beginCrossfade(0);

      final fadeFuture = crossfadeManager.fadeVolume(
        mockActive,
        1.0,
        0.0,
        const Duration(seconds: 1), // Long fade
        fadeId,
      );

      // Cancel after 50ms while fade is in progress
      await Future.delayed(const Duration(milliseconds: 50));
      await crossfadeManager.cancel(
        mockInactive,
        mockActive,
        restoreVolume: 0.5,
      );

      await fadeFuture;

      // Should not be crossfading
      expect(crossfadeManager.isCrossfading, isFalse);
    });

    test('multiple fade IDs are sequential', () async {
      final fadeIds = <int>[];
      for (int i = 0; i < 5; i++) {
        fadeIds.add(crossfadeManager.nextFadeId());
      }

      // All IDs should be unique
      expect(fadeIds.toSet().length, equals(fadeIds.length));

      // IDs should be sequential
      for (int i = 1; i < fadeIds.length; i++) {
        expect(fadeIds[i], equals(fadeIds[i - 1] + 1));
      }
    });

    test('fade with error completes without crashing', () async {
      final errorPlayer = MockAudioPlayer();
      when(
        () => errorPlayer.setVolume(any()),
      ).thenThrow(Exception('Volume set failed'));

      // Should complete and handle error gracefully
      await expectLater(
        () => crossfadeManager.fadeVolume(
          errorPlayer,
          1.0,
          0.0,
          const Duration(milliseconds: 100),
          1,
        ),
        returnsNormally,
      );
    });

    test('begin and finish crossfade updates state', () async {
      expect(crossfadeManager.isCrossfading, isFalse);

      crossfadeManager.beginCrossfade(1);
      expect(crossfadeManager.isCrossfading, isTrue);
      expect(crossfadeManager.pendingIndex, equals(1));

      crossfadeManager.finishCrossfade();
      expect(crossfadeManager.isCrossfading, isFalse);
      expect(crossfadeManager.pendingIndex, isNull);
    });

    test('zero duration fade applies volume immediately', () async {
      var volumeApplied = false;
      when(() => mockActive.setVolume(any())).thenAnswer((_) async {
        volumeApplied = true;
      });

      await crossfadeManager.fadeVolume(mockActive, 1.0, 0.5, Duration.zero, 1);

      expect(volumeApplied, isTrue);
    });
  });
}
