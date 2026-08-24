import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';

void main() {
  group('AudioFormats Tests', () {
    test('Standard audio extensions are supported and playable', () {
      final validFormats = ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'mka'];
      for (final ext in validFormats) {
        expect(AudioFormats.isSupportedExtension(ext), isTrue, reason: '$ext should be supported');
        expect(AudioFormats.isPlayableExtension('music/track.$ext'), isTrue, reason: 'track.$ext should be playable');
      }
    });

    test('Unsupported or proprietary formats are flagged as unsupported', () {
      final unsupportedFormats = ['wma', 'dsf', 'dff'];
      for (final ext in unsupportedFormats) {
        expect(AudioFormats.isSupportedExtension(ext), isFalse, reason: '$ext should not be scanned');
        expect(AudioFormats.unsupportedExtensions.contains(ext), isTrue);
      }
    });

    test('extractExtension handles urls, dotfiles, and query params correctly', () {
      expect(AudioFormats.extractExtension('content://media/external/audio/media/123.flac?param=1'), 'flac');
      expect(AudioFormats.extractExtension('/storage/emulated/0/Music/song.MP3'), 'mp3');
      expect(AudioFormats.extractExtension('/storage/emulated/0/Music/song.part1.flac'), 'flac');
      expect(AudioFormats.extractExtension('.gitignore'), '');
      expect(AudioFormats.extractExtension('/path/to/.mp3'), '');
      expect(AudioFormats.extractExtension('mp3'), 'mp3');
      expect(AudioFormats.isSupportedExtension('mp3'), isTrue);
      expect(AudioFormats.isSupportedExtension('/path/to/.gitignore'), isFalse);
    });
  });
}
