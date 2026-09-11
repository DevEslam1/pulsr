// lib/core/services/xdm_backend_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/ytm_track.dart';
import '../constants/prefs_keys.dart';
import '../utils/ytm_rate_limiter.dart';
import 'ytm_service.dart';

enum BackendCircuitState {
  closed,
  open,
  halfOpen,
}

class BackendHealthInfo {
  final bool ok;
  final String backendVersion;
  final String ytdlpVersion;
  final int proxyPoolSize;
  final int latencyMs;
  final String? message;
  final BackendCircuitState circuitState;

  const BackendHealthInfo({
    required this.ok,
    required this.backendVersion,
    required this.ytdlpVersion,
    required this.proxyPoolSize,
    required this.latencyMs,
    required this.circuitState,
    this.message,
  });
}

/// Service interfacing with the remote yt-dlp microservice (xdm-backend).
///
/// DISABLED: the remote backend is fully decommissioned. This class is kept
/// only so existing DI registrations/tests keep compiling. Every entry point
/// below short-circuits without any network I/O. Do not re-enable.
@lazySingleton
class XdmBackendService {
  /// Global kill-switch. Always true — the backend must never be used.
  static const bool hardDisabled = true;
  static const String defaultBaseUrl =
      'https://xdm-backend-10763667121.europe-west1.run.app';
  static const String _tokenSecureKey = 'xdm_backend_token_secure';
  static const String defaultApiToken =
      String.fromEnvironment('XDM_BACKEND_TOKEN', defaultValue: '');

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  // Circuit Breaker state (retained for API compat; backend disabled)
  int _consecutiveInfraFailures = 0;
  DateTime? _circuitOpenUntil;
  static const int _infraFailureThreshold = 3;
  static const Duration _circuitRecoveryDuration = Duration(minutes: 15);

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

  BackendCircuitState get circuitState {
    if (_circuitOpenUntil == null) return BackendCircuitState.closed;
    if (DateTime.now().isBefore(_circuitOpenUntil!)) {
      return BackendCircuitState.open;
    }
    return BackendCircuitState.halfOpen;
  }

  bool get isCircuitOpen => circuitState == BackendCircuitState.open;
  DateTime? get circuitOpenUntil => _circuitOpenUntil;
  int get consecutiveInfraFailures => _consecutiveInfraFailures;

  void resetCircuitBreaker() {
    _consecutiveInfraFailures = 0;
    _circuitOpenUntil = null;
  }

  void recordInfraFailure() {
    _consecutiveInfraFailures++;
    if (_consecutiveInfraFailures >= _infraFailureThreshold) {
      _circuitOpenUntil = DateTime.now().add(_circuitRecoveryDuration);
      debugPrint(
          '[XDM_BACKEND] Circuit breaker OPEN after $_consecutiveInfraFailures failures. Disabled until $_circuitOpenUntil');
    }
  }

  void recordSuccess() {
    _consecutiveInfraFailures = 0;
    _circuitOpenUntil = null;
    YtmRateLimiter.shared.onBackendSuccess();
  }

  static String _generateRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // RFC 4122 v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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

