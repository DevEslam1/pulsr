// test/domain/models/value_equality_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/headphone_profile.dart';
import 'package:pulsr/domain/models/lyrics_line.dart';

AudioOutputInfo _baseAudio() => const AudioOutputInfo(
      deviceName: 'USB DAC',
      isUsbDac: true,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: false,
    );

void main() {
  group('AudioOutputInfo full-field equality', () {
    test('identical values are equal with equal hashCodes', () {
      final a = _baseAudio();
      final b = _baseAudio();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('every ignored field breaks equality', () {
      final base = _baseAudio();
      final variants = <String, AudioOutputInfo>{
        'availableDevices': base.copyWith(availableDevices: const [
          AudioDeviceEntry(
            id: 1,
            name: 'Speakers',
            type: 2,
            typeName: 'Built-in',
            isCurrent: true,
          ),
        ]),
        'directFormats': base.copyWith(directFormats: const [
          AudioDirectFormat(
              encoding: 'float', sampleRate: 96000, supported: true),
        ]),
        'btCodecName': base.copyWith(btCodecName: 'LDAC'),
        'btSampleRateHz': base.copyWith(btSampleRateHz: 96000),
        'btBitDepth': base.copyWith(btBitDepth: 24),
        'btLdacQualityMode': base.copyWith(btLdacQualityMode: 3),
        'usbAudioClass': base.copyWith(usbAudioClass: 2),
        'isLeAudio': base.copyWith(isLeAudio: true),
        'bleAudioPresent': base.copyWith(bleAudioPresent: true),
        'btSelectableCodecs':
            base.copyWith(btSelectableCodecs: ['SBC', 'LDAC']),
        'btSupportedCodecs': base.copyWith(btSupportedCodecs: ['LDAC']),
        'btSelectableSampleRates':
            base.copyWith(btSelectableSampleRates: [96000]),
        'btSelectableBitDepths': base.copyWith(btSelectableBitDepths: [24]),
      };

      variants.forEach((name, variant) {
        expect(variant, isNot(equals(base)), reason: '$name must affect ==');
        expect(variant.hashCode, isNot(equals(base.hashCode)),
            reason: '$name must affect hashCode');
      });
    });

    test('btCodecConnected is not silently ignored', () {
      final base = _baseAudio();
      final withCodec = base.copyWith(btCodecConnected: true);
      expect(withCodec, isNot(equals(base)));
    });

    test('AudioDeviceEntry isPreferred and sampleRates affect equality', () {
      const a = AudioDeviceEntry(
        id: 1,
        name: 'Speakers',
        type: 2,
        typeName: 'Built-in',
        isCurrent: true,
      );
      const preferred = AudioDeviceEntry(
        id: 1,
        name: 'Speakers',
        type: 2,
        typeName: 'Built-in',
        isCurrent: true,
        isPreferred: true,
      );
      const otherRates = AudioDeviceEntry(
        id: 1,
        name: 'Speakers',
        type: 2,
        typeName: 'Built-in',
        isCurrent: true,
        sampleRates: [48000],
      );
      expect(a, isNot(equals(preferred)));
      expect(a, isNot(equals(otherRates)));
    });

    test('structurally equal list fields compare by value', () {
      final a = _baseAudio().copyWith(btSelectableCodecs: ['SBC', 'AAC']);
      final b = _baseAudio().copyWith(btSelectableCodecs: ['SBC', 'AAC']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('HeadphoneProfile full-field equality', () {
    const base = HeadphoneProfile(
      id: 'p1',
      name: 'Sony XM5',
      brand: 'Sony',
      model: 'WH-1000XM5',
      category: 'Over-Ear',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );

    test('same id different name is not equal', () {
      final renamed = base.copyWith(name: 'Sony XM5 v2');
      expect(renamed, isNot(equals(base)));
      expect(renamed, isNot(equals(base)));
    });

    test('gains/filters/source changes break equality and hashCode', () {
      expect(base.copyWith(gains: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
          isNot(equals(base)));
      expect(
        base.copyWith(filters: [const EqFilter(frequency: 100, gain: 1)]),
        isNot(equals(base)),
      );
      expect(base.copyWith(source: 'AutoEQ'), isNot(equals(base)));
      expect(
        base.copyWith(preampGain: -3.0).hashCode,
        isNot(equals(base.hashCode)),
      );
    });

    test('structurally equal profiles are equal', () {
      const other = HeadphoneProfile(
        id: 'p1',
        name: 'Sony XM5',
        brand: 'Sony',
        model: 'WH-1000XM5',
        category: 'Over-Ear',
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(other, equals(base));
      expect(other.hashCode, equals(base.hashCode));
    });

    test('fromJson null-guards missing required strings without throwing', () {
      final profile = HeadphoneProfile.fromJson(<String, dynamic>{
        'cat' 'egory': 'Over-Ear',
      });
      expect(profile.id, '');
      expect(profile.name, '');
      expect(profile.brand, '');
      expect(profile.model, '');
      expect(profile.category, 'Over-Ear');
    });
  });

  group('LyricsLine equality includes words', () {
    const line = LyricsLine(
      timestamp: Duration(milliseconds: 1000),
      text: 'hello',
      words: [WordTimestamp(word: 'hel', startMs: 1000, endMs: 1200)],
    );

    test('same scalars but different words are not equal', () {
      const noWords = LyricsLine(
        timestamp: Duration(milliseconds: 1000),
        text: 'hello',
      );
      expect(line, isNot(equals(noWords)));
    });

    test('different word timings break equality', () {
      const shifted = LyricsLine(
        timestamp: Duration(milliseconds: 1000),
        text: 'hello',
        words: [WordTimestamp(word: 'hel', startMs: 1000, endMs: 1400)],
      );
      expect(line, isNot(equals(shifted)));
      expect(line.hashCode, isNot(equals(shifted.hashCode)));
    });

    test('structurally equal lines with words are equal', () {
      const same = LyricsLine(
        timestamp: Duration(milliseconds: 1000),
        text: 'hello',
        words: [WordTimestamp(word: 'hel', startMs: 1000, endMs: 1200)],
      );
      expect(line, equals(same));
      expect(line.hashCode, equals(same.hashCode));
    });
  });
}
