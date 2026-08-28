import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/file_intent_handler.dart';

void main() {
  group('FileIntentHandler YouTube Extraction Tests', () {
    test('extracts raw 11-char video ID', () {
      expect(FileIntentHandler.extractYouTubeVideoId('dQw4w9WgXcQ'),
          'dQw4w9WgXcQ');
      expect(FileIntentHandler.extractYouTubeVideoId('1234567890a'),
          '1234567890a');
    });

    test('extracts standard youtu.be short link', () {
      expect(
        FileIntentHandler.extractYouTubeVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        FileIntentHandler.extractYouTubeVideoId(
            'http://youtu.be/dQw4w9WgXcQ?t=43'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts standard youtube.com watch link', () {
      expect(
        FileIntentHandler.extractYouTubeVideoId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        FileIntentHandler.extractYouTubeVideoId(
            'https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts youtube shorts link', () {
      expect(
        FileIntentHandler.extractYouTubeVideoId(
            'https://youtube.com/shorts/dQw4w9WgXcQ?feature=share'),
        'dQw4w9WgXcQ',
      );
    });

    test(
        'rejects local file paths that happen to be 11 characters or have query-like names',
        () {
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              '/storage/emulated/0/Music/track.mp3'),
          isNull);
      expect(
          FileIntentHandler.extractYouTubeVideoId('C:\\Music\\12345678901.mp3'),
          isNull);
      expect(
          FileIntentHandler.extractYouTubeVideoId(
              'https://example.com/audio.mp3?v=12345678901'),
          isNull);
    });
  });
}
