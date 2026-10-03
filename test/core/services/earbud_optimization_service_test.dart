// test/core/services/earbud_optimization_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/earbud_optimization_service.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';

AudioOutputInfo _info({
  String deviceName = 'Test Device',
  bool isUsbDac = false,
  int sampleRate = 44100,
  int bitDepth = 16,
  bool isBluetooth = false,
  bool isLeAudio = false,
  String? btCodecName,
  int? btSampleRateHz,
  int? btBitDepth,
  bool btCodecConnected = false,
  String? btReason,
}) {
  return AudioOutputInfo(
    deviceName: deviceName,
    isUsbDac: isUsbDac,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
    isBitPerfectActive: false,
    isBluetooth: isBluetooth,
    isLeAudio: isLeAudio,
    btCodecName: btCodecName,
    btSampleRateHz: btSampleRateHz,
    btBitDepth: btBitDepth,
    btCodecConnected: btCodecConnected,
    btReason: btReason,
  );
}

void main() {
  late EarbudOptimizationService service;

  setUp(() {
    service = EarbudOptimizationService();
  });

  group('EarbudCodec', () {
    test('ultra-high-quality flags only the four premium A2DP codecs', () {
      expect(EarbudCodec.ldac.isUltraHighQuality, isTrue);
      expect(EarbudCodec.lhdc.isUltraHighQuality, isTrue);
      expect(EarbudCodec.aptxHd.isUltraHighQuality, isTrue);
      expect(EarbudCodec.aptxAdaptive.isUltraHighQuality, isTrue);
      expect(EarbudCodec.sbc.isUltraHighQuality, isFalse);
      expect(EarbudCodec.aac.isUltraHighQuality, isFalse);
      expect(EarbudCodec.wired.isUltraHighQuality, isFalse);
    });
  });

  group('detect', () {
    test('null output falls back to a safe default route', () {
      final caps = service.detect(null);
      expect(caps.deviceName, 'Default output');
      expect(caps.codec, EarbudCodec.unknown);
      expect(caps.isBluetooth, isFalse);
      expect(caps.sampleRateHz, 44100);
      expect(caps.bitDepth, 16);
      expect(caps.latencyMs, 0);
      expect(caps.isLossyBluetooth, isFalse);
      expect(caps.hasHighLatency, isFalse);
      expect(caps.reverbScale, 1.0);
    });

    test('wired output reports lossless and zero latency', () {
      final caps = service.detect(_info(sampleRate: 48000, bitDepth: 24));
      expect(caps.codec, EarbudCodec.wired);
      expect(caps.isUsbDac, isFalse);
      expect(caps.latencyMs, 0);
      expect(caps.codec.isLossless, isTrue);
      expect(caps.reverbScale, 1.0);
    });

    test('USB DAC output reports the usbDac codec', () {
      final caps = service.detect(_info(isUsbDac: true));
      expect(caps.codec, EarbudCodec.usbDac);
      expect(caps.isUsbDac, isTrue);
    });

    test('bluetooth sample rate/bit depth fall back to generic values', () {
      final caps = service.detect(_info(
        isBluetooth: true,
        sampleRate: 44100,
        bitDepth: 16,
        btCodecName: 'SBC',
      ));
      expect(caps.sampleRateHz, 44100);
      expect(caps.bitDepth, 16);
    });

    test('bluetooth-specific sample rate and bit depth win when present', () {
      final caps = service.detect(_info(
        isBluetooth: true,
        sampleRate: 44100,
        bitDepth: 16,
        btSampleRateHz: 96000,
        btBitDepth: 24,
        btCodecName: 'LDAC',
      ));
      expect(caps.sampleRateHz, 96000);
      expect(caps.bitDepth, 24);
      expect(caps.latencyMs, 250);
      expect(caps.isLeAudio, isFalse);
    });

    test('codec names map to the right family', () {
      EarbudCodec codecFor(String? name) =>
          service.detect(_info(isBluetooth: true, btCodecName: name)).codec;

      expect(codecFor('LDAC'), EarbudCodec.ldac);
      expect(codecFor('LHDC'), EarbudCodec.lhdc);
      expect(codecFor('aptX Adaptive'), EarbudCodec.aptxAdaptive);
      expect(codecFor('aptX HD'), EarbudCodec.aptxHd);
      expect(codecFor('aptX'), EarbudCodec.aptx);
      expect(codecFor('LC3'), EarbudCodec.lc3);
      expect(codecFor('SBC'), EarbudCodec.sbc);
      expect(codecFor('AAC'), EarbudCodec.aac);
      expect(codecFor('Opus'), EarbudCodec.opus);
      expect(codecFor('mystery-codec'), EarbudCodec.unknown);
      expect(codecFor(null), EarbudCodec.unknown);
    });

    test('LE Audio routes keep the LE flag and codec estimate', () {
      final caps = service.detect(_info(
        isBluetooth: true,
        isLeAudio: true,
        btCodecName: 'LC3',
      ));
      expect(caps.isLeAudio, isTrue);
      expect(caps.codec, EarbudCodec.lc3);
      expect(caps.latencyMs, 60);
    });
  });

  group('reverbScale / hasHighLatency', () {
    test('lossy BT under 200ms uses the milder dampening', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'LC3'));
      expect(caps.isLossyBluetooth, isTrue);
      expect(caps.reverbScale, 0.8);
      expect(caps.hasHighLatency, isFalse);
    });

    test('lossy BT at/over 200ms dampens harder', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'SBC'));
      expect(caps.latencyMs, 220);
      expect(caps.reverbScale, 0.65);
      expect(caps.hasHighLatency, isTrue);
    });

    test('unknown BT codec uses the default 180ms estimate', () {
      final caps =
          service.detect(_info(isBluetooth: true, btCodecName: 'weird'));
      expect(caps.latencyMs, 180);
      // Unknown is treated as lossless, so no transient smearing compensation
      // is applied even though the route is Bluetooth.
      expect(caps.isLossyBluetooth, isFalse);
      expect(caps.reverbScale, 1.0);
    });
  });

  group('eqCompensation', () {
    test('non-bluetooth routes get a flat curve', () {
      final gains = service.eqCompensation(service.detect(_info()));
      expect(gains, everyElement(0.0));
    });

    test('lossless bluetooth is left untouched', () {
      const losslessBt = EarbudCapabilities(
        deviceName: 'USB-C headset',
        codec: EarbudCodec.usbDac,
        isBluetooth: true,
        isLeAudio: false,
        isUsbDac: true,
        sampleRateHz: 48000,
        bitDepth: 24,
        latencyMs: 0,
      );
      expect(service.eqCompensation(losslessBt), everyElement(0.0));
    });

    test('SBC lifts 4 kHz and 8 kHz presence bands', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'SBC'));
      final gains = service.eqCompensation(caps);
      expect(gains[7], 0.5);
      expect(gains[8], 0.5);
      expect(gains.where((g) => g != 0).length, 2);
    });

    test('AAC and Opus lift only the 4 kHz presence band', () {
      for (final name in ['AAC', 'Opus']) {
        final caps =
            service.detect(_info(isBluetooth: true, btCodecName: name));
        final gains = service.eqCompensation(caps);
        expect(gains[7], 0.3, reason: name);
        expect(gains.where((g) => g != 0).length, 1, reason: name);
      }
    });

    test('premium codecs are deliberately left flat', () {
      for (final name in ['LDAC', 'LHDC', 'aptX HD', 'aptX Adaptive']) {
        final caps =
            service.detect(_info(isBluetooth: true, btCodecName: name));
        expect(service.eqCompensation(caps), everyElement(0.0), reason: name);
      }
    });
  });

  group('mergeCompensation', () {
    test('adds compensation and clamps to +/-15 dB', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'SBC'));
      final base = List<double>.filled(10, 14.9);
      final merged = service.mergeCompensation(base, caps);
      expect(merged[7], 15.0);
      expect(merged[8], 15.0);
      expect(merged[0], 14.9);
    });

    test('clamps negative sums at -15 dB', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'AAC'));
      final base = List<double>.filled(10, -15.0);
      final merged = service.mergeCompensation(base, caps);
      expect(merged[7], greaterThanOrEqualTo(-15.0));
      expect(merged[7], closeTo(-14.7, 0.0001));
    });

    test('a base longer than the compensation curve pads with zeros', () {
      final caps = service.detect(_info(isBluetooth: true, btCodecName: 'SBC'));
      final base = List<double>.filled(20, 1.0);
      final merged = service.mergeCompensation(base, caps);
      expect(merged.length, 20);
      expect(merged[7], 1.5);
      expect(merged[12], 1.0);
    });
  });

  group('needsBluetoothPermission', () {
    test('false for null and non-bluetooth routes', () {
      expect(EarbudOptimizationService.needsBluetoothPermission(null), isFalse);
      expect(
          EarbudOptimizationService.needsBluetoothPermission(
              _info(isBluetooth: false)),
          isFalse);
    });

    test('false when codec status was read successfully', () {
      expect(
        EarbudOptimizationService.needsBluetoothPermission(_info(
          isBluetooth: true,
          btCodecName: 'SBC',
          btCodecConnected: true,
        )),
        isFalse,
      );
    });

    test('true when permission_required is reported', () {
      expect(
        EarbudOptimizationService.needsBluetoothPermission(_info(
          isBluetooth: true,
          btReason: 'permission_required',
        )),
        isTrue,
      );
    });

    test('true when an A2DP device is present but codec name is empty', () {
      expect(
        EarbudOptimizationService.needsBluetoothPermission(_info(
          isBluetooth: true,
          btCodecName: '',
        )),
        isTrue,
      );
    });

    test('false when disconnected for an unrelated reason with a codec name',
        () {
      expect(
        EarbudOptimizationService.needsBluetoothPermission(_info(
          isBluetooth: true,
          btCodecName: 'AAC',
          btReason: 'proxy_initializing',
        )),
        isFalse,
      );
    });
  });

  group('describe', () {
    test('wired route prints wired/USB and kHz', () {
      final caps = service.detect(
          _info(deviceName: 'USB DAC', isUsbDac: true, sampleRate: 96000));
      expect(service.describe(caps), 'USB DAC • wired/USB • 96 kHz');
    });

    test('unknown bluetooth codec without info says codec unavailable', () {
      final caps = service.detect(_info(deviceName: 'Buds', isBluetooth: true));
      expect(service.describe(caps),
          'Buds • Bluetooth • codec unavailable • ~180 ms');
    });

    test('unknown bluetooth codec with permission missing adds a hint', () {
      final info = _info(
        deviceName: 'Buds',
        isBluetooth: true,
        btReason: 'permission_required',
      );
      final caps = service.detect(info);
      expect(
        service.describe(caps, info),
        'Buds • Bluetooth • grant Nearby-devices permission for codec details • ~180 ms',
      );
    });

    test('known codec prints label, bit depth, rate and latency', () {
      final caps = service.detect(_info(
        deviceName: 'XM5',
        isBluetooth: true,
        btCodecName: 'LDAC',
        btSampleRateHz: 96000,
        btBitDepth: 24,
      ));
      expect(service.describe(caps), 'XM5 • LDAC • 24-bit • 96 kHz • ~250 ms');
    });
  });
}
