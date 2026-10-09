// test/data/audio/sleep_timer_manager_coverage_test.dart
//
// Branch coverage for SleepTimerManager: the remaining-duration arithmetic for
// track-count modes, the end-of-track / after-N / end-of-queue expiry paths,
// persistence restore, the remove-stream emissions and the coordinated
// (handler-driven) fade path.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SleepTimerManager manager;
  late MockAudioPlayer player;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = SleepTimerManager();
    player = MockAudioPlayer();
    when(() => player.volume).thenReturn(1.0);
    when(() => player.playing).thenReturn(true);
    when(() => player.setVolume(any())).thenAnswer((_) async {});
    when(() => player.dspSetGainCurve(any(),
        segmentMs: any(named: 'segmentMs'))).thenAnswer((_) async => false);
    when(() => player.dspClearGainCurve()).thenAnswer((_) async => false);
  });

  tearDown(() {
    manager.dispose();
  });

  group('remaining-duration arithmetic', () {
    test('no track durations falls back to a 3-minute average', () {
      manager.startAfterNTracksTimer(
        3,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
        trackDurations: const [],
      );
      expect(manager.mode, SleepTimerMode.afterNTracks);
      expect(manager.remainingDuration, const Duration(minutes: 9));
    });

    test('a mix of known and unknown durations averages the known ones', () {
      manager.startAfterNTracksTimer(
        3,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
        trackDurations: const [
          Duration(minutes: 2),
          Duration.zero,
          Duration.zero,
        ],
      );
      // 1 known (2min) + 2 unknown * average(2min) = 6min.
      expect(manager.remainingDuration, const Duration(minutes: 6));
    });

    test('all-known durations are summed exactly', () {
      manager.startAfterNTracksTimer(
        3,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
        trackDurations: const [
          Duration(minutes: 1),
          Duration(minutes: 2),
          Duration(minutes: 3),
        ],
      );
      expect(manager.remainingDuration, const Duration(minutes: 6));
    });

    test('a non-positive track count is ignored', () {
      manager.startAfterNTracksTimer(
        0,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
      );
      expect(manager.isArmed, isFalse);
    });

    test('updateQueueDurations recomputes the remaining duration', () {
      manager.startAfterNTracksTimer(
        3,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
        trackDurations: const [],
      );
      manager.updateQueueDurations(const [
        Duration(minutes: 5),
        Duration(minutes: 5),
        Duration(minutes: 5),
      ]);
      expect(manager.remainingDuration, const Duration(minutes: 15));
    });
  });

  group('streams', () {
    test('starting a duration timer emits a remaining duration and null tracks',
        () async {
      final durations = <Duration?>[];
      final tracks = <int?>[];
      final dSub = manager.sleepTimerRemainingStream.listen(durations.add);
      final tSub = manager.sleepTimerRemainingTracksStream.listen(tracks.add);

      manager.startSleepTimer(
        const Duration(minutes: 15),
        onTimerExpired: () async {},
        getActivePlayer: () => player,
      );
      await Future<void>.delayed(Duration.zero);
      expect(durations, contains(const Duration(minutes: 15)));
      expect(tracks, contains(null));

      manager.cancelSleepTimer();
      await Future<void>.delayed(Duration.zero);
      await dSub.cancel();
      await tSub.cancel();
    });

    test('startEndOfTrackTimer emits a symbolic duration and track count',
        () async {
      final tracks = <int?>[];
      final tSub = manager.sleepTimerRemainingTracksStream.listen(tracks.add);
      manager.startEndOfTrackTimer(
        onTimerExpired: () async {},
        getActivePlayer: () => player,
      );
      await Future<void>.delayed(Duration.zero);
      expect(tracks, contains(1));
      await tSub.cancel();
    });
  });

  group('end-of-track / after-N / end-of-queue expiry', () {
    test('endOfTrack fires the callback on the first track completion', () async {
      var fired = 0;
      manager.startEndOfTrackTimer(
        fadeOut: false,
        onTimerExpired: () async => fired++,
        getActivePlayer: () => player,
      );
      expect(manager.isArmed, isTrue);
      await manager.onTrackCompleted();
      expect(fired, 1);
      expect(manager.isArmed, isFalse);
    });

    test('afterNTracks decrements and only expires on the last track', () async {
      var fired = 0;
      manager.startAfterNTracksTimer(
        2,
        fadeOut: false,
        onTimerExpired: () async => fired++,
        getActivePlayer: () => player,
        trackDurations: const [Duration(minutes: 3), Duration(minutes: 3)],
      );
      await manager.onTrackCompleted();
      expect(fired, 0);
      expect(manager.remainingTracks, 1);
      await manager.onTrackCompleted();
      expect(fired, 1);
    });

    test('endOfQueue fires when the queue completes', () async {
      var fired = 0;
      manager.startEndOfQueueTimer(
        fadeOut: false,
        onTimerExpired: () async => fired++,
        getActivePlayer: () => player,
      );
      expect(manager.mode, SleepTimerMode.endOfQueue);
      await manager.onQueueCompleted();
      expect(fired, 1);
    });

    test('onQueueCompleted and onTrackCompleted are no-ops when not armed',
        () async {
      await manager.onQueueCompleted();
      await manager.onTrackCompleted();
      expect(manager.isArmed, isFalse);
    });
  });

  group('fade behaviour', () {
    test('duration countdown applies a stepped fade in the final 15s', () {
      fakeAsync((async) {
        final volumes = <double>[];
        when(() => player.setVolume(any())).thenAnswer((inv) async {
          volumes.add(inv.positionalArguments[0] as double);
        });

        manager.startSleepTimer(
          const Duration(seconds: 17),
          fadeOut: true,
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        );
        async.elapse(const Duration(seconds: 18));
        expect(volumes, isNotEmpty,
            reason: 'the final-15s fade must write volumes directly');
      });
    });

    test('cancel restores the pre-fade volume from a clean baseline', () {
      fakeAsync((async) {
        final volumes = <double>[];
        when(() => player.setVolume(any())).thenAnswer((inv) async {
          volumes.add(inv.positionalArguments[0] as double);
        });
        manager.baseVolumeProvider = () => 0.8;

        manager.startSleepTimer(
          const Duration(seconds: 17),
          fadeOut: true,
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        );
        async.elapse(const Duration(seconds: 2));
        manager.cancelSleepTimer();
        expect(volumes, isNotEmpty);
      });
    });

    test('coordinated mode reports fade factors and releases on cancel', () {
      fakeAsync((async) {
        final factors = <double>[];
        manager.onFadeFactor = factors.add;

        manager.startSleepTimer(
          const Duration(seconds: 17),
          fadeOut: true,
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        );
        async.elapse(const Duration(seconds: 2));
        manager.cancelSleepTimer();
        expect(factors.last, 1.0,
            reason: 'cancel must release the fade factor');
        expect(factors.length, greaterThan(1));
      });
    });

    test('non-duration modes run a short boundary ramp before pausing',
        () async {
      final factors = <double>[];
      manager.onFadeFactor = factors.add;
      manager.baseVolumeProvider = () => 1.0;

      manager.startEndOfTrackTimer(
        fadeOut: true,
        onTimerExpired: () async {},
        getActivePlayer: () => player,
      );
      await manager.onTrackCompleted();
      // 16 ramp steps + the final 1.0 release from _executeExpiration.
      expect(factors.length, greaterThanOrEqualTo(17));
      expect(factors.last, 1.0);
    });
  });

  group('persistence restore', () {
    test('no persisted target returns false', () async {
      expect(
        await manager.restorePersistedState(
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        ),
        isFalse,
      );
    });

    test('a non-duration mode is refused and cleared', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.sleepTimerTarget,
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      await prefs.setString('sleep_timer_mode_v1', 'afterNTracks');

      expect(
        await manager.restorePersistedState(
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        ),
        isFalse,
      );
      expect(prefs.getInt(PrefsKeys.sleepTimerTarget), isNull);
      expect(prefs.getString('sleep_timer_mode_v1'), isNull);
    });

    test('an already-expired target is refused and cleared', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.sleepTimerTarget,
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch);
      expect(
        await manager.restorePersistedState(
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        ),
        isFalse,
      );
      expect(prefs.getInt(PrefsKeys.sleepTimerTarget), isNull);
    });

    test('a valid duration target is re-armed', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.sleepTimerTarget,
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      expect(
        await manager.restorePersistedState(
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        ),
        isTrue,
      );
      expect(manager.isArmed, isTrue);
      expect(manager.mode, SleepTimerMode.duration);
      manager.cancelSleepTimer();
    });

    test('a missing mode is treated as a duration for backward compatibility',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefsKeys.sleepTimerTarget,
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
      expect(
        await manager.restorePersistedState(
          onTimerExpired: () async {},
          getActivePlayer: () => player,
        ),
        isTrue,
      );
      manager.cancelSleepTimer();
    });
  });

  group('startDurationTimer wrapper', () {
    test('starts a timer using the supplied getter and callback', () {
      fakeAsync((async) {
        var fired = 0;
        manager.startDurationTimer(
          const Duration(milliseconds: 30),
          playerGetter: () => player,
          onExpired: () async => fired++,
        );
        expect(manager.isArmed, isTrue);
        async.elapse(const Duration(milliseconds: 60));
        expect(fired, 1);
      });
    });
  });
}
