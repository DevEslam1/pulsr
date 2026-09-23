// lib/core/services/ytm_client_version_resolver.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/channels.dart';
import '../constants/embedded_browser_ua.dart';
import '../utils/error_logger.dart';

@singleton
class YtmClientVersionResolver {
  static const String _prefKeyClientVersion = 'ytm_cached_client_version';
  static const String _prefKeyApiKey = 'ytm_cached_api_key';
  static const String _prefKeyLastFetchTime = 'ytm_client_version_fetch_ts';

  /// Native `ClientCapabilityMatrix.setWebMusicClientVersion` sink. Native pins
  /// a WEB_REMIX version from its asset that ages out; YouTube then answers
  /// every player request with UNPLAYABLE "Video unavailable". The live scraped
  /// value is pushed here so the two stay in sync.
  static const MethodChannel _nativeChannel = MethodChannel(PulsrChannels.ytm);

  static Future<void> _pushToNative(String version) async {
    if (version.isEmpty) return;
    try {
      await _nativeChannel.invokeMethod<bool>(
          'setClientVersion', {'clientVersion': version});
    } catch (_) {}
  }

  static String get defaultDynamicVersion {
    final now = DateTime.now().toUtc();
    final yyyy = now.year.toString().padLeft(4, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '1.$yyyy$mm$dd.01.00';
  }

  /// Build-time fallbacks. Both are overridable via `--dart-define` so release
  /// pipelines can inject their own values from CI secrets rather than relying
  /// on the public defaults baked into source (I18). The live scraped values
  /// still take precedence once [init] refreshes them.
  static String get fallbackClientVersion {
    const fromEnv = String.fromEnvironment('YTM_CLIENT_VERSION');
    if (fromEnv.isNotEmpty) return fromEnv;
    return defaultDynamicVersion;
  }

  static const String fallbackApiKey = String.fromEnvironment(
    'YTM_API_KEY',
    defaultValue: 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
  );
  static const Duration _cacheTtl = Duration(hours: 24);
  static const Duration _maxStaleTtl = Duration(days: 30);
  static const String _prefKeySts = 'ytm_cached_sts';

  late String _clientVersion = fallbackClientVersion;
  String _apiKey = fallbackApiKey;
  int? _sts;
  bool _isInitialized = false;

  String get clientVersion => _clientVersion;
  String get apiKey => _apiKey;
  int get sts => _sts ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000);

  String get androidMusicVersion =>
      const String.fromEnvironment('YTM_ANDROID_MUSIC_VERSION', defaultValue: '8.32.50');
  String get iosMusicVersion =>
      const String.fromEnvironment('YTM_IOS_MUSIC_VERSION', defaultValue: '8.32.1');
  String get androidVrVersion =>
      const String.fromEnvironment('YTM_ANDROID_VR_VERSION', defaultValue: '1.63.27');
  String get androidVersion =>
      const String.fromEnvironment('YTM_ANDROID_VERSION', defaultValue: '19.44.38');
  String get androidCreatorVersion =>
      const String.fromEnvironment('YTM_ANDROID_CREATOR_VERSION', defaultValue: '24.45.100');

  String clientVersionFor(String clientType) {
    switch (clientType) {
      case 'WEB_REMIX':
      case 'MWEB':
      case 'WEB_EMBEDDED_PLAYER':
        return _clientVersion;
      case 'ANDROID_MUSIC':
        return androidMusicVersion;
      case 'IOS_MUSIC':
        return iosMusicVersion;
      case 'ANDROID_VR':
        return androidVrVersion;
      case 'ANDROID':
        return androidVersion;
      case 'ANDROID_CREATOR':
        return androidCreatorVersion;
      case 'TVHTML5_SIMPLY_EMBEDDED_PLAYER':
        return '2.0';
      case 'ANDROID_TESTSUITE':
        return '1.9';
      default:
        return _clientVersion;
    }
  }

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
        unawaited(_pushToNative(savedVersion));
      } else {
        _clientVersion = fallbackClientVersion;
        unawaited(_pushToNative(_clientVersion));
      }
      if (!isStale && savedKey != null && savedKey.isNotEmpty) {
        _apiKey = savedKey;
      }
      final savedSts = prefs.getInt(_prefKeySts);
      if (savedSts != null && savedSts > 0) {
        _sts = savedSts;
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
    try {
      http.Response? response;
      try {
        response = await http.get(
          Uri.parse('https://music.youtube.com'),
          headers: {
            'User-Agent': EmbeddedBrowserUa.desktop,
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ).timeout(const Duration(seconds: 15));
      } catch (_) {
        try {
          response = await http.get(
            Uri.parse('https://www.youtube.com'),
            headers: {
              'User-Agent': EmbeddedBrowserUa.desktop,
              'Accept-Language': 'en-US,en;q=0.9',
            },
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }

      if (response != null && response.statusCode == 200) {
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

        // 3. Extract STS (signatureTimestamp)
        final stsMatch = RegExp(r'"STS":\s*(\d+)').firstMatch(body) ??
            RegExp(r'"signatureTimestamp":\s*(\d+)').firstMatch(body);

        final prefs = await SharedPreferences.getInstance();

        if (stsMatch != null && stsMatch.group(1) != null) {
          final parsed = int.tryParse(stsMatch.group(1)!);
          if (parsed != null && parsed > 0) {
            _sts = parsed;
            await prefs.setInt(_prefKeySts, parsed);
          }
        }

        if (versionMatch != null && versionMatch.group(1) != null) {
          final resolvedVersion = versionMatch.group(1)!;
          if (resolvedVersion.isNotEmpty) {
            _clientVersion = resolvedVersion;
            await prefs.setString(_prefKeyClientVersion, resolvedVersion);
            unawaited(_pushToNative(resolvedVersion));
            debugPrint(
                '[YTM_VERSION] Resolved Innertube clientVersion: $_clientVersion');
          }
        }

        if (apiKeyMatch != null && apiKeyMatch.group(1) != null) {
          final resolvedKey = apiKeyMatch.group(1)!;
          if (resolvedKey.isNotEmpty) {
            _apiKey = resolvedKey;
            await prefs.setString(_prefKeyApiKey, resolvedKey);
            debugPrint('[YTM_VERSION] Successfully resolved Innertube apiKey');
          }
        }

        await prefs.setInt(
            _prefKeyLastFetchTime, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint(
          '[YTM_VERSION] Dynamic client version fetch failed (using cached/fallback): $e');
    }
  }
}
