// lib/core/services/xdm_backend_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/ytm_track.dart';
import '../constants/prefs_keys.dart';
import 'ytm_service.dart';

/// Service interfacing with the remote yt-dlp microservice (xdm-backend).
///
/// Features:
/// - Audio stream resolution with multi-format fallback (m4a, webm/opus).
/// - YouTube playlist extraction.
/// - YouTube search fallback.
/// - Live server health checking.
@lazySingleton
class XdmBackendService {
  static const String defaultBaseUrl =
      'https://xdm-backend-10763667121.europe-west1.run.app';
  static const String _tokenSecureKey = 'xdm_backend_token_secure';
  static const String defaultApiToken =
      String.fromEnvironment('XDM_BACKEND_TOKEN', defaultValue: '');

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  @factoryMethod
  XdmBackendService({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  })  : _client = http.Client(),
        _secureStorage = secureStorage;

  @visibleForTesting
  XdmBackendService.withClient(
    http.Client client, {
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  })  : _client = client,
        _secureStorage = secureStorage;

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(PrefsKeys.ytdlpBackendUrl)?.trim();
    if (url != null && url.isNotEmpty) {
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
    return defaultBaseUrl;
  }

  Future<String> _getApiToken() async {
    try {
      final secureToken = await _secureStorage.read(key: _tokenSecureKey);
      if (secureToken != null && secureToken.isNotEmpty) return secureToken;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final prefsToken = prefs.getString(PrefsKeys.ytdlpBackendToken)?.trim();
    if (prefsToken != null && prefsToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _tokenSecureKey, value: prefsToken);
        await prefs.remove(PrefsKeys.ytdlpBackendToken);
      } catch (_) {}
      return prefsToken;
    }

