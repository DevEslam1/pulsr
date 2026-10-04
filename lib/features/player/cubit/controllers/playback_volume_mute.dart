// lib/features/player/cubit/controllers/playback_volume_mute.dart
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../player_state.dart';

/// Owns output volume and the mute toggle, remembering the pre-mute volume so
/// unmuting restores it.
class PlaybackVolumeMute {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;

  bool _muted = false;
  double _volumeBeforeMute = 1.0;
  bool _isMuting = false;

  PlaybackVolumeMute({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit;

  bool get isMuted => _muted;

  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
      if (volume > 0.0) _muted = false;
    } catch (e, st) {
      ErrorLogger.log('Set volume failed',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Volume change failed')));
    }
  }

  Future<void> adjustVolume(double delta) async {
    try {
      final current = _audioHandler.volume;
      final target = (current + delta).clamp(0.0, 1.0);
      await _audioHandler.setVolume(target);
      if (target > 0.0) _muted = false;
    } catch (e, st) {
      ErrorLogger.log('Adjust volume failed',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Volume change failed')));
    }
  }

  /// A-06: Toggle output mute, remembering the pre-mute volume so unmuting
  /// restores it. Exposed for the global keyboard-shortcut layer.
  Future<void> toggleMute() async {
    if (_isMuting) return;
    _isMuting = true;
    try {
      if (_muted) {
        final targetVol = _volumeBeforeMute > 0.0 ? _volumeBeforeMute : 1.0;
        await _audioHandler.setVolume(targetVol);
        _muted = false;
      } else {
        final currentVol = _audioHandler.volume;
        if (currentVol > 0.0) {
          _volumeBeforeMute = currentVol;
        }
        await _audioHandler.setVolume(0.0);
        _muted = true;
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle mute failed',
          error: e,
          stackTrace: st,
          category: 'PlayerPlaybackOptionsController');
    } finally {
      _isMuting = false;
    }
  }
}
