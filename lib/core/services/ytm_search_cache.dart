// lib/core/services/ytm_search_cache.dart
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';

/// Last successful results for a query, so an offline search is not a dead end.
///
/// This is intentionally a small, bounded, best-effort cache: the point is the
/// query the user just repeated while the network dropped, not a complete
/// offline index. A miss, corrupt payload or expired entry is always a normal
/// cache miss — search itself must never fail because of this store.
@lazySingleton
class YtmSearchCache {
  static const String prefsKey = 'ytm_search_cache_v1';
  static const int maxEntries = 30;
  static const int maxResultsPerEntry = 40;
  static const Duration ttl = Duration(days: 14);

  static String normalize(String query) => query.trim().toLowerCase();

  Future<List<YtmTrack>> read(String query, {DateTime? now}) async {
    final key = normalize(query);
    if (key.isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _decode(prefs.getString(prefsKey));
      final at = now ?? DateTime.now();
      for (final entry in entries) {
        if (entry.query != key) continue;
        if (at.difference(entry.savedAt) > ttl) return const [];
        return List<YtmTrack>.unmodifiable(entry.results);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read the YTM search cache',
          error: e, stackTrace: st, category: 'YtmSearchCache');
    }
    return const [];
  }

  Future<void> write(
    String query,
    List<YtmTrack> results, {
    DateTime? now,
  }) async {
    final key = normalize(query);
    if (key.isEmpty || results.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = _decode(prefs.getString(prefsKey))
        ..removeWhere((entry) => entry.query == key);
      entries.insert(
        0,
        _CacheEntry(
          query: key,
          savedAt: now ?? DateTime.now(),
          results: List<YtmTrack>.unmodifiable(
            results
                .where((track) => track.videoId.isNotEmpty)
                .take(maxResultsPerEntry),
          ),
        ),
      );
      if (entries.length > maxEntries) {
        entries.removeRange(maxEntries, entries.length);
      }
      await prefs.setString(
        prefsKey,
        jsonEncode([
          for (final entry in entries)
            {
              'q': entry.query,
              'at': entry.savedAt.toIso8601String(),
              'results': [for (final track in entry.results) track.toJson()],
            },
        ]),
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to write the YTM search cache',
          error: e, stackTrace: st, category: 'YtmSearchCache');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (e, st) {
      ErrorLogger.log('Failed to clear the YTM search cache',
          error: e, stackTrace: st, category: 'YtmSearchCache');
    }
  }

  static List<_CacheEntry> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final entries = <_CacheEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final query = (map['q'] as String?)?.trim() ?? '';
      final at = DateTime.tryParse(map['at'] as String? ?? '');
      final rawResults = map['results'];
      if (query.isEmpty || at == null || rawResults is! List) continue;
      final results = <YtmTrack>[];
      for (final result in rawResults) {
        if (result is! Map) continue;
        final track = YtmTrack.fromJson(result.cast<String, dynamic>());
        if (track.videoId.isNotEmpty) results.add(track);
      }
      if (results.isEmpty) continue;
      entries.add(_CacheEntry(query: query, savedAt: at, results: results));
    }
    return entries;
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.query,
    required this.savedAt,
    required this.results,
  });

  final String query;
  final DateTime savedAt;
  final List<YtmTrack> results;
}
