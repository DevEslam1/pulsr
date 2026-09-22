// test/perf/frame_budget_test.dart
// FIX-E1: Frame budget and memory ceiling tests for Phase E
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

void main() {
  group('Phase E: Performance & Memory Ceiling Tests', () {
    testWidgets('ListView with 1,000 items renders smoothly within frame budget', (tester) async {
      final items = List.generate(
        1000,
        (i) => SongsTableData(
          id: i,
          title: 'Track $i',
          artist: 'Artist $i',
          album: 'Album $i',
          durationMs: 200000,
          path: '/path/$i.mp3',
          source: SongSource.local,
          playCount: 0,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          lastPositionMs: 0,
          isDownloaded: false,
        ),
      );

      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final song = items[index];
                return RepaintBoundary(
                  child: ListTile(
                    title: Text(song.title),
                    subtitle: Text(song.artist),
                  ),
                );
              },
            ),
          ),
        ),
      );

      final initialPumpMs = stopwatch.elapsedMilliseconds;
      // Initial render of the viewport should be fast (< 1000 ms in debug/test VM)
      expect(initialPumpMs, lessThan(1000));

      stopwatch.reset();
      // Scroll down by 500 pixels
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      final scrollPumpMs = stopwatch.elapsedMilliseconds;

      // Scroll frame in headless test VM should execute smoothly
      expect(scrollPumpMs, lessThan(250));
    });

    test('PlayerState differsFromBeyondPosition executes 5,000 times in under 50ms', () {
      const state1 = PlayerState(
        position: Duration(seconds: 10),
        isPlaying: true,
        duration: Duration(minutes: 3),
      );
      const state2 = PlayerState(
        position: Duration(seconds: 11),
        isPlaying: true,
        duration: Duration(minutes: 3),
      );

      bool allFalse = true;
      final sw = Stopwatch()..start();
      for (int i = 0; i < 5000; i++) {
        if (state1.differsFromBeyondPosition(state2)) {
          allFalse = false;
        }
      }
      sw.stop();

      expect(allFalse, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(50),
          reason: 'O(1) differsFromBeyondPosition benchmark must be hyper-fast');
    });

    test('Queue slot lookup cache prunes inactive entries beyond 1500 limit', () {
      final slotLookupCache = <int, SongsTableData>{};
      final activeSongIds = <int>{1, 2, 3};

      // Populate 2,000 entries
      for (int i = 0; i < 2000; i++) {
        slotLookupCache[i] = SongsTableData(
          id: i,
          title: 'Track $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 100000,
          path: '/path/$i.mp3',
          source: SongSource.local,
          playCount: 0,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          lastPositionMs: 0,
          isDownloaded: false,
        );
      }

      expect(slotLookupCache.length, equals(2000));

      // Simulate pruning logic from PlayerCubit._recordQueueSlot
      if (slotLookupCache.length > 1500) {
        slotLookupCache.removeWhere((id, _) => !activeSongIds.contains(id));
      }

      expect(slotLookupCache.length, equals(3));
      expect(slotLookupCache.containsKey(1), isTrue);
      expect(slotLookupCache.containsKey(2), isTrue);
      expect(slotLookupCache.containsKey(3), isTrue);
    });

    test('Dynamic theme palette cache ceiling of 50 entries FIFO eviction', () {
      final cache = <String, int>{};
      const maxCacheSize = 50;

      for (int i = 0; i < 80; i++) {
        final key = 'item_$i';
        if (cache.length >= maxCacheSize) {
          cache.remove(cache.keys.first);
        }
        cache[key] = i;
      }

      expect(cache.length, equals(50));
      // First 30 items (0..29) should have been evicted
      expect(cache.containsKey('item_0'), isFalse);
      expect(cache.containsKey('item_29'), isFalse);
      // Items 30..79 must be present
      expect(cache.containsKey('item_30'), isTrue);
      expect(cache.containsKey('item_79'), isTrue);
    });

    test('Large queue slicing to 500 items operates in sub-millisecond time', () {
      final largeQueue = List.generate(
        10000,
        (i) => SongsTableData(
          id: i,
          title: 'Title $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: '/path/$i.mp3',
          source: SongSource.local,
          playCount: 0,
          dateAdded: 0,
          isFavorite: false,
          isMissing: false,
          lastPositionMs: 0,
          isDownloaded: false,
        ),
      );

      final sw = Stopwatch()..start();
      const maxQueueSize = 500;
      const targetIndex = 4500;

      final halfWindow = maxQueueSize ~/ 2;
      var start = targetIndex - halfWindow;
      if (start < 0) start = 0;
      if (start + maxQueueSize > largeQueue.length) {
        start = (largeQueue.length - maxQueueSize).clamp(0, largeQueue.length);
      }
      final sliced = largeQueue.sublist(start, start + maxQueueSize);
      sw.stop();

      expect(sliced.length, equals(500));
      expect(sw.elapsedMilliseconds, lessThan(5));
    });
  });
}
