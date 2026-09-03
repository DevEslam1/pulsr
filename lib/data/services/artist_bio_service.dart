// lib/data/services/artist_bio_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import '../../core/utils/error_logger.dart';

class ArtistInfo {
  final String name;
  final String? bio;
  final String? pictureUrl;
  final int? fanCount;
  final List<String> topTracks;

  const ArtistInfo({
    required this.name,
    this.bio,
    this.pictureUrl,
    this.fanCount,
    this.topTracks = const [],
  });
}

@singleton
class ArtistBioService {
  final http.Client _client;
  final Map<String, ArtistInfo> _cache = {};
  static const int _maxCacheSize = 150;

  ArtistBioService([http.Client? client]) : _client = client ?? http.Client();

  /// Fetches artist info and picture from Deezer and Wikipedia APIs.
  Future<ArtistInfo?> getArtistInfo(String artistName) async {
    final cleanName = artistName.trim();
    if (cleanName.isEmpty || cleanName.toLowerCase() == 'unknown artist') {
      return null;
    }

    if (_cache.containsKey(cleanName.toLowerCase())) {
      return _cache[cleanName.toLowerCase()];
    }

    try {
      // 1. Search Deezer for HD Artist Picture and Top Tracks
      final uri = Uri.parse(
          'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(cleanName)}&limit=1');
      final res = await _client.get(uri).timeout(const Duration(seconds: 8));

      String? pictureUrl;
      int? fanCount;

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = data['data'] as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          final first = list.first;
          pictureUrl = (first['picture_xl'] ??
                  first['picture_big'] ??
                  first['picture_medium']) as String?;
          fanCount = (first['nb_fan'] as num?)?.toInt();
        }
      }

      // 2. Fetch artist bio snippet from Wikipedia API
      String? bio;
      try {
        final wikiUri = Uri.parse(
            'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(cleanName)}');
        final wikiRes =
            await _client.get(wikiUri).timeout(const Duration(seconds: 6));
        if (wikiRes.statusCode == 200) {
          final wikiData = json.decode(wikiRes.body);
          bio = wikiData['extract'] as String?;
        }
      } catch (e, st) {
        ErrorLogger.log('toInt failed', error: e, stackTrace: st, category: 'ArtistBioService');
      }

      final info = ArtistInfo(
        name: cleanName,
        bio: bio ?? '$cleanName is a featured artist in your library.',
        pictureUrl: pictureUrl,
        fanCount: fanCount,
      );

      if (_cache.length >= _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cleanName.toLowerCase()] = info;
      return info;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch artist info for $cleanName',
          error: e, stackTrace: st, category: 'ArtistBioService');
      return null;
    }
  }
}

