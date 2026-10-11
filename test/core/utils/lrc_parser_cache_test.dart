// test/core/utils/lrc_parser_cache_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

void main() {
  group('metadata sharing a line with a timestamp', () {
    test('keeps the lyric after a leading metadata tag', () {
      final result =
          LrcParser.parseWithMetadata('[ar:Cool Artist][00:12.34]First line');

      expect(result.lines, hasLength(1));
      expect(result.lines.single.text, 'First line');
      expect(result.lines.single.timestamp,
          const Duration(seconds: 12, milliseconds: 340));
      expect(result.metadata['ar'], 'Cool Artist');
    });

    test('handles several chained metadata tags before the timestamp', () {
      final result =
          LrcParser.parseWithMetadata('[ti:Title][al:Album][00:05.00]Hello');

      expect(result.lines, hasLength(1));
      expect(result.lines.single.text, 'Hello');
      expect(result.lines.single.timestamp, const Duration(seconds: 5));
      expect(result.metadata['ti'], 'Title');
      expect(result.metadata['al'], 'Album');
    });

    test('metadata-only lines still produce no lyric', () {
      final result = LrcParser.parseWithMetadata('[ar:Artist]\n[ti:Title]');
      expect(result.lines, isEmpty);
    });
  });

  group('disk cache payload', () {
    test('round-trips words, translation, isVocal and metadata', () {
      final result = LyricsResult(
        source: LyricsSource.lrclib,
        metadata: {'ar': 'Artist', 'ti': 'Title'},
        lines: [
          LyricsLine(
            timestamp: const Duration(seconds: 1),
            text: 'Hello world',
            source: LyricsSource.lrclib,
            words: const [
              WordTimestamp(word: 'Hello', startMs: 1000, endMs: 1400),
              WordTimestamp(word: 'world', startMs: 1400, endMs: 1900),
            ],
            translation: 'Bonjour',
            isVocal: false,
          ),
          LyricsLine(
            timestamp: const Duration(seconds: 5),
            text: 'Instrumental',
            source: LyricsSource.lrclib,
            isVocal: false,
          ),
        ],
      );

      final encoded = LrcParser.encodeDiskCachePayload(result);
      expect(encoded['v'], 2);

      final decoded = jsonDecode(jsonEncode(encoded));
      final restored =
          LrcParser.decodeDiskCachePayload(decoded as Map<String, dynamic>);

      expect(restored, isNotNull);
      expect(restored!.source, LyricsSource.lrclib);
      expect(restored.lines, result.lines,
          reason: 'line equality covers words/translation/isVocal');
      expect(restored.lines.first.words, hasLength(2));
      expect(restored.lines.first.translation, 'Bonjour');
      expect(restored.metadata, result.metadata);
    });

    test('ignores unknown future cache versions', () {
      final restored = LrcParser.decodeDiskCachePayload({
        'v': 99,
        'lines': [
          {'ms': 1, 'text': 'x', 'source': 'none'},
        ],
      });
      expect(restored, isNull);
    });

    test('decodes legacy v1 payloads with safe defaults', () {
      final restored = LrcParser.decodeDiskCachePayload({
        'source': 'externalLrc',
        'lines': [
          {'ms': 500, 'text': 'Legacy', 'source': 'externalLrc'},
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.source, LyricsSource.externalLrc);
      expect(restored.lines.single.text, 'Legacy');
      expect(
          restored.lines.single.timestamp, const Duration(milliseconds: 500));
      expect(restored.lines.single.words, isEmpty);
      expect(restored.lines.single.translation, isNull);
      expect(restored.lines.single.isVocal, isTrue);
      expect(restored.metadata, isEmpty);
    });

    test('tolerates type-corrupt fields instead of throwing', () {
      final restored = LrcParser.decodeDiskCachePayload({
        'v': 2,
        'source': 42,
        'metadata': {'ar': 1, 'ti': 'ok'},
        'lines': [
          {
            'ms': 'soon',
            'text': 7,
            'words': [
              {'w': 'good', 's': 'bad', 'e': 5},
              {'w': '', 's': 1, 'e': 2},
            ],
            'vocal': 'yes',
          },
        ],
      });

      expect(restored, isNotNull);
      expect(restored!.lines.single.text, '');
      expect(restored.lines.single.timestamp, Duration.zero);
      expect(restored.lines.single.words, hasLength(1));
      expect(restored.lines.single.words.single.word, 'good');
      expect(restored.lines.single.isVocal, isTrue);
      expect(restored.metadata, {'ti': 'ok'});
    });
  });
}
