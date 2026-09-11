// lib/data/audio/output_format_negotiation.dart
//
// Pure, side-effect-free decision for the output format the engine should
// request for a track. Extracted from the manual, device-global setting so the
// policy can be unit-tested without a device, a platform channel or a player.
//
// Guarantees enforced here (and proven by the table test):
//   * the chosen format never exceeds the device's advertised caps;
//   * when there is no explicit user request, the track's native rate is
//     requested whenever the device supports it — a higher available tier is
//     never silently traded for a lower one;
//   * when the request cannot be honoured, the highest supported tier below it
//     is chosen and a machine-readable `reasonCode` is returned.
//
// The caller owns the side effect (calling `setTargetOutputFormat`); this file
// only decides.
import 'dart:math' as math;

import '../../domain/models/audio_output_info.dart';

/// Output route class the format is negotiated for.
enum OutputRoute {
  speaker,
  wired,
  bluetooth;

  /// Classifies an [AudioOutputInfo] the same way the session telemetry does.
  static OutputRoute fromOutputInfo(AudioOutputInfo? info) {
    if (info == null) return OutputRoute.speaker;
    final type = info.activeDeviceType.toLowerCase();
    if (info.isBluetooth ||
        info.isLeAudio ||
        type.contains('blue') ||
        type.contains('ble') ||
        type.contains('hearing')) {
      return OutputRoute.bluetooth;
    }
    if (info.isUsbDac ||
        type.contains('usb') ||
        type.contains('wired') ||
        type.contains('headphone') ||
        type.contains('headset')) {
      return OutputRoute.wired;
    }
    return OutputRoute.speaker;
  }
}

/// Stable reason codes for a negotiation outcome (safe to persist/log).
enum OutputFormatReason {
  /// Exclusive/bit-perfect output owns the format; the caller must not override.
  bitPerfectExclusive,

  /// No track or user preference known — take the device's best tier.
  autoDeviceDefault,

  /// The track's own rate was requested and the device supports it exactly.
  exactTrackMatch,

  /// An explicit user-selected rate was honoured.
  userRequested,

  /// The requested tier is not supported; the highest supported lower tier was
  /// chosen instead (never a lower one than necessary).
  deviceRateLimited,

  /// The user explicitly asked for a rate below the track's native rate.
  userRequestedBelowTrack,
}

/// Inputs for [negotiateOutputFormat].
class OutputFormatRequest {
  /// Native sample rate of the track; 0 when unknown.
  final int trackSampleRate;

  /// Native bit depth of the track; 0 when unknown.
  final int trackBitDepth;

  /// Explicit user target rate; 0 means "auto" (follow the track).
  final int requestedSampleRate;

  /// Explicit user target depth; 0 means "auto" (follow the track/caps).
  final int requestedBitDepth;

  const OutputFormatRequest({
    this.trackSampleRate = 0,
    this.trackBitDepth = 0,
    this.requestedSampleRate = 0,
    this.requestedBitDepth = 0,
  });
}

/// Result of a negotiation. [applied] is false only when the exclusive
/// bit-perfect path owns the format.
class OutputFormatDecision {
  final int sampleRate;
  final int bitDepth;
  final bool applied;
  final bool isBelowTrackRate;
  final bool isBelowTrackDepth;
  final OutputFormatReason reason;

  const OutputFormatDecision({
    required this.sampleRate,
    required this.bitDepth,
    required this.reason,
    this.applied = true,
    this.isBelowTrackRate = false,
    this.isBelowTrackDepth = false,
  });

  /// Stable machine name for logs / telemetry.
  String get reasonCode => reason.name;

  @override
  String toString() => 'OutputFormatDecision(${sampleRate}Hz/${bitDepth}bit, '
      'applied: $applied, reason: $reasonCode, '
      'belowTrackRate: $isBelowTrackRate, belowTrackDepth: $isBelowTrackDepth)';
}

/// Fallback caps when the platform reports no usable device information.
const List<int> kFallbackOutputSampleRates = <int>[44100, 48000];

