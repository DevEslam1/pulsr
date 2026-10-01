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
  AudioPlayer Function()? getActivePlayer;
  AudioPlayer Function()? getInactivePlayer;

  double _userVolume = 1.0;
  String _replayGainMode = 'off';
  double _preampWithRg = 0.0;
  double _preampWithoutRg = 0.0;
  bool _isDucked = false;
  double _duckFactor = 0.2;
  bool _isDopActive = false;
  bool _nativeRgActive = false;
  bool _dvcEnabled = false;
  bool _bitPerfectBypass = false;

  Timer? _transitionTimer;
  Completer<void>? _transitionCompleter;
  bool _isDisposed = false;
  bool _isTransitionActive = false;

  /// BUG-07: bumped whenever a transition starts or the controller is disposed.
  /// A timer callback from a superseded / disposed transition bails out before
  /// touching the player again.
  int _transitionGeneration = 0;

  double get userVolume => _userVolume;
  String get replayGainMode => _replayGainMode;
  double get preampWithRg => _preampWithRg;
  double get preampWithoutRg => _preampWithoutRg;
  bool get isDucked => _isDucked;
  double get duckFactor => _duckFactor;
  bool get isDopActive => _isDopActive;
  bool get nativeRgActive => _nativeRgActive;
  bool get dvcEnabled => _dvcEnabled;
  bool get bitPerfectBypass => _bitPerfectBypass;
  bool get isDisposed => _isDisposed;
  bool get hasActiveTransitionTimer =>
      _isTransitionActive && !_isDisposed;

  void setDopActive(bool active) {
    _isDopActive = active;
  }

  void setDvcEnabled(bool enabled) {
    _dvcEnabled = enabled;
  }

  void setBitPerfectBypass(bool bypass) {
    _bitPerfectBypass = bypass;
  }

  /// Mirrors [PulsrAudioHandler.isNativeRgActive]: when true the native DSP
  /// pre-gain owns ReplayGain, so this controller must not re-apply it in
  /// [calculateTargetVolume] (ducking/crossfade path) — otherwise the gain
  /// would double. DoP unity-gain still takes precedence over both.
  void setNativeRgActive(bool active) {
    _nativeRgActive = active;
  }

  void setDuckedState(bool ducked) {
    _isDucked = ducked;
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
    bool? isDucked,
    bool? nativeRgActive,
    bool? dvcEnabled,
    bool? isDopActive,
    bool? bitPerfectBypass,
  }) {
    if (userVolume != null) _userVolume = userVolume.clamp(0.0, 1.0);
    if (replayGainMode != null) _replayGainMode = replayGainMode;
    if (preampWithRg != null) _preampWithRg = preampWithRg;
    if (preampWithoutRg != null) _preampWithoutRg = preampWithoutRg;
    if (duckFactor != null) _duckFactor = duckFactor.clamp(0.05, 1.0);
    if (isDucked != null) _isDucked = isDucked;
    if (nativeRgActive != null) _nativeRgActive = nativeRgActive;
    if (dvcEnabled != null) _dvcEnabled = dvcEnabled;
    if (isDopActive != null) _isDopActive = isDopActive;
    if (bitPerfectBypass != null) _bitPerfectBypass = bitPerfectBypass;
  }

  /// Calculates target volume for [song] with current ReplayGain, ducking, and per-song offset.
  double calculateTargetVolume(
    SongsTableData? song, {
    bool albumContext = false,
    double perSongOffsetDb = 0.0,
  }) {
    // During DSD DoP transmission, volume must strictly stay at 1.0 (unity gain)
    // to avoid corrupting 0x05 / 0xFA marker bits into white noise.
    if (_isDopActive) return 1.0;

    // Strict Bit-Perfect: bypass ReplayGain completely to preserve exact PCM samples
    if (_bitPerfectBypass) return _userVolume;

    final effectiveUserVolume = _dvcEnabled ? 1.0 : _userVolume;
    final baseVolume =
        _isDucked ? (effectiveUserVolume * _duckFactor) : effectiveUserVolume;

    if (song == null) {
      return baseVolume;
    }

    // Native pre-gain owns RG: keep the mixer at user volume (+ per-song).
    // Prompt 1.2: simplified condition to `_nativeRgActive`
    final rgVolume = _nativeRgActive
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

    if (perSongOffsetDb.abs() >= 0.01) {
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
    if (_isDisposed) return;
    final clamped = targetVolume.clamp(0.0, 1.0);
    _transitionGeneration++;
    _transitionTimer?.cancel();
    _transitionTimer = null;

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
    var stepIndex = 0;

    if (_transitionCompleter != null && !_transitionCompleter!.isCompleted) {
      _transitionCompleter!.complete();
    }
    final completer = Completer<void>();
    _transitionCompleter = completer;
    final generation = _transitionGeneration;
    _isTransitionActive = true;

    unawaited(() async {
      try {
        while (stepIndex < steps) {
          await Future.delayed(stepDuration);
          if (_isDisposed || generation != _transitionGeneration) break;

          stepIndex++;
          final current =
              (startVol + diff * (stepIndex / steps)).clamp(0.0, 1.0);
          if (_isDisposed || generation != _transitionGeneration) break;

          try {
            await player.setVolume(current);
          } catch (_) {
            break;
          }
        }
      } finally {
        if (generation == _transitionGeneration) {
          _isTransitionActive = false;
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }());

    return completer.future;
  }

  /// Sets ducked state for transient notifications / speech.
  /// [perSongOffsetDb] keeps per-track volume overrides applied across the
  /// duck ramp; without it the restore target would drop the override.
  Future<void> setDucked(bool ducked, SongsTableData? currentSong,
      {double perSongOffsetDb = 0.0}) async {
    _isDucked = ducked;
    final active = getActivePlayer?.call();
    if (active != null) {
      final target =
          calculateTargetVolume(currentSong, perSongOffsetDb: perSongOffsetDb);
      await applyVolume(active, target, smoothTransition: true);
    }
  }

  /// Lifecycle teardown hook (Prompt 1.3).
  void dispose() {
    // BUG-07: mark disposed and invalidate any in-flight transition timer
    // before cancelling it, so a callback already in flight cannot setVolume.
    _isDisposed = true;
    _isTransitionActive = false;
    _transitionGeneration++;
    _transitionTimer?.cancel();
    _transitionTimer = null;
    if (_transitionCompleter != null && !_transitionCompleter!.isCompleted) {
      _transitionCompleter!.complete();
    }
    _transitionCompleter = null;
    getActivePlayer = null;
    getInactivePlayer = null;
  }
}
