// test/domain/bit_perfect_state_test.dart
//
// The tier resolver is the only gate that may print BIT-PERFECT. These tests
// pin its fail-closed contract: every observation must hold, every reason code
// is reachable, and no default argument can produce `active`.
import 'package:flutter_test/flutter_test.dart';

import 'package:pulsr/data/audio/bit_perfect_chain.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';

/// All facts that a verified chain needs, plus the source/sink format match.
/// Tests override one fact at a time so a failure names the exact defect.
BitPerfectState _resolve({
  bool requested = true,
  bool sinkActive = true,
  bool exclusive = true,
  bool integerBypass = true,
  bool halClean = true,
  bool unityGain = true,
  bool softwareGainUnknown = false,
  bool samplesModified = false,
  bool channelsAltered = false,
  bool isDsdDop = false,
  bool oversamplingActive = false,
  bool pcmToDsdActive = false,
  bool sourceLossy = false,
  bool sourceCodecUnconfirmed = false,
  bool rateVerified = true,
  bool systemEffectsCompromised = false,
  int sourceSampleRate = 96000,
  int sourceBitDepth = 24,
  int sinkSampleRate = 96000,
  int sinkBitDepth = 24,
  String? failureReason,
}) =>
    resolveBitPerfectState(
      requested: requested,
      sinkActive: sinkActive,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      sinkSampleRate: sinkSampleRate,
      sinkBitDepth: sinkBitDepth,
      exclusive: exclusive,
      integerBypass: integerBypass,
      halClean: halClean,
      systemEffectsCompromised: systemEffectsCompromised,
      unityGain: unityGain,
      softwareGainUnknown: softwareGainUnknown,
      samplesModified: samplesModified,
      channelsAltered: channelsAltered,
      isDsdDop: isDsdDop,
      oversamplingActive: oversamplingActive,
      pcmToDsdActive: pcmToDsdActive,
      sourceLossy: sourceLossy,
      sourceCodecUnconfirmed: sourceCodecUnconfirmed,
      rateVerified: rateVerified,
      failureReason: failureReason,
    );

