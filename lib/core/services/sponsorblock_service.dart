import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
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
    // Pulsr Pure / offline-only: never reach the SponsorBlock API.
    if (!AppConfig.isCloudSyncAllowed) return const [];
    await loadPreferences();
    // Letting an empty set short-circuit avoids a pointless request when the
    // user has disabled every category.
    if (!_enabled || _enabledCategories.isEmpty) return const [];

    // Bound the in-memory cache so a long session cannot grow it unbounded.
    if (_cache.length > 256) _cache.clear();

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
          // Merge overlapping or contiguous intervals to prevent skip bounce loops
          final merged = <SponsorBlockSegment>[];
          for (final seg in segments) {
            if (merged.isEmpty) {
              merged.add(seg);
            } else {
              final last = merged.last;
              // Only merge same-category segments: merging an enabled and a
              // disabled category would apply one category's policy to the
              // other's content during eligibility filtering.
              if (seg.start <= last.end && seg.category == last.category) {
                final maxEnd = seg.end > last.end ? seg.end : last.end;
                merged[merged.length - 1] = SponsorBlockSegment(
                  category: last.category,
                  start: last.start,
                  end: maxEnd,
                  uuid: '${last.uuid}_${seg.uuid}',
                );
              } else {
                merged.add(seg);
              }
            }
          }
          _cache[cleanId] = merged;
          return merged;
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

  /// Pure skip decision extracted from PlayerCubit (god-object split): given
  /// the fetched [segments], the user-enabled [enabledCategories] and the
  /// current [position], returns the seek target (chained segment end + 50ms)
  /// when auto-skip should fire, else null.
  ///
  /// Debounce, last-skip guards and the actual seek stay caller-side (they own
  /// mutable playback state); this method only decides. Chaining walks
  /// adjacent/overlapping segments so the target never lands inside the next
  /// one (which would re-trigger or suppress the following tick).
  Duration? findSkipTarget({
    required List<SponsorBlockSegment> segments,
    required Set<String> enabledCategories,
    required Duration position,
  }) {
    final eligible = <SponsorBlockSegment>[
      for (final seg in segments)
        if (enabledCategories.contains(seg.category)) seg,
    ];
    final hit = findSegmentToSkip(eligible, position);
    if (hit == null) return null;
    var target = hit.end;
    var chained = true;
    while (chained) {
      chained = false;
      // Chain only over eligible segments: extending past a disabled-category
      // neighbour would skip content the user asked to keep.
      for (final other in eligible) {
        if (other.end > target && other.contains(target)) {
          target = other.end;
          chained = true;
        }
      }
    }
    return target + const Duration(milliseconds: 50);
  }

  void clearCache() {
    _cache.clear();
  }
}
