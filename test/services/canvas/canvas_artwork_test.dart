// test/services/canvas/canvas_artwork_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/services/canvas/canvas_artwork.dart';

void main() {
  group('CanvasArtwork normalization & matching', () {
    test('normalizeForMatch removes punctuation, diacritics, and extra spaces',
        () {
      expect(normalizeForMatch('Beyoncé - CRAZY IN LOVE!'),
          'beyonce crazy in love');
      expect(normalizeForMatch('AC/DC'), 'ac dc');
      expect(normalizeForMatch('  Track   (Remastered)  '), 'track remastered');
    });

    test('cleanNoise removes common packaging from titles', () {
      expect(cleanNoise('Blinding Lights (Official Video)'), 'Blinding Lights');
      expect(cleanNoise('Song Title [Official Music Video]'), 'Song Title');
      expect(cleanNoise('Track | 4K Video'), 'Track');
      expect(cleanNoise('My Song (Lyrical)'), 'My Song');
    });

    test('splitArtists handles commas, ampersands, feat, x', () {
      expect(splitArtists('Drake feat. 21 Savage'), ['drake', '21 savage']);
      expect(splitArtists('Jay-Z & Alicia Keys'), ['jay z', 'alicia keys']);
      expect(splitArtists('Marshmello x Bastille'), ['marshmello', 'bastille']);
      expect(splitArtists('Artist A, Artist B with Artist C'),
          ['artist a', 'artist b', 'artist c']);
    });

    test('matches verifies track title, artists and album', () {
      const art = CanvasArtwork(
        videoUrl: 'https://example.com/video.mp4',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        source: 'community',
      );

      // Exact match
      expect(
          art.matches('Blinding Lights', 'The Weeknd', 'After Hours'), isTrue);

      // Match with noise stripped in search query
      expect(
          art.matches(
              'Blinding Lights (Official Video)', 'The Weeknd', 'After Hours'),
          isTrue);

      // Match without knowing album
      expect(art.matches('Blinding Lights', 'The Weeknd', null), isTrue);

      // Rejects different title by same artist
      expect(
          art.matches('Save Your Tears', 'The Weeknd', 'After Hours'), isFalse);

      // Rejects different artist
      expect(art.matches('Blinding Lights', 'Someone Else', 'After Hours'),
          isFalse);
    });
  });
}
