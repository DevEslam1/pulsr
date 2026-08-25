// lib/core/services/ytm_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../di/injection.dart';
import 'ytm_account_service.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';

/// A failed YTM call.
class YtmException implements Exception {
  final String code;
  final String? details;

  const YtmException(this.code, [this.details]);

  /// Retrying later may work; retrying the rest of the queue now will not.
  bool get isNetwork => code == 'YTM_NETWORK' || code == 'YTM_TIMEOUT';

  /// YouTube has flagged the IP / client as automated/bot and requires authentication.
  bool get isBotBlocked =>
      code == 'YTM_BOT_BLOCKED' ||
      code == 'YTM_RECAPTCHA' ||
      (details != null &&
          (details!.contains('bot') ||
              details!.contains('LOGIN_REQUIRED') ||
              details!.contains('Sign in to confirm')));

  /// Session has expired or authentication is invalid.
  bool get isAuth =>
      code == 'YTM_AUTH' ||
      code == 'LOGIN_REQUIRED' ||
      (details != null && details!.toLowerCase().contains('unauthenticated'));

  /// Fatal error where looping / skipping the queue will only worsen the block.
  bool get isFatal => isNetwork || isDisabled || isBotBlocked || isAuth;

  /// This one video cannot be played, but others still can.
  bool get isUnavailable => code == 'YTM_UNAVAILABLE';

  /// The build has no extractor compiled in.
  bool get isDisabled => code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED';

  @override
  String toString() => 'YtmException($code${details == null ? '' : ': $details'})';
}

@singleton
class YtmService {
  static const String channelName = 'com.pulsr.music/ytm';
  static const Duration _defaultSearchTimeout = Duration(seconds: 15);
  static const Duration _defaultResolveTimeout = Duration(seconds: 20);

  final MethodChannel _channel = const MethodChannel(channelName);
  final StreamController<void> _authExpiredController = StreamController<void>.broadcast();

  bool? _available;

  Stream<void> get onAuthExpired => _authExpiredController.stream;

  void notifyAuthExpired() {
    _authExpiredController.add(null);
  }

  /// Synchronizes cookies into the native CookieManager so the extractor
  /// makes authenticated requests on all YouTube endpoints.
  Future<void> syncCookies(String cookies) async {
    try {
      await _channel.invokeMethod<bool>('setCookies', {'cookies': cookies});
    } catch (_) {}
  }

