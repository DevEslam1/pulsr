// test/data/audio/output_format_negotiation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/output_format_negotiation.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

void main() {
  const wired = OutputRoute.wired;
  const bt = OutputRoute.bluetooth;

  OutputFormatDecision run({
    int trackRate = 0,
    int trackDepth = 0,
    int reqRate = 0,
    int reqDepth = 0,
    List<int> rates = const [44100, 48000],
    int maxDepth = 16,
    OutputRoute route = wired,
    bool bitPerfect = false,
  }) =>
      negotiateOutputFormat(
        request: OutputFormatRequest(
          trackSampleRate: trackRate,
          trackBitDepth: trackDepth,
          requestedSampleRate: reqRate,
          requestedBitDepth: reqDepth,
        ),
        deviceSampleRates: rates,
        deviceMaxBitDepth: maxDepth,
        route: route,
        bitPerfectActive: bitPerfect,
      );

  group('rate negotiation', () {
    test('auto picks the track native rate when the device supports it', () {
      final d = run(
        trackRate: 192000,
        trackDepth: 24,
        rates: const [44100, 48000, 96000, 192000],
        maxDepth: 24,
      );
      expect(d.sampleRate, 192000);
      expect(d.reason, OutputFormatReason.exactTrackMatch);
      expect(d.isBelowTrackRate, isFalse);
    });

    test('no silent downgrade: highest tier is kept, not a lower one', () {
      // Device advertises a full ladder; the track is 96 kHz. A buggy
      // "maxByOrNull"-style pick could return 48 k or a different tier.
      final d = run(
        trackRate: 96000,
        rates: const [44100, 48000, 88200, 96000],
        maxDepth: 24,
      );
      expect(d.sampleRate, 96000);
      expect(d.isBelowTrackRate, isFalse);
    });

    test('below-track fallback is the highest supported lower tier + reason',
        () {
      final d = run(
        trackRate: 192000,
        rates: const [44100, 48000, 96000],
        maxDepth: 24,
      );
      expect(d.sampleRate, 96000);
      expect(d.reason, OutputFormatReason.deviceRateLimited);
      expect(d.isBelowTrackRate, isTrue);
    });

    test('never exceeds device caps even when asked higher', () {
      final d = run(
        trackRate: 96000,
        reqRate: 384000,
        rates: const [44100, 48000, 96000],
        maxDepth: 24,
      );
      expect(d.sampleRate, 96000);
      expect(d.reason, OutputFormatReason.deviceRateLimited);
    });

    test('explicit request below track native is honoured and flagged', () {
      final d = run(
        trackRate: 96000,
        reqRate: 48000,
        rates: const [44100, 48000, 96000],
        maxDepth: 24,
      );
      expect(d.sampleRate, 48000);
      expect(d.reason, OutputFormatReason.userRequestedBelowTrack);
      expect(d.isBelowTrackRate, isTrue);
    });

    test('auto with unknown track rate falls back to the device best tier', () {
      final d = run(rates: const [44100, 48000, 96000], maxDepth: 24);
      expect(d.sampleRate, 96000);
      expect(d.reason, OutputFormatReason.autoDeviceDefault);
    });

    test('missing device info uses the 44.1/48 k fallback and flags the gap',
        () {
      final d = run(trackRate: 192000, rates: const [], maxDepth: 0);
      expect(d.sampleRate, 48000);
      expect(d.bitDepth, 16);
      expect(d.reason, OutputFormatReason.deviceRateLimited);
      expect(d.isBelowTrackRate, isTrue);
    });

    test('Bluetooth is capped to the lossy transport ceiling', () {
      final d = run(
        trackRate: 192000,
        rates: const [44100, 48000, 88200, 96000, 176400, 192000],
        maxDepth: 24,
        route: bt,
      );
      expect(d.sampleRate, 96000);
      expect(d.isBelowTrackRate, isTrue);
    });
  });

  group('bit-depth negotiation', () {
    test('auto follows the track depth, capped by the device', () {
      expect(run(trackDepth: 24, maxDepth: 32).bitDepth, 24);
      final capped = run(trackDepth: 32, maxDepth: 24);
      expect(capped.bitDepth, 24);
      expect(capped.isBelowTrackDepth, isTrue);
    });

    test('explicit depth is honoured, then clamped to device max', () {
      expect(run(reqDepth: 16, trackDepth: 24, maxDepth: 32).bitDepth, 16);
      expect(run(reqDepth: 32, maxDepth: 16).bitDepth, 16);
    });

    test('invalid device depth defaults to 16-bit', () {
      expect(run(trackDepth: 24, maxDepth: 0).bitDepth, 16);
    });
  });

  group('bit-perfect exclusive path', () {
    test('is not overridden: applied=false with an exclusive reason', () {
      final d = run(
        trackRate: 192000,
        trackDepth: 24,
        rates: const [44100, 48000],
        maxDepth: 16,
        bitPerfect: true,
      );
      expect(d.applied, isFalse);
      expect(d.reason, OutputFormatReason.bitPerfectExclusive);
      // Reports intent (the track's native format), never a device-capped one.
      expect(d.sampleRate, 192000);
      expect(d.bitDepth, 24);
      expect(d.isBelowTrackRate, isFalse);
    });
  });

  group('route classification', () {
    test('maps AudioOutputInfo device classes', () {
      expect(OutputRoute.fromOutputInfo(null), OutputRoute.speaker);
      expect(
        OutputRoute.fromOutputInfo(const AudioOutputInfo(
          deviceName: 'LDAC Buds',
          isUsbDac: false,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: true,
        )),
        OutputRoute.bluetooth,
      );
      expect(
        OutputRoute.fromOutputInfo(const AudioOutputInfo(
          deviceName: 'USB DAC',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: false,
          activeDeviceType: 'usb',
        )),
        OutputRoute.wired,
      );
    });
  });
}
