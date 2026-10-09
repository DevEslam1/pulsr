// test/data/scanner/media_scanner_service_test.dart
import 'dart:async';
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

  setUpAll(() {
    registerFallbackValue(<SongsTableCompanion>[]);
    registerFallbackValue(<AlbumsTableCompanion>[]);
    registerFallbackValue(<ArtistsTableCompanion>[]);
    registerFallbackValue(<int>{});
  });

  setUp(() {
    MediaScannerService.clearNomediaCache();
    repo = MockMusicRepository();
    when(() => repo.getExcludedFolderPaths())
        .thenAnswer((_) async => const Right(<String>[]));
    when(() => repo.getAllSongs())
        .thenAnswer((_) async => const Right(<SongsTableData>[]));
    when(() => repo.syncScannedMusic(
        songs: any(named: 'songs'),
        albums: any(named: 'albums'),
        artists: any(named: 'artists'))).thenAnswer((_) async => const Right(null));
    when(() => repo.cleanupOrphanedSongs(any()))
        .thenAnswer((_) async => const Right(0));
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(queryChannel, (call) async {
      if (call.method == 'querySongs') return <dynamic>[];
      return <dynamic>[];
    });

    scanner = MediaScannerService(repo);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tagChannel, null);
    scanner.dispose();
  });

  group('isSystemIgnoredPath', () {
    test('flags messenger voice notes and known system dot folders', () {
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Telegram/Telegram Audio/voice.ogg'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Recordings/call_1.m4a'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Music/.cache/temp.mp3'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/ptt-2020.opus'),
          isTrue);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              '/storage/emulated/0/Music/.my_collection/song.mp3'),
          isFalse);
      expect(
          MediaScannerService.isSystemIgnoredPath(
              r'C:\Music\Albums\Track.flac'),
          isFalse);
    });
  });

  group('isInNomediaDirectory', () {
    test('detects a .nomedia marker in a parent directory', () {
      final temp = Directory.systemTemp.createTempSync('nomedia');
      addTearDown(() {
        temp.deleteSync(recursive: true);
        MediaScannerService.clearNomediaCache();
      });
      final album = Directory('${temp.path}${Platform.pathSeparator}album')
        ..createSync();
      File('${album.path}${Platform.pathSeparator}.nomedia').writeAsStringSync('');
      final song =
          '${album.path}${Platform.pathSeparator}song.mp3';

      expect(MediaScannerService.isInNomediaDirectory(song), isTrue);
      // cached second call
      expect(MediaScannerService.isInNomediaDirectory(song), isTrue);
    });

    test('returns false without a marker and for bare filenames', () {
      final temp = Directory.systemTemp.createTempSync('nomedia_none');
      addTearDown(() => temp.deleteSync(recursive: true));
      expect(
          MediaScannerService.isInNomediaDirectory(
              '${temp.path}${Platform.pathSeparator}song.mp3'),
          isFalse);
      expect(MediaScannerService.isInNomediaDirectory('song.mp3'), isFalse);
      expect(MediaScannerService.isInNomediaDirectory(''), isFalse);
    });
  });

  group('scan lifecycle', () {
    test('markScanComplete and shouldRescanOnResume', () {
      expect(scanner.shouldRescanOnResume(), isTrue);
      scanner.markScanComplete(epochSec: 1234);
      expect(scanner.lastScanEpochSec, 1234);
      expect(scanner.lastScanAt, isNotNull);
      expect(scanner.shouldRescanOnResume(), isFalse);
      expect(
          scanner.shouldRescanOnResume(threshold: Duration.zero), isTrue);
    });

    test('checkPermission and requestPermission succeed off Android', () async {
      expect(await scanner.checkPermission(), isTrue);
      expect(await scanner.requestPermission(), isTrue);
    });

    test('progress streams are exposed and dispose is idempotent', () {
      expect(scanner.scanProgress, isA<Stream<double>>());
      expect(scanner.detailedProgress, isA<Stream<ScanProgressUpdate>>());
      expect(scanner.scanErrors, isA<Stream<ScanError>>());
      scanner.dispose();
      expect(() => scanner.dispose(), returnsNormally);
    });
  });

  group('scanDeviceLibrary', () {
    test('completes an empty scan against mocked platform channels', () async {
      final events = <double>[];
      final sub = scanner.scanProgress.listen(events.add);

      final count = await scanner.scanDeviceLibrary();

      expect(count, 0);
      expect(events.isNotEmpty, isTrue);
      expect(scanner.lastScanAt, isNotNull);
      verify(() => repo.syncScannedMusic(
          songs: any(named: 'songs'),
          albums: any(named: 'albums'),
          artists: any(named: 'artists'))).called(1);
      verify(() => repo.cleanupOrphanedSongs(any())).called(1);
      verify(() => repo.expandCueSheets()).called(1);
      await sub.cancel();
    });

    test('returns 0 when the MediaStore query throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(queryChannel, (call) async {
        throw PlatformException(code: 'error', message: 'no media store');
      });

      final scanner2 = MediaScannerService(repo);
      addTearDown(scanner2.dispose);
      expect(await scanner2.scanDeviceLibrary(), 0);
    });
  });

  group('rescanSingleFile', () {
    test('reads tags and persists them', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async {
        if (call.method == 'readTags') {
          return <String, dynamic>{
            'title': 'Title',
            'artist': 'Artist',
            'album': 'Album',
            'genre': 'Rock',
            'year': '2020',
            'trackNumber': '3',
          };
        }
        return null;
      });

      await scanner.rescanSingleFile('/music/song.mp3');

      final captured = verify(() => repo.updateSongTags(
            path: captureAny(named: 'path'),
            title: captureAny(named: 'title'),
            artist: captureAny(named: 'artist'),
            album: captureAny(named: 'album'),
            genre: captureAny(named: 'genre'),
            year: captureAny(named: 'year'),
            trackNumber: captureAny(named: 'trackNumber'),
          )).captured;
      expect(captured[0], '/music/song.mp3');
      expect(captured[1], 'Title');
      expect(captured[4], 'Rock');
      expect(captured[5], 2020);
      expect(captured[6], 3);
    });

    test('falls back to Unknown defaults for missing tags', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async {
        if (call.method == 'readTags') {
          return <String, dynamic>{'title': '  '};
        }
        return null;
      });

      await scanner.rescanSingleFile('/music/blank.mp3');
      final captured = verify(() => repo.updateSongTags(
            path: any(named: 'path'),
            title: captureAny(named: 'title'),
            artist: captureAny(named: 'artist'),
            album: captureAny(named: 'album'),
            genre: any(named: 'genre'),
            year: any(named: 'year'),
            trackNumber: any(named: 'trackNumber'),
          )).captured;
      expect(captured[0], 'Unknown Song');
      expect(captured[1], 'Unknown Artist');
      expect(captured[2], 'Unknown Album');
    });

    test('emits a ScanError when the channel fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tagChannel, (call) async {
        throw PlatformException(code: 'boom');
      });

      final errorFuture = scanner.scanErrors.first;
      await scanner.rescanSingleFile('/music/bad.mp3');
      final error = await errorFuture;
      expect(error.path, '/music/bad.mp3');
    });
  });

  group('enrichAudioQuality / enrichment', () {
    test('is a no-op off Android', () async {
      await scanner.enrichAudioQuality(1, '/music/song.mp3');
      verifyNever(() => repo.updateAudioQuality(
          songId: any(named: 'songId'),
          sampleRate: any(named: 'sampleRate'),
          bitDepth: any(named: 'bitDepth'),
          bitrateKbps: any(named: 'bitrateKbps'),
          codec: any(named: 'codec'),
          loudnessRange: any(named: 'loudnessRange')));
    });

    test('scheduleAudioQualityEnrichment is a no-op off Android', () async {
      scanner.scheduleAudioQualityEnrichment();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      verifyNever(() => repo.getAllSongs());
    });
  });
}
