// test/data/audio/output_verdict_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/domain/models/audio_output_info.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';
import 'package:pulsr/data/audio/live_output_verdict.dart';

void main() {
  group('OutputVerdict Derived Status (Section 5.3)', () {
    test('resolves bit-perfect state when output facts are clean', () {
      final obs = LiveOutputObservation(
        output: const AudioOutputInfo(
          deviceName: 'USB DAC',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: true,
          isBluetooth: false,
          sinkSampleRate: 96000,
          sinkBitDepth: 24,
          integerBypassActive: true,
          floatCarrierDecodesSource: true,
        ),
        directStreamingActive: true,
        streamingSampleRate: 96000,
        streamingBitDepth: 24,
        rawPcmBitDepth: 24,
        rateVerified: true,
        taggedSampleRate: 96000,
        taggedBitDepth: 24,
        codec: 'flac',
        path: 'test.flac',
        bitPerfectOutput: true,
        strictBitPerfect: true,
        bypassDspOnBitPerfect: true,
        dspEffectsActive: false,
        softwareGain: 1.0,
      );

      final OutputVerdict verdict = resolveLiveOutputVerdict(obs);
      // print('TIER: ${verdict.state.tier}, REASON: ${verdict.state.reasonCode}');
      expect(verdict.state.tier, equals(BitPerfectTier.active),
          reason: 'Reason was: ${verdict.state.reasonCode}');
      expect(verdict.isBitPerfect, isTrue);
      expect(verdict.isDirectUsb, isTrue);
      expect(verdict.isLossy, isFalse);
      expect(verdict.dspBypassed, isTrue);
    });

    test('refuses bit-perfect when DSP effects are active', () {
      final obs = LiveOutputObservation(
        output: const AudioOutputInfo(
          deviceName: 'USB DAC',
          isUsbDac: true,
          sampleRate: 96000,
          bitDepth: 24,
          isBitPerfectActive: false,
          isBluetooth: false,
          sinkSampleRate: 96000,
          sinkBitDepth: 24,
        ),
        directStreamingActive: true,
        taggedSampleRate: 96000,
        taggedBitDepth: 24,
        codec: 'flac',
        path: 'test.flac',
        bitPerfectOutput: true,
        strictBitPerfect: false,
        bypassDspOnBitPerfect: false,
        dspEffectsActive: true,
      );

      final OutputVerdict verdict = resolveLiveOutputVerdict(obs);
      expect(verdict.isBitPerfect, isFalse);
    });

  });
}
