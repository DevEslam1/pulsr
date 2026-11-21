// lib/data/services/cast_playback_handoff.dart
//
// Cast is a separate renderer. Starting a session must silence the local
// player, and ending it should restore only the playback this service paused.

import 'dart:async';

import '../../core/utils/error_logger.dart';
import 'cast_service.dart';

class CastPlaybackHandoff {
  CastPlaybackHandoff({
    required this.isLocalPlaying,
    required this.pauseLocal,
    required this.resumeLocal,
  });

  final bool Function() isLocalPlaying;
  final Future<void> Function() pauseLocal;
  final Future<void> Function() resumeLocal;

  StreamSubscription<CastSessionStatus>? _sub;
  bool _pausedByCast = false;
  bool _wasConnected = false;

  void start() {
    if (_sub != null) return;
    _wasConnected = CastService().sessionStatus.connected;
    if (_wasConnected && isLocalPlaying()) {
      unawaited(_pause());
    }
    unawaited(CastService().isSessionAvailable());
    _sub = CastService().sessionStream.listen(
      _onStatus,
      onError: (Object e, StackTrace st) {
        ErrorLogger.log('Cast handoff status stream failed',
            error: e, stackTrace: st, category: 'CastPlaybackHandoff');
      },
    );
  }

  void _onStatus(CastSessionStatus status) {
    final connected = status.connected;
    if (connected && !_wasConnected) {
      _wasConnected = true;
      if (isLocalPlaying()) {
        unawaited(_pause());
      }
      return;
    }
    if (!connected && _wasConnected) {
      _wasConnected = false;
      if (_pausedByCast) {
        _pausedByCast = false;
        unawaited(_resume());
      }
    }
  }

  Future<void> _pause() async {
    _pausedByCast = true;
    try {
      await pauseLocal();
    } catch (e, st) {
      _pausedByCast = false;
      ErrorLogger.log('Cast handoff pause failed',
          error: e, stackTrace: st, category: 'CastPlaybackHandoff');
      return;
    }
    if (!CastService().sessionStatus.connected) {
      if (_pausedByCast) {
        _pausedByCast = false;
        unawaited(_resume());
      }
    }
  }

  Future<void> _resume() async {
    try {
      await resumeLocal();
    } catch (e, st) {
      ErrorLogger.log('Cast handoff resume failed',
          error: e, stackTrace: st, category: 'CastPlaybackHandoff');
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
