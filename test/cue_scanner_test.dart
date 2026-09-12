// test/cue_scanner_test.dart
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/cue_parser.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

const _cueContent = '''
TITLE "Sample Album"
PERFORMER "Sample Artist"
FILE "album.flac" FLAC
  TRACK 01 AUDIO
    TITLE "Opening"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Middle"
    INDEX 01 04:30:00
  TRACK 03 AUDIO
    TITLE "Finale"
    INDEX 01 09:15:00
''';

SongsTableData _container(String path, {int durationMs = 600000}) =>
    SongsTableData(
      id: 10,
      title: 'Full Album',
      artist: 'Container Artist',
      album: 'Container Album',
      durationMs: durationMs,
      path: path,
      source: SongSource.local,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );

void main() {
  group('CueParser fixture', () {
    test('parses chapters with starts and derived ends', () {
      final chapters = CueParser.parse(_cueContent);

      expect(chapters.length, equals(3));
      expect(chapters[0].index, equals(1));
      expect(chapters[0].title, equals('Opening'));
      expect(chapters[0].start, equals(Duration.zero));
      expect(chapters[0].end,
          equals(const Duration(minutes: 4, seconds: 30)));
      expect(chapters[2].end, isNull);
    });
  });

  group('cueVirtualSongId', () {
    test('is deterministic, negative and distinct per track index', () {
      const path = '/music/album.flac';
      final a = MusicRepository.cueVirtualSongId(path, 1);
      final b = MusicRepository.cueVirtualSongId(path, 1);
      final other = MusicRepository.cueVirtualSongId(path, 2);
      final otherPath = MusicRepository.cueVirtualSongId('/music/x.flac', 1);

      expect(a, equals(b), reason: 'same path + index must be stable');
      expect(a, isNegative);
      expect(other, isNot(equals(a)));
      expect(otherPath, isNot(equals(a)));
    });
  });

  group('buildCueExpansion', () {
    test('maps chapters onto the container path with the real file fields',
        () {
      final container = _container('/music/album.flac');
      final chapters = CueParser.parse(_cueContent);
      final companions = MusicRepository.buildCueExpansion(
        container: container,
        chapters: chapters,
        cuePath: '/music/album.cue',
      );

      expect(companions.length, equals(3));
      final first = companions.first;
      expect(first.id.value,
          equals(MusicRepository.cueVirtualSongId(container.path, 1)));
      expect(first.path.value, equals(container.path));
      expect(first.cueFile.value, equals('/music/album.cue'));
      expect(first.cueStartMs.value, equals(0));
      expect(first.cueEndMs.value, equals(270000));
      expect(first.durationMs.value, equals(container.durationMs));
      expect(first.title.value, equals('Opening'));
      expect(first.artist.value, equals(container.artist));
      expect(first.album.value, equals(container.album));
      expect(first.trackNumber.value, equals(1));

      // Last chapter runs to the end of the real file, so its end is open and
      // natural file completion advances the queue.
      final last = companions.last;
      expect(last.cueStartMs.value, equals(555000));
      expect(last.cueEndMs.value, isNull);
      expect(last.durationMs.value, equals(container.durationMs));
    });
  });

  group('AppDatabase + expandCueSheets', () {
    late AppDatabase db;
    late MusicRepository repository;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = MusicRepository(db);
      tempDir = await Directory.systemTemp.createTemp('pulsr_cue_test');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists cue columns through an in-memory database', () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(1),
            title: 'Virtual Track',
            path: '/music/album.flac',
            cueStartMs: const Value(1000),
            cueEndMs: const Value(2000),
            cueFile: const Value('/music/album.cue'),
          ));

      final row = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(row.cueStartMs, equals(1000));
      expect(row.cueEndMs, equals(2000));
      expect(row.cueFile, equals('/music/album.cue'));
    });

    test('expands a sibling cue idempotently and hides the container',
        () async {
      final audioPath = '${tempDir.path}${Platform.pathSeparator}album.flac';
      final cuePath = '${tempDir.path}${Platform.pathSeparator}album.cue';
      await File(audioPath).writeAsString('');
      await File(cuePath).writeAsString(_cueContent);

      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(10),
            title: 'Full Album',
            path: audioPath,
            durationMs: const Value(600000),
          ));

      final first = await repository.expandCueSheets();
      expect(first.getOrElse((_) => -1), equals(3));

      // Repeat scan must not duplicate rows or delete the real file row.
      final second = await repository.expandCueSheets();
      expect(second.getOrElse((_) => -1), equals(3));

      final allRows = await db.select(db.songsTable).get();
      expect(allRows.where((s) => s.cueStartMs != null).length, equals(3));
      final container = allRows.firstWhere((s) => s.id == 10);
      expect(container.cueFile, equals(cuePath));
      expect(container.cueStartMs, isNull);

      // Container is hidden from the standard library listing.
      final library = (await repository.getAllSongs()).getOrElse((_) => []);
      expect(library.length, equals(3));
      expect(library.every((s) => s.cueStartMs != null), isTrue);
      expect(library.any((s) => s.id == 10), isFalse);
    });
  });
}
