// lib/domain/interfaces/scrobble_sink_interface.dart
// FIX-A2: Dependency inversion interface for music scrobbling

/// Contract for dispatching playback state events to Last.fm / Libre.fm / ListenBrainz scrobblers.
abstract class IScrobbleSink {
  /// Notifies the scrobbler service of track playback progress and state transitions.
  void notifyPlaybackState({
    required int id,
    required String artist,
    required String track,
    required String album,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    required bool isQuran,
  });
}
