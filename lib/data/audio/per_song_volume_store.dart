// lib/data/audio/per_song_volume_store.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Persists per-song volume overrides in decibels (-12.0 dB to +6.0 dB).
/// Applied dynamically during playback volume calculation.
@singleton
class PerSongVolumeStore {
  static const String prefsKey = 'per_song_volume_overrides_v1';
  static const int maxEntries = 500;
  static const double minGainDb = -12.0;
  static const double maxGainDb = 6.0;

  final Map<String, double> _overrides = {};
  late final Future<void> ready;

  PerSongVolumeStore() {
    ready = load();
  }

  /// Returns the volume gain in dB for [trackKey] (defaults to 0.0 dB / no change).
  double getGainDbForTrack(String trackKey) => _overrides[trackKey] ?? 0.0;

  /// Sets or clears the volume override for [trackKey].
  Future<void> setGainDbForTrack(String trackKey, double gainDb) async {
    final clamped = gainDb.clamp(minGainDb, maxGainDb);
    if (clamped.abs() < 0.1) {
      _overrides.remove(trackKey);
    } else {
      _overrides[trackKey] = clamped;
    }
    await persist();
  }

  void clearAll() {
    _overrides.clear();
    persist();
  }

  Map<String, double> snapshot() => Map.unmodifiable(_overrides);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _overrides.clear();
      decoded.forEach((k, v) {
        if (v is num) {
          final d = v.toDouble().clamp(minGainDb, maxGainDb);
          if (d.abs() >= 0.1) {
            _overrides[k] = d;
          }
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load per-song volume overrides',
          error: e, stackTrace: st, category: 'PerSongVolumeStore');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_overrides.length > maxEntries) {
        final keysToRemove = _overrides.keys.take(_overrides.length - maxEntries).toList();
        for (final k in keysToRemove) {
          _overrides.remove(k);
        }
      }
      final encoded = jsonEncode(_overrides);
      await prefs.setString(prefsKey, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist per-song volume overrides',
          error: e, stackTrace: st, category: 'PerSongVolumeStore');
    }
  }
}
