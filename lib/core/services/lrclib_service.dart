// lib/core/services/lrclib_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:injectable/injectable.dart';
import '../../domain/models/lyrics_line.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';

@singleton
class LrclibService {
  final HttpClient _client;

  LrclibService({HttpClient? client}) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  Future<LyricsResult?> fetchLyrics({
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
      request.headers.set(HttpHeaders.userAgentHeader, 'PulsrMusic/1.0.0 (offline music player)');
      final response = await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        final syncedLyrics = json['syncedLyrics'] as String?;
        final plainLyrics = json['plainLyrics'] as String?;

        if (syncedLyrics != null && syncedLyrics.trim().isNotEmpty) {
          final lines = LrcParser.parse(syncedLyrics, source: LyricsSource.lrclib);
          if (lines.isNotEmpty) {
            return LyricsResult(lines: lines, source: LyricsSource.lrclib);
          }
        }

        if (plainLyrics != null && plainLyrics.trim().isNotEmpty) {
          final lines = LrcParser.parsePlainText(plainLyrics, source: LyricsSource.lrclib);
          if (lines.isNotEmpty) {
            return LyricsResult(lines: lines, source: LyricsSource.lrclib);
          }
        }
      }
    } catch (e) {
      ErrorLogger.log('LRCLIB fetch skipped or offline: $e', category: 'LRCLIB');
    }
    return null;
  }
}
