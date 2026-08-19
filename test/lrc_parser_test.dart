// test/lrc_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/lrc_parser.dart';

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
      expect(lines[0].timestamp, const Duration(seconds: 12, milliseconds: 340));

      expect(lines[1].text, 'Second line of lyrics');
      expect(lines[1].timestamp, const Duration(seconds: 15, milliseconds: 670));

      expect(lines[2].text, 'Chorus line');
      expect(lines[2].timestamp, const Duration(minutes: 1, seconds: 2, milliseconds: 890));
    });

    test('parses three-digit millisecond timestamps', () {
      const lrc = '[02:30.500]Precision lyric';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 1);
      expect(lines[0].text, 'Precision lyric');
      expect(lines[0].timestamp, const Duration(minutes: 2, seconds: 30, milliseconds: 500));
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
  });
}