/// Lossy Bluetooth transports top out at 96 kHz (LDAC); anything above is a
/// platform echo, not a sink the A2DP stack can actually feed.
const int kBluetoothMaxSampleRate = 96000;

/// Decides the output format to request. Pure: no I/O, no platform calls.
OutputFormatDecision negotiateOutputFormat({
  required OutputFormatRequest request,
  required List<int> deviceSampleRates,
  required int deviceMaxBitDepth,
  required OutputRoute route,
  required bool bitPerfectActive,
}) {
  final trackRate = request.trackSampleRate > 0 ? request.trackSampleRate : 0;
  final trackDepth = request.trackBitDepth > 0 ? request.trackBitDepth : 0;
  final explicitRate =
      request.requestedSampleRate > 0 ? request.requestedSampleRate : 0;
  final explicitDepth =
      request.requestedBitDepth > 0 ? request.requestedBitDepth : 0;

  // Bit-perfect / exclusive output negotiates its own mixer attributes; asking
  // the shared output format would fight it. Report the intent, applied:false.
  if (bitPerfectActive) {
    return OutputFormatDecision(
      sampleRate: explicitRate > 0 ? explicitRate : trackRate,
      bitDepth: explicitDepth > 0 ? explicitDepth : trackDepth,
      reason: OutputFormatReason.bitPerfectExclusive,
      applied: false,
    );
  }

  // Sanitize device caps (never trust 0 / out-of-range values).
  var rates = deviceSampleRates.where((r) => r > 0).toSet().toList()..sort();
  if (routesThroughBluetooth(route)) {
    rates = rates.where((r) => r <= kBluetoothMaxSampleRate).toList();
  }
  if (rates.isEmpty) {
    rates = List<int>.of(kFallbackOutputSampleRates);
  }
  var maxDepth = deviceMaxBitDepth;
  if (maxDepth != 16 && maxDepth != 24 && maxDepth != 32) maxDepth = 16;

  final desiredRate = explicitRate > 0 ? explicitRate : trackRate;
  int chosenRate;
  OutputFormatReason reason;
  if (desiredRate <= 0) {
    chosenRate = rates.last;
    reason = OutputFormatReason.autoDeviceDefault;
  } else if (rates.contains(desiredRate)) {
    chosenRate = desiredRate;
    if (explicitRate > 0) {
      reason = (trackRate > 0 && explicitRate < trackRate)
          ? OutputFormatReason.userRequestedBelowTrack
          : OutputFormatReason.userRequested;
    } else {
      reason = OutputFormatReason.exactTrackMatch;
    }
  } else {
    // Highest supported rate that does not exceed the request; if the request
    // is below every supported rate, the device cannot go lower.
    final atOrBelow = rates.where((r) => r <= desiredRate).toList();
    chosenRate = atOrBelow.isNotEmpty ? atOrBelow.last : rates.first;
    if (trackRate > 0 &&
        chosenRate < trackRate &&
        explicitRate > 0 &&
        explicitRate <= trackRate) {
      reason = OutputFormatReason.userRequestedBelowTrack;
    } else {
      reason = OutputFormatReason.deviceRateLimited;
    }
  }

  final desiredDepth = explicitDepth > 0 ? explicitDepth : trackDepth;
  var chosenDepth =
      desiredDepth <= 0 ? maxDepth : math.min(desiredDepth, maxDepth);
  if (chosenDepth != 16 && chosenDepth != 24 && chosenDepth != 32) {
    chosenDepth = 16;
  }

  return OutputFormatDecision(
    sampleRate: chosenRate,
    bitDepth: chosenDepth,
    reason: reason,
    isBelowTrackRate: trackRate > 0 && chosenRate < trackRate,
    isBelowTrackDepth: trackDepth > 0 && chosenDepth < trackDepth,
  );
}

/// True when the route's transport is lossy Bluetooth (rate-capped).
bool routesThroughBluetooth(OutputRoute route) =>
    route == OutputRoute.bluetooth;
