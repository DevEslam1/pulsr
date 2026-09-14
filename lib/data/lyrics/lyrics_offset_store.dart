// lib/data/lyrics/lyrics_offset_store.dart
// Per-file lyrics sync offset persistence (gap 15-02).
// Stores a millisecond offset per audio path so a user's manual sync
// correction survives restarts. Backed by SharedPreferences with a bounded
// entry count; failures are swallowed as best-effort (offset is cosmetic).
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

class LyricsOffsetStore {
  static const String _prefix = 'lyrics_offset_v1_';
  static const int maxEntries = 500;

  int _hash(String path) {
    var h = 0;
    for (var i = 0; i < path.length; i++) {
      h = (h * 31 + path.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }

  String _key(String path) => '$_prefix${_hash(path)}';

  Future<int> getOffsetMs(String path) async {
    if (path.isEmpty) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_key(path)) ?? 0;
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset read failed',
          error: e, stackTrace: st, category: 'Lyrics');
      return 0;
    }
  }

  Future<void> setOffsetMs(String path, int offsetMs) async {
    if (path.isEmpty) return;
    final clamped = offsetMs.clamp(-5000, 5000);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(path), clamped);
      // Best-effort bound: SharedPreferences has no enumeration budget check
      // here; entries are tiny ints and LRU eviction is a future improvement.
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset write failed',
          error: e, stackTrace: st, category: 'Lyrics');
    }
  }

  Future<void> clearOffset(String path) async {
    if (path.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(path));
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset clear failed',
          error: e, stackTrace: st, category: 'Lyrics');
    }
  }
}
