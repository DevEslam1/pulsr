import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';

void main() {
  group('AudioFormats Tests', () {
    test('Standard and DSD audio extensions are supported', () {
      final validFormats = [
        'mp3',
        'm4a',
        'aac',
        'flac',
        'wav',
        'ogg',
        'opus',
        'mka',
        'dsf',
        'dff'
      ];
      for (final ext in validFormats) {
        expect(AudioFormats.isSupportedExtension(ext), isTrue,
            reason: '$ext should be supported');
        expect(AudioFormats.isSupportedExtension('music/track.$ext'), isTrue,
            reason: 'track.$ext should be supported');
      }
    });

    test('Unsupported or proprietary formats are flagged as unsupported', () {
      final unsupportedFormats = ['wma'];
      for (final ext in unsupportedFormats) {
        expect(AudioFormats.isSupportedExtension(ext), isFalse,
            reason: '$ext should not be scanned');
        expect(AudioFormats.unsupportedExtensions.contains(ext), isTrue);
      }
    });

    test('extractExtension handles all edge cases exhaustively', () {
      // URIs and query parameters / fragments
      expect(
          AudioFormats.extractExtension(
              'content://media/external/audio/media/123.flac?param=1#anchor'),
          'flac');
      expect(
          AudioFormats.extractExtension(
              'https://example.com/audio/song.mp3?token=abc'),
          'mp3');

      // Standard paths and casing
      expect(
          AudioFormats.extractExtension('/storage/emulated/0/Music/song.MP3'),
          'mp3');
      expect(
          AudioFormats.extractExtension(
              r'C:\Users\Music\Album\01 - Track.FLAC'),
          'flac');

      // Multi-dot filenames
      expect(
          AudioFormats.extractExtension(
              '/storage/emulated/0/Music/song.part1.flac'),
          'flac');
      expect(AudioFormats.extractExtension('artist.feat.guest - track.01.m4a'),
          'm4a');

      // Local files with '#' and '?' in filenames (must preserve extension)
      expect(AudioFormats.extractExtension('Track #1.mp3'), 'mp3');
      expect(AudioFormats.extractExtension('Symphony #5.flac'), 'flac');
      expect(
          AudioFormats.extractExtension('/storage/emulated/0/Music/Track #1.mp3'),
          'mp3');
      expect(
          AudioFormats.extractExtension(
              r'C:\Users\Music\Album #2\01 - Track #1.flac'),
          'flac');
      expect(AudioFormats.extractExtension('Song with ? in name.ogg'), 'ogg');
      expect(
          AudioFormats.extractExtension(
              'file:///storage/emulated/0/Music/Track%20#1.mp3'),
          'mp3');
      expect(
          AudioFormats.isSupportedExtension('Track #1.mp3'),
          isTrue);
      expect(
          AudioFormats.isSupportedExtension('/storage/Music/Symphony #5.flac'),
          isTrue);

      // HTTP Stream URLs with query parameters
      expect(
          AudioFormats.extractExtension(
              'https://stream.example.com/live.aac?bitrate=320&token=xyz#play'),
          'aac');
      expect(
          AudioFormats.extractExtension(
              'http://radio.example.org:8000/stream?format=mp3'),
          '');

      // Extensionless paths and filenames (B9 regression tests)
      expect(
          AudioFormats.extractExtension('/storage/emulated/0/Music/song'), '');
      expect(AudioFormats.extractExtension(r'C:\Music\song'), '');
      expect(AudioFormats.extractExtension('song'), '');
      expect(AudioFormats.extractExtension('my_track_name'), '');
      expect(AudioFormats.extractExtension('Makefile'), '');
      expect(AudioFormats.extractExtension(''), '');
      expect(AudioFormats.extractExtension('/path/to/folder/'), '');
      expect(AudioFormats.extractExtension(r'C:\path\to\folder\'), '');

      // Dotfiles
      expect(AudioFormats.extractExtension('.gitignore'), '');
      expect(AudioFormats.extractExtension('.nomedia'), '');
      expect(AudioFormats.extractExtension('/Music/.nomedia'), '');
      expect(AudioFormats.extractExtension('.mp3'), 'mp3');
      expect(AudioFormats.extractExtension('.flac'), 'flac');

      // Bare extensions without leading dot
      expect(AudioFormats.extractExtension('mp3'), 'mp3');
      expect(AudioFormats.extractExtension('FLAC'), 'flac');
      expect(AudioFormats.extractExtension('wav'), 'wav');
      expect(AudioFormats.extractExtension('wma'), 'wma');
      expect(AudioFormats.extractExtension('unknown_ext'), '');

      // Validation via isSupportedExtension
      expect(AudioFormats.isSupportedExtension('.mp3'), isTrue);
      expect(AudioFormats.isSupportedExtension('mp3'), isTrue);
      expect(AudioFormats.isSupportedExtension('/path/to/.gitignore'), isFalse);
      expect(AudioFormats.isSupportedExtension('/path/to/extensionless_file'),
          isFalse);
      expect(AudioFormats.isSupportedExtension('extensionless_file'), isFalse);
    });

    test('extractExtension rejects dot-prefixed hidden files, .trashed-*, and ._* files', () {
      expect(AudioFormats.extractExtension('.trashed-12345-track.mp3'), '');
      expect(AudioFormats.extractExtension('/storage/emulated/0/Music/.trashed-9876.flac'), '');
      expect(AudioFormats.extractExtension('._track.mp3'), '');
      expect(AudioFormats.extractExtension('/Volumes/Drive/._song.flac'), '');
      expect(AudioFormats.extractExtension('/storage/Music/.hidden_track.mp3'), '');
      expect(AudioFormats.extractExtension(r'C:\Music\.dotfile.wav'), '');
      expect(AudioFormats.extractExtension('/path/to/.mp3'), '');

      // But bare extensions without path separator are still valid extension queries
      expect(AudioFormats.extractExtension('.mp3'), 'mp3');
      expect(AudioFormats.extractExtension('.flac'), 'flac');
    });
  });
}