    // One-time migration from SharedPreferences to FlutterSecureStorage
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
    // DISABLED: remote backend decommissioned — never enabled.
    return false;
  }

  Future<bool> isCookieSyncAllowed() async {
    // DISABLED: never sync cookies to a remote backend.
    return false;
  }

  Map<String, String> _headers(
    String token, {
    String? cookies,
    String? userAgent,
    String? requestId,
  }) =>
      {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'X-Request-Id': requestId ?? _generateRequestId(),
        'X-Client-Version': '2.0.0',
        if (cookies != null && cookies.isNotEmpty) 'X-YouTube-Cookies': cookies,
        if (userAgent != null && userAgent.isNotEmpty)
          'X-User-Agent': userAgent,
      };

  /// Checks server health, returning a typed BackendHealthInfo.
  Future<BackendHealthInfo> checkHealth({bool force = false}) async {
    if (!await isEnabled()) {
      return const BackendHealthInfo(
        ok: false,
        backendVersion: 'disabled',
        ytdlpVersion: 'disabled',
        proxyPoolSize: 0,
        latencyMs: 0,
        circuitState: BackendCircuitState.open,
        message: 'Remote yt-dlp backend is disabled (on-device only).',
      );
    }

    try {
      final baseUrl = await _getBaseUrl();
      final uri = Uri.parse('$baseUrl/health');
      final sw = Stopwatch()..start();
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      sw.stop();

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return BackendHealthInfo(
          ok: data['ok'] == true || data['status'] == 'healthy' || data['status'] == 'ok',
          backendVersion: data['version']?.toString() ?? '1.0.0',
          ytdlpVersion: data['ytdlp_version']?.toString() ?? 'unknown',
          proxyPoolSize: data['proxies_count'] as int? ?? 0,
          latencyMs: sw.elapsedMilliseconds,
          circuitState: BackendCircuitState.closed,
          message: data['message']?.toString() ?? 'Backend online',
        );
      } else {
        return BackendHealthInfo(
          ok: false,
          backendVersion: 'error',
          ytdlpVersion: 'error',
          proxyPoolSize: 0,
          latencyMs: sw.elapsedMilliseconds,
          circuitState: BackendCircuitState.open,
          message: 'HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      return BackendHealthInfo(
        ok: false,
        backendVersion: 'unreachable',
        ytdlpVersion: 'unreachable',
        proxyPoolSize: 0,
        latencyMs: 0,
        circuitState: BackendCircuitState.open,
        message: 'Connection failed: $e',
      );
    }
  }

  /// Resolves an audio stream for [videoId] via the Contract v2 /resolve/audio endpoint.
  Future<YtmStream?> resolveStream(
    String videoId, {
    String quality = 'high',
    String? userAgent,
    String? cookies,
  }) async {
    if (!await isEnabled()) return null;

    try {
      await YtmRateLimiter.shared.acquireBackendPermit();

      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      final syncCookies = await isCookieSyncAllowed();
      final effectiveCookies = syncCookies ? cookies : null;

      final uri = Uri.parse('$baseUrl/resolve/audio')
          .replace(queryParameters: {'videoId': videoId});

      final response = await _client
          .get(uri,
              headers: _headers(token,
                  cookies: effectiveCookies, userAgent: userAgent))
          .timeout(const Duration(seconds: 12));

      // Handle responses
      if (response.statusCode == 200) {
        recordSuccess();
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final audioLadder = data['audio'] as List<dynamic>? ?? [];
        if (audioLadder.isEmpty) return null;

        return _selectBestAudioFromLadder(
          videoId,
          data['title'] as String? ?? 'Unknown Track',
          data['author'] as String? ?? '',
          audioLadder.cast<Map<String, dynamic>>(),
          quality,
        );
      }

      // Handle Contract v2 structured error bodies
      _handleBackendErrorResponse(response);
      return null;
    } on SocketException catch (e) {
      debugPrint('[XDM_BACKEND] SocketException: $e');
      recordInfraFailure();
      return null;
    } on TimeoutException catch (e) {
      debugPrint('[XDM_BACKEND] TimeoutException: $e');
      recordInfraFailure();
      return null;
    } on http.ClientException catch (e) {
      debugPrint('[XDM_BACKEND] ClientException: $e');
      recordInfraFailure();
      return null;
    } catch (e) {
      if (e is YtmException) rethrow;
      debugPrint('[XDM_BACKEND] resolveStream failed for $videoId: $e');
      return null;
    }
  }

  void _handleBackendErrorResponse(http.Response response) {
    String errorCode = 'EXTRACTOR_ERROR';
    String message = response.body;

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      errorCode = json['error_code'] as String? ?? errorCode;
      message = json['message'] as String? ?? message;
    } catch (_) {}

    // Infra 5xx status codes trip circuit breaker
    if (response.statusCode >= 500) {
      recordInfraFailure();
      return;
    }

    // Rate limited / platform bot detection
    if (response.statusCode == 429 || errorCode == 'RATE_LIMITED' || errorCode == 'BOT_CHECK') {
      final retryHeader = response.headers['retry-after'];
      final retryAfter = int.tryParse(retryHeader ?? '') ?? 60;
      // Only the backend bucket. The backend's quota — and its cookie pool's
      // BOT_CHECK — say nothing about how YouTube sees *this device*: it is a
      // different IP entirely. Freezing the native path here made the fallback
      // take the primary down with it, which is what "everything is blocked"
      // looked like, and an uncapped `Retry-After` froze it for hours.
      YtmRateLimiter.shared.onBackendRateLimited(retryAfter);
      throw YtmException(errorCode, message);
    }

    if (errorCode == 'GEO_BLOCKED' ||
        errorCode == 'AGE_RESTRICTED' ||
        errorCode == 'FORBIDDEN' ||
        errorCode == 'CONTENT_GONE') {
      throw YtmException(errorCode, message);
    }
  }

  YtmStream? _selectBestAudioFromLadder(
    String videoId,
    String title,
    String artist,
    List<Map<String, dynamic>> audioList,
    String quality,
  ) {
    if (audioList.isEmpty) return null;

    int getAbr(Map<String, dynamic> item) {
      final abr = item['abr'];
      if (abr is num) return abr.toInt();
      final q = (item['quality'] as String? ?? '').replaceAll('kbps', '').trim();
      return int.tryParse(q) ?? 0;
    }

    // Prefer AAC / m4a streams for compatibility & taggability
    final aacStreams = audioList.where((s) {
      final ext = (s['ext'] as String? ?? '').toLowerCase();
      final codec = (s['codec'] as String? ?? '').toLowerCase();
      final formatId = (s['format_id'] as String? ?? '').toLowerCase();
      return ext == 'm4a' ||
          ext == 'aac' ||
          ext == 'mp4' ||
          codec.contains('mp4a') ||
          codec.contains('aac') ||
          formatId == '140' ||
          formatId == '141' ||
          formatId == '139';
    }).toList();

    final pool = aacStreams.isNotEmpty ? aacStreams : audioList;
    pool.sort((a, b) => getAbr(b).compareTo(getAbr(a)));

    Map<String, dynamic> selected;
    final qLower = quality.toLowerCase();
    if (qLower == 'low') {
      selected = pool.last;
    } else if (qLower == 'medium') {
      selected = pool.reduce((curr, next) {
        final currDiff = (getAbr(curr) - 128).abs();
        final nextDiff = (getAbr(next) - 128).abs();
        return nextDiff < currDiff ? next : curr;
      });
    } else {
      selected = pool.first;
    }

    final streamUrl = selected['src'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) return null;

    final ext = (selected['ext'] as String? ?? 'm4a').toLowerCase();
    final bitrate = getAbr(selected);
    final expiresAt = (selected['expiresAt'] as num?)?.toInt();

    return YtmStream(
      videoId: videoId,
      url: streamUrl,
      mimeType: ext == 'm4a' || ext == 'mp4' || ext == 'aac'
          ? 'audio/mp4'
          : 'audio/webm',
      container: ext,
      bitrateKbps: bitrate > 0 ? bitrate : 160,
      duration: Duration.zero,
      title: title.isNotEmpty ? title : 'Unknown Track',
      artist: artist,
      artworkUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      expiresAt: expiresAt,
      // The backend may omit `expiresAt` entirely, and when it does send one the
      // unit is not guaranteed to be millis. Left as-is, an absent stamp made
      // every consumer treat the URL as immortal, and a seconds-valued one made
      // it born expired — which the URL cache answers by refusing to store it.
    ).withResolvedExpiry();
  }

  /// Extracts playlist tracks from [playlistUrl] via the yt-dlp backend.
  Future<List<YtmTrack>> getPlaylist(
    String playlistUrl, {
    int limit = 100,
    String? cookies,
  }) async {
    if (!await isEnabled()) return const [];

    try {
      await YtmRateLimiter.shared.acquireBackendPermit();
      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      final syncCookies = await isCookieSyncAllowed();
      final effectiveCookies = syncCookies ? cookies : null;

      final uri = Uri.parse('$baseUrl/api/playlist')
          .replace(queryParameters: {'url': playlistUrl});

      final response = await _client
          .get(uri, headers: _headers(token, cookies: effectiveCookies))
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        _handleBackendErrorResponse(response);
        return const [];
      }

      recordSuccess();
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
      if (e is SocketException || e is TimeoutException) {
        recordInfraFailure();
      }
      debugPrint('[XDM_BACKEND] getPlaylist failed: $e');
      return const [];
    }
  }

  /// Searches tracks via the yt-dlp backend.
  Future<List<YtmTrack>> search(String query, {int limit = 30}) async {
    if (!await isEnabled()) return const [];

    try {
      await YtmRateLimiter.shared.acquireBackendPermit();
      final baseUrl = await _getBaseUrl();
      final token = await _getApiToken();
      final uri = Uri.parse('$baseUrl/api/search')
          .replace(queryParameters: {'q': query});

      final response = await _client
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _handleBackendErrorResponse(response);
        return const [];
      }

      recordSuccess();
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
      if (e is SocketException || e is TimeoutException) {
        recordInfraFailure();
      }
      debugPrint('[XDM_BACKEND] search failed: $e');
      return const [];
    }
  }
}
