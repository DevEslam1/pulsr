// lib/data/audio/playback_backend.dart
//
// PlaybackBackend abstraction and capability contract (Section 5.1).
// Provides the seam between high-level queue / session management and the
// audio rendering engine (LocalPCM, LocalDSD, Cast, UPnP).

import 'dart:async';
import 'package:audio_service/audio_service.dart';

/// Capabilities exposed by a [PlaybackBackend] instance.
class BackendCapabilities {
  final bool canSeek;
  final bool canGapless;
  final bool canCrossfade;
  final bool canRateSwitch;
  final bool canSoftwareVolume;
  final bool canLocalDsp;
  final bool canReplayGain;
  final bool canSleepFade;
  final bool isRemote;
  final int latencyFrames;

  const BackendCapabilities({
    required this.canSeek,
    required this.canGapless,
    required this.canCrossfade,
    required this.canRateSwitch,
    required this.canSoftwareVolume,
    required this.canLocalDsp,
    required this.canReplayGain,
    required this.canSleepFade,
    required this.isRemote,
    this.latencyFrames = 0,
  });

  /// Standard Local PCM engine (ExoPlayer/just_audio A/B + C++ DSP).
  static const BackendCapabilities localPcm = BackendCapabilities(
    canSeek: true,
    canGapless: true,
    canCrossfade: true,
    canRateSwitch: true,
    canSoftwareVolume: true,
    canLocalDsp: true,
    canReplayGain: true,
    canSleepFade: true,
    isRemote: false,
    latencyFrames: 0,
  );

  /// Direct USB DSD / DoP bitstream engine.
  static const BackendCapabilities localDsd = BackendCapabilities(
    canSeek: true,
    canGapless: true,
    canCrossfade: false,
    canRateSwitch: true,
    canSoftwareVolume: false,
    canLocalDsp: false,
    canReplayGain: false,
    canSleepFade: false,
    isRemote: false,
    latencyFrames: 0,
  );

  /// Google Cast remote playback via local proxy.
  static const BackendCapabilities cast = BackendCapabilities(
    canSeek: true,
    canGapless: false,
    canCrossfade: false,
    canRateSwitch: false,
    canSoftwareVolume: false,
    canLocalDsp: false,
    canReplayGain: false,
    canSleepFade: false,
    isRemote: true,
    latencyFrames: 0,
  );

  /// DLNA / UPnP remote media renderer.
  static const BackendCapabilities upnp = BackendCapabilities(
    canSeek: true,
    canGapless: false,
    canCrossfade: false,
    canRateSwitch: false,
    canSoftwareVolume: false,
    canLocalDsp: false,
    canReplayGain: false,
    canSleepFade: false,
    isRemote: true,
    latencyFrames: 0,
  );
}

/// Abstract contract for an audio rendering backend.
abstract class PlaybackBackend {
  BackendCapabilities get capabilities;

  Future<void> prepare(MediaItem item, {MediaItem? next});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
  Future<void> setVolume(double volume);

  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<PlaybackState> get stateStream;
  Stream<void> get completedStream;
}
