// lib/core/services/metadata_search_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../constants/prefs_keys.dart';
import '../network/remote_target_policy.dart';
import '../utils/error_logger.dart';

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
  static const int _maxArtworkBytes = 10 * 1024 * 1024;
  static final RegExp _luceneSpecialChars =
      RegExp(r'[+\-&|!(){}\[\]^"~*?:\\/]');

  final http.Client _httpClient;
  final bool _ownsClient;

  MetadataSearchService([http.Client? httpClient])
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  @disposeMethod
  void dispose() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  static String _escapeLucene(String value) =>
      value.trim().replaceAllMapped(_luceneSpecialChars, (m) => '\\${m[0]}');

  /// Searches online metadata matching [title] & [artist].
  /// Sources: iTunes Search API first (fast, high-res artwork), then
  /// MusicBrainz (open, no key, slower) as fallback/enrichment.
  /// Returns empty when offline-only mode is enabled.
  Future<List<OnlineTrackMetadata>> searchMetadata({
    required String title,
    String? artist,
    String? album,
  }) async {
    try {
      if (!AppConfig.isCloudSyncAllowed) return const [];
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefsKeys.offlineOnlyMode) == true) return const [];
    } catch (e, st) {
      ErrorLogger.log('Failed to read offline-only preference for metadata',
          error: e, stackTrace: st, category: 'MetadataSearch');
    }
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

    // 2. MusicBrainz fallback (open API, no key): fills gaps iTunes misses
    // (obscure pressings, non-Latin catalog). Rate-limited to 1 req/s per
    // their etiquette — single query per search, 10s timeout.
    if (results.isEmpty && title.trim().isNotEmpty) {
      try {
        final query = [
          'recording:"${_escapeLucene(title)}"',
          if (artist != null &&
              artist.isNotEmpty &&
              artist.toLowerCase() != 'unknown artist')
            'artist:"${_escapeLucene(artist)}"',
        ].join(' AND ');
        final uri = Uri.https('musicbrainz.org', '/ws/2/recording/', {
          'query': query,
          'fmt': 'json',
          'limit': '8',
        });
        final response = await _httpClient.get(uri, headers: {
          'User-Agent': 'Pulsr/${AppConfig.appVersion} ( https://pulsr.music )',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = (data['recordings'] as List<dynamic>?) ?? [];
          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final recTitle = item['title'] as String? ?? '';
            if (recTitle.isEmpty) continue;
            var recArtist = '';
            String? recAlbum;
            String? recYear;
            final artists = (item['artist-credit'] as List<dynamic>?) ?? [];
            if (artists.isNotEmpty) {
              final names = <String>[];
              for (final a in artists) {
                if (a is Map<String, dynamic>) {
                  final n = (a['name'] as String?) ??
                      (a['artist'] is Map
                          ? (a['artist'] as Map)['name'] as String?
                          : null);
                  if (n != null && n.isNotEmpty) names.add(n);
                } else if (a is String && a.isNotEmpty) {
                  names.add(a);
                }
              }
              recArtist = names.join(', ');
            }
            final releases = (item['releases'] as List<dynamic>?) ?? [];
            if (releases.isNotEmpty && releases.first is Map) {
              final rel = releases.first as Map<String, dynamic>;
              recAlbum = rel['title'] as String?;
              final date = rel['date'] as String?;
              if (date != null && date.length >= 4) {
                recYear = date.substring(0, 4);
              }
            }
            results.add(OnlineTrackMetadata(
              title: recTitle,
              artist: recArtist.isNotEmpty
                  ? recArtist
                  : (artist ?? 'Unknown Artist'),
              album: recAlbum ?? album ?? '',
              releaseYear: recYear,
              // MusicBrainz core has no genre/artwork inline; Cover Art
              // Archive fetch would need per-release MBIDs (slow) — artwork
              // stays iTunes-sourced.
            ));
          }
        }
      } catch (e, st) {
        ErrorLogger.log('MusicBrainz metadata search failed',
            error: e, stackTrace: st, category: 'MetadataSearch');
      }
    }

    return results;
  }

  Future<String?> downloadArtworkToTemp(String url) async {
    if (!AppConfig.isCloudSyncAllowed) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefsKeys.offlineOnlyMode) == true) return null;
    } catch (_) {}

    if (!RemoteTargetPolicy.isAllowed(url)) return null;

    try {
      final initialUri = Uri.tryParse(url);
      if (initialUri == null ||
          (initialUri.scheme != 'http' && initialUri.scheme != 'https')) {
        return null;
      }
      var currentUri = initialUri;
      final isSafe = await RemoteTargetPolicy.isSafeHost(currentUri.host);
      if (!isSafe) return null;

      http.StreamedResponse? streamed;
      for (var redirectCount = 0; redirectCount <= 3; redirectCount++) {
        final request = http.Request('GET', currentUri)
          ..headers['User-Agent'] = 'Pulsr/${AppConfig.appVersion}'
          ..followRedirects = false;
        final response = await _httpClient
            .send(request)
            .timeout(const Duration(seconds: 12));

        final status = response.statusCode;
        if (status >= 300 &&
            status < 400 &&
            response.headers.containsKey('location')) {
          await response.stream.listen((_) {}, onError: (_) {}).cancel();
          if (redirectCount == 3) return null;
          final location = response.headers['location']!;
          final nextUri = currentUri.resolve(location);
          final nextUrl = nextUri.toString();
          if (!RemoteTargetPolicy.isAllowed(nextUrl)) return null;
          final nextSafe = await RemoteTargetPolicy.isSafeHost(nextUri.host);
          if (!nextSafe) return null;
          currentUri = nextUri;
          continue;
        }

        streamed = response;
        break;
      }

      if (streamed == null) return null;

      final contentLength = streamed.contentLength;
      if (streamed.statusCode != 200 ||
          (contentLength != null && contentLength > _maxArtworkBytes)) {
        await streamed.stream.listen((_) {}, onError: (_) {}).cancel();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      var totalBytes = 0;
      await for (final chunk
          in streamed.stream.timeout(const Duration(seconds: 12))) {
        totalBytes += chunk.length;
        if (totalBytes > _maxArtworkBytes) {
          return null;
        }
        builder.add(chunk);
      }

      final bytes = builder.takeBytes();
      if (bytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final fileName =
            'auto_art_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(bytes);
        return file.path;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to download auto artwork: $url',
          error: e, stackTrace: st, category: 'MetadataSearch');
    }
    return null;
  }
}
