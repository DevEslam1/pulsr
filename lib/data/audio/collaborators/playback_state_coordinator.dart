// lib/data/audio/collaborators/playback_state_coordinator.dart
import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../../../core/utils/error_logger.dart';

/// Coordinates position stream broadcasting (dual-rate), debounced state persistence,
/// and AudioService PlaybackState updates.
class PlaybackStateCoordinator {
  final Future<void> Function() onSavePositionRequested;

  final BehaviorSubject<Duration> _positionSubject =
      BehaviorSubject.seeded(Duration.zero);
  final PublishSubject<Duration> _highRatePositionSubject =
      PublishSubject<Duration>();

  int _lastStandardPositionEmitMs = 0;
  int _lastHighRatePositionEmitMs = 0;

  bool _positionDirty = false;
  Timer? _saveTimer;
  bool _disposed = false;

  /// BUG-02/21: last position actually persisted, so a paused/unchanged
  /// position does not keep dirtying the coordinator every tick.
  Duration _lastSavedPosition = Duration.zero;

  /// BUG-02: most recent position observed, used as the value written when a
  /// save completes.
  Duration _lastEmittedPosition = Duration.zero;

  /// Standard throttled stream (~250ms) for UI progress bars, scrobbling, and telemetry.
  Stream<Duration> get positionStream => _positionSubject.stream;

  /// High-rate stream (~16ms, 60fps) for fluid waveform seeks.
  Stream<Duration> get highRatePositionStream => _highRatePositionSubject.stream;

  PlaybackStateCoordinator({
    required this.onSavePositionRequested,
  }) {
    _initSaveTimer();
  }

  void _initSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed) return;
      _executeSave();
    });
  }

  /// Runs a pending position save. Kept synchronous at the call site: the dirty
  /// flag is cleared before invoking the callback (so callers observing state
  /// immediately see it clean) and restored if the callback fails, so a failed
  /// write is retried on the next tick (BUG-10).
  void _executeSave() {
    if (_disposed || !_positionDirty) return;
    _positionDirty = false;
    final positionAtSave = _lastEmittedPosition;
    try {
      onSavePositionRequested().then((_) {
        if (_lastEmittedPosition == positionAtSave) {
          _lastSavedPosition = positionAtSave;
        }
      }).catchError((Object e, StackTrace st) {
        _positionDirty = true;
        if (!_disposed) {
          ErrorLogger.log(
            'Failed to persist playback position',
            error: e,
            stackTrace: st,
            category: 'PlaybackStateCoordinator',
          );
        }
      });
    } catch (e, st) {
      _positionDirty = true;
      if (!_disposed) {
        ErrorLogger.log(
          'Failed to persist playback position',
          error: e,
          stackTrace: st,
          category: 'PlaybackStateCoordinator',
        );
      }
    }
  }

  /// Called on player position stream tick.
  void onPositionTick(Duration pos) {
    if (_disposed) return;
    _lastEmittedPosition = pos;
    final now = DateTime.now().millisecondsSinceEpoch;

    // High-rate emission (~16ms granularity for 60 FPS waveform tracking)
    if (now - _lastHighRatePositionEmitMs >= 16 || pos == Duration.zero) {
      _lastHighRatePositionEmitMs = now;
      if (!_highRatePositionSubject.isClosed) {
        _highRatePositionSubject.add(pos);
      }
    }

    // Standard emission (~250ms granularity)
    if (now - _lastStandardPositionEmitMs >= 250 || pos == Duration.zero) {
      _lastStandardPositionEmitMs = now;
      if (!_positionSubject.isClosed) {
        _positionSubject.add(pos);
      }
    }

    // BUG-02/21: only dirty when the position actually differs from the last
    // value written, so pausing (or an unchanged tick) stops the 2s disk write.
    if (pos != _lastSavedPosition) {
      markPositionDirty();
    }
  }

  /// Marks position as needing persistence on next 2s periodic timer tick.
  void markPositionDirty() {
    if (_disposed) return;
    _positionDirty = true;
  }

  bool get isPositionDirty => _positionDirty;

  void triggerSaveIfDirty() {
    if (_disposed) return;
    _executeSave();
  }

  void dispose() {
    // BUG-30: mark disposed before cancelling so an in-flight timer callback
    // bails out immediately.
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    _positionDirty = false;
    _lastSavedPosition = Duration.zero;
    _lastEmittedPosition = Duration.zero;
    if (!_positionSubject.isClosed) {
      _positionSubject.close();
    }
    if (!_highRatePositionSubject.isClosed) {
      _highRatePositionSubject.close();
    }
  }
}
