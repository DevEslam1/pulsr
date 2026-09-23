// lib/core/services/artist_bio_service.dart
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';

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
  final LinkedHashMap<String, ArtistInfo> _cache = LinkedHashMap<String, ArtistInfo>();
  static const int _maxCacheSize = 150;

  ArtistBioService([http.Client? client]) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  /// Fetches artist info and picture from Deezer and Wikipedia APIs.
  /// Returns null immediately when offline-only mode is enabled.
  Future<ArtistInfo?> getArtistInfo(String artistName) async {
    final cleanName = artistName.trim();
    if (cleanName.isEmpty || cleanName.toLowerCase() == 'unknown artist') {
      return null;
    }

    final key = cleanName.toLowerCase();
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key)!;
      _cache[key] = cached; // LRU refresh
      return cached;
    }

    try {
      if (!AppConfig.isCloudSyncAllowed) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('setting_offline_only_mode') == true) return null;
    } catch (e, st) {
      ErrorLogger.log('Failed to read offline-only preference for artist bio',
          error: e, stackTrace: st, category: 'ArtistBio');
    }

    try {
      final deezerUri = Uri.parse(
          'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(cleanName)}&limit=1');
      final wikiUri = Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(cleanName)}');

      final deezerFuture = _client.get(deezerUri).timeout(const Duration(seconds: 8)).catchError((e, st) {
        ErrorLogger.log('Deezer artist lookup failed for $cleanName',
            error: e, stackTrace: st, category: 'ArtistBio');
        return http.Response('', 500);
      });

      final wikiFuture = _client.get(wikiUri).timeout(const Duration(seconds: 6)).catchError((e, st) {
        ErrorLogger.log('Wikipedia bio lookup failed for $cleanName',
            error: e, stackTrace: st, category: 'ArtistBio');
        return http.Response('', 500);
      });

      final results = await Future.wait([deezerFuture, wikiFuture]);
      final res = results[0];
      final wikiRes = results[1];

      String? pictureUrl;
      int? fanCount;

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        try {
          final data = json.decode(res.body);
          final list = data['data'] as List<dynamic>?;
          if (list != null && list.isNotEmpty) {
            final first = list.first;
            pictureUrl = first['picture_xl'] ??
                first['picture_big'] ??
                first['picture_medium'];
            fanCount = (first['nb_fan'] as num?)?.toInt();
          }
        } catch (_) {}
      }

      String? bio;
      if (wikiRes.statusCode == 200 && wikiRes.body.isNotEmpty) {
        try {
          final wikiData = json.decode(wikiRes.body);
          bio = wikiData['extract'] as String?;
        } catch (_) {}
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
      _cache[key] = info;
      return info;
    } catch (e, st) {
      ErrorLogger.log('Failed to fetch artist info for $cleanName',
          error: e, stackTrace: st, category: 'ArtistBioService');
      return null;
    }
  }
}
