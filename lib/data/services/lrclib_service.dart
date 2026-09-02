// lib/data/services/lrclib_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import '../../domain/models/lyrics_line.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/lrc_parser.dart';

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
    final cleanTrack = _cleanTitle(trackName);
    final cleanArtist = _cleanArtist(artistName);

    // Try exact get first
    var result = await _tryGetLyrics(
      trackName: cleanTrack.isNotEmpty ? cleanTrack : trackName,
      artistName: cleanArtist.isNotEmpty ? cleanArtist : artistName,
      albumName: albumName,
      durationSeconds: durationSeconds,
    );

    if (result != null && result.lines.isNotEmpty) return result;

    // Fallback to fuzzy search on LRCLIB
    result = await _trySearchLyrics(
      query:
          '${cleanTrack.isNotEmpty ? cleanTrack : trackName} ${cleanArtist.isNotEmpty ? cleanArtist : artistName}',
    );

    return result;
  }

  String _cleanTitle(String title) {
    var cleaned = title;
    if (cleaned.contains('|')) {
      cleaned = cleaned.split('|').first;
    }
    cleaned = cleaned
        .replaceAll(
            RegExp(
                r'\s*[\(\[\{].*?(official|video|audio|mv|lyrics|feat|ft\.|remix|version|hq|hd|حفل|كليب|فيديو|موسيقى|جلسة|لايف|بث).*?[\)\]\}]',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s*-\s*(official|video|audio|mv|lyrics|فيديو|كليب|حفل).*',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\s*(حفل|مهرجان|جلسة|فيديو كليب).*', caseSensitive: false),
            '')
        .trim();
    return cleaned;
  }

  String _cleanArtist(String artist) {
    return artist
        .replaceAll(
            RegExp(r'\s*[\(\[\{].*?(topic|vevo).*?[\)\]\}]',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s*-\s*Topic', caseSensitive: false), '')
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

