// test/domain/bit_perfect_output_facts_test.dart
//
// One assembler, one verdict. These tests pin the rules that used to live in
// three different call sites: which format wins on the direct route, what
// proves an integer bypass, and which reason a lowered volume reports.
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsr/data/audio/bit_perfect_chain.dart';
import 'package:pulsr/domain/models/bit_perfect_output_facts.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';

/// Direct-USB facts that should verify: the Media3 feed is a mismatched float
/// carrier and the UAC2 sink proves 24-bit raw delivery. Tests flip one fact.
BitPerfectOutputFacts _facts({
  bool requested = true,
  bool sinkActive = true,
  bool directUsbActive = true,
  bool bluetooth = false,
  int sourceSampleRate = 96000,
  int sourceBitDepth = 24,
  int sinkSampleRate = 48000,
  int sinkBitDepth = 32,
  int directStreamSampleRate = 96000,
  int directStreamBitDepth = 24,
  int directRawPcmBitDepth = 24,
  bool floatCarrierDecodesSource = true,
  bool sourceFloat = false,
  bool sinkIntegerBypass = false,
  int halStagesActive = 0,
  bool systemEffectsCompromised = false,
  double? softwareGain = 1.0,
  bool dspProcessing = false,
  bool transportSamplesModified = false,
  bool channelsAltered = false,
  bool rateVerified = true,
  bool isDsdDop = false,
  bool oversamplingActive = false,
  bool pcmToDsdActive = false,
  bool sourceLossy = false,
  bool sourceCodecUnconfirmed = false,
  String? failureReason,
}) =>
    BitPerfectOutputFacts(
      requested: requested,
      sinkActive: sinkActive,
      directUsbActive: directUsbActive,
      bluetooth: bluetooth,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      sinkSampleRate: sinkSampleRate,
      sinkBitDepth: sinkBitDepth,
      directStreamSampleRate: directStreamSampleRate,
      directStreamBitDepth: directStreamBitDepth,
      directRawPcmBitDepth: directRawPcmBitDepth,
      floatCarrierDecodesSource: floatCarrierDecodesSource,
      sourceFloat: sourceFloat,
      sinkIntegerBypass: sinkIntegerBypass,
      halStagesActive: halStagesActive,
      systemEffectsCompromised: systemEffectsCompromised,
      softwareGain: softwareGain,
      dspProcessing: dspProcessing,
      transportSamplesModified: transportSamplesModified,
      channelsAltered: channelsAltered,
      rateVerified: rateVerified,
      isDsdDop: isDsdDop,
      oversamplingActive: oversamplingActive,
      pcmToDsdActive: pcmToDsdActive,
      sourceLossy: sourceLossy,
      sourceCodecUnconfirmed: sourceCodecUnconfirmed,
      failureReason: failureReason,
    );