  /// Calls native PoTokenManager to ensure attestation tokens are ready.
  Future<bool> ensurePoTokenReady() async {
    try {
      final ready = await _channel.invokeMethod<bool>('ensurePoTokenReady');
      return ready ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Invalidates BotGuard poToken state on bot-detection block or session logout.
  Future<void> invalidatePoToken() async {
    try {
      await _channel.invokeMethod<bool>('invalidatePoToken');
    } catch (_) {}
  }

  /// Retrieves state of PoTokenManager.
  Future<Map<String, dynamic>?> getPoTokenState() async {
    try {
      final state = await _channel.invokeMethod<Map<Object?, Object?>>('getPoTokenState');
      if (state == null) return null;
      return state.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _localeArgs() {
    final locale = ui.PlatformDispatcher.instance.locale;
    final country = locale.countryCode;
    final lang = locale.languageCode;
    return {
      if (country != null && country.isNotEmpty) 'country': country,
      if (lang.isNotEmpty) 'lang': lang,
    };
  }

  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isAvailable'),
        timeout: const Duration(seconds: 5),
      );
      return _available = value ?? false;
    } on YtmException {
      return _available = false;
    }
  }

  Future<bool> isWifiConnected() async {
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isWifiConnected'),
        timeout: const Duration(seconds: 3),
      );
      return value ?? true;
    } on YtmException {
      return true;
    }
  }

  Future<List<YtmTrack>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final raw = await _guard(
      () => _channel.invokeMethod<List<Object?>>('search', {
        'query': trimmed,
        'limit': limit,
        ..._localeArgs(),
      }),
      timeout: _defaultSearchTimeout,
    );

    return _parseTracks(raw);
  }

  /// Search with fallback: First tries native extractor, then falls back to
  /// Innertube search if the extractor returns empty or throws.
  Future<List<YtmTrack>> searchWithFallback(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Try native extractor search
    try {
      final results = await search(trimmed, limit: limit);
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native search failed, trying Innertube fallback: $e');
    }

    // 2. Fallback: Innertube search
    try {
      final innertubeResults = await _searchInnertube(trimmed, limit: limit);
      if (innertubeResults.isNotEmpty) return innertubeResults;
    } catch (e) {
      debugPrint('[YTM_SERVICE] Innertube fallback search failed: $e');
    }

    return const [];
  }

  Future<List<YtmTrack>> _searchInnertube(String query, {int limit = 30}) async {
    try {
      const apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250820.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': query,
      });

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
        'x-origin': 'https://music.youtube.com',
        'x-goog-authuser': '0',
      };

      if (getIt.isRegistered<YtmAccountService>()) {
        final account = getIt<YtmAccountService>();
        if (account.isLoggedIn) {
          final cookies = account.cookies;
          if (cookies != null && cookies.isNotEmpty) {
            headers['Cookie'] = cookies;
            final sapisid = _extractCookieValue(cookies, 'SAPISID') ??
                _extractCookieValue(cookies, '__Secure-3PAPISID') ??
                _extractCookieValue(cookies, '__Secure-1PAPISID');
            if (sapisid != null && sapisid.isNotEmpty) {
              final timestamp =
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
              final toHash = '$timestamp $sapisid https://music.youtube.com';
              final sha1Digest = sha1.convert(utf8.encode(toHash)).toString();
              headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Digest';
            }
          }
        }
      }

      await YtmRateLimiter.shared.acquirePermit();
      final response = await http
          .post(
            Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false&key=$apiKey'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final tracks = <YtmTrack>[];

        void traverse(dynamic node) {
          if (node is Map<String, dynamic>) {
            if (node.containsKey('musicResponsiveListItemRenderer')) {
              final r = node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
              final flexCols = r['flexColumns'] as List<dynamic>? ?? [];
              String? videoId;
              String title = 'Unknown Title';
              String artist = 'Unknown Artist';

              final pData = r['playlistItemData'] as Map<String, dynamic>?;
              videoId = pData?['videoId'] as String?;

              if (flexCols.isNotEmpty) {
                final c0 = flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                if (c0 != null && c0.isNotEmpty) {
                  title = c0[0]['text'] as String? ?? title;
                  final nav = c0[0]['navigationEndpoint'] as Map<String, dynamic>?;
                  videoId ??= nav?['watchEndpoint']?['videoId'] as String?;
                }
              }
              if (flexCols.length > 1) {
                final c1 = flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'] as List<dynamic>?;
                if (c1 != null && c1.isNotEmpty) {
                  artist = c1[0]['text'] as String? ?? artist;
                }
              }

              if (videoId != null && videoId.length == 11) {
                tracks.add(YtmTrack(
                  videoId: videoId,
                  title: title,
                  artist: artist,
                  duration: Duration.zero,
                ));
              }
              return;
            }
            for (final val in node.values) {
              traverse(val);
            }
          } else if (node is List) {
            for (final item in node) {
              traverse(item);
            }
          }
        }

        traverse(json);
        return tracks.take(limit).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<YtmTrack>> trending({int limit = 30}) async {
    final raw = await _guard(
      () => _channel.invokeMethod<List<Object?>>('trending', {
        'limit': limit,
        ..._localeArgs(),
      }),
      timeout: _defaultSearchTimeout,
    );

    return _parseTracks(raw);
  }

  Future<List<YtmTrack>> getPlaylistTracks(String urlOrId, {int limit = 100}) async {
    final raw = await _guard(
      () => _channel.invokeMethod<Map<Object?, Object?>>('getPlaylist', {
        'url': urlOrId.trim(),
        'limit': limit,
      }),
      timeout: const Duration(seconds: 40),
    );

    if (raw == null) return const [];
    final rawTracks = raw['tracks'] as List<Object?>?;
    return _parseTracks(rawTracks);
  }

  List<YtmTrack> _parseTracks(List<Object?>? raw) {
    if (raw == null) return const [];
    final tracks = <YtmTrack>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final track = YtmTrack.fromChannel(entry);
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  /// Resolves audio stream using multi-tier fallback:
  /// (a) Direct authenticated account stream -> (b) Native multi-client extractor
  Future<YtmStream> resolveStream(String videoId, {String quality = 'high'}) async {
    // 1. Try direct authenticated YouTube Music InnerTube Player API if logged in
    try {
      if (getIt.isRegistered<YtmAccountService>()) {
        final account = getIt<YtmAccountService>();
        if (account.isLoggedIn) {
          final directStream = await account.resolvePlayerStream(videoId, quality: quality);
          if (directStream != null) {
            return directStream;
          }
        }
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Direct account stream resolution fallback: $e');
    }

    // 2. Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
    final raw = await _guard(
      () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
        'videoId': videoId,
        'quality': quality,
      }),
      timeout: _defaultResolveTimeout,
    );

    final stream = raw == null ? null : YtmStream.fromChannel(raw);
    if (stream == null) {
      throw const YtmException('YTM_FAILED', 'No stream returned');
    }
    return stream;
  }

  Future<T?> _guard<T>(
    Future<T?> Function() call, {
    required Duration timeout,
    int maxRetries = 2,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final adaptiveTimeout = timeout + Duration(seconds: attempt * 5);
        return await call().timeout(adaptiveTimeout);
      } on TimeoutException {
        if (attempt == maxRetries) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
      } on MissingPluginException {
        throw const YtmException('YTM_UNSUPPORTED');
      } on PlatformException catch (e) {
        if (attempt == maxRetries || e.code == 'YTM_DISABLED' || e.code == 'YTM_UNSUPPORTED') {
          ErrorLogger.log('YTM call failed: ${e.code} ${e.message}', category: 'YTM');
          if (e.code == 'LOGIN_REQUIRED' || e.code == 'YTM_AUTH') {
            notifyAuthExpired();
          }
          throw YtmException(e.code, e.message);
        }
        // If bot blocked, invalidate poToken before retrying
        if (e.code == 'YTM_BOT_BLOCKED' || e.code == 'YTM_RECAPTCHA') {
          await invalidatePoToken();
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
        }
      }
    }
    throw const YtmException('YTM_FAILED', 'Max retries exhausted');
  }

  static String? _extractCookieValue(String cookieString, String key) {
    for (final pair in cookieString.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2 && parts[0].trim() == key) {
        return parts.sublist(1).join('=').trim();
      }
    }
    return null;
  }
}
