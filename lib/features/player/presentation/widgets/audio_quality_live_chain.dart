// lib/features/player/presentation/widgets/audio_quality_live_chain.dart
//
// Fail-closed gain gate for the live signal-chain verdict.
//
// `effectiveSoftwareGain` is the only evidence that the player volume stage
// sits at unity. NaN compares false against every bound, so a naive
// `gain < 1.0` attenuation test reads a broken reading as "not attenuated".
// A reading that cannot be a real volume multiplier is unknown, and unknown is
// never unity.
import 'package:flutter/widgets.dart';

import '../../../../core/utils/l10n_extensions.dart';
import '../../../../data/audio/bit_perfect_chain.dart';

/// Wording for the reasons a live chain can name without an l10n key.
///
/// The old catch-all ("platform conversion") said the same thing for a DSP
/// stage, a HAL AudioEffect and a float carrier, so a chain this app had
/// itself modified looked like an OS resample. Only those three reasons are
/// replaced; every other code keeps its existing explanation.
String liveChainReasonLabel(BuildContext context, String? reasonCode) {
  switch (reasonCode) {
    case 'samples_modified':
      return 'Samples modified by DSP';
    case 'hal_effect_active':
      return 'HAL effect active';
    case 'float_conversion':
      return 'Float conversion';
    case 'source_codec_unconfirmed':
      return context.l10n.bpSourceCodecUnconfirmed;
    case 'digital_volume_attenuation':
      return context.l10n.bpDigitalVolumeAttenuation;
    default:
      return context.l10n.bpPlatformConversion;
  }
}

/// Highest software gain this app can legitimately report.
///
/// `_volume` and the ReplayGain multiplier are clamped to 0..1 and the native
/// DVC stage tops out at 4.0, so a larger reading is a corrupt value rather
/// than a real level.
const double _kMaxTrustedSoftwareGain = 4.0;

/// The gain a bit-perfect verdict may trust, or `null` when the reading cannot
/// be a real software volume multiplier.
///
/// Missing, NaN, ±Infinity, negative and absurd readings are all unusable.
/// `double.nan` is the worst of them: it compares false against every bound,
/// which is how it used to slip through as "not attenuated".
double? trustedSoftwareGain(double? gain) {
  if (gain == null || !gain.isFinite) return null;
  if (gain < 0.0 || gain > _kMaxTrustedSoftwareGain) return null;
  return gain;
}

/// Pure gain gate over the observed chain facts.
///
/// The live sheet routes the same rule through `resolveBitPerfectState`
/// (`softwareGainUnknown`). This builder stays as the pure statement of the
/// gain contract (an unreadable gain is unknown, never unity), independent of
/// widget pumping. [softwareGain] is the handler's raw
/// `effectiveSoftwareGain`, or `null` when none is registered.
///
/// An unreadable gain is *unknown*, not unity. It is deliberately not folded
/// into the `samples_modified` reason - "the samples were edited" is not what
/// a missing reading proves - and it cannot set attenuation either, because
/// attenuation was never measured. A chain that would otherwise verify is
/// downgraded to [BitPerfectChainVerdict.unverified] with reason
/// `software_gain_unknown`; a more serious finding (resample, depth loss,
/// inactive route) still wins, because that one is observable on its own.
BitPerfectChainAssessment buildLiveChainAssessment({
  required bool requested,
  required bool active,
  required int sourceSampleRate,
  required int sourceBitDepth,
  required int outputSampleRate,
  required int outputBitDepth,
  required bool isDsdDop,
  required bool transportSamplesModified,
  required bool dspProcessing,
  required bool directUsbActive,
  required int rawPcmBitDepth,
  required bool sourceFloat,
  required bool sourceRepresentationUnknown,
  required bool sourceLossy,
  required bool sourceCodecUnconfirmed,
  required bool channelsAltered,
  required bool rateVerified,
  required double? softwareGain,
  String? failureReason,
}) {
  final gain = trustedSoftwareGain(softwareGain);
  // A direct raw USB tee applies the player gain in the sink, so it does not
  // edit the samples; every AudioTrack-backed route multiplies them.
  final rawUsb = directUsbActive && rawPcmBitDepth > 0;
  final assessment = assessBitPerfectChain(
    requested: requested,
    active: active,
    sourceSampleRate: sourceSampleRate,
    sourceBitDepth: sourceBitDepth,
    outputSampleRate: outputSampleRate,
    outputBitDepth: outputBitDepth,
    isDsdDop: isDsdDop,
    samplesModified: transportSamplesModified ||
        dspProcessing ||
        (gain != null &&
            chainSamplesModified(
              dspProcessing: false,
              effectiveGain: gain,
              rawUsb: rawUsb,
            )),
    directUsbActive: directUsbActive,
    rawPcmBitDepth: rawPcmBitDepth,
    sourceFloat: sourceFloat,
    sourceRepresentationUnknown: sourceRepresentationUnknown,
    sourceLossy: sourceLossy,
    sourceCodecUnconfirmed: sourceCodecUnconfirmed,
    channelsAltered: channelsAltered,
    // Direct USB applies the player gain natively (_syncDirectUsbVolume), so
    // attenuation is real on that path too; only a DAC-owned volume keeps the
    // player gain at unity.
    digitalVolumeAttenuated: gain != null && gain < 1.0,
    rateVerified: rateVerified,
    failureReason: failureReason,
  );
  if (gain != null || assessment.verdict != BitPerfectChainVerdict.verified) {
    return assessment;
  }
  return BitPerfectChainAssessment(
    verdict: BitPerfectChainVerdict.unverified,
    sourceSampleRate: assessment.sourceSampleRate,
    sourceBitDepth: assessment.sourceBitDepth,
    outputSampleRate: assessment.outputSampleRate,
    outputBitDepth: assessment.outputBitDepth,
    reasonCode: 'software_gain_unknown',
  );
}
