// test/features/player/widgets/audio_quality_sheet_gain_test.dart
//
// P1-2.8: the live signal chain's software-gain gate.
//
// The verdict is no longer folded here or in the sheet: every surface builds
// `BitPerfectOutputFacts` and asks `resolveBitPerfectOutput`. This test pins
// the gain contract on that assembler. `effectiveSoftwareGain` is the only
// evidence that the player volume stage sits at unity; NaN compares false
// against every bound, which is how a naive `gain < 1.0` attenuation test once
// read a broken reading as "not attenuated". A reading that cannot be a real
// volume multiplier is unknown, and unknown is never unity.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bit_perfect_chain.dart';
import 'package:pulsr/domain/models/bit_perfect_output_facts.dart';
import 'package:pulsr/domain/models/bit_perfect_state.dart';

void main() {
  /// Direct-USB raw facts: Pulsr's own sink owns the endpoint and reported a
  /// 24-bit raw block at the source's own 96 kHz, so the gain reading is the
  /// only thing that can change the verdict.
  BitPerfectState resolve(
    double? gain, {
    bool directUsbActive = true,
    int directRawPcmBitDepth = 24,
    int directStreamSampleRate = 96000,
  }) {
    return resolveBitPerfectOutput(BitPerfectOutputFacts(
      requested: true,
      sinkActive: true,
      directUsbActive: directUsbActive,
      sourceSampleRate: 96000,
      sourceBitDepth: 24,
      sinkSampleRate: 96000,
      sinkBitDepth: 24,
      directStreamSampleRate: directStreamSampleRate,
      directStreamBitDepth: 24,
      directRawPcmBitDepth: directRawPcmBitDepth,
      softwareGain: gain,
    ));
  }

  test('a unity gain on a matching direct raw chain verifies', () {
    final state = resolve(1.0);

    expect(state.assessment.verdict, BitPerfectChainVerdict.verified);
    expect(state.assessment.reasonCode, isNull);
    expect(state.isVerified, isTrue);
  });

  test('a 0.5 gain still reports the attenuated path', () {
    final state = resolve(0.5);

    expect(state.assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(state.assessment.reasonCode, 'digital_volume_attenuation');
  });

  for (final gain in <double>[
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -0.5,
  ]) {
    test('an unusable gain ($gain) never verifies the chain', () {
      final state = resolve(gain);

      expect(state.assessment.verdict, BitPerfectChainVerdict.unverified);
      expect(state.assessment.reasonCode, 'software_gain_unknown');
    });
  }

  test('a missing handler reading never verifies the chain', () {
    final state = resolve(null);

    expect(state.assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(state.assessment.reasonCode, 'software_gain_unknown');
  });

  test('an absurd gain reading never verifies the chain', () {
    final state = resolve(1e6);

    expect(state.assessment.verdict, BitPerfectChainVerdict.unverified);
    expect(state.assessment.reasonCode, 'software_gain_unknown');
  });

  test('no integer bypass names the float path, not a modified sample', () {
    // The last delivered block went the float path (raw depth 0), so nothing
    // proves the samples stayed integer. The verdict must say float conversion
    // rather than blaming the transport/DSP for edits nobody observed.
    final state = resolve(1.0, directRawPcmBitDepth: 0);

    expect(state.assessment.verdict, isNot(BitPerfectChainVerdict.verified));
    expect(state.assessment.reasonCode, 'float_conversion');
    expect(state.assessment.reasonCode, isNot('samples_modified'));
  });

  test('a serious format finding outranks an unusable gain', () {
    final state = resolve(double.nan, directStreamSampleRate: 48000);

    expect(state.assessment.verdict, BitPerfectChainVerdict.resampled);
    expect(state.assessment.reasonCode, 'rate_mismatch');
  });
}
