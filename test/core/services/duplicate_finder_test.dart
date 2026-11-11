import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import '../../helpers/test_song_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = DuplicateFinderService();

  group('DuplicateFinderService Clustering & Verification', () {
    test('remix vs original are NOT merged into the same duplicate cluster', () async {
      final original = createTestSong(
        id: 1,
        title: 'Midnight City',
        artist: 'M83',
        path: '/dummy/midnight.mp3',
      );
      final remix = createTestSong(
        id: 2,
        title: 'Midnight City (Eric Prydz Remix)',
        artist: 'M83',
        path: '/dummy/midnight_remix.mp3',
      );
      final live = createTestSong(
        id: 3,
        title: 'Midnight City (Live Version)',
        artist: 'M83',
        path: '/dummy/midnight_live.mp3',
      );
      final duplicateOriginal = createTestSong(
        id: 4,
        title: 'Midnight City [Official Video]',
        artist: 'M83',
        path: '/dummy/midnight_copy.mp3',
      );

      final duplicates = await service.findDuplicates([
        original,
        remix,
        live,
        duplicateOriginal,
      ]);

      // Original and duplicateOriginal should cluster together because [Official Video] is stripped,
      // while (Eric Prydz Remix) and (Live Version) preserve version tags and must not merge.
      expect(duplicates.length, equals(1));
      final clusterIds = duplicates.first.songs.map((s) => s.id).toSet();
      expect(clusterIds, containsAll([1, 4]));
      expect(clusterIds, isNot(contains(2)));
      expect(clusterIds, isNot(contains(3)));
    });

    test('tightened duration tolerance (±2s) is enforced when version tags differ', () async {
      final songA = createTestSong(
        id: 1,
        title: 'Intro Song (Radio Edit)',
        artist: 'Artist',
        durationMs: 120000,
        path: '/dummy/intro_radio.mp3',
      );
      final songB = createTestSong(
        id: 2,
        title: 'Intro Song (Extended Version)',
        artist: 'Artist',
        durationMs: 123500, // 3.5s difference: exceeds the ±2s tolerance for differing versions
        path: '/dummy/intro_extended.mp3',
      );

      final duplicates = await service.findDuplicates([
        songA,
        songB,
      ]);

      expect(duplicates, isEmpty);
    });

    test('identical recordings with bracketed promotional labels cluster properly', () async {
      final songA = createTestSong(
        id: 1,
        title: 'Shape of You [Official Audio]',
        artist: 'Ed Sheeran',
        durationMs: 233000,
        path: '/dummy/shape1.mp3',
      );
      final songB = createTestSong(
        id: 2,
        title: 'Shape of You (Lyric Video)',
        artist: 'Ed Sheeran',
        durationMs: 233500,
        path: '/dummy/shape2.mp3',
      );

      final duplicates = await service.findDuplicates([
        songA,
        songB,
      ]);

      expect(duplicates.length, equals(1));
      expect(duplicates.first.songs.length, equals(2));
    });

    test('partial hash collision resolved by full hash during checksum verification', () async {
      final tempDir = await Directory.systemTemp.createTemp('pulsr_dup_test_');
      try {
        final fileA = File('${tempDir.path}/trackA.bin');
        final fileB = File('${tempDir.path}/trackB.bin');

        // Create two files that share identical first 64KB (partial hash match),
        // but have different trailing content (full SHA-256 mismatch).
        final header = List<int>.filled(65536, 42);
        final contentA = List<int>.from(header)..addAll(List<int>.filled(1024, 1));
        final contentB = List<int>.from(header)..addAll(List<int>.filled(1024, 2));

        await fileA.writeAsBytes(contentA);
        await fileB.writeAsBytes(contentB);

        final songA = createTestSong(
          id: 10,
          title: 'Track One',
          artist: 'Artist One',
          durationMs: 100000,
          path: fileA.path,
        );
        final songB = createTestSong(
          id: 11,
          title: 'Track Two',
          artist: 'Artist Two',
          durationMs: 100000,
          path: fileB.path,
        );

        final duplicates = await service.findDuplicates([
          songA,
          songB,
        ]);

        // If they had matched partial hash, full-file SHA-256 separates them,
        // so no Checksum Verified duplicate cluster is formed.
        final checksumClusters = duplicates
            .where((g) => g.reason.contains('Checksum Verified'))
            .toList();
        expect(checksumClusters, isEmpty);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
