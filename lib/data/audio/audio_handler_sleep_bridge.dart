part of 'audio_handler.dart';

extension PulsrAudioSleepBridge on PulsrAudioHandler {
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerManager.sleepTimerRemainingStream;

  Stream<int?> get sleepTimerRemainingTracksStream =>
      _sleepTimerManager.sleepTimerRemainingTracksStream;

  int? get sleepTimerRemainingTracks =>
      (_sleepTimerManager.isArmed &&
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
  void _notifySleepTrackCompleted() {
    final now = DateTime.now();
    if (!isDistinctSleepCompletion(_lastSleepTrackCompletedAt, now)) return;
    _lastSleepTrackCompletedAt = now;
    unawaited(_sleepTimerManager.onTrackCompleted());
  }

  // Sleep Timer controls
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    _sleepTimerManager.startSleepTimer(
      duration,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    final now = DateTime.now();
    final diff = stopTime.isAfter(now)
        ? stopTime.difference(now)
        : const Duration(minutes: 1);
    _sleepTimerManager.startSleepTimer(
      diff,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startEndOfTrackTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfTrackTimer(
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAfterNTracksTimer(int trackCount, {bool fadeOut = true}) {
    _sleepTimerManager.startAfterNTracksTimer(
      trackCount,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startEndOfQueueTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfQueueTimer(
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void cancelSleepTimer() {
    _sleepTimerManager.cancelSleepTimer();
  }

}
