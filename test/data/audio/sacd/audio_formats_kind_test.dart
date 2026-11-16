// test/data/audio/sacd/audio_formats_kind_test.dart
//
// Classification tests for the SACD-related additions to [AudioFormats]:
// the container extension set, the `iso` path helper and `kindFor`.

import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';

void main() {
  group('AudioFormats container extensions', () {
    test('iso is a container, never a playable extension', () {
      expect(AudioFormats.containerExtensions, <String>{'iso'});
      expect(AudioFormats.supportedExtensions.contains('iso'), isFalse);
      expect(AudioFormats.isSupportedExtension('disc.iso'), isFalse);
      expect(AudioFormats.isSupportedExtension('/music/disc.ISO'), isFalse);
    });

    test('native decoder tier is unchanged and still excluded', () {
      for (final ext in <String>['ape', 'wv', 'wma', 'tta', 'tak']) {
        expect(AudioFormats.supportedExtensions.contains(ext), isFalse,
            reason: '$ext must stay out of the playable library');
        expect(AudioFormats.unsupportedExtensions.contains(ext), isTrue,
            reason: '$ext must stay in the unsupported tier');
      }
      expect(AudioFormats.unsupportedExtensions.contains('iso'), isFalse);
    });

    test('iso is recognized but needs extraction', () {
      expect(AudioFormats.isRecognizedExtension('disc.iso'), isTrue);
      expect(AudioFormats.isRecognizedExtension('/music/Disc.ISO'), isTrue);
      expect(AudioFormats.isRecognizedExtension('disc.flac'), isTrue);
      expect(AudioFormats.isRecognizedExtension('disc.ape'), isTrue);
      expect(AudioFormats.isRecognizedExtension('disc.txt'), isFalse);
      expect(AudioFormats.isRecognizedExtension('disc'), isFalse);
    });

    test('isSacdIsoPath only matches iso', () {
      expect(AudioFormats.isSacdIsoPath('/storage/disc.iso'), isTrue);
      expect(AudioFormats.isSacdIsoPath('disc.ISO'), isTrue);
      expect(AudioFormats.isSacdIsoPath('iso'), isTrue);
      expect(AudioFormats.isSacdIsoPath('.iso'), isTrue);
      expect(AudioFormats.isSacdIsoPath('disc.flac'), isFalse);
      expect(AudioFormats.isSacdIsoPath('disc.iso.bak'), isFalse);
      expect(AudioFormats.isSacdIsoPath(''), isFalse);
      expect(AudioFormats.isSacdIsoPath('/music/'), isFalse);
    });
  });

  group('AudioFormats.kindFor', () {
    test('classifies every tier', () {
      expect(AudioFormats.kindFor('song.flac'), AudioFormatKind.playable);
      expect(AudioFormats.kindFor('/music/song.MP3'), AudioFormatKind.playable);
      expect(AudioFormats.kindFor('song.dsf'), AudioFormatKind.playable);
      expect(
        AudioFormats.kindFor('song.ape'),
        AudioFormatKind.nativeDecoderRequired,
      );
      expect(
        AudioFormats.kindFor('/music/song.WV'),
        AudioFormatKind.nativeDecoderRequired,
      );
      expect(
        AudioFormats.kindFor('/storage/disc.iso'),
        AudioFormatKind.sacdContainer,
      );
      expect(AudioFormats.kindFor('iso'), AudioFormatKind.sacdContainer);
      expect(AudioFormats.kindFor('.iso'), AudioFormatKind.sacdContainer);
      expect(AudioFormats.kindFor('notes.txt'), AudioFormatKind.unknown);
      expect(AudioFormats.kindFor('song'), AudioFormatKind.unknown);
      expect(AudioFormats.kindFor(''), AudioFormatKind.unknown);
      expect(AudioFormats.kindFor('/music/'), AudioFormatKind.unknown);
      expect(AudioFormats.kindFor('.nomedia'), AudioFormatKind.unknown);
    });
  });
}
