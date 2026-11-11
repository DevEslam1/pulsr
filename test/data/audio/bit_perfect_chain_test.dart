// test/data/audio/bit_perfect_chain_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/bit_perfect_chain.dart';

void main() {
  test('int32 requires observed raw integer USB, never a wider float tag', () {
    BitPerfectChainAssessment assess({bool usb = false, int raw = 0,
      bool floating = false, bool unknown = false, bool rate = true}) =>
        assessBitPerfectChain(requested: true, active: true,
          sourceSampleRate: 48000,
          sourceBitDepth: effectiveSourceBitDepth(tagged: 16, decoded: 32),
          outputSampleRate: 48000, outputBitDepth: 32,
          directUsbActive: usb, rawPcmBitDepth: raw,
          sourceFloat: floating, sourceRepresentationUnknown: unknown,
          rateVerified: rate);
    expect(assess().isVerified, false);
    expect(assess(usb: true, raw: 24).isVerified, false);
    expect(assess(usb: true, raw: 32).isVerified, true);
    expect(assess(usb: true, raw: 32, floating: true).isVerified, false);
    expect(assess(usb: true, raw: 32, unknown: true).isVerified, false);
    expect(assess(usb: true, raw: 32, rate: false).isVerified, false);
  });
  test('all effective modifying stages downgrade a clean-format chain', () {
    bool edits({double gain = 1, double speed = 1, double pitch = 1,
      bool skip = false, bool fade = false, bool duck = false, bool dsp = false,
      bool raw = false}) => chainSamplesModified(dspProcessing: dsp,
          effectiveGain: gain, speed: speed, pitch: pitch, silenceSkip: skip,
          crossfade: fade, duckOrSleepFade: duck, rawUsb: raw);
    expect(edits(), false);
    expect(edits(gain: double.nan), true);
    expect(edits(gain: 0.8), true);
    expect(edits(speed: 1.1), true);
    expect(edits(pitch: 0.9), true);
    expect(edits(skip: true), true);
    expect(edits(fade: true), true);
    expect(edits(duck: true), true);
    expect(edits(dsp: true), true);
    expect(edits(gain: 0.5, raw: true), false);
    expect(edits(speed: 1.1, raw: true), true);
    final lossy = assessBitPerfectChain(requested: true, active: true,
        sourceSampleRate: 48000, sourceBitDepth: 16,
        outputSampleRate: 48000, outputBitDepth: 24, sourceLossy: true);
    expect(lossy.reasonCode, 'source_lossy');
    expect(lossy.isVerified, false);
  });
  group('effectiveSourceBitDepth', () {
    test('the decoder probe wins over a stale tag', () {
      expect(effectiveSourceBitDepth(tagged: 16, decoded: 24), 24);
      expect(effectiveSourceBitDepth(tagged: 24, decoded: 16), 24);
      expect(effectiveSourceBitDepth(tagged: 0, decoded: 24), 24);
      expect(effectiveSourceBitDepth(tagged: 16, decoded: 0), 16);
    });
  });

  group('effectiveSourceSampleRate', () {
    test('prefers the tag when read and falls back to the decoder probe', () {
      expect(effectiveSourceSampleRate(tagged: 44100, decoded: 48000), 44100);
      expect(effectiveSourceSampleRate(tagged: 0, decoded: 48000), 48000);
      expect(effectiveSourceSampleRate(tagged: 96000, decoded: 0), 96000);
      expect(effectiveSourceSampleRate(tagged: 0, decoded: 0), 0);
    });
  });

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

    test('direct Native DSD bitstream without DSP yields verified bit-perfect', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 2822400, // DSD64 (1-bit 2.8224 MHz)
        sourceBitDepth: 1,
        outputSampleRate: 2822400,
        outputBitDepth: 1,
        isDsdNative: true,
      );

      expect(result.verdict, BitPerfectChainVerdict.verified);
      expect(result.isVerified, isTrue);
      expect(result.isProblem, isFalse);
    });

    test('direct Native DSD refuses verification if samples were modified', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 11289600, // DSD256
        sourceBitDepth: 1,
        outputSampleRate: 11289600,
        outputBitDepth: 1,
        isDsdNative: true,
        samplesModified: true,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'samples_modified');
      expect(result.isVerified, isFalse);
    });

    test('digital volume attenuation downgrades an otherwise verified chain',
        () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        outputSampleRate: 96000,
        outputBitDepth: 24,
        digitalVolumeAttenuated: true,
      );

      expect(result.verdict, BitPerfectChainVerdict.unverified);
      expect(result.reasonCode, 'digital_volume_attenuation');
    });

    test('a rate mismatch still outranks volume attenuation', () {
      final result = assessBitPerfectChain(
        requested: true,
        active: true,
        sourceSampleRate: 44100,
        sourceBitDepth: 16,
        outputSampleRate: 48000,
        outputBitDepth: 16,
        digitalVolumeAttenuated: true,
      );

      expect(result.verdict, BitPerfectChainVerdict.resampled);
    });
  });
}
