// lib/core/services/ambient_sound_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/generated/app_localizations.dart';

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

  /// Station-independent UI name. The const [label] stays English because the
  /// enum is built before any locale exists; widgets resolve it here instead.
  String localizedLabel(AppLocalizations l) {
    switch (this) {
      case AmbientSoundEffect.rain:
        return l.ambientEffectRain;
      case AmbientSoundEffect.fire:
        return l.ambientEffectFire;
      case AmbientSoundEffect.forest:
        return l.ambientEffectForest;
      case AmbientSoundEffect.ocean:
        return l.ambientEffectOcean;
      case AmbientSoundEffect.wind:
        return l.ambientEffectWind;
      case AmbientSoundEffect.thunder:
        return l.ambientEffectThunder;
      case AmbientSoundEffect.birds:
        return l.ambientEffectBirds;
      case AmbientSoundEffect.cafe:
        return l.ambientEffectCafe;
      case AmbientSoundEffect.whiteNoise:
        return l.ambientEffectWhiteNoise;
    }
  }

  String localizedDisplayName(AppLocalizations l) => '$emoji ${localizedLabel(l)}';
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
  static const _keyMaster = 'ambient_master_volume';
  static const _keyAllowQuran = 'ambient_allow_during_quran';
  static const _keyMixes = 'ambient_saved_mixes_v1';

  // ─── State ─────────────────────────────────────────────────────────────────
  final Set<AmbientSoundEffect> _activeEffects = {};
  Set<AmbientSoundEffect> _lastActiveEffects = {AmbientSoundEffect.rain};
  final Map<AmbientSoundEffect, double> _volumes = {
    for (final e in AmbientSoundEffect.values) e: 0.5,
  };
  final Map<AmbientSoundEffect, bool> _loadingEffects = {};
  String? _errorMessage;
  bool _isPlayerPlaying = false;
  bool _quranModeActive = false;
  bool _allowDuringQuran = false;

  /// True when the sounds should currently be audible: at least one effect is active,
  /// the main player is playing, and Quran Mode is not asking for a clean, undisturbed recitation.
  bool get _shouldPlay =>
      isEnabled && _isPlayerPlaying && (!_quranModeActive || _allowDuringQuran);

  /// Whether ambient sounds keep playing while Quran Mode is on.
  bool get allowDuringQuran => _allowDuringQuran;

  /// True when ambient sounds are held back because Quran Mode is on.
  bool get isSuppressedByQuran => _quranModeActive && !_allowDuringQuran;

  /// Called by the player when Quran Mode turns on or off.
  void setQuranModeActive(bool active) {
    if (_quranModeActive == active) return;
    final before = _shouldPlay;
    _quranModeActive = active;
    notifyListeners();
    if (before != _shouldPlay) unawaited(_applyPlayerState());
  }

  Future<void> setAllowDuringQuran(bool allow) async {
    if (_allowDuringQuran == allow) return;
    final before = _shouldPlay;
    _allowDuringQuran = allow;
    notifyListeners();
    if (before != _shouldPlay) unawaited(_applyPlayerState());
    _persist();
  }

  double _masterVolume = 1.0;
  final Map<String, Map<String, double>> _mixes = {};
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  DateTime? _sleepEndsAt;
  int _fadeEpoch = 0;

  static const Duration _fadeDuration = Duration(milliseconds: 400);

  // --- Master volume, mixes, sleep timer ---

  /// Master volume (0.0 to 1.0) applied on top of each effect's own volume.
  double get masterVolume => _masterVolume;

  /// Saved mixes: name to (effect name to volume).
  Map<String, Map<String, double>> get savedMixes => Map.unmodifiable(_mixes);

  /// Time left on the sleep timer, or null when no timer is running.
  Duration? get sleepTimeRemaining {
    final end = _sleepEndsAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  double _effectiveVolume(AmbientSoundEffect e) =>
      ((_volumes[e] ?? 0.5) * _masterVolume * _duckFactor).clamp(0.0, 1.0);

  double _duckFactor = 1.0;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// Lowers the ambient sounds while a transient interruption (navigation
  /// prompt, assistant) ducks the main player, and restores them afterwards.
  Future<void> _listenForDucking() async {
    try {
      final session = await AudioSession.instance;
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.type != AudioInterruptionType.duck) return;
        _duckFactor = event.begin ? 0.3 : 1.0;
        for (final entry in _players.entries.toList()) {
          unawaited(entry.value
              .setVolume(_effectiveVolume(entry.key))
              .catchError((Object _) {}));
        }
      });
    } catch (_) {
      // No audio session available (e.g. unit tests): ducking is optional.
    }
  }

  Future<void> setMasterVolume(double volume) async {
    _masterVolume = volume.clamp(0.0, 1.0);
    for (final entry in _players.entries.toList()) {
      unawaited(entry.value
          .setVolume(_effectiveVolume(entry.key))
          .catchError((Object _) {}));
    }
    notifyListeners();
    _persist();
  }

  /// Starts (or with null cancels) a timer that fades out and stops all
  /// ambient effects.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepTimer = null;
    _sleepTicker = null;
    _sleepEndsAt = null;
    if (duration != null && duration > Duration.zero) {
      _sleepEndsAt = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () => unawaited(_onSleepTimerFired()));
      _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> _onSleepTimerFired() async {
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepEndsAt = null;
    final epoch = ++_fadeEpoch;
    await _fadeAll(0, epoch);
    if (_activeEffects.isNotEmpty) {
      _lastActiveEffects = Set.from(_activeEffects);
    }
    for (final e in List.of(_activeEffects)) {
      _activeEffects.remove(e);
      await _stopEffectPlayer(e);
    }
    if (!_disposed) notifyListeners();
    _persist();
  }

  /// Saves the current active effects and their volumes as [name].
  void saveMix(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _activeEffects.isEmpty) return;
    _mixes[trimmed] = {
      for (final e in _activeEffects) e.name: _volumes[e] ?? 0.5,
    };
    notifyListeners();
    _persist();
  }

  void deleteMix(String name) {
    if (_mixes.remove(name) != null) {
      notifyListeners();
      _persist();
    }
  }

  /// Replaces the active effects with those of the saved mix [name].
  Future<void> applyMix(String name) async {
    final mix = _mixes[name];
    if (mix == null) return;
    final wanted = <AmbientSoundEffect>{};
    for (final entry in mix.entries) {
      for (final e in AmbientSoundEffect.values) {
        if (e.name == entry.key) {
          wanted.add(e);
          _volumes[e] = entry.value.clamp(0.0, 1.0);
        }
      }
    }
    for (final e in List.of(_activeEffects)) {
      if (!wanted.contains(e)) await toggleEffect(e);
    }
    for (final e in wanted) {
      if (_activeEffects.contains(e)) {
        await _players[e]?.setVolume(_effectiveVolume(e));
      } else {
        await toggleEffect(e);
      }
    }
    notifyListeners();
    _persist();
  }

  Future<void> _fadeAll(double target, int epoch) async {
    const steps = 8;
    final stepDelay =
        Duration(milliseconds: _fadeDuration.inMilliseconds ~/ steps);
    final players = _players.entries.toList();
    final starts = {
      for (final e in players) e.key: e.value.volume,
    };
    for (var i = 1; i <= steps; i++) {
      if (epoch != _fadeEpoch || _disposed) return;
      final t = i / steps;
      for (final e in players) {
        final goal = target == 0 ? 0.0 : _effectiveVolume(e.key);
        final v = starts[e.key]! + (goal - starts[e.key]!) * t;
        unawaited(
            e.value.setVolume(v.clamp(0.0, 1.0)).catchError((Object _) {}));
      }
      await Future<void>.delayed(stepDelay);
    }
  }

  // ─── Public read-only access ───────────────────────────────────────────────

  /// The set of currently active (toggled-on) ambient effects.
  Set<AmbientSoundEffect> get activeEffects => Set.unmodifiable(_activeEffects);

  /// Returns true if at least one effect is active.
  bool get isEnabled => _activeEffects.isNotEmpty;

  /// Returns true if [effect] is currently toggled on.
  bool isEffectActive(AmbientSoundEffect effect) =>
      _activeEffects.contains(effect);

  /// Volume (0.0–1.0) for the given [effect].
  double volumeFor(AmbientSoundEffect effect) => _volumes[effect] ?? 0.5;

  /// True if any ambient audio is loading.
  bool get isLoading => _loadingEffects.values.any((v) => v);

  /// True if a specific effect is currently loading.
  bool isEffectLoading(AmbientSoundEffect effect) =>
      _loadingEffects[effect] ?? false;

  String? get errorMessage => _errorMessage;
  bool get isPlayerPlaying => _isPlayerPlaying;

  /// True when ambient audio is actively emitting (at least one player running).
  bool get isAudioPlaying =>
      isEnabled && _shouldPlay && _players.values.any((p) => p.playing);

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
  // Interruptions (calls, navigation prompts) are handled centrally by following
  // the main player, so ambient players never pause/resume on their own.
  static AudioPlayer Function() playerFactory =
      () => AudioPlayer(handleInterruptions: false);

  final Map<AmbientSoundEffect, AudioPlayer> _players = {};
  final Map<AmbientSoundEffect, int> _generation = {};
  bool _disposed = false;
  bool _initialized = false;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Toggle an effect on or off. When turning on, starts the player.
  /// When turning off, stops and disposes the player.
  Future<void> toggleEffect(AmbientSoundEffect effect) async {
    if (_activeEffects.contains(effect)) {
      _activeEffects.remove(effect);
      if (_activeEffects.isEmpty) {
        _lastActiveEffects = {effect};
      } else {
        _lastActiveEffects = Set.from(_activeEffects);
      }
      notifyListeners();
      await _stopEffectPlayer(effect);
    } else {
      _activeEffects.add(effect);
      _lastActiveEffects = Set.from(_activeEffects);
      notifyListeners();
      await _startEffectPlayer(effect);
    }
    _persist();
  }

  /// Set the volume for a specific effect (0.0–1.0).
  Future<void> setEffectVolume(AmbientSoundEffect effect, double volume) async {
    _volumes[effect] = volume.clamp(0.0, 1.0);
    await _players[effect]?.setVolume(_effectiveVolume(effect));
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

  /// Enables or disables ambient sounds.
  ///
  /// When [enabled] is false, remembers the current active effects, clears
  /// [_activeEffects], and stops all active ambient players.
  /// When [enabled] is true, restores previously active effects (or defaults to [AmbientSoundEffect.rain]).
  Future<void> setEnabled(bool enabled) async {
    if (enabled == isEnabled) return;
    if (!enabled) {
      if (_activeEffects.isNotEmpty) {
        _lastActiveEffects = Set.from(_activeEffects);
      }
      final toStop = List.of(_activeEffects);
      _activeEffects.clear();
      notifyListeners();
      for (final e in toStop) {
        await _stopEffectPlayer(e);
      }
      _persist();
    } else {
      final toRestore = _lastActiveEffects.isNotEmpty
          ? _lastActiveEffects
          : {AmbientSoundEffect.rain};
      for (final e in toRestore) {
        _activeEffects.add(e);
        unawaited(_startEffectPlayer(e));
      }
      notifyListeners();
      _persist();
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

    unawaited(_applyPlayerState());
  }

  Future<void> _applyPlayerState() async {
    final epoch = ++_fadeEpoch;
    final players = _players.values.toList();
    if (_shouldPlay) {
      for (final p in players) {
        try {
          await p.setVolume(0);
          if (!p.playing) unawaited(p.play().catchError((Object _) {}));
        } catch (_) {}
      }
      await _fadeAll(1, epoch);
    } else {
      await _fadeAll(0, epoch);
      if (epoch != _fadeEpoch) return;
      // Always pause (no `playing` guard): the flag can be stale while a
      // play() call is still in flight, which left sounds running.
      for (final p in players) {
        try {
          unawaited(p.pause().catchError((Object _) {}));
        } catch (_) {}
      }
    }
  }

  /// Restores persisted state from disk. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    unawaited(_listenForDucking());
    try {
      final prefs = await SharedPreferences.getInstance();

      _masterVolume = (prefs.getDouble(_keyMaster) ?? 1.0).clamp(0.0, 1.0);
      _allowDuringQuran = prefs.getBool(_keyAllowQuran) ?? false;
      final rawMixes = prefs.getString(_keyMixes);
      if (rawMixes != null && rawMixes.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawMixes);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              if (v is Map) {
                _mixes['$k'] = {
                  for (final e in v.entries)
                    '${e.key}': (e.value as num).toDouble(),
                };
              }
            });
          }
        } catch (_) {}
      }

      // Load volumes
      for (final effect in AmbientSoundEffect.values) {
        final v = prefs.getDouble('$_keyVolumePrefix${effect.name}');
        if (v != null) _volumes[effect] = v.clamp(0.0, 1.0);
      }

      // Load active effects
      final activeNames = prefs.getStringList(_keyActiveEffects) ?? [];
      for (final name in activeNames) {
        final effect = AmbientSoundEffect.values
            .cast<AmbientSoundEffect?>()
            .firstWhere(
              (e) => e?.name == name,
              orElse: () => null,
            );
        if (effect != null) {
          _activeEffects.add(effect);
        }
      }
      if (_activeEffects.isNotEmpty) {
        _lastActiveEffects = Set.from(_activeEffects);
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
    unawaited(_interruptionSub?.cancel());
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
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

    final token = _generation[effect] = (_generation[effect] ?? 0) + 1;
    bool stale() =>
        _disposed ||
        _generation[effect] != token ||
        !_activeEffects.contains(effect);

    try {
      // Dispose any existing player for this effect
      final existing = _players.remove(effect);
      await existing?.stop();
      await existing?.dispose();
      if (stale()) return;

      final player = playerFactory();
      _players[effect] = player;

      await player.setVolume(_effectiveVolume(effect));
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

      if (stale()) {
        if (identical(_players[effect], player)) _players.remove(effect);
        await player.dispose();
        return;
      }

      // Respect the main player's playback state. Never await play(): its
      // future only completes when playback stops, which left the effect
      // "loading" and blocked toggleEffect()/_persist() while it played.
      if (_shouldPlay) {
        unawaited(player.play().catchError((Object _) {}));
      } else {
        await player.pause();
      }

      if (stale()) {
        if (identical(_players[effect], player)) _players.remove(effect);
        await player.dispose();
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
    _generation[effect] = (_generation[effect] ?? 0) + 1;
    final player = _players.remove(effect);
    await player?.stop();
    await player?.dispose();
    _loadingEffects.remove(effect);
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble(_keyMaster, _masterVolume);
      prefs.setBool(_keyAllowQuran, _allowDuringQuran);
      prefs.setString(_keyMixes, jsonEncode(_mixes));
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
