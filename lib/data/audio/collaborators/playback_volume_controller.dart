// lib/data/audio/collaborators/playback_volume_controller.dart
import 'dart:async';
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
  bool _isDopActive = false;

  double get userVolume => _userVolume;
  String get replayGainMode => _replayGainMode;
  bool get isDucked => _isDucked;
  bool get isDopActive => _isDopActive;

  void setDopActive(bool active) {
    _isDopActive = active;
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
  }) {
    if (userVolume != null) _userVolume = userVolume.clamp(0.0, 1.0);
    if (replayGainMode != null) _replayGainMode = replayGainMode;
    if (preampWithRg != null) _preampWithRg = preampWithRg;
    if (preampWithoutRg != null) _preampWithoutRg = preampWithoutRg;
  }

  /// Calculates target volume for [song] with current ReplayGain and ducking state.
  double calculateTargetVolume(SongsTableData? song, {bool albumContext = false}) {
    // During DSD DoP transmission, volume must strictly stay at 1.0 (unity gain)
    // to avoid corrupting 0x05 / 0xFA marker bits into white noise.
    if (_isDopActive) return 1.0;

    if (song == null) return _isDucked ? (_userVolume * 0.2) : _userVolume;

    final baseVolume = _isDucked ? (_userVolume * 0.2) : _userVolume;
    return ReplayGainMath.apply(
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
  Future<void> setDucked(bool ducked, SongsTableData? currentSong) async {
    _isDucked = ducked;
    final active = getActivePlayer();
    final target = calculateTargetVolume(currentSong);
    await applyVolume(active, target, smoothTransition: true);
  }
}
