import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

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

  static const _defaultCategories = [
    'sponsor',
    'selfpromo',
    'interaction',
    'intro',
    'outro',
    'music_offtopic',
  ];

  /// Retrieves skip segments for a YouTube video. Results are cached in-memory.
  Future<List<SponsorBlockSegment>> getSegments(String videoId) async {
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
          'category': jsonEncode(_defaultCategories),
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
