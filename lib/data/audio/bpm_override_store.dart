// lib/data/audio/bpm_override_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

/// Persists manual per-track BPM overrides (40–240, inclusive). The BPM-synced
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

  /// Insertion-ordered: the first keys are the least recently set.
  final Map<String, double> _overrides = {};
  late final Future<void> ready;
  bool _clearedBeforeLoad = false;
  Future<void> _persistChain = Future<void>.value();

  BpmOverrideStore() {
    ready = load();
  }

  /// BPM for [trackKey], or null when unset.
  double? getBpmForTrack(String trackKey) => _overrides[trackKey];

  /// Sets (or clears with null) the BPM override for [trackKey].
  /// Returns false when the value or key is invalid.
  Future<bool> setBpmForTrack(String trackKey, double? bpm) async {
    // Wait for the initial load: otherwise load() could overwrite this edit,
    // or persist() could write a partial map over the stored one.
    await ready;
    if (bpm == null) {
      _overrides.remove(trackKey);
      await persist();
      return true;
    }
    if (trackKey.isEmpty) return false;
    if (!bpm.isFinite || bpm < minBpm || bpm > maxBpm) return false;
    // Remove first so an updated key moves to the "most recent" end;
    // otherwise a re-set entry keeps its old position and is evicted first.
    _overrides.remove(trackKey);
    _overrides[trackKey] = bpm;
    _trimToLimit();
    await persist();
    return true;
  }

  void clearAll() {
    _clearedBeforeLoad = true;
    _overrides.clear();
    unawaited(persist());
  }

  Map<String, double> snapshot() => Map.unmodifiable(_overrides);

  void _trimToLimit() {
    final excess = _overrides.length - maxEntries;
    if (excess <= 0) return;
    final keysToRemove = _overrides.keys.take(excess).toList();
    for (final k in keysToRemove) {
      _overrides.remove(k);
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      if (_clearedBeforeLoad) return; // user cleared before load finished
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (k is String && v is num) {
          final d = v.toDouble();
          if (d.isFinite && d >= minBpm && d <= maxBpm) {
            // In-memory edits made before load completed win over stored data.
            _overrides.putIfAbsent(k, () => d);
          }
        }
      });
      _trimToLimit();
    } catch (e, st) {
      ErrorLogger.log('Failed to load per-track BPM overrides',
          error: e, stackTrace: st, category: 'BpmOverrideStore');
    }
  }

  /// Writes are serialized so an older snapshot can never land after a newer one.
  Future<void> persist() {
    _persistChain = _persistChain.then((_) => _persistNow());
    return _persistChain;
  }

  Future<void> _persistNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _trimToLimit();
      await prefs.setString(prefsKey, jsonEncode(_overrides));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist per-track BPM overrides',
          error: e, stackTrace: st, category: 'BpmOverrideStore');
    }
  }
}
