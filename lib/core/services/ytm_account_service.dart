// lib/core/services/ytm_account_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/lyrics_line.dart';
import '../../domain/models/ytm_track.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';
import '../utils/ytm_rate_limiter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class YtmAccountPlaylist {
  final String playlistId;
  final String title;
  final String subtitle;
  final String? artworkUrl;

  const YtmAccountPlaylist({
    required this.playlistId,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
  });

  String get cleanPlaylistId =>
      playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;

  String get shareUrl =>
      'https://music.youtube.com/playlist?list=$cleanPlaylistId';

  Map<String, dynamic> toJson() => {
        'playlistId': playlistId,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
      };

  factory YtmAccountPlaylist.fromJson(Map<String, dynamic> json) =>
      YtmAccountPlaylist(
        playlistId: json['playlistId'] as String? ?? '',
        title: json['title'] as String? ?? 'Playlist',
        subtitle: json['subtitle'] as String? ?? 'YouTube Music',
        artworkUrl: json['artworkUrl'] as String?,
      );
}

@singleton
class YtmAccountService {
  static const String _cookiePrefKey = 'ytm_session_cookies';
  static const String _accountNamePrefKey = 'ytm_account_name';
  static const String _accountAvatarPrefKey = 'ytm_account_avatar';
  static const String _innertubeBrowseUrl =
      'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false';

  final YtmClientVersionResolver _versionResolver;

  YtmAccountService(this._versionResolver);

  String? _cookies;
  String? _accountName;
  String? _accountAvatar;
  bool _isInitialized = false;

  /// Notifies listeners whenever the YTM login state changes (login/logout).
  final loginState = ValueNotifier<bool>(false);

  bool get isLoggedIn => _cookies != null && _cookies!.isNotEmpty;
  String? get accountName => _accountName;
  String? get accountAvatar => _accountAvatar;

  String get _clientVersion => _versionResolver.clientVersion;
  String get _apiKey => _versionResolver.apiKey;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _versionResolver.init();
      final prefs = await SharedPreferences.getInstance();
      _cookies = prefs.getString(_cookiePrefKey);
      _accountName = prefs.getString(_accountNamePrefKey);
      _accountAvatar = prefs.getString(_accountAvatarPrefKey);
      _isInitialized = true;
      loginState.value = isLoggedIn;

