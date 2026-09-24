// lib/data/audio/collaborators/playback_volume_controller.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/core/utils/error_logger.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/audio/replay_gain_math.dart';

/// Manages player volume staging, ReplayGain application with smooth transitions,
/// volume ducking, and crossfade volume math.
class PlaybackVolumeController {
  final AudioPlayer Function() getActivePlayer;
  final AudioPlayer Function() getInactivePlayer;

  double _userVolume = 1.0;
  String _replayGainMode = 'off';
  double _preampWithRg = 0.0;
  double _preampWithoutRg = -3.0;
  bool _isDucked = false;
  double _duckFactor = 0.2;
  bool _isDopActive = false;
  bool _nativeRgActive = false;
  bool _dvcEnabled = false;

  double get userVolume => _userVolume;
  String get replayGainMode => _replayGainMode;
  bool get isDucked => _isDucked;
  bool get isDopActive => _isDopActive;
  bool get nativeRgActive => _nativeRgActive;
  bool get dvcEnabled => _dvcEnabled;

  void setDopActive(bool active) {
    _isDopActive = active;
  }

  void setDvcEnabled(bool enabled) {
    _dvcEnabled = enabled;
  }

  /// Mirrors [PulsrAudioHandler.isNativeRgActive]: when true the native DSP
  /// pre-gain owns ReplayGain, so this controller must not re-apply it in
  /// [calculateTargetVolume] (ducking/crossfade path) — otherwise the gain
  /// would double. DoP unity-gain still takes precedence over both.
  void setNativeRgActive(bool active) {
    _nativeRgActive = active;
  }

  PlaybackVolumeController({
    required this.getActivePlayer,
    required this.getInactivePlayer,
  });

  void updateSettings({
    double? userVolume,
    String? replayGainMode,
    double? preampWithRg,
    double? preampWithoutRg,
    double? duckFactor,
  }) {
    if (userVolume != null) _userVolume = userVolume.clamp(0.0, 1.0);
    if (replayGainMode != null) _replayGainMode = replayGainMode;
    if (preampWithRg != null) _preampWithRg = preampWithRg;
    if (preampWithoutRg != null) _preampWithoutRg = preampWithoutRg;
    if (duckFactor != null) _duckFactor = duckFactor.clamp(0.05, 1.0);
  }

  /// Calculates target volume for [song] with current ReplayGain, ducking, and per-song offset.
  double calculateTargetVolume(SongsTableData? song,
      {bool albumContext = false, double perSongOffsetDb = 0.0}) {
    // During DSD DoP transmission, volume must strictly stay at 1.0 (unity gain)
    // to avoid corrupting 0x05 / 0xFA marker bits into white noise.
    if (_isDopActive) return 1.0;

    final effectiveUserVolume = _dvcEnabled ? 1.0 : _userVolume;
    if (song == null) {
      return _isDucked ? (effectiveUserVolume * _duckFactor) : effectiveUserVolume;
    }

    final baseVolume =
        _isDucked ? (effectiveUserVolume * _duckFactor) : effectiveUserVolume;
    // Native pre-gain owns RG: keep the mixer at user volume (+ per-song).
    final rgVolume = (_nativeRgActive || (_dvcEnabled && _nativeRgActive))
        ? baseVolume
        : ReplayGainMath.apply(
            mode: _replayGainMode,
            volume: baseVolume,
            trackGainDb: song.replayGainTrack,
            trackPeak: song.replayGainTrackPeak,
            albumGainDb: song.replayGainAlbum,
            albumPeak: song.replayGainAlbumPeak,
            albumContext: albumContext,
            preampWithRg: _preampWithRg,
            preampWithoutRg: _preampWithoutRg,
          );

    if (perSongOffsetDb.abs() >= 0.1) {
      final multiplier = math.pow(10, perSongOffsetDb / 20.0).toDouble();
      return (rgVolume * multiplier).clamp(0.0, 1.0);
    }
    return rgVolume;
  }

  /// Applies calculated volume to [player] with an optional 500ms smooth ramp (P2-1).
  Future<void> applyVolume(
    AudioPlayer player,
    double targetVolume, {
    bool smoothTransition = false,
  }) async {
    final clamped = targetVolume.clamp(0.0, 1.0);
    if (!smoothTransition) {
      try {
        await player.setVolume(clamped);
      } catch (e, st) {
        ErrorLogger.log('Failed to set player volume',
            error: e, stackTrace: st, category: 'VolumeController');
      }
      return;
    }

    final startVol = player.volume;
    if ((startVol - clamped).abs() < 0.01) {
      try {
        await player.setVolume(clamped);
      } catch (_) {}
      return;
    }

    // P2-1: 500ms smooth crossfade between gain values
    const steps = 10;
    const stepDuration = Duration(milliseconds: 50);
    final diff = clamped - startVol;

    for (var i = 1; i <= steps; i++) {
      await Future.delayed(stepDuration);
      final current = (startVol + diff * (i / steps)).clamp(0.0, 1.0);
      try {
        await player.setVolume(current);
      } catch (_) {
        break;
      }
    }
  }

  /// Sets ducked state for transient notifications / speech.
  /// [perSongOffsetDb] keeps per-track volume overrides applied across the
  /// duck ramp; without it the restore target would drop the override.
  Future<void> setDucked(bool ducked, SongsTableData? currentSong,
      {double perSongOffsetDb = 0.0}) async {
    _isDucked = ducked;
    final active = getActivePlayer();
    final target = calculateTargetVolume(currentSong,
        perSongOffsetDb: perSongOffsetDb);
    await applyVolume(active, target, smoothTransition: true);
  }

  /// Lifecycle teardown hook (Issue 20).
  void dispose() {
    // Teardown hook for future streams / timers
  }
}
