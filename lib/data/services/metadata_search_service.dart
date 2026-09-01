// lib/core/services/metadata_search_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/utils/error_logger.dart';

class OnlineTrackMetadata {
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final String? releaseYear;
  final String? trackNumber;
  final String? artworkUrl;

  const OnlineTrackMetadata({
    required this.title,
    required this.artist,
    required this.album,
    this.genre,
    this.releaseYear,
    this.trackNumber,
    this.artworkUrl,
  });
}

@lazySingleton
class MetadataSearchService {
  final http.Client _httpClient;

  MetadataSearchService([http.Client? httpClient])
      : _httpClient = httpClient ?? http.Client();

  /// Searches iTunes and MusicBrainz APIs for track metadata matching [query] or [artist] & [title].
  Future<List<OnlineTrackMetadata>> searchMetadata({
    required String title,
    String? artist,
    String? album,
  }) async {
    final results = <OnlineTrackMetadata>[];

    // 1. Search iTunes Search API (fast, reliable, high-res artwork)
    try {
      final queryTerms = [
        title,
        if (artist != null &&
            artist.isNotEmpty &&
            artist.toLowerCase() != 'unknown artist')
          artist,
      ].join(' ');

      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': queryTerms,
        'media': 'music',
        'entity': 'song',
        'limit': '10',
      });

      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['results'] as List<dynamic>?) ?? [];

        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final trackName = item['trackName'] as String? ?? '';
          final artistName = item['artistName'] as String? ?? '';
          final collectionName = item['collectionName'] as String? ?? '';
          final primaryGenre = item['primaryGenreName'] as String?;
          final releaseDate = item['releaseDate'] as String?;
          final trackNum = item['trackNumber']?.toString();

          // Get high-res artwork (replace 100x100 with 1400x1400)
          String? artUrl = item['artworkUrl100'] as String?;
          if (artUrl != null) {
            artUrl = artUrl
                .replaceAll('100x100bb', '1400x1400bb')
                .replaceAll('100x100', '1400x1400');
          }

          String? year;
          if (releaseDate != null && releaseDate.length >= 4) {
            year = releaseDate.substring(0, 4);
          }

          if (trackName.isNotEmpty) {
            results.add(OnlineTrackMetadata(
              title: trackName,
              artist: artistName,
              album: collectionName,
              genre: primaryGenre,
              releaseYear: year,
              trackNumber: trackNum,
              artworkUrl: artUrl,
            ));
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('iTunes metadata search failed',
          error: e, stackTrace: st, category: 'MetadataSearch');
    }

    return results;
  }

  Future<String?> downloadArtworkToTemp(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final fileName =
            'auto_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to download auto artwork: $url',
          error: e, stackTrace: st, category: 'MetadataSearch');
    }
    return null;
  }
}

