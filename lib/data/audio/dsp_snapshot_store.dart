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

  static double _finite(double v) => v.isFinite ? v : 0.0;

  /// Recursively replaces NaN/Infinity so the nested effects map (dozens of
  /// DSP params, IR samples) can never make jsonEncode throw.
  static dynamic _sanitize(dynamic v) {
    if (v is double) return _finite(v);
    if (v is List) return v.map(_sanitize).toList();
    if (v is Map) return v.map((k, val) => MapEntry(k, _sanitize(val)));
    return v;
  }

  // jsonEncode throws on NaN/Infinity, and persist() swallows the error, so one
  // bad value used to silently stop ALL snapshots from ever being saved.
  Map<String, dynamic> toMap() => {
        'preset': presetName,
        'gains': gains.map(_finite).toList(),
        'volumeBoost': _finite(volumeBoost),
        'bassBoost': _finite(bassBoost),
        'savedAt': savedAt.millisecondsSinceEpoch,
        if (effects != null) 'effects': _sanitize(effects),
      };

  static DspSnapshot? fromMap(Map<String, dynamic> m) {
    try {
      final gains = (m['gains'] as List)
          .map((e) => (e as num).toDouble())
          .map((g) => g.isFinite ? g : 0.0)
          .toList();
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

  /// False for empty / placeholder tags. Without this every "Unknown Album" (or
  /// empty-artist) track shared ONE snapshot key and overwrote each other.
  static bool isUsableScope(String? value) {
    if (value == null) return false;
    final v = value.trim().toLowerCase();
    return v.isNotEmpty &&
        v != 'unknown' &&
        v != '<unknown>' &&
        v != 'unknown album' &&
        v != 'unknown artist';
  }

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
    // A disabled store must not apply snapshots (it previously only blocked
    // saving, so the toggle did nothing for recall).
    if (!enabled) return null;
    // Route through recall() so a hit is refreshed to the MRU position and is
    // not evicted ahead of stale entries by the LRU cap.
    if (isUsableScope(album) && isUsableScope(artist)) {
      final s = recall(albumKey(album!, artist!));
      if (s != null) return s;
    }
    if (isUsableScope(artist)) {
      final s = recall(artistKey(artist!));
      if (s != null) return s;
    }
    if (isUsableScope(genre)) {
      final s = recall(genreKey(genre!));
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
      while (_snapshots.length > maxEntries) {
        _snapshots.remove(_snapshots.keys.first);
      }
    } catch (_) {}
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${prefsKey}_enabled', enabled);
      await prefs.setString(prefsKey,
          jsonEncode(_snapshots.map((k, v) => MapEntry(k, v.toMap()))));
    } catch (_) {}
  }
}
