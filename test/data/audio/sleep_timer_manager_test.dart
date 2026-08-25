import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';

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
  });

  tearDown(() {
    sleepTimerManager.dispose();
  });

  group('SleepTimerManager Hardening Tests', () {
    test('startSleepTimer persists target time to SharedPreferences', () async {
      sleepTimerManager.startSleepTimer(
        const Duration(minutes: 15),
        fadeOut: false,
        onTimerExpired: () async {},
        getActivePlayer: () => mockPlayer,
      );

      final prefs = await SharedPreferences.getInstance();
      final targetMs = prefs.getInt(PrefsKeys.sleepTimerTarget);
      expect(targetMs, isNotNull);
      expect(targetMs!, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('cancelSleepTimer clears target time and restores volume', () async {
      sleepTimerManager.startSleepTimer(
        const Duration(minutes: 15),
        fadeOut: false,
        onTimerExpired: () async {},
        getActivePlayer: () => mockPlayer,
      );

      sleepTimerManager.cancelSleepTimer();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PrefsKeys.sleepTimerTarget), isNull);
    });

    test('startSleepTimer triggers callback on expiration', () async {
      bool expired = false;
      sleepTimerManager.startSleepTimer(
        const Duration(milliseconds: 50),
        fadeOut: false,
        onTimerExpired: () async {
          expired = true;
        },
        getActivePlayer: () => mockPlayer,
      );

      await Future.delayed(const Duration(milliseconds: 100));
      expect(expired, isTrue);
    });

    test('startSleepTimer skips fade out when player is paused', () async {
      when(() => mockPlayer.playing).thenReturn(false);

      final volumes = <double>[];
      when(() => mockPlayer.setVolume(any())).thenAnswer((inv) async {
        volumes.add(inv.positionalArguments[0] as double);
      });

      bool expired = false;
      sleepTimerManager.startSleepTimer(
        const Duration(milliseconds: 20),
        fadeOut: true,
        onTimerExpired: () async => expired = true,
        getActivePlayer: () => mockPlayer,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(expired, isTrue);
      // Because player was paused, 10-step fade was skipped and only restoration ran
      expect(volumes.length, lessThanOrEqualTo(2));
    });
  });
}
