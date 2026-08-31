// lib/data/audio/audio_session_id_router.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/utils/error_logger.dart';

/// Single source of truth for routing Android audio session ids from the
/// active just_audio player into the DSP/equalizer stack.
///
/// Contract:
///  * Validates ids — null/0/negative mean "no session yet" and are ignored
///    (attaching effects to session 0 would bind them to the global output
///    mix instead of the player's stream).
///  * Suppresses duplicate same-id re-emissions (e.g. BehaviorSubject replay
///    after re-subscribe) so a repeated event never triggers a native
///    release/recreate cycle.
///  * Serializes out-of-order updates: if several ids arrive while a
///    re-attach is still in flight, only the most recently requested id is
///    applied once the in-flight operation completes; intermediate ids are
///    collapsed.
class AudioSessionIdRouter {
  /// Invoked at most once per distinct session id, in application order.
  final void Function(int sessionId) onSessionChanged;

  /// Invoked when the audio route changed (e.g. Bluetooth <-> speaker).
  /// The Android session id usually stays the same across route switches,
  /// but the HAL effect chain is re-initialized by the platform, so consumers
  /// re-push their full effect state through this callback.
  final void Function()? onRouteChanged;

  int? _currentSessionId;
  Future<void> _chain = Future<void>.value();
  int? _pendingSessionId;
  bool _routeResyncPending = false;

  AudioSessionIdRouter({required this.onSessionChanged, this.onRouteChanged});

  /// The last session id accepted by this router (never 0).
  int? get currentSessionId => _currentSessionId;

  /// Feed every emission of the player's `androidAudioSessionIdStream` here,
  /// including the first non-zero id emitted right after player init.
  void handleSessionId(int? sessionId) {
    if (sessionId == null || sessionId <= 0) return;
    if (sessionId == _currentSessionId && _pendingSessionId == null) {
      // Duplicate same-id re-emit: no re-attach needed.
      return;
    }
    _pendingSessionId = sessionId;
    _chain = _chain.then((_) => _drain()).catchError((Object e, StackTrace st) {
      ErrorLogger.log('AudioSessionIdRouter chain error',
          error: e, stackTrace: st, category: 'AudioSessionIdRouter');
    });
  }

  void handleRouteChanged() {
    if (_routeResyncPending) return;
    _routeResyncPending = true;
    _chain = _chain.then((_) {
      _routeResyncPending = false;
      final callback = onRouteChanged;
      if (callback != null) callback();
    }).catchError((Object e, StackTrace st) {
      _routeResyncPending = false;
      ErrorLogger.log('AudioSessionIdRouter route resync error',
          error: e, stackTrace: st, category: 'AudioSessionIdRouter');
    });
  }

  Future<void> _drain() async {
    final next = _pendingSessionId;
    _pendingSessionId = null;
    if (next == null || next <= 0) return;
    if (next == _currentSessionId) return;
    _currentSessionId = next;
    onSessionChanged(next);
  }

  /// Test-only: completes when every queued operation has been applied.
  @visibleForTesting
  Future<void> get idleForTest => _chain;

  /// Test-only: resets dedupe state (hot restart / test teardown).
  @visibleForTesting
  void resetForTest() {
    _currentSessionId = null;
    _pendingSessionId = null;
  }
}
