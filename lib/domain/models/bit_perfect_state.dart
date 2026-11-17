// lib/domain/models/bit_perfect_state.dart
//
// One fail-closed answer to "is this stream bit-perfect?" that every surface
// can read.
//
// The platform reports the format it opened; it never reports that the samples
// arrived unaltered. A preference flag, a device capability or an exclusive
// attribute therefore says nothing about the bytes that reached the DAC. This
// file turns the observable facts (sink format, exclusive route, integer
// bypass, HAL effects, gain, sample edits, source codec) into a single tier
// and keeps the existing chain assessment as the authority on format identity.
//
// Fail-closed means: anything unknown or contradicted lands in `degraded` (or
// `armed` before the sink is up), and only a chain assessment that returned
// `verified` while every other fact holds can produce `active`. There is no
// path from "absence of evidence" to `isVerified`.
//
// Domain-only: no features/ imports, no Flutter, no I/O.

import '../../data/audio/bit_perfect_chain.dart';

/// How far the current output is from a verified bit-perfect chain.
enum BitPerfectTier {
  /// Bit-Perfect was not requested; nothing is claimed.
  off,

  /// Requested, but the platform has not configured an exclusive/direct sink
  /// yet. This is intent, not output: nothing has been verified.
  armed,

  /// Every observed fact holds and [BitPerfectChainAssessment] returned
  /// `verified`.
  active,

  /// Requested and the sink is up, but at least one observed fact contradicts
  /// a bit-exact claim (HAL effect, float conversion, attenuation, resample,
  /// depth truncation, modified samples, lossy or DoP carrier...).
  degraded,
}

/// The single verdict consumed by the UI.
class BitPerfectState {
  final BitPerfectTier tier;

  /// Machine-readable reason the claim is not verified; overrides the
  /// assessment reason when set. `null` when Bit-Perfect was never requested.
  /// The platform's own failure text stays on [assessment]`.reasonCode`
  /// whenever the assessment produced no more specific verdict (typically
  /// [BitPerfectTier.armed], where it is the only explanation available). An
  /// observed contradiction is named first in [reasonCode]; the platform text
  /// is not echoed over it, because that text describes why the sink did not
  /// open, not what the open sink is doing now.
  final String? reasonCode;

  /// The format-identity assessment this tier was derived from.
  final BitPerfectChainAssessment assessment;

  const BitPerfectState({
    required this.tier,
    required this.assessment,
    this.reasonCode,
  });

  /// True only for [BitPerfectTier.active] — the sole tier allowed to print
  /// "BIT-PERFECT".
  bool get isVerified => tier == BitPerfectTier.active;

  /// Chip text. Anything that is not verified says so, even when the route is
  /// exclusive. The `off` tier must never read as an exclusive claim either:
  /// nothing was requested, so there is no route to describe.
  String get label => switch (tier) {
        BitPerfectTier.active => 'BIT-PERFECT',
        BitPerfectTier.off => 'BIT-PERFECT OFF',
        BitPerfectTier.armed => 'BIT-PERFECT ARMING',
        BitPerfectTier.degraded => 'EXCLUSIVE / UNVERIFIED',
      };
}

