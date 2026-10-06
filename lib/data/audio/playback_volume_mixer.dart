// lib/data/audio/playback_volume_mixer.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/error_logger.dart';

/// Single authority for all volume applications to [AudioPlayer] instances.
/// Composes base user volume, ReplayGain/per-song target, duck factor,
/// sleep fade factor, and crossfade gains into cohesive final gains for
/// the active and inactive audio players.
class PlaybackVolumeMixer {
  final AudioPlayer Function()? _getActivePlayer;
  final AudioPlayer Function()? _getInactivePlayer;

  double _userVolume = 1.0;
  double _targetActiveFactor = 1.0;
  double _targetInactiveFactor = 1.0;
  double _duckFactor = 1.0;
  double _sleepFadeFactor = 1.0;
  double _crossfadeOutgoingGain = 1.0;
  double _crossfadeIncomingGain = 0.0;
  bool _isCrossfading = false;
  bool _dvcEnabled = false;

  Completer<void>? _inFlightApply;
  bool _pendingApply = false;

  double _lastAppliedActive = 1.0;
  double _lastAppliedInactive = 0.0;

  PlaybackVolumeMixer({
    required AudioPlayer Function()? getActivePlayer,
    required AudioPlayer Function()? getInactivePlayer,
  })  : _getActivePlayer = getActivePlayer,
        _getInactivePlayer = getInactivePlayer;

  @visibleForTesting
  double get lastAppliedActiveVolume => _lastAppliedActive;

  @visibleForTesting
  double get lastAppliedInactiveVolume => _lastAppliedInactive;

  double get userVolume => _userVolume;
  double get duckFactor => _duckFactor;
  double get sleepFadeFactor => _sleepFadeFactor;
  bool get isCrossfading => _isCrossfading;

  void setUserVolume(double volume) {
    _userVolume = volume.clamp(0.0, 1.0);
  }

  void setDvcEnabled(bool enabled) {
    _dvcEnabled = enabled;
  }

  void setActiveTargetFactor(double factor) {
    _targetActiveFactor = factor.clamp(0.0, 2.0);
  }

  void setInactiveTargetFactor(double factor) {
    _targetInactiveFactor = factor.clamp(0.0, 2.0);
  }

  void setDuckFactor(double factor) {
    _duckFactor = factor.clamp(0.0, 1.0);
  }

  void clearDuck() {
    _duckFactor = 1.0;
  }

  void setSleepFadeFactor(double factor) {
    _sleepFadeFactor = factor.clamp(0.0, 1.0);
  }

  void clearSleepFade() {
    _sleepFadeFactor = 1.0;
  }

  void setCrossfadeGains({
    required double outgoingGain,
    required double incomingGain,
    required bool isCrossfading,
  }) {
    _crossfadeOutgoingGain = outgoingGain.clamp(0.0, 1.0);
    _crossfadeIncomingGain = incomingGain.clamp(0.0, 1.0);
    _isCrossfading = isCrossfading;
  }

  void clearCrossfade() {
    _crossfadeOutgoingGain = 1.0;
    _crossfadeIncomingGain = 0.0;
    _isCrossfading = false;
  }

  /// Calculates the final volume to set on the active player.
  double get calculatedActiveVolume {
    final effectiveUser = _dvcEnabled ? 1.0 : _userVolume;
    final base = (effectiveUser * _targetActiveFactor * _duckFactor * _sleepFadeFactor);
    if (_isCrossfading) {
      return (base * _crossfadeOutgoingGain).clamp(0.0, 1.0);
    }
    return base.clamp(0.0, 1.0);
  }

  /// Calculates the final volume to set on the inactive player.
  double get calculatedInactiveVolume {
    if (!_isCrossfading) return 0.0;
    final effectiveUser = _dvcEnabled ? 1.0 : _userVolume;
    final base = (effectiveUser * _targetInactiveFactor * _duckFactor * _sleepFadeFactor);
    return (base * _crossfadeIncomingGain).clamp(0.0, 1.0);
  }

  /// Coalesced, serialized volume application to both players.
  Future<void> apply() async {
    if (_inFlightApply != null) {
      _pendingApply = true;
      return _inFlightApply!.future;
    }

    final completer = Completer<void>();
    _inFlightApply = completer;

    try {
      do {
        _pendingApply = false;
        final targetActive = calculatedActiveVolume;
        final targetInactive = calculatedInactiveVolume;

        final activePlayer = _getActivePlayer?.call();
        final inactivePlayer = _getInactivePlayer?.call();

        if (activePlayer != null) {
          try {
            await activePlayer.setVolume(targetActive);
            _lastAppliedActive = targetActive;
          } catch (e, st) {
            ErrorLogger.log(
              'Mixer failed to set active volume',
              error: e,
              stackTrace: st,
              category: 'PlaybackVolumeMixer',
            );
          }
        }

        if (inactivePlayer != null && (_isCrossfading || _lastAppliedInactive > 0.0)) {
          try {
            await inactivePlayer.setVolume(targetInactive);
            _lastAppliedInactive = targetInactive;
          } catch (e, st) {
            ErrorLogger.log(
              'Mixer failed to set inactive volume',
              error: e,
              stackTrace: st,
              category: 'PlaybackVolumeMixer',
            );
          }
        }
      } while (_pendingApply);
    } finally {
      _inFlightApply = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Direct volume update for a specific player (used during standalone transitions).
  Future<void> applyDirectToPlayer(AudioPlayer player, double volume) async {
    try {
      await player.setVolume(volume.clamp(0.0, 1.0));
    } catch (e, st) {
      ErrorLogger.log(
        'Mixer failed in applyDirectToPlayer',
        error: e,
        stackTrace: st,
        category: 'PlaybackVolumeMixer',
      );
    }
  }
}