void main() {
  group('direct UAC2 sink', () {
    test('raw integer delivery verifies even though Media3 runs a float feed',
        () {
      final state = resolveBitPerfectOutput(_facts());
      expect(state.tier, BitPerfectTier.active);
      expect(state.isVerified, isTrue);
      expect(state.reasonCode, isNull);
      expect(state.assessment.verdict, BitPerfectChainVerdict.verified);
      // The direct wire format outranks the 48 kHz Media3 snapshot.
      expect(state.assessment.outputSampleRate, 96000);
      expect(state.assessment.outputBitDepth, 24);
    });

    test('a narrower raw depth is depth truncation, not a float excuse', () {
      final state = resolveBitPerfectOutput(_facts(
        directStreamBitDepth: 16,
        directRawPcmBitDepth: 16,
      ));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'depth_truncated');
      expect(state.assessment.verdict, BitPerfectChainVerdict.depthReduced);
    });

    test('no delivered raw depth cannot verify', () {
      final state = resolveBitPerfectOutput(_facts(directRawPcmBitDepth: 0));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'float_conversion');
    });

    test('a clock that was not read back keeps its own reason', () {
      final state = resolveBitPerfectOutput(_facts(rateVerified: false));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'rate_not_verified');
    });

    test('a rate mismatch is reported as a resample', () {
      final state = resolveBitPerfectOutput(_facts(
        directStreamSampleRate: 48000,
      ));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'rate_mismatch');
      expect(state.assessment.verdict, BitPerfectChainVerdict.resampled);
    });

    test('32-bit integer survives only on the raw direct route', () {
      final state = resolveBitPerfectOutput(_facts(
        sourceBitDepth: 32,
        directStreamBitDepth: 32,
        directRawPcmBitDepth: 32,
      ));
      expect(state.tier, BitPerfectTier.active);
    });

    test('a 32-bit float source can never be called bit-perfect', () {
      final state = resolveBitPerfectOutput(_facts(
        sourceBitDepth: 32,
        sourceFloat: true,
        directStreamBitDepth: 32,
        directRawPcmBitDepth: 32,
      ));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'float_conversion');
    });
  });

  group('Media3 integer bypass', () {
    test('an observed sink bypass verifies without a direct stream', () {
      final state = resolveBitPerfectOutput(_facts(
        directUsbActive: false,
        directRawPcmBitDepth: 0,
        floatCarrierDecodesSource: false,
        sinkSampleRate: 96000,
        sinkBitDepth: 24,
        sinkIntegerBypass: true,
      ));
      expect(state.tier, BitPerfectTier.active);
    });

    test('a float carrier contributes no container depth', () {
      final state = resolveBitPerfectOutput(_facts(
        directUsbActive: false,
        directRawPcmBitDepth: 0,
        floatCarrierDecodesSource: true,
        sinkSampleRate: 96000,
        sinkBitDepth: 32,
        sinkIntegerBypass: true,
      ));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.assessment.verdict, BitPerfectChainVerdict.unverified);
      expect(state.reasonCode, 'depth_unknown');
    });
  });

  group('software gain is a volume fact', () {
    test('a lowered slider is attenuation, never "samples modified"', () {
      final state = resolveBitPerfectOutput(_facts(softwareGain: 0.5));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'digital_volume_attenuation');
      expect(state.reasonCode, isNot('samples_modified'));
    });

    test('an unreadable gain is unknown, not attenuation', () {
      final state = resolveBitPerfectOutput(_facts(softwareGain: null));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'software_gain_unknown');
    });

    test('NaN gain canonicalises to unknown', () {
      final state = resolveBitPerfectOutput(_facts(softwareGain: double.nan));
      expect(state.reasonCode, 'software_gain_unknown');
    });
  });

  group('observed contradictions', () {
    test('an unprovable OEM effect blocks active and is named', () {
      final state =
          resolveBitPerfectOutput(_facts(systemEffectsCompromised: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'system_effect_active');
    });

    test('an app-owned HAL effect blocks active', () {
      final state = resolveBitPerfectOutput(_facts(halStagesActive: 1));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'hal_effect_active');
    });

    test('DSP processing is named as modified samples', () {
      final state = resolveBitPerfectOutput(_facts(dspProcessing: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'samples_modified');
    });

    test('remapped channels are named', () {
      final state = resolveBitPerfectOutput(_facts(channelsAltered: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'channels_remapped');
    });

    test('transport edits are named', () {
      final state =
          resolveBitPerfectOutput(_facts(transportSamplesModified: true));
      expect(state.reasonCode, 'samples_modified');
    });

    test('a DoP carrier stays unmeasured', () {
      final state = resolveBitPerfectOutput(_facts(isDsdDop: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'dop_carrier_not_measured');
    });

    test('oversampling degrades bit-perfect and names reason', () {
      final state = resolveBitPerfectOutput(_facts(oversamplingActive: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, 'oversampling_active');

      final restored = resolveBitPerfectOutput(_facts(oversamplingActive: false));
      expect(restored.tier, BitPerfectTier.active);
      expect(restored.isVerified, isTrue);
    });

    test('PCM->DSD degrades bit-perfect and names reason', () {
      final state = resolveBitPerfectOutput(_facts(pcmToDsdActive: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, 'pcm_to_dsd_active');

      final restored = resolveBitPerfectOutput(_facts(pcmToDsdActive: false));
      expect(restored.tier, BitPerfectTier.active);
      expect(restored.isVerified, isTrue);
    });

    test('a lossy source never verifies', () {
      final state = resolveBitPerfectOutput(_facts(sourceLossy: true));
      expect(state.reasonCode, 'source_lossy');
    });

    test('an unconfirmed codec never verifies', () {
      final state =
          resolveBitPerfectOutput(_facts(sourceCodecUnconfirmed: true));
      expect(state.reasonCode, 'source_codec_unconfirmed');
    });

    test('Bluetooth is never exclusive', () {
      final state = resolveBitPerfectOutput(_facts(bluetooth: true));
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'not_exclusive');
    });
  });

  group('tiers that make no claim', () {
    test('not requested is off', () {
      expect(resolveBitPerfectOutput(_facts(requested: false)).tier,
          BitPerfectTier.off);
    });

    test('no sink is arming and keeps the platform reason', () {
      final state = resolveBitPerfectOutput(
        _facts(sinkActive: false, failureReason: 'format_unsupported'),
      );
      expect(state.tier, BitPerfectTier.armed);
      expect(state.reasonCode, 'format_unsupported');
    });
  });
}
