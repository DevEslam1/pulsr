part of 'audio_handler.dart';

mixin PulsrAudioSleepBridge on BaseAudioHandler {
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerManager.sleepTimerRemainingStream;

  Stream<int?> get sleepTimerRemainingTracksStream =>
      _sleepTimerManager.sleepTimerRemainingTracksStream;

  int? get sleepTimerRemainingTracks => (_sleepTimerManager.isArmed &&
          (_sleepTimerManager.mode == SleepTimerMode.endOfTrack ||
              _sleepTimerManager.mode == SleepTimerMode.afterNTracks))
      ? _sleepTimerManager.remainingTracks
      : null;

  SleepTimerMode get sleepTimerMode => _sleepTimerManager.mode;

  /// Single funnel for "a track finished" so the sleep timer's after-N-tracks
  /// and end-of-track modes decrement exactly once per boundary. In gapless
  /// mode a boundary is reported twice — native `completed` plus the
  /// `currentIndexStream` advance — and feeding both straight into
  /// [SleepTimerManager.onTrackCompleted] halved an "after N songs" timer.
  void notifySleepTrackCompleted() {
    final now = DateTime.now();
    if (!PulsrAudioHandler.isDistinctSleepCompletion(
        _lastSleepTrackCompletedAt, now)) {
      return;
    }
    _lastSleepTrackCompletedAt = now;
    unawaited(_sleepTimerManager.onTrackCompleted());
  }

  Future<void> _onSleepTimerExpired() => pause();

  // Sleep Timer controls
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    // A zero/negative timer would fire instantly and pause playback.
    if (duration <= Duration.zero) {
      cancelSleepTimer();
      return;
    }
    _sleepTimerManager.startSleepTimer(
      duration,
      fadeOut: fadeOut,
      onTimerExpired: _onSleepTimerExpired,
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    final now = DateTime.now();
    final diff = stopTime.isAfter(now)
        ? stopTime.difference(now)
        : const Duration(minutes: 1);
    startSleepTimer(diff, fadeOut: fadeOut);
  }

  void startEndOfTrackTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfTrackTimer(
      fadeOut: fadeOut,
      onTimerExpired: _onSleepTimerExpired,
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAfterNTracksTimer(int trackCount, {bool fadeOut = true}) {
    if (trackCount <= 0) {
      cancelSleepTimer();
      return;
    }
    final durations = <Duration>[];
    if (_songs.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _songs.length) {
      for (int i = _currentIndex;
          i < _songs.length && durations.length < trackCount;
          i++) {
        var d = Duration(milliseconds: _songs[i].durationMs);
        if (i == _currentIndex) {
          // The current track is already partly played: only its remainder
          // counts toward the timer.
          final remaining = d - _activePlayer.position;
          if (remaining > Duration.zero) d = remaining;
        }
        durations.add(d);
      }
    }
    // Streams / unscanned rows report durationMs == 0; a zero in the list
    // would skew the fade-out schedule, so fall back to "unknown".
    final usable =
        durations.isNotEmpty && durations.every((d) => d > Duration.zero);
    _sleepTimerManager.startAfterNTracksTimer(
      trackCount,
      fadeOut: fadeOut,
      trackDurations: usable ? durations : null,
      onTimerExpired: _onSleepTimerExpired,
      getActivePlayer: () => _activePlayer,
    );
  }

  void startEndOfQueueTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfQueueTimer(
      fadeOut: fadeOut,
      onTimerExpired: _onSleepTimerExpired,
      getActivePlayer: () => _activePlayer,
    );
  }

  void cancelSleepTimer() {
    _sleepTimerManager.cancelSleepTimer();
  }

  // Abstract contract supplied by the composing PulsrAudioHandler (same
  // library). Declaring these here keeps the mixin stateless and lets the
  // analyser type-check each mixin against the host's private members.
  AudioPlayer get _activePlayer;
  List<SongsTableData> get _songs;
  int get _currentIndex;

  DateTime? get _lastSleepTrackCompletedAt;
  set _lastSleepTrackCompletedAt(DateTime? value);

  SleepTimerManager get _sleepTimerManager;
}
