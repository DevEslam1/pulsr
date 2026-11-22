import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/tap_src_policy.dart';

void main() {
  group('decideTapSrcTargetRate (in-app SRC ahead of the DSP chain)', () {
    test('targets the mixer rate when the route can actually run it', () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [44100, 48000, 96000],
        ),
        48000,
      );
    });

    test('an unverified device rate list does not veto the mixer rate', () {
      // supportedSampleRates is empty whenever the platform gives no per-device
      // list. Absence of evidence is not evidence of incompatibility, and the
      // native tap still disables itself when the rates already match.
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const <int>[],
        ),
        48000,
      );
    });

    test('a device that cannot run the mixer rate converts nothing', () {
      // Converting to a rate the hardware never uses would play the track at
      // the wrong pitch, so an unverifiable target must fall back to the
      // platform path.
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [44100, 88200],
        ),
        0,
      );
    });

    test('negotiation off restores the platform-resample path', () {
      expect(
        decideTapSrcTargetRate(
          enabled: false,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [48000],
        ),
        0,
      );
    });

    test('bit-perfect never resamples: resampled bytes are not identical', () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: true,
          isBluetooth: false,
          deviceSampleRates: const [48000],
        ),
        0,
      );
    });

    test('Bluetooth is excluded — the A2DP link owns its own rate', () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: true,
          deviceSampleRates: const <int>[],
        ),
        0,
      );
    });

    test('an unknown or impossible mixer rate converts nothing', () {
      for (final rate in const [0, -1, 8000 - 1, 768000 + 1]) {
        expect(
          decideTapSrcTargetRate(
            enabled: true,
            nativeSampleRate: rate,
            bitPerfectActive: false,
            isBluetooth: false,
            deviceSampleRates: const <int>[],
          ),
          0,
          reason: 'rate $rate is outside the native tap window',
        );
      }
    });

    test('the native window bounds are the ones the JNI accepts', () {
      expect(kTapSrcMinRate, 8000);
      expect(kTapSrcMaxRate, 768000);
    });
  });

  group('decideTapSrcTargetRate (Remaster)', () {
    test('oversamples the source track rate, not the previous sink rate', () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [44100, 88200, 176400],
          remasterMultiplier: 4,
          trackSampleRate: 44100,
        ),
        176400,
      );
    });

    test('steps down against the DAC rates without exceeding the tap window',
        () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [44100, 88200, 176400],
          remasterMultiplier: 8,
          trackSampleRate: 44100,
        ),
        176400,
      );
    });

    test('an unknown track rate converts nothing instead of using the mixer',
        () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          deviceSampleRates: const [48000, 96000],
          remasterMultiplier: 2,
          trackSampleRate: 0,
        ),
        0,
      );
    });

    test('bit-perfect wins over a requested oversampling factor', () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: true,
          isBluetooth: false,
          deviceSampleRates: const [44100, 88200],
          remasterMultiplier: 2,
          trackSampleRate: 44100,
        ),
        0,
      );
    });

    test('built-in speakers skip Remaster oversampling and stay at mixer rate',
        () {
      expect(
        decideTapSrcTargetRate(
          enabled: true,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          isSpeaker: true,
          deviceSampleRates: const <int>[],
          remasterMultiplier: 4,
          trackSampleRate: 44100,
        ),
        48000,
      );
    });

    test('built-in speakers with negotiation off return 0 even with Remaster',
        () {
      expect(
        decideTapSrcTargetRate(
          enabled: false,
          nativeSampleRate: 48000,
          bitPerfectActive: false,
          isBluetooth: false,
          isSpeaker: true,
          deviceSampleRates: const <int>[],
          remasterMultiplier: 4,
          trackSampleRate: 44100,
        ),
        0,
      );
    });
  });
}
