// F9: Per-session DSP snapshot (restore EQ per album / artist / genre).
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A lightweight snapshot of the DSP chain for one scope key.
class DspSnapshot {
  final String presetName;
  final List<double> gains;
  final double volumeBoost;
  final double bassBoost;
  final DateTime savedAt;

  /// Full effect-chain state (all JamesDSP / Phase-1 stages), produced by
  /// `EqualizerManager.captureEffectsState()`. Null for legacy v1 snapshots
  /// that only captured the graphic-EQ curve; recall falls back to the
  /// preset/gains fields above in that case.
  final Map<String, dynamic>? effects;

  const DspSnapshot({
    required this.presetName,
    required this.gains,
    this.volumeBoost = 0.0,
    this.bassBoost = 0.0,
    required this.savedAt,
    this.effects,
  });

  Map<String, dynamic> toMap() => {
        'preset': presetName,
        'gains': gains,
        'volumeBoost': volumeBoost,
        'bassBoost': bassBoost,
        'savedAt': savedAt.millisecondsSinceEpoch,
        if (effects != null) 'effects': effects,
      };

  static DspSnapshot? fromMap(Map<String, dynamic> m) {
    try {
      final gains = (m['gains'] as List).map((e) => (e as num).toDouble()).toList();
      final rawEffects = m['effects'];
      return DspSnapshot(
        presetName: m['preset'] as String? ?? 'Flat',
        gains: gains,
        volumeBoost: (m['volumeBoost'] as num?)?.toDouble() ?? 0.0,
        bassBoost: (m['bassBoost'] as num?)?.toDouble() ?? 0.0,
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['savedAt'] as num?)?.toInt() ?? 0),
        effects:
            rawEffects is Map ? Map<String, dynamic>.from(rawEffects) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Stores snapshots keyed by album/artist/genre scope. LRU-capped.
class DspSnapshotStore {
  static const String prefsKey = 'dsp_snapshot_store_v1';
  static const int maxEntries = 100;

  final Map<String, DspSnapshot> _snapshots = {};
  bool enabled = true;

  Map<String, DspSnapshot> snapshot() => Map.unmodifiable(_snapshots);

  static String albumKey(String album, String artist) =>
      'album:${artist.trim().toLowerCase()}::${album.trim().toLowerCase()}';
  static String artistKey(String artist) =>
      'artist:${artist.trim().toLowerCase()}';
  static String genreKey(String genre) => 'genre:${genre.trim().toLowerCase()}';

  void save(String scopeKey, DspSnapshot snap) {
    if (!enabled) return;
    _snapshots.remove(scopeKey);
    _snapshots[scopeKey] = snap;
    while (_snapshots.length > maxEntries) {
      _snapshots.remove(_snapshots.keys.first);
    }
  }

  DspSnapshot? recall(String scopeKey) {
    final snap = _snapshots.remove(scopeKey);
    if (snap != null) _snapshots[scopeKey] = snap; // Move to end (MRU)
    return snap;
  }

  /// Recall precedence: album > artist > genre.
  DspSnapshot? recallFor({
    String? album,
    String? artist,
    String? genre,
  }) {
    if (album != null && artist != null) {
      final s = _snapshots[albumKey(album, artist)];
      if (s != null) return s;
    }
    if (artist != null) {
      final s = _snapshots[artistKey(artist)];
      if (s != null) return s;
    }
    if (genre != null) {
      final s = _snapshots[genreKey(genre)];
      if (s != null) return s;
    }
    return null;
  }

  void remove(String scopeKey) => _snapshots.remove(scopeKey);
  void clear() => _snapshots.clear();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('${prefsKey}_enabled') ?? true;
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _snapshots.clear();
      decoded.forEach((k, v) {
        if (v is Map) {
          final s = DspSnapshot.fromMap(Map<String, dynamic>.from(v));
          if (s != null) _snapshots[k] = s;
        }
      });
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${prefsKey}_enabled', enabled);
      await prefs.setString(
          prefsKey, jsonEncode(_snapshots.map((k, v) => MapEntry(k, v.toMap()))));
    } catch (_) {}
  }
}
