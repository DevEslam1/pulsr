import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/data/db/app_database.dart';

SongsTableData _testSong({
  required int id,
  required String title,
  required String artist,
  String album = 'Test Album',
  required String path,
  int durationMs = 180000,
  int? fileSize,
}) =>
    SongsTableData(
      id: id,
      title: title,
      artist: artist,
      album: album,
      path: path,
      durationMs: durationMs,
      fileSize: fileSize,
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuplicateFinderService Tests', () {
    late DuplicateFinderService service;

    setUp(() {
      service = DuplicateFinderService();
    });

    test('Identical title and artist clusters as Pass 1 duplicates', () async {
      final song1 = _testSong(
        id: 1,
        title: 'Song Alpha',
        artist: 'Artist One',
        path: '/storage/music/song1.mp3',
      );
      final song2 = _testSong(
        id: 2,
        title: 'Song Alpha',
        artist: 'Artist One',
        path: '/storage/music/song2.mp3',
      );
      final song3 = _testSong(
        id: 3,
        title: 'Song Beta',
        artist: 'Artist Two',
        path: '/storage/music/song3.mp3',
      );

      final duplicates = await service.findDuplicates([song1, song2, song3]);

      expect(duplicates.length, equals(1));
      expect(duplicates.first.songs.length, equals(2));
      expect(duplicates.first.reason, contains('Identical Title & Artist'));
    });

    test('same title/artist on different albums are not duplicates', () async {
      final duplicates = await service.findDuplicates([
        _testSong(
            id: 1,
            title: 'Intro',
            artist: 'Band',
            album: 'Album A',
            path: '/a/intro.mp3'),
        _testSong(
            id: 2,
            title: 'Intro',
            artist: 'Band',
            album: 'Album B',
            path: '/b/intro.mp3'),
      ]);

      expect(duplicates, isEmpty);
    });

    test('durations beyond tolerance are not duplicates', () async {
      final duplicates = await service.findDuplicates([
        _testSong(
            id: 1,
            title: 'Intro',
            artist: 'Band',
            durationMs: 100000,
            path: '/a/intro.mp3'),
        _testSong(
            id: 2,
            title: 'Intro',
            artist: 'Band',
            durationMs: 130000,
            path: '/b/intro.mp3'),
      ]);

      expect(duplicates, isEmpty);
    });

    test('codec variants with different file sizes still cluster', () async {
      final duplicates = await service.findDuplicates([
        _testSong(
            id: 1,
            title: 'Song Alpha',
            artist: 'Artist One',
            path: '/a/song.flac',
            fileSize: 40000000),
        _testSong(
            id: 2,
            title: 'Song Alpha',
            artist: 'Artist One',
            path: '/a/song.mp3',
            fileSize: 8000000),
      ]);

      expect(duplicates.length, equals(1));
      expect(duplicates.first.songs.length, equals(2));
    });

    test('two recordings sharing a title cluster into separate groups',
        () async {
      final duplicates = await service.findDuplicates([
        _testSong(
            id: 1,
            title: 'Live',
            artist: 'Band',
            album: 'Live Album',
            durationMs: 200000,
            path: '/live/a.mp3'),
        _testSong(
            id: 2,
            title: 'Live',
            artist: 'Band',
            album: 'Live Album',
            durationMs: 200500,
            path: '/live/b.flac'),
        _testSong(
            id: 3,
            title: 'Live',
            artist: 'Band',
            album: 'Studio Album',
            durationMs: 180000,
            path: '/studio/a.mp3'),
      ]);

      expect(duplicates.length, equals(1));
      expect(duplicates.first.songs.map((s) => s.id), unorderedEquals([1, 2]));
    });

    test(
        'Pass 2 disambiguates keys for multiple checksum clusters in same bucket',
        () {
      final group = DuplicateGroup(
        key: '180-500-1',
        songs: [
          _testSong(id: 1, title: 'Track A', artist: 'Art', path: '/a.mp3'),
          _testSong(
              id: 2,
              title: 'Track A (Copy)',
              artist: 'Art',
              path: '/a_copy.mp3'),
        ],
        reason: 'Identical Audio Content (Checksum Verified)',
      );

      expect(group.key, equals('180-500-1'));
    });
  });
}
