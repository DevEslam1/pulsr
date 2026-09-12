// F1: AB Loop (repeat segment A→B).
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds a single A→B loop region and decides when a position tick
/// must wrap back to A.
///
/// Loop points persist per track in SharedPreferences (`ab_loops_v1`,
/// capped at 100 tracks) and are restored when the track starts, so a
/// practice loop survives app restarts.
class AbLoopManager {
  static const String prefsKey = 'ab_loops_v1';
  static const int maxEntries = 100;
  Duration? _a;
  Duration? _b;
  bool _enabled = false;
  int? _scopeSongId;

  final StreamController<bool> _changeSubject =
      StreamController<bool>.broadcast();
  Stream<bool> get changes => _changeSubject.stream;

  Duration? get pointA => _a;
  Duration? get pointB => _b;
  bool get isEnabled => _enabled && _a != null && _b != null;
  bool get hasA => _a != null;
  bool get hasB => _b != null;

  void _emit() {
    if (!_changeSubject.isClosed) _changeSubject.add(isEnabled);
  }

  /// Sets point A. Clears B if it now precedes A.
  void setA(Duration pos, {int? songId}) {
    _a = pos;
    _scopeSongId = songId;
    if (_b != null && _b! <= _a!) _b = null;
    _enabled = _a != null && _b != null ? _enabled : false;
    _emit();
    unawaited(persist());
  }

  void setB(Duration pos, {int? songId}) {
    if (_a == null) return;
    if (pos <= _a!) return;
    _b = pos;
    _scopeSongId ??= songId;
    _enabled = true;
    _emit();
    unawaited(persist());
  }

  void toggle() {
    if (_a == null || _b == null) return;
    _enabled = !_enabled;
    _emit();
    unawaited(persist());
  }

  void clear({bool persistDeletion = true}) {
    _a = null;
    _b = null;
    _enabled = false;
    _scopeSongId = null;
    _emit();
    if (persistDeletion) unawaited(persistCleared());
  }

  /// Returns the seek target when [pos] ran past B, else null.
  /// Automatically invalidates when the song changes.
  Duration? wrapTarget(Duration pos, {int? songId}) {
    if (!isEnabled) return null;
    if (_scopeSongId != null && songId != null && songId != _scopeSongId) {
      return null;
    }
    if (_b != null && pos >= _b!) return _a;
    return null;
  }

  void onSongChanged(int? songId) {
    if (_scopeSongId != null && songId != _scopeSongId) {
      clear(persistDeletion: false);
    }
  }

  /// Restores the persisted loop for [songId], if any. Called after
  /// [onSongChanged] when a new track starts.
  Future<void> restoreForSong(int? songId) async {
    if (songId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entry = decoded[songId.toString()];
      if (entry is! Map<String, dynamic>) return;
      final aMs = (entry['a'] as num?)?.toInt();
      final bMs = (entry['b'] as num?)?.toInt();
      if (aMs == null || bMs == null || bMs <= aMs || aMs < 0) return;
      _a = Duration(milliseconds: aMs);
      _b = Duration(milliseconds: bMs);
      _scopeSongId = songId;
      _enabled = (entry['enabled'] as bool?) ?? false;
      _emit();
    } catch (_) {}
  }

  /// Persists the current loop (or its absence) for the scoped song.
  Future<void> persist() async {
    final songId = _scopeSongId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> all;
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) {
        all = <String, dynamic>{};
      } else {
        all = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
      if (songId == null || _a == null || _b == null) {
        if (songId != null) all.remove(songId.toString());
      } else {
        all[songId.toString()] = {
          'a': _a!.inMilliseconds,
          'b': _b!.inMilliseconds,
          'enabled': _enabled,
        };
        while (all.length > maxEntries) {
          all.remove(all.keys.first);
        }
      }
      await prefs.setString(prefsKey, jsonEncode(all));
    } catch (_) {}
  }

  /// Removes the persisted entry for the scoped (or given) song, e.g. on
  /// explicit user clear.
  Future<void> persistCleared([int? songId]) async {
    final id = songId ?? _scopeSongId;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final all = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (all.remove(id.toString()) != null) {
        await prefs.setString(prefsKey, jsonEncode(all));
      }
    } catch (_) {}
  }

  void dispose() => _changeSubject.close();
}
