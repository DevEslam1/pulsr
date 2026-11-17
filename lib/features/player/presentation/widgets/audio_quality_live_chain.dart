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
    case 'system_effect_active':
      return 'System effect active';
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
