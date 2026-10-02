// lib/data/lyrics/lyrics_offset_store.dart
// Per-file lyrics sync offset persistence (gap 15-02).
// Stores a millisecond offset per audio path so a user's manual sync
// correction survives restarts. Backed by SharedPreferences with a bounded
// entry count; failures are swallowed as best-effort (offset is cosmetic).
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/error_logger.dart';

class LyricsOffsetStore {
  static const String _prefix = 'lyrics_offset_v1_';
  static const String _pathSuffix = '_path';
  static const String _indexKey = 'lyrics_offset_index_v1';
  static const int maxEntries = 500;

  /// Serializes all read-modify-write operations on [_indexKey]. Without this,
  /// two concurrent `setOffsetMs` calls can each read the same index snapshot
  /// and the second write silently drops the first key. Shared by every
  /// instance because SharedPreferences itself is process-global.
  static Future<void> _indexChain = Future<void>.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _indexChain = _indexChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  String _hash(String path) {
    var h1 = 0x811c9dc5;
    var h2 = 5381;
    for (var i = 0; i < path.length; i++) {
      final code = path.codeUnitAt(i);
      h1 = ((h1 ^ code) * 0x01000193) & 0x7fffffff;
      h2 = (((h2 << 5) + h2) + code) & 0x7fffffff;
    }
    return '${path.length}_${h1.toRadixString(16)}_${h2.toRadixString(16)}';
  }

  String _legacyKey(String path) {
    var h = 0;
    for (var i = 0; i < path.length; i++) {
      h = (h * 31 + path.codeUnitAt(i)) & 0x7fffffff;
    }
    return '$_prefix$h';
  }

  String _key(String path) => '$_prefix${_hash(path)}';

  Future<int> getOffsetMs(String path) async {
    if (path.isEmpty) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(path);
      // Collision guard: the hash key may belong to a different path.
      final owner = prefs.getString('$key$_pathSuffix');
      if (owner == path) {
        return prefs.getInt(key) ?? 0;
      }
      // Check legacy key for migration
      final legKey = _legacyKey(path);
      final legOwner = prefs.getString('$legKey$_pathSuffix');
      if (legOwner == path) {
        final val = prefs.getInt(legKey) ?? 0;
        await prefs.setInt(key, val);
        await prefs.setString('$key$_pathSuffix', path);
        await prefs.remove(legKey);
        await prefs.remove('$legKey$_pathSuffix');
        return val;
      }
      if (owner != null && owner != path) return 0;
      return prefs.getInt(key) ?? 0;
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

  Future<void> _touchIndex(SharedPreferences prefs, String key) {
    return _synchronized(() async {
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
      } catch (e, st) {
        ErrorLogger.log('Lyrics offset index update failed',
            error: e, stackTrace: st, category: 'Lyrics');
      }
    });
  }

  Future<void> clearOffset(String path) async {
    if (path.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(path);
      await prefs.remove(key);
      await prefs.remove('$key$_pathSuffix');
      await _synchronized(() async {
        final index = prefs.getStringList(_indexKey) ?? <String>[];
        if (index.remove(key)) await prefs.setStringList(_indexKey, index);
      });
    } catch (e, st) {
      ErrorLogger.log('Lyrics offset clear failed',
          error: e, stackTrace: st, category: 'Lyrics');
    }
  }
}
