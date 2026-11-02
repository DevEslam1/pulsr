// lib/core/services/ambient_sound_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All available ambient sound effects.
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
  ),
  forest(
    label: 'Forest',
    emoji: '🌲',
    assetPath: 'assets/sounds/forest.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/5/56/Forest_Birds_Ambient_Sound.ogg',
  ),
  ocean(
    label: 'Ocean',
    emoji: '🌊',
    assetPath: 'assets/sounds/ocean.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/60/Ocean_waves_-_Lihou.ogg',
  ),
  wind(
    label: 'Wind',
    emoji: '💨',
    assetPath: 'assets/sounds/wind.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/a/a4/Howling_wind.ogg',
  ),
  thunder(
    label: 'Thunder',
    emoji: '⛈',
    assetPath: 'assets/sounds/thunder.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e9/Thunder_close_call.ogg',
  ),
  birds(
    label: 'Birds',
    emoji: '🐦',
    assetPath: 'assets/sounds/birds.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/b/b4/Songbird_at_Prospect_Hill.ogg',
  ),
  cafe(
    label: 'Café',
    emoji: '☕',
    assetPath: 'assets/sounds/cafe.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/27/Cafe_sounds.ogg',
  ),
  whiteNoise(
    label: 'White Noise',
    emoji: '〰',
    assetPath: 'assets/sounds/white_noise.ogg',
    remoteUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/21/White-noise-sound-20sec-mono-44100Hz.ogg',
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

/// Singleton manager for looping ambient background sounds.
///
/// Supports **multiple simultaneous effects** (e.g. Rain + Fire together),
/// each with individual volume control. Synchronised with the main player:
/// pauses all active sounds when the player pauses, resumes them when
/// the player plays again.
///
/// Persistence via [SharedPreferences] stores which effects are active and
/// each effect's volume.
class AmbientSoundService extends ChangeNotifier {
  static final AmbientSoundService _instance = AmbientSoundService._();
  factory AmbientSoundService() => _instance;
  AmbientSoundService._();

  // ─── Prefs keys ────────────────────────────────────────────────────────────
  static const _keyActiveEffects = 'ambient_active_effects';
  static const _keyVolumePrefix = 'ambient_volume_';

  // ─── State ─────────────────────────────────────────────────────────────────
  final Set<AmbientSoundEffect> _activeEffects = {};
  final Map<AmbientSoundEffect, double> _volumes = {
    for (final e in AmbientSoundEffect.values) e: 0.5,
  };
  final Map<AmbientSoundEffect, bool> _loadingEffects = {};
  String? _errorMessage;
  bool _isPlayerPlaying = false;

  // ─── Public read-only access ───────────────────────────────────────────────

  /// The set of currently active (toggled-on) ambient effects.
  Set<AmbientSoundEffect> get activeEffects =>
      Set.unmodifiable(_activeEffects);

  /// Returns true if at least one effect is active.
  bool get isEnabled => _activeEffects.isNotEmpty;

  /// Returns true if [effect] is currently toggled on.
  bool isEffectActive(AmbientSoundEffect effect) =>
      _activeEffects.contains(effect);

  /// Volume (0.0–1.0) for the given [effect].
  double volumeFor(AmbientSoundEffect effect) =>
      _volumes[effect] ?? 0.5;

  /// True if any ambient audio is loading.
  bool get isLoading => _loadingEffects.values.any((v) => v);

  /// True if a specific effect is currently loading.
  bool isEffectLoading(AmbientSoundEffect effect) =>
      _loadingEffects[effect] ?? false;

  String? get errorMessage => _errorMessage;
  bool get isPlayerPlaying => _isPlayerPlaying;

  /// True when ambient audio is actively emitting (at least one player running).
  bool get isAudioPlaying =>
      isEnabled && _isPlayerPlaying && _players.values.any((p) => p.playing);

  // ─── Legacy single-effect API (deprecated, kept for smooth migration) ──────

  /// The most recently added active effect, or [AmbientSoundEffect.rain] as default.
  @Deprecated('Use activeEffects and toggleEffect() instead')
  AmbientSoundEffect get effect =>
      _activeEffects.isEmpty ? AmbientSoundEffect.rain : _activeEffects.last;

  /// Master volume – getter reads from the last active effect for backward compat.
  @Deprecated('Use volumeFor(effect) and setEffectVolume() instead')
  double get volume => volumeFor(
      _activeEffects.isEmpty ? AmbientSoundEffect.rain : _activeEffects.last);

  // ─── Internal players ──────────────────────────────────────────────────────
  @visibleForTesting
  static AudioPlayer Function() playerFactory = () => AudioPlayer();

  final Map<AmbientSoundEffect, AudioPlayer> _players = {};
  bool _disposed = false;
  bool _initialized = false;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Toggle an effect on or off. When turning on, starts the player.
  /// When turning off, stops and disposes the player.
  Future<void> toggleEffect(AmbientSoundEffect effect) async {
    if (_activeEffects.contains(effect)) {
      _activeEffects.remove(effect);
      notifyListeners();
      await _stopEffectPlayer(effect);
    } else {
      _activeEffects.add(effect);
      notifyListeners();
      await _startEffectPlayer(effect);
    }
    _persist();
  }

  /// Set the volume for a specific effect (0.0–1.0).
  Future<void> setEffectVolume(AmbientSoundEffect effect, double volume) async {
    _volumes[effect] = volume.clamp(0.0, 1.0);
    await _players[effect]?.setVolume(_volumes[effect]!);
    notifyListeners();
    _persist();
  }

  /// Legacy: set volume on the current active effect.
  @Deprecated('Use setEffectVolume() instead')
  Future<void> setVolume(double volume) async {
    if (_activeEffects.isEmpty) {
      // Just set all volumes
      for (final e in AmbientSoundEffect.values) {
        _volumes[e] = volume.clamp(0.0, 1.0);
      }
      notifyListeners();
      return;
    }
    await setEffectVolume(_activeEffects.last, volume);
  }

  /// Legacy: enable/disable ambient sounds (uses rain as the default effect).
  @Deprecated('Use toggleEffect() instead')
  Future<void> setEnabled(bool enabled) async {
    if (enabled && _activeEffects.isEmpty) {
      await toggleEffect(AmbientSoundEffect.rain);
    } else if (!enabled && _activeEffects.isNotEmpty) {
      final toStop = Set<AmbientSoundEffect>.from(_activeEffects);
      for (final e in toStop) {
        await toggleEffect(e);
      }
    }
  }

  /// Legacy: switch active effect (stops old one, starts new one).
  @Deprecated('Use toggleEffect() instead')
  Future<void> setEffect(AmbientSoundEffect effect) async {
    // Stop all currently active
    final toStop = Set<AmbientSoundEffect>.from(_activeEffects);
    for (final e in toStop) {
      _activeEffects.remove(e);
      await _stopEffectPlayer(e);
    }
    // Start the new one
    await toggleEffect(effect);
  }

  /// Notifies the ambient sound service of the main player's playback state.
  /// When the player pauses, all active ambient sounds pause.
  /// When the player resumes, ambient sounds resume (if active).
  void onPlayerPlaybackStateChanged(bool isPlaying) {
    if (_isPlayerPlaying == isPlaying) return;
    _isPlayerPlaying = isPlaying;
    notifyListeners();

    for (final entry in _players.entries) {
      try {
        if (_isPlayerPlaying) {
          if (!(entry.value.playing)) {
            unawaited(entry.value.play().catchError((Object _) {}));
          }
        } else {
          if (entry.value.playing) {
            unawaited(entry.value.pause().catchError((Object _) {}));
          }
        }
      } catch (_) {}
    }
  }

  /// Restores persisted state from disk. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load volumes
      for (final effect in AmbientSoundEffect.values) {
        final v = prefs.getDouble('$_keyVolumePrefix${effect.name}');
        if (v != null) _volumes[effect] = v.clamp(0.0, 1.0);
      }

      // Load active effects
      final activeNames = prefs.getStringList(_keyActiveEffects) ?? [];
      for (final name in activeNames) {
        final effect = AmbientSoundEffect.values.firstWhere(
          (e) => e.name == name,
          orElse: () => AmbientSoundEffect.rain,
        );
        _activeEffects.add(effect);
      }

      // Start players for all persisted active effects
      for (final effect in List.of(_activeEffects)) {
        unawaited(_startEffectPlayer(effect));
      }
    } catch (_) {
      // Non-fatal: safely continue without ambient sound.
    }
    if (!_disposed) notifyListeners();
  }

  /// No-op: ambient sounds are decoupled from Quran Mode.
  Future<void> onQuranModeDisabled() async {}

  @override
  void dispose() {
    _disposed = true;
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    super.dispose();
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _startEffectPlayer(AmbientSoundEffect effect) async {
    if (_disposed) return;
    _loadingEffects[effect] = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Dispose any existing player for this effect
      final existing = _players.remove(effect);
      await existing?.stop();
      await existing?.dispose();

      final player = playerFactory();
      _players[effect] = player;

      await player.setVolume(_volumes[effect]!);
      await player.setLoopMode(LoopMode.all);

      // Attempt to load from offline bundled asset first; fallback to remote URL.
      // Uses duplicated sources with LoopMode.all so ExoPlayer pre-buffers
      // the next repetition in advance, eliminating seek lag and gaps at loop points.
      try {
        await player.setAudioSources([
          AudioSource.asset(effect.assetPath),
          AudioSource.asset(effect.assetPath),
        ]);
      } catch (_) {
        if (effect.remoteUrl.isNotEmpty) {
          await player.setAudioSources([
            AudioSource.uri(Uri.parse(effect.remoteUrl)),
            AudioSource.uri(Uri.parse(effect.remoteUrl)),
          ]);
        }
      }

      if (_disposed || !_activeEffects.contains(effect)) {
        await player.dispose();
        _players.remove(effect);
        return;
      }

      // Respect the main player's playback state
      if (_isPlayerPlaying) {
        await player.play();
      } else {
        await player.pause();
      }

      if (_disposed || !_activeEffects.contains(effect)) {
        await player.dispose();
        _players.remove(effect);
        return;
      }

      _loadingEffects[effect] = false;
      notifyListeners();
    } catch (e) {
      if (!_disposed) {
        _loadingEffects[effect] = false;
        _activeEffects.remove(effect);
        _errorMessage = 'Could not load ${effect.label} sound.';
        notifyListeners();
      }
    }
  }

  Future<void> _stopEffectPlayer(AmbientSoundEffect effect) async {
    final player = _players.remove(effect);
    await player?.stop();
    await player?.dispose();
    _loadingEffects.remove(effect);
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(
        _keyActiveEffects,
        _activeEffects.map((e) => e.name).toList(),
      );
      for (final effect in AmbientSoundEffect.values) {
        prefs.setDouble(
          '$_keyVolumePrefix${effect.name}',
          _volumes[effect] ?? 0.5,
        );
      }
    }).catchError((_) {});
  }
}
