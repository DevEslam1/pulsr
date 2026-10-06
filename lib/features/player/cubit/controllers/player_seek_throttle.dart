// lib/features/player/cubit/controllers/player_seek_throttle.dart
import 'dart:async';

import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../player_constants.dart';
import '../player_state.dart';

/// Owns the monotonic seek throttle: coalesces rapid seek-bar drags onto one
/// trailing engine seek and restores the previous position when a seek fails.
class PlayerSeekThrottle {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;

  // Monotonic stopwatch for seek throttling. H-05: instance-scoped so separate
  // controller instances (e.g. test + prod) never share throttle state.
  final Stopwatch _stopwatch = Stopwatch()..start();
  int _lastSeekMs = -PlayerConstants.seekThrottleMs;
  Timer? _throttleTimer;
  Duration? _pendingSeek;
  Completer<void>? _pendingCompleter;

  PlayerSeekThrottle({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed;

  Future<void> seek(Duration position) {
    if (_isClosed()) return Future.value();
    final state = _getState();
    final enginePos = _audioHandler.playbackState.value.position;
    final prevPosition = enginePos > Duration.zero ? enginePos : state.position;
    var target = position.isNegative ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }

    _emit(state.copyWith(playback: state.playback.copyWith(position: target)));

    final nowMs = _stopwatch.elapsedMilliseconds;
    if (nowMs - _lastSeekMs < PlayerConstants.seekThrottleMs) {
      _pendingSeek = target;
      final completer = _pendingCompleter ??= Completer<void>();
      _throttleTimer?.cancel();
      _throttleTimer = Timer(
        Duration(
            milliseconds:
                (PlayerConstants.seekThrottleMs - (nowMs - _lastSeekMs))
                    .clamp(16, PlayerConstants.seekThrottleMs)),
        () {
          if (_isClosed()) {
            _pendingSeek = null;
            if (!completer.isCompleted) completer.complete();
            _pendingCompleter = null;
            return;
          }
          final pending = _pendingSeek;
          _pendingSeek = null;
          final c = _pendingCompleter;
          _pendingCompleter = null;
          if (pending != null && !_isClosed()) {
            _lastSeekMs = _stopwatch.elapsedMilliseconds;
            _audioHandler.seek(pending).catchError((Object e, StackTrace st) {
              ErrorLogger.log('Coalesced seek failed',
                  error: e,
                  stackTrace: st,
                  category: 'PlayerTransportController');
              if (!_isClosed()) {
                // C-2: Restore position so seek bar snaps back to where it was.
                final s = _getState();
                _emit(s.copyWith(
                  playback: s.playback.copyWith(
                    position: prevPosition,
                    errorMessage: 'Seek failed, position restored',
                  ),
                ));
              }
            }).whenComplete(() {
              if (c != null && !c.isCompleted) c.complete();
            });
          } else {
            if (c != null && !c.isCompleted) c.complete();
          }
        },
      );
      return completer.future;
    }

    _pendingSeek = null;
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete();
    }
    _pendingCompleter = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _lastSeekMs = nowMs;

    return _audioHandler
        .seekDirect(target)
        .catchError((Object e, StackTrace st) {
      ErrorLogger.log('Discrete seek failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        // C-2: Restore position so seek bar snaps back to where it was.
        final s = _getState();
        _emit(s.copyWith(
          playback: s.playback.copyWith(
            position: prevPosition,
            errorMessage: 'Seek failed, position restored',
          ),
        ));
      }
    });
  }

  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _pendingSeek = null;
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete();
    }
    _pendingCompleter = null;
  }
}
