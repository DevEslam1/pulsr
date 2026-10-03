// Edge-case coverage for LrcParser: metadata/offset handling, bilingual merge,
// word-level timestamps, disk lookup fallbacks, caching and resolveLyrics
// orchestration with a fake LRCLIB service. Happy paths live in
// test/lrc_parser_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

class _FakeLrclib {
  int calls = 0;
  LyricsResult? result;
  String? lastTrack;
  String? lastArtist;
  String? lastAlbum;
  int? lastDuration;

  Future<LyricsResult?> fetchLyrics({
    String? trackName,
    String? artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    calls++;
    lastTrack = trackName;
    lastArtist = artistName;
    lastAlbum = albumName;
    lastDuration = durationSeconds;
    return result;
  }
}

class _ThrowingLrclib {
  Future<LyricsResult?> fetchLyrics({
    String? trackName,
    String? artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    throw StateError('lrclib offline');
  }
}

class _DeferredLrclib {
  final Completer<LyricsResult?> completer = Completer<LyricsResult?>();
  int calls = 0;

  Future<LyricsResult?> fetchLyrics({
    String? trackName,
    String? artistName,
    String? albumName,
    int? durationSeconds,
  }) {
    calls++;
    return completer.future;
  }
}

LyricsResult _syncedResult() => LyricsResult(
      lines: [
        LyricsLine(
          timestamp: const Duration(seconds: 3),
          text: 'From LRCLIB',
          source: LyricsSource.lrclib,
        ),
      ],
      source: LyricsSource.lrclib,
    );

void main() {
  tearDown(() {
    LrcParser.clearCache();
  });

  group('LrcParser.parseWithMetadata', () {
    test('strips a UTF-8 BOM before parsing', () {
      const lrc = '\uFEFF[00:01.00]Bom line';
      final result = LrcParser.parseWithMetadata(lrc);
      expect(result.lines.single.text, 'Bom line');
      expect(result.lines.single.timestamp, const Duration(seconds: 1));
    });

    test('collects ar/ti/al/by/length/offset metadata', () {
      const lrc = '''
[ar:Artist Name]
[ti:Song Title]
[al:Album Name]
[by:Lyric Author]
[length:03:20]
[offset:150]
[00:05.00]Line
''';
      final result = LrcParser.parseWithMetadata(lrc);
      expect(result.metadata['ar'], 'Artist Name');
      expect(result.metadata['ti'], 'Song Title');
      expect(result.metadata['al'], 'Album Name');
      expect(result.metadata['by'], 'Lyric Author');
      expect(result.metadata['length'], '03:20');
      expect(result.metadata['offset'], '150');
      expect(result.lines.single.timestamp,
          const Duration(seconds: 5, milliseconds: 150));
    });

    test('a non-numeric offset is treated as zero', () {
      const lrc = '[offset:abc]\n[00:02.00]Line';
      final result = LrcParser.parseWithMetadata(lrc);
      expect(result.lines.single.timestamp, const Duration(seconds: 2));
    });

    test('single-digit minute/fraction fields are padded', () {
      final lines = LrcParser.parse('[1:02.5]Short fields');
      expect(lines.single.timestamp,
          const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    });

    test('a negative timestamp offset clamps to zero', () {
      final lines = LrcParser.parse('[offset:-20000]\n[00:05.00]Late');
      expect(lines.single.timestamp, Duration.zero);
    });

    test('lines shorter than 50ms apart merge as translations', () {
      const lrc = '''
[00:10.00]Original line
[00:10.03]Translated line
[00:20.00]Next line
''';
      final result = LrcParser.parseWithMetadata(lrc);
      expect(result.lines, hasLength(2));
      expect(result.lines[0].text, 'Original line');
      expect(result.lines[0].translation, 'Translated line');
      expect(result.lines[1].translation, isNull);
    });

    test('identical text is not merged, larger gaps are not merged', () {
      const lrc = '''
[00:10.00]Same
[00:10.02]Same
[00:11.00]Other
''';
      final result = LrcParser.parseWithMetadata(lrc);
      expect(result.lines, hasLength(3));
      expect(result.lines.every((l) => l.translation == null), isTrue);
    });

    test('non-vocal markers are flagged', () {
      const lrc = '''
[00:01.00]♪
[00:02.00]instrumental break
[00:03.00]...
[00:04.00]•••
[00:05.00]Real lyric
''';
      final lines = LrcParser.parse(lrc);
      expect(lines.map((l) => l.isVocal), [false, false, false, false, true]);
    });

    test('one line with several timestamps produces several entries', () {
      const lrc = '[00:01.00][00:02.00]Repeated';
      final lines = LrcParser.parse(lrc);
      expect(lines, hasLength(2));
      expect(lines[0].text, 'Repeated');
      expect(lines[1].timestamp, const Duration(seconds: 2));
    });

    test('source is propagated to every parsed line and result', () {
      const lrc = '[00:01.00]Line';
      final result = LrcParser.parseWithMetadata(
        lrc,
        source: LyricsSource.ytmusic,
      );
      expect(result.source, LyricsSource.ytmusic);
      expect(result.lines.single.source, LyricsSource.ytmusic);
    });

    test('enhanced word timestamps expose start/end offsets', () {
      const lrc = '[00:10.00]<00:10.00>Hello <00:10.50>world';
      final line = LrcParser.parse(lrc).single;
      expect(line.words, hasLength(2));
      expect(line.words[0].word, 'Hello');
      expect(line.words[0].startMs, 10000);
      expect(line.words[0].endMs, 10500);
      expect(line.words[1].word, 'world');
      expect(line.words[1].startMs, 10500);
      // The final word gets a synthetic 350ms duration.
      expect(line.words[1].endMs, 10850);
    });

    test('word timestamps without minute part fall back to the line start', () {
      const lrc = '[00:10.00]<10>Hi<20>There';
      final line = LrcParser.parse(lrc).single;
      expect(line.words, hasLength(2));
      expect(line.words[0].startMs, 10000);
      expect(line.words[0].endMs, 10050);
      expect(line.words[1].startMs, 10000);
    });

    test('word timestamps honour sub-second fractions and offsets', () {
      const lrc = '[offset:1000]\n'
          '[00:10.00]<00:10.500>Hello <00:11.000>world';
      final line = LrcParser.parse(lrc).single;
      expect(line.words[0].startMs, 11500);
      expect(line.words[0].endMs, 12000);
      expect(line.words[1].startMs, 12000);
    });

    test('empty word segments between tags are dropped', () {
      const lrc = '[00:01.00]<00:01.00> <00:01.50>Hello';
      final line = LrcParser.parse(lrc).single;
      expect(line.words, hasLength(1));
      expect(line.words.single.word, 'Hello');
    });

    test('plain metadata-only content parses to an empty line list', () {
      final result = LrcParser.parseWithMetadata('[ar:Only metadata]\n');
      expect(result.lines, isEmpty);
      expect(result.metadata['ar'], 'Only metadata');
    });
  });

  group('LrcParser.formatToLrc / parsePlainText', () {
    test('formatToLrc pads fields and renders empty text as dots', () {
      final lrc = LrcParser.formatToLrc([
        const LyricsLine(timestamp: Duration.zero, text: ''),
        const LyricsLine(
          timestamp: Duration(minutes: 2, seconds: 5, milliseconds: 123),
          text: 'Hello',
        ),
      ]);
      expect(lrc, contains('[00:00.00]•••\n'));
      expect(lrc, contains('[02:05.12]Hello\n'));
    });

    test('parsePlainText trims, skips blanks and keeps the chosen source', () {
      final lines = LrcParser.parsePlainText(
        '  First  \n\nSecond\n   ',
        source: LyricsSource.lrclib,
      );
      expect(lines.map((l) => l.text), ['First', 'Second']);
      expect(lines.every((l) => l.timestamp == Duration.zero), isTrue);
      expect(lines.every((l) => l.source == LyricsSource.lrclib), isTrue);
    });

    test('parsePlainText defaults to the embedded source', () {
      final lines = LrcParser.parsePlainText('Only line');
      expect(lines.single.source, LyricsSource.embedded);
    });
  });

  group('LrcParser.findAndParseLrc', () {
    late Directory tempDir;
    late String musicDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('pulsr_lrc_edge_');
      musicDir = '${tempDir.path}${Platform.pathSeparator}music';
      Directory(musicDir).createSync(recursive: true);
    });

    tearDownAll(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File audioFile(String name) {
      final file = File('$musicDir${Platform.pathSeparator}$name');
      file.writeAsStringSync('audio');
      return file;
    }

    test('guards reject empty, content, http and ytmusic paths', () async {
      expect(await LrcParser.findAndParseLrc(''), isNull);
      expect(await LrcParser.findAndParseLrc('content://media/1'), isNull);
      expect(await LrcParser.findAndParseLrc('https://x/song.mp3'), isNull);
      expect(await LrcParser.findAndParseLrc('ytmusic://abc'), isNull);
    });

    test('a path without an extension is ignored', () async {
      expect(await LrcParser.findAndParseLrc('no-extension'), isNull);
    });

    test('finds a direct sibling .lrc', () async {
      final audio = audioFile('sibling.mp3');
      File('$musicDir${Platform.pathSeparator}sibling.lrc')
          .writeAsStringSync('[00:04.00]Sibling');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.text, 'Sibling');
    });

    test('falls back to a .txt sibling', () async {
      final audio = audioFile('textfallback.mp3');
      File('$musicDir${Platform.pathSeparator}textfallback.txt')
          .writeAsStringSync('[00:05.00]Text sibling');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.text, 'Text sibling');
    });

    test('searches a Lyrics subdirectory', () async {
      final audio = audioFile('subsong.mp3');
      final lyricsDir = Directory('$musicDir${Platform.pathSeparator}Lyrics');
      lyricsDir.createSync();
      File('${lyricsDir.path}${Platform.pathSeparator}subsong.lrc')
          .writeAsStringSync('[00:06.00]Subdir');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.text, 'Subdir');
    });

