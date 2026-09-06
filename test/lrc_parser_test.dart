// test/lrc_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

void main() {
  group('LrcParser', () {
    test('parses standard two-digit millisecond timestamps', () {
      const lrc = '''
[00:12.34]First line of lyrics
[00:15.67]Second line of lyrics
[01:02.89]Chorus line
''';

      final lines = LrcParser.parse(lrc);

      expect(lines.length, 3);
      expect(lines[0].text, 'First line of lyrics');
      expect(
          lines[0].timestamp, const Duration(seconds: 12, milliseconds: 340));

      expect(lines[1].text, 'Second line of lyrics');
      expect(
          lines[1].timestamp, const Duration(seconds: 15, milliseconds: 670));

      expect(lines[2].text, 'Chorus line');
      expect(lines[2].timestamp,
          const Duration(minutes: 1, seconds: 2, milliseconds: 890));
    });

    test('parses three-digit millisecond timestamps', () {
      const lrc = '[02:30.500]Precision lyric';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 1);
      expect(lines[0].text, 'Precision lyric');
      expect(lines[0].timestamp,
          const Duration(minutes: 2, seconds: 30, milliseconds: 500));
    });

    test('handles empty lines and non-timestamp header tags', () {
      const lrc = '''
[ti:Awesome Song]
[ar:Cool Artist]
[al:Great Album]

[00:05.00]First real lyric
''';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines[0].text, 'First real lyric');
      expect(lines[0].timestamp, const Duration(seconds: 5));
    });

    test('parsePlainText parses non-synced lyrics with Duration.zero timestamp',
        () {
      const plainText = '''
First line of plain lyric
Second line of plain lyric
Third line of plain lyric
''';
      final lines =
          LrcParser.parsePlainText(plainText, source: LyricsSource.embedded);

      expect(lines.length, 3);
      expect(lines[0].text, 'First line of plain lyric');
      expect(lines[0].timestamp, Duration.zero);
      expect(lines[0].source, LyricsSource.embedded);

      expect(lines[1].text, 'Second line of plain lyric');
      expect(lines[1].timestamp, Duration.zero);
      expect(lines[1].source, LyricsSource.embedded);
    });

    test('applies [offset:+500] and [offset:-200] header tags', () {
      const lrcPositive = '''
[offset:+500]
[00:05.00]Positive offset lyric
''';
      final linesPos = LrcParser.parse(lrcPositive);
      expect(linesPos[0].timestamp, const Duration(seconds: 5, milliseconds: 500));

      const lrcNegative = '''
[offset:-500]
[00:05.00]Negative offset lyric
''';
      final linesNeg = LrcParser.parse(lrcNegative);
      expect(linesNeg[0].timestamp, const Duration(seconds: 4, milliseconds: 500));
    });

    test('strips word-level karaoke tags from enhanced LRC', () {
      const lrc = '[00:10.00]<00:10.00>Hello <00:10.50>world <00:11.00>!';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines[0].text, 'Hello world !');
    });

    test('formatToLrc formats lyrics back into standard LRC syntax', () {
      final input = [
        LyricsLine(timestamp: const Duration(seconds: 5, milliseconds: 200), text: 'Line 1'),
        LyricsLine(timestamp: const Duration(minutes: 1, seconds: 12, milliseconds: 450), text: 'Line 2'),
      ];
      final lrc = LrcParser.formatToLrc(input);
      expect(lrc, contains('[00:05.20]Line 1'));
      expect(lrc, contains('[01:12.45]Line 2'));
    });

    test(
        'resolveLyrics returns null for non-existent audio path when no embedded or external lrc',
        () async {
      final result =
          await LrcParser.resolveLyrics('/invalid/path/non_existent.mp3');
      expect(result, isNull);
    });
  });
}
