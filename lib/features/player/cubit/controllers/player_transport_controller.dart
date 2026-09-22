// lib/features/player/cubit/controllers/player_transport_controller.dart
// FIX-A1: Focused PlayerTransportController extracted from PlayerCubit
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../player_state.dart';

/// Owns audio transport controls: play, pause, seek, track skipping, shuffle, and repeat.
class PlayerTransportController {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final void Function(bool intentional)? _onUserPausedIntentionally;

  // Monotonic stopwatch for seek throttling
  static final Stopwatch _seekStopwatch = Stopwatch()..start();
  int _lastSeekMs = 0;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeek;

  PlayerTransportController({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    void Function(bool intentional)? onUserPausedIntentionally,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _onUserPausedIntentionally = onUserPausedIntentionally;

  Future<void> play() async {
    try {
      _onUserPausedIntentionally?.call(false);
      await _audioHandler.play();
      if (!_isClosed()) {
        _emit(_getState().copyWith(isPlaying: true, errorMessage: null));
      }
    } catch (e, st) {
      ErrorLogger.log('Play failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(errorMessage: 'Failed to start playback'));
      }
    }
  }

  Future<void> pause() async {
    try {
      _onUserPausedIntentionally?.call(true);
      _emit(_getState().copyWith(isPlaying: false));
      await _audioHandler.pause();
    } catch (e, st) {
      ErrorLogger.log('Pause failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(errorMessage: 'Failed to pause playback'));
      }
    }
  }

  Future<void> togglePlayPause() async {
    HapticFeedback.lightImpact();
    try {
      final state = _getState();
      final enginePlaying = _audioHandler.playbackState.value.playing;
      final shouldPause = state.isPlaying || enginePlaying;

      if (state.isPlaying != shouldPause) {
        _emit(state.copyWith(isPlaying: shouldPause));
      }
      if (shouldPause) {
        _onUserPausedIntentionally?.call(true);
        _emit(state.copyWith(isPlaying: false));
        await _audioHandler.pause();
      } else {
        if (state.currentSong == null && state.queue.isEmpty) return;
        _onUserPausedIntentionally?.call(false);
        await _audioHandler.play();
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle play/pause failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(errorMessage: 'Playback action failed'));
      }
    }
  }

  Future<void> seek(Duration position) {
    if (_isClosed()) return Future.value();
    final state = _getState();
    var target = position.isNegative ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }

    _emit(state.copyWith(position: target));

    final nowMs = _seekStopwatch.elapsedMilliseconds;
    if (nowMs - _lastSeekMs < 100) {
      _pendingSeek = target;
      _seekThrottleTimer?.cancel();
      _seekThrottleTimer = Timer(
        Duration(milliseconds: 100 - (nowMs - _lastSeekMs)),
        () {
          if (_isClosed()) {
            _pendingSeek = null;
            return;
          }
          final pending = _pendingSeek;
          _pendingSeek = null;
          if (pending != null) {
            _lastSeekMs = _seekStopwatch.elapsedMilliseconds;
            _audioHandler.seek(pending).catchError((Object e, StackTrace st) {
              ErrorLogger.log('Coalesced seek failed',
                  error: e, stackTrace: st, category: 'PlayerTransportController');
              if (!_isClosed()) {
                _emit(_getState().copyWith(
                    errorMessage: 'Seek failed, position restored'));
              }
            });
          }
        },
      );
      return Future.value();
    }
    _lastSeekMs = nowMs;

    return _audioHandler.seekDirect(target).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Discrete seek failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(errorMessage: 'Seek failed, position restored'));
      }
    });
  }

  Future<void> next() async {
    try {
      await _audioHandler.skipToNext();
    } catch (e, st) {
      ErrorLogger.log('Skip to next failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) _emit(_getState().copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> previous() async {
    try {
      await _audioHandler.skipToPrevious();
    } catch (e, st) {
      ErrorLogger.log('Skip to previous failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) _emit(_getState().copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> skipToQueueItem(int index) async {
    final state = _getState();
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.skipToQueueItem(index);
    } catch (e, st) {
      ErrorLogger.log('Skip to queue item failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) _emit(_getState().copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> toggleShuffle() async {
    final state = _getState();
    final prev = state.isShuffle;
    final next = !prev;
    _emit(state.copyWith(isShuffle: next, errorMessage: null));
    try {
      await _audioHandler.setShuffleMode(
          next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
    } catch (e, st) {
      ErrorLogger.log('Toggle shuffle failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(isShuffle: prev, errorMessage: 'Shuffle failed'));
      }
    }
  }

  Future<void> toggleRepeat() async {
    final state = _getState();
    final prev = state.repeatMode;
    final next = switch (prev) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    final nextMode = switch (next) {
      PlayerRepeatMode.off => AudioServiceRepeatMode.none,
      PlayerRepeatMode.all => AudioServiceRepeatMode.all,
      PlayerRepeatMode.one => AudioServiceRepeatMode.one,
    };
    _emit(state.copyWith(repeatMode: next, errorMessage: null));
    try {
      await _audioHandler.setRepeatMode(nextMode);
    } catch (e, st) {
      ErrorLogger.log('Toggle repeat failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        _emit(_getState().copyWith(repeatMode: prev, errorMessage: 'Repeat failed'));
      }
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.25, 3.0);
    _emit(_getState().copyWith(playbackSpeed: clamped, errorMessage: null));
    try {
      await _audioHandler.setSpeed(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set speed failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
    }
  }

  Future<void> setPlaybackPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0);
    _emit(_getState().copyWith(playbackPitch: clamped, errorMessage: null));
    try {
      await _audioHandler.setPitch(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set pitch failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
    }
  }

  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) async {
    final state = _getState();
    await seek(state.position + step);
  }

  Future<void> rewind([Duration step = const Duration(seconds: 10)]) async {
    final state = _getState();
    await seek(state.position - step);
  }

  void dispose() {
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
  }
}
