// test/benchmark/state_performance_benchmark_test.dart
// FIX-A4: State performance benchmarks verifying O(1) diffs and cached operations
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/downloads/cubit/downloads_state.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/features/player/cubit/player_state.dart';
import 'package:pulsr/features/settings/cubit/settings_state.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  group('Performance Benchmarks (A4)', () {
    test('PlayerState.differsFromBeyondPosition completes 10,000 checks in <500ms', () {
      final songA = SongsTableData(
        id: 1,
        title: 'Song A',
        artist: 'Artist A',
        album: 'Album A',
        durationMs: 180000,
        path: '/music/a.mp3',
        source: SongSource.local,
        playCount: 10,
        dateAdded: 0,
        isFavorite: false,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      final songB = SongsTableData(
        id: 2,
        title: 'Song B',
        artist: 'Artist B',
        album: 'Album B',
        durationMs: 200000,
        path: '/music/b.mp3',
        source: SongSource.local,
        playCount: 5,
        dateAdded: 0,
        isFavorite: true,
        isMissing: false,
        lastPositionMs: 0,
        isDownloaded: false,
      );

      const state1 = PlayerState(
        position: Duration(seconds: 10),
        duration: Duration(seconds: 180),
        isPlaying: true,
        playbackPitch: 1.0,
      );

      const state2 = PlayerState(
        position: Duration(seconds: 11), // only position differs
        duration: Duration(seconds: 180),
        isPlaying: true,
        playbackPitch: 1.0,
      );

      final state3 = state1.copyWith(currentSong: songA);
      final state4 = state1.copyWith(currentSong: songB);

      final stopwatch = Stopwatch()..start();
      const iterations = 10000;

      for (int i = 0; i < iterations; i++) {
        // Fast path: identical beyond position
        final diff1 = state1.differsFromBeyondPosition(state2);
        expect(diff1, isFalse);

        // Different track
        final diff2 = state3.differsFromBeyondPosition(state4);
        expect(diff2, isTrue);
      }

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(500),
          reason: '10,000 state diffs took ${stopwatch.elapsedMilliseconds}ms');
    });

    test('DownloadsState hash code is order-independent and performant', () {
      final now = DateTime.now();
      final task1 = DownloadTask(
        id: '1',
        videoId: 'vid1',
        title: 'Title 1',
        artist: 'Channel 1',
        createdAt: now,
      );
      final task2 = DownloadTask(
        id: '2',
        videoId: 'vid2',
        title: 'Title 2',
        artist: 'Channel 2',
        createdAt: now,
      );

      final stateA = DownloadsState(tasks: {'1': task1, '2': task2});
      final stateB = DownloadsState(tasks: {'2': task2, '1': task1});

      expect(stateA.hashCode, equals(stateB.hashCode));
      expect(stateA, equals(stateB));

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 5000; i++) {
        final _ = stateA.hashCode;
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('SettingsState.customAccentColor uses cached Color instances', () {
      const state = SettingsState(customAccentColorValue: 0xFF123456);
      final color1 = state.customAccentColor;
      final color2 = state.customAccentColor;

      // Identity check: exact same reference returned from cache
      expect(identical(color1, color2), isTrue);
      expect(color1.toARGB32(), equals(0xFF123456));
    });
  });
}
