import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioOutputInfo Phase-4 diagnostics fields', () {
    test('fromMap parses directFormats/usbAudioClass/usbDacLabel', () {
      final info = AudioOutputInfo.fromMap({
        'deviceName': 'Test DAC',
        'isUsbDac': true,
        'sampleRate': 96000,
        'bitDepth': 24,
        'isBitPerfectActive': false,
        'usbAudioClass': 2,
        'usbDacLabel': 'Generic USB Audio',
        'directFormats': [
          {'encoding': 'float', 'sampleRate': 96000, 'supported': true},
          {'encoding': '24', 'sampleRate': 48000, 'supported': false},
        ],
      });
      expect(info.usbAudioClass, 2);
      expect(info.usbDacLabel, 'Generic USB Audio');
      expect(info.directFormats.length, 2);
      expect(info.directFormats.first.encoding, 'float');
      expect(info.directFormats.first.sampleRate, 96000);
      expect(info.directFormats.first.supported, isTrue);
      expect(info.directFormats.last.supported, isFalse);
    });

    test('missing keys fall back to neutral defaults', () {
      final info = AudioOutputInfo.fromMap({
        'deviceName': 'Speaker',
        'isUsbDac': false,
        'sampleRate': 44100,
        'bitDepth': 16,
        'isBitPerfectActive': false,
      });
      expect(info.usbAudioClass, 0);
      expect(info.usbDacLabel, isNull);
      expect(info.directFormats, isEmpty);
    });

    test('copyWith preserves diagnostics fields', () {
      const base = AudioOutputInfo(
        deviceName: 'DAC',
        isUsbDac: true,
        sampleRate: 48000,
        bitDepth: 32,
        isBitPerfectActive: true,
        usbAudioClass: 2,
        usbDacLabel: 'Label',
        directFormats: [
          AudioDirectFormat(encoding: '32', sampleRate: 192000, supported: true)
        ],
      );
      final toggled = base.copyWith(isBitPerfectActive: false);
      expect(toggled.isBitPerfectActive, isFalse);
      expect(toggled.usbAudioClass, 2);
      expect(toggled.usbDacLabel, 'Label');
      expect(toggled.directFormats.length, 1);
      expect(toggled.directFormats.first.supported, isTrue);
    });

    test('toMap/fromMap round-trip keeps diagnostics', () {
      const base = AudioOutputInfo(
        deviceName: 'DAC',
        isUsbDac: true,
        sampleRate: 48000,
        bitDepth: 24,
        isBitPerfectActive: false,
        usbAudioClass: 1,
        usbDacLabel: 'UAC1 Dongle',
        directFormats: [
          AudioDirectFormat(encoding: '24', sampleRate: 96000, supported: true)
        ],
      );
      final restored = AudioOutputInfo.fromMap(base.toMap());
      expect(restored.usbAudioClass, 1);
      expect(restored.usbDacLabel, 'UAC1 Dongle');
      expect(restored.directFormats.first.encoding, '24');
      expect(restored.directFormats.first.supported, isTrue);
    });
  });

  group('AudioOutputInfo system-effect compromise observation', () {
    test('defaults off when the key is absent and round-trips true', () {
      // A platform build that never published the key has not observed the
      // vendor chain, so the model must not invent a compromise.
      final legacy = AudioOutputInfo.fromMap({
        'deviceName': 'Speaker',
        'isUsbDac': false,
        'sampleRate': 44100,
        'bitDepth': 16,
        'isBitPerfectActive': false,
      });
      expect(legacy.systemEffectsCompromised, isFalse);

      const info = AudioOutputInfo(
        deviceName: 'USB DAC',
        isUsbDac: true,
        sampleRate: 96000,
        bitDepth: 24,
        isBitPerfectActive: false,
        systemEffectsCompromised: true,
      );

      expect(info.toMap()['systemEffectsCompromised'], isTrue);
      expect(AudioOutputInfo.fromMap(info.toMap()).systemEffectsCompromised,
          isTrue);
      expect(info.copyWith(bitDepth: 16).systemEffectsCompromised, isTrue);
      expect(
          info
              .copyWith(systemEffectsCompromised: false)
              .systemEffectsCompromised,
          isFalse);

      // Two routes that differ only in whether the OEM chain is compromised
      // are not the same route.
      final clean = info.copyWith(systemEffectsCompromised: false);
      expect(info, isNot(equals(clean)));
      expect(info.hashCode, isNot(equals(clean.hashCode)));
    });
  });
}
