import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/cue_parser.dart';

void main() {
  group('CueParser Tests', () {
    test('Parses valid CUE sheet with multiple chapters and timestamps', () {
      const cueContent = '''
TITLE "Sample Audiobook"
PERFORMER "Author Name"
FILE "audiobook.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Prologue - The Beginning"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Chapter 1 - Into The Woods"
    INDEX 01 04:30:00
  TRACK 03 AUDIO
    TITLE "Chapter 2 - Discovery"
    INDEX 01 12:45:50
''';

      final chapters = CueParser.parse(cueContent);

      expect(chapters.length, equals(3));
      expect(chapters[0].index, equals(1));
      expect(chapters[0].title, equals('Prologue - The Beginning'));
      expect(chapters[0].start, equals(Duration.zero));
      expect(chapters[0].end, equals(const Duration(minutes: 4, seconds: 30)));

      expect(chapters[1].index, equals(2));
      expect(chapters[1].title, equals('Chapter 1 - Into The Woods'));
      expect(chapters[1].start, equals(const Duration(minutes: 4, seconds: 30)));
      expect(chapters[1].end, isNotNull);

      expect(chapters[2].index, equals(3));
      expect(chapters[2].title, equals('Chapter 2 - Discovery'));
      expect(chapters[2].end, isNull);
    });

    test('Handles empty or invalid CUE gracefully', () {
      final empty = CueParser.parse('');
      expect(empty, isEmpty);

      final noTracks = CueParser.parse('TITLE "Something"\nPERFORMER "Nobody"');
      expect(noTracks, isEmpty);
    });
  });
}
