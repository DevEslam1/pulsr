// Edge-case and malformed-input coverage for CueParser (text sheets, embedded
// FLAC Vorbis/CUESHEET blocks and embedded WAV cue chunks).
// Basic text parsing already lives in test/cue_parser_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/cue_parser.dart';

List<int> _le32(int value) => <int>[
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

void _writeLe32At(List<int> target, int offset, int value) {
  target[offset] = value & 0xFF;
  target[offset + 1] = (value >> 8) & 0xFF;
  target[offset + 2] = (value >> 16) & 0xFF;
  target[offset + 3] = (value >> 24) & 0xFF;
}

void _writeBe64At(List<int> target, int offset, int value) {
  for (int i = 7; i >= 0; i--) {
    target[offset + i] = value & 0xFF;
    value >>= 8;
  }
}

/// FLAC metadata block with a Vorbis comment holding `CUESHEET=<cue>`.
List<int> _flacWithVorbisCue(String cue, {bool includeStreamInfo = false}) {
  final vendor = utf8.encode('unit-test');
  final comment = utf8.encode('CUESHEET=$cue');
  final vorbis = <int>[];
  vorbis.addAll(_le32(vendor.length));
  vorbis.addAll(vendor);
  vorbis.addAll(_le32(1));
  vorbis.addAll(_le32(comment.length));
  vorbis.addAll(comment);

  final out = <int>[...utf8.encode('fLaC')];
  if (includeStreamInfo) {
    // Non-last STREAMINFO block (type 0) that must be skipped.
    const streamInfoLength = 34;
    out.add(0x00);
    out.addAll(<int>[
      (streamInfoLength >> 16) & 0xFF,
      (streamInfoLength >> 8) & 0xFF,
      streamInfoLength & 0xFF,
    ]);
    out.addAll(List<int>.filled(streamInfoLength, 0));
  }
  out.add(0x80 | 4); // last block, type 4 (VORBIS_COMMENT)
  out.addAll(<int>[
    (vorbis.length >> 16) & 0xFF,
    (vorbis.length >> 8) & 0xFF,
    vorbis.length & 0xFF,
  ]);
  out.addAll(vorbis);
  return out;
}

/// FLAC metadata block with a raw CUESHEET (type 5) payload.
List<int> _flacWithCuesheetBlock(List<int> cuesheetData) {
  final out = <int>[...utf8.encode('fLaC')];
  out.add(0x80 | 5);
  out.addAll(<int>[
    (cuesheetData.length >> 16) & 0xFF,
    (cuesheetData.length >> 8) & 0xFF,
    cuesheetData.length & 0xFF,
  ]);
  out.addAll(cuesheetData);
  return out;
}

/// CUESHEET metadata payload: 396-byte header + 36-byte track headers + index
/// points (12 bytes each).
List<int> _cuesheetPayload(
  List<({int number, int offsetSamples, List<int> pointOffsets})> tracks,
) {
  final bytes = <int>[...List<int>.filled(396, 0)];
  bytes[395] = tracks.length;
  for (final track in tracks) {
    final header = List<int>.filled(36, 0);
    _writeBe64At(header, 0, track.offsetSamples);
    header[8] = track.number;
    header[35] = track.pointOffsets.length;
    bytes.addAll(header);
    for (final point in track.pointOffsets) {
      final indexPoint = List<int>.filled(12, 0);
      _writeBe64At(indexPoint, 0, point);
      indexPoint[8] = 1; // INDEX 01
      bytes.addAll(indexPoint);
    }
  }
  return bytes;
}

List<int> _wavCueChunk(List<int> sampleOffsets) {
  final bytes = <int>[..._le32(sampleOffsets.length)];
  for (final offset in sampleOffsets) {
    final point = List<int>.filled(24, 0);
    _writeLe32At(point, 20, offset);
    bytes.addAll(point);
  }
  return bytes;
}

List<int> _wavBytes({
  required int sampleRate,
  required List<int> cueSampleOffsets,
  bool withOddChunk = false,
}) {
  final out = <int>[
    ...ascii.encode('RIFF'),
    ..._le32(0),
    ...ascii.encode('WAVE')
  ];
  out.addAll(ascii.encode('fmt '));
  out.addAll(_le32(16));
  final fmt = List<int>.filled(16, 0);
  _writeLe32At(fmt, 4, sampleRate);
  out.addAll(fmt);

  if (withOddChunk) {
    out.addAll(ascii.encode('LIST'));
    out.addAll(_le32(3));
    out.addAll(<int>[1, 2, 3, 0]); // data + pad byte
  }

  final cue = _wavCueChunk(cueSampleOffsets);
  out.addAll(ascii.encode('cue '));
  out.addAll(_le32(cue.length));
  out.addAll(cue);
  return out;
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('pulsr_cue_edge_');
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  group('CueParser.parse edge cases', () {
    test('track without TITLE falls back to a generated chapter name', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    INDEX 01 01:00:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.length, 2);
      expect(chapters[0].title, 'Chapter 1');
      expect(chapters[1].title, 'Chapter 2');
    });

    test('track without INDEX is skipped', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "No index"
  TRACK 02 AUDIO
    TITLE "Has index"
    INDEX 01 00:30:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.length, 1);
      expect(chapters.single.index, 2);
      expect(chapters.single.title, 'Has index');
    });

    test('CD frames convert to milliseconds with rounding', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    INDEX 01 00:00:37
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.single.start, const Duration(milliseconds: 493));
    });

    test('INDEX 00 alone is not treated as a start marker', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Pregap only"
    INDEX 00 00:05:00
''';
      expect(CueParser.parse(cue), isEmpty);
    });

    test('unquoted TITLE is parsed and whitespace-trimmed', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE   Chapter Without Quotes   
    INDEX 01 00:00:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.single.title, 'Chapter Without Quotes');
    });

    test('a header TITLE before the first TRACK is ignored', () {
      const cue = '''
TITLE "Album Name"
PERFORMER "Narrator"
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    INDEX 01 00:00:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.single.title, 'Chapter 1');
    });

    test('the last TITLE inside a track wins', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "First"
    TITLE "Second"
    INDEX 01 00:00:00
''';
      expect(CueParser.parse(cue).single.title, 'Second');
    });

    test('an overflowing track number falls back to the running count', () {
      final cue = '''
FILE "book.mp3" MP3
  TRACK 99999999999999999999999 AUDIO
    TITLE "Huge"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Normal"
    INDEX 01 00:10:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.length, 2);
      expect(chapters[0].index, 1);
      expect(chapters[1].index, 2);
    });

    test('CRLF line endings and blank lines are tolerated', () {
      const cue =
          'FILE "book.mp3" MP3\r\n\r\n  TRACK 01 AUDIO\r\n    TITLE "Windows"\r\n    INDEX 01 00:01:00\r\n';
      final chapters = CueParser.parse(cue);
      expect(chapters.single.title, 'Windows');
      expect(chapters.single.start, const Duration(seconds: 1));
    });

    test('track numbers may be non-sequential and unsorted', () {
      const cue = '''
FILE "book.mp3" MP3
  TRACK 05 AUDIO
    TITLE "Later track listed first"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Earlier track listed second"
    INDEX 01 00:05:00
''';
      final chapters = CueParser.parse(cue);
      expect(chapters.map((c) => c.index), [5, 2]);
      expect(chapters[0].end, const Duration(seconds: 5));
      expect(chapters[1].end, isNull);
    });
  });

  group('CueParser.findAndParseCue external .cue', () {
    test('parses a sibling .cue file next to the audio file', () async {
      final audio = writeFile('book.mp3', utf8.encode('not really audio'));
      File('${audio.path.substring(0, audio.path.lastIndexOf('.'))}.cue')
          .writeAsStringSync('''
FILE "book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Sibling chapter"
    INDEX 01 00:00:00
''');
      final chapters = await CueParser.findAndParseCue(audio.path);
      expect(chapters.single.title, 'Sibling chapter');
    });

    test('returns empty for a path without extension', () async {
      final file = writeFile('noextension', utf8.encode('x'));
      expect(await CueParser.findAndParseCue(file.path), isEmpty);
    });

    test('returns empty when neither sibling nor embedded cue exists',
        () async {
      final audio = writeFile('silent.mp3', utf8.encode('mp3'));
      expect(await CueParser.findAndParseCue(audio.path), isEmpty);
    });

    test('returns empty for a fully missing path', () async {
      expect(await CueParser.findAndParseCue('Z:/definitely/missing.mp3'),
          isEmpty);
    });
  });

  group('CueParser embedded FLAC', () {
    test('extracts a CUESHEET Vorbis comment', () async {
      const cue = '''
FILE "album.flac" FLAC
  TRACK 01 AUDIO
    TITLE "Embedded"
    INDEX 01 00:00:00
''';
      final file = writeFile('vorbis.flac', _flacWithVorbisCue(cue));
      final chapters = await CueParser.findAndParseCue(file.path);
      expect(chapters.single.title, 'Embedded');
    });

    test('skips a non-last STREAMINFO block before the Vorbis comment',
        () async {
      const cue = '''
FILE "album.flac" FLAC
  TRACK 01 AUDIO
    INDEX 01 00:00:00
''';
      final file = writeFile(
        'streaminfo.flac',
        _flacWithVorbisCue(cue, includeStreamInfo: true),
      );
      final extracted = await CueParser.extractEmbeddedCueSheet(file.path);
      expect(extracted, isNotNull);
      expect(CueParser.parse(extracted!).single.title, 'Chapter 1');
    });

    test('rejects a Vorbis comment shorter than its own header', () async {
      // 4 bytes of data are not enough for the vendor-length prefix.
      final file = writeFile('shortvorbis.flac', <int>[
        ...utf8.encode('fLaC'),
        0x80 | 4,
        0,
        0,
        4,
        1,
        2,
        3,
        4,
      ]);
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });

    test('parses a CUESHEET metadata block', () async {
      final payload = _cuesheetPayload([
        (number: 1, offsetSamples: 0, pointOffsets: [0]),
        (number: 2, offsetSamples: 11907000, pointOffsets: [0]),
      ]);
      final file = writeFile('cuesheet.flac', _flacWithCuesheetBlock(payload));
      final chapters = await CueParser.findAndParseCue(file.path);
      expect(chapters.length, 2);
      expect(chapters[0].index, 1);
      expect(chapters[0].start, Duration.zero);
      expect(chapters[1].index, 2);
      expect(chapters[1].start, const Duration(minutes: 4, seconds: 30));
      expect(chapters[0].end, chapters[1].start);
    });

    test('CUESHEET lead-out track (170) is skipped', () async {
      final payload = _cuesheetPayload([
        (number: 1, offsetSamples: 0, pointOffsets: [0]),
        (number: 170, offsetSamples: 0, pointOffsets: [0]),
      ]);
      final file = writeFile('leadout.flac', _flacWithCuesheetBlock(payload));
      final chapters = await CueParser.findAndParseCue(file.path);
      expect(chapters.length, 1);
      expect(chapters.single.index, 1);
    });

    test('CUESHEET with zero tracks yields no cue text', () async {
      final file = writeFile(
        'emptysheet.flac',
        _flacWithCuesheetBlock(List<int>.filled(396, 0)),
      );
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });

    test('CUESHEET shorter than the fixed header is rejected', () async {
      final file = writeFile(
        'tinycuesheet.flac',
        _flacWithCuesheetBlock(List<int>.filled(10, 0)),
      );
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });

    test('a track with zero index points produces no chapter', () async {
      final payload = _cuesheetPayload([
        (number: 1, offsetSamples: 0, pointOffsets: const []),
      ]);
      final extracted = await CueParser.extractEmbeddedCueSheet(
        writeFile('noindex.flac', _flacWithCuesheetBlock(payload)).path,
      );
      expect(extracted, contains('TRACK 01 AUDIO'));
      expect(CueParser.parse(extracted!), isEmpty);
    });

    test('non-FLAC magic and truncated headers return null', () async {
      final bad = writeFile('bad.flac', utf8.encode('NOPE this is not flac'));
      expect(await CueParser.extractEmbeddedCueSheet(bad.path), isNull);

      final tiny = writeFile('tiny.flac', <int>[0x66, 0x4C]);
      expect(await CueParser.extractEmbeddedCueSheet(tiny.path), isNull);
    });

    test('unknown audio extensions have no embedded parser', () async {
      final file = writeFile('audio.ogg', utf8.encode('OggS'));
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });
  });

  group('CueParser embedded WAV', () {
    test('extracts a cue chunk using the fmt sample rate', () async {
      // 48000 samples at 48 kHz = exactly one second = 75 CD frames.
      final file = writeFile(
        'cue.wav',
        _wavBytes(sampleRate: 48000, cueSampleOffsets: [48000]),
      );
      final extracted = await CueParser.extractEmbeddedCueSheet(file.path);
      expect(extracted, isNotNull);
      expect(extracted, contains('INDEX 01 00:01:00'));

      final chapters = await CueParser.findAndParseCue(file.path);
      expect(chapters.single.start, const Duration(seconds: 1));
    });

    test('odd-sized chunks are padded during the scan', () async {
      final file = writeFile(
        'oddchunk.wav',
        _wavBytes(
          sampleRate: 44100,
          cueSampleOffsets: [44100, 88200],
          withOddChunk: true,
        ),
      );
      final chapters = await CueParser.findAndParseCue(file.path);
      expect(chapters.length, 2);
      expect(chapters[0].start, const Duration(seconds: 1));
      expect(chapters[1].start, const Duration(seconds: 2));
    });

    test('a cue chunk with zero points yields null', () async {
      final file = writeFile(
        'zeropoints.wav',
        _wavBytes(sampleRate: 44100, cueSampleOffsets: const []),
      );
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });

    test('bad RIFF/WAVE magic and short files return null', () async {
      final bad = writeFile('bad.wav', utf8.encode('RIFX junk data here'));
      expect(await CueParser.extractEmbeddedCueSheet(bad.path), isNull);

      final tiny = writeFile('tiny.wav', utf8.encode('RIFF'));
      expect(await CueParser.extractEmbeddedCueSheet(tiny.path), isNull);
    });

    test('a non-WAVE RIFF container is rejected', () async {
      final file = writeFile(
        'riffAvi.wav',
        <int>[...ascii.encode('RIFF'), ..._le32(0), ...ascii.encode('AVI ')],
      );
      expect(await CueParser.extractEmbeddedCueSheet(file.path), isNull);
    });
  });
}
