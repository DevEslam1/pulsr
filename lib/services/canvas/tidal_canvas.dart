// lib/services/canvas/tidal_canvas.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/error_logger.dart';
import 'canvas_artwork.dart';

/// Tidal's square video cover search.
class TidalCanvas {
  static const String searchEndpoint = 'https://api.tidal.com/v1/search';
  static const String embedToken = 'vNVdglQOjFJJGG2U';

  TidalCanvas({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Searches Tidal for a track's looping video cover.
  Future<CanvasArtwork?> search(
      String title, String artist, String? album) async {
    final cleanTitle = cleanNoise(title);
    final query = album != null && album.trim().isNotEmpty
        ? '$album $artist $cleanTitle'
        : '$artist $cleanTitle';

    final uri = Uri.parse(searchEndpoint).replace(queryParameters: {
      'query': query,
      'limit': '10',
      'types': 'TRACKS',
      'countryCode': 'US',
    });

    final body = await _get(uri.toString());
    if (body == null) return null;

    try {
      final Map<String, dynamic> root = jsonDecode(body);
      final tracks = root['tracks'] as Map<String, dynamic>?;
      final items = tracks?['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final trackTitle = item['title']?.toString();
        if (trackTitle == null) continue;

        final artistsList = item['artists'] as List<dynamic>?;
        final artists = artistsList
                ?.whereType<Map<String, dynamic>>()
                .map((a) => a['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList() ??
            const <String>[];

        if (!_isMatch(trackTitle, artists, cleanTitle, artist)) continue;

        final albumObj = item['album'] as Map<String, dynamic>?;
        final videoCover = albumObj?['videoCover']?.toString();
        if (videoCover == null || videoCover.trim().isEmpty) continue;

        final videoUrl = coverUrl(videoCover);
        if (videoUrl == null) continue;

        return CanvasArtwork(
          videoUrl: videoUrl,
          title: trackTitle,
          artist: artists.join(', ').trim(),
          album: albumObj?['title']?.toString(),
          source: 'tidal',
        );
      }
    } catch (e, st) {
      ErrorLogger.log('TidalCanvas search error',
          error: e, stackTrace: st, category: 'TidalCanvas');
    }
    return null;
  }

  /// Searches Tidal for an album's video cover.
  Future<CanvasArtwork?> searchAlbum(String album, String artist) async {
    final uri = Uri.parse(searchEndpoint).replace(queryParameters: {
      'query': '$album $artist',
      'limit': '10',
      'types': 'ALBUMS',
      'countryCode': 'US',
    });

    final body = await _get(uri.toString());
    if (body == null) return null;

    try {
      final Map<String, dynamic> root = jsonDecode(body);
      final albumsObj = root['albums'] as Map<String, dynamic>?;
      final items = albumsObj?['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) return null;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final recordTitle = item['title']?.toString();
        if (recordTitle == null) continue;

        final artistsList = item['artists'] as List<dynamic>?;
        final artists = artistsList
                ?.whereType<Map<String, dynamic>>()
                .map((a) => a['name']?.toString() ?? '')
                .where((name) => name.isNotEmpty)
                .toList() ??
            const <String>[];

        if (!_isMatch(recordTitle, artists, album, artist)) continue;

        final videoCover = item['videoCover']?.toString();
        if (videoCover == null || videoCover.trim().isEmpty) continue;

        final videoUrl = coverUrl(videoCover);
        if (videoUrl == null) continue;

        return CanvasArtwork(
          videoUrl: videoUrl,
          title: recordTitle,
          artist: artists.join(', ').trim(),
          album: recordTitle,
          source: 'tidal',
        );
      }
    } catch (e, st) {
      ErrorLogger.log('TidalCanvas searchAlbum error',
          error: e, stackTrace: st, category: 'TidalCanvas');
    }
    return null;
  }

  bool _isMatch(
    String gotName,
    List<String> gotArtists,
    String wantName,
    String wantArtist,
  ) {
    if (normalizeForMatch(gotName) != normalizeForMatch(wantName)) return false;
    final wanted = splitArtists(wantArtist);
    final credited =
        gotArtists.map(normalizeForMatch).where((a) => a.isNotEmpty).toList();
    if (wanted.isEmpty || credited.isEmpty) return false;
    return wanted.every((want) => credited.any((c) => c == want));
  }

  /// Converts Tidal 5-part video cover ID into CDN MP4 URL.
  static String? coverUrl(String id) {
    final parts = id.trim().split('-');
    if (parts.length != 5) return null;
    return 'https://resources.tidal.com/videos/${parts.join('/')}/1280x1280.mp4';
  }

  Future<String?> _get(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await _client.get(
        uri,
        headers: {
          'X-Tidal-Token': embedToken,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (_) {}
    return null;
  }
}
