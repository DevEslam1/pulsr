// lib/features/player/cubit/controllers/player_playback_options_volume.dart
part of 'player_playback_options_controller.dart';

/// Output volume / mute surface for [PlayerPlaybackOptionsController]. Kept in a
/// part so the main controller stays under the 400-line hygiene cap.
extension PlayerPlaybackOptionsVolumeExtension
    on PlayerPlaybackOptionsController {
  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
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

  bool get isMuted => _muted;
}
