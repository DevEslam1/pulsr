// lib/core/services/ytm_client_version_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_logger.dart';

@singleton
class YtmClientVersionResolver {
  static const String _prefKeyClientVersion = 'ytm_cached_client_version';
  static const String _prefKeyApiKey = 'ytm_cached_api_key';
  static const String _prefKeyLastFetchTime = 'ytm_client_version_fetch_ts';

  static const String fallbackClientVersion = '1.20240417.01.00';
  static const String fallbackApiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const Duration _cacheTtl = Duration(hours: 24);

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

      if (savedVersion != null && savedVersion.isNotEmpty) {
        _clientVersion = savedVersion;
      }
      if (savedKey != null && savedKey.isNotEmpty) {
        _apiKey = savedKey;
      }

      _isInitialized = true;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastFetch > _cacheTtl.inMilliseconds) {
        // Refresh asynchronously in background
        unawaited(refresh());
      }
    } catch (e, st) {
      ErrorLogger.log('Failed initializing YtmClientVersionResolver',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  Future<void> refresh() async {
    try {
      final response = await http
          .get(
            Uri.parse('https://music.youtube.com'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;

        // 1. Extract clientVersion
        final versionMatch = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":\s*"([^"]+)"')
                .firstMatch(body) ??
            RegExp(r'"clientVersion":\s*"([^"]+)"').firstMatch(body);

        // 2. Extract apiKey
        final apiKeyMatch = RegExp(r'"INNERTUBE_API_KEY":\s*"([^"]+)"')
                .firstMatch(body) ??
            RegExp(r'"innertubeApiKey":\s*"([^"]+)"').firstMatch(body);

        final prefs = await SharedPreferences.getInstance();

        if (versionMatch != null && versionMatch.group(1) != null) {
          final resolvedVersion = versionMatch.group(1)!;
          if (resolvedVersion.isNotEmpty) {
            _clientVersion = resolvedVersion;
            await prefs.setString(_prefKeyClientVersion, resolvedVersion);
            debugPrint('[YTM_VERSION] Resolved Innertube clientVersion: $_clientVersion');
          }
        }

        if (apiKeyMatch != null && apiKeyMatch.group(1) != null) {
          final resolvedKey = apiKeyMatch.group(1)!;
          if (resolvedKey.isNotEmpty) {
            _apiKey = resolvedKey;
            await prefs.setString(_prefKeyApiKey, resolvedKey);
            debugPrint('[YTM_VERSION] Resolved Innertube apiKey: $_apiKey');
          }
        }

        await prefs.setInt(_prefKeyLastFetchTime, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[YTM_VERSION] Dynamic client version fetch failed (using cached/fallback): $e');
    }
  }
}
