// test/data/audio/playback_queue_state_machine_test.dart
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:pulsr/data/audio/playback_queue_state_machine.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _testSong(int id, String title) {
  return SongsTableData(
    id: id,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    path: '/music/$title.mp3',
    durationMs: 180000,
    dateAdded: 1600000000,
    isFavorite: false,
    playCount: 0,
    isMissing: false,
    lastPositionMs: 0,
    source: SongSource.local,
    isDownloaded: false,
  );
}

void main() {
  group('PlaybackQueueStateMachine Tests', () {
    late PlaybackQueueStateMachine sm;
    final song1 = _testSong(1, 'Song One');
    final song2 = _testSong(2, 'Song Two');
    final song3 = _testSong(3, 'Song Three');
    final song4 = _testSong(4, 'Song Four');
    final song5 = _testSong(5, 'Song Five');

    setUp(() {
      sm = PlaybackQueueStateMachine(
        initialSongs: [song1, song2, song3, song4, song5],
        initialIndex: 0,
        random: math.Random(42),
      );
    });

    test('initializes with correct songs and currentSong', () {
      expect(sm.length, equals(5));
      expect(sm.currentIndex, equals(0));
      expect(sm.currentSong?.id, equals(1));
      expect(sm.isNotEmpty, isTrue);
      expect(sm.isEmpty, isFalse);
    });

    test('setCurrentIndex clamps to bounds', () {
      sm.setCurrentIndex(2);
      expect(sm.currentIndex, equals(2));
      expect(sm.currentSong?.id, equals(3));

      sm.setCurrentIndex(100);
      expect(sm.currentIndex, equals(4));

      sm.setCurrentIndex(-10);
      expect(sm.currentIndex, equals(0));
    });

    test('addSong and insertSong maintain queue and dirty state', () {
      sm.markQueueClean(0);
      expect(sm.isQueueDirty, isFalse);

      final newSong = _testSong(6, 'Song Six');
      sm.addSong(newSong);
      expect(sm.length, equals(6));
      expect(sm.songs.last.id, equals(6));
      expect(sm.isQueueDirty, isTrue);

      sm.insertSong(1, _testSong(7, 'Song Seven'));
      expect(sm.length, equals(7));
      expect(sm.songs[1].id, equals(7));
    });

    test('removeSongAt adjusts currentIndex and remaps shuffleHistory', () {
      sm.setCurrentIndex(2); // Song Three
      sm.shuffleHistory.addAll([0, 1, 3, 4]);

      final removed = sm.removeSongAt(1); // Remove Song Two
      expect(removed?.id, equals(2));
      expect(sm.length, equals(4));
      // Current index shifted down from 2 to 1
      expect(sm.currentIndex, equals(1));
      expect(sm.currentSong?.id, equals(3));
      // Shuffle history entries > 1 are decremented (3->2, 4->3), entry 1 removed
      expect(sm.shuffleHistory, equals([0, 2, 3]));
    });

    test('reorder moves track and adjusts currentIndex appropriately', () {
      sm.setCurrentIndex(2); // Song Three

      // Move Song One (index 0) to index 3
      sm.reorder(0, 3);
      // Index 2 should shift down to 1
      expect(sm.currentIndex, equals(1));
      expect(sm.currentSong?.id, equals(3));

      // Move currently playing track
      sm.reorder(1, 4);
      expect(sm.currentIndex, equals(4));
      expect(sm.currentSong?.id, equals(3));
    });

    test('clear resets all state', () {
      sm.shuffleHistory.addAll([1, 2]);
      sm.clear();
      expect(sm.isEmpty, isTrue);
      expect(sm.currentIndex, equals(0));
      expect(sm.currentSong, isNull);
      expect(sm.shuffleHistory, isEmpty);
      expect(sm.isQueueDirty, isTrue);
      expect(sm.savedQueueIndex, equals(-1));
    });

    group('getNextIndex', () {
      test('returns null for empty queue', () {
        sm.clear();
        expect(sm.getNextIndex(), isNull);
      });

      test('LoopMode.one returns currentIndex', () {
        sm.setCurrentIndex(2);
        expect(
          sm.getNextIndex(loopMode: LoopMode.one),
          equals(2),
        );
      });

      test('linear navigation returns next track and null at end', () {
        sm.setCurrentIndex(3);
        expect(sm.getNextIndex(offset: 1), equals(4));

        sm.setCurrentIndex(4);
        expect(sm.getNextIndex(offset: 1), isNull);
      });

      test('LoopMode.all wraps from end to head', () {
        sm.setCurrentIndex(4);
        expect(
          sm.getNextIndex(offset: 1, loopMode: LoopMode.all),
          equals(0),
        );
      });

      test('shuffle mode for 2-song queue alternates', () {
        final twoSongSm = PlaybackQueueStateMachine(
          initialSongs: [song1, song2],
          initialIndex: 0,
        );
        expect(
          twoSongSm.getNextIndex(shuffleModeEnabled: true),
          equals(1),
        );

        twoSongSm.setCurrentIndex(1);
        expect(
          twoSongSm.getNextIndex(shuffleModeEnabled: true),
          equals(0),
        );
      });

      test('shuffle mode records into shuffleHistory when not peek', () {
        sm.setCurrentIndex(1);
        final next = sm.getNextIndex(shuffleModeEnabled: true, peek: false);
        expect(next, isNotNull);
        expect(next, isNot(equals(1)));
        expect(sm.shuffleHistory, contains(1));
      });

      test('shuffle mode does not record history when peek is true', () {
        sm.setCurrentIndex(1);
        final historyBefore = List<int>.from(sm.shuffleHistory);
        final next = sm.getNextIndex(shuffleModeEnabled: true, peek: true);
        expect(next, isNotNull);
        expect(sm.shuffleHistory, equals(historyBefore));
      });
    });

    group('getPreviousIndex', () {
      test('returns null for empty queue', () {
        sm.clear();
        expect(sm.getPreviousIndex(), isNull);
      });

      test('returns current index if playback position > 3 seconds', () {
        sm.setCurrentIndex(2);
        expect(
          sm.getPreviousIndex(
            position: const Duration(seconds: 4),
            forcePrevious: false,
          ),
          equals(2),
        );
      });

      test('returns previous index if forcePrevious is true even when position > 3 seconds', () {
        sm.setCurrentIndex(2);
        expect(
          sm.getPreviousIndex(
            position: const Duration(seconds: 10),
            forcePrevious: true,
          ),
          equals(1),
        );
      });

      test('linear navigation returns previous track and null at head', () {
        sm.setCurrentIndex(1);
        expect(
          sm.getPreviousIndex(position: Duration.zero),
          equals(0),
        );

        sm.setCurrentIndex(0);
        expect(
          sm.getPreviousIndex(position: Duration.zero),
          isNull,
        );
      });

      test('LoopMode.all wraps from head to last track', () {
        sm.setCurrentIndex(0);
        expect(
          sm.getPreviousIndex(
            position: Duration.zero,
            loopMode: LoopMode.all,
          ),
          equals(4),
        );
      });

      test('shuffle mode pops and returns valid index from shuffleHistory', () {
        sm.setCurrentIndex(3);
        sm.shuffleHistory.addAll([0, 1, 2]);

        final prev = sm.getPreviousIndex(
          position: Duration.zero,
          shuffleModeEnabled: true,
        );
        expect(prev, equals(2));
        expect(sm.shuffleHistory, equals([0, 1]));
      });

      test('shuffle mode drains stale out-of-range history entries', () {
        sm.setCurrentIndex(0);
        sm.shuffleHistory.addAll([3, 100, 200]);

        final prev = sm.getPreviousIndex(
          position: Duration.zero,
          shuffleModeEnabled: true,
        );
        expect(prev, equals(3));
        expect(sm.shuffleHistory, isEmpty);
      });
    });

    group('hasQueueNeighbour', () {
      test('returns false for queue with 1 song', () {
        final singleSm = PlaybackQueueStateMachine(
          initialSongs: [song1],
        );
        expect(singleSm.hasQueueNeighbour(forward: true), isFalse);
        expect(singleSm.hasQueueNeighbour(forward: false), isFalse);
      });

      test('returns true in shuffle mode or LoopMode.all', () {
        sm.setCurrentIndex(4);
        expect(sm.hasQueueNeighbour(forward: true, shuffleModeEnabled: true), isTrue);
        expect(sm.hasQueueNeighbour(forward: true, loopMode: LoopMode.all), isTrue);
      });

      test('linear forward/backward neighbor checks', () {
        sm.setCurrentIndex(0);
        expect(sm.hasQueueNeighbour(forward: false), isFalse);
        expect(sm.hasQueueNeighbour(forward: true), isTrue);

        sm.setCurrentIndex(4);
        expect(sm.hasQueueNeighbour(forward: true), isFalse);
        expect(sm.hasQueueNeighbour(forward: false), isTrue);
      });
    });
  });
}
