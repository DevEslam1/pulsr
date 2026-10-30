import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/services/output_path_verdict.dart';

AudioOutputInfo _info({
  bool usb = false,
  bool bitPerfect = false,
  bool bt = false,
  bool le = false,
  String type = 'builtin',
  String? codec,
  int? btRate,
  int? btDepth,
  int? kbps,
}) =>
    AudioOutputInfo(
      deviceName: 'Test',
      isUsbDac: usb,
      sampleRate: 96000,
      bitDepth: 24,
      isBitPerfectActive: bitPerfect,
      activeDeviceType: type,
      isBluetooth: bt,
      isLeAudio: le,
      btCodecName: codec,
      btSampleRateHz: btRate,
      btBitDepth: btDepth,
      btEstimatedBitrateKbps: kbps,
    );

void main() {
  group('OutputPathVerdict', () {
    test('USB + bit-perfect + no DSP is bit-perfect', () {
      final v =
          OutputPathVerdict.of(_info(usb: true, bitPerfect: true, type: 'usb'));
      expect(v.quality, OutputPathQuality.bitPerfect);
      expect(v.detail, '96 kHz / 24-bit');
      expect(v.isLossy, isFalse);
    });

    test('USB with active DSP is lossless but processed', () {
      final v = OutputPathVerdict.of(
          _info(usb: true, bitPerfect: true, type: 'usb'),
          dspActive: true);
      expect(v.quality, OutputPathQuality.losslessProcessed);
    });

    test('Bluetooth reports codec, rate, depth and estimated bitrate', () {
      final v = OutputPathVerdict.of(_info(
        bt: true,
        type: 'bluetooth',
        codec: 'LDAC',
        btRate: 96000,
        btDepth: 24,
        kbps: 990,
      ));
      expect(v.quality, OutputPathQuality.lossyBluetooth);
      expect(v.label, 'LOSSY · LDAC');
      expect(v.detail, '96 kHz / 24-bit · ~990 kbps (est.)');
      expect(v.isLossy, isTrue);
    });

    test('Bluetooth with unknown depth does not invent 16-bit', () {
      final v = OutputPathVerdict.of(
          _info(bt: true, type: 'bluetooth', codec: 'SBC', btRate: 44100));
      expect(v.detail, '44.1 kHz');
      expect(v.detail, isNot(contains('16-bit')));
    });

    test('LE Audio is lossy LC3', () {
      final v = OutputPathVerdict.of(_info(le: true, bt: true, type: 'ble'));
      expect(v.quality, OutputPathQuality.lossyLeAudio);
      expect(v.label, 'LOSSY · LC3');
    });

    test('built-in speaker is a plain device output', () {
      final v = OutputPathVerdict.of(_info());
      expect(v.quality, OutputPathQuality.deviceOutput);
    });
  });
}