void main() {
  group('BitPerfectTier transitions', () {
    test('not requested is off and claims nothing', () {
      final state = _resolve(requested: false);
      expect(state.tier, BitPerfectTier.off);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, isNull);
      expect(state.label, 'BIT-PERFECT OFF');
    });

    test('off ignores contradictory observations', () {
      final state = _resolve(
        requested: false,
        halClean: false,
        exclusive: false,
        unityGain: false,
        sourceLossy: true,
      );
      expect(state.tier, BitPerfectTier.off);
      expect(state.reasonCode, isNull);
    });

    test('requested with no sink is armed, never active', () {
      final state = _resolve(sinkActive: false);
      expect(state.tier, BitPerfectTier.armed);
      expect(state.isVerified, isFalse);
      expect(state.label, 'BIT-PERFECT ARMING');
    });

    test('armed keeps the platform failure reason', () {
      final state =
          _resolve(sinkActive: false, failureReason: 'format_unsupported');
      expect(state.tier, BitPerfectTier.armed);
      expect(state.reasonCode, 'format_unsupported');
    });

    test('armed without a platform reason names the missing sink', () {
      final state = _resolve(sinkActive: false);
      expect(state.reasonCode, 'sink_not_active');
    });

    test('every fact plus a verified assessment is active', () {
      final state = _resolve();
      expect(state.tier, BitPerfectTier.active);
      expect(state.isVerified, isTrue);
      expect(state.reasonCode, isNull);
      expect(state.label, 'BIT-PERFECT');
      expect(state.assessment.verdict, BitPerfectChainVerdict.verified);
    });

    test('an unprovable OEM effect blocks active and names it', () {
      final state = _resolve(systemEffectsCompromised: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'system_effect_active');
    });

    test('an unprovable OEM effect never changes off or armed', () {
      expect(
        _resolve(requested: false, systemEffectsCompromised: true).tier,
        BitPerfectTier.off,
      );
      expect(
        _resolve(sinkActive: false, systemEffectsCompromised: true).tier,
        BitPerfectTier.armed,
      );
    });
  });

  group('BitPerfectState fail-closed defaults', () {
    test('default capability booleans cannot reach active', () {
      final state = resolveBitPerfectState(
        requested: true,
        sinkActive: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        sinkSampleRate: 96000,
        sinkBitDepth: 24,
      );
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
    });

    test('unknown gain is attenuation, not unity', () {
      final state = _resolve(unityGain: false);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'digital_volume_attenuation');
    });

    test('an unreadable gain is unmeasured, not attenuated', () {
      final state = _resolve(unityGain: false, softwareGainUnknown: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'software_gain_unknown');
      expect(state.assessment.reasonCode, 'software_gain_unknown');
      expect(state.reasonCode, isNot('digital_volume_attenuation'));
    });

    test('an unreadable gain can never verify a formatted chain', () {
      final state = _resolve(softwareGainUnknown: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, 'software_gain_unknown');
    });

    test('a serious format finding outranks an unreadable gain', () {
      final state = _resolve(softwareGainUnknown: true, sourceSampleRate: 44100);
      expect(state.assessment.verdict, BitPerfectChainVerdict.resampled);
      expect(state.reasonCode, 'rate_mismatch');
    });
  });

  group('BitPerfectState reason precedence', () {
    test('a dirty HAL dominates every other fact', () {
      final state = _resolve(halClean: false, exclusive: false);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'hal_effect_active');
    });

    test('a non-exclusive route is named before the float carrier', () {
      final state = _resolve(exclusive: false, integerBypass: false);
      expect(state.reasonCode, 'not_exclusive');
    });

    test('a float carrier is a conversion, not a pref', () {
      final state = _resolve(integerBypass: false);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'float_conversion');
    });

    test('rate mismatch keeps its specific assessment reason', () {
      final state = _resolve(sourceSampleRate: 44100);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'rate_mismatch');
      expect(state.assessment.verdict, BitPerfectChainVerdict.resampled);
    });

    test('a shallower sink is depth truncated', () {
      final state = _resolve(sinkBitDepth: 16);
      expect(state.reasonCode, 'depth_truncated');
      expect(state.assessment.isDepthReduced, isTrue);
    });

    test('modified samples are named as such', () {
      final state = _resolve(samplesModified: true);
      expect(state.reasonCode, 'samples_modified');
    });

    test('remapped channels are named as such', () {
      final state = _resolve(channelsAltered: true);
      expect(state.reasonCode, 'channels_remapped');
    });

    test('a lossy source can never verify', () {
      final state = _resolve(sourceLossy: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.reasonCode, 'source_lossy');
    });

    test('a DoP carrier is reported as unmeasured', () {
      final state = _resolve(isDsdDop: true);
      expect(state.reasonCode, 'dop_carrier_not_measured');
    });

    test('active oversampling degrades bit-perfect and names reason', () {
      final state = _resolve(oversamplingActive: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, 'oversampling_active');

      // Restoring oversampling to false restores active verified bit-perfect
      final restored = _resolve(oversamplingActive: false);
      expect(restored.tier, BitPerfectTier.active);
      expect(restored.isVerified, isTrue);
    });

    test('active PCM->DSD degrades bit-perfect and names reason', () {
      final state = _resolve(pcmToDsdActive: true);
      expect(state.tier, BitPerfectTier.degraded);
      expect(state.isVerified, isFalse);
      expect(state.reasonCode, 'pcm_to_dsd_active');

      // Restoring PCM->DSD to false restores active verified bit-perfect
      final restored = _resolve(pcmToDsdActive: false);
      expect(restored.tier, BitPerfectTier.active);
      expect(restored.isVerified, isTrue);
    });

    test('an unverified rate is not a rate mismatch', () {
      final state = _resolve(rateVerified: false);
      expect(state.reasonCode, 'rate_not_verified');
    });

    test('an unconfirmed codec is not silently lossless', () {
      final state = _resolve(sourceCodecUnconfirmed: true);
      expect(state.reasonCode, 'source_codec_unconfirmed');
    });

    test('an unknown sink rate is unknown, not zero hertz', () {
      final state = _resolve(sinkSampleRate: 0);
      expect(state.reasonCode, 'rate_unknown');
    });

    test('an unknown source depth is named', () {
      final state = _resolve(sourceBitDepth: 0);
      expect(state.reasonCode, 'source_depth_unknown');
    });

    test('an unknown sink depth is named', () {
      final state = _resolve(sinkBitDepth: 0);
      expect(state.reasonCode, 'depth_unknown');
    });
  });

  group('BitPerfectState keeps the explanation it has', () {
    test('an armed state preserves the platform failure text', () {
      final state =
          _resolve(sinkActive: false, failureReason: 'mixer_attributes_rejected');
      expect(state.tier, BitPerfectTier.armed);
      expect(state.reasonCode, 'mixer_attributes_rejected');
      expect(state.assessment.reasonCode, 'mixer_attributes_rejected');
    });

    test('an observed contradiction is not overwritten by stale platform text',
        () {
      // The sink is up and its format matches, so the old refusal text no
      // longer describes the live chain: the DSP contradiction is the reason.
      final state = _resolve(
        samplesModified: true,
        failureReason: 'format_unsupported',
      );
      expect(state.reasonCode, 'samples_modified');
      expect(state.assessment.reasonCode, 'samples_modified');
    });
  });
}
