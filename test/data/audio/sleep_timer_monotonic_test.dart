// test/data/audio/sleep_timer_monotonic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';

class MockPlayerForTimer extends Fake implements AudioPlayer {
  bool _playing = true;
  double _volume = 1.0;

  @override
  bool get playing => _playing;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double vol) async {
    _volume = vol;
  }

  void setPlayingState(bool playing) {
    _playing = playing;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — SleepTimerManager Monotonic & Doze-Resilience Tests', () {
    late SleepTimerManager manager;
    late MockPlayerForTimer player;

    setUp(() {
      manager = SleepTimerManager();
      player = MockPlayerForTimer();
    });

    tearDown(() {
      manager.dispose();
    });

    test('Arming duration sleep timer initializes remaining duration and mode',
        () {
      bool expired = false;
      manager.startSleepTimer(
        const Duration(minutes: 15),
        fadeOut: true,
        onTimerExpired: () async => expired = true,
        getActivePlayer: () => player,
      );

      expect(manager.isArmed, isTrue);
      expect(manager.mode, equals(SleepTimerMode.duration));
      expect(manager.remainingDuration.inMinutes, equals(15));
      expect(expired, isFalse);
    });

    test('Canceling sleep timer resets state instantly', () {
      manager.startSleepTimer(
        const Duration(minutes: 30),
        onTimerExpired: () async {},
        getActivePlayer: () => player,
      );

      expect(manager.isArmed, isTrue);
      manager.cancelSleepTimer();
      expect(manager.isArmed, isFalse);
      expect(manager.remainingDuration, equals(Duration.zero));
    });

    test('End of track mode triggers on track completion event', () async {
      bool expired = false;
      manager.startEndOfTrackTimer(
        onTimerExpired: () async => expired = true,
        getActivePlayer: () => player,
      );

      expect(manager.isArmed, isTrue);
      expect(manager.mode, equals(SleepTimerMode.endOfTrack));

      await manager.onTrackCompleted();
      expect(expired, isTrue);
      expect(manager.isArmed, isFalse);
    });

    test('After N tracks mode decrements count and expires on Nth track',
        () async {
      bool expired = false;
      manager.startAfterNTracksTimer(
        3,
        onTimerExpired: () async => expired = true,
        getActivePlayer: () => player,
      );

      expect(manager.isArmed, isTrue);
      expect(manager.mode, equals(SleepTimerMode.afterNTracks));
      expect(manager.remainingTracks, equals(3));

      await manager.onTrackCompleted();
      expect(manager.remainingTracks, equals(2));
      expect(expired, isFalse);

      await manager.onTrackCompleted();
      expect(manager.remainingTracks, equals(1));
      expect(expired, isFalse);

      await manager.onTrackCompleted();
      expect(manager.remainingTracks, equals(0));
      expect(expired, isTrue);
      expect(manager.isArmed, isFalse);
    });

    test('Rapid re-arming cancels prior instance without duplicate execution',
        () async {
      int expiredCount = 0;
      manager.startSleepTimer(
        const Duration(minutes: 10),
        onTimerExpired: () async => expiredCount++,
        getActivePlayer: () => player,
      );

      manager.startSleepTimer(
        const Duration(minutes: 20),
        onTimerExpired: () async => expiredCount++,
        getActivePlayer: () => player,
      );

      expect(manager.remainingDuration.inMinutes, equals(20));
      expect(expiredCount, equals(0));
    });
  });
}
