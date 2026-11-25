// test/core/utils/track_display_info_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/utils/track_display_info.dart';
import '../../helpers/test_song_factory.dart';

void main() {
  group('TrackDisplayInfo.resolve', () {
    test('parses "Artist - Title" when artist is empty', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Mohamed Hamaki - Bahareya',
        rawArtist: '',
      );
      expect(info.title, 'Bahareya');
      expect(info.artist, 'Mohamed Hamaki');
    });

    test('parses "Artist - Title" when artist is whitespace', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Mohamed Hamaki - Bahareya',
        rawArtist: '   ',
      );
      expect(info.title, 'Bahareya');
      expect(info.artist, 'Mohamed Hamaki');
    });

    test('parses "Artist - Title" when artist is "Unknown Artist"', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Mohamed Hamaki - Bahareya',
        rawArtist: 'Unknown Artist',
      );
      expect(info.title, 'Bahareya');
      expect(info.artist, 'Mohamed Hamaki');
    });

    test(
        'parses "Artist - Title" when artist is "unknown artist" (case-insensitive)',
        () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Pink Floyd - Comfortably Numb',
        rawArtist: 'unknown artist',
      );
      expect(info.title, 'Comfortably Numb');
      expect(info.artist, 'Pink Floyd');
    });

    test('parses "Artist - Title" when artist is "<unknown>"', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Queen - Bohemian Rhapsody',
        rawArtist: '<unknown>',
      );
      expect(info.title, 'Bohemian Rhapsody');
      expect(info.artist, 'Queen');
    });

    test('splits on the first " - " when multiple hyphens exist', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Mohamed Hamaki - Bahareya - Live Acoustic',
        rawArtist: 'Unknown Artist',
      );
      expect(info.title, 'Bahareya - Live Acoustic');
      expect(info.artist, 'Mohamed Hamaki');
    });

    test('preserves title and artist when artist is already known', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Mohamed Hamaki - Bahareya',
        rawArtist: 'Mohamed Hamaki',
      );
      expect(info.title, 'Mohamed Hamaki - Bahareya');
      expect(info.artist, 'Mohamed Hamaki');
    });

    test('preserves title and artist when title does not contain " - "', () {
      final info = TrackDisplayInfo.resolve(
        rawTitle: 'Bahareya',
        rawArtist: 'Unknown Artist',
      );
      expect(info.title, 'Bahareya');
      expect(info.artist, 'Unknown Artist');
    });

    test('falls back when parsed artist or title would be empty', () {
      final leadingDash = TrackDisplayInfo.resolve(
        rawTitle: ' - Only Title',
        rawArtist: 'Unknown Artist',
      );
      expect(leadingDash.title, ' - Only Title');
      expect(leadingDash.artist, 'Unknown Artist');

      final trailingDash = TrackDisplayInfo.resolve(
        rawTitle: 'Only Artist - ',
        rawArtist: 'Unknown Artist',
      );
      expect(trailingDash.title, 'Only Artist - ');
      expect(trailingDash.artist, 'Unknown Artist');
    });

    test('resolves from SongsTableData entity via fromSong without mutating it',
        () {
      final song = createTestSong(
        id: 42,
        title: 'Mohamed Hamaki - Bahareya',
        artist: 'Unknown Artist',
      );
      final info = TrackDisplayInfo.fromSong(song);

      expect(info.title, 'Bahareya');
      expect(info.artist, 'Mohamed Hamaki');
      // Entity remains untouched
      expect(song.title, 'Mohamed Hamaki - Bahareya');
      expect(song.artist, 'Unknown Artist');
    });
  });
}
