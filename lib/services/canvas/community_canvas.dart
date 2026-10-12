// lib/services/canvas/community_canvas.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/utils/error_logger.dart';
import 'canvas_artwork.dart';

class _CommunityEntry {
  final String song;
  final String artist;
  final String album;
  final String url;

  _CommunityEntry({
    required this.song,
    required this.artist,
    required this.album,
    required this.url,
  });
}

/// Community Canvas index curator: fetches the 30-minute cached community manifest.
class CommunityCanvas {
  static const String manifestUrl =
      'https://vivimusicanvas.mkmdevilmi.workers.dev/canvas.json';
  static const Duration ttl = Duration(minutes: 30);

  CommunityCanvas({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  List<_CommunityEntry> _entries = [];
  DateTime? _fetchedAt;

  /// Searches the community manifest for a track matching [title] and [artist].
  Future<CanvasArtwork?> search(
      String title, String artist, String? album) async {
    final index = await _getManifest();
    if (index.isEmpty) return null;

    final wantTitle = normalizeForMatch(cleanNoise(title));
    final wantArtist = normalizeForMatch(artist);
    final wantAlbum = album != null ? normalizeForMatch(album) : null;

    if (wantTitle.isEmpty || wantArtist.isEmpty) return null;

    for (final entry in index) {
      final song = normalizeForMatch(cleanNoise(entry.song));
      final credited = normalizeForMatch(entry.artist);
      final listed = normalizeForMatch(entry.album);

      final titleOk = song.isNotEmpty &&
          (wantTitle.contains(song) || song.contains(wantTitle));
      final artistOk = credited.isNotEmpty &&
          (wantArtist.contains(credited) || credited.contains(wantArtist));
      final albumOk = listed.isEmpty ||
          wantAlbum == null ||
          wantAlbum.isEmpty ||
          listed == wantAlbum;

      if (titleOk && artistOk && albumOk) {
        return CanvasArtwork(
          videoUrl: entry.url,
          title: entry.song,
          artist: entry.artist,
          album: entry.album.isNotEmpty ? entry.album : null,
          source: 'community',
        );
      }
    }
    return null;
  }

  /// Searches the community manifest for an album's motion artwork.
  Future<CanvasArtwork?> searchAlbum(String album, String artist) async {
    final index = await _getManifest();
    if (index.isEmpty) return null;

    final wantAlbum = normalizeForMatch(album);
    final wantArtist = normalizeForMatch(artist);
    if (wantAlbum.isEmpty) return null;

    for (final entry in index) {
      final listed = normalizeForMatch(entry.album);
      final credited = normalizeForMatch(entry.artist);

      if (listed == wantAlbum &&
          credited.isNotEmpty &&
          (wantArtist.contains(credited) || credited.contains(wantArtist))) {
        return CanvasArtwork(
          videoUrl: entry.url,
          title: entry.album,
          artist: entry.artist,
          album: entry.album,
          source: 'community',
        );
      }
    }
    return null;
  }

  Future<List<_CommunityEntry>> _getManifest() async {
    final now = DateTime.now();
    if (_entries.isNotEmpty &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < ttl) {
      return _entries;
    }

    try {
      final uri = Uri.parse(manifestUrl);
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final List<dynamic> items;
        if (decoded is Map<String, dynamic> && decoded['items'] is List) {
          items = decoded['items'] as List<dynamic>;
        } else if (decoded is List) {
          items = decoded;
        } else {
          items = const [];
        }

        final parsed = items
            .whereType<Map<String, dynamic>>()
            .map((obj) {
              final song = obj['song']?.toString() ?? '';
              final artist = obj['artist']?.toString() ?? '';
              final album = obj['album']?.toString() ?? '';
              final url = obj['url']?.toString() ?? '';
              if (song.isEmpty || artist.isEmpty || url.isEmpty) return null;
              return _CommunityEntry(
                song: song,
                artist: artist,
                album: album,
                url: url,
              );
            })
            .whereType<_CommunityEntry>()
            .toList();

        if (parsed.isNotEmpty) {
          _entries = parsed;
          _fetchedAt = now;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('CommunityCanvas manifest fetch error',
          error: e, stackTrace: st, category: 'CommunityCanvas');
    }

    return _entries;
  }
}
