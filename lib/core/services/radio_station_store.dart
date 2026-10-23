// lib/core/services/radio_station_store.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/radio_station.dart';
import '../utils/error_logger.dart';

/// Persists the user's internet radio stations as a JSON list in [SharedPreferences].
///
/// **Design Note:**
/// This class uses an intentional in-memory static store (`_stations`) across all
/// direct-constructed instances within the isolate session (e.g. between the radio
/// browsing screens and player queue mixins) to guarantee instantaneous UI consistency
/// without incurring cross-widget synchronization latency or DI graph churn.
///
/// For test isolation, use [resetForTesting] in `setUp`/`tearDown`.
class RadioStationStore {
  static const String prefsKey = 'radio_stations_v1';
  static const int maxEntries = 500;

  static final List<RadioStation> _stations = [];
  late final Future<void> ready;

  @visibleForTesting
  static void resetForTesting() {
    _stations.clear();
  }

  RadioStationStore() {
    ready = load();
  }

  /// Stations in display order (most recently added first).
  List<RadioStation> get list => List.unmodifiable(_stations);

  Future<void> add(RadioStation station) async {
    if (!RadioStation.isHttpUrl(station.url)) return;
    _stations.removeWhere((s) => s.id == station.id || s.url == station.url);
    _stations.insert(0, station);
    if (_stations.length > maxEntries) {
      _stations.removeRange(maxEntries, _stations.length);
    }
    await persist();
  }

  /// True when a station other than [exceptId] already uses [url]. Callers use
  /// this to refuse an edit that would silently delete another station.
  bool hasUrlCollision(String url, {String? exceptId}) {
    final normalized = url.trim();
    return _stations.any((s) => s.id != exceptId && s.url == normalized);
  }

  /// Atomically replaces [previous] with [updated] in a single persist pass,
  /// so a rejected update can never leave the list missing the old entry.
  /// Returns false (touching nothing) when [updated] is not a valid URL.
  Future<bool> replace(RadioStation previous, RadioStation updated) async {
    if (!RadioStation.isHttpUrl(updated.url)) return false;
    _stations.removeWhere((s) => s.id == previous.id);
    _stations.removeWhere((s) => s.id == updated.id || s.url == updated.url);
    _stations.insert(0, updated);
    if (_stations.length > maxEntries) {
      _stations.removeRange(maxEntries, _stations.length);
    }
    await persist();
    return true;
  }

