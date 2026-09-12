import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';

class SponsorBlockSegment {
  final String category;
  final Duration start;
  final Duration end;
  final String uuid;

  const SponsorBlockSegment({
    required this.category,
    required this.start,
    required this.end,
    required this.uuid,
  });

  bool contains(Duration position) {
    return position >= start && position < end;
  }
}

@singleton
class SponsorBlockService {
  static final SponsorBlockService instance = SponsorBlockService();

  final http.Client _client;
  final Map<String, List<SponsorBlockSegment>> _cache = {};

  SponsorBlockService([http.Client? client]) : _client = client ?? http.Client();

  /// Categories the service can request and skip. Order is used by the UI.
  static const List<String> supportedCategories = [
    'sponsor',
    'selfpromo',
    'interaction',
    'intro',
    'outro',
    'music_offtopic',
  ];

  SharedPreferences? _prefs;
  bool _enabled = true;
  Set<String> _enabledCategories = Set.of(supportedCategories);

  /// Whether auto-skip is enabled (default true). Reflects persisted prefs
  /// once [loadPreferences] has run and is updated immediately by
  /// [setSkipEnabled].
  bool get isEnabled => _enabled;

  /// Categories currently eligible for auto-skip. Treat as read-only.
  Set<String> get enabledCategories => _enabledCategories;

  /// Loads the persisted SponsorBlock controls. Safe to call more than once.
  Future<void> loadPreferences() async {
    if (_prefs != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _enabled = prefs.getBool(PrefsKeys.sponsorBlockEnabled) ?? true;
      final saved = prefs.getStringList(PrefsKeys.sponsorBlockCategories);
      if (saved != null) {
        _enabledCategories =
            saved.where(supportedCategories.contains).toSet();
      }
    } catch (_) {}
  }

  Future<void> setSkipEnabled(bool enabled) async {
    _enabled = enabled;
    await loadPreferences();
    try {
      await _prefs?.setBool(PrefsKeys.sponsorBlockEnabled, enabled);
    } catch (_) {}
  }

  Future<void> setEnabledCategories(Set<String> categories) async {
    _enabledCategories =
        categories.where(supportedCategories.contains).toSet();
    await loadPreferences();
    try {
      await _prefs?.setStringList(
          PrefsKeys.sponsorBlockCategories, _enabledCategories.toList());
    } catch (_) {}
  }

  /// Retrieves skip segments for a YouTube video. Results are cached in-memory.
  Future<List<SponsorBlockSegment>> getSegments(String videoId) async {
    await loadPreferences();
    // Letting an empty set short-circuit avoids a pointless request when the
    // user has disabled every category.
    if (!_enabled || _enabledCategories.isEmpty) return const [];

    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return const [];

    if (_cache.containsKey(cleanId)) {
      return _cache[cleanId]!;
    }

    try {
      final uri = Uri.https(
        'sponsor.ajay.app',
        '/api/skipSegments',
        {
          'videoID': cleanId,
          'category': jsonEncode(_enabledCategories.toList()),
          'actionType': 'skip',
        },
      );

      final response = await _client.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 404 || response.body == 'Not Found') {
        _cache[cleanId] = const [];
        return const [];
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          final segments = <SponsorBlockSegment>[];
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final rawSegment = item['segment'];
            if (rawSegment is! List || rawSegment.length < 2) continue;

            final startSec = (rawSegment[0] as num).toDouble();
            final endSec = (rawSegment[1] as num).toDouble();
            if (endSec <= startSec) continue;

            segments.add(
              SponsorBlockSegment(
                category: item['category'] as String? ?? 'sponsor',
                start: Duration(milliseconds: (startSec * 1000).round()),
                end: Duration(milliseconds: (endSec * 1000).round()),
                uuid: item['UUID'] as String? ?? '',
              ),
            );
          }

          segments.sort((a, b) => a.start.compareTo(b.start));
          _cache[cleanId] = segments;
          return segments;
        }
      }
    } catch (e) {
      debugPrint('[SPONSORBLOCK] Failed to fetch skip segments for $cleanId: $e');
    }

    return const [];
  }

  /// Finds any segment that spans [position].
  SponsorBlockSegment? findSegmentToSkip(
      List<SponsorBlockSegment> segments, Duration position) {
    for (final seg in segments) {
      if (seg.contains(position)) {
        return seg;
      }
    }
    return null;
  }

  void clearCache() {
    _cache.clear();
  }
}
