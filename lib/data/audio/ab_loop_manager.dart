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
  // On an un-throttled position stream, every tick inside the B window used to
  // fire its own seek (seek-storm). This latch is raised when a wrap target is
  // handed out and lowered once playback drops back below the window (the seek
  // landed) or a short safety timeout elapses, so only one seek fires per pass.
  bool _wrapping = false;
  DateTime? _wrapAt;

  void _resetWrapLatch() {
    _wrapping = false;
    _wrapAt = null;
  }

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
    _resetWrapLatch();
    _emit();
    unawaited(persist());
  }

  void setB(Duration pos, {int? songId}) {
    if (_a == null) return;
    if (pos <= _a!) return;
    _b = pos;
    _scopeSongId ??= songId;
    _enabled = true;
    _resetWrapLatch();
    _emit();
    unawaited(persist());
  }

  void toggle() {
    if (_a == null || _b == null) return;
    _enabled = !_enabled;
    _resetWrapLatch();
    _emit();
    unawaited(persist());
  }

  void clear({bool persistDeletion = true}) {
    _a = null;
    _b = null;
    _enabled = false;
    _scopeSongId = null;
    _resetWrapLatch();
    _emit();
    if (persistDeletion) unawaited(persistCleared());
  }

  /// Returns the seek target when [pos] ran past B, else null.
  /// Automatically invalidates when the song changes.
  ///
  /// [speed] defaults to 1.0 so the existing call site (audio_handler) keeps
  /// working unchanged; it can pass the real playback speed later to widen the
  /// look-ahead and avoid overshooting B at 2–4x.
  Duration? wrapTarget(Duration pos, {int? songId, double speed = 1.0}) {
    if (!isEnabled) return null;
    if (_scopeSongId != null && songId != null && songId != _scopeSongId) {
      return null;
    }
    final a = _a;
    final b = _b;
    if (a == null || b == null) return null;

    // Scale the look-ahead tolerance with playback speed. At 1x keep the tight
    // 20ms window (avoids premature wraps); at 2–4x a single position tick
    // jumps far enough that a fixed 20ms window is overshot before it triggers,
    // so widen it by roughly the distance one ~150ms tick travels at `speed`.
    final clampedSpeed = (speed.isFinite && speed > 0) ? speed : 1.0;
    final toleranceMs =
        (20 + (clampedSpeed - 1.0) * 150).clamp(20, 600).round();
    final tolerance = Duration(milliseconds: toleranceMs);

    // Lower the latch once playback has returned below the wrap window (the
    // seek landed) or a safety timeout elapses, re-arming the next wrap.
    if (_wrapping) {
      final leftWindow = pos < b - tolerance;
      final timedOut = _wrapAt != null &&
          DateTime.now().difference(_wrapAt!) > const Duration(seconds: 2);
      if (leftWindow || timedOut) _resetWrapLatch();
    }

    // Requiring pos > A avoids wrapping when the reported position is still
    // before A; the latch avoids a seek-storm from repeated ticks in the window.
    if (!_wrapping && pos >= b - tolerance && pos > a) {
      _wrapping = true;
      _wrapAt = DateTime.now();
      return a;
    }
    return null;
  }

  void onSongChanged(int? songId) {
    if (_scopeSongId != null && songId != _scopeSongId) {
      clear(persistDeletion: false);
    }
  }

  Map<String, dynamic>? _memoryCache;

  Future<void> _ensureCacheLoaded() async {
    if (_memoryCache != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _memoryCache = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else {
        _memoryCache = <String, dynamic>{};
      }
    } catch (_) {
      _memoryCache = <String, dynamic>{};
    }
  }

  /// Restores the persisted loop for [songId], if any. Called after
  /// [onSongChanged] when a new track starts.
  Future<void> restoreForSong(int? songId) async {
    if (songId == null) return;
    try {
      await _ensureCacheLoaded();
      final entry = _memoryCache![songId.toString()];
      if (entry is! Map<String, dynamic>) return;
      final aMs = (entry['a'] as num?)?.toInt();
      final bMs = (entry['b'] as num?)?.toInt();
      if (aMs == null || bMs == null || bMs <= aMs || aMs < 0) return;
      _a = Duration(milliseconds: aMs);
      _b = Duration(milliseconds: bMs);
      _scopeSongId = songId;
      _enabled = (entry['enabled'] as bool?) ?? false;
      _resetWrapLatch();
      _emit();
    } catch (_) {}
  }

  /// Persists the current loop (or its absence) for the scoped song.
  Future<void> persist() async {
    final songId = _scopeSongId;
    try {
      await _ensureCacheLoaded();
      if (songId == null || _a == null || _b == null) {
        if (songId != null) _memoryCache!.remove(songId.toString());
      } else {
        _memoryCache![songId.toString()] = {
          'a': _a!.inMilliseconds,
          'b': _b!.inMilliseconds,
          'enabled': _enabled,
        };
        while (_memoryCache!.length > maxEntries) {
          _memoryCache!.remove(_memoryCache!.keys.first);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(_memoryCache!));
    } catch (_) {}
  }

  /// Removes the persisted entry for the scoped (or given) song, e.g. on
  /// explicit user clear.
  Future<void> persistCleared([int? songId]) async {
    final id = songId ?? _scopeSongId;
    if (id == null) return;
    try {
      await _ensureCacheLoaded();
      if (_memoryCache!.remove(id.toString()) != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsKey, jsonEncode(_memoryCache!));
      }
    } catch (_) {}
  }

  void dispose() => _changeSubject.close();
}
