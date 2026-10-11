// test/core/utils/lrc_parser_encoding_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';

List<int> _utf16Bytes(String text, {required bool bigEndian, bool bom = true}) {
  final bytes = <int>[];
  if (bom) {
    bytes.addAll(bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]);
  }
  for (final unit in text.codeUnits) {
    if (bigEndian) {
      bytes
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    } else {
      bytes
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    }
  }
  return bytes;
}

void main() {
  group('LrcParser.decodeLrcBytes BOM detection', () {
    test('decodes UTF-16LE with BOM including Arabic lyrics', () {
      const text = '[00:10.00]مرحبا بالعالم';
      final decoded =
          LrcParser.decodeLrcBytes(_utf16Bytes(text, bigEndian: false));

      expect(decoded, text);
    });

    test('decodes UTF-16BE with BOM including Arabic lyrics', () {
      const text = '[00:10.00]أهلا وسهلا';
      final decoded =
          LrcParser.decodeLrcBytes(_utf16Bytes(text, bigEndian: true));

      expect(decoded, text);
    });

    test('handles UTF-16 surrogate pairs', () {
      const text = '[00:01.00]🎵 music 🎶';
      final decoded =
          LrcParser.decodeLrcBytes(_utf16Bytes(text, bigEndian: false));

      expect(decoded, text);
    });

    test('strips a UTF-8 BOM', () {
      final bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('[00:01.00]سلام'),
      ];

      final decoded = LrcParser.decodeLrcBytes(bytes);

      expect(decoded, '[00:01.00]سلام');
      expect(decoded.codeUnitAt(0), isNot(0xFEFF));
    });

    test('falls back to latin1 for invalid UTF-8 without a BOM', () {
      final bytes = latin1.encode('[00:08.00]Caf\xE9 line');

      expect(LrcParser.decodeLrcBytes(bytes), '[00:08.00]Café line');
    });
  });

  group('LrcParser.findAndParseLrc encoding', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pulsr_lrc_encoding_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File writeAudio(String name) {
      final audio = File('${tempDir.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync('audio');
      return audio;
    }

    test('parses a UTF-16LE sibling .lrc with synced Arabic lyrics', () async {
      final audio = writeAudio('arabic.mp3');
      File('${tempDir.path}${Platform.pathSeparator}arabic.lrc')
          .writeAsBytesSync(_utf16Bytes(
        '[00:10.00]مرحبا بالعالم\n[00:14.50]كلمات ثانية',
        bigEndian: false,
      ));

      final lines = await LrcParser.findAndParseLrc(audio.path);

      expect(lines, isNotNull);
      expect(lines!.length, 2);
      expect(lines[0].text, 'مرحبا بالعالم');
      expect(lines[0].timestamp, const Duration(seconds: 10));
      expect(lines[1].text, 'كلمات ثانية');
      expect(
          lines[1].timestamp, const Duration(seconds: 14, milliseconds: 500));
    });

    test('parses a UTF-16BE generic lyrics.lrc', () async {
      final audio = writeAudio('generic.mp3');
      File('${tempDir.path}${Platform.pathSeparator}lyrics.lrc')
          .writeAsBytesSync(_utf16Bytes(
        '[00:09.00]مقطع عام',
        bigEndian: true,
      ));

      final lines = await LrcParser.findAndParseLrc(audio.path);

      expect(lines, isNotNull);
      expect(lines!.single.text, 'مقطع عام');
      expect(lines.single.timestamp, const Duration(seconds: 9));
    });
  });
}
