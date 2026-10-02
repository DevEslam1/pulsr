// lib/domain/interfaces/scrobble_sink_interface.dart
// FIX-A2: Dependency inversion interface for music scrobbling

/// Contract for dispatching playback state events to Last.fm / Libre.fm /
/// ListenBrainz scrobblers.
///
/// Failure semantics:
/// - [notifyPlaybackState] is fire-and-forget (`void`): it must never throw
///   into the playback path. A remote scrobble failure is reported through the
///   scrobbler's own queue/status, not by propagating an exception here.
/// - Calls are advisory: dropping an event (e.g. while offline) is allowed and
///   must not corrupt local playback or progress accounting.
abstract class IScrobbleSink {
  /// Notifies the scrobbler service of track playback progress and state
  /// transitions. Never throws.
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