      if (_cookies != null && _cookies!.isNotEmpty) {
        final ytmService = getIt<YtmService>();
        await ytmService.syncCookies(_cookies!);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize YtmAccountService',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
    }
  }

  /// Returns cookies from all YouTube Music / Google domains via native CookieManager.
  Future<String?> getNativeCookiesFromDomains() async {
    const channel = MethodChannel('com.pulsr.music/ytm');
    try {
      final cookies = await channel.invokeMethod<String>('getCookies');
      return cookies;
    } catch (_) {
      return null;
    }
  }

  /// Saves extracted web cookies, warms the session, and triggers fresh attestation.
  Future<bool> saveSession(String rawCookies) async {
    _cookies = rawCookies;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiePrefKey, rawCookies);

    // Sync to native CookieManager and invalidate stale poTokens
    final ytmService = getIt<YtmService>();
    await ytmService.syncCookies(rawCookies);
    await ytmService.invalidatePoToken();

    final name = _extractCookieValue(rawCookies, 'ACCOUNT_CHOOSER') ??
        _extractCookieValue(rawCookies, 'LOGIN_INFO') ??
        'YouTube Music User';
    _accountName = name;
    await prefs.setString(_accountNamePrefKey, name);

    loginState.value = true;

    // Warm session in background & harvest any Set-Cookie headers
    unawaited(_warmSession());
    return true;
  }

  Future<void> logout() async {
    _cookies = null;
    _accountName = null;
    _accountAvatar = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiePrefKey);
    await prefs.remove(_accountNamePrefKey);
    await prefs.remove(_accountAvatarPrefKey);
    loginState.value = false;

    try {
      final ytmService = getIt<YtmService>();
      await ytmService.syncCookies('');
      await ytmService.invalidatePoToken();
    } catch (_) {}
    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
  }

  Future<void> _warmSession() async {
    try {
      final headers = _buildHeaders();
      final body = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'browseId': 'FEmusic_home',
      });

      final res = await _postWithRetry(
        Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
        headers: headers,
        body: body,
      );

      if (res.statusCode == 200) {
        final setCookie = res.headers['set-cookie'];
        if (setCookie != null && setCookie.isNotEmpty) {
          _ingestSetCookies(setCookie);
        }
        debugPrint('[YTM_ACCOUNT] Session warmed successfully');
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Session warming error (non-fatal): $e');
    }
  }

  void _ingestSetCookies(String setCookieHeader) {
    final currentMap = <String, String>{};
    if (_cookies != null && _cookies!.isNotEmpty) {
      for (final pair in _cookies!.split(';')) {
        final parts = pair.trim().split('=');
        if (parts.length >= 2 && parts[0].isNotEmpty) {
          currentMap[parts[0].trim()] = parts.sublist(1).join('=').trim();
        }
      }
    }

    final newPairs = setCookieHeader.split(',');
    for (final p in newPairs) {
      final cookiePart = p.split(';').first.trim();
      final parts = cookiePart.split('=');
      if (parts.length >= 2 && parts[0].isNotEmpty) {
        currentMap[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    final merged = currentMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _cookies = merged;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_cookiePrefKey, merged);
    });
  }

  /// Builds authenticated Innertube request headers with timestamped SAPISIDHASH.
  Map<String, String> _buildHeaders({String userAgent = ''}) {
    final defaultUa =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': userAgent.isNotEmpty ? userAgent : defaultUa,
      'Origin': 'https://music.youtube.com',
      'Referer': 'https://music.youtube.com/',
      'x-origin': 'https://music.youtube.com',
      'x-youtube-client-name': '67',
      'x-youtube-client-version': _clientVersion,
      'x-goog-authuser': '0',
      'X-Goog-Api-Key': _apiKey,
    };

    if (_cookies != null && _cookies!.isNotEmpty) {
      headers['Cookie'] = _cookies!;
      final sapisid = _extractCookieValue(_cookies!, 'SAPISID') ??
          _extractCookieValue(_cookies!, '__Secure-3PAPISID') ??
          _extractCookieValue(_cookies!, '__Secure-1PAPISID');

      if (sapisid != null && sapisid.isNotEmpty) {
        final timestamp =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        final toHash = '$timestamp $sapisid https://music.youtube.com';
        final sha1Digest = sha1.convert(utf8.encode(toHash)).toString();
        headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Digest';
      }
    }

    return headers;
  }

  String? _extractCookieValue(String cookieString, String key) {
    for (final pair in cookieString.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2 && parts[0].trim() == key) {
        return parts.sublist(1).join('=').trim();
      }
    }
    return null;
  }

  Map<String, dynamic> _buildClientContext(String clientType) {
    final clientMap = <String, dynamic>{
      'clientName': clientType,
      'clientVersion': clientType == 'WEB_REMIX' ? _clientVersion : '19.29.37',
      'hl': 'en',
      'gl': 'US',
    };

    if (clientType == 'ANDROID_MUSIC') {
      clientMap['clientVersion'] = '7.27.52';
      clientMap['androidSdkVersion'] = 33;
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '13';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'IOS_MUSIC') {
      clientMap['clientVersion'] = '7.27.1';
      clientMap['deviceMake'] = 'Apple';
      clientMap['deviceModel'] = 'iPhone14,3';
      clientMap['osName'] = 'iOS';
      clientMap['osVersion'] = '17.5.1';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_VR') {
      clientMap['clientVersion'] = '1.60.19';
      clientMap['androidSdkVersion'] = 32;
      clientMap['deviceMake'] = 'Oculus';
      clientMap['deviceModel'] = 'Quest 2';
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '12';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_CREATOR') {
      clientMap['clientVersion'] = '24.45.100';
      clientMap['androidSdkVersion'] = 33;
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '13';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_TESTSUITE') {
      clientMap['clientVersion'] = '1.9';
      clientMap['androidSdkVersion'] = 28;
    } else if (clientType == 'MWEB') {
      clientMap['clientVersion'] = '2.20250820.01.00';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'WEB_EMBEDDED_PLAYER') {
      clientMap['clientVersion'] = '1.20250820.01.00';
      clientMap['platform'] = 'DESKTOP';
    } else if (clientType == 'ANDROID') {
      clientMap['androidSdkVersion'] = 33;
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '13';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'IOS') {
      clientMap['clientVersion'] = '19.29.1';
      clientMap['deviceMake'] = 'Apple';
      clientMap['deviceModel'] = 'iPhone14,3';
      clientMap['osName'] = 'iOS';
      clientMap['osVersion'] = '17.5.1';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
      clientMap['clientVersion'] = '2.0';
      clientMap['platform'] = 'TV';
    } else {
      clientMap['platform'] = 'DESKTOP';
    }

    final contextJson = <String, dynamic>{
      'client': clientMap,
      'user': {'lockedSafetyMode': false},
    };

    if (clientType == 'WEB_EMBEDDED_PLAYER' || clientType == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
      contextJson['thirdParty'] = {'embedUrl': 'https://www.youtube.com'};
    }

    return contextJson;
  }

  Future<http.Response> _postWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    int maxAttempts = 3,
    int baseTimeoutSeconds = 15,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await YtmRateLimiter.shared.acquirePermit();
        final timeout = Duration(seconds: baseTimeoutSeconds + attempt * 5);
        final res = await http.post(uri, headers: headers, body: body).timeout(timeout);

        if (res.statusCode == 429) {
          YtmRateLimiter.shared.onRateLimited();
          final backoffSec = (1 << attempt) + Random().nextInt(2);
          debugPrint('[YTM_ACCOUNT] HTTP 429 rate limited. Backing off for ${backoffSec}s');
          await Future.delayed(Duration(seconds: backoffSec));
          continue;
        }

        YtmRateLimiter.shared.onSuccess();
        return res;
      } on TimeoutException {
        if (attempt == maxAttempts - 1) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
      }
    }
    throw const YtmException('YTM_TIMEOUT', 'Exceeded maximum retry attempts');
  }

  /// Fetches library playlists from YouTube Music.
  Future<List<YtmAccountPlaylist>> fetchAccountPlaylists() async {
    if (!isLoggedIn) {
      throw const YtmException('YTM_AUTH', 'Not signed in to YouTube Music');
    }

    final headers = _buildHeaders();
    final browseIds = [
      'FEmusic_library_playlists',
      'FEmusic_liked_playlists',
      'FEmusic_library_landing',
    ];

    for (final bId in browseIds) {
      try {
        final body = jsonEncode({
          'context': _buildClientContext('WEB_REMIX'),
          'browseId': bId,
        });

        final response = await _postWithRetry(
          Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
          headers: headers,
          body: body,
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json)) {
            debugPrint('[YTM_ACCOUNT] Unauthenticated response detected on $bId');
            await logout();
            throw const YtmException('YTM_AUTH', 'Session expired');
          }

          final playlists = _parseInnertubeAccountPlaylists(json);
          if (playlists.isNotEmpty) {
            return playlists;
          }
        }
      } catch (e) {
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint('[YTM_ACCOUNT] Failed fetching account playlists ($bId): $e');
      }
    }
    return [];
  }

  /// Fetches private Liked Music playlist (`FEmusic_liked_videos`).
  Future<List<YtmTrack>> fetchLikedSongs({int maxTracks = 200}) async {
    if (!isLoggedIn) {
      throw const YtmException('YTM_AUTH', 'Not signed in to YouTube Music');
    }

    final headers = _buildHeaders();
    final browseIds = ['FEmusic_liked_videos', 'VLLM'];

    for (final bId in browseIds) {
      try {
        final body = jsonEncode({
          'context': _buildClientContext('WEB_REMIX'),
          'browseId': bId,
        });

        final response = await _postWithRetry(
          Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
          headers: headers,
          body: body,
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json)) {
            debugPrint('[YTM_ACCOUNT] Liked songs returned unauthenticated, logging out');
            await logout();
            throw const YtmException('YTM_AUTH', 'Session expired');
          }

          final tracks = _parseInnertubePlaylistTracks(json);
          if (tracks.isNotEmpty) {
            return tracks.take(maxTracks).toList();
          }
        }
      } catch (e) {
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint('[YTM_ACCOUNT] Liked songs fetch failed for $bId: $e');
      }
    }
    return [];
  }

  /// Fetches personalized recommendations and home feed from YouTube Music (`FEmusic_home`).
  Future<List<YtmTrack>> fetchHomeRecommendations({int maxTracks = 50}) async {
    if (!isLoggedIn) return [];
    final headers = _buildHeaders();

    try {
      final body = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'browseId': 'FEmusic_home',
      });

      final response = await _postWithRetry(
        Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (!_isUnauthenticatedResponse(json)) {
          final tracks = _parseInnertubePlaylistTracks(json);
          if (tracks.isNotEmpty) {
            final seen = <String>{};
            final unique = <YtmTrack>[];
            for (final t in tracks) {
              if (seen.add(t.videoId)) {
                unique.add(t);
              }
            }
            return unique.take(maxTracks).toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Failed to fetch personalized home feed: $e');
    }
    return [];
  }

  /// Fetches native lyrics from YouTube Music for a given [videoId].
  Future<LyricsResult?> fetchYtmLyrics(String videoId) async {
    if (videoId.isEmpty) return null;
    final headers = _buildHeaders();

    try {
      final nextBody = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'videoId': videoId,
      });

      final nextRes = await _postWithRetry(
        Uri.parse('https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey'),
        headers: headers,
        body: nextBody,
        baseTimeoutSeconds: 8,
      );

      if (nextRes.statusCode != 200) return null;
      final nextJson = jsonDecode(nextRes.body) as Map<String, dynamic>;

      String? lyricsBrowseId;
      void findLyricsBrowseId(dynamic node) {
        if (lyricsBrowseId != null) return;
        if (node is Map<String, dynamic>) {
          if (node.containsKey('tabRenderer')) {
            final tab = node['tabRenderer'] as Map<String, dynamic>;
            final title = tab['title'] as String? ?? '';
            final endpoint =
                tab['endpoint']?['browseEndpoint'] as Map<String, dynamic>?;
            final bId = endpoint?['browseId'] as String?;
            if (title.toLowerCase().contains('lyric') ||
                (bId != null && bId.startsWith('MPLYt'))) {
              lyricsBrowseId = bId;
              return;
            }
          }
          for (final val in node.values) {
            findLyricsBrowseId(val);
          }
        } else if (node is List) {
          for (final item in node) {
            findLyricsBrowseId(item);
          }
        }
      }

      findLyricsBrowseId(nextJson);
      if (lyricsBrowseId == null) return null;

      final browseBody = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'browseId': lyricsBrowseId,
      });

      final browseRes = await _postWithRetry(
        Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
        headers: headers,
        body: browseBody,
        baseTimeoutSeconds: 8,
      );

      if (browseRes.statusCode != 200) return null;
      final browseJson = jsonDecode(browseRes.body) as Map<String, dynamic>;

      final List<LyricsLine> lines = [];
      void parseLyrics(dynamic node) {
        if (node is Map<String, dynamic>) {
          if (node.containsKey('musicDescriptionShelfRenderer')) {
            final shelf =
                node['musicDescriptionShelfRenderer'] as Map<String, dynamic>;
            final desc = shelf['description'];
            String plainText = '';
            if (desc is Map && desc.containsKey('runs')) {
              final runs = desc['runs'] as List<dynamic>;
              plainText = runs.map((r) => r['text'] as String? ?? '').join();
            } else if (desc is String) {
              plainText = desc;
            }
            if (plainText.isNotEmpty) {
              lines.addAll(LrcParser.parsePlainText(plainText,
                  source: LyricsSource.ytmusic));
            }
            return;
          }
          for (final val in node.values) {
            parseLyrics(val);
          }
        } else if (node is List) {
          for (final item in node) {
            parseLyrics(item);
          }
        }
      }

      parseLyrics(browseJson);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, source: LyricsSource.ytmusic);
      }
    } catch (e) {
      debugPrint('[YTM_LYRICS] Error fetching YTM lyrics: $e');
    }
    return null;
  }

  /// Resolves an audio stream using multi-client priority fallback:
  /// 1. WEB_REMIX + cookies
  /// 2. ANDROID client
  /// 3. IOS client
  /// 4. TVHTML5_SIMPLY_EMBEDDED_PLAYER
  Future<YtmStream?> resolvePlayerStream(String videoId, {String quality = 'high'}) async {
    final clientChain = (isLoggedIn && _cookies != null && _cookies!.isNotEmpty)
        ? [
            'WEB_REMIX',
            'ANDROID_VR',
            'ANDROID_CREATOR',
            'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
            'WEB_EMBEDDED_PLAYER',
            'ANDROID_MUSIC',
            'IOS_MUSIC',
            'MWEB',
            'ANDROID_TESTSUITE',
          ]
        : [
            'ANDROID_VR',
            'ANDROID_CREATOR',
            'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
            'WEB_EMBEDDED_PLAYER',
            'ANDROID_MUSIC',
            'IOS_MUSIC',
            'WEB_REMIX',
            'MWEB',
            'ANDROID_TESTSUITE',
          ];

    for (final client in clientChain) {
      try {
        final isWeb = client == 'WEB_REMIX' || client == 'WEB_EMBEDDED_PLAYER' || client == 'MWEB' || client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER';
        final endpointHost = (client == 'ANDROID_MUSIC' || client == 'IOS_MUSIC' || client == 'WEB_REMIX')
            ? 'https://music.youtube.com'
            : (client == 'MWEB' ? 'https://m.youtube.com' : 'https://www.youtube.com');

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'x-youtube-client-name': client == 'ANDROID_MUSIC'
              ? '21'
              : (client == 'IOS_MUSIC'
                  ? '26'
                  : (client == 'WEB_REMIX'
                      ? '67'
                      : (client == 'WEB_EMBEDDED_PLAYER'
                          ? '56'
                          : (client == 'MWEB'
                              ? '65'
                              : (client == 'ANDROID_VR'
                                  ? '28'
                                  : (client == 'ANDROID_CREATOR'
                                      ? '62'
                                      : (client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' ? '85' : '89'))))))),
          'x-youtube-client-version': client == 'ANDROID_MUSIC'
              ? '7.27.52'
              : (client == 'IOS_MUSIC'
                  ? '7.27.1'
                  : (client == 'ANDROID_VR'
                      ? '1.60.19'
                      : (client == 'ANDROID_CREATOR'
                          ? '24.45.100'
                          : (client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
                              ? '2.0'
                              : (client == 'ANDROID_TESTSUITE' ? '1.9' : _clientVersion))))),
          'User-Agent': client == 'ANDROID_MUSIC'
              ? 'com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 13; en_US) gzip'
              : (client == 'IOS_MUSIC'
                  ? 'com.google.ios.youtubemusic/7.27.1 (iPhone14,3; U; CPU iOS 17_5_1 like Mac OS X; en_US)'
                  : (client == 'ANDROID_VR'
                      ? 'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12; en_US; Quest 2) gzip'
                      : (client == 'ANDROID_CREATOR'
                          ? 'com.google.android.apps.youtube.creator/24.45.100 (Linux; U; Android 13; en_US) gzip'
                          : (client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
                              ? 'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36'
                              : (client == 'ANDROID_TESTSUITE'
                                  ? 'com.google.android.youtube/1.9 (Linux; U; Android 9; gzip)'
                                  : (client == 'MWEB'
                                      ? 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36'
                                      : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36')))))),
        };

        if (isWeb) {
          final origin = endpointHost;
          headers['Origin'] = origin;
          headers['Referer'] = '$origin/';
          headers['x-origin'] = origin;
          headers['x-goog-authuser'] = '0';
          if (_cookies != null && _cookies!.isNotEmpty) {
            headers['Cookie'] = _cookies!;
            final sapisid = _extractCookieValue(_cookies!, 'SAPISID') ??
                _extractCookieValue(_cookies!, '__Secure-3PAPISID') ??
                _extractCookieValue(_cookies!, '__Secure-1PAPISID');

            if (sapisid != null && sapisid.isNotEmpty) {
              final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
              final toHash = '$timestamp $sapisid $origin';
              final sha1Digest = sha1.convert(utf8.encode(toHash)).toString();
              headers['Authorization'] = 'SAPISIDHASH ${timestamp}_$sha1Digest';
            }
          }
        }

        Map<String, dynamic>? poState;
        if (client == 'WEB_REMIX') {
          try {
            poState = await getIt<YtmService>().getPoTokenState();
          } catch (_) {}
        }
        final poToken = poState?['streamingPoToken'] as String?;
        final visitorData = poState?['visitorData'] as String?;

        final clientContext = _buildClientContext(client);
        if (visitorData != null && visitorData.isNotEmpty && clientContext['client'] is Map<String, dynamic>) {
          (clientContext['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
        }

        final body = jsonEncode({
          'context': clientContext,
          'videoId': videoId,
          'racyCheckOk': true,
          'contentCheckOk': true,
          'playbackContext': {
            'contentPlaybackContext': {
              'html5Preference': 'HTML5_PREF_WANTS',
              if (poToken != null && poToken.isNotEmpty) 'poToken': poToken,
            },
          },
        });

        final response = await _postWithRetry(
          Uri.parse('$endpointHost/youtubei/v1/player?prettyPrint=false&key=$_apiKey'),
          headers: headers,
          body: body,
          baseTimeoutSeconds: 10,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final playability = data['playabilityStatus'] as Map<String, dynamic>?;
          final status = playability?['status'] as String? ?? '';

          if (status == 'LOGIN_REQUIRED' || status == 'UNPLAYABLE' || status.contains('BOT')) {
            debugPrint('[YTM_ACCOUNT] Client $client returned playability $status, falling back to next');
            continue;
          }

          final streamingData = data['streamingData'] as Map<String, dynamic>?;
          final adaptive = (streamingData?['adaptiveFormats'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();

          final audioFormats = <({Map<String, dynamic> format, String url})>[];
          for (final f in adaptive) {
            final mime = f['mimeType'] as String? ?? '';
            final streamUrl = _extractUrlFromFormat(f);
            if (mime.startsWith('audio/') && streamUrl != null && streamUrl.isNotEmpty) {
              audioFormats.add((format: f, url: streamUrl));
            }
          }

          if (audioFormats.isNotEmpty) {
            final m4a = audioFormats
                .where((f) => ((f.format['mimeType'] as String?) ?? '').contains('mp4'))
                .toList();
            final pool = m4a.isNotEmpty ? m4a : audioFormats;

            final selected = switch (quality.toLowerCase()) {
              'low' => pool.reduce((a, b) =>
                  ((a.format['bitrate'] as num?) ?? 0) < ((b.format['bitrate'] as num?) ?? 0) ? a : b),
              'medium' => pool.reduce((a, b) =>
                  (((a.format['bitrate'] as num?) ?? 128000) - 128000).abs() <
                          (((b.format['bitrate'] as num?) ?? 128000) - 128000).abs()
                      ? a
                      : b),
              _ => pool.reduce((a, b) =>
                  ((a.format['bitrate'] as num?) ?? 0) > ((b.format['bitrate'] as num?) ?? 0) ? a : b),
            };

            final mime = selected.format['mimeType'] as String? ?? 'audio/mp4';
            final bitrate = (selected.format['bitrate'] as num?)?.toInt() ?? 128000;
            final durationMs =
                int.tryParse(selected.format['approxDurationMs']?.toString() ?? '0') ?? 0;
            final details = data['videoDetails'] as Map<String, dynamic>?;

            return YtmStream(
              videoId: videoId,
              url: selected.url,
              mimeType: mime.split(';').first.trim(),
              container: mime.contains('mp4') ? 'm4a' : 'webm',
              bitrateKbps: (bitrate / 1000).round(),
              duration: Duration(milliseconds: durationMs),
              title: details?['title'] as String? ?? '',
              artist: details?['author'] as String? ?? '',
              artworkUrl: null,
              userAgent: headers['User-Agent'],
            );
          }
        }
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Client $client resolution error for $videoId: $e');
      }
    }
    return null;
  }

  String? _extractUrlFromFormat(Map<String, dynamic> format) {
    final directUrl = format['url'] as String?;
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    final cipher = (format['signatureCipher'] ?? format['cipher']) as String?;
    if (cipher != null && cipher.isNotEmpty) {
      try {
        final uri = Uri.parse('?$cipher');
        final extracted = uri.queryParameters['url'];
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      } catch (_) {}
    }
    return null;
  }

  bool _isUnauthenticatedResponse(Map<String, dynamic> json) {
    final hasContents = json.containsKey('contents');
    final hasHeader = json.containsKey('header');
    final hasResponseContext = json.containsKey('responseContext');
    return hasResponseContext && !hasContents && !hasHeader;
  }

  List<YtmTrack> _parseInnertubePlaylistTracks(Map<String, dynamic> root) {
    final tracks = <YtmTrack>[];

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final track = _parseListItemRenderer(renderer);
          if (track != null) tracks.add(track);
          return;
        } else if (node.containsKey('playlistVideoRenderer')) {
          final renderer =
              node['playlistVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final title = renderer['title']?['runs']?[0]?['text'] as String? ??
              'Unknown Title';
          final artist =
              renderer['shortBylineText']?['runs']?[0]?['text'] as String? ??
                  'Unknown Artist';
          final lengthSeconds =
              int.tryParse(renderer['lengthSeconds']?.toString() ?? '0') ?? 0;
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork = thumbnails?.isNotEmpty == true
              ? thumbnails!.last['url'] as String?
              : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(YtmTrack(
              videoId: videoId,
              title: title,
              artist: artist,
              duration: Duration(seconds: lengthSeconds),
              artworkUrl: artwork,
            ));
          }
          return;
        } else if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final vid = nav?['watchEndpoint']?['videoId'] as String?;
          if (vid != null && vid.length == 11) {
            final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
            final title = titleRuns?.isNotEmpty == true
                ? titleRuns![0]['text'] as String? ?? 'Unknown Title'
                : 'Unknown Title';

            String artist = 'Unknown Artist';
            int durationMs = 0;

            final subRuns = renderer['subtitle']?['runs'] as List<dynamic>?;
            if (subRuns != null && subRuns.isNotEmpty) {
              final texts = subRuns
                  .map((r) => r['text']?.toString().trim() ?? '')
                  .where((t) => t.isNotEmpty && t != '•' && t != '·')
                  .toList();

              for (final t in texts) {
                final parts = t.split(':').map((e) => int.tryParse(e)).toList();
                if (parts.length == 2 && parts[0] != null && parts[1] != null) {
                  durationMs = (parts[0]! * 60 + parts[1]!) * 1000;
                } else if (parts.length == 3 &&
                    parts[0] != null &&
                    parts[1] != null &&
                    parts[2] != null) {
                  durationMs =
                      (parts[0]! * 3600 + parts[1]! * 60 + parts[2]!) * 1000;
                } else if (t.toLowerCase() != 'song' &&
                    t.toLowerCase() != 'video' &&
                    artist == 'Unknown Artist') {
                  artist = t;
                }
              }
            }

            String? artworkUrl;
            final thumbRenderer = renderer['thumbnailRenderer']
                    ?['musicThumbnailRenderer'] ??
                renderer['thumbnail']?['musicThumbnailRenderer'];
            final thumbs = (thumbRenderer?['thumbnail']?['thumbnails'] ??
                renderer['thumbnail']?['thumbnails']) as List<dynamic>?;
            if (thumbs != null && thumbs.isNotEmpty) {
              artworkUrl = thumbs.last['url'] as String?;
              if (artworkUrl != null) {
                artworkUrl =
                    artworkUrl.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
                artworkUrl =
                    artworkUrl.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
              }
            }

            tracks.add(YtmTrack(
              videoId: vid,
              title: title,
              artist: artist,
              duration: Duration(milliseconds: durationMs),
              artworkUrl: artworkUrl,
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

    traverse(root);
    return tracks;
  }

  YtmTrack? _parseListItemRenderer(Map<String, dynamic> renderer) {
    try {
      final playlistItemData =
          renderer['playlistItemData'] as Map<String, dynamic>?;
      String? videoId = playlistItemData?['videoId'] as String?;

      if (videoId == null) {
        final flexColumns =
            renderer['flexColumns'] as List<dynamic>? ?? const [];
        for (final col in flexColumns) {
          final runs = col['musicResponsiveListItemFlexColumnRenderer']?['text']
              ?['runs'] as List<dynamic>?;
          if (runs != null) {
            for (final r in runs) {
              final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
              final vid = nav?['watchEndpoint']?['videoId'] as String?;
              if (vid != null) {
                videoId = vid;
                break;
              }
            }
          }
          if (videoId != null) break;
        }
      }

      if (videoId == null || videoId.length != 11) return null;

      String title = 'Unknown Title';
      String artist = 'Unknown Artist';
      int durationMs = 0;

      final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? const [];
      if (flexColumns.isNotEmpty) {
        final col0 = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']
            ?['text']?['runs'];
        if (col0 is List && col0.isNotEmpty) {
          title = col0[0]['text'] as String? ?? title;
        }
      }
      if (flexColumns.length > 1) {
        final col1 = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']
            ?['text']?['runs'];
        if (col1 is List && col1.isNotEmpty) {
          artist = col1[0]['text'] as String? ?? artist;
        }
      }

      final fixedCols = renderer['fixedColumns'] as List<dynamic>? ?? const [];
      if (fixedCols.isNotEmpty) {
        final durText = fixedCols[0]
                ['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']
            ?[0]?['text'] as String?;
        if (durText != null) {
          final parts =
              durText.split(':').map((e) => int.tryParse(e) ?? 0).toList();
          if (parts.length == 2) {
            durationMs = (parts[0] * 60 + parts[1]) * 1000;
          } else if (parts.length == 3) {
            durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
          }
        }
      }

      String? artworkUrl;
      final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List<dynamic>?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        artworkUrl = thumbnails.last['url'] as String?;
        if (artworkUrl != null) {
          artworkUrl =
              artworkUrl.replaceAll(RegExp(r'=w\d+-h\d+[^?]*'), '=s1200');
          artworkUrl = artworkUrl.replaceAll(RegExp(r'=s\d+[^?]*'), '=s1200');
        }
      }

      return YtmTrack(
        videoId: videoId,
        title: title,
        artist: artist,
        duration: Duration(milliseconds: durationMs),
        artworkUrl: artworkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  List<YtmAccountPlaylist> _parseInnertubeAccountPlaylists(
    Map<String, dynamic> root,
  ) {
    final results = <YtmAccountPlaylist>[];
    final seenIds = <String>{};

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId = nav?['browseEndpoint']?['browseId'] as String?;

          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL') ||
                  browseId.startsWith('RDCLAK5uy_'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
              final title =
                  titleRuns?.map((r) => r['text']?.toString() ?? '').join() ??
                      'Playlist';

              final subRuns = renderer['subtitle']?['runs'] as List<dynamic>?;
              final subtitle =
                  subRuns?.map((r) => r['text']?.toString() ?? '').join() ??
                      'YouTube Music';

              String? artwork;
              final thumbRenderer =
                  renderer['thumbnailRenderer']?['musicThumbnailRenderer'];
              final thumbs =
                  thumbRenderer?['thumbnail']?['thumbnails'] as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title.isNotEmpty ? title : 'Playlist',
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
        }

        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
          final browseId = nav?['browseEndpoint']?['browseId'] as String?;
          if (browseId != null &&
              (browseId.startsWith('VLPL') ||
                  browseId.startsWith('VL') ||
                  browseId.startsWith('PL'))) {
            final cleanId =
                browseId.startsWith('VL') ? browseId.substring(2) : browseId;
            if (cleanId != 'LM' &&
                cleanId != 'SE' &&
                !seenIds.contains(cleanId)) {
              seenIds.add(cleanId);

              String title = 'Playlist';
              final flexCols = renderer['flexColumns'] as List<dynamic>?;
              if (flexCols != null && flexCols.isNotEmpty) {
                final r = flexCols[0]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  title = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String subtitle = 'YouTube Music';
              if (flexCols != null && flexCols.length > 1) {
                final r = flexCols[1]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  subtitle = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String? artwork;
              final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']
                  ?['thumbnail']?['thumbnails'] as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(YtmAccountPlaylist(
                playlistId: cleanId,
                title: title,
                subtitle: subtitle,
                artworkUrl: artwork,
              ));
            }
          }
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

    traverse(root);
    return results;
  }
}
