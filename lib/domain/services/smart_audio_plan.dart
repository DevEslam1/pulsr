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
  String toString() =>
      'SmartAudioPlan(${mode.name}/${decision.name}, profile: '
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

  // Wired/USB, hi-res track, exclusive output supported, and no correction
  // requested -> hand over to bit-perfect. If a correction exists, keeping the
  // DSP chain (and thus the correction) wins over raw bit-perfect output.
  if (deviceSupportsBitPerfect &&
      trackIsHiRes &&
      matchedHeadphoneProfileId == null &&
      manualHeadphoneProfileId == null) {
    return SmartAudioPlan(
      mode: mode,
      decision: SmartAudioDecision.bitPerfect,
      keepDsp: false,
      preferBitPerfect: true,
      reason: 'auto-bitperfect',
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
/// bit depth exceeds 16-bit. Unknown (0) values are treated as not hi-res so a
/// missing tag never promotes bit-perfect output.
bool smartAudioTrackIsHiRes({int sampleRate = 0, int bitDepth = 0}) =>
    sampleRate > 48000 || bitDepth > 16;
