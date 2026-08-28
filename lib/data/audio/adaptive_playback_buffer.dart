/// Dynamic buffer sizing calculator based on network speed, connection type, and track bitrate.
class AdaptivePlaybackBuffer {
  /// Calculates initial start buffer duration before playback begins.
  /// Fast Wi-Fi (>=8 Mbps): 800ms
  /// Standard Cellular (2-8 Mbps): 1200ms
  /// Poor network (<2 Mbps): 2500ms
  static Duration calculateStartBuffer({
    required double networkSpeedMbps,
    required bool isWifi,
  }) {
    final speed =
        networkSpeedMbps <= 0 ? (isWifi ? 10.0 : 2.0) : networkSpeedMbps;
    if (isWifi && speed >= 8.0) {
      return const Duration(milliseconds: 800);
    } else if (speed >= 2.0) {
      return const Duration(milliseconds: 1200);
    } else {
      return const Duration(milliseconds: 2500);
    }
  }

  /// Calculates optimal buffer duration based on bitrate (kbps), network speed (Mbps),
  /// and whether the device is on Wi-Fi or Cellular network.
  static Duration calculateBuffer({
    required int bitrateKbps,
    required double networkSpeedMbps,
    required bool isWifi,
  }) {
    // If invalid inputs or offline, fallback to safe defaults
    final safeBitrate = bitrateKbps <= 0 ? 320 : bitrateKbps;
    final safeSpeed =
        networkSpeedMbps <= 0 ? (isWifi ? 10.0 : 2.0) : networkSpeedMbps;

    const trackDurationEstimate = Duration(seconds: 240);
    // Data needed in Megabits = (kbps * duration_seconds) / 1000.0
    final dataNeededMb =
        (safeBitrate * trackDurationEstimate.inSeconds) / 1000.0;
    final downloadTimeSec = dataNeededMb / safeSpeed;

    if (isWifi) {
      final targetSeconds = (downloadTimeSec * 1.2).ceil().clamp(5, 30);
      return Duration(seconds: targetSeconds);
    } else {
      final targetSeconds = (downloadTimeSec * 2.0).ceil().clamp(10, 60);
      return Duration(seconds: targetSeconds);
    }
  }

  /// Calculates pre-buffer duration for gapless preload streams.
  static Duration calculatePreloadBuffer({
    required int bitrateKbps,
    required bool isWifi,
  }) {
    if (isWifi) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 8);
  }
}