  /// Adds many stations with a single persist pass. Returns the number of
  /// accepted (valid `http(s)`) stations.
  Future<int> addAll(Iterable<RadioStation> stations) async {
    var accepted = 0;
    for (final station in stations) {
      if (!RadioStation.isHttpUrl(station.url)) continue;
      _stations.removeWhere((s) => s.id == station.id || s.url == station.url);
      _stations.insert(0, station);
      if (_stations.length > maxEntries) {
        _stations.removeRange(maxEntries, _stations.length);
      }
      accepted++;
    }
    if (accepted > 0) await persist();
    return accepted;
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
      var migrated = false;
      for (final item in decoded) {
        if (item is! Map) continue;
        var station = RadioStation.fromJson(Map<String, dynamic>.from(item));
        final migratedStation = _migrateLegacyStation(station);
        if (migratedStation != null) {
          station = migratedStation;
          migrated = true;
        }
        if (station.url.isNotEmpty && RadioStation.isHttpUrl(station.url)) {
          _stations.add(station);
        }
        if (_stations.length >= maxEntries) break;
      }
      if (migrated) {
        await persist();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to load radio stations',
          error: e, stackTrace: st, category: 'RadioStationStore');
    }
  }

  static RadioStation? _migrateLegacyStation(RadioStation station) {
    if (station.id == 'cur-quran-cairo' ||
        station.url == 'https://stream.radiojar.com/8s5u8tpdtwzuv') {
      const updatedUrl = 'https://stream.radiojar.com/8s5u5tpdtwzuv';
      const updatedName = 'إذاعة القرآن الكريم المصرية - القاهرة';
      if (station.url != updatedUrl || station.name != updatedName) {
        return station.copyWith(name: updatedName, url: updatedUrl);
      }
    }
    if (station.id == 'cur-quran-tarteel' ||
        station.url == 'https://stream.qurango.net/radio/tarteel') {
      const updatedUrl = 'https://backup.qurango.net/radio/tarateel';
      const updatedName = 'إذاعة تراتيل القرآن الكريم';
      if (station.url != updatedUrl || station.name != updatedName) {
        return station.copyWith(name: updatedName, url: updatedUrl);
      }
    }
    return null;
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
            id: 'cur-quran-cairo',
            name: 'إذاعة القرآن الكريم المصرية - القاهرة',
            url: 'https://stream.radiojar.com/8s5u5tpdtwzuv',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-cairo-backup',
            name: 'إذاعة القرآن الكريم - القاهرة (بث بديل)',
            url: 'https://radio.xecod.com/station/quran-cairo',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-hussary',
            name: 'إذاعة الشيخ محمود خليل الحصري',
            url: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-abdulbasit',
            name: 'إذاعة الشيخ عبد الباسط عبد الصمد (مجود)',
            url:
                'https://backup.qurango.net/radio/abdulbasit_abdulsamad_mojawwad',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-minshawi',
            name: 'إذاعة الشيخ محمد صديق المنشاوي (مجود)',
            url:
                'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi_mojawwad',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-mustafa',
            name: 'إذاعة الشيخ مصطفى إسماعيل',
            url: 'https://backup.qurango.net/radio/mustafa_ismail',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-quran-tarteel',
            name: 'إذاعة تراتيل القرآن الكريم',
            url: 'https://backup.qurango.net/radio/tarateel',
            genre: 'Quran'),
        RadioStation(
            id: 'cur-lofi',
            name: 'Lofi Hip Hop',
            url: 'https://ice1.somafm.com/groovesalad-128-mp3',
            genre: 'Chill'),
        RadioStation(
            id: 'cur-ambient',
            name: 'Drone Zone (Ambient)',
            url: 'https://ice1.somafm.com/dronezone-128-mp3',
            genre: 'Ambient'),
        RadioStation(
            id: 'cur-paradise',
            name: 'Radio Paradise (Eclectic HQ)',
            url: 'https://stream.radioparadise.com/mp3-320',
            genre: 'Eclectic'),
        RadioStation(
            id: 'cur-classic',
            name: 'Classical Folk',
            url: 'https://ice1.somafm.com/thistle-128-mp3',
            genre: 'Classical'),
        RadioStation(
            id: 'cur-jazz',
            name: 'Smooth Jazz',
            url: 'https://ice1.somafm.com/sonicuniverse-128-mp3',
            genre: 'Jazz'),
        RadioStation(
            id: 'cur-electro',
            name: 'DEF CON Radio (Electronic)',
            url: 'https://ice1.somafm.com/defcon-128-mp3',
            genre: 'Electronic'),
        RadioStation(
            id: 'cur-rock',
            name: 'Classic Rock 70s',
            url: 'https://ice1.somafm.com/seventies-128-mp3',
            genre: 'Rock'),
        RadioStation(
            id: 'cur-indie',
            name: 'Indie Pop Rocks',
            url: 'https://ice1.somafm.com/indiepop-128-mp3',
            genre: 'Indie'),
        RadioStation(
            id: 'cur-news',
            name: 'BBC World Service',
            url: 'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service',
            genre: 'News'),
      ];

  /// Adds curated stations missing from the user list. Returns added count.
  Future<int> importCurated() async {
    for (var i = 0; i < _stations.length; i++) {
      final migrated = _migrateLegacyStation(_stations[i]);
      if (migrated != null) {
        _stations[i] = migrated;
      }
    }
    final existingUrls = _stations.map((s) => s.url).toSet();
    final existingIds = _stations.map((s) => s.id).toSet();
    var added = 0;
    for (final s in curatedDirectory()) {
      // Respect the same cap as add()/load so importing onto a near-full
      // user list can't push the store past maxEntries.
      if (_stations.length >= maxEntries) break;
      if (!existingUrls.contains(s.url) && !existingIds.contains(s.id)) {
        _stations.add(s);
        existingUrls.add(s.url);
        existingIds.add(s.id);
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
