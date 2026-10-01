import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

/// Ultra-fast synchronous in-memory settings cache backed by [SharedPreferences].
///
/// Eliminates asynchronous await latencies during UI builds and background service queries.
@singleton
class SettingsCache {
  static final SettingsCache _instance = SettingsCache._internal();
  factory SettingsCache() => _instance;
  SettingsCache._internal();

  SharedPreferences? _prefs;
  final Map<String, Object?> _cache = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes the in-memory cache from disk. Called during app startup.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final keys = _prefs!.getKeys();
      for (final key in keys) {
        _cache[key] = _prefs!.get(key);
      }
      _isInitialized = true;
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize SettingsCache',
          error: e, stackTrace: st, category: 'SettingsCache');
    }
  }

  // Synchronous Getters
  bool getBool(String key, {bool defaultValue = false}) {
    final val = _cache[key];
    if (val is bool) return val;
    return _prefs?.getBool(key) ?? defaultValue;
  }

  int getInt(String key, {int defaultValue = 0}) {
    final val = _cache[key];
    if (val is int) return val;
    return _prefs?.getInt(key) ?? defaultValue;
  }

  double getDouble(String key, {double defaultValue = 0.0}) {
    final val = _cache[key];
    if (val is double) return val;
    return _prefs?.getDouble(key) ?? defaultValue;
  }

  String getString(String key, {String defaultValue = ''}) {
    final val = _cache[key];
    if (val is String) return val;
    return _prefs?.getString(key) ?? defaultValue;
  }

  List<String> getStringList(String key,
      {List<String> defaultValue = const []}) {
    final val = _cache[key];
    if (val is List<String>) return val;
    return _prefs?.getStringList(key) ?? defaultValue;
  }

  bool containsKey(String key) {
    return _cache.containsKey(key) || (_prefs?.containsKey(key) ?? false);
  }

  // Write-Through Setters
  Future<bool> setBool(String key, bool value) async {
    _cache[key] = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.setBool(key, value);
  }

  Future<bool> setInt(String key, int value) async {
    _cache[key] = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.setInt(key, value);
  }

  Future<bool> setDouble(String key, double value) async {
    _cache[key] = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.setDouble(key, value);
  }

  Future<bool> setString(String key, String value) async {
    _cache[key] = value;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.setString(key, value);
  }

  Future<bool> setStringList(String key, List<String> value) async {
    _cache[key] = List<String>.from(value);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.setStringList(key, value);
  }

  Future<bool> remove(String key) async {
    _cache.remove(key);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.remove(key);
  }
}
