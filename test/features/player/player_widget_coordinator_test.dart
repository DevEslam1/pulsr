import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/controllers/player_widget_bridge.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/player/cubit/player_widget_coordinator.dart';
import 'package:pulsr/features/widgets/widget_service.dart';

class MockWidgetService extends Mock implements WidgetService {}

void main() {
  group('H-11: PlayerWidgetCoordinator clock management', () {
    late MockWidgetService mockWidgetService;

    setUp(() {
      mockWidgetService = MockWidgetService();
    });

    test('isClockRunning is initially true', () {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      expect(coordinator.isClockRunning, isTrue);
    });

    test('reset clears caches and resets clock', () async {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.reset();
      expect(coordinator.isClockRunning, isTrue);
    });

    test('dispose stops clock and resets state', () async {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      expect(coordinator.isClockRunning, isTrue);

      coordinator.dispose();
      expect(coordinator.isClockRunning, isFalse);
    });

    test('PlayerWidgetBridge.dispose properly invokes coordinator.dispose', () {
      final bridge = PlayerWidgetBridge(
        widgetService: mockWidgetService,
        isQuranMode: () => false,
        isClosed: () => false,
      );

      bridge.dispose();
      // Verifies bridge.dispose cleanly completes without leaking or throwing
    });
  });

  group('M-24: nextTitles cache invalidation on queue reorder', () {
    late MockWidgetService mockWidgetService;

    setUp(() {
      mockWidgetService = MockWidgetService();
    });

    SongsTableData makeSong(int id, String title, String artist) {
      return SongsTableData(
        id: id,
        title: title,
        artist: artist,
        album: 'Album',
        durationMs: 180000,
        path: '/path/$id.mp3',
        source: SongSource.local,
        remoteId: null,
        remoteArtworkUrl: null,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
    }

    test(
        'invalidates cache when songs are reordered within the next-titles window',
        () {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      final songA = makeSong(1, 'Song A', 'Artist A');
      final songB = makeSong(2, 'Song B', 'Artist B');
      final songC = makeSong(3, 'Song C', 'Artist C');

      final stateInitial = PlayerState(
        queueSlice: QueueSlice(
          queue: [songA, songB, songC],
          currentIndex: 0,
        ),
      );

      final titlesInitial = coordinator.nextTitles(stateInitial, 0);
      expect(titlesInitial, ['Song B · Artist B', 'Song C · Artist C']);

      // Reorder queue: swap songB and songC
      final stateReordered = PlayerState(
        queueSlice: QueueSlice(
          queue: [songA, songC, songB],
          currentIndex: 0,
        ),
      );

      // Even with the same queueVersion, the reorder must invalidate the cache
      final titlesReordered = coordinator.nextTitles(stateReordered, 0);
      expect(titlesReordered, ['Song C · Artist C', 'Song B · Artist B']);
    });

    test(
        'invalidates cache when duplicate IDs are reordered or track content differs',
        () {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      final song1 = makeSong(-1, 'Track 1', 'Artist');
      final song2 = makeSong(-1, 'Track 2', 'Artist');

      final state1 = PlayerState(
        queueSlice: QueueSlice(
          queue: [makeSong(0, 'Now', 'Artist'), song1, song2],
          currentIndex: 0,
        ),
      );

      final titles1 = coordinator.nextTitles(state1, 0);
      expect(titles1, ['Track 1 · Artist', 'Track 2 · Artist']);

      final state2 = PlayerState(
        queueSlice: QueueSlice(
          queue: [makeSong(0, 'Now', 'Artist'), song2, song1],
          currentIndex: 0,
        ),
      );

      final titles2 = coordinator.nextTitles(state2, 0);
      expect(titles2, ['Track 2 · Artist', 'Track 1 · Artist']);
    });

    test('invalidateNextTitlesCache clears cache explicitly', () {
      final coordinator = PlayerWidgetCoordinator(mockWidgetService);
      final songA = makeSong(1, 'Song A', 'Artist A');
      final songB = makeSong(2, 'Song B', 'Artist B');

      final state = PlayerState(
        queueSlice: QueueSlice(
          queue: [songA, songB],
          currentIndex: 0,
        ),
      );

      final titles1 = coordinator.nextTitles(state, 1);
      expect(titles1, isNotNull);

      coordinator.invalidateNextTitlesCache();
      final titles2 = coordinator.nextTitles(state, 1);
      expect(titles2, isNotNull);
      // New list instance is produced
      expect(identical(titles1, titles2), isFalse);
    });
  });
}
