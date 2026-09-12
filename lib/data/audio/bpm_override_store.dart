// lib/data/audio/bpm_override_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Persists manual per-track BPM overrides (40–240). The BPM-synced
/// crossfade reads these through [PulsrAudioHandler] into
/// `CrossfadeManager.bpmOverrides`, so the toggle has a real signal source.
///
/// Plain class (no injectable annotation): constructed directly like
/// [SilenceSkipController] to avoid regenerating the DI graph.
class BpmOverrideStore {
  static const String prefsKey = 'per_track_bpm_overrides_v1';
  static const int maxEntries = 500;
  static const double minBpm = 40.0;
  static const double maxBpm = 240.0;

  final Map<String, double> _overrides = {};
  late final Future<void> ready;

  BpmOverrideStore() {
    ready = load();
  }

  /// BPM for [trackKey], or null when unset.
  double? getBpmForTrack(String trackKey) => _overrides[trackKey];

  /// Sets (or clears with null) the BPM override for [trackKey].
  /// Returns false when the value is out of range.
  Future<bool> setBpmForTrack(String trackKey, double? bpm) async {
    if (bpm == null) {
      _overrides.remove(trackKey);
      await persist();
      return true;
    }
    if (!bpm.isFinite || bpm < minBpm || bpm > maxBpm) return false;
    _overrides[trackKey] = bpm;
    await persist();
    return true;
  }

  void clearAll() {
    _overrides.clear();
    unawaited(persist());
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
          final d = v.toDouble();
          if (d.isFinite && d >= minBpm && d <= maxBpm) {
            _overrides[k] = d;
          }
        }
      });
    } catch (e, st) {
      ErrorLogger.log('Failed to load per-track BPM overrides',
          error: e, stackTrace: st, category: 'BpmOverrideStore');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_overrides.length > maxEntries) {
        final keysToRemove =
            _overrides.keys.take(_overrides.length - maxEntries).toList();
        for (final k in keysToRemove) {
          _overrides.remove(k);
        }
      }
      await prefs.setString(prefsKey, jsonEncode(_overrides));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist per-track BPM overrides',
          error: e, stackTrace: st, category: 'BpmOverrideStore');
    }
  }
}
