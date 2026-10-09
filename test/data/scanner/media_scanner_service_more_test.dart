// test/data/scanner/media_scanner_service_more_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/scanner/media_scanner_service.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

class MockMusicRepository extends Mock implements IMusicRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tagChannel = MethodChannel('com.pulsr.music/tag_editor');
  const queryChannel = MethodChannel('com.lucasjosino.on_audio_query');

  late MockMusicRepository repo;
  late MediaScannerService scanner;
  List<SongsTableCompanion>? capturedSongs;
  Set<int>? capturedValidIds;

  Map<String, dynamic> song(
    int id,
    String path, {
    int duration = 200000,
    int size = 5000,
    String? title = 'Title',
    String? artist = 'Artist',
    String? album = 'Album',
    Object? genre,
    Object? year,
    int? artistId = 10,
    int? albumId = 20,
    int? dateAdded,
    int? dateModified,
    String? displayWOExt,
  }) {
    return <String, dynamic>{
      '_id': id,
      '_data': path,
      '_display_name_wo_ext': displayWOExt ?? 'track$id',
      'duration': duration,
      '_size': size,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'artist_id': artistId,
      'album_id': albumId,
      'date_added': dateAdded,
      'date_modified': dateModified,
    };
  }

  setUp(() {
    MediaScannerService.clearNomediaCache();
    capturedSongs = null;
    capturedValidIds = null;
    repo = MockMusicRepository();
    when(() => repo.getExcludedFolderPaths())
        .thenAnswer((_) async => const Right(<String>[]));
    when(() => repo.getAllSongs())
        .thenAnswer((_) async => const Right(<SongsTableData>[]));
    when(() => repo.syncScannedMusic(
        songs: any(named: 'songs'),
        albums: any(named: 'albums'),
        artists: any(named: 'artists'))).thenAnswer((invocation) async {
      capturedSongs = invocation.namedArguments[const Symbol('songs')]
          as List<SongsTableCompanion>;
      return const Right(null);
    });
    when(() => repo.cleanupOrphanedSongs(any()))
        .thenAnswer((invocation) async {
      capturedValidIds = invocation.positionalArguments.first as Set<int>;
      return const Right(0);
    });
    when(() => repo.expandCueSheets()).thenAnswer((_) async => const Right(0));
    when(() => repo.updateAudioQuality(
        songId: any(named: 'songId'),
        sampleRate: any(named: 'sampleRate'),
        bitDepth: any(named: 'bitDepth'),
        bitrateKbps: any(named: 'bitrateKbps'),
        codec: any(named: 'codec'),
        loudnessRange: any(named: 'loudnessRange'))).thenAnswer((_) async => const Right(null));
    when(() => repo.updateSongTags(
        path: any(named: 'path'),
        title: any(named: 'title'),
        artist: any(named: 'artist'),
        album: any(named: 'album'),
        genre: any(named: 'genre'),
        year: any(named: 'year'),
        trackNumber: any(named: 'trackNumber'))).thenAnswer((_) async => const Right(null));

    scanner = MediaScannerService(repo);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(queryChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tagChannel, null);
    scanner.dispose();
  });

  group('isSystemIgnoredPath extra branches', () {
    test('ptt- and aud- only match inside messenger folders', () {
      expect(
          MediaScannerService.isSystemIgnoredPath('/music/ptt-1234.ogg'),
          isFalse);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/whatsapp/aud-1234567890123456789012.opus'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath('/music/aud-1234.opus'),
          isFalse);
    });

    test('normalizes backslashes and ignores known system dot folders', () {
      expect(
          MediaScannerService.isSystemIgnoredPath(
              r'C:\Users\me\Music\.trash\song.mp3'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              r'C:\Users\me\Music\.thumbnails\song.mp3'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              r'C:\Users\me\Music\.my_folder\song.mp3'),
          isFalse);
    });

    test('detects WhatsApp voice notes under the Android media tree', () {
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/'
              'WhatsApp Voice Notes/ptt-2020.opus'),
          isTrue);
    });
  });

  group('isInNomediaDirectory extra branches', () {
    test('detects a marker several directories up', () {
      final temp = Directory.systemTemp.createTempSync('nomedia_deep');
      addTearDown(() {
        temp.deleteSync(recursive: true);
        MediaScannerService.clearNomediaCache();
      });
      File('${temp.path}${Platform.pathSeparator}.nomedia')
          .writeAsStringSync('');
      final deep = Directory(
          '${temp.path}${Platform.pathSeparator}a${Platform.pathSeparator}b')
        ..createSync(recursive: true);
      final file =
          File('${deep.path}${Platform.pathSeparator}song.mp3');
      expect(MediaScannerService.isInNomediaDirectory(file.path), isTrue);
    });

    test('evicts the cache when it grows past its cap', () {
      for (var i = 0; i < 1300; i++) {
        expect(
            MediaScannerService.isInNomediaDirectory('/unique$i/a/song.mp3'),
            isFalse);
      }
      expect(MediaScannerService.isInNomediaDirectory('bare.mp3'), isFalse);
    });
  });

  group('scanDeviceLibrary parse pipeline', () {
    test('parses songs, filters invalid ones and aggregates albums/artists',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        switch (call.method) {
          case 'querySongs':
            return <Map<String, dynamic>>[
              song(1, '/storage/emulated/0/Music/a.mp3',
                  title: 'Track A',
                  artist: 'Artist A',
                  album: 'Album A',
                  genre: 'Rock',
                  year: 2020,
                  dateAdded: 1600000000),
              song(2, '/storage/emulated/0/Music/b.flac',
                  title: 'Track B',
                  artist: 'Artist B',
                  album: 'Album B',
                  artistId: 11,
                  albumId: 21,
                  dateAdded: 1600000001),
              // Skipped: too short.
              song(3, '/storage/emulated/0/Music/c.mp3', duration: 500),
              // Skipped: requires a native decoder.
              song(4, '/storage/emulated/0/Music/d.ape'),
              // Skipped: unrecognized extension.
              song(5, '/storage/emulated/0/Music/e.xyz'),
              // Skipped: empty path.
              song(6, ''),
              // Skipped: non-positive id.
              song(0, '/storage/emulated/0/Music/f.mp3'),
              // Skipped: system-ignored folder.
              song(7, '/storage/emulated/0/Recordings/rec.m4a'),
              // Unknown metadata fallbacks, bad year.
              song(8, '/storage/emulated/0/Music/g.ogg',
                  title: '',
                  artist: '<unknown>',
                  album: null,
                  genre: '<unknown>',
                  year: 'nope',
                  artistId: null,
                  albumId: null),
              // Duplicate id -> skipped.
              song(1, '/storage/emulated/0/Music/a.mp3'),
            ];
          case 'queryGenres':
            return <Map<String, dynamic>>[
              {'_id': 5, 'name': 'Jazz'},
            ];
          case 'queryAudiosFrom':
            return <Map<String, dynamic>>[
              {'_id': 2},
            ];
          default:
            return <dynamic>[];
        }
      });

      final count = await scanner.scanDeviceLibrary();

      expect(count, 3);
      final songs = capturedSongs!;
      expect(songs.map((s) => s.id.value), containsAll([1, 2, 8]));
      expect(songs.any((s) => s.id.value == 4), isFalse);

      final trackA = songs.firstWhere((s) => s.id.value == 1);
      expect(trackA.title.value, 'Track A');
      expect(trackA.genre.value, 'Rock');
      expect(trackA.dateAdded.value, 1600000000000);
      final trackB = songs.firstWhere((s) => s.id.value == 2);
      expect(trackB.genre.value, 'Jazz');
      final fallback = songs.firstWhere((s) => s.id.value == 8);
      expect(fallback.title.value, 'Unknown Song');
      expect(fallback.artist.value, 'Unknown Artist');
      expect(fallback.album.value, 'Unknown Album');
      expect(fallback.genre.value, isNull);
      expect(fallback.year.value, isNull);

      expect(capturedValidIds, {1, 2, 8});
      verify(() => repo.expandCueSheets()).called(1);
    });

    test('honours minSizeKb and excluded folders', () async {
      when(() => repo.getExcludedFolderPaths()).thenAnswer(
          (_) async => const Right(<String>[r'C:\Music\Excluded']));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        switch (call.method) {
          case 'querySongs':
            return <Map<String, dynamic>>[
              song(1, r'C:\Music\Kept\big.mp3', size: 3000),
              song(2, r'C:\Music\Kept\small.mp3', size: 100),
              song(3, r'C:\Music\Excluded\skip.mp3', size: 3000),
            ];
          default:
            return <dynamic>[];
        }
      });

      final count = await scanner.scanDeviceLibrary(minSizeKb: 1);
      expect(count, 1);
      expect(capturedSongs!.single.id.value, 1);
    });

    test('incremental scan skips unchanged songs and reports completion',
        () async {
      scanner.markScanComplete(epochSec: 2000);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        if (call.method == 'querySongs') {
          return <Map<String, dynamic>>[
            song(1, '/storage/emulated/0/Music/old.mp3',
                dateModified: 1000),
          ];
        }
        return <dynamic>[];
      });

      final events = <double>[];
      final sub = scanner.scanProgress.listen(events.add);
      final count = await scanner.scanDeviceLibrary(incremental: true);
      await sub.cancel();

      expect(count, 0);
      expect(events, isNotEmpty);
      verifyNever(() => repo.syncScannedMusic(
          songs: any(named: 'songs'),
          albums: any(named: 'albums'),
          artists: any(named: 'artists')));
    });

    test('incremental scan keeps newly modified songs', () async {
      scanner.markScanComplete(epochSec: 2000);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        if (call.method == 'querySongs') {
          return <Map<String, dynamic>>[
            song(1, '/storage/emulated/0/Music/new.mp3',
                dateModified: 3000),
          ];
        }
        return <dynamic>[];
      });

      final count = await scanner.scanDeviceLibrary(incremental: true);
      expect(count, 1);
      expect(capturedSongs!.single.id.value, 1);
      verifyNever(() => repo.cleanupOrphanedSongs(any()));
    });

    test('only syncs when starting permission is granted', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        if (call.method == 'querySongs') {
          return <Map<String, dynamic>>[
            song(1, '/storage/emulated/0/Music/a.mp3'),
          ];
        }
        return <dynamic>[];
      });
      expect(await scanner.scanDeviceLibrary(), 1);
    });
  });

  group('rescanSingleFile / progress models', () {
    test('does nothing when the tag channel returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async => null);

      await scanner.rescanSingleFile('/music/null.mp3');
      verifyNever(() => repo.updateSongTags(
          path: any(named: 'path'),
          title: any(named: 'title'),
          artist: any(named: 'artist'),
          album: any(named: 'album'),
          genre: any(named: 'genre'),
          year: any(named: 'year'),
          trackNumber: any(named: 'trackNumber')));
    });

    test('non-numeric year and track are ignored', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async {
        if (call.method == 'readTags') {
          return <String, dynamic>{
            'title': 'T',
            'artist': 'A',
            'album': 'B',
            'year': 'nope',
            'trackNumber': 'also-nope',
          };
        }
        return null;
      });

      await scanner.rescanSingleFile('/music/badints.mp3');
      final captured = verify(() => repo.updateSongTags(
            path: any(named: 'path'),
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            genre: any(named: 'genre'),
            year: captureAny(named: 'year'),
            trackNumber: captureAny(named: 'trackNumber'),
          )).captured;
      expect(captured[0], isNull);
      expect(captured[1], isNull);
    });

    test('ScanProgressUpdate and ScanError expose their fields', () {
      const update = ScanProgressUpdate(
        progress: 0.5,
        currentFile: 'x.mp3',
        scannedCount: 2,
        totalCount: 4,
        isIncremental: true,
      );
      expect(update.toString(), contains('50.0%'));
      expect(update.toString(), contains('x.mp3'));
      expect(update.toString(), contains('2/4'));

      final error = ScanError(path: '/p.mp3', message: 'm', error: 'e');
      expect(error.path, '/p.mp3');
      expect(error.message, 'm');
      expect(error.error, 'e');
    });
  });
}
