// F1: AB Loop (repeat segment A→B).
import 'dart:async';

/// Holds a single A→B loop region and decides when a position tick
/// must wrap back to A.
class AbLoopManager {
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
  }

  void setB(Duration pos, {int? songId}) {
    if (_a == null) return;
    if (pos <= _a!) return;
    _b = pos;
    _scopeSongId ??= songId;
    _enabled = true;
    _emit();
  }

  void toggle() {
    if (_a == null || _b == null) return;
    _enabled = !_enabled;
    _emit();
  }

  void clear() {
    _a = null;
    _b = null;
    _enabled = false;
    _scopeSongId = null;
    _emit();
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
    if (_scopeSongId != null && songId != _scopeSongId) clear();
  }

  void dispose() => _changeSubject.close();
}
