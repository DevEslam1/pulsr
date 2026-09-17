// lib/data/lyrics/lyrics_offset_store.dart
// Per-file lyrics sync offset persistence (gap 15-02).
// Stores a millisecond offset per audio path so a user's manual sync
// correction survives restarts. Backed by SharedPreferences with a bounded
// entry count; failures are swallowed as best-effort (offset is cosmetic).
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

class LyricsOffsetStore {
  static const String _prefix = 'lyrics_offset_v1_';
  static const String _pathSuffix = '_path';
  static const String _indexKey = 'lyrics_offset_index_v1';
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
      // Collision guard: the hash key may belong to a different path.
      final owner = prefs.getString('${_key(path)}$_pathSuffix');
      if (owner != null && owner != path) return 0;
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
      final key = _key(path);
      await prefs.setInt(key, clamped);
      await prefs.setString('$key$_pathSuffix', path);
      await _touchIndex(prefs, key);
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset write failed',
          error: e, stackTrace: st, category: 'Lyrics');
    }
  }

  Future<void> _touchIndex(SharedPreferences prefs, String key) async {
    try {
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      index.remove(key);
      index.add(key);
      // Evict oldest beyond the bound (both value and path marker).
      while (index.length > maxEntries) {
        final evicted = index.removeAt(0);
        await prefs.remove(evicted);
        await prefs.remove('$evicted$_pathSuffix');
      }
      await prefs.setStringList(_indexKey, index);
    } catch (_) {}
  }

  Future<void> clearOffset(String path) async {
    if (path.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(path);
      await prefs.remove(key);
      await prefs.remove('$key$_pathSuffix');
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      if (index.remove(key)) await prefs.setStringList(_indexKey, index);
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset clear failed',
          error: e, stackTrace: st, category: 'Lyrics');
    }
  }
}
