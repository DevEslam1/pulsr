// test/integration/playback_integration_test.dart
// FIX-A3: Playback integration tests verifying state transitions, managers, and queue navigation
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/leak_detector.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/player/cubit/managers/player_lyrics_manager.dart';
import 'package:pulsr/features/player/cubit/managers/player_quran_manager.dart';
import 'package:pulsr/features/player/cubit/managers/player_sponsorblock_manager.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';

void main() {
  group('Playback Integration Tests (A3)', () {
    late SongsTableData testSong1;
    late SongsTableData testSong2;
    late SongsTableData testSong3;

    setUp(() {
      testSong1 = const SongsTableData(
        id: 101,
        title: 'Track One',
        artist: 'Artist One',
        album: 'Album One',
        durationMs: 240000,
        path: '/music/track1.mp3',
        source: SongSource.local,
        playCount: 1,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      testSong2 = const SongsTableData(
        id: 102,
        title: 'Track Two',
        artist: 'Artist Two',
        album: 'Album Two',
        durationMs: 180000,
        path: '/music/track2.flac',
        source: SongSource.local,
        playCount: 3,
        dateAdded: 0,
        isFavorite: true,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      testSong3 = const SongsTableData(
        id: 103,
        title: 'Track Three',
        artist: 'Artist Three',
        album: 'Album Three',
        durationMs: 300000,
        path: 'ytmusic://dQw4w9WgXcQ',
        source: SongSource.youtube,
        remoteId: 'dQw4w9WgXcQ',
        playCount: 0,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );
    });

    test('Queue progression and neighbour calculations reflect playback position', () {
      final queue = [testSong1, testSong2, testSong3];

      var state = PlayerState(
        playback: PlaybackSlice(
          currentSong: testSong1,
          isPlaying: true,
        ),
        queueSlice: QueueSlice(
          queue: queue,
          currentIndex: 0,
        ),
      );

      expect(state.hasPreviousNeighbour, isFalse);
      expect(state.hasNextNeighbour, isTrue);

      // Advance to middle
      state = state.copyWith(
        playback: state.playback.copyWith(currentSong: testSong2),
        queueSlice: state.queueSlice.copyWith(currentIndex: 1),
      );

      expect(state.hasPreviousNeighbour, isTrue);
      expect(state.hasNextNeighbour, isTrue);

      // Advance to end
      state = state.copyWith(
        playback: state.playback.copyWith(currentSong: testSong3),
        queueSlice: state.queueSlice.copyWith(currentIndex: 2),
      );

      expect(state.hasPreviousNeighbour, isTrue);
      expect(state.hasNextNeighbour, isFalse);

      // Repeat mode 'all' enables next neighbour even at end
      state = state.copyWith(
        playback: state.playback.copyWith(repeatMode: PlayerRepeatMode.all),
      );
      expect(state.hasNextNeighbour, isTrue);
    });

    test('PlayerSponsorBlockManager handles skip detection and segment reset', () {
      final manager = PlayerSponsorBlockManager();
      expect(manager.currentSegments, isEmpty);

      // Reset works idempotently
      manager.reset();
      expect(manager.currentSegments, isEmpty);
      expect(manager.currentVideoId, isNull);

      // checkSkipTarget returns null when no segments are loaded
      final skip = manager.checkSkipTarget(const Duration(seconds: 30), isPlaying: true);
      expect(skip, isNull);
    });

    test('PlayerLyricsManager generation counter increments monotonically', () {
      final manager = PlayerLyricsManager();
      expect(manager.generation, equals(0));

      final gen1 = manager.bumpGeneration();
      final gen2 = manager.bumpGeneration();

      expect(gen1, equals(1));
      expect(gen2, equals(2));
      expect(manager.generation, equals(2));
    });

    test('PlayerQuranManager handles snapshot storage', () {
      final manager = PlayerQuranManager();
      expect(manager.restoreSnapshot, isNull);

      manager.setRestoreSnapshot(null);
      expect(manager.restoreSnapshot, isNull);
    });

    test('LeakDetector tracks zero unclosed instances in clean state', () {
      expect(LeakDetector.trackedCount, equals(0));
      expect(() => LeakDetector.debugAssertNoLeaks(), returnsNormally);
    });
  });
}
