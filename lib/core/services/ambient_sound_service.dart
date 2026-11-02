// lib/core/services/ambient_sound_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Relaxing ambient sound effects for Quran Mode.
enum AmbientSoundEffect {
  rain(
    label: 'Rain',
    emoji: '🌧',
    assetPath: 'assets/sounds/rain.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8a/Sound_of_rain.ogg',
  ),
  fire(
    label: 'Fire',
    emoji: '🔥',
    assetPath: 'assets/sounds/fire.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/b/b1/Campfire_sound_ambience.ogg',
  );

  const AmbientSoundEffect({
    required this.label,
    required this.emoji,
    required this.assetPath,
    required this.remoteUrl,
  });

  final String label;
  final String emoji;
  final String assetPath;
  final String remoteUrl;

  String get displayName => '$emoji $label';
}

/// Singleton manager for looping relaxing ambient sounds (Rain, Fire) in Quran Mode.
///
/// Features:
/// - Dedicated [AudioPlayer] with seamless looping.
/// - Offline-first bundled assets (`assets/sounds/`) with network fallback.
/// - Volume control slider (0.0 to 1.0).
/// - Instant switching between sound effects.
/// - On/Off toggle control.
/// - Persistence via [SharedPreferences].
class AmbientSoundService extends ChangeNotifier {
  static final AmbientSoundService _instance = AmbientSoundService._();
  factory AmbientSoundService() => _instance;
  AmbientSoundService._();

  // ─── Prefs keys ────────────────────────────────────────────────────────────
  static const _keyEnabled = 'ambient_sound_enabled';
  static const _keyEffect = 'ambient_sound_effect';
  static const _keyVolume = 'ambient_sound_volume';

  // ─── State ─────────────────────────────────────────────────────────────────
  bool _isEnabled = false;
  AmbientSoundEffect _effect = AmbientSoundEffect.rain;
  double _volume = 0.5;
  bool _isLoading = false;
  String? _errorMessage;

  bool get isEnabled => _isEnabled;
  AmbientSoundEffect get effect => _effect;
  double get volume => _volume;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // ─── Internal player ───────────────────────────────────────────────────────
  AudioPlayer? _player;
  bool _disposed = false;
  bool _initialized = false;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Restores persisted state from disk. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_keyEnabled) ?? false;
      _volume = (prefs.getDouble(_keyVolume) ?? 0.5).clamp(0.0, 1.0);
      final effectName = prefs.getString(_keyEffect);
      _effect = AmbientSoundEffect.values.firstWhere(
        (e) => e.name == effectName,
        orElse: () => AmbientSoundEffect.rain,
      );

      if (_isEnabled) {
        await _startPlayer();
      }
    } catch (_) {
      // Non-fatal: safely continue without ambient sound.
    }
    if (!_disposed) notifyListeners();
  }

  /// Toggle ambient sound on or off.
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    _errorMessage = null;
    notifyListeners();

    if (enabled) {
      await _startPlayer();
    } else {
      await _stopPlayer();
    }

    _persist();
  }

  /// Switch between ambient sound effects (Rain, Fire).
  Future<void> setEffect(AmbientSoundEffect effect) async {
    if (_effect == effect) return;
    _effect = effect;
    _errorMessage = null;
    notifyListeners();

    if (_isEnabled) {
      await _startPlayer();
    }
    _persist();
  }

  /// Adjust ambient sound volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
    notifyListeners();
    _persist();
  }

  /// Automatically called when Quran Mode is disabled.
  Future<void> onQuranModeDisabled() async {
    if (_isEnabled) {
      await setEnabled(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _player?.dispose();
    _player = null;
    super.dispose();
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _startPlayer() async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _player?.stop();
      await _player?.dispose();
      _player = null;

      final player = AudioPlayer();
      _player = player;

      await player.setVolume(_volume);
      await player.setLoopMode(LoopMode.one);

      // Attempt to load from offline bundled asset first; fallback to remote URL
      try {
        await player.setAsset(_effect.assetPath);
      } catch (_) {
        await player.setAudioSource(
          AudioSource.uri(Uri.parse(_effect.remoteUrl)),
        );
      }

      await player.play();

      if (_disposed) {
        await player.dispose();
        return;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (!_disposed) {
        _isLoading = false;
        _isEnabled = false;
        _errorMessage = 'Could not load ambient sound.';
        notifyListeners();
      }
    }
  }

  Future<void> _stopPlayer() async {
    await _player?.stop();
    await _player?.dispose();
    _player = null;
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_keyEnabled, _isEnabled);
      prefs.setDouble(_keyVolume, _volume);
      prefs.setString(_keyEffect, _effect.name);
    }).catchError((_) {});
  }
}
