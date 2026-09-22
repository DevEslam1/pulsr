// lib/data/audio/per_song_playback_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// A-01: Lightweight per-song playback memory.
///
/// Remembers a track's individual playback speed and pitch so that resuming it
/// (bookmark / last position) restores the user's prior settings. Volume and EQ
/// overrides already have dedicated stores ([PerSongVolumeStore],
/// [PerSongEqStore]); this store covers the remaining transport parameters.
///
/// Only non-default values are stored, and the map is capped at [maxEntries].
class PerSongPlaybackStore {
  static const String prefsKey = 'per_song_playback_memory_v1';
  static const int maxEntries = 500;
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;
  static const double minPitch = 0.5;
  static const double maxPitch = 2.0;

  final Map<String, ({double speed, double pitch})> _memory = {};
  late final Future<void> ready;

  PerSongPlaybackStore() {
    ready = load();
  }

  /// Remembered speed for [trackKey], or null when none/near-default.
  double? getSpeed(String trackKey) {
    final entry = _memory[trackKey];
    if (entry == null) return null;
    return (entry.speed - 1.0).abs() < 0.001 ? null : entry.speed;
  }

  /// Remembered pitch for [trackKey], or null when none/near-default.
  double? getPitch(String trackKey) {
    final entry = _memory[trackKey];
    if (entry == null) return null;
    return (entry.pitch - 1.0).abs() < 0.001 ? null : entry.pitch;
  }

  Future<void> setSpeed(String trackKey, double speed) async {
    await ready;
    final clamped = speed.clamp(minSpeed, maxSpeed);
    _update(trackKey, speed: clamped);
    await persist();
  }

  Future<void> setPitch(String trackKey, double pitch) async {
    await ready;
    final clamped = pitch.clamp(minPitch, maxPitch);
    _update(trackKey, pitch: clamped);
    await persist();
  }

  void _update(String trackKey, {double? speed, double? pitch}) {
    final existing = _memory[trackKey];
    final nextSpeed = speed ?? existing?.speed ?? 1.0;
    final nextPitch = pitch ?? existing?.pitch ?? 1.0;
    final isDefault =
        (nextSpeed - 1.0).abs() < 0.001 && (nextPitch - 1.0).abs() < 0.001;
    if (isDefault) {
      _memory.remove(trackKey);
    } else {
      _memory[trackKey] = (speed: nextSpeed, pitch: nextPitch);
    }
  }

  void clearForTrack(String trackKey) {
    _memory.remove(trackKey);
    persist();
  }

  void clearAll() {
    _memory.clear();
    persist();
  }

  Map<String, ({double speed, double pitch})> snapshot() =>
      Map.unmodifiable(_memory);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _memory.clear();
      decoded.forEach((key, value) {
        if (value is Map) {
          final speed = (value['speed'] as num?)?.toDouble() ?? 1.0;
          final pitch = (value['pitch'] as num?)?.toDouble() ?? 1.0;
          final isDefault =
              (speed - 1.0).abs() < 0.001 && (pitch - 1.0).abs() < 0.001;
          if (!isDefault) {
            _memory[key] = (
              speed: speed.clamp(minSpeed, maxSpeed),
              pitch: pitch.clamp(minPitch, maxPitch),
            );
          }
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load per-song playback memory',
          error: e, stackTrace: st, category: 'PerSongPlaybackStore');
    }
  }

  Future<void> persist() async {
    try {
      if (_memory.length > maxEntries) {
        final keysToRemove =
            _memory.keys.take(_memory.length - maxEntries).toList();
        for (final k in keysToRemove) {
          _memory.remove(k);
        }
      }
      final encoded = jsonEncode({
        for (final entry in _memory.entries)
          entry.key: {
            'speed': entry.value.speed,
            'pitch': entry.value.pitch,
          },
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist per-song playback memory',
          error: e, stackTrace: st, category: 'PerSongPlaybackStore');
    }
  }
}
