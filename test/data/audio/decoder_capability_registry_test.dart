// test/data/audio/decoder_capability_registry_test.dart
//
// Table-driven guard for the decoder capability registry. The registry is the
// honest answer to "can this build decode format X?", so these tests pin every
// extension the scanner recognizes plus the codec-level cases that the
// extension alone cannot express (ALAC inside .m4a).
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_formats.dart';
import 'package:pulsr/data/audio/decoder_capability_registry.dart';

/// All recognized extensions, straight from the scanner's own sets.
List<String> _allAudioFormatExtensions() => <String>[
      ...AudioFormats.supportedExtensions,
      ...AudioFormats.nativeDecodableExtensions,
      ...AudioFormats.containerExtensions,
    ];

void main() {
  group('coverage of AudioFormats', () {
    test('every recognized extension has a defined capability', () {
      for (final extension in _allAudioFormatExtensions()) {
        final capability = DecoderCapabilityRegistry.lookup(extension);
        expect(capability, isNotNull,
            reason: 'AudioFormats recognizes ".$extension" but '
                'DecoderCapabilityRegistry has no entry for it');
        expect(capability!.extension, extension,
            reason: 'registry entry for ".$extension" is keyed as '
                '"${capability.extension}"');
      }
    });

    test('capabilities carry no duplicate extensions', () {
      final seen = <String>{};
      final duplicates = <String>[];
      for (final capability in DecoderCapabilityRegistry.capabilities) {
        if (!seen.add(capability.extension)) duplicates.add(capability.extension);
      }
      expect(duplicates, isEmpty,
          reason: 'DecoderCapabilityRegistry.capabilities declares '
              '${DecoderCapabilityRegistry.capabilities.length} entries but '
              'repeats: $duplicates');
      expect(seen.length, DecoderCapabilityRegistry.capabilities.length);
    });

    test('every capability is normalized and has a reason code', () {
      for (final capability in DecoderCapabilityRegistry.capabilities) {
        expect(capability.extension, capability.extension.toLowerCase(),
            reason: 'extension "${capability.extension}" must be lower-case');
        expect(capability.extension.startsWith('.'), isFalse,
            reason: 'extension "${capability.extension}" must not keep its dot');
        expect(capability.reasonCode, isNotEmpty,
            reason: '".${capability.extension}" has an empty reason code');
        expect(capability.displayName, isNotEmpty,
            reason: '".${capability.extension}" has no display name');
      }
    });
  });

  group('support table', () {
    const bundled = <String>['flac', 'dsf', 'dff', 'iso'];
    const platform = <String>[
      'wav',
      'aiff',
      'aif',
      'mp3',
      'aac',
      'm4a',
      'alac',
      'ogg',
      'oga',
      'opus',
      'webm',
      'mka',
    ];
    const notBundled = <String>[
      'ape',
      'wv',
      'tta',
      'tak',
      'wma',
      'mpc',
      'mod',
      'it',
      'xm',
      's3m',
    ];

    final expectations = <String, DecoderSupport>{
      for (final extension in bundled) extension: DecoderSupport.bundled,
      for (final extension in platform)
        extension: DecoderSupport.platformProbeRequired,
      for (final extension in notBundled)
        extension: DecoderSupport.notBundled,
    };

    test('each extension reports its declared support', () {
      for (final entry in expectations.entries) {
        expect(DecoderCapabilityRegistry.supportFor(entry.key), entry.value,
            reason: '".${entry.key}" should be ${entry.value.name}');
      }
    });

    test('the three support tiers cover every extension exactly once', () {
      final tiers = <String>[...bundled, ...platform, ...notBundled];
      expect(tiers.toSet().length, tiers.length,
          reason: 'an extension is listed in more than one tier: $tiers');

      final registryKeys = tiers.toSet();
      final recognized = _allAudioFormatExtensions().toSet();
      final missing = recognized.difference(registryKeys);
      expect(missing, isEmpty,
          reason: 'AudioFormats recognizes $missing but the tier table does '
              'not cover it');
      // `alac` is a codec identifier (an ALAC stream can live inside .m4a),
      // not a scanner extension, so it is the one allowed extra key.
      final extra = registryKeys.difference(recognized);
      expect(extra, <String>{'alac'},
          reason: 'the tier table declares formats AudioFormats does not '
              'recognize: $extra');
    });

    test('FLAC, DSD and SACD ISO are bundled', () {
      for (final extension in bundled) {
        expect(DecoderCapabilityRegistry.supportFor(extension),
            DecoderSupport.bundled,
            reason: '".$extension" must be bundled in this build');
      }
    });

    test('ALAC is platformProbeRequired, not bundled', () {
      final capability = DecoderCapabilityRegistry.capabilityFor('alac');
      expect(capability.support, DecoderSupport.platformProbeRequired,
          reason: 'Media3 ships no ALAC decoder, so ALAC cannot be bundled');
      expect(capability.reasonCode, DecoderCapabilityRegistry.reasonNoAlacDecoder,
          reason: 'ALAC must explain itself as '
              '"${DecoderCapabilityRegistry.reasonNoAlacDecoder}"');
    });

    test('native-tier formats are not bundled', () {
      for (final extension in notBundled) {
        final capability = DecoderCapabilityRegistry.capabilityFor(extension);
        expect(capability.support, DecoderSupport.notBundled,
            reason: '".$extension" has no decoder in this build');
        expect(capability.reasonCode, DecoderCapabilityRegistry.reasonNotBundled);
        expect(capability.isPlayable, isFalse,
            reason: '".$extension" must not be offered for playback');
      }
    });
  });

  group('lookup normalization', () {
    test('extensions are case-insensitive and dot-tolerant', () {
      for (final input in <String>['FLAC', '.flac', '  Flac  ', 'a/b/Album.FLAC']) {
        expect(DecoderCapabilityRegistry.supportFor(input), DecoderSupport.bundled,
            reason: '"$input" should resolve to the bundled FLAC entry');
      }
      expect(DecoderCapabilityRegistry.supportFor('DSF'), DecoderSupport.bundled);
      expect(DecoderCapabilityRegistry.supportFor('.APE'), DecoderSupport.notBundled);
    });

    test('MIME types resolve to their extension', () {
      const expectations = <String, DecoderSupport>{
        'audio/flac': DecoderSupport.bundled,
        'audio/x-flac': DecoderSupport.bundled,
        'audio/flac; codecs=flac': DecoderSupport.bundled,
        'audio/mpeg': DecoderSupport.platformProbeRequired,
        'audio/mp4': DecoderSupport.platformProbeRequired,
        'audio/alac': DecoderSupport.platformProbeRequired,
        'audio/x-dsf': DecoderSupport.bundled,
        'audio/x-ape': DecoderSupport.notBundled,
      };
      for (final entry in expectations.entries) {
        expect(DecoderCapabilityRegistry.supportFor(entry.key), entry.value,
            reason: 'MIME "${entry.key}" should resolve to ${entry.value.name}');
      }
    });

    test('unknown extensions fall back to a non-null fails-closed entry', () {
      for (final input in <String>['nope', 'xyz', '', 'audio/nonsense']) {
        final capability = DecoderCapabilityRegistry.capabilityFor(input);
        expect(capability, isNotNull);
        expect(capability.support, DecoderSupport.notBundled,
            reason: '"$input" must fail closed, not be treated as playable');
        expect(capability.reasonCode,
            DecoderCapabilityRegistry.reasonUnknownExtension,
            reason: '"$input" must report an unknown-extension reason');
        expect(DecoderCapabilityRegistry.isPlayable(input), isFalse);
        expect(DecoderCapabilityRegistry.reasonCodeFor(input), isNotNull);
        expect(DecoderCapabilityRegistry.lookup(input), isNull,
            reason: '"$input" is not a registry entry');
      }
    });
  });

  group('isPlayable agreement', () {
    test('isPlayable == (support != notBundled) for every entry', () {
      for (final capability in DecoderCapabilityRegistry.capabilities) {
        final expected = capability.support != DecoderSupport.notBundled;
        expect(DecoderCapabilityRegistry.isPlayable(capability.extension),
            expected,
            reason: '".${capability.extension}" is ${capability.support.name} '
                'but isPlayable returned '
                '${DecoderCapabilityRegistry.isPlayable(capability.extension)}');
        expect(capability.isPlayable, expected);
      }
    });

    test('reasonCodeFor is null only for bundled formats', () {
      for (final capability in DecoderCapabilityRegistry.capabilities) {
        final reason =
            DecoderCapabilityRegistry.reasonCodeFor(capability.extension);
        if (capability.support == DecoderSupport.bundled) {
          expect(reason, isNull,
              reason: 'bundled ".${capability.extension}" needs no reason code');
        } else {
          expect(reason, isNotNull,
              reason: '".${capability.extension}" is '
                  '${capability.support.name} and must explain why');
        }
      }
    });
  });
}
