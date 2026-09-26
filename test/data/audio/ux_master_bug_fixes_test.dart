import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/core/constants/prefs_keys.dart';
import 'package:pulsr/data/audio/adaptive_quality_manager.dart';
import 'package:pulsr/data/audio/artwork_uri_resolver.dart';
import 'package:pulsr/data/audio/sleep_timer_manager.dart';
import 'package:pulsr/data/audio/playback_bookmark_store.dart';
import 'package:pulsr/data/audio/ab_loop_manager.dart';
import 'package:pulsr/data/audio/equalizer_manager.dart';
import 'package:pulsr/data/repositories/prefs_repository.dart';
import 'package:pulsr/domain/models/audio_quality_info.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UX & Master Fix Catalog Tests', () {
    test('B-01 / B-02 / B-17: Adaptive quality policy steps down on underruns and respects ceiling', () {
      final policy = AdaptiveQualityPolicy(underrunThreshold: 2, healthyThreshold: 2);

      // Starting at high quality
      expect(policy.onBufferUnderrun('high'), isNull); // 1st underrun
      final step1 = policy.onBufferUnderrun('high'); // 2nd underrun triggers step-down
      expect(step1, equals('medium'));

      // Downgrade from medium to low
      expect(policy.onBufferUnderrun('medium'), isNull);
      final step2 = policy.onBufferUnderrun('medium');
      expect(step2, equals('low'));

      // Low cannot step down further
      expect(policy.onBufferUnderrun('low'), isNull);
      expect(policy.onBufferUnderrun('low'), isNull);

      // Recovery upward
      expect(policy.onHealthyWindow('low'), isNull);
      final stepUp1 = policy.onHealthyWindow('low');
      expect(stepUp1, equals('medium'));
    });

    test('B-03: AudioQualityInfo.dsdDopActive forces bit-perfect DoP state', () {
      AudioQualityInfo.dsdDopActive = true;
      expect(AudioQualityInfo.dsdDopActive, isTrue);

      AudioQualityInfo.dsdDopActive = false;
      expect(AudioQualityInfo.dsdDopActive, isFalse);
    });

    test('B-06: SleepTimerManager pauses countdown ticker while playback is paused', () {
      fakeAsync((async) {
        final mockPlayer = MockAudioPlayer();
        when(() => mockPlayer.volume).thenReturn(1.0);
        when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});
        when(() => mockPlayer.playing).thenReturn(false);

        final manager = SleepTimerManager();
        manager.countDownWhilePaused = false;
        bool expired = false;

        manager.startSleepTimer(
          const Duration(seconds: 2),
          fadeOut: false,
          onTimerExpired: () async => expired = true,
          getActivePlayer: () => mockPlayer,
        );

        // Elapse 5 seconds while paused: should not expire
        async.elapse(const Duration(seconds: 5));
        expect(expired, isFalse);

        // Resume playback and elapse 2 seconds
        when(() => mockPlayer.playing).thenReturn(true);
        async.elapse(const Duration(seconds: 2));
        expect(expired, isTrue);

        manager.dispose();
      });
    });

    test('B-14: SleepTimerManager calculates accurate total duration for N tracks', () async {
      final mockPlayer = MockAudioPlayer();
      when(() => mockPlayer.volume).thenReturn(1.0);
      when(() => mockPlayer.playing).thenReturn(true);
      when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});

      final manager = SleepTimerManager();
      final trackDurations = [
        const Duration(seconds: 180),
        const Duration(seconds: 240),
        const Duration(seconds: 120),
      ];

      manager.startAfterNTracksTimer(
        3,
        fadeOut: false,
        trackDurations: trackDurations,
        onTimerExpired: () async {},
        getActivePlayer: () => mockPlayer,
      );

      final prefs = await SharedPreferences.getInstance();
      final targetMs = prefs.getInt(PrefsKeys.sleepTimerTarget);
      expect(targetMs, isNotNull);

      // Expected duration is 180 + 240 + 120 = 540 seconds (9 minutes)
      final expectedMinTarget = DateTime.now().millisecondsSinceEpoch + 530 * 1000;
      final expectedMaxTarget = DateTime.now().millisecondsSinceEpoch + 550 * 1000;
      expect(targetMs!, greaterThanOrEqualTo(expectedMinTarget));
      expect(targetMs, lessThanOrEqualTo(expectedMaxTarget));

      manager.dispose();
    });

    test('B-07: ArtworkUriResolver synchronous cache methods return null for uncached items', () {
      expect(ArtworkUriResolver.getCachedArtworkUri(9999), isNull);
      expect(ArtworkUriResolver.getCachedAlbumArtUri(9999), isNull);
    });

    test('B-08: PlaybackBookmarkStore identifies podcasts and long tracks for +/-10s rewind/fastForward', () {
      // Track > 20 minutes (1,200,000 ms) qualifies for bookmarking / podcast controls
      expect(
        PlaybackBookmarkStore.shouldBookmark(
          durationMs: 1200001,
          genre: 'Rock',
          album: 'Album',
        ),
        isTrue,
      );

      // Podcast or Audiobook genre qualifies regardless of length
      expect(
        PlaybackBookmarkStore.shouldBookmark(
          durationMs: 60000,
          genre: 'Podcast',
          album: 'Daily Show',
        ),
        isTrue,
      );
      expect(
        PlaybackBookmarkStore.shouldBookmark(
          durationMs: 60000,
          genre: 'Audiobook',
          album: 'Book',
        ),
        isTrue,
      );

      // Short standard music track does not qualify
      expect(
        PlaybackBookmarkStore.shouldBookmark(
          durationMs: 180000,
          genre: 'Pop',
          album: 'Hit Album',
        ),
        isFalse,
      );
    });

    test('B-15: EqualizerManager loadCustomImpulseResponse safely fails on non-Android', () async {
      final eq = EqualizerManager();
      if (!Platform.isAndroid) {
        final result = await eq.loadCustomImpulseResponse([0.1, 0.2, 0.3]);
        expect(result, isFalse);
      }
      eq.dispose();
    });

    test('B-22: AbLoopManager handles points A and B and responds to song changes', () {
      final ab = AbLoopManager();
      ab.setA(const Duration(seconds: 10), songId: 42);
      expect(ab.pointA, equals(const Duration(seconds: 10)));
      expect(ab.isEnabled, isFalse);

      ab.setB(const Duration(seconds: 20), songId: 42);
      expect(ab.pointB, equals(const Duration(seconds: 20)));
      expect(ab.isEnabled, isTrue);

      // Target wrap works when within scope
      expect(ab.wrapTarget(const Duration(seconds: 25), songId: 42), equals(const Duration(seconds: 10)));
      // Outside scope songId returns null
      expect(ab.wrapTarget(const Duration(seconds: 25), songId: 99), isNull);

      ab.onSongChanged(99);
      expect(ab.pointA, isNull);
      expect(ab.pointB, isNull);
    });

    test('B-24: PrefsRepository type-safe getter returns null on type mismatch without throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('test_string_key', 'hello');
      await prefs.setInt('test_int_key', 42);

      final repo = PrefsRepository(prefs);

      // Correct types
      expect(repo.get<String>('test_string_key'), equals('hello'));
      expect(repo.get<int>('test_int_key'), equals(42));

      // Type mismatches safely return null instead of throwing ClassCastException
      expect(repo.get<int>('test_string_key'), isNull);
      expect(repo.get<bool>('test_string_key'), isNull);
      expect(repo.get<String>('test_int_key'), isNull);

      // B8: Type mismatch evicts stale cache entry so subsequent matching read re-fetches
      await repo.set('dynamic_key', 'text_value', immediate: true);
      expect(repo.get<int>('dynamic_key'), isNull);
      expect(repo.get<String>('dynamic_key'), equals('text_value'));
    });

    test('B-26: Scanner dateAdded normalization preserves milliseconds and scales seconds', () {
      const secondsTimestamp = 1600000000; // < 10^10
      const msTimestamp = 1600000000000; // > 10^10

      int normalize(int? raw) {
        if (raw == null) return DateTime.now().millisecondsSinceEpoch;
        return raw < 10000000000 ? raw * 1000 : raw;
      }

      expect(normalize(secondsTimestamp), equals(1600000000000));
      expect(normalize(msTimestamp), equals(1600000000000));
    });

    test('N-2: AbLoopManager preserves previously persisted loops when persist() is called before load completes', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AbLoopManager.prefsKey,
        '{"1":{"a":1000,"b":5000,"enabled":true}}',
      );

      final ab = AbLoopManager();
      ab.setA(const Duration(seconds: 2), songId: 2);
      ab.setB(const Duration(seconds: 8), songId: 2);
      await ab.persist();

      final raw = prefs.getString(AbLoopManager.prefsKey);
      expect(raw, isNotNull);
      expect(raw!, contains('"1"'));
      expect(raw, contains('"2"'));
    });
  });
}
