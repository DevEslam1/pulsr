// test/features/player/widgets/audio_quality_sheet_gain_test.dart
//
// P1-2.8: the live signal chain's software-gain gate.
//
// `effectiveSoftwareGain` is the only evidence that the player volume stage
// sits at unity. NaN compares false against every bound, so the old
// `gain < 1.0` attenuation test read a broken reading as "not attenuated" and
// let a would-be verified chain through. A reading that cannot be a real
// volume multiplier is unknown, and unknown is never unity.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bit_perfect_chain.dart';
import 'package:pulsr/features/player/presentation/widgets/audio_quality_live_chain.dart';

void main() {
  /// A chain whose format facts agree end to end, so the gain reading is the
  /// only thing that can change the verdict.
  BitPerfectChainAssessment assess(
    double? gain, {
    bool directUsbActive = true,
    int rawPcmBitDepth = 24,
    int outputSampleRate = 96000,
  }) {
    return buildLiveChainAssessment(
      requested: true,
      active: true,
      sourceSampleRate: 96000,
      sourceBitDepth: 24,
      outputSampleRate: outputSampleRate,
      outputBitDepth: 24,
      isDsdDop: false,
      transportSamplesModified: false,
      dspProcessing: false,
      directUsbActive: directUsbActive,
      rawPcmBitDepth: rawPcmBitDepth,
      sourceFloat: false,
      sourceRepresentationUnknown: false,
      sourceLossy: false,
      sourceCodecUnconfirmed: false,
      channelsAltered: false,
      rateVerified: true,
      softwareGain: gain,
    );
  }

  test('a unity gain on a matching chain is verified', () {
    final assessment = assess(1.0);

    expect(assessment.verdict, BitPerfectChainVerdict.verified);
    expect(assessment.reasonCode, isNull);
  });

  test('a 0.5 gain still reports the attenuated path', () {
    final assessment = assess(0.5);

    expect(assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(assessment.reasonCode, 'digital_volume_attenuation');
  });

  for (final gain in <double>[
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -0.5,
  ]) {
    test('an unusable gain ($gain) never verifies the chain', () {
      final assessment = assess(gain);

      expect(assessment.verdict, BitPerfectChainVerdict.unverified);
      expect(assessment.reasonCode, 'software_gain_unknown');
    });
  }

  test('a missing handler reading never verifies the chain', () {
    final assessment = assess(null);

    expect(assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(assessment.reasonCode, 'software_gain_unknown');
  });

  test('an absurd gain reading never verifies the chain', () {
    final assessment = assess(1e6);

    expect(assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(assessment.reasonCode, 'software_gain_unknown');
  });

  test('an unusable gain does not borrow the samples-modified reason', () {
    // On an AudioTrack route the raw NaN reaches `chainSamplesModified`, which
    // folds a non-finite gain into "samples modified". The gate must report the
    // unmeasured volume stage instead of claiming the samples were edited.
    final assessment = assess(double.nan,
        directUsbActive: false, rawPcmBitDepth: 0);

    expect(assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(assessment.reasonCode, 'software_gain_unknown');
  });

  test('a serious format finding outranks an unusable gain', () {
    final assessment = assess(double.nan, outputSampleRate: 48000);

    expect(assessment.verdict, BitPerfectChainVerdict.resampled);
    expect(assessment.reasonCode, 'rate_mismatch');
  });
}
