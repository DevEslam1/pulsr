// lib/data/audio/per_song_eq_store.dart
import 'dart:convert';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Persists per-song EQ preset overrides. When a song starts playing,
/// if it has an assigned preset name, the equalizer auto-switches to it.
@singleton
class PerSongEqStore {
  static const String prefsKey = 'per_song_eq_overrides_v1';
  static const int maxEntries = 500;

  final Map<String, String> _overrides = {};
  late final Future<void> ready;

  PerSongEqStore() {
    ready = load();
  }

  /// Returns the assigned EQ preset name for [trackKey] (e.g. song.id or song.path), or null if none.
  String? getPresetForTrack(String trackKey) => _overrides[trackKey];

  /// Sets or clears the EQ preset override for [trackKey].
  Future<void> setPresetForTrack(String trackKey, String? presetName) async {
    if (presetName == null || presetName.trim().isEmpty || presetName.trim().toLowerCase() == 'none') {
      _overrides.remove(trackKey);
    } else {
      _overrides[trackKey] = presetName.trim();
    }
    await persist();
  }

  void clearAll() {
    _overrides.clear();
    persist();
  }

  Map<String, String> snapshot() => Map.unmodifiable(_overrides);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _overrides.clear();
      decoded.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          _overrides[k] = v;
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load per-song EQ overrides',
          error: e, stackTrace: st, category: 'PerSongEqStore');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cap at maxEntries (evict oldest entries if exceeded)
      if (_overrides.length > maxEntries) {
        final keysToRemove = _overrides.keys.take(_overrides.length - maxEntries).toList();
        for (final k in keysToRemove) {
          _overrides.remove(k);
        }
      }
      final encoded = jsonEncode(_overrides);
      await prefs.setString(prefsKey, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist per-song EQ overrides',
          error: e, stackTrace: st, category: 'PerSongEqStore');
    }
  }
}
