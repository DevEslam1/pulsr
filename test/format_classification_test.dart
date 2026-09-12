// test/format_classification_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';

void main() {
  group('AudioFormats three-tier classification', () {
    const platformDecodable = [
      'mp3',
      'm4a',
      'aac',
      'flac',
      'wav',
      'ogg',
      'opus',
      'mka',
      'dsf',
      'dff',
      'webm',
      'aiff',
      'aif',
    ];

    const nativeTier = [
      'ape',
      'wma',
      'tta',
      'tak',
      'wv',
      'mpc',
      'mod',
      'it',
      'xm',
      's3m',
    ];

    test('supported tier contains platform-decodable formats', () {
      for (final ext in platformDecodable) {
        expect(AudioFormats.supportedExtensions.contains(ext), isTrue,
            reason: '$ext must be in supportedExtensions');
      }
    });

    test('native tier contains recognized-but-undecodable formats', () {
      for (final ext in nativeTier) {
        expect(AudioFormats.nativeDecodableExtensions.contains(ext), isTrue,
            reason: '$ext must be in nativeDecodableExtensions');
        expect(AudioFormats.supportedExtensions.contains(ext), isFalse,
            reason: '$ext must not be in supportedExtensions');
      }
    });

    test('unsupported tier folds in the native tier for compatibility', () {
      for (final ext in nativeTier) {
        expect(AudioFormats.unsupportedExtensions.contains(ext), isTrue,
            reason: '$ext must be excluded from the playable library');
      }
    });

    test('isSupportedExtension accepts webm/aiff and rejects native tier', () {
      expect(AudioFormats.isSupportedExtension('webm'), isTrue);
      expect(AudioFormats.isSupportedExtension('aiff'), isTrue);
      expect(AudioFormats.isSupportedExtension('aif'), isTrue);
      expect(AudioFormats.isSupportedExtension('music/track.webm'), isTrue);

      for (final ext in ['ape', 'wma', 'tta']) {
        expect(AudioFormats.isSupportedExtension(ext), isFalse,
            reason: '$ext must not scan into the playable library');
        expect(AudioFormats.isSupportedExtension('music/track.$ext'), isFalse);
      }
    });

    test('requiresNativeDecoder flags the native tier only', () {
      for (final ext in nativeTier) {
        expect(AudioFormats.requiresNativeDecoder(ext), isTrue,
            reason: '$ext requires a native decoder');
        expect(AudioFormats.requiresNativeDecoder('music/track.$ext'), isTrue);
      }

      for (final ext in platformDecodable) {
        expect(AudioFormats.requiresNativeDecoder(ext), isFalse,
            reason: '$ext must not require a native decoder');
      }
      expect(AudioFormats.requiresNativeDecoder('unknown_ext'), isFalse);
      expect(AudioFormats.requiresNativeDecoder(''), isFalse);
    });

    test('isRecognizedExtension accepts supported and native tiers', () {
      for (final ext in [...platformDecodable, ...nativeTier]) {
        expect(AudioFormats.isRecognizedExtension(ext), isTrue,
            reason: '$ext must be recognized');
      }
      expect(AudioFormats.isRecognizedExtension('unknown_ext'), isFalse);
      expect(AudioFormats.isRecognizedExtension('/path/song'), isFalse);
    });

    test('existing supported extensions remain supported (regression)', () {
      for (final ext in platformDecodable) {
        expect(AudioFormats.isSupportedExtension('track.$ext'), isTrue,
            reason: 'regression: $ext must stay supportable');
        expect(AudioFormats.requiresNativeDecoder('track.$ext'), isFalse);
      }
    });
  });
}
