// test/fuzz/parser_fuzz_test.dart
// FIX-B3: Fuzz testing for CueParser, LrcParser, and QueueSlotCodec
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/cue_parser.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/features/player/cubit/queue_slot_codec.dart';

void main() {
  group('Phase B: Parser Fuzz Testing', () {
    final rnd = Random(42);

    String generateRandomString(int length) {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \t\r\n[]()<>-:;,."\'\\/!@#\$%^&*';
      return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
    }

    test('CueParser.parse fuzz test: 10,000 iterations without unhandled exceptions', () {
      final cuePatterns = [
        'FILE "test.mp3" MP3\nTRACK 01 AUDIO\nTITLE "Test"\nINDEX 01 00:00:00',
        'TRACK %d AUDIO\nINDEX 01 %d:%d:%d',
        'FILE "" \nTRACK %s\nTITLE\nINDEX',
        'TITLE "Unclosed quote\nTRACK -1 AUDIO\nINDEX 01 999:999:999',
        'INDEX 01 00:00:75\nINDEX 01 00:00:00',
      ];

      for (int i = 0; i < 10000; i++) {
        String input;
        final mode = i % 4;
        if (mode == 0) {
          // Pure random garbage
          input = generateRandomString(rnd.nextInt(200));
        } else if (mode == 1) {
          // Pattern with random numbers
          final template = cuePatterns[rnd.nextInt(cuePatterns.length)];
          input = template
              .replaceAll('%d', '${rnd.nextInt(1000) - 100}')
              .replaceAll('%s', generateRandomString(10));
        } else if (mode == 2) {
          // Massive lines or blank lines
          input = '${'\n' * rnd.nextInt(50)}FILE "a" MP3\n${generateRandomString(500)}';
        } else {
          // Truncated tokens
          input = 'FILE TRACK TITLE INDEX'.substring(0, rnd.nextInt(22));
        }

        expect(() => CueParser.parse(input), returnsNormally);
      }
    });

    test('LrcParser.parse fuzz test: 10,000 iterations without unhandled exceptions', () {
      final lrcSnippets = [
        '[01:23.45]Normal lyric',
        '[offset: %d]\n[%d:%d.%d]Fuzzed lyric',
        '[-00:02.50]Negative timestamp',
        '[999:99.999]Huge timestamp <00:01.00>word',
        'No timestamp at all',
        '[ar:Artist][ti:Title][offset:-5000]',
        '[:.] Corrupt timestamp',
        '[\uFEFF01:00.00]BOM tagged',
      ];

      for (int i = 0; i < 10000; i++) {
        String input;
        final mode = i % 4;
        if (mode == 0) {
          input = generateRandomString(rnd.nextInt(250));
        } else if (mode == 1) {
          final snippet = lrcSnippets[rnd.nextInt(lrcSnippets.length)];
          input = snippet
              .replaceAll('%d', '${rnd.nextInt(500) - 100}');
        } else if (mode == 2) {
          // Nested brackets and tags
          input = '[[[${rnd.nextInt(100)}:${rnd.nextInt(60)}]]]<${generateRandomString(20)}>';
        } else {
          // Mixed UTF-8 and control characters
          input = '\uFEFF[offset:${rnd.nextInt(10000) - 5000}]\n${generateRandomString(100)}';
        }

        expect(() => LrcParser.parse(input), returnsNormally);
      }
    });

    test('QueueSlotCodec.decodeSlot fuzz test: 2,000 malformed dictionaries safely handled', () {
      for (int i = 0; i < 2000; i++) {
        final malformedMap = <String, dynamic>{
          'songIds': (i % 3 == 0)
              ? generateRandomString(20)
              : (i % 3 == 1)
                  ? [generateRandomString(5), null, 42, -99, 3.14]
                  : List.generate(rnd.nextInt(600), (idx) => idx),
          'currentIndex': (i % 2 == 0) ? 'not_an_int' : rnd.nextInt(500) - 50,
          'positionMs': (i % 2 == 0) ? 'pos' : rnd.nextInt(100000000) - 50000,
          'speed': (i % 2 == 0) ? 'speed' : rnd.nextDouble() * 20.0 - 5.0,
          'onlineSongs': (i % 2 == 0)
              ? 'invalid_list'
              : [
                  {'id': 'not_an_int', 'title': 123},
                  {'id': 10, 'title': 'Valid Title', 'durationMs': 'str_ms'},
                  generateRandomString(10),
                  null,
                ],
        };

        expect(() => QueueSlotCodec.decodeSlot(malformedMap, 500), returnsNormally);
      }
    });
  });
}
