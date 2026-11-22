import 'dart:async';

import '../../../../data/audio/audio_handler.dart';
import '../../../../data/audio/sleep_timer_manager.dart';
import '../player_state.dart';

/// Sleep-timer arm/cancel intent translated into audio-handler calls and state
/// emissions.
class PlaybackSleepTimer {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;

  PlaybackSleepTimer({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit;

  void start(int minutes) {
    if (minutes <= 0) return;
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: duration,
        sleepTimerRemainingTracks: null,
        sleepTimerMode: SleepTimerMode.duration,
        isEndOfQueueSleepTimer: false,
      ),
    ));
  }

  void startAbsolute(DateTime stopTime) {
    var effectiveStopTime = stopTime;
    final now = DateTime.now();
    // AUDIT-FIX (P2-20): Advance stale timestamps (>24h in past) to the next
    // future 24h cycle and clamp remaining non-negative.
    var diff = effectiveStopTime.difference(now);
    if (diff.isNegative) {
      final daysToAdd =
          ((-diff.inMicroseconds) ~/ Duration.microsecondsPerDay) + 1;
      effectiveStopTime = effectiveStopTime.add(Duration(days: daysToAdd));
      diff = effectiveStopTime.difference(now);
      if (diff.isNegative) {
        diff = Duration.zero;
      }
    }
    _audioHandler.startAbsoluteSleepTimer(effectiveStopTime);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: diff,
        sleepTimerRemainingTracks: null,
        sleepTimerMode: SleepTimerMode.duration,
        isEndOfQueueSleepTimer: false,
      ),
    ));
  }

  void startEndOfTrack() {
    _audioHandler.startEndOfTrackTimer();
    final s = _getState();
    final remaining = s.duration > s.position
        ? s.duration - s.position
        : const Duration(minutes: 1);
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: remaining,
        sleepTimerRemainingTracks: null,
        sleepTimerMode: SleepTimerMode.endOfTrack,
        isEndOfQueueSleepTimer: false,
      ),
    ));
  }

  void startAfterNTracks(int trackCount) {
    if (trackCount <= 0) return;
    _audioHandler.startAfterNTracksTimer(trackCount);
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: trackCount,
        sleepTimerMode: SleepTimerMode.afterNTracks,
        isEndOfQueueSleepTimer: false,
      ),
    ));
  }

  void startEndOfQueue() {
    _audioHandler.startEndOfQueueTimer();
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: null,
        sleepTimerMode: SleepTimerMode.endOfQueue,
        isEndOfQueueSleepTimer: true,
      ),
    ));
  }

  void cancel() {
    _audioHandler.cancelSleepTimer();
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        sleepTimerRemaining: null,
        sleepTimerRemainingTracks: null,
        sleepTimerMode: null,
        isEndOfQueueSleepTimer: false,
      ),
    ));
  }

  int? get remainingTracks => _audioHandler.sleepTimerRemainingTracks;
  SleepTimerMode get mode => _audioHandler.sleepTimerMode;
  bool get isEndOfQueue => mode == SleepTimerMode.endOfQueue;
  Stream<int?> get remainingTracksStream =>
      _audioHandler.sleepTimerRemainingTracksStream;
}