    test('falls back to a generic lyrics.lrc in the folder', () async {
      final audio = audioFile('genericsong.mp3');
      File('$musicDir${Platform.pathSeparator}lyrics.lrc')
          .writeAsStringSync('[00:07.00]Generic');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.text, 'Generic');
    });

    test('generic file with unsynced text yields plain lyrics', () async {
      final audio = audioFile('plainsong.mp3');
      File('$musicDir${Platform.pathSeparator}lyrics.lrc')
          .writeAsStringSync('Just a plain line\nAnother plain line');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.map((l) => l.text),
          ['Just a plain line', 'Another plain line']);
      expect(lines.every((l) => l.timestamp == Duration.zero), isTrue);
    });

    test('invalid UTF-8 falls back to latin1 decoding', () async {
      final audio = audioFile('latin.mp3');
      File('$musicDir${Platform.pathSeparator}latin.lrc')
          .writeAsBytesSync(latin1.encode('[00:08.00]Caf\xE9 line'));
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.text, 'Café line');
    });

    test('unsynced (negative-only) timestamps still parse', () async {
      final audio = audioFile('unsynced.mp3');
      File('$musicDir${Platform.pathSeparator}unsynced.lrc')
          .writeAsStringSync('[-00:02.00]Intro count');
      final lines = await LrcParser.findAndParseLrc(audio.path);
      expect(lines!.single.timestamp, Duration.zero);
      expect(lines.single.text, 'Intro count');
    });

    test('missing sibling files return null', () async {
      final emptyDir = Directory.systemTemp.createTempSync('pulsr_lrc_empty_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final audio = File('${emptyDir.path}${Platform.pathSeparator}nothing.mp3')
        ..writeAsStringSync('audio');
      expect(await LrcParser.findAndParseLrc(audio.path), isNull);
    });
  });

  group('LrcParser cache helpers', () {
    test('lookups without a key return safe defaults', () {
      expect(LrcParser.hasCachedLyrics(), isFalse);
      expect(LrcParser.getCachedLyrics(), isNull);
      expect(LrcParser.getCacheTimestamp(), isNull);
      LrcParser.cacheLyricsResult(_syncedResult());
      LrcParser.invalidateCache();
      LrcParser.invalidateSong();
    });

    test('negative results are cached with a timestamp', () {
      LrcParser.cacheLyricsResult(null, songId: 700001);
      expect(LrcParser.hasCachedLyrics(songId: 700001), isTrue);
      expect(LrcParser.getCachedLyrics(songId: 700001), isNull);
      expect(LrcParser.getCacheTimestamp(songId: 700001), isNotNull);
    });

    test('positive results cache under both songId and path keys', () {
      final result = _syncedResult();
      LrcParser.cacheLyricsResult(result,
          songId: 700002, path: '/music/two.mp3');
      expect(LrcParser.getCachedLyrics(songId: 700002), same(result));
      expect(LrcParser.getCachedLyrics(path: '/music/two.mp3'), same(result));
      expect(LrcParser.getCacheTimestamp(songId: 700002), isNull);
    });

    test('invalidateCache removes both songId and path entries', () {
      LrcParser.cacheLyricsResult(_syncedResult(),
          songId: 700003, path: '/music/three.mp3');
      LrcParser.invalidateCache(songId: 700003, path: '/music/three.mp3');
      expect(LrcParser.hasCachedLyrics(songId: 700003), isFalse);
      expect(LrcParser.hasCachedLyrics(path: '/music/three.mp3'), isFalse);
    });

    test('invalidateSong removes songId and path entries', () {
      LrcParser.cacheLyricsResult(_syncedResult(),
          songId: 700004, path: '/music/four.mp3');
      LrcParser.invalidateSong(songId: 700004, path: '/music/four.mp3');
      expect(LrcParser.hasCachedLyrics(songId: 700004), isFalse);
      expect(LrcParser.hasCachedLyrics(path: '/music/four.mp3'), isFalse);
    });

    test('the cache evicts the oldest entry past 50 keys', () {
      for (int i = 0; i < 55; i++) {
        LrcParser.cacheLyricsResult(_syncedResult(), songId: 710000 + i);
      }
      expect(LrcParser.hasCachedLyrics(songId: 710000), isFalse);
      expect(LrcParser.hasCachedLyrics(songId: 710054), isTrue);
    });
  });

  group('LrcParser.resolveLyrics', () {
    test('returns a previously cached result immediately', () async {
      final cached = _syncedResult();
      LrcParser.cacheLyricsResult(cached, songId: 720001);
      final resolved = await LrcParser.resolveLyrics(
        '/missing/track.mp3',
        songId: 720001,
      );
      expect(identical(resolved, cached), isTrue);
    });

    test('unsynced external lrc becomes a plain fallback', () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_lrc_resolve_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final audio = File('${dir.path}${Platform.pathSeparator}book.mp3')
        ..writeAsStringSync('audio');
      File('${dir.path}${Platform.pathSeparator}book.lrc')
          .writeAsStringSync('[-00:01.00]Intro count');

      final resolved = await LrcParser.resolveLyrics(audio.path);
      expect(resolved, isNotNull);
      expect(resolved!.source, LyricsSource.externalLrc);
      expect(resolved.lines.single.text, 'Intro count');
      expect(LrcParser.hasCachedLyrics(path: audio.path), isTrue);
    });

    test('a fake LRCLIB service supplies synced lines', () async {
      final fake = _FakeLrclib()..result = _syncedResult();
      final resolved = await LrcParser.resolveLyrics(
        '/missing/online.mp3',
        songId: 720002,
        trackTitle: 'Title',
        artist: 'Artist',
        album: 'Album',
        durationSec: 210,
        lrclibService: fake,
      );
      expect(resolved, same(fake.result));
      expect(fake.calls, 1);
      expect(fake.lastTrack, 'Title');
      expect(fake.lastArtist, 'Artist');
      expect(fake.lastAlbum, 'Album');
      expect(fake.lastDuration, 210);
    });

    test('external plain fallback loses to a synced LRCLIB result', () async {
      final dir = Directory.systemTemp.createTempSync('pulsr_lrc_pref_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final audio = File('${dir.path}${Platform.pathSeparator}book.mp3')
        ..writeAsStringSync('audio');
      File('${dir.path}${Platform.pathSeparator}book.lrc')
          .writeAsStringSync('[-00:01.00]Intro count');

      final fake = _FakeLrclib()..result = _syncedResult();
      final resolved = await LrcParser.resolveLyrics(
        audio.path,
        songId: 720003,
        trackTitle: 'Title',
        artist: 'Artist',
        lrclibService: fake,
      );
      expect(resolved!.source, LyricsSource.lrclib);
    });

    test('a throwing LRCLIB service caches a negative result', () async {
      final resolved = await LrcParser.resolveLyrics(
        '/missing/broken.mp3',
        songId: 720004,
        trackTitle: 'Title',
        artist: 'Artist',
        lrclibService: _ThrowingLrclib(),
      );
      expect(resolved, isNull);
      expect(LrcParser.hasCachedLyrics(songId: 720004), isTrue);
      expect(LrcParser.getCachedLyrics(songId: 720004), isNull);
    });

    test('without title metadata the online lookup is skipped', () async {
      final resolved = await LrcParser.resolveLyrics(
        '/missing/untitled.mp3',
        songId: 720005,
      );
      expect(resolved, isNull);
      expect(LrcParser.hasCachedLyrics(songId: 720005), isFalse);
    });

    test('saturated caches are swept and evicted on a new resolve', () async {
      for (int i = 0; i < 51; i++) {
        LrcParser.cacheLyricsResult(null, songId: 730000 + i);
      }
      final fake = _FakeLrclib()..result = _syncedResult();
      final resolved = await LrcParser.resolveLyrics(
        '/missing/saturated.mp3',
        songId: 730100,
        trackTitle: 'Title',
        artist: 'Artist',
        lrclibService: fake,
      );
      expect(resolved, isNotNull);
      expect(LrcParser.hasCachedLyrics(songId: 730100), isTrue);
      expect(LrcParser.hasCachedLyrics(songId: 730000), isFalse);
    });

    test('concurrent resolves for one song share a single in-flight future',
        () async {
      final fake = _DeferredLrclib();
      const path = '/missing/dedup.mp3';
      final first = LrcParser.resolveLyrics(
        path,
        songId: 720006,
        trackTitle: 'Title',
        artist: 'Artist',
        lrclibService: fake,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final second = LrcParser.resolveLyrics(
        path,
        songId: 720006,
        trackTitle: 'Title',
        artist: 'Artist',
        lrclibService: fake,
      );
      expect(fake.calls, 1);

      fake.completer.complete(_syncedResult());
      final firstResult = await first;
      final secondResult = await second;
      expect(firstResult, isNotNull);
      expect(identical(firstResult, secondResult), isTrue);
    });
  });
}