/// Resolves the tier from observed output facts, not from preferences.
///
/// [requested] is the user's Bit-Perfect preference; [sinkActive] is the
/// platform confirming the exclusive/direct output is configured. Everything
/// else is an observation about the live chain.
///
/// [strict] carries the "block rather than downgrade" preference. It never
/// loosens the verdict — the resolver is fail-closed for both values — and it
/// does not change the tier; callers use it to decide whether a
/// non-[BitPerfectTier.active] state should block playback or only warn.
///
/// The capability booleans are deliberately defaulted to `false`: a caller
/// that has not proven exclusivity, an integer path, a clean HAL and unity
/// gain gets `degraded`, never `active`. [softwareGainUnknown] says the gain
/// reading itself was unusable, which is distinct from a measured attenuation.
BitPerfectState resolveBitPerfectState({
  required bool requested,
  required bool strict,
  required bool sinkActive,
  required int sourceSampleRate,
  required int sourceBitDepth,
  required int sinkSampleRate,
  required int sinkBitDepth,
  bool exclusive = false,
  bool integerBypass = false,
  bool halClean = false,
  bool unityGain = false,
  bool softwareGainUnknown = false,
  bool samplesModified = false,
  bool channelsAltered = false,
  bool isDsdDop = false,
  bool sourceLossy = false,
  bool sourceCodecUnconfirmed = false,
  bool rateVerified = true,
  String? failureReason,
}) {
  // Fold every observation into the one assessment that already knows how to
  // compare source and sink formats:
  //  - a non-integer path re-quantises the samples, so it *is* a modification;
  //  - any gain below unity attenuates them;
  //  - exclusive is the direct-USB fact the precision rules depend on;
  //  - the sink depth is the raw depth, never the collapsed display value.
  BitPerfectChainAssessment assessment = assessBitPerfectChain(
    requested: requested,
    active: sinkActive,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    outputSampleRate: sinkSampleRate,
    outputBitDepth: sinkBitDepth,
    isDsdDop: isDsdDop,
    samplesModified: samplesModified || !integerBypass,
    channelsAltered: channelsAltered,
    // An unreadable gain is unknown, not attenuated: attenuation was never
    // measured, and claiming it would invent a fact.
    digitalVolumeAttenuated: !unityGain && !softwareGainUnknown,
    rateVerified: rateVerified,
    sourceCodecUnconfirmed: sourceCodecUnconfirmed,
    sourceLossy: sourceLossy,
    directUsbActive: exclusive,
    rawPcmBitDepth: sinkBitDepth,
    failureReason: failureReason,
  );

  // A gain that could not be read leaves the volume stage unmeasured. When
  // every format fact otherwise verifies, say exactly that instead of letting
  // the chain pass or borrowing an unrelated reason.
  if (softwareGainUnknown &&
      assessment.verdict == BitPerfectChainVerdict.verified) {
    assessment = BitPerfectChainAssessment(
      verdict: BitPerfectChainVerdict.unverified,
      sourceSampleRate: assessment.sourceSampleRate,
      sourceBitDepth: assessment.sourceBitDepth,
      outputSampleRate: assessment.outputSampleRate,
      outputBitDepth: assessment.outputBitDepth,
      reasonCode: 'software_gain_unknown',
    );
  }

  // `halClean` has no counterpart in the assessment (HAL effects live outside
  // the PCM buffer), so the active tier requires it here as well. Every fact
  // must hold *and* the chain must be verified; anything else is degraded.
  final allFactsHold =
      exclusive && integerBypass && halClean && unityGain && !softwareGainUnknown;

  final BitPerfectTier tier;
  if (!requested) {
    tier = BitPerfectTier.off;
  } else if (!sinkActive) {
    tier = BitPerfectTier.armed;
  } else if (allFactsHold &&
      assessment.verdict == BitPerfectChainVerdict.verified) {
    tier = BitPerfectTier.active;
  } else {
    tier = BitPerfectTier.degraded;
  }

  // Reason precedence: the fact that most directly destroys bit-exactness
  // wins. A HAL effect alters the stream after the app hands it over; without
  // an exclusive route the sink format is not ours to control; a float carrier
  // re-quantises integer samples. Otherwise the assessment's own reason stands
  // (rate/depth mismatch, modified samples, lossy source, DoP carrier...).
  final String? reasonCode;
  if (!requested) {
    reasonCode = null;
  } else if (!sinkActive) {
    // Nothing is open yet, so a HAL/gain/format fact cannot be the reason.
    // Keep the platform's own failure text when it supplied one; otherwise
    // say exactly what is missing: an active sink.
    reasonCode = assessment.reasonCode ?? 'sink_not_active';
  } else if (!halClean) {
    reasonCode = 'hal_effect_active';
  } else if (!exclusive) {
    reasonCode = 'not_exclusive';
  } else if (!integerBypass) {
    reasonCode = 'float_conversion';
  } else {
    reasonCode = assessment.reasonCode;
  }

  return BitPerfectState(
    tier: tier,
    assessment: assessment,
    reasonCode: reasonCode,
  );
}
