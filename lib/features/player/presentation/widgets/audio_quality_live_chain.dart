// lib/features/player/presentation/widgets/audio_quality_live_chain.dart
//
// Presentation-only wording for why a live chain is not verified.
//
// The verdict itself no longer lives here: the sheet and the per-track session
// log both build `BitPerfectOutputFacts` and hand them to
// `resolveBitPerfectOutput`, which owns the single gain/format fold (including
// the rule that an unreadable gain is unknown, never unity). What remains is
// the mapping from a machine reason code to user-facing text.
import 'package:flutter/widgets.dart';

import '../../../../core/utils/l10n_extensions.dart';

/// Wording for every reason a live chain can name.
///
/// Each code the domain can emit has its own sentence: the old catch-all
/// ("Platform conversion") described an OS resample for a volume attenuation,
/// an unreadable gain or an unknown output rate alike, so a chain this app had
/// itself left untouched looked like a platform resample - and a real resample
/// looked the same as a missing measurement. An unknown code now says only
/// that nothing verified the chain, never what did it.
String liveChainReasonLabel(BuildContext context, String? reasonCode) {
  final l10n = context.l10n;
  switch (reasonCode) {
    case 'samples_modified':
      return l10n.bpReasonSamplesModified;
    case 'hal_effect_active':
      return l10n.bpReasonHalEffect;
    case 'system_effect_active':
      return l10n.bpReasonSystemEffect;
    case 'float_conversion':
      return l10n.bpReasonFloatConversion;
    case 'source_codec_unconfirmed':
      return l10n.bpSourceCodecUnconfirmed;
    case 'digital_volume_attenuation':
      return l10n.bpDigitalVolumeAttenuation;
    case 'rate_unknown':
      return l10n.bpReasonRateUnknown;
    case 'rate_not_verified':
      return l10n.bpReasonRateNotVerified;
    case 'rate_mismatch':
      return l10n.bpChainResampled;
    case 'depth_unknown':
      return l10n.bpReasonDepthUnknown;
    case 'source_depth_unknown':
      return l10n.bpReasonSourceDepthUnknown;
    case 'depth_truncated':
      return l10n.bpChainDepthReduced;
    case 'source_lossy':
      return l10n.bpReasonSourceLossy;
    case 'source_precision_not_preserved':
      return l10n.bpReasonPrecisionNotPreserved;
    case 'channels_remapped':
      return l10n.bpReasonChannelsRemapped;
    case 'dop_carrier_not_measured':
      return l10n.bpReasonDopCarrier;
    case 'software_gain_unknown':
      return l10n.bpReasonGainUnknown;
    case 'not_exclusive':
      return l10n.bpReasonNotExclusive;
    case 'sink_not_active':
      return l10n.bpChainInactive;
    default:
      return l10n.bpReasonUnknown;
  }
}
