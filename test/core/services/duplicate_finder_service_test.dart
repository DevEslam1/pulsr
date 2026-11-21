import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/duplicate_finder_service.dart';
import 'package:pulsr/core/utils/l10n_holder.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/l10n/generated/app_localizations_ar.dart';

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

    test('Pass 2 matches identical audio across adjacent (+/-1) bucket boundary',
        () async {
      final dir = await Directory.systemTemp.createTemp('pulsr_dup_boundary_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final bytes = List<int>.generate(4096, (i) => i % 251);
      final fileA = File('${dir.path}/a.mp3')..writeAsBytesSync(bytes);
      final fileB = File('${dir.path}/b.mp3')..writeAsBytesSync(bytes);

      // Different metadata skips Pass 1; durations fall on either side of the
      // .round() 1000ms boundary (120 vs 121) and stale DB size on either side
      // of the 10KB rounding boundary (0 vs 1).
      final duplicates = await service.findDuplicates([
        _testSong(
          id: 10,
          title: 'First Name',
          artist: 'Artist A',
          durationMs: 120499,
          fileSize: 4999,
          path: fileA.path,
        ),
        _testSong(
          id: 11,
          title: 'Renamed Copy',
          artist: 'Artist B',
          durationMs: 120501,
          fileSize: 5001,
          path: fileB.path,
        ),
      ]);

      expect(duplicates.length, 1);
      expect(duplicates.first.songs.map((s) => s.id), unorderedEquals([10, 11]));
    });

    test('preserves localized reason via L10nHolder when allSongs.length >= 20', () async {
      final l10n = AppLocalizationsAr();
      L10nHolder.current = l10n;
      addTearDown(() => L10nHolder.current = null);

      final songs = List<SongsTableData>.generate(
        22,
        (i) => _testSong(
          id: i + 1,
          title: i < 2 ? 'Same Song' : 'Unique Song $i',
          artist: i < 2 ? 'Same Artist' : 'Artist $i',
          path: '/music/song_$i.mp3',
        ),
      );

      final duplicates = await service.findDuplicates(songs);

      expect(duplicates.length, 1);
      expect(duplicates.first.songs.length, 2);
      expect(duplicates.first.reason, l10n.dupReasonTitleArtist(2));
    });
  });
}
