import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// An abstraction for preferences storage with an in-memory read cache and batched/async writing.
class PrefsRepository {
  final SharedPreferences _prefs;
  final Map<String, dynamic> _memoryCache = {};
  Timer? _batchTimer;
  final Map<String, dynamic> _pendingWrites = {};

  PrefsRepository(this._prefs) {
    // Populate in-memory cache with all existing keys
    for (final key in _prefs.getKeys()) {
      _memoryCache[key] = _prefs.get(key);
    }
  }

  static Future<PrefsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsRepository(prefs);
  }

  /// Get value with in-memory fallback.
  T? get<T>(String key) {
    if (_memoryCache.containsKey(key)) {
      final v = _memoryCache[key];
      if (v is T) return v;
      // FIX B8: a type-mismatched cache entry is stale; drop it so a later
      // read re-fetches from disk instead of forever returning null.
      _memoryCache.remove(key);
      return null;
    }
    final val = _prefs.get(key);
    if (val is T) {
      _memoryCache[key] = val;
      return val;
    }
    return null;
  }

  bool? getBool(String key) => get<bool>(key);
  String? getString(String key) => get<String>(key);
  int? getInt(String key) => get<int>(key);
  double? getDouble(String key) => get<double>(key);
  List<String>? getStringList(String key) => get<List<String>>(key);

  /// Synchronously updates the in-memory cache and schedules a batched disk write,
  /// or writes immediately to disk if [immediate] is true (Issue 14).
  Future<void> set<T>(String key, T value, {bool immediate = false}) async {
    _memoryCache[key] = value;
    if (immediate) {
      _pendingWrites.remove(key);
      await _writeToDisk(key, value);
    } else {
      _pendingWrites[key] = value;
      _scheduleBatchWrite();
    }
  }

  Future<void> setBool(String key, bool value, {bool immediate = false}) =>
      set(key, value, immediate: immediate);

  Future<void> setString(String key, String value, {bool immediate = false}) =>
      set(key, value, immediate: immediate);

  Future<void> setInt(String key, int value, {bool immediate = false}) =>
      set(key, value, immediate: immediate);

  Future<void> setDouble(String key, double value, {bool immediate = false}) =>
      set(key, value, immediate: immediate);

  Future<void> setStringList(String key, List<String> value, {bool immediate = false}) =>
      set(key, value, immediate: immediate);

  /// Cancels the batch timer and flushes any pending writes to prevent data loss.
  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    unawaited(flush());
  }

  Future<void> remove(String key) async {
    _memoryCache.remove(key);
    _pendingWrites.remove(key);
    await _prefs.remove(key);
  }

  Future<void> flush() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_pendingWrites.isEmpty) return;

    final writes = Map<String, dynamic>.from(_pendingWrites);
    _pendingWrites.clear();
    for (final entry in writes.entries) {
      await _writeToDisk(entry.key, entry.value);
    }
  }

  void _scheduleBatchWrite() {
    _batchTimer ??= Timer(const Duration(milliseconds: 300), () {
      _batchTimer = null;
      flush();
    });
  }

  Future<void> _writeToDisk(String key, dynamic value) async {
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is List<String>) {
      await _prefs.setStringList(key, value);
    }
  }
}
