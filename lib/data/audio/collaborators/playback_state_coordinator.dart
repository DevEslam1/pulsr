// lib/data/audio/collaborators/playback_state_coordinator.dart
import 'dart:async';

import 'package:rxdart/rxdart.dart';

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
    _saveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed) return;
      if (_positionDirty) {
        _positionDirty = false;
        onSavePositionRequested();
      }
    });
  }

  /// Called on player position stream tick.
  void onPositionTick(Duration pos) {
    if (_disposed) return;
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

    markPositionDirty();
  }

  /// Marks position as needing persistence on next 2s periodic timer tick.
  void markPositionDirty() {
    _positionDirty = true;
  }

  bool get isPositionDirty => _positionDirty;

  void triggerSaveIfDirty() {
    if (_positionDirty) {
      _positionDirty = false;
      onSavePositionRequested();
    }
  }

  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    _positionSubject.close();
    _highRatePositionSubject.close();
  }
}
