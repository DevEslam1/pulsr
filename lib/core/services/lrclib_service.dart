// lib/core/services/lrclib_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import '../../domain/models/lyrics_line.dart';
import '../config/app_config.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';

@singleton
class LrclibService {
  final HttpClient _client;

  LrclibService({HttpClient? client})
      : _client = client ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  void dispose() {
    _client.close(force: false);
  }

  Future<LyricsResult?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    // 1. Clean track & artist name (strip (Official Video), [MV], (feat. ...), etc.)
    final cleanTrack = _cleanTitle(trackName, artistName: artistName);
    final cleanArtist = _cleanArtist(artistName);

    final effectiveTrack = cleanTrack.isNotEmpty ? cleanTrack : trackName;
    final effectiveArtist = cleanArtist.isNotEmpty ? cleanArtist : artistName;

    // 1. Try exact get with all metadata (album, duration)
    var result = await _tryGetLyrics(
      trackName: effectiveTrack,
      artistName: effectiveArtist,
      albumName: albumName,
      durationSeconds: durationSeconds,
    );

    if (result != null && result.lines.isNotEmpty) return result;

    // 2. If exact get with album/duration failed, try without strict album/duration
    if (albumName != null || durationSeconds != null) {
      result = await _tryGetLyrics(
        trackName: effectiveTrack,
        artistName: effectiveArtist,
      );
      if (result != null && result.lines.isNotEmpty) return result;
    }

    // 3. Fallback to fuzzy search on LRCLIB with clean query
    final searchTerms = <String>[effectiveTrack];
    if (effectiveArtist.isNotEmpty &&
        !effectiveTrack.toLowerCase().contains(effectiveArtist.toLowerCase())) {
      searchTerms.add(effectiveArtist);
    }
    result = await _trySearchLyrics(query: searchTerms.join(' '));
    if (result != null && result.lines.isNotEmpty) return result;

    // 4. If cleanTrack differed from raw trackName, try raw search as last resort
    if (effectiveTrack != trackName) {
      result = await _trySearchLyrics(query: '$trackName $effectiveArtist');
      if (result != null && result.lines.isNotEmpty) return result;
    }

    return null;
  }

  String _cleanTitle(String title, {String? artistName}) {
    var cleaned = title;

    // Split on common dividers like |, /, •, ~
    if (cleaned.contains(RegExp(r'\s*[|/•~]\s*'))) {
      cleaned = cleaned.split(RegExp(r'\s*[|/•~]\s*')).first;
    }

    // Strip common YouTube / release clutter inside brackets/parentheses
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*[\(\[\{].*?(official|video|audio|mv|lyrics|lyric|remix|version|hq|hd|explicit|clean|visualizer|clip|حفل|كليب|فيديو|موسيقى|جلسة|لايف|بث|مهرجان).*?[\)\]\}]',
        caseSensitive: false,
      ),
      '',
    );

    // Strip trailing "- Official Video", etc.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\s*-\s*(official|video|audio|mv|lyrics|lyric|remix|version|visualizer|clip|فيديو|كليب|حفل).*',
        caseSensitive: false,
      ),
      '',
    );

    // Strip leading "Artist - " or "Artist – " if artist is provided or title contains " - "
    if (artistName != null && artistName.trim().isNotEmpty) {
      final escapedArtist = RegExp.escape(artistName.trim());
      cleaned = cleaned.replaceAll(
        RegExp('^\\s*$escapedArtist\\s*[-–—:]\\s*', caseSensitive: false),
        '',
      );
      // Also check if artist is at the end: "Title - Artist"
      cleaned = cleaned.replaceAll(
        RegExp('\\s*[-–—:]\\s*$escapedArtist\\s*\$', caseSensitive: false),
        '',
      );
    }

    // Strip common YouTube "feat." or "ft." in brackets or standalone
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*[\(\[\{]?\s*(feat\.|ft\.|with)\s+.*?[\)\]\}]?', caseSensitive: false),
      '',
    );

    // Strip remaining generic Arabic video labels
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(فيديو كليب|حفل|مهرجان|جلسة|سهرة).*', caseSensitive: false),
      '',
    );

    return cleaned.trim();
  }

  String _cleanArtist(String artist) {
    return artist
        .replaceAll(
          RegExp(r'\s*[\(\[\{].*?(topic|vevo).*?[\)\]\}]', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*Vevo', caseSensitive: false), '')
        .trim();
  }

  Future<LyricsResult?> _tryGetLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    try {
      final queryParams = <String, String>{
        'track_name': trackName,
        'artist_name': artistName,
      };
      if (albumName != null && albumName.isNotEmpty) {
        queryParams['album_name'] = albumName;
      }
      if (durationSeconds != null && durationSeconds > 0) {
        queryParams['duration'] = durationSeconds.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', queryParams);
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader,
          'PulsrMusic/${AppConfig.appVersion} (music player)');
      final response =
          await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return _extractLyricsFromJson(json);
      }
    } catch (e) {
      ErrorLogger.log('LRCLIB get query skipped: $e', category: 'LRCLIB');
    }
    return null;
  }

  Future<LyricsResult?> _trySearchLyrics({required String query}) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {'q': query});
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader,
          'PulsrMusic/${AppConfig.appVersion} (music player)');
      final response =
          await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final list = jsonDecode(responseBody);
        if (list is List && list.isNotEmpty) {
          // Pass 1: Prioritize synced lyrics
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final synced = item['syncedLyrics'] as String?;
              if (synced != null && synced.trim().isNotEmpty) {
                final res = _extractLyricsFromJson(item);
                if (res != null && res.lines.isNotEmpty) return res;
              }
            }
          }
          // Pass 2: Fallback to plain lyrics
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final res = _extractLyricsFromJson(item);
              if (res != null && res.lines.isNotEmpty) return res;
            }
          }
        }
      }
    } catch (e) {
      ErrorLogger.log('LRCLIB search query skipped: $e', category: 'LRCLIB');
    }
    return null;
  }

  LyricsResult? _extractLyricsFromJson(Map<String, dynamic> json) {
    final syncedLyrics = json['syncedLyrics'] as String?;
    final plainLyrics = json['plainLyrics'] as String?;

    if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
      final lines = LrcParser.parse(syncedLyrics, source: LyricsSource.lrclib);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.lrclib);
      }
    }

    if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
      final lines =
          LrcParser.parsePlainText(plainLyrics, source: LyricsSource.lrclib);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.lrclib);
      }
    }
    return null;
  }
}
