// lib/data/audio/bit_perfect_chain.dart
//
// Pure verdict for "did the file's rate/depth actually reach the output?".
// The platform only reports the stream format it opened; it does not compare
// that against the source. Without this comparison the UI can only say
// "exclusive mixer configured", which is why a silent OS resample was
// invisible. No I/O here: the caller supplies the source and output facts.

enum BitPerfectChainVerdict {
  /// Bit-Perfect was not requested; nothing to verify.
  notRequested,

  /// Bit-Perfect was requested but the platform/direct sink is not active.
  inactive,

  /// The output reports the source rate and at least the source depth.
  verified,

  /// The output rate differs from the source: the platform resampled.
  resampled,

  /// The output depth is lower than the source: samples were truncated.
  depthReduced,

  /// The output did not report enough information to decide.
  unverified,
}

class BitPerfectChainAssessment {
  final BitPerfectChainVerdict verdict;
  final int sourceSampleRate;
  final int sourceBitDepth;
  final int outputSampleRate;
  final int outputBitDepth;
  final String? reasonCode;

  const BitPerfectChainAssessment({
    required this.verdict,
    this.sourceSampleRate = 0,
    this.sourceBitDepth = 0,
    this.outputSampleRate = 0,
    this.outputBitDepth = 0,
    this.reasonCode,
  });

  bool get isVerified => verdict == BitPerfectChainVerdict.verified;

  /// A verdict the user should be warned about, not merely "unverified".
  bool get isProblem =>
      verdict == BitPerfectChainVerdict.resampled ||
      verdict == BitPerfectChainVerdict.depthReduced ||
      verdict == BitPerfectChainVerdict.inactive;

  bool get isResampled => verdict == BitPerfectChainVerdict.resampled;

  bool get isDepthReduced => verdict == BitPerfectChainVerdict.depthReduced;

  @override
  String toString() =>
      'BitPerfectChainAssessment($verdict.name, $sourceSampleRate→'
      '$outputSampleRate, $sourceBitDepth→${outputBitDepth}bit)';
}

/// Compares the source format with the format the output actually opened.
///
/// [isDsdDop] suppresses the rate comparison: DSD-over-PCM intentionally
/// carries 1-bit DSD in a PCM carrier at a different rate (usually 176.4 or
/// 352.8 kHz), so a mismatch is expected and does not mean a resample.
BitPerfectChainAssessment assessBitPerfectChain({
  required bool requested,
  required bool active,
  required int sourceSampleRate,
  required int sourceBitDepth,
  required int outputSampleRate,
  required int outputBitDepth,
  bool isDsdDop = false,
  String? failureReason,
}) {
  if (!requested) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.notRequested,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
    );
  }
  if (!active) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.inactive,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: failureReason,
    );
  }

  // DoP is a carrier, not a resample; the DAC receives the DSD stream.
  if (isDsdDop) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.verified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
    );
  }

  if (sourceSampleRate <= 0 || outputSampleRate <= 0) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'rate_unknown',
    );
  }

  if (sourceSampleRate != outputSampleRate) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.resampled,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'rate_mismatch',
    );
  }

  if (sourceBitDepth > 0) {
    if (outputBitDepth <= 0) {
      return BitPerfectChainAssessment(
        verdict: BitPerfectChainVerdict.unverified,
        sourceSampleRate: sourceSampleRate,
        sourceBitDepth: sourceBitDepth,
        outputSampleRate: outputSampleRate,
        outputBitDepth: outputBitDepth,
        reasonCode: 'depth_unknown',
      );
    }
    if (outputBitDepth < sourceBitDepth) {
      return BitPerfectChainAssessment(
        verdict: BitPerfectChainVerdict.depthReduced,
        sourceSampleRate: sourceSampleRate,
        sourceBitDepth: sourceBitDepth,
        outputSampleRate: outputSampleRate,
        outputBitDepth: outputBitDepth,
        reasonCode: 'depth_truncated',
      );
    }
  }

  return BitPerfectChainAssessment(
    verdict: BitPerfectChainVerdict.verified,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    outputSampleRate: outputSampleRate,
    outputBitDepth: outputBitDepth,
  );
}
