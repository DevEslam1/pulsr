// lib/features/player/cubit/controllers/playback_volume_mute.dart
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../system_behavior/system_behavior_policy.dart';
import '../../../system_behavior/system_behavior_runtime.dart';
import '../../../system_behavior/system_behavior_settings.dart';
import '../player_state.dart';

import '../../../../core/errors/app_error.dart';

/// Owns output volume and the mute toggle, remembering the pre-mute volume so
/// unmuting restores it.
class PlaybackVolumeMute {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final Mutex _fifo = Mutex();

  bool _muted = false;
  double _volumeBeforeMute = 1.0;

  PlaybackVolumeMute({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit;

  bool get isMuted => _muted;

  void _remember(double v) {
    if (v > 0.001) _volumeBeforeMute = v;
  }

  Future<void> setVolume(double volume) => _fifo.protect(() async {
        final clamped = volume.clamp(0.0, 1.0);
        _remember(clamped);
        try {
          // A volume raise is an implicit unmute, including a DAC muted from
          // Settings with CS_MUTE (the app volume itself never moved).
          if (clamped > 0.001 &&
              _audioHandler.usbHardwareVolumeOwned &&
              (_muted || _audioHandler.usbHardwareMute == true)) {
            await _audioHandler.setUsbHardwareMute(false);
          }
          await _audioHandler.setVolume(clamped);
          _muted = clamped <= 0.001;
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(volume: clamped, isMuted: _muted)));
        } catch (e, st) {
          ErrorLogger.log('Set volume failed',
              error: e,
              stackTrace: st,
              category: 'PlayerPlaybackOptionsController');
          final s = _getState();
          _emit(s.copyWith(
              playback:
                  s.playback.copyWith(error: uiError('Volume change failed'))));
        }
      });

  Future<void> adjustVolume(double delta) => _fifo.protect(() async {
        try {
          final current = _audioHandler.volume;
          final settings = _resolveVolumeSettings();
          final double target;
          if (settings != null && (delta.abs() - 0.05).abs() < 1e-6) {
            target = nextVolume(
              current: current,
              direction: delta >= 0 ? 1 : -1,
              settings: settings,
            );
          } else {
            target = (current + delta).clamp(0.0, 1.0);
          }
          await _applyVolumeTarget(target);
        } catch (e, st) {
          ErrorLogger.log('Adjust volume failed',
              error: e,
              stackTrace: st,
              category: 'PlayerPlaybackOptionsController');
          final s = _getState();
          _emit(s.copyWith(
              playback:
                  s.playback.copyWith(error: uiError('Volume change failed'))));
        }
      });

  /// Step output volume according to the active [SystemBehaviorSettings] step
  /// percentage and response curve (`+1` louder, `-1` quieter).
  Future<void> stepVolume(
    int direction, {
    SystemBehaviorSettingsSnapshot? settingsOverride,
  }) =>
      _fifo.protect(() async {
        try {
          final settings = settingsOverride ??
              _resolveVolumeSettings() ??
              SystemBehaviorSettingsSnapshot.defaults;
          final target = nextVolume(
            current: _audioHandler.volume,
            direction: direction,
            settings: settings,
          );
          await _applyVolumeTarget(target);
        } catch (e, st) {
          ErrorLogger.log('Step volume failed',
              error: e,
              stackTrace: st,
              category: 'PlayerPlaybackOptionsController');
          final s = _getState();
          _emit(s.copyWith(
              playback:
                  s.playback.copyWith(error: uiError('Volume change failed'))));
        }
      });

  Future<void> _applyVolumeTarget(double target) async {
    _remember(target);
    if (target > 0.001 &&
        _audioHandler.usbHardwareVolumeOwned &&
        (_muted || _audioHandler.usbHardwareMute == true)) {
      await _audioHandler.setUsbHardwareMute(false);
    }
    await _audioHandler.setVolume(target);
    _muted = target <= 0.001;
    final s = _getState();
    _emit(s.copyWith(
        playback: s.playback.copyWith(volume: target, isMuted: _muted)));
  }

  SystemBehaviorSettingsSnapshot? _resolveVolumeSettings() {
    final active = SystemBehaviorRuntime.activeSettings;
    if (active != null) return active.snapshot;
    if (!getIt.isRegistered<SharedPreferences>()) return null;
    final prefs = getIt<SharedPreferences>();
    final hasCurve = prefs.containsKey(SystemBehaviorPrefsKeys.softwareVolumeCurve);
    final hasStep = prefs.containsKey(SystemBehaviorPrefsKeys.volumeStepPercent);
    if (!hasCurve && !hasStep) return null;
    return SystemBehaviorSettingsSnapshot.normalized(
      softwareVolumeCurve: SoftwareVolumeCurve.parse(
        prefs.getString(SystemBehaviorPrefsKeys.softwareVolumeCurve),
      ),
      volumeStepPercent: prefs.getInt(SystemBehaviorPrefsKeys.volumeStepPercent) ??
          SystemBehaviorSettingsSnapshot.defaults.volumeStepPercent,
    );
  }

  /// A-06: Toggle output mute, remembering the pre-mute volume so unmuting
  /// restores it. Exposed for the global keyboard-shortcut layer.
  Future<void> toggleMute() => _fifo.protect(() async {
        try {
          // When the DAC's Feature Unit owns the level, use its CS_MUTE
          // control instead of slamming software volume to zero. The app
          // slider keeps its value; the DAC display shows the real mute.
          if (_audioHandler.usbHardwareVolumeOwned) {
            final currentlyMuted = _audioHandler.usbHardwareMute ?? _muted;
            final target = !currentlyMuted;
            if (await _audioHandler.setUsbHardwareMute(target)) {
              _muted = target;
              final s = _getState();
              _emit(s.copyWith(
                  playback: s.playback.copyWith(isMuted: _muted)));
              return;
            }
          }
          if (_muted) {
            final targetVol = _volumeBeforeMute > 0.0 ? _volumeBeforeMute : 1.0;
            await _audioHandler.setVolume(targetVol);
            _muted = false;
            final s = _getState();
            _emit(s.copyWith(
                playback:
                    s.playback.copyWith(volume: targetVol, isMuted: false)));
          } else {
            final currentVol = _audioHandler.volume;
            _remember(currentVol);
            await _audioHandler.setVolume(0.0);
            _muted = true;
            final s = _getState();
            _emit(s.copyWith(
                playback: s.playback.copyWith(volume: 0.0, isMuted: true)));
          }
        } catch (e, st) {
          ErrorLogger.log('Toggle mute failed',
              error: e,
              stackTrace: st,
              category: 'PlayerPlaybackOptionsController');
          final s = _getState();
          _emit(s.copyWith(
              playback:
                  s.playback.copyWith(error: uiError('Toggle mute failed'))));
        }
      });
}
