// lib/data/services/ytm_client_version_resolver.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/embedded_browser_ua.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/error_logger.dart';

@singleton
class YtmClientVersionResolver {
  static const String _prefKeyClientVersion = 'ytm_cached_client_version';
  static const String _prefKeyApiKey = 'ytm_cached_api_key';
  static const String _prefKeyLastFetchTime = 'ytm_client_version_fetch_ts';

  static const String fallbackClientVersion = String.fromEnvironment(
    'YTM_CLIENT_VERSION',
    defaultValue: '1.20250820.01.00',
  );
  static const String fallbackApiKey = String.fromEnvironment(
    'YTM_API_KEY',
    defaultValue: 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
  );
  static const Duration _cacheTtl = Duration(hours: 24);
  static const Duration _maxStaleTtl = Duration(days: 30);

  String _clientVersion = fallbackClientVersion;
  String _apiKey = fallbackApiKey;
  bool _isInitialized = false;

  String get clientVersion => _clientVersion;
  String get apiKey => _apiKey;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString(_prefKeyClientVersion);
      final savedKey = prefs.getString(_prefKeyApiKey);
      final lastFetch = prefs.getInt(_prefKeyLastFetchTime) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isStale = (now - lastFetch) > _maxStaleTtl.inMilliseconds;

      if (!isStale && savedVersion != null && savedVersion.isNotEmpty) {
        _clientVersion = savedVersion;
      }
      if (!isStale && savedKey != null && savedKey.isNotEmpty) {
        _apiKey = savedKey;
      }

      _isInitialized = true;

      if (now - lastFetch > _cacheTtl.inMilliseconds || isStale) {
        // Refresh asynchronously in background
        unawaited(refresh());
      }
    } catch (e, st) {
      ErrorLogger.log('Failed initializing YtmClientVersionResolver',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  Future<void> refresh() async {
    var attempt = 0;
    while (attempt < 3) {
      try {
        final response = await http.get(
          Uri.parse('https://music.youtube.com'),
          headers: {
            'User-Agent': EmbeddedBrowserUa.desktop,
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final body = response.body;

          // 1. Extract clientVersion
          final versionMatch =
              RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":\s*"([^"]+)"')
                      .firstMatch(body) ??
                  RegExp(r'"clientVersion":\s*"([^"]+)"').firstMatch(body) ??
                  RegExp(r'"INNERTUBE_CLIENT_VERSION":\s*"([^"]+)"')
                      .firstMatch(body);

          // 2. Extract apiKey
          final apiKeyMatch =
              RegExp(r'"INNERTUBE_API_KEY":\s*"([^"]+)"').firstMatch(body) ??
                  RegExp(r'"innertubeApiKey":\s*"([^"]+)"').firstMatch(body) ??
                  RegExp(r'key=([a-zA-Z0-9_-]{39})').firstMatch(body);

          final prefs = await SharedPreferences.getInstance();
          var updated = false;

          if (versionMatch != null && versionMatch.group(1) != null) {
            final resolvedVersion = versionMatch.group(1)!;
            // Validate format: must look like 1.YYYYMMDD.XX.XX (reject consent-wall junk)
            if (RegExp(r'^1\.\d{8}\.\d{2}\.\d{2}$').hasMatch(resolvedVersion)) {
              _clientVersion = resolvedVersion;
              await prefs.setString(_prefKeyClientVersion, resolvedVersion);
              AppLogger.debug(
                  '[YTM_VERSION] Resolved Innertube clientVersion: $_clientVersion',
                  category: 'YTM');
              updated = true;
            }
          }

          if (apiKeyMatch != null && apiKeyMatch.group(1) != null) {
            final resolvedKey = apiKeyMatch.group(1)!;
            if (RegExp(r'^[a-zA-Z0-9_-]{39}$').hasMatch(resolvedKey)) {
              _apiKey = resolvedKey;
              await prefs.setString(_prefKeyApiKey, resolvedKey);
              AppLogger.debug('[YTM_VERSION] Resolved Innertube apiKey',
                  category: 'YTM');
              updated = true;
            }
          }

          await prefs.setInt(
              _prefKeyLastFetchTime, DateTime.now().millisecondsSinceEpoch);
          if (updated) return;
        } else if (response.statusCode == 429) {
          // Honor Retry-After on version scrape — don't hammer consent wall.
          attempt++;
          final retryAfter = int.tryParse(
              response.headers['retry-after'] ?? '');
          await Future<void>.delayed(Duration(
              seconds: (retryAfter ?? (1 << attempt)).clamp(1, 30)));
          continue;
        }
        return;
      } catch (e, st) {
        attempt++;
        if (attempt >= 3) {
          AppLogger.warning(
              '[YTM_VERSION] Dynamic client version fetch failed (using cached/fallback)',
              error: e,
              stackTrace: st,
              category: 'YTM');
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }
}

