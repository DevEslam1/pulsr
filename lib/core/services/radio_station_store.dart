// lib/core/services/radio_station_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/radio_station.dart';
import '../utils/error_logger.dart';

/// Persists the user's internet radio stations as a JSON list in
/// [SharedPreferences]. Plain class (no injectable annotation): constructed
/// directly like [BpmOverrideStore] to avoid regenerating the DI graph.
/// The station list is static-shared so direct-constructed instances (radio
/// screen, player queue mixin) never diverge within a session.
class RadioStationStore {
  static const String prefsKey = 'radio_stations_v1';
  static const int maxEntries = 500;

  static final List<RadioStation> _stations = [];
  late final Future<void> ready;

  RadioStationStore() {
    ready = load();
  }

  /// Stations in display order (most recently added first).
  List<RadioStation> get list => List.unmodifiable(_stations);

  Future<void> add(RadioStation station) async {
    if (!RadioStation.isHttpUrl(station.url)) return;
    _stations.removeWhere(
        (s) => s.id == station.id || s.url == station.url);
    _stations.insert(0, station);
    if (_stations.length > maxEntries) {
      _stations.removeRange(maxEntries, _stations.length);
    }
    await persist();
  }

  Future<void> remove(String id) async {
    final before = _stations.length;
    _stations.removeWhere((s) => s.id == id);
    if (_stations.length != before) await persist();
  }

  Future<void> markPlayed(String id, int timestampMs) async {
    final index = _stations.indexWhere((s) => s.id == id);
    if (index == -1) return;
    _stations[index] = _stations[index].copyWith(lastPlayed: timestampMs);
    await persist();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      // The station list is process-static, so an empty/missing store must
      // clear it — otherwise stations from a previous session (or a cleared
      // store) leak back into the current one.
      if (raw == null || raw.isEmpty) {
        _stations.clear();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _stations.clear();
      for (final item in decoded) {
        if (item is! Map) continue;
        final station = RadioStation.fromJson(Map<String, dynamic>.from(item));
        if (station.url.isNotEmpty && RadioStation.isHttpUrl(station.url)) {
          _stations.add(station);
        }
        if (_stations.length >= maxEntries) break;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load radio stations',
          error: e, stackTrace: st, category: 'RadioStationStore');
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode(_stations.map((s) => s.toJson()).toList()),
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to persist radio stations',
          error: e, stackTrace: st, category: 'RadioStationStore');
    }
  }

  /// Curated starter directory (all public free streams). Imported on demand
  /// via [importCurated] — never auto-added, so user lists stay theirs.
  static List<RadioStation> curatedDirectory() => [
        RadioStation(
            id: 'cur-lofi', name: 'Lofi Hip Hop', url: 'https://ice1.somafm.com/groovesalad-128-mp3', genre: 'Chill'),
        RadioStation(
            id: 'cur-ambient', name: 'Drone Zone (Ambient)', url: 'https://ice1.somafm.com/dronezone-128-mp3', genre: 'Ambient'),
        RadioStation(
            id: 'cur-paradise', name: 'Radio Paradise (Eclectic HQ)', url: 'https://stream.radioparadise.com/mp3-320', genre: 'Eclectic'),
        RadioStation(
            id: 'cur-classic', name: 'Classical Folk', url: 'https://ice1.somafm.com/thistle-128-mp3', genre: 'Classical'),
        RadioStation(
            id: 'cur-jazz', name: 'Smooth Jazz', url: 'https://ice1.somafm.com/sonicuniverse-128-mp3', genre: 'Jazz'),
        RadioStation(
            id: 'cur-electro', name: 'DEF CON Radio (Electronic)', url: 'https://ice1.somafm.com/defcon-128-mp3', genre: 'Electronic'),
        RadioStation(
            id: 'cur-rock', name: 'Classic Rock 70s', url: 'https://ice1.somafm.com/seventies-128-mp3', genre: 'Rock'),
        RadioStation(
            id: 'cur-indie', name: 'Indie Pop Rocks', url: 'https://ice1.somafm.com/indiepop-128-mp3', genre: 'Indie'),
        RadioStation(
            id: 'cur-news', name: 'BBC World Service', url: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service', genre: 'News'),
        RadioStation(
            id: 'cur-quran-cairo', name: 'Cairo Quran Radio', url: 'https://stream.radiojar.com/8s5u8tpdtwzuv', genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-tarteel', name: 'Holy Quran Tarteel', url: 'https://stream.qurango.net/radio/tarteel', genre: 'Quran'),
      ];

  /// Adds curated stations missing from the user list. Returns added count.
  Future<int> importCurated() async {
    final existing = _stations.map((s) => s.url).toSet();
    var added = 0;
    for (final s in curatedDirectory()) {
      if (!existing.contains(s.url)) {
        _stations.add(s);
        added++;
      }
    }
    if (added > 0) await persist();
    return added;
  }

  /// Extracts the absolute `http(s)://` stream URLs from `.m3u` / `.m3u8`  /// playlist content, mirroring the line parser used for local playlists:
  /// blank lines and `#` directives are skipped, quotes are stripped, and
  /// only absolute stream URLs are kept (relative paths are local files).
  static List<String> extractStreamUrls(String content) {
    final urls = <String>[];
    final seen = <String>{};
    for (final line in content.split(RegExp(r'\r?\n'))) {
      var trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (trimmed.length >= 2 &&
          ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
              (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
        trimmed = trimmed.substring(1, trimmed.length - 1).trim();
      }
      if (!RadioStation.isHttpUrl(trimmed)) continue;
      if (seen.add(trimmed)) urls.add(trimmed);
    }
    return urls;
  }
}
