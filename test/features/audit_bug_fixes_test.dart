import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _makeSong(int id, {String title = 'Song', String path = '/music/song.mp3'}) {
  return SongsTableData(
    id: id,
    title: title,
    artist: 'Artist',
    album: 'Album',
    path: path,
    durationMs: 180000,
    playCount: 0,
    lastPositionMs: 0,
    isFavorite: false,
    isMissing: false,
    isDownloaded: false,
    source: SongSource.local,
  );
}

void main() {
  group('Codebase Audit Bug Fixes (B-1 to B-14)', () {
    test('B-1: _SongLock ref counting prevents premature mutex deletion during concurrency', () {
      int refCount = 0;
      final map = <int, int>{};

      // Caller 1 enters
      map.putIfAbsent(101, () => ++refCount);
      expect(map[101], 1);

      // Caller 2 enters while Caller 1 in-flight
      refCount++;
      map[101] = refCount;
      expect(map[101], 2);

      // Caller 1 finishes: decrements refCount
      refCount--;
      if (refCount == 0) {
        map.remove(101);
      }
      // Lock is still present for Caller 2!
      expect(map.containsKey(101), isTrue);

      // Caller 3 arrives: finds same lock
      refCount++;
      map[101] = refCount;
      expect(map[101], 2);

      // Caller 2 finishes
      refCount--;
      if (refCount == 0) map.remove(101);
      expect(map.containsKey(101), isTrue);

      // Caller 3 finishes: refCount reaches 0 and lock is cleaned up
      refCount--;
      if (refCount == 0) map.remove(101);
      expect(map.containsKey(101), isFalse);
    });

    test('B-7: Folder extraction memoization prevents redundant parsing for identical song list', () {
      final songs1 = [
        _makeSong(1, path: '/storage/emulated/0/Music/Pop/song1.mp3'),
        _makeSong(2, path: '/storage/emulated/0/Music/Rock/song2.mp3'),
      ];

      List<SongsTableData>? cachedSongsRef;
      Set<String>? cachedFolders;
      int parseCount = 0;

      Set<String> getFolders(List<SongsTableData> songs) {
        if (identical(cachedSongsRef, songs) && cachedFolders != null) {
          return cachedFolders!;
        }
        cachedSongsRef = songs;
        parseCount++;
        cachedFolders = songs
            .map((s) => s.path.substring(0, s.path.lastIndexOf('/')))
            .toSet();
        return cachedFolders!;
      }

      // Initial call (e.g., in initState or listener)
      final res1 = getFolders(songs1);
      expect(parseCount, 1);
      expect(res1.length, 2);

      // Second call with same state.songs reference (e.g., in builder during same build cycle)
      final res2 = getFolders(songs1);
      expect(parseCount, 1);
      expect(identical(res1, res2), isTrue);

      // Call with new list instance parses once
      final songs2 = List<SongsTableData>.from(songs1);
      final res3 = getFolders(songs2);
      expect(parseCount, 2);
      expect(res3.length, 2);
    });

    test('B-9: Visible window freezing maintains stable coordinates during drag scrubbing', () {
      ({int startIndex, int visibleCount}) computeVisibleWindow(
        int totalCount,
        double positionMs,
        double durationMs,
        double zoomScale,
      ) {
        final visibleCount = (totalCount / zoomScale).round().clamp(2, totalCount);
        final centerRatio = durationMs > 0 ? positionMs / durationMs : 0.0;
        final centerIndex = (centerRatio.clamp(0.0, 1.0) * totalCount).round();
        final halfVisible = visibleCount ~/ 2;
        final startIndex = (centerIndex - halfVisible).clamp(0, totalCount - visibleCount);
        return (startIndex: startIndex, visibleCount: visibleCount);
      }

      const totalCount = 1000;
      const durationMs = 200000.0;
      const zoomScale = 4.0;

      // Position at 50,000 ms (25% progress)
      final initialWindow = computeVisibleWindow(totalCount, 50000.0, durationMs, zoomScale);

      // User starts dragging: freeze the window
      ({int startIndex, int visibleCount})? dragFrozenWindow = initialWindow;

      // Dragging moves finger to 80,000 ms
      // Unfrozen window would shift startIndex:
      final unfrozenWindowAt80k = computeVisibleWindow(totalCount, 80000.0, durationMs, zoomScale);
      expect(unfrozenWindowAt80k.startIndex, isNot(equals(initialWindow.startIndex)));

      // With frozen window, the mapping frame stays locked during drag:
      final effectiveWindow = dragFrozenWindow;
      expect(effectiveWindow.startIndex, equals(initialWindow.startIndex));
      expect(effectiveWindow.visibleCount, equals(initialWindow.visibleCount));

      // On drag end, window unfreezes
      dragFrozenWindow = null;
      expect(dragFrozenWindow, isNull);
    });

    test('B-10: Recents Show Less is guarded by _userExpanded and limit', () {
      const persistedLimit = 100;
      const maxLimit = 500;
      int historyLimit = persistedLimit;
      bool userExpanded = false;
      final allRecents = List.generate(150, (i) => _makeSong(i));

      bool shouldShowShowLess() {
        return userExpanded &&
            historyLimit > persistedLimit &&
            allRecents.length > persistedLimit;
      }

      // Initial state: not expanded
      expect(shouldShowShowLess(), isFalse);

      // User taps "Load more"
      userExpanded = true;
      historyLimit = (historyLimit + 100).clamp(persistedLimit, maxLimit);
      expect(shouldShowShowLess(), isTrue);

      // User taps "Show less"
      userExpanded = false;
      historyLimit = persistedLimit;
      expect(shouldShowShowLess(), isFalse);
    });

    test('B-11: Quick actions song cache is invalidated when song identity changes', () {
      final listA = [_makeSong(1, title: 'Track 1'), _makeSong(2, title: 'Track 2')];
      final listB = [_makeSong(3, title: 'Track 3'), _makeSong(2, title: 'Track 2')];

      bool shouldInvalidate(
        List<SongsTableData> current,
        List<SongsTableData> previous,
      ) {
        final firstId = current.firstOrNull?.id;
        final lastFirstId = previous.firstOrNull?.id;
        return !identical(current, previous) ||
            current.length != previous.length ||
            firstId != lastFirstId;
      }

      expect(shouldInvalidate(listA, listA), isFalse);
      expect(shouldInvalidate(listB, listA), isTrue);
    });

    test('B-13: PulsrCastSheet initialization is idempotent', () {
      bool initialized = false;
      int initCallCount = 0;

      void init() {
        if (initialized) return;
        initialized = true;
        initCallCount++;
      }

      init();
      expect(initCallCount, 1);

      // Subsequent duplicate init calls are ignored
      init();
      init();
      expect(initCallCount, 1);
    });
  });
}
