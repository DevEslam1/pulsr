// lib/features/player/cubit/player_constants.dart
import 'dart:core';

/// Shared constants for the player feature, eliminating magic numbers across controllers and UI.
abstract final class PlayerConstants {
  /// Seek throttle window to prevent flooding AudioHandler with rapid scrubbing calls.
  static const Duration seekThrottleDuration = Duration(milliseconds: 100);
  static const int seekThrottleMs = 100;

  /// Throttling interval for position stream updates to the UI and widget progress.
  static const Duration positionThrottleDuration = Duration(milliseconds: 200);

  /// Throttling interval for home-screen widget metadata and progress updates.
  static const Duration widgetThrottleDuration = Duration(milliseconds: 1000);

  /// Interval between scrobble checks/submissions during playback.
  static const Duration scrobbleInterval = Duration(seconds: 5);

  /// Network timeout for fetching online lyrics (LRCLIB, YTM).
  static const Duration lyricsTimeout = Duration(seconds: 10);

  /// Time-to-live for negative lyrics cache entries (preventing re-queries for missing lyrics).
  static const Duration lyricsNegativeCacheTtl = Duration(minutes: 10);

  /// Maximum zoom factor for waveform scrubbing.
  static const double waveformMaxZoom = 4.0;

  /// Minimum zoom factor for waveform scrubbing.
  static const double waveformMinZoom = 1.0;

  /// Fallback audio bit depth when track metadata does not specify it.
  static const int defaultBitDepth = 16;
}
