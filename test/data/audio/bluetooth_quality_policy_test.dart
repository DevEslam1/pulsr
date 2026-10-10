// test/data/audio/bluetooth_quality_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bluetooth_quality_policy.dart';

void main() {
  BluetoothQualityPlan run({
    bool hires = true,
    bool dither = false,
    String? codec = 'SBC',
    int? codecRate = 48000,
    int? codecDepth = 16,
    bool leAudio = false,
    int trackRate = 44100,
    int trackDepth = 24,
    List<int> selectableRates = const [44100, 48000],
    List<int> selectableDepths = const [16, 24],
  }) =>
      resolveBluetoothQualityPlan(
        bluetoothHiResEnabled: hires,
        ditherEnabled: dither,
        codecName: codec,
        codecSampleRateHz: codecRate,
        codecBitDepth: codecDepth,
        isLeAudio: leAudio,
        trackSampleRate: trackRate,
        trackBitDepth: trackDepth,
        codecSelectableSampleRates: selectableRates,
        codecSelectableBitDepths: selectableDepths,
      );

  group('codec tier', () {
    test('classifies the common codecs', () {
      expect(bluetoothCodecTier('SBC'), BluetoothCodecTier.low);
      expect(bluetoothCodecTier('AAC'), BluetoothCodecTier.standard);
      expect(bluetoothCodecTier('aptX'), BluetoothCodecTier.standard);
      expect(bluetoothCodecTier('aptX HD'), BluetoothCodecTier.high);
      expect(bluetoothCodecTier('LDAC'), BluetoothCodecTier.high);
      expect(bluetoothCodecTier('LC3'), BluetoothCodecTier.high);
      expect(bluetoothCodecTier('LC3plus'), BluetoothCodecTier.high);
      expect(bluetoothCodecTier(null), BluetoothCodecTier.unknown);
      expect(bluetoothCodecTier(''), BluetoothCodecTier.unknown);
    });

    test('is tolerant of case and separators', () {
      expect(bluetoothCodecTier('aptx-hd'), BluetoothCodecTier.high);
      expect(bluetoothCodecTier('  ldac '), BluetoothCodecTier.high);
    });
  });

  group('dither bit depth', () {
    test('clamps to the native-accepted depths', () {
      expect(sanitizeDitherBitDepth(16), 16);
      expect(sanitizeDitherBitDepth(24), 24);
      expect(sanitizeDitherBitDepth(32), 32);
      expect(sanitizeDitherBitDepth(20), 16);
      expect(sanitizeDitherBitDepth(null), 16);
    });
  });

  group('item 1 - float path', () {
    test('off unless the user opted into BT Hi-Res', () {
      expect(run(hires: false).keepFloatPath, isFalse);
      expect(run(hires: true).keepFloatPath, isTrue);
    });
  });

  group('item 5 - bluetooth dither', () {
    test('never runs unless the user opted in AND enabled dither', () {
      expect(run(hires: true, dither: false).allowBluetoothDither, isFalse);
      expect(run(hires: false, dither: true).allowBluetoothDither, isFalse);
      expect(run(hires: true, dither: true).allowBluetoothDither, isTrue);
    });

    test('targets the codec depth when reported', () {
      expect(run(codecDepth: 24, trackDepth: 16).ditherBitDepth, 24);
      expect(run(codecDepth: 32, trackDepth: 16).ditherBitDepth, 32);
    });

    test('falls back to the track depth when the codec reports nothing', () {
      expect(run(codecDepth: null, trackDepth: 24).ditherBitDepth, 24);
      expect(run(codecDepth: null, trackDepth: 16).ditherBitDepth, 16);
    });
  });

  group('item 3 - codec rate alignment', () {
    test('aligns to the track rate when the codec advertises it', () {
      final p = run(
        trackRate: 44100,
        codecRate: 48000,
        selectableRates: const [44100, 48000],
      );
      expect(p.alignCodecSampleRateTo, 44100);
    });

    test('does not align when the codec cannot switch to the track rate', () {
      final p = run(
        trackRate: 96000,
        codecRate: 48000,
        selectableRates: const [44100, 48000],
      );
      expect(p.alignCodecSampleRateTo, isNull);
    });

    test('does nothing when the codec already runs at the track rate', () {
      final p = run(trackRate: 48000, codecRate: 48000);
      expect(p.alignCodecSampleRateTo, isNull);
    });

    test('does nothing when Hi-Res is off', () {
      final p = run(hires: false, trackRate: 44100, codecRate: 48000);
      expect(p.alignCodecSampleRateTo, isNull);
    });

    test('does nothing when the codec rate is unknown', () {
      final p = run(trackRate: 44100, codecRate: null);
      expect(p.alignCodecSampleRateTo, isNull);
    });
  });

  group('item 4 - LE Audio / high codec', () {
    test('flags LE Audio routes and LC3 codec', () {
      expect(run(leAudio: true).isLeAudio, isTrue);
      expect(run(codec: 'LC3').isLeAudio, isTrue);
      expect(run(codec: 'SBC').isLeAudio, isFalse);
    });

    test('marks high-quality codecs', () {
      expect(run(codec: 'LDAC', codecDepth: 24).isHighQuality, isTrue);
      expect(run(codec: 'SBC').isHighQuality, isFalse);
    });
  });

  group('reason codes', () {
    test('reflect the dominant decision', () {
      expect(run(hires: false).reason, 'bt-hires-off');
      expect(run(codec: 'LDAC', codecRate: 44100).reason,
          'bt-hires-high-codec');
      expect(run(leAudio: true, codecRate: 44100).reason, 'bt-hires-le-audio');
      expect(run(codec: 'SBC', codecRate: 44100).reason, 'bt-hires-lossy-codec');
      expect(
        run(trackRate: 44100, codecRate: 48000).reason,
        'bt-hires-align-rate',
      );
    });
  });
}
