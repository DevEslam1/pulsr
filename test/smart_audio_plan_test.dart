// test/smart_audio_plan_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/services/smart_audio_plan.dart';

AudioOutputInfo _device({
  String name = 'WH-1000XM5',
  String type = 'bluetooth',
  bool isBluetooth = true,
  bool bitPerfect = false,
}) =>
    AudioOutputInfo(
      deviceName: name,
      isUsbDac: type == 'usb',
      sampleRate: 48000,
      bitDepth: 24,
      isBitPerfectActive: false,
      isBitPerfectSupported: bitPerfect,
      activeDeviceType: type,
      isBluetooth: isBluetooth,
    );

void main() {
  group('resolveSmartAudioPlan', () {
    test('manual mode makes no automatic choices', () {
      final plan = resolveSmartAudioPlan(
        mode: SmartAudioMode.manual,
        device: _device(),
        matchedHeadphoneProfileId: 'sony_wh1000xm5',
      );
      expect(plan.decision, SmartAudioDecision.none);
      expect(plan.preferBitPerfect, isFalse);
      expect(plan.headphoneProfileId, isNull);
    });

    test('bluetooth always takes the DSP path with the matched correction', () {
      final plan = resolveSmartAudioPlan(
        mode: SmartAudioMode.auto,
        device: _device(),
        matchedHeadphoneProfileId: 'sony_wh1000xm5',
        trackIsHiRes: true,
        deviceSupportsBitPerfect: true,
      );
      expect(plan.decision, SmartAudioDecision.dsp);
      expect(plan.headphoneProfileId, 'sony_wh1000xm5');
      expect(plan.preferBitPerfect, isFalse);
    });

    test('hi-res wired with bit-perfect support and no correction -> bit-perfect',
        () {
      final plan = resolveSmartAudioPlan(
        mode: SmartAudioMode.auto,
        device: _device(
            name: 'USB DAC', type: 'usb', isBluetooth: false, bitPerfect: true),
        trackIsHiRes: true,
        deviceSupportsBitPerfect: true,
      );
      expect(plan.decision, SmartAudioDecision.bitPerfect);
      expect(plan.preferBitPerfect, isTrue);
      expect(plan.keepDsp, isFalse);
    });

    test('a correction keeps the DSP path even on a bit-perfect DAC', () {
      final plan = resolveSmartAudioPlan(
        mode: SmartAudioMode.auto,
        device: _device(
            name: 'USB DAC', type: 'usb', isBluetooth: false, bitPerfect: true),
        matchedHeadphoneProfileId: 'sony_wh1000xm5',
        trackIsHiRes: true,
        deviceSupportsBitPerfect: true,
      );
      expect(plan.decision, SmartAudioDecision.dsp);
      expect(plan.preferBitPerfect, isFalse);
    });

    test('a manual profile overrides the auto-matched one', () {
      final plan = resolveSmartAudioPlan(
        mode: SmartAudioMode.auto,
        device: _device(),
        manualHeadphoneProfileId: 'apple_airpods_pro_2',
        matchedHeadphoneProfileId: 'sony_wh1000xm5',
      );
      expect(plan.headphoneProfileId, 'apple_airpods_pro_2');
    });

    test('smartAudioTrackIsHiRes only trusts >48kHz or >16-bit', () {
      expect(smartAudioTrackIsHiRes(), isFalse);
      expect(smartAudioTrackIsHiRes(sampleRate: 44100, bitDepth: 16), isFalse);
      expect(smartAudioTrackIsHiRes(sampleRate: 96000), isTrue);
      expect(smartAudioTrackIsHiRes(bitDepth: 24), isTrue);
    });
  });
}