    return const String.fromEnvironment('XDM_BACKEND_TOKEN', defaultValue: '');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final engineStr = prefs.getString(PrefsKeys.extractorEngine);
    if (engineStr == 'onDevice') return false;
    return prefs.getBool(PrefsKeys.ytdlpBackendEnabled) ?? true;
  }

  Map<String, String> _headers(String token,
          {String? cookies, String? userAgent}) =>
      {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (cookies != null && cookies.isNotEmpty) 'X-YouTube-Cookies': cookies,
        if (userAgent != null && userAgent.isNotEmpty)
          'X-User-Agent': userAgent,
      };

  /// Checks server health, returning a map with version, proxy count, and latency in ms.
  Future<
      ({
        bool ok,
        String ytdlpVersion,
        int proxyPoolSize,
        int latencyMs,
        String? message
      })> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/health');
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final version = data['ytdlp'] as String? ?? 'unknown';
        final proxies = (data['proxy_pool_size'] as num?)?.toInt() ?? 0;
        return (
          ok: true,
          ytdlpVersion: version,
          proxyPoolSize: proxies,
          latencyMs: stopwatch.elapsedMilliseconds,
          message: 'Connected (yt-dlp v$version, $proxies proxies)',
        );
      }
      return (
        ok: false,
        ytdlpVersion: 'unknown',
        proxyPoolSize: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: 'Server returned HTTP ${response.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();
      return (
        ok: false,
        ytdlpVersion: 'unknown',
        proxyPoolSize: 0,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: 'Connection failed: $e',
      );
    }
  }

  /// Resolves an audio stream for [videoId] via the yt-dlp backend.
  Future<YtmStream?> resolveStream(String videoId,
      {String quality = 'high'}) async {
    if (!await isEnabled()) return null;

    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      // Target YouTube Music URL specifically
      final videoUrl = 'https://music.youtube.com/watch?v=$videoId';
      final uri = Uri.parse('$baseUrl/api/streams')
          .replace(queryParameters: {'url': videoUrl});

      final response = await _client
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        if (response.statusCode == 400 && response.body.contains('407')) {
          throw const YtmException('YTM_PROXY_AUTH',
              'XDM Backend proxy authentication failed (407)');
        }
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawStreams = data['streams'] as List<dynamic>? ?? [];
      if (rawStreams.isEmpty) return null;

      final audioStreams = rawStreams
          .where((s) => s is Map && s['type'] == 'audio')
          .cast<Map<String, dynamic>>()
          .toList();
      if (audioStreams.isEmpty) return null;

      // Extract bitrates
      int getBitrate(Map<String, dynamic> s) {
        final q = (s['quality'] as String? ?? '').replaceAll('kbps', '').trim();
        return int.tryParse(q) ?? 0;
      }

      // Filter for AAC (m4a / aac) audio streams
      final aacStreams = audioStreams.where((s) {
        final ext = (s['ext'] as String? ?? '').toLowerCase();
        final formatId = (s['format_id'] as String? ?? '').toLowerCase();
        final label = (s['label'] as String? ?? '').toLowerCase();
        return ext == 'm4a' ||
            ext == 'aac' ||
            ext == 'mp4' ||
            label.contains('m4a') ||
            label.contains('aac') ||
            formatId == '140' ||
            formatId == '141' ||
            formatId == '139';
      }).toList();

      // Use AAC streams if available, otherwise fall back to all audio streams
      final pool = aacStreams.isNotEmpty ? aacStreams : audioStreams;

      // Sort by bitrate descending (e.g. 256kbps -> 160kbps -> 128kbps -> 48kbps)
      pool.sort((a, b) => getBitrate(b).compareTo(getBitrate(a)));

      // Quality preference filtering targeting AAC
      Map<String, dynamic> selected;
      final qLower = quality.toLowerCase();
      if (qLower == 'low') {
        // Lowest bitrate AAC (e.g. 48kbps - itag 139)
        selected = pool.last;
      } else if (qLower == 'medium') {
        // Medium quality AAC: target closest to 128kbps (e.g. 128-140kbps - itag 140)
        selected = pool.reduce((curr, next) {
          final currDiff = (getBitrate(curr) - 128).abs();
          final nextDiff = (getBitrate(next) - 128).abs();
          return nextDiff < currDiff ? next : curr;
        });
      } else {
        // High quality AAC: highest bitrate available (e.g. 256kbps / 160kbps / 140kbps)
        selected = pool.first;
      }

      final streamUrl = selected['src'] as String?;
      if (streamUrl == null || streamUrl.isEmpty) return null;

      final ext = (selected['ext'] as String? ?? 'm4a').toLowerCase();
      final bitrate = getBitrate(selected);
      final title = (data['title'] as String?) ?? 'Unknown Track';

      return YtmStream(
        videoId: videoId,
        url: streamUrl,
        mimeType: ext == 'm4a' || ext == 'mp4' || ext == 'aac'
            ? 'audio/mp4'
            : 'audio/webm',
        container: ext,
        bitrateKbps: bitrate > 0 ? bitrate : 160,
        duration: Duration.zero,
        title: title,
        artist: '',
        artworkUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      );
    } catch (e) {
      debugPrint('[XDM_BACKEND] resolveStream failed for $videoId: $e');
      return null;
    }
  }

  /// Extracts playlist tracks from [playlistUrl] via the yt-dlp backend.
  Future<List<YtmTrack>> getPlaylist(String playlistUrl,
      {int limit = 100, String? cookies}) async {
    if (!await isEnabled()) return const [];

    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      final uri = Uri.parse('$baseUrl/api/playlist')
          .replace(queryParameters: {'url': playlistUrl});

      final response = await _client
          .get(uri, headers: _headers(token, cookies: cookies))
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        return const [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawVideos = data['videos'] as List<dynamic>? ?? [];

      final tracks = <YtmTrack>[];
      for (final v in rawVideos) {
        if (v is! Map<String, dynamic>) continue;
        final id = v['id'] as String?;
        final title = v['title'] as String?;
        if (id == null || id.isEmpty || title == null || title.isEmpty) {
          continue;
        }

        final author = (v['author'] as String?)?.trim() ?? 'Unknown Artist';
        final durationSec = (v['duration'] as num?)?.toInt() ?? 0;
        final thumb = (v['thumbnailUrl'] as String?) ??
            'https://i.ytimg.com/vi/$id/hqdefault.jpg';

        tracks.add(YtmTrack(
          videoId: id,
          title: title,
          artist: author.isNotEmpty ? author : 'Unknown Artist',
          duration: Duration(seconds: durationSec),
          artworkUrl: thumb,
        ));
      }

      return tracks.take(limit).toList();
    } catch (e) {
      debugPrint('[XDM_BACKEND] getPlaylist failed: $e');
      return const [];
    }
  }

  /// Searches tracks via the yt-dlp backend.
  Future<List<YtmTrack>> search(String query, {int limit = 30}) async {
    if (!await isEnabled()) return const [];

    try {
      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      final uri = Uri.parse('$baseUrl/api/search')
          .replace(queryParameters: {'q': query});

      final response = await _client
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawResults = data['results'] as List<dynamic>? ?? [];

      final tracks = <YtmTrack>[];
      for (final r in rawResults) {
        if (r is! Map<String, dynamic>) continue;
        final id = r['id'] as String?;
        final title = r['title'] as String?;
        if (id == null || id.isEmpty || title == null || title.isEmpty) {
          continue;
        }

        final author = (r['author'] as String?)?.trim() ?? 'Unknown Artist';
        final durationSec = (r['duration'] as num?)?.toInt() ?? 0;
        final thumb = (r['thumbnailUrl'] as String?) ??
            'https://i.ytimg.com/vi/$id/hqdefault.jpg';

        tracks.add(YtmTrack(
          videoId: id,
          title: title,
          artist: author.isNotEmpty ? author : 'Unknown Artist',
          duration: Duration(seconds: durationSec),
          artworkUrl: thumb,
        ));
      }

      return tracks.take(limit).toList();
    } catch (e) {
      debugPrint('[XDM_BACKEND] search failed: $e');
      return const [];
    }
  }
}
