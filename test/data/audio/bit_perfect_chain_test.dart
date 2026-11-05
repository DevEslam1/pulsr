// test/data/audio/bit_perfect_chain_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bit_perfect_chain.dart';

void main() {
  group('assessBitPerfectChain', () {
    test('reports notRequested when Bit-Perfect is off', () {
      final result = assessBitPerfectChain(
        requested: false,
        active: false,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
      );

      expect(result.verdict, BitPerfectChainVerdict.notRequested);
      expect(result.isProblem, isFalse);
    });

    test('reports inactive with the native failure reason', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: false,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
        failureReason: 'interface_busy',
      );

      expect(result.verdict, BitPerfectChainVerdict.inactive);
      expect(result.reasonCode, 'interface_busy');
      expect(result.isProblem, isTrue);
    });

    test('verifies an exact source-rate match', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
      );

      expect(result.verdict, BitPerfectChainVerdict.verified);
      expect(result.isVerified, isTrue);
      expect(result.isProblem, isFalse);
    });

    test('flags an OS resample from 44.1 to 48 kHz', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
      );

      expect(result.verdict, BitPerfectChainVerdict.resampled);
      expect(result.isResampled, isTrue);
      expect(result.isProblem, isTrue);
      expect(result.reasonCode, 'rate_mismatch');
    });

    test('flags 24-bit source truncated to a 16-bit output', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 16,
      );

      expect(result.verdict, BitPerfectChainVerdict.depthReduced);
      expect(result.isDepthReduced, isTrue);
      expect(result.isProblem, isTrue);
    });

    test('does not require an exact depth when the output is wider', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 44100,
        outputBitDepth: 24,
      );

      expect(result.verdict, BitPerfectChainVerdict.verified);
    });

    test('treats DoP as an unmeasured carrier rather than a verified chain',
        () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 2822400,
        sourceBitDepth: 1,
        outputSampleRate: 176400,
        outputBitDepth: 24,
        isDsdDop: true,
      );

      // Rate agreement is impossible for a DSD-in-PCM carrier, and the marker
      // bits are never inspected here, so nothing can be claimed.
      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'dop_carrier_not_measured');
      expect(result.isProblem, isFalse);
    });

    test('a known-modifying chain is never reported as verified', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        samplesModified: true,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'samples_modified');
      expect(result.isVerified, isFalse);
    });

    test('an unknown source depth cannot claim identity', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 0,
        outputSampleRate: 96000,
        outputBitDepth: 32,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'source_depth_unknown');
    });

    test('does not guess when either side reports no rate', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 0,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.isProblem, isFalse);
    });

    test(
        'does not claim verified when the source depth is known but output depth is not',
        () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 24,
        outputSampleRate: 44100,
        outputBitDepth: 0,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'depth_unknown');
    });
  });
}
