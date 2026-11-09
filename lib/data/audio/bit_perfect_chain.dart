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

  /// The output reports the source rate and at least the source depth, and
  /// nothing in the chain is known to have altered the samples. Format
  /// agreement alone is not sample identity: it never proves the bytes that
  /// reached the DAC are the bytes that came out of the decoder.
  verified,

  /// The output rate differs from the source: the platform resampled.
  resampled,

  /// The output depth is lower than the source: samples were truncated.
  depthReduced,

  /// The output did not report enough information to decide.
  unverified,
}

/// The source depth the chain should compare against.
///
/// The database tag is what the scanner read; the decoder probe is what the
/// sink actually received. A 24-bit ALAC whose tag says 16 must be judged at
/// 24, otherwise a 16-bit output is reported as a verified match. The wider
/// of the two is always the truthful source depth.
int effectiveSourceBitDepth({required int tagged, required int decoded}) =>
    decoded > tagged ? decoded : tagged;

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
      'BitPerfectChainAssessment(${verdict.name}, $sourceSampleRate→'
      '$outputSampleRate, $sourceBitDepth→${outputBitDepth}bit)';
}

/// Compares the source format with the format the output actually opened.
///
/// [isDsdDop] suppresses the rate comparison: DSD-over-PCM intentionally
/// carries 1-bit DSD in a PCM carrier at a different rate (usually 176.4 or
/// 352.8 kHz), so a mismatch is expected and does not mean a resample. It does
/// not prove identity either - the carrier and marker bits are not measured
/// here, so DoP stays unverified rather than claiming a verified PCM chain.
///
/// [samplesModified] means something upstream is known to change the samples
/// (an active DSP stage, or int32 source audio entering a float32 pipeline).
/// No format agreement can make that chain bit-perfect. It is a single bool on
/// purpose - the verdict does not enumerate stages - so the caller must fold
/// *every* processing and gain stage it knows about into it (EQ, limiter,
/// crossfeed, reverb, saturation, dynamics, width, contour, crossover, volume
/// boost, ReplayGain...); passing a partial list silently upgrades the verdict
/// to "verified".
///
/// [channelsAltered] means the sink remapped the channel layout (duplicated,
/// silenced or dropped channels) on at least one frame. Like [samplesModified]
/// it can never be format-agreement "verified"; it is a separate flag because
/// the reason the user is shown differs.
BitPerfectChainAssessment assessBitPerfectChain({
  required bool requested,
  required bool active,
  required int sourceSampleRate,
  required int sourceBitDepth,
  required int outputSampleRate,
  required int outputBitDepth,
  bool isDsdDop = false,
  bool isDsdNative = false,
  bool samplesModified = false,
  bool channelsAltered = false,
  /// The active sink scales the samples with software/system volume below
  /// unity. A bit-exact claim needs unity gain; below it the samples are
  /// attenuated even when the format matches.
  bool digitalVolumeAttenuated = false,
  bool rateVerified = true,
  bool sourceCodecUnconfirmed = false,
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

  // DoP is a carrier, not a resample - but the carrier/marker integrity is not
  // observable from here, so it cannot be reported as a verified chain.
  if (isDsdDop) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'dop_carrier_not_measured',
    );
  }

  if (samplesModified) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'samples_modified',
    );
  }

  if (channelsAltered) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'channels_remapped',
    );
  }

  if (!rateVerified) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'rate_not_verified',
    );
  }

  if (sourceCodecUnconfirmed) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'source_codec_unconfirmed',
    );
  }

  // Direct Native DSD (Raw Bitstream): 1-bit DSD without PCM markers or downsampling.
  if (isDsdNative) {
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

  // Neither side of a depth comparison can be unknown: agreeing rates with an
  // unmeasured container depth prove nothing about the samples.
  if (sourceBitDepth <= 0 || outputBitDepth <= 0) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: sourceBitDepth <= 0 ? 'source_depth_unknown' : 'depth_unknown',
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

  // Volume is checked last on purpose: a rate mismatch or a narrower output
  // is the more serious finding and must keep its specific verdict. Volume
  // only downgrades what would otherwise be called verified.
  if (digitalVolumeAttenuated) {
    return BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: sourceSampleRate,
      sourceBitDepth: sourceBitDepth,
      outputSampleRate: outputSampleRate,
      outputBitDepth: outputBitDepth,
      reasonCode: 'digital_volume_attenuation',
    );
  }

  return BitPerfectChainAssessment(
    verdict: BitPerfectChainVerdict.verified,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    outputSampleRate: outputSampleRate,
    outputBitDepth: outputBitDepth,
  );
}
