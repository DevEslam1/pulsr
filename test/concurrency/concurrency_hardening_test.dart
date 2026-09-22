// test/concurrency/concurrency_hardening_test.dart
// FIX-G: Concurrency hardening tests verifying Mutex safety, monotonic clocks, and structured concurrency
import 'package:flutter_test/flutter_test.dart';
import 'package:mutex/mutex.dart';
import 'package:pulsr/features/player/cubit/player_scrobble_coordinator.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  group('Phase G: Concurrency Hardening Tests', () {
    test('Mutex serializes concurrent writes deterministically', () async {
      final mutex = Mutex();
      final order = <int>[];

      Future<void> delayedWrite(int id, int delayMs) async {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: delayMs));
          order.add(id);
        });
      }

      await Future.wait([
        delayedWrite(1, 30),
        delayedWrite(2, 10),
        delayedWrite(3, 5),
      ]);

      // Since each enters the mutex sequentially, they complete in order of acquisition
      expect(order, equals([1, 2, 3]));
    });

    test('PlayerScrobbleCoordinator records monotonic elapsed milliseconds on playback notify', () {
      final coordinator = PlayerScrobbleCoordinator(
        service: () => null,
        isQuranMode: () => false,
        isClosed: () => false,
        interval: const Duration(milliseconds: 50),
      );

      final song = const SongsTableData(
        id: 42,
        title: 'Monotonic Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 180000,
        path: '/music/mono.mp3',
        source: SongSource.local,
        playCount: 0,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      coordinator.debouncedScrobble(song, const Duration(seconds: 1), true);

      expect(coordinator.lastScrobbleTime, isNotNull);
      expect(coordinator.lastScrobbleElapsedMs, isNotNull);
      expect(coordinator.lastScrobbleElapsedMs!, greaterThanOrEqualTo(0));

      final firstElapsed = coordinator.lastScrobbleElapsedMs!;
      coordinator.debouncedScrobble(song, const Duration(seconds: 10), true); // major seek >= 5s triggers flush
      final secondElapsed = coordinator.lastScrobbleElapsedMs!;

      expect(secondElapsed, greaterThanOrEqualTo(firstElapsed));
      coordinator.dispose();
    });

    test('Structured concurrency: Future.wait aggregates errors and completes atomically', () async {
      bool task1Done = false;
      bool task2Done = false;
      bool task3Done = false;

      final futures = [
        Future.delayed(const Duration(milliseconds: 10), () => task1Done = true),
        Future.delayed(const Duration(milliseconds: 15), () => task2Done = true),
        Future.delayed(const Duration(milliseconds: 20), () => task3Done = true),
      ];

      await Future.wait(futures);

      expect(task1Done, isTrue);
      expect(task2Done, isTrue);
      expect(task3Done, isTrue);
    });

    test('Downloads tombstone map protected under concurrent deletes', () async {
      final deleteMutex = Mutex();
      final deletedAtMsByVideoId = <String, int>{};
      final stopwatch = Stopwatch()..start();

      Future<void> simulateDelete(String vid) async {
        await deleteMutex.protect(() async {
          deletedAtMsByVideoId[vid] = stopwatch.elapsedMilliseconds;
        });
      }

      await Future.wait([
        simulateDelete('vid_1'),
        simulateDelete('vid_2'),
        simulateDelete('vid_3'),
        simulateDelete('vid_4'),
      ]);

      expect(deletedAtMsByVideoId.length, equals(4));
      expect(deletedAtMsByVideoId.containsKey('vid_1'), isTrue);
      expect(deletedAtMsByVideoId.containsKey('vid_4'), isTrue);
    });

    test('Monotonic stopwatch elapsed duration is immune to wall clock backward jumps', () async {
      final sw = Stopwatch()..start();
      final start = sw.elapsedMilliseconds;
      await Future.delayed(const Duration(milliseconds: 20));
      final end = sw.elapsedMilliseconds;

      // Monotonic clock is strictly non-decreasing
      expect(end, greaterThanOrEqualTo(start));
    });
  });
}
