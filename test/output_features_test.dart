import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/constants/audio_feature_info.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/services/hires_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T2 follow-track rate decision', () {
    test('stays inert when the preference is off', () {
      expect(
        HiResAudioService.followTrackRateToApply(
          trackSampleRate: 96000,
          lastRequestedSampleRate: null,
          isBluetooth: false,
          followTrackEnabled: false,
        ),
        isNull,
      );
    });

    test('applies a new track rate once and de-dupes repeats', () {
      final first = HiResAudioService.followTrackRateToApply(
        trackSampleRate: 44100,
        lastRequestedSampleRate: null,
        isBluetooth: false,
        followTrackEnabled: true,
      );
      expect(first, 44100);

      final repeat = HiResAudioService.followTrackRateToApply(
        trackSampleRate: 44100,
        lastRequestedSampleRate: first,
        isBluetooth: false,
        followTrackEnabled: true,
      );
      expect(repeat, isNull);

      final changed = HiResAudioService.followTrackRateToApply(
        trackSampleRate: 96000,
        lastRequestedSampleRate: first,
        isBluetooth: false,
        followTrackEnabled: true,
      );
      expect(changed, 96000);
    });

    test('skips unknown, zero and out-of-ladder rates', () {
      for (final rate in <int?>[null, 0, -44100, 12345]) {
        expect(
          HiResAudioService.followTrackRateToApply(
            trackSampleRate: rate,
            lastRequestedSampleRate: null,
            isBluetooth: false,
            followTrackEnabled: true,
          ),
          isNull,
          reason: 'rate $rate must not be requested',
        );
      }
    });

    test('never fights AVRCP on Bluetooth', () {
      expect(
        HiResAudioService.followTrackRateToApply(
          trackSampleRate: 96000,
          lastRequestedSampleRate: null,
          isBluetooth: true,
          followTrackEnabled: true,
        ),
        isNull,
      );
    });
  });

  group('T3 strict bit-perfect conflict rules', () {
    const supportedUsbDac = AudioOutputInfo(
      deviceName: 'USB DAC',
      isUsbDac: true,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: true,
      isBitPerfectSupported: true,
    );
    const unsupportedWired = AudioOutputInfo(
      deviceName: 'Wired Headset',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
    );
    const bluetooth = AudioOutputInfo(
      deviceName: 'WH-1000XM5',
      isUsbDac: false,
      sampleRate: 48000,
      bitDepth: 16,
      isBitPerfectActive: false,
      isBluetooth: true,
    );

    test('blocked when no output device / no exclusive support', () {
      expect(AudioConflicts.strictBitPerfectBlockedReason(null), isNotNull);
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(unsupportedWired),
        isNotNull,
      );
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(bluetooth),
        isNotNull,
      );
    });

    test('allowed on a device reporting exclusive bit-perfect support', () {
      expect(
        AudioConflicts.strictBitPerfectBlockedReason(supportedUsbDac),
        isNull,
      );
    });

    test('crossfade is blocked while the bit-perfect bypass is active', () {
      final block = AudioConflicts.crossfadeBlockedByBitPerfect(
        bitPerfectOutput: true,
        bypassDspOnBitPerfect: true,
        device: unsupportedWired,
      );
      expect(block, isNotNull);

      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: unsupportedWired,
        ),
        isNull,
      );
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: false,
          device: unsupportedWired,
        ),
        isNull,
      );
    });

    test('bluetooth never reports the DSP conflict', () {
      expect(
        AudioConflicts.crossfadeBlockedByBitPerfect(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: bluetooth,
        ),
        isNull,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: bluetooth,
        ),
        isNull,
      );
    });

    test('active reason appears only with output + bypass on', () {
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: true,
          bypassDspOnBitPerfect: true,
          device: unsupportedWired,
        ),
        isNotNull,
      );
      expect(
        AudioConflicts.strictBitPerfectActiveReason(
          bitPerfectOutput: false,
          bypassDspOnBitPerfect: true,
          device: unsupportedWired,
        ),
        isNull,
      );
    });
  });

  group('T5 output envelope', () {
    test('keeps only device-reported rates', () {
      final filtered = HiResAudioService.supportedSampleRateOptions(
        deviceSampleRates: const [48000],
        directFormats: const [
          AudioDirectFormat(encoding: '32', sampleRate: 96000, supported: true),
          AudioDirectFormat(
              encoding: '24', sampleRate: 192000, supported: false),
          AudioDirectFormat(
              encoding: '32', sampleRate: 384000, supported: true),
        ],
      );
      expect(filtered, [48000, 96000, 384000]);
    });

    test('exposes 352.8/384/705.6/768 when advertised', () {
      final filtered = HiResAudioService.supportedSampleRateOptions(
        deviceSampleRates: const [],
        directFormats: const [
          AudioDirectFormat(
              encoding: '32', sampleRate: 352800, supported: true),
          AudioDirectFormat(
              encoding: '32', sampleRate: 384000, supported: true),
          AudioDirectFormat(
              encoding: '32', sampleRate: 705600, supported: true),
          AudioDirectFormat(
              encoding: '32', sampleRate: 768000, supported: true),
        ],
      );
      expect(filtered, [352800, 384000, 705600, 768000]);
    });

    test('falls back to 44.1/48 when nothing is reported', () {
      final filtered = HiResAudioService.supportedSampleRateOptions(
        deviceSampleRates: const [],
        directFormats: const [],
      );
      expect(filtered, [44100, 48000]);
    });

    test('ladder/target sets match the honest envelope', () {
      expect(HiResAudioService.envelopeSampleRateLadder, contains(705600));
      expect(HiResAudioService.envelopeSampleRateLadder, contains(768000));
      expect(HiResAudioService.validTargetSampleRates, contains(705600));
      expect(HiResAudioService.validTargetSampleRates, contains(768000));
      expect(HiResAudioService.validTargetBitDepths, {0, 16, 24, 32});
      // 8.24 packed is not representable / not native-reported: never offered.
      expect(HiResAudioService.validTargetBitDepths.contains(8), isFalse);
    });
  });
}
