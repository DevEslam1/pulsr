// lib/data/audio/tap_src_policy.dart
//
// Pure decision for the tap-side sample-rate converter: the rate the PCM tap
// should convert TO, or 0 to leave rate conversion to the platform mixer.
//
// Why this exists: without it, the native DSP chain finishes (EQ, noise
// shaping, dither, limiting) and AudioFlinger then resamples the result with
// its own short-kernel converter. The tap converts ahead of the chain instead,
// at Ultra quality, so the mixer receives the rate it wanted and copies 1:1.
//
// Extracted from the cubit so the whole policy is unit-testable without a
// device, a platform channel or a player.

/// Bounds the native tap accepts; outside them the request is ignored natively.
const int kTapSrcMinRate = 8000;
const int kTapSrcMaxRate = 768000;

/// Returns the mixer rate the tap should target, or 0 for "convert nothing".
///
/// The target is the platform's native mixer rate ([nativeSampleRate], from
/// `AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE`) — NOT the app's own AudioTrack
/// rate, which is the track rate whenever the mixer is the one resampling.
///
/// Every guard below exists because a wrong target is not a silent failure: the
/// sink would be opened at a rate the hardware does not use and the track plays
/// at the wrong pitch, so an unknown or unverifiable rate must return 0.
int decideTapSrcTargetRate({
  required bool enabled,
  required int nativeSampleRate,
  required bool bitPerfectActive,
  required bool isBluetooth,
  required List<int> deviceSampleRates,
}) {
  if (!enabled) return 0;
  // Bit-perfect promises sample-identical output; resampled bytes cannot keep
  // that promise. (The native processor guards this too, on the same basis.)
  if (bitPerfectActive) return 0;
  // The A2DP link owns its own rate and codec-alignment path; converting to the
  // phone's mixer rate would be a conversion the Bluetooth path never needs.
  if (isBluetooth) return 0;
  if (nativeSampleRate < kTapSrcMinRate || nativeSampleRate > kTapSrcMaxRate) {
    return 0;
  }
  // When the routed device advertises what it can actually run, the target must
  // be in that list. An empty list means "unverified", which is not evidence
  // that the rate is unusable, so it does not veto.
  if (deviceSampleRates.isNotEmpty &&
      !deviceSampleRates.contains(nativeSampleRate)) {
    return 0;
  }
  return nativeSampleRate;
}
