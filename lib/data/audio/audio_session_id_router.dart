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
///  * Serializes out-of-order updates: if several ids arrive before the
///    drain runs, only the most recently requested id is applied;
///    intermediate ids are collapsed (latest wins).
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
  final List<int> _pendingSessionIds = <int>[];
  bool _routeResyncPending = false;
  bool _isDraining = false;
  bool _drainQueued = false;

  AudioSessionIdRouter({required this.onSessionChanged, this.onRouteChanged});

  /// The last session id accepted by this router (never 0).
  int? get currentSessionId => _currentSessionId;

  /// Feed every emission of the player's `androidAudioSessionIdStream` here,
  /// including the first non-zero id emitted right after player init.
  void handleSessionId(int? sessionId) {
    if (sessionId == null || sessionId <= 0) {
      ErrorLogger.log(
        'Ignoring invalid audio session ID: $sessionId (null or <= 0)',
        category: 'AudioSessionIdRouter',
      );
      return;
    }

    // Duplicate of whatever will be the effective id once the queue drains.
    final effective = _pendingSessionIds.isEmpty
        ? _currentSessionId
        : _pendingSessionIds.last;
    if (sessionId == effective) return;

    ErrorLogger.log(
      'AudioSessionIdRouter received sessionId: $sessionId (current: $_currentSessionId)',
      category: 'AudioSessionIdRouter',
    );

    // Latest wins: a newer id supersedes any not-yet-applied one. (Previously
    // the oldest pending id was kept as well, so an "intermediate" id was
    // still applied, contradicting the documented contract.)
    _pendingSessionIds
      ..clear()
      ..add(sessionId);

    if (!_drainQueued) {
      _drainQueued = true;
      _chain = _chain.then((_) => _drainQueue()).catchError((
        Object e,
        StackTrace st,
      ) {
        _drainQueued = false;
        ErrorLogger.log(
          'AudioSessionIdRouter chain error',
          error: e,
          stackTrace: st,
          category: 'AudioSessionIdRouter',
        );
      });
    }
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
      ErrorLogger.log(
        'AudioSessionIdRouter route resync error',
        error: e,
        stackTrace: st,
        category: 'AudioSessionIdRouter',
      );
    });
  }

  Future<void> _drainQueue() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_pendingSessionIds.isNotEmpty) {
        final next = _pendingSessionIds.removeAt(0);
        if (next == _currentSessionId) continue;
        _currentSessionId = next;
        try {
          onSessionChanged(next);
        } catch (e, st) {
          ErrorLogger.log(
            'AudioSessionIdRouter callback error',
            error: e,
            stackTrace: st,
            category: 'AudioSessionIdRouter',
          );
        }
      }
    } finally {
      _isDraining = false;
      _drainQueued = false;
    }
  }

  /// Test-only: completes when every queued operation has been applied.
  @visibleForTesting
  Future<void> get idleForTest => _chain;

  /// Test-only: resets dedupe state (hot restart / test teardown).
  @visibleForTesting
  void resetForTest() {
    _currentSessionId = null;
    _pendingSessionIds.clear();
    _routeResyncPending = false;
    _isDraining = false;
    _drainQueued = false;
  }
}
