// lib/data/audio/interruption_state_machine.dart

/// The kind of audio-focus interruption that began.
enum InterruptionKind { duck, pause, unknown }

/// Pure, type-safe bookkeeping for audio-session interruptions.
///
/// It owns exactly the two facts the audio handler needs to make a
/// resume decision:
///   * *which* interruption kind (if any) currently holds the pause, and
///   * whether playback was running when that interruption began.
///
/// Tracking the kind instead of two independent booleans guarantees that an
/// interruption's end only clears the state its own begin established: one
/// interruption type can never leave another type's begin half-open (B-1).
///
/// This type is deliberately free of platform dependencies so the decision
/// logic is unit-testable without constructing [PulsrAudioHandler].
class InterruptionStateMachine {
  InterruptionKind? _activeKind;
  bool _wasPlaying = false;

  /// The interruption kind currently holding the pause, or null.
  InterruptionKind? get activeKind => _activeKind;

  /// Whether playback was running when the active interruption began.
  bool get wasPlayingBeforeInterruption => _wasPlaying;

  /// Whether any interruption currently holds the pause.
  bool get isActive => _activeKind != null;

  /// Records the start of [kind], snapshotting [playing].
  ///
  /// Stack-safe: the first begin wins, so an overlapping duck + phone call
  /// cannot clobber the original pre-interruption snapshot.
  void begin(InterruptionKind kind, {required bool playing}) {
    if (_activeKind != null) return;
    _activeKind = kind;
    _wasPlaying = playing;
  }

  /// For a permanent/unknown focus loss: never auto-resume, even if playback
  /// was running when the interruption began.
  void neverResume() {
    _wasPlaying = false;
  }

  /// Records the end of [kind].
  ///
  /// Returns whether playback was running when that kind began, and clears the
  /// state. If [kind] is not the active kind this returns false and leaves the
  /// other kind's state untouched.
  bool end(InterruptionKind kind) {
    if (_activeKind != kind) return false;
    final wasPlaying = _wasPlaying;
    _activeKind = null;
    _wasPlaying = false;
    return wasPlaying;
  }

  /// An explicit user/system pause invalidates any pending interruption
  /// bookkeeping: the pre-interruption "was playing" fact is stale, and a later
  /// interruption must be able to snapshot afresh (B-1).
  void onUserPause() {
    _activeKind = null;
    _wasPlaying = false;
  }

  /// Clears everything unconditionally (permanent/unknown focus loss end).
  void reset() {
    _activeKind = null;
    _wasPlaying = false;
  }
}
