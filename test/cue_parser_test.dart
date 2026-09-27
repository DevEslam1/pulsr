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
      expect(
          chapters[1].start, equals(const Duration(minutes: 4, seconds: 30)));
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

    test('Parses multi-file CUE sheet with separate FILE directives', () {
      const cueContent = '''
TITLE "Split Album"
PERFORMER "Artist Name"
FILE "01_intro.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Intro Track"
    INDEX 01 00:00:00
FILE "02_verse.flac" FLAC
  TRACK 02 AUDIO
    TITLE "Verse Track"
    INDEX 01 00:00:00
''';

      final chapters = CueParser.parse(cueContent);

      expect(chapters.length, equals(2));
      expect(chapters[0].fileName, equals('01_intro.wav'));
      expect(chapters[0].title, equals('Intro Track'));
      expect(chapters[0].end, isNull); // Different file, so end is null

      expect(chapters[1].fileName, equals('02_verse.flac'));
      expect(chapters[1].title, equals('Verse Track'));
      expect(chapters[1].end, isNull);
    });

    test('Parses single-file multi-track CUE sheet with contiguous start and end times', () {
      const cueContent = '''
FILE "full_album.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Track 1"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Track 2"
    INDEX 01 03:15:00
  TRACK 03 AUDIO
    TITLE "Track 3"
    INDEX 01 07:45:00
''';
      final chapters = CueParser.parse(cueContent);
      expect(chapters.length, equals(3));
      expect(chapters[0].start, equals(Duration.zero));
      expect(chapters[0].end, equals(const Duration(minutes: 3, seconds: 15)));
      expect(chapters[1].start, equals(const Duration(minutes: 3, seconds: 15)));
      expect(chapters[1].end, equals(const Duration(minutes: 7, seconds: 45)));
      expect(chapters[2].start, equals(const Duration(minutes: 7, seconds: 45)));
      expect(chapters[2].end, isNull);
    });

    test('Ignores data tracks and pregaps gracefully, only capturing AUDIO tracks at INDEX 01', () {
      const cueContent = '''
FILE "cd_image.bin" BINARY
  TRACK 01 MODE1/2352
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    PREGAP 00:02:00
    TITLE "Audio Track After Data"
    INDEX 00 05:00:00
    INDEX 01 05:02:00
''';
      final chapters = CueParser.parse(cueContent);
      expect(chapters.length, equals(1));
      expect(chapters.single.index, equals(2));
      expect(chapters.single.title, equals('Audio Track After Data'));
      expect(chapters.single.start, equals(const Duration(minutes: 5, seconds: 2)));
    });
  });
}
