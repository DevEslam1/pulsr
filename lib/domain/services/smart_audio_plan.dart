// lib/domain/services/smart_audio_plan.dart
//
// The "brain" of Smart Audio: a pure decision that fuses the connected output
// device and the current track with the user's Auto/Manual preference to pick
// (a) which headphone correction to apply and (b) whether this route should
// stay on the DSP path or hand over to the bit-perfect/hi-res path.
//
// Kept pure (no I/O, no platform calls) so the whole policy is unit-testable.
import '../models/audio_output_info.dart';

/// User-facing Smart Audio preference.
///
/// - [auto]: the app adapts per connected device/track automatically.
/// - [manual]: the app makes no automatic choices; existing manual/device
///   profile behavior is untouched.
enum SmartAudioMode {
  manual,
  auto;

  static SmartAudioMode fromName(String? name) => SmartAudioMode.values
      .firstWhere((m) => m.name == name, orElse: () => SmartAudioMode.auto);
}

/// What the DSP/output chain should do for the resolved route.
enum SmartAudioDecision {
  /// Manual mode: make no automatic changes.
  none,

  /// Keep the DSP chain (AutoEQ correction etc.) audible.
  dsp,

  /// Favour the exclusive bit-perfect/hi-res path; the DSP chain is bypassed.
  bitPerfect,
}

/// Resolved plan for the current device + track.
class SmartAudioPlan {
  final SmartAudioMode mode;
  final SmartAudioDecision decision;

  /// Headphone AutoEQ profile to apply, if any.
  final String? headphoneProfileId;

  /// True when the DSP chain should remain in the audible path.
  final bool keepDsp;

  /// True when the route should favour exclusive bit-perfect output.
  final bool preferBitPerfect;

  /// Machine-readable reason (safe to log).
  final String reason;

  const SmartAudioPlan({
    required this.mode,
    required this.decision,
    required this.reason,
    this.headphoneProfileId,
    this.keepDsp = true,
    this.preferBitPerfect = false,
  });

  @override
  String toString() => 'SmartAudioPlan(${mode.name}/${decision.name}, profile: '
      '$headphoneProfileId, keepDsp: $keepDsp, bitPerfect: $preferBitPerfect, '
      'reason: $reason)';
}

/// Classifies an output device as lossy Bluetooth (A2DP or LE Audio).
bool smartAudioIsBluetooth(AudioOutputInfo? info) {
  if (info == null) return false;
  if (info.isBluetooth || info.isLeAudio) return true;
  final type = info.activeDeviceType.toLowerCase();
  return type.contains('blue') ||
      type.contains('ble') ||
      type.contains('hearing');
}

/// Resolves the plan. Precedence, low to high:
///   1. Auto matching (AutoEQ + smart quality arbitration).
///   2. A manual per-device AutoEQ profile (device profile link / user pick).
///   3. [SmartAudioMode.manual] disables all of the above.
SmartAudioPlan resolveSmartAudioPlan({
  required SmartAudioMode mode,
  required AudioOutputInfo? device,
  String? manualHeadphoneProfileId,
  String? matchedHeadphoneProfileId,
  bool trackIsHiRes = false,
  bool deviceSupportsBitPerfect = false,
  bool hasActiveDspEffect = false,
}) {
  if (mode == SmartAudioMode.manual) {
    return SmartAudioPlan(
      mode: mode,
      decision: SmartAudioDecision.none,
      headphoneProfileId: manualHeadphoneProfileId,
      keepDsp: true,
      preferBitPerfect: false,
      reason: 'manual',
    );
  }

  final profileId = manualHeadphoneProfileId ?? matchedHeadphoneProfileId;

  // Bluetooth is always a DSP route: the lossy codec link owns the format and
  // exclusive/bit-perfect output is impossible, so apply the correction.
  if (smartAudioIsBluetooth(device)) {
    return SmartAudioPlan(
      mode: mode,
      decision: SmartAudioDecision.dsp,
      headphoneProfileId: profileId,
      reason: 'auto-bluetooth-dsp',
    );
  }

  // No device info yet: stay on the safe DSP path.
  if (device == null) {
    return SmartAudioPlan(
      mode: mode,
      decision: SmartAudioDecision.dsp,
      headphoneProfileId: profileId,
      reason: 'auto-no-device',
    );
  }

  // Wired/USB with exclusive output supported and no correction requested ->
  // hand over to bit-perfect for ANY sample rate / bit depth, not just hi-res.
  // Bit-perfect runs the DAC at the track's exact native rate and bypasses the
  // OS resampler, so even 16-bit/44.1 "CD" content is delivered bit-exact
  // instead of being resampled to the mixer rate on the shared DSP path — this
  // is the maximum fidelity a capable DAC can produce. If a correction exists
  // OR any user DSP effect is active, keeping the DSP chain wins over raw
  // bit-perfect output: bit-perfect bypasses the whole DSP chain, so engaging
  // it would silently mute the user's active EQ/effects (the no-conflict rule:
  // never bit-perfect ON together with a DSP effect ON).
  //
  // Trade-off accepted for fidelity: the DAC re-locks its clock whenever a
  // track's rate differs from the previous one, which some DACs flag with a
  // brief mute/relock gap. [trackIsHiRes] no longer gates the decision; it only
  // annotates the reason for telemetry.
  if (deviceSupportsBitPerfect &&
      !hasActiveDspEffect &&
      matchedHeadphoneProfileId == null &&
      manualHeadphoneProfileId == null) {
    return SmartAudioPlan(
      mode: mode,
      decision: SmartAudioDecision.bitPerfect,
      keepDsp: false,
      preferBitPerfect: true,
      reason: trackIsHiRes ? 'auto-bitperfect-hires' : 'auto-bitperfect',
    );
  }

  return SmartAudioPlan(
    mode: mode,
    decision: SmartAudioDecision.dsp,
    headphoneProfileId: profileId,
    reason: 'auto-dsp',
  );
}

/// Heuristic: a track is "hi-res" when its native rate exceeds 48 kHz or its
/// bit depth exceeds 16-bit. Unknown (0) values are treated as not hi-res.
/// This no longer gates bit-perfect handover (any rate on a capable DAC now
/// qualifies); it is kept to tag the arbitration reason for telemetry.
bool smartAudioTrackIsHiRes({int sampleRate = 0, int bitDepth = 0}) =>
    sampleRate > 48000 || bitDepth > 16;
