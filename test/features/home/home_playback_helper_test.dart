import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/features/home/presentation/widgets/home_playback_helper.dart';

SongsTableData _testSong(int id, String title) {
  return SongsTableData(
    id: id,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    durationMs: 180000,
    path: '/music/$title.mp3',
    source: SongSource.local,
    isFavorite: false,
    isMissing: false,
    isDownloaded: true,
    playCount: 1,
    lastPositionMs: 0,
  );
}

void main() {
  group('buildQueueWithLibraryFallback', () {
    test('returns section songs unmodified when library is empty', () {
      final section = [_testSong(1, 'Song 1'), _testSong(2, 'Song 2')];
      final result = buildQueueWithLibraryFallback(
        sectionSongs: section,
        librarySongs: const [],
      );

      expect(result.map((s) => s.id).toList(), [1, 2]);
    });

    test('appends library songs without duplicating section songs', () {
      final s1 = _testSong(1, 'Song 1');
      final s2 = _testSong(2, 'Song 2');
      final s3 = _testSong(3, 'Song 3');
      final s4 = _testSong(4, 'Song 4');

      final section = [s3, s1];
      final library = [s1, s2, s3, s4];

      final result = buildQueueWithLibraryFallback(
        sectionSongs: section,
        librarySongs: library,
      );

      // Section order preserved first, then non-duplicate library items appended
      expect(result.map((s) => s.id).toList(), [3, 1, 2, 4]);
    });

    test('preserves entire section even if library has duplicates', () {
      final s1 = _testSong(1, 'Song 1');
      final s2 = _testSong(2, 'Song 2');

      final section = [s1];
      final library = [s1, s2];

      final result = buildQueueWithLibraryFallback(
        sectionSongs: section,
        librarySongs: library,
      );

      expect(result.map((s) => s.id).toList(), [1, 2]);
    });
  });
}
