import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/failures.dart' hide Result;
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/utils/cache_manager.dart';
import 'package:pulsr/core/utils/leak_detector.dart';
import 'package:pulsr/core/utils/result.dart';
import 'package:pulsr/core/utils/timer_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/repositories/prefs_repository.dart';
import 'package:pulsr/features/player/cubit/player_cubit.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/presentation/themes/theme_registry.dart';
import 'package:pulsr/features/player/presentation/themes/player_theme.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTimerHost with TimerManager {}
class MockPlayerCubit extends Mock implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('I-03 Result<T>', () {
    test('Result.success holds data and reports flags correctly', () {
      const res = Result<int>.success(42);
      expect(res.isSuccess, isTrue);
      expect(res.isFailure, isFalse);
      expect(res.isLoading, isFalse);
      expect(res.dataOrNull, 42);
      expect(res.failureOrNull, isNull);

      final val = res.when(
        success: (d) => 'ok: $d',
        failure: (f, m) => 'fail',
        loading: () => 'loading',
      );
      expect(val, 'ok: 42');

      final folded = res.fold((f) => -1, (d) => d * 2);
      expect(folded, 84);
    });

    test('Result.failure holds failure and reports flags correctly', () {
      const res =
          Result<int>.failure(DatabaseFailure('timeout'), 'Network error');
      expect(res.isSuccess, isFalse);
      expect(res.isFailure, isTrue);
      expect(res.isLoading, isFalse);
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<DatabaseFailure>());

      final val = res.when(
        success: (d) => 'ok',
        failure: (f, m) => '$m: ${f.message}',
        loading: () => 'loading',
      );
      expect(val, 'Network error: timeout');

      final folded = res.fold((f) => -1, (d) => d * 2);
      expect(folded, -1);
    });

    test('Result.loading reports isLoading true', () {
      const res = Result<int>.loading();
      expect(res.isSuccess, isFalse);
      expect(res.isFailure, isFalse);
      expect(res.isLoading, isTrue);
      expect(res.dataOrNull, isNull);

      final val = res.when(
        success: (d) => 'ok',
        failure: (f, m) => 'fail',
        loading: () => 'loading',
      );
      expect(val, 'loading');
    });
  });

  group('I-05 TimerManager', () {
    test('schedules and cancels timers cleanly', () async {
      final host = _TestTimerHost();
      var triggered = false;

      final timer = host.scheduleTimer(const Duration(milliseconds: 50), () {
        triggered = true;
      });

      expect(host.activeTimerCount, 1);
      host.cancelTimer(timer);
      expect(host.activeTimerCount, 0);

      await Future.delayed(const Duration(milliseconds: 70));
      expect(triggered, isFalse);

      host.disposeTimers();
      expect(host.activeTimerCount, 0);
    });
  });

  group('I-06 CacheManager', () {
    test('evicts least recently used on max capacity and respects TTL',
        () async {
      final cache = CacheManager<String, int>(
          maxSize: 3, defaultTtl: const Duration(milliseconds: 100));

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(cache.length, 3);

      // Access 'a' to mark it recently used
      expect(cache.get('a'), 1);

      // Insert 'd', which should evict oldest unaccessed 'b'
      cache.put('d', 4);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('d'), isTrue);

      // Wait for TTL expiration
      await Future.delayed(const Duration(milliseconds: 120));
      expect(cache.get('a'), isNull);
      expect(cache.length, 0);
    });
  });

  group('I-07 PrefsRepository', () {
    test('reads and writes with in-memory caching and immediate flush',
        () async {
      SharedPreferences.setMockInitialValues({'init_key': 'initial'});
      final repo = await PrefsRepository.create();

      expect(repo.getString('init_key'), 'initial');

      await repo.setString('new_key', 'value', immediate: true);
      expect(repo.getString('new_key'), 'value');

      await repo.setBool('flag', true, immediate: true);
      expect(repo.getBool('flag'), isTrue);

      await repo.remove('flag');
      expect(repo.getBool('flag'), isNull);
    });
  });

  group('I-09 ThemeRegistry', () {
    test('builds widgets for all 8 PlayerThemeModes', () {
      for (final mode in PlayerThemeMode.values) {
        ThemeRegistry.register(mode, (props) => SizedBox(key: ValueKey(mode)));
      }

      final mockCubit = MockPlayerCubit();
      final dummyProps = PlayerThemeProps(
        state: const PlayerState(),
        cubit: mockCubit,
        activeColor: Colors.blue,
        bgColor: Colors.black,
      );

      for (final mode in PlayerThemeMode.values) {
        final widget = ThemeRegistry.build(mode, dummyProps);
        expect(widget, isNotNull);
        expect(widget, isA<SizedBox>());
      }
    });
  });

  group('I-12 LeakDetector', () {
    test('tracks and untracks instances correctly', () {
      final initialCount = LeakDetector.trackedCount;
      final dummyObj = Object();

      LeakDetector.track(dummyObj);
      expect(LeakDetector.trackedCount, initialCount + 1);

      LeakDetector.untrack(dummyObj);
      expect(LeakDetector.trackedCount, initialCount);
    });
  });

  group('YtmErrorClassifier', () {
    test('classifies rate limit and bot challenge correctly', () {
      final info429 =
          YtmErrorClassifier.classify('HTTP status 429 too many requests');
      expect(info429.signal, YtmBlockSignal.rateLimited);

      final infoBot =
          YtmErrorClassifier.classify('Sign in to confirm you are not a bot');
      expect(infoBot.signal, YtmBlockSignal.botChallenge);
    });
  });
}
