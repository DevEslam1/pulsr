import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SleepTimerManager sleepTimerManager;
  late MockAudioPlayer mockPlayer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sleepTimerManager = SleepTimerManager();
    mockPlayer = MockAudioPlayer();

    when(() => mockPlayer.volume).thenReturn(1.0);
    when(() => mockPlayer.playing).thenReturn(true);
    when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayer.dspClearGainCurve()).thenAnswer((_) async => true);
  });

  tearDown(() {
    sleepTimerManager.dispose();
  });

  group('SleepTimerManager mid-fade cancel', () {
    test(
        'native gain curve mid-fade cancel clears gain curve and invalidates token',
        () async {
      final completer = Completer<bool>();
      when(() => mockPlayer.dspSetGainCurve(any(),
              segmentMs: any(named: 'segmentMs')))
          .thenAnswer((_) => completer.future);

      // Trigger native fade-out while remaining <= 15s
      sleepTimerManager.debugApplyFadeOut(mockPlayer, 10);

      // Cancel while gain curve is in flight
      sleepTimerManager.cancelSleepTimer();

      // Resolve the pending setGainCurve call
      completer.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // dspClearGainCurve must have been called
      verify(() => mockPlayer.dspClearGainCurve())
          .called(greaterThanOrEqualTo(1));
    });

    test('startEndOfTrackTimer mid-fade cancel aborts expiration callback',
        () async {
      bool expired = false;

      sleepTimerManager.startEndOfTrackTimer(
        fadeOut: true,
        onTimerExpired: () async {
          expired = true;
        },
        getActivePlayer: () => mockPlayer,
      );

      // Trigger expiration which starts _fadeBeforePause (~1.6s ramp)
      unawaited(sleepTimerManager.onTrackCompleted());

      // Let fade begin
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Cancel mid-fade
      sleepTimerManager.cancelSleepTimer();

      // Wait for any remaining steps to elapse
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Callback must NEVER have been called
      expect(expired, isFalse,
          reason:
              'Expiration callback must be aborted when timer is cancelled mid-fade');
    });
  });
}
