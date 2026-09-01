// lib/core/services/ytm_account_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/lyrics_line.dart';
import '../../domain/models/ytm_track.dart';
import '../constants/channels.dart';
import '../utils/error_logger.dart';
import '../utils/lrc_parser.dart';
import 'xdm_backend_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    hide AndroidOptions;

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

enum SessionValidationResult { valid, invalid, unknown }

@singleton
class YtmAccountService {
  String? _cachedLikedSongsBrowseId;
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/ytm');

  /// Session cookies are full Google auth credentials — stored in
  /// Keystore/Keychain-backed secure storage, never as plaintext prefs. (BUG-023)
  static const String _cookieSecureKey = 'ytm_session_cookies_secure';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // ignore: deprecated_member_use
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const String _accountNamePrefKey = 'ytm_account_name';
  static const String _accountAvatarPrefKey = 'ytm_account_avatar';
  static const String _dataSyncIdPrefKey = 'ytm_data_sync_id';
  static const String _innertubeBrowseUrl =
      'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false';
  static const Map<String, String> _clientNameIds = {
    'ANDROID_MUSIC': '21',
    'IOS_MUSIC': '26',
    'ANDROID_VR': '28',
    'ANDROID_TESTSUITE': '30',
    'WEB_EMBEDDED_PLAYER': '56',
    'ANDROID_CREATOR': '62',
    'MWEB': '65',
    'WEB_REMIX': '67',
    'TVHTML5_SIMPLY_EMBEDDED_PLAYER': '85',
  };

  final YtmClientVersionResolver _versionResolver;

  YtmAccountService(this._versionResolver);

  String? _cookies;
  String? _accountName;
  String? _accountAvatar;
  bool _isInitialized = false;

  /// Raw `datasyncId` of the authenticated account (e.g. "userSessionId||"), harvested from any
  /// authenticated Innertube response. Used as the account-bound poToken content-binding.
  String? _dataSyncId;
  Timer? _sessionHarvestDebounce;

  /// `visitorData` harvested from an authenticated response; sent in the WEB_REMIX player context.
  String? _sessionVisitorData;

  /// Timestamp of the most recent successful [saveSession] call. Used to
  /// suppress false-positive auth-expiry signals during the post-login window
  /// (cookie propagation + poToken minting lag can cause WEB_REMIX to return
  /// LOGIN_REQUIRED for ~10-20 s right after a fresh login).
  DateTime? _sessionSavedAt;

  /// Returns true when we are inside the 30-second grace window after a
  /// fresh login, during which LOGIN_REQUIRED signals should NOT trigger a
  /// logout or an auth-expiry notification.
  bool get _inPostLoginGrace {
    final saved = _sessionSavedAt;
    if (saved == null) return false;
    return DateTime.now().difference(saved).inSeconds < 30;
  }

  /// Coalesces concurrent liked-songs imports so UI + background callers share
  /// a single pagination ladder instead of burning the BROWSE rate-limiter
  /// bucket with duplicate 20-page fetches.
  final Map<String, Future<List<YtmTrack>>> _inFlightLikedSongs = {};

  /// Notifies listeners whenever the YTM login state changes (login/logout).
  final loginState = ValueNotifier<bool>(false);

  bool get isLoggedIn => _cookies != null && _cookies!.isNotEmpty;
  String? get cookies => _cookies;
  String? get accountName => _accountName;
  String? get accountAvatar => _accountAvatar;

  String get _clientVersion => _versionResolver.clientVersion;
  String get _apiKey => _versionResolver.apiKey;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _versionResolver.init();
      final nativeCookies = await getNativeCookiesFromDomains();
      if (nativeCookies != null &&
          nativeCookies.isNotEmpty &&
          looksLikeSignedInCookies(nativeCookies)) {
        _cookies = nativeCookies;
        await _persistCookies(nativeCookies);
      } else {
        _cookies = await _readStoredCookies();
      }
      if (_cookies != null && _cookies!.isNotEmpty) {
        final ok = await validateSession();
        if (!ok) {
          await _deleteStoredCookies(); // dead session: wipe, don't poison WebView
          _cookies = null;
        } else {
          final ytmService = getIt<YtmService>();
          await ytmService.syncCookies(
            _cookies!,
          ); // inject ONLY validated cookies
          final dsid = _dataSyncId;
          if (dsid != null && dsid.isNotEmpty) {
            await ytmService.setDataSyncId(dsid);
          }
          // One-time migration: move any legacy plaintext copy into secure
          // storage and drop the plaintext key.
          unawaited(_persistCookies(_cookies!));
        }
      }
      final prefs = await SharedPreferences.getInstance();
      _accountName = prefs.getString(_accountNamePrefKey);
      _accountAvatar = prefs.getString(_accountAvatarPrefKey);
      _dataSyncId = prefs.getString(_dataSyncIdPrefKey);
      _isInitialized = true;
      loginState.value = isLoggedIn;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to initialize YtmAccountService',
        error: e,
        stackTrace: st,
        category: 'YTM_ACCOUNT',
      );
    }
  }

  /// Returns [SessionValidationResult] indicating if the session is valid, invalid, or unknown (network error).
  Future<SessionValidationResult> validateSessionDetailed() async {
    if (!isLoggedIn) return SessionValidationResult.invalid;
    try {
      final res = await _postWithRetry(
        Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
        headers: _buildHeaders(),
        body: jsonEncode({
          'context': _buildClientContext('WEB_REMIX'),
          'browseId': 'FEmusic_home',
        }),
        baseTimeoutSeconds: 8,
      );
      if (res.statusCode != 200) {
        return SessionValidationResult.unknown; // transient, don't kill session
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (_isUnauthenticatedResponse(json)) {
        return SessionValidationResult.invalid; // definitive
      }
      _harvestSessionState(json);
      return SessionValidationResult.valid;
    } on YtmException catch (e) {
      return e.isAuth
          ? SessionValidationResult.invalid
          : SessionValidationResult.unknown;
    } catch (_) {
      return SessionValidationResult.unknown; // network failure
    }
  }

  /// Convenience wrapper returning false only when session is definitively invalid.
  Future<bool> validateSession() async {
    final res = await validateSessionDetailed();
    return res != SessionValidationResult.invalid;
  }

  /// Returns cookies from all YouTube Music / Google domains via native CookieManager.
  Future<String?> getNativeCookiesFromDomains() async {
    const channel = MethodChannel(PulsrChannels.ytm);
    try {
      final cookies = await channel.invokeMethod<String>('getCookies');
      return cookies;
    } catch (_) {
      return null;
    }
  }

  /// Reads session cookies exclusively from Keystore/Keychain secure storage. (BUG-023)
  Future<String?> _readStoredCookies() async {
    try {
      final secure = await _secureStorage.read(key: _cookieSecureKey);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to read cookies from secure storage',
        error: e,
        stackTrace: st,
        category: 'YTM_ACCOUNT',
      );
    }
    return null;
  }

  static String sanitizeAndValidateCookies(String rawCookies) {
    if (rawCookies.isEmpty) return '';
    final parts = rawCookies.split(';');
    final validPairs = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx > 0) {
        final key = trimmed.substring(0, eqIdx).trim();
        final value = trimmed.substring(eqIdx + 1).trim();
        if (RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(key)) {
          validPairs.add('$key=$value');
        }
      }
    }
    return validPairs.join('; ');
  }

  /// Persists session cookies exclusively to secure storage. (BUG-023)
  Future<void> _persistCookies(String rawCookies) async {
    final sanitized = sanitizeAndValidateCookies(rawCookies);
    try {
      await _secureStorage.write(key: _cookieSecureKey, value: sanitized);
      _cookies = sanitized;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist cookies to secure storage',
        error: e,
        stackTrace: st,
        category: 'YTM_ACCOUNT',
      );
      _cookies = sanitized;
    }
  }

  Future<void> _deleteStoredCookies() async {
    try {
      await _secureStorage.delete(key: _cookieSecureKey);
    } catch (_) {}
  }

  /// Saves extracted web cookies, warms the session, and triggers fresh attestation.
  Future<bool> saveSession(String rawCookies) async {
    _cookies = rawCookies;
    // Stamp the login time BEFORE the warm request fires so the grace window
    // is active during any concurrent resolvePlayerStream calls.
    _sessionSavedAt = DateTime.now();
    await _persistCookies(rawCookies);

    // Sync to native CookieManager and invalidate stale poTokens
    final ytmService = getIt<YtmService>();
    await ytmService.syncCookies(rawCookies);
    await ytmService.invalidatePoToken();

    // ACCOUNT_CHOOSER / LOGIN_INFO hold opaque base64 blobs, not human names.
    // Use a stable honest label; real account metadata is harvested later.
    const name = 'YouTube Music Account';
    _accountName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountNamePrefKey, name);

    loginState.value = true;

    // Warm session in background & harvest any Set-Cookie headers
    unawaited(
      _warmSession().catchError((Object e) {
        debugPrint('[YTM_ACCOUNT] Session warming failed (non-fatal): $e');
      }),
    );
    return true;
  }


  Future<void> logout() async {
    _cookies = null;
    _accountName = null;
    _accountAvatar = null;
    _dataSyncId = null;
    _sessionVisitorData = null;
    _cachedLikedSongsBrowseId = null;
    _inFlightLikedSongs.clear();
    await _deleteStoredCookies();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountNamePrefKey);
    await prefs.remove(_accountAvatarPrefKey);
    await prefs.remove(_dataSyncIdPrefKey);
    loginState.value = false;

    try {
      final ytmService = getIt<YtmService>();
      // Full identity reset (PoToken + visitorData + fingerprint) so the
      // next login does not reuse a fingerprint-bound visitorData from the
      // previous account — matches resetIdentities semantics.
      await ytmService.resetIdentities();
    } catch (_) {
      try {
        final ytmService = getIt<YtmService>();
        await ytmService.syncCookies('');
        await ytmService.invalidatePoToken();
      } catch (_) {}
    }
    try {
      await _deleteSessionWebViewCookies();
    } catch (_) {}
  }

  /// Cookie domains owned by the YTM sign-in flow. Logout clears only these
  /// instead of wiping every WebView/Google cookie on the device.
  static const List<String> _sessionCookieDomains = [
    '.youtube.com',
    '.google.com',
    'https://music.youtube.com',
    'https://www.youtube.com',
    'https://youtube.com',
    'https://m.youtube.com',
    'https://accounts.google.com',
    'https://accounts.youtube.com',
    'https://myaccount.google.com',
  ];

  /// Deletes only YTM/Google session cookies from the WebView cookie store.
  /// Public so the login sheet's manual "clear cookies" action stays scoped.
  Future<void> clearSessionWebViewCookies() => _deleteSessionWebViewCookies();

  Future<void> _deleteSessionWebViewCookies() async {
    try {
      final cookieManager = CookieManager.instance();
      for (final domain in _sessionCookieDomains) {
        final isHostScoped = domain.startsWith('https://');
        await cookieManager.deleteCookies(
          url: WebUri(isHostScoped ? domain : 'https://$domain'),
          domain: isHostScoped ? '' : domain,
          path: '/',
        );
      }
    } catch (_) {
      // Scoped deletion unsupported on this platform — fall back to a full
      // wipe rather than leaving session cookies behind.
      try {
        await CookieManager.instance().deleteAllCookies();
      } catch (_) {}
    }
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
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if (_isUnauthenticatedResponse(json)) {
          // During the post-login grace window (≤30 s after saveSession) the
          // warm request may race cookie propagation and return unauthenticated
          // even though the session is valid. Suppress the auth-expiry signal
          // so the user isn't incorrectly kicked back to the login sheet.
          if (_inPostLoginGrace) {
            debugPrint(
              '[YTM_ACCOUNT] Warm-session unauthenticated response suppressed '
              '(within 30 s post-login grace window) — session kept.',
            );
            return;
          }
          debugPrint(
            '[YTM_ACCOUNT] Warmed session returned unauthenticated — keeping session, notifying expiry check',
          );
          getIt<YtmService>().notifyAuthExpired();
          return;
        }
        try {
          _harvestSessionState(json);
        } catch (_) {}
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


  /// Splits a (possibly comma-merged) Set-Cookie header into individual
  /// cookies without breaking on `Expires=Wed, 21 Oct ...` dates: a comma only
  /// Robust splitting of comma-delimited Set-Cookie headers while respecting
  /// expires dates containing commas (e.g. `Expires=Wed, 21 Oct 2026 07:28:00 GMT`).
  static List<String> splitSetCookies(String header) {
    final results = <String>[];
    int start = 0;
    bool inExpires = false;
    for (int i = 0; i < header.length; i++) {
      if (i + 8 <= header.length &&
          header.substring(i, i + 8).toLowerCase() == 'expires=') {
        inExpires = true;
      }
      if (header[i] == ';') {
        inExpires = false;
      }
      if (header[i] == ',' && !inExpires) {
        final nextPart = header.substring(i + 1).trim();
        final eqIdx = nextPart.indexOf('=');
        final semiIdx = nextPart.indexOf(';');
        if (eqIdx > 0 && (semiIdx == -1 || eqIdx < semiIdx)) {
          results.add(header.substring(start, i).trim());
          start = i + 1;
        }
      }
    }
    if (start < header.length) {
      results.add(header.substring(start).trim());
    }
    return results.where((s) => s.isNotEmpty).toList();
  }

  /// Pure cookie-jar merge: applies a raw Set-Cookie header (possibly several
  /// comma-merged cookies) on top of a `k=v; k2=v2` jar. Static so it can be
  /// unit-tested without DI/network.
  static String mergeSetCookieInto(String current, String setCookieHeader) {
    final map = <String, String>{};
    for (final pair in current.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length >= 2 && parts[0].trim().isNotEmpty) {
        map[parts[0].trim()] = parts.sublist(1).join('=').trim();
      }
    }

    final cookies = splitSetCookies(setCookieHeader);
    for (final cookie in cookies) {
      final segments = cookie.split(';');
      if (segments.isEmpty) continue;

      final nameValue = segments.first.trim();
      final eqIdx = nameValue.indexOf('=');
      if (eqIdx <= 0) continue;

      final name = nameValue.substring(0, eqIdx).trim();
      final value = nameValue.substring(eqIdx + 1).trim();

      bool shouldDelete = false;
      for (int i = 1; i < segments.length; i++) {
        final attr = segments[i].trim().toLowerCase();
        if (attr.startsWith('max-age=')) {
          final maxAge = int.tryParse(attr.substring(8)) ?? 0;
          if (maxAge <= 0) shouldDelete = true;
        }
        if (attr.startsWith('expires=')) {
          try {
            final expires = HttpDate.parse(
              segments[i].trim().substring(8).trim(),
            );
            if (expires.isBefore(DateTime.now())) {
              shouldDelete = true;
            }
          } catch (_) {
            final fallbackExp = DateTime.tryParse(attr.substring(8));
            if (fallbackExp != null && fallbackExp.isBefore(DateTime.now())) {
              shouldDelete = true;
            }
          }
        }
      }

      if (shouldDelete) {
        map.remove(name);
      } else {
        map[name] = value;
      }
    }

    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _ingestSetCookies(String setCookieHeader) {
    final current = _cookies ?? '';
    final merged = mergeSetCookieInto(current, setCookieHeader);
    if (merged.isEmpty || merged == current) return;

    _cookies = merged;
    // Persist via the secure-storage path — never a plaintext prefs copy.
    unawaited(_persistCookies(merged));
    // Keep the native cookie store (used by the extractor) in sync with the
    // refreshed jar so the two layers never drift apart.
    try {
      unawaited(getIt<YtmService>().syncCookies(merged));
    } catch (_) {}
  }

  /// Builds authenticated Innertube request headers with timestamped SAPISIDHASH, SAPISID3PHASH, or SAPISID1PHASH.
  Map<String, String> _buildHeaders({
    String userAgent = '',
    String origin = 'https://music.youtube.com',
  }) {
    final defaultUa =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Safari/537.36';

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': userAgent.isNotEmpty ? userAgent : defaultUa,
      'Origin': origin,
      'Referer': '$origin/',
      'x-origin': origin,
      'x-youtube-client-name': '67',
      'x-youtube-client-version': _clientVersion,
      'x-goog-authuser': '0',
      'X-Goog-Api-Key': _apiKey,
    };

    if (_cookies != null && _cookies!.isNotEmpty) {
      headers['Cookie'] = _cookies!;
      final authHeader = buildAuthorizationHeader(_cookies!, origin: origin);
      if (authHeader != null) {
        headers['Authorization'] = authHeader;
      }
    }

    return headers;
  }

  /// Builds the proper Authorization header for YouTube / Google InnerTube requests.
  /// Supports SAPISID (SAPISIDHASH), __Secure-3PAPISID (SAPISID3PHASH), and __Secure-1PAPISID (SAPISID1PHASH).
  static String? buildAuthorizationHeader(
    String cookies, {
    String origin = 'https://music.youtube.com',
  }) {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final sapisid = _extractCookieValue(cookies, 'SAPISID');
    if (sapisid != null && sapisid.isNotEmpty) {
      final toHash = '$timestamp $sapisid $origin';
      final digest = sha1.convert(utf8.encode(toHash)).toString();
      return 'SAPISIDHASH ${timestamp}_$digest';
    }

    final sapisid3p = _extractCookieValue(cookies, '__Secure-3PAPISID');
    if (sapisid3p != null && sapisid3p.isNotEmpty) {
      final toHash = '$timestamp $sapisid3p $origin';
      final digest = sha1.convert(utf8.encode(toHash)).toString();
      return 'SAPISID3PHASH ${timestamp}_$digest';
    }

    final sapisid1p = _extractCookieValue(cookies, '__Secure-1PAPISID');
    if (sapisid1p != null && sapisid1p.isNotEmpty) {
      final toHash = '$timestamp $sapisid1p $origin';
      final digest = sha1.convert(utf8.encode(toHash)).toString();
      return 'SAPISID1PHASH ${timestamp}_$digest';
    }

    return null;
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

  /// Exact-name session-cookie validation: requires an SAPISID-family cookie
  /// AND a PSID login cookie. Unlike raw substring checks on the whole header,
  /// this cannot be fooled by values that merely contain a cookie name and
  /// never validates an empty value as present.
  static bool looksLikeSignedInCookies(String rawCookies) {
    String? valueOf(String name) {
      for (final pair in rawCookies.split(';')) {
        final parts = pair.trim().split('=');
        if (parts.length >= 2 && parts[0].trim() == name) {
          final v = parts.sublist(1).join('=').trim();
          if (v.isNotEmpty) return v;
        }
      }
      return null;
    }

    final hasSapisid =
        valueOf('SAPISID') != null ||
        valueOf('__Secure-3PAPISID') != null ||
        valueOf('__Secure-1PAPISID') != null;
    final hasPsid =
        valueOf('__Secure-3PSID') != null || valueOf('__Secure-1PSID') != null;
    return hasSapisid && hasPsid;
  }

  Map<String, dynamic> _buildClientContext(
    String clientType, [
    String? videoId,
  ]) {
    final clientMap = <String, dynamic>{
      'clientName': clientType,
      // Use the resolved client version for WEB_REMIX; explicit per-client
      // versions for the named mobile clients; fall back to WEB_REMIX version
      // rather than the stale '19.29.37' for anything else.
      'clientVersion':
          clientType == 'WEB_REMIX'
              ? _clientVersion
              : clientType == 'ANDROID_MUSIC'
              ? '8.32.50'
              : clientType == 'IOS_MUSIC'
              ? '8.32.1'
              : _clientVersion,
      'hl': 'en',
      'gl': 'US',
    };

    if (clientType == 'ANDROID_MUSIC') {
      clientMap['clientVersion'] = '7.27.53';
      clientMap['androidSdkVersion'] = 35;
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '15';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'IOS_MUSIC') {
      clientMap['clientVersion'] = '7.27.0';
      clientMap['deviceMake'] = 'Apple';
      clientMap['deviceModel'] = 'iPhone16,2';
      clientMap['osName'] = 'iOS';
      clientMap['osVersion'] = '18.5';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_VR') {
      clientMap['clientVersion'] = '1.63.27';
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
      clientMap['clientVersion'] = _clientVersion;
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'WEB_EMBEDDED_PLAYER') {
      clientMap['clientVersion'] = _clientVersion;
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

    if (clientType == 'WEB_EMBEDDED_PLAYER' ||
        clientType == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER') {
      contextJson['thirdParty'] = {
        'embedUrl':
            (videoId != null && videoId.isNotEmpty)
                ? 'https://www.youtube.com/watch?v=$videoId'
                : 'https://www.youtube.com',
      };
    }

    return contextJson;
  }

  Future<http.Response> _postWithRetry(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    int maxAttempts = 3,
    int baseTimeoutSeconds = 15,
    // Native RateLimiter.Bucket name (SEARCH/BROWSE/PLAYER/STREAM/DOWNLOAD).
    // Player-endpoint calls must use the PLAYER bucket (5 tokens / 2 per s /
    // 200ms gap) so play-path requests are not paced behind browse traffic.
    String bucket = 'BROWSE',
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      try {
        try {
          await _channel.invokeMethod<bool>('acquirePermit', {
            'bucket': bucket,
          });
        } catch (_) {}
        final timeout = Duration(seconds: baseTimeoutSeconds + attempt * 5);
        final res = await http
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
        final elapsed = DateTime.now().millisecondsSinceEpoch - startTime;

        if (res.statusCode == 429 || res.statusCode >= 500) {
          try {
            await _channel.invokeMethod<bool>('recordMetric', {
              'operation': 'account.post',
              'latencyMs': elapsed,
              'isError': true,
            });
          } catch (_) {}

          if (res.statusCode == 429) {
            final retryHeader = res.headers['retry-after'];
            final retryAfter = int.tryParse(retryHeader ?? '');
            try {
              await _channel.invokeMethod<int>('onRateLimited', {
                'retryAfter': retryAfter,
              });
            } catch (_) {}
          }
          final backoffSec = (1 << attempt) + Random().nextInt(2);
          debugPrint(
            '[YTM_ACCOUNT] HTTP ${res.statusCode} encountered. Backing off for ${backoffSec}s (attempt ${attempt + 1}/$maxAttempts)',
          );
          if (attempt < maxAttempts - 1) {
            await Future<void>.delayed(Duration(seconds: backoffSec));
            continue;
          }
          if (res.statusCode == 429) {
            throw const YtmException(
              'RATE_LIMITED',
              'YouTube Music rate limit reached',
            );
          } else {
            throw YtmException(
              'HTTP_${res.statusCode}',
              'Server returned HTTP ${res.statusCode}',
            );
          }
        }

        // Only record success for valid, non-rate-limited, non-5xx responses
        try {
          await _channel.invokeMethod<bool>('onSuccess');
          await _channel.invokeMethod<bool>('recordMetric', {
            'operation': 'account.post',
            'latencyMs': elapsed,
            'isError': false,
          });
        } catch (_) {}
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
            debugPrint(
              '[YTM_ACCOUNT] Unauthenticated response detected on $bId',
            );
            await logout();
            throw const YtmException('YTM_AUTH', 'Session expired');
          }

          _harvestSessionState(json);
          final playlists = _parseInnertubeAccountPlaylists(json);
          if (playlists.isNotEmpty) {
            return playlists;
          }
        }
      } catch (e) {
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint(
          '[YTM_ACCOUNT] Failed fetching account playlists ($bId): $e',
        );
      }
    }
    return [];
  }

  /// Fetches private Liked Music playlist (`VLLM`, `FEmusic_liked_videos`, `LM`).
  Future<List<YtmTrack>> fetchLikedSongs({int maxTracks = 200}) async {
    if (!isLoggedIn) {
      throw const YtmException('YTM_AUTH', 'Not signed in to YouTube Music');
    }

    final coalesceKey = 'fetchLikedSongs:$maxTracks';
    final inFlight = _inFlightLikedSongs[coalesceKey];
    if (inFlight != null) return inFlight;

    final future = _fetchLikedSongsInternal(maxTracks: maxTracks);
    _inFlightLikedSongs[coalesceKey] = future;
    try {
      return await future;
    } finally {
      // ignore: unawaited_futures - remove returns the Future value, not a new async op
      _inFlightLikedSongs.remove(coalesceKey);
    }
  }

  Future<List<YtmTrack>> _fetchLikedSongsInternal({required int maxTracks}) async {
    // Refresh cookies from native CookieManager if needed
    final nativeCookies = await getNativeCookiesFromDomains();
    if (nativeCookies != null &&
        nativeCookies.isNotEmpty &&
        looksLikeSignedInCookies(nativeCookies)) {
      _cookies = nativeCookies;
      unawaited(_persistCookies(nativeCookies));
    }

    final headers = _buildHeaders();
    final orderedBrowseIds =
        {
          if (_cachedLikedSongsBrowseId != null) _cachedLikedSongsBrowseId!,
          'VLLM',
          'FEmusic_liked_videos',
          'FEmusic_liked_tracks',
          'LM',
          'VLSE',
        }.toList();

    for (final bId in orderedBrowseIds) {
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

        debugPrint(
          '[YTM_ACCOUNT] Liked songs query $bId: HTTP ${response.statusCode}, body length=${response.body.length}',
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json)) {
            debugPrint(
              '[YTM_ACCOUNT] Liked songs returned unauthenticated on $bId, trying next candidate',
            );
            continue;
          }

          _harvestSessionState(json);
          final tracks = _parseInnertubePlaylistTracks(json);
          debugPrint(
            '[YTM_ACCOUNT] Liked songs query $bId parsed ${tracks.length} tracks'
            ' (top-level keys: ${json.keys.take(8).join(', ')})',
          );

          if (tracks.isEmpty) {
            debugPrint(
              '[YTM_ACCOUNT] Liked songs query $bId returned 0 tracks. RAW BODY:\n${response.body}',
            );
            // YouTube Music frequently delivers the liked-songs list only via
            // continuation — the initial browse response is a header shell.
            final initToken = _extractContinuationToken(json);
            if (initToken != null && initToken.isNotEmpty) {
              debugPrint(
                '[YTM_ACCOUNT] Initial browse had 0 tracks but continuation found, fetching...',
              );
              final contBody = jsonEncode({
                'context': _buildClientContext('WEB_REMIX'),
                'continuation': initToken,
              });
              final contRes = await _postWithRetry(
                Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                headers: headers,
                body: contBody,
              );
              if (contRes.statusCode == 200) {
                final contJson =
                    jsonDecode(contRes.body) as Map<String, dynamic>;
                final contTracks = _parseInnertubePlaylistTracks(contJson);
                debugPrint(
                  '[YTM_ACCOUNT] Browse initial continuation parsed ${contTracks.length} tracks',
                );
                if (contTracks.isNotEmpty) {
                  tracks.addAll(contTracks);
                } else {
                  debugPrint(
                    '[YTM_ACCOUNT] Continuation body returned 0 tracks. RAW:\n${contRes.body}',
                  );
                }
              }
            }
          }

          if (tracks.isNotEmpty) {
            _cachedLikedSongsBrowseId = bId;
            final allTracks = List<YtmTrack>.from(tracks);
            var currentJson = json;

            // Fetch continuation pages until *unique* tracks satisfy maxTracks.
            // Guard against YouTube returning the same token on an empty page
            // (which would otherwise spin 20 identical requests).
            var pageCount = 0;
            const maxPages = 20;
            final seenTokens = <String>{};
            final seenIdsForPaging = <String>{for (final t in allTracks) t.videoId};
            while (seenIdsForPaging.length < maxTracks && pageCount < maxPages) {
              pageCount++;
              try {
                final ctoken = _extractContinuationToken(currentJson);
                if (ctoken == null || ctoken.isEmpty) break;
                if (!seenTokens.add(ctoken)) {
                  debugPrint('[YTM_ACCOUNT] Duplicate continuation token $ctoken — breaking loop');
                  break;
                }

                final contBody = jsonEncode({
                  'context': _buildClientContext('WEB_REMIX'),
                  'continuation': ctoken,
                });

                final contResponse = await _postWithRetry(
                  Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                  headers: headers,
                  body: contBody,
                );

                if (contResponse.statusCode == 200) {
                  currentJson =
                      jsonDecode(contResponse.body) as Map<String, dynamic>;
                  final contTracks = _parseInnertubePlaylistTracks(currentJson);
                  if (contTracks.isEmpty) break;
                  for (final ct in contTracks) {
                    if (seenIdsForPaging.add(ct.videoId)) {
                      allTracks.add(ct);
                    }
                  }
                  if (seenIdsForPaging.length >= maxTracks) break;
                } else {
                  break;
                }
              } catch (e) {
                debugPrint(
                  '[YTM_ACCOUNT] Liked songs continuation error on page $pageCount: $e',
                );
                break;
              }
            }
            if (pageCount >= maxPages) {
              debugPrint(
                '[YTM_ACCOUNT] Hit max continuation pages ($maxPages)',
              );
            }

            // Final dedup (covers initial tracks dupes)
            final seenIds = <String>{};
            final uniqueTracks = <YtmTrack>[];
            for (final t in allTracks) {
              if (seenIds.add(t.videoId)) {
                uniqueTracks.add(t);
              }
            }
            return uniqueTracks.take(maxTracks).toList();
          }
        }
      } catch (e) {
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint('[YTM_ACCOUNT] Liked songs fetch failed for $bId: $e');
      }
    }

    // Try /next with playlistId: 'LM' / 'VLLM' (YouTube Music Queue / Liked playlist endpoint)
    final nextPlaylistIds = ['LM', 'VLLM', 'FEmusic_liked_videos'];
    for (final pId in nextPlaylistIds) {
      try {
        final body = jsonEncode({
          'context': _buildClientContext('WEB_REMIX'),
          'playlistId': pId,
          'enablePersistentPlaylistPanel': true,
          'isAudioOnly': true,
        });
        final response = await _postWithRetry(
          Uri.parse(
            'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey',
          ),
          headers: headers,
          body: body,
        );
        debugPrint(
          '[YTM_ACCOUNT] Next endpoint query $pId: HTTP ${response.statusCode}, length=${response.body.length}',
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final tracks = _parseInnertubePlaylistTracks(json);
          debugPrint(
            '[YTM_ACCOUNT] Next endpoint query $pId parsed ${tracks.length} tracks',
          );
          if (tracks.isNotEmpty) {
            return tracks.take(maxTracks).toList();
          } else {
            debugPrint(
              '[YTM_ACCOUNT] Next endpoint $pId raw body:\n${response.body}',
            );
          }
        }
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Next endpoint query error for $pId: $e');
      }
    }

    // Fallback: discover Liked Songs playlist directly from user's account library
    try {
      final playlists = await fetchAccountPlaylists();
      debugPrint(
        '[YTM_ACCOUNT] Discovered ${playlists.length} account playlists for liked songs resolution',
      );
      for (final p in playlists) {
        final lowerTitle = p.title.toLowerCase();
        final isLiked =
            p.playlistId.contains('LM') ||
            lowerTitle.contains('like') ||
            lowerTitle.contains('aimé') ||
            lowerTitle.contains('favori') ||
            lowerTitle.contains('j\'aime') ||
            lowerTitle.contains('liebling');
        if (isLiked) {
          debugPrint(
            '[YTM_ACCOUNT] Found Liked Music playlist in account: ${p.playlistId} (${p.title})',
          );
          final candidateIds = [p.playlistId, 'VL${p.cleanPlaylistId}'];
          for (final cId in candidateIds) {
            final body = jsonEncode({
              'context': _buildClientContext('WEB_REMIX'),
              'browseId': cId,
            });
            final res = await _postWithRetry(
              Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
              headers: headers,
              body: body,
            );
            if (res.statusCode == 200) {
              final json = jsonDecode(res.body) as Map<String, dynamic>;
              final tracks = _parseInnertubePlaylistTracks(json);
              if (tracks.isNotEmpty) {
                return tracks.take(maxTracks).toList();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Account playlists liked resolution error: $e');
    }

    // Try Native Kotlin Innertube browse with full WebView cookie jar
    try {
      debugPrint(
        '[YTM_ACCOUNT] Attempting Native Kotlin Innertube fallback for liked songs...',
      );
      final ytmService = getIt<YtmService>();
      final nativeTracks = await ytmService.getPlaylistTracks(
        'VLLM',
        limit: maxTracks,
      );
      if (nativeTracks.isNotEmpty) {
        debugPrint(
          '[YTM_ACCOUNT] Native Kotlin fallback returned ${nativeTracks.length} liked songs',
        );
        return nativeTracks.take(maxTracks).toList();
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Native Kotlin fallback failed: $e');
    }

    // Last resort: XDM yt-dlp backend — passes authenticated cookies server-side
    // via the cookie pool and can access private playlists that InnerTube rejects.
    try {
      debugPrint(
        '[YTM_ACCOUNT] Attempting XDM backend fallback for liked songs...',
      );
      final xdm = getIt<XdmBackendService>();
      if (await xdm.isEnabled()) {
        var tracks = await xdm.getPlaylist(
          'https://www.youtube.com/playlist?list=LL',
          limit: maxTracks,
          cookies: _cookies,
        );
        if (tracks.isEmpty) {
          tracks = await xdm.getPlaylist(
            'https://music.youtube.com/playlist?list=LM',
            limit: maxTracks,
            cookies: _cookies,
          );
        }
        if (tracks.isNotEmpty) {
          debugPrint(
            '[YTM_ACCOUNT] XDM backend returned ${tracks.length} liked songs',
          );
          return tracks.take(maxTracks).toList();
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] XDM backend fallback failed: $e');
    }

    return [];
  }

  /// Fetches personalized recommendations and home feed from YouTube Music (`FEmusic_home`).
  Future<List<YtmTrack>> fetchHomeRecommendations({int maxTracks = 50}) async {
    if (!isLoggedIn) return [];

    final nativeCookies = await getNativeCookiesFromDomains();
    if (nativeCookies != null &&
        nativeCookies.isNotEmpty &&
        looksLikeSignedInCookies(nativeCookies)) {
      _cookies = nativeCookies;
      unawaited(_persistCookies(nativeCookies));
    }

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
          _harvestSessionState(json);
          final tracks = _parseInnertubePlaylistTracks(json);

          if (tracks.isEmpty) {
            final initToken = _extractContinuationToken(json);
            if (initToken != null && initToken.isNotEmpty) {
              final contBody = jsonEncode({
                'context': _buildClientContext('WEB_REMIX'),
                'continuation': initToken,
              });
              final contRes = await _postWithRetry(
                Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                headers: headers,
                body: contBody,
              );
              if (contRes.statusCode == 200) {
                final contJson =
                    jsonDecode(contRes.body) as Map<String, dynamic>;
                final contTracks = _parseInnertubePlaylistTracks(contJson);
                if (contTracks.isNotEmpty) {
                  tracks.addAll(contTracks);
                }
              }
            }
          }

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
        Uri.parse(
          'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey',
        ),
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
      final id = lyricsBrowseId;
      if (id == null || !id.startsWith('MPLYt')) return null;

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
              lines.addAll(
                LrcParser.parsePlainText(
                  plainText,
                  source: LyricsSource.ytmusic,
                ),
              );
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
  Future<YtmStream?> resolvePlayerStream(
    String videoId, {
    String quality = 'high',
  }) async {
    try {
      return await _resolvePlayerStreamInternal(
        videoId,
        quality: quality,
      ).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      debugPrint(
        '[YTM_ACCOUNT] Global stream resolution timed out after 25s for $videoId',
      );
      return null;
    }
  }

  Future<YtmStream?> _resolvePlayerStreamInternal(
    String videoId, {
    String quality = 'high',
  }) async {
    // BotGuard requires a poToken on WEB_REMIX player requests regardless of login.
    // Authenticated → the token must be content-bound to the account's datasyncId, sent WITH
    // the session cookies + SAPISIDHASH. Unauthenticated → a guest token bound to guest visitorData.
    final isAuthenticated =
        isLoggedIn && _cookies != null && _cookies!.isNotEmpty;

    // Run ensurePoTokenReady and datasyncId bootstrap in parallel — they have
    // no dependency on each other. Saves ~200-400ms on cold resolves.
    await Future.wait([
      Future(() async {
        try {
          await getIt<YtmService>().ensurePoTokenReady();
        } catch (_) {}
      }),
      Future(() async {
        if (isAuthenticated &&
            (_dataSyncId == null || _dataSyncId!.isEmpty)) {
          try {
            await _bootstrapDataSyncId();
          } catch (_) {}
        }
      }),
    ]);

    String? poToken;
    String? visitorData;
    if (isAuthenticated) {
      final dsid = _dataSyncId;
      if (dsid != null && dsid.isNotEmpty) {
        try {
          final account = await getIt<YtmService>().getAccountPoToken(dsid);
          poToken = account?['poToken'] as String?;
          final vd = account?['visitorData'] as String?;
          visitorData =
              _sessionVisitorData ?? (vd != null && vd.isNotEmpty ? vd : null);
        } catch (e) {
          debugPrint('[YTM_ACCOUNT] Account poToken minting failed: $e');
        }
      } else {
        visitorData = _sessionVisitorData;
      }
    } else {
      try {
        final poState = await getIt<YtmService>().getPoTokenState();
        poToken = poState?['streamingPoToken'] as String?;
        visitorData = poState?['visitorData'] as String?;
      } catch (_) {}
    }
    // Diagnostics: every bot-gate log below reports whether a token was
    // actually attached, so "WEB_REMIX bot challenge" is immediately
    // attributable to missing attestation vs rejected attestation.
    final hadPoToken = poToken != null && poToken.isNotEmpty;

    final clientChain =
        isAuthenticated
            ? [
              'WEB_REMIX', // cookies + poToken → most reliable
              'ANDROID_VR', // fallback unauthenticated
              'IOS_MUSIC',
              'ANDROID_MUSIC',
            ]
            : [
              'ANDROID_VR',
              'IOS_MUSIC',
              'ANDROID_MUSIC',
              'WEB_REMIX',
            ];

    for (final client in clientChain) {
      try {
        final isWeb =
            client == 'WEB_REMIX' ||
            client == 'WEB_EMBEDDED_PLAYER' ||
            client == 'MWEB' ||
            client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER';
        final endpointHost =
            (client == 'ANDROID_MUSIC' ||
                    client == 'IOS_MUSIC' ||
                    client == 'WEB_REMIX')
                ? 'https://music.youtube.com'
                : (client == 'MWEB'
                    ? 'https://m.youtube.com'
                    : 'https://www.youtube.com');

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          'x-youtube-client-name': _clientNameIds[client] ?? '67',
          'x-youtube-client-version':
              client == 'ANDROID_MUSIC'
                  ? '7.27.53'
                  : (client == 'IOS_MUSIC'
                      ? '7.27.0'
                      : (client == 'ANDROID_VR'
                          ? '1.63.27'
                          : (client == 'MWEB'
                              ? _clientVersion
                              : (client == 'WEB_EMBEDDED_PLAYER'
                                  ? _clientVersion
                                  : (client == 'ANDROID_CREATOR'
                                      ? '24.45.100'
                                      : (client ==
                                              'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
                                          ? '2.0'
                                          : (client == 'ANDROID_TESTSUITE'
                                              ? '1.9'
                                              : _clientVersion))))))),
          'User-Agent':
              client == 'ANDROID_MUSIC'
                  ? 'com.google.android.apps.youtube.music/7.27.53 (Linux; U; Android 15; en_US) gzip'
                  : (client == 'IOS_MUSIC'
                      ? 'com.google.ios.youtubemusic/7.27.0 (iPhone16,2; U; CPU iOS 18_5 like Mac OS X; en_US)'
                      : (client == 'ANDROID_VR'
                          ? 'com.google.android.apps.youtube.vr.oculus/1.63.27 (Linux; U; Android 12; en_US; Quest 3) gzip'
                          : (client == 'ANDROID_CREATOR'
                              ? 'com.google.android.apps.youtube.creator/24.45.100 (Linux; U; Android 14; en_US) gzip'
                              : (client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
                                  ? 'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36'
                                  : (client == 'ANDROID_TESTSUITE'
                                      ? 'com.google.android.youtube/1.9 (Linux; U; Android 9; gzip)'
                                      : (client == 'MWEB'
                                          ? 'Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Mobile Safari/537.36'
                                          : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.7151.119 Safari/537.36')))))),
        };

        if (visitorData != null && visitorData.isNotEmpty) {
          headers['X-Goog-Visitor-Id'] = visitorData;
        }

        if (isWeb) {
          final origin = endpointHost;
          headers['Origin'] = origin;
          headers['Referer'] = '$origin/';
          headers['X-Origin'] = origin;
          headers['x-origin'] = origin;
          headers['x-goog-authuser'] = '0';
          if (_cookies != null && _cookies!.isNotEmpty) {
            headers['Cookie'] = _cookies!;
            final authHeader = buildAuthorizationHeader(
              _cookies!,
              origin: origin,
            );
            if (authHeader != null) {
              headers['Authorization'] = authHeader;
            }
          }
        } else {
          headers['X-Origin'] = endpointHost;
        }

        final clientContext = _buildClientContext(client, videoId);
        if (visitorData != null &&
            visitorData.isNotEmpty &&
            clientContext.containsKey('client') &&
            clientContext['client'] is Map) {
          (clientContext['client'] as Map)['visitorData'] = visitorData;
        }

        final body = jsonEncode({
          'context': clientContext,
          'videoId': videoId,
          'racyCheckOk': true,
          'contentCheckOk': true,
          // Web clients attest via root-level serviceIntegrityDimensions;
          // mobile clients read playbackContext.contentPlaybackContext.poToken.
          // Sending both keeps every client in the chain covered.
          if (isWeb && poToken != null && poToken.isNotEmpty)
            'serviceIntegrityDimensions': {'poToken': poToken},
          'playbackContext': {
            'contentPlaybackContext': {
              'html5Preference': 'HTML5_PREF_WANTS',
              if (poToken != null && poToken.isNotEmpty) 'poToken': poToken,
            },
          },
        });

        final response = await _postWithRetry(
          Uri.parse(
            '$endpointHost/youtubei/v1/player?prettyPrint=false&key=$_apiKey',
          ),
          headers: headers,
          body: body,
          baseTimeoutSeconds: 10,
          bucket: 'PLAYER',
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final playability =
              data['playabilityStatus'] as Map<String, dynamic>?;
          final status = playability?['status'] as String? ?? '';

          if (status == 'LOGIN_REQUIRED' ||
              status == 'UNPLAYABLE' ||
              status.contains('BOT')) {
            final statusReason =
                playability?['reason'] as String? ?? 'no reason';
            debugPrint(
              '[YTM_ACCOUNT] Client $client returned playability $status ($statusReason, poTokenAttached: $hadPoToken), falling back to next',
            );

            // If WEB_REMIX (the client using auth cookies) returns LOGIN_REQUIRED,
            // check whether it's a genuine session expiry or just a bot challenge.
            // Bot challenges say "Sign in to confirm you're not a bot" — don't logout for those.
            if (client == 'WEB_REMIX' &&
                status == 'LOGIN_REQUIRED' &&
                _cookies != null &&
                _cookies!.isNotEmpty) {
              final reason =
                  (playability?['reason'] as String? ?? '').toLowerCase();
              final isBotChallenge =
                  reason.contains('bot') || reason.contains('confirm');
              if (!isBotChallenge) {
                // During the post-login grace window (≤30 s) the WEB_REMIX
                // player request can return LOGIN_REQUIRED because the poToken
                // hasn't been minted for the new account yet, or because the
                // cookies haven't fully propagated to the YTM domain. Treat
                // this as a transient failure and fall through to the next
                // client instead of wiping the session that was JUST saved.
                if (_inPostLoginGrace) {
                  debugPrint(
                    '[YTM_ACCOUNT] WEB_REMIX LOGIN_REQUIRED suppressed '
                    '(within 30 s post-login grace window) — trying next client.',
                  );
                  continue;
                }
                // Genuine session expiry outside the grace window: notify the
                // UI so the user gets the re-login snackbar. Do NOT call
                // logout() here — that races with saveSession() on fresh logins
                // and wipes valid cookies. The session will be cleaned up via
                // the normal logout flow when the user explicitly signs out or
                // when the app validates the session on the next cold start.
                debugPrint(
                  '[YTM_ACCOUNT] Session expired detected on WEB_REMIX. Notifying UI.',
                );
                try {
                  getIt<YtmService>().notifyAuthExpired();
                } catch (_) {}

                throw const YtmException(
                  'YTM_AUTH',
                  'YouTube Music session expired. Please sign in again.',
                );
              }
              debugPrint(
                '[YTM_ACCOUNT] WEB_REMIX bot challenge detected, trying next client without logout',
              );
            }
            continue;

          }

          final streamingData = data['streamingData'] as Map<String, dynamic>?;
          final adaptive =
              (streamingData?['adaptiveFormats'] as List<dynamic>? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .toList();

          final audioFormats = <({Map<String, dynamic> format, String url})>[];
          for (final f in adaptive) {
            final mime = f['mimeType'] as String? ?? '';
            final streamUrl = _extractUrlFromFormat(f);
            if (mime.startsWith('audio/') &&
                streamUrl != null &&
                streamUrl.isNotEmpty) {
              audioFormats.add((format: f, url: streamUrl));
            }
          }

          if (audioFormats.isNotEmpty) {
            final m4a =
                audioFormats
                    .where(
                      (f) => ((f.format['mimeType'] as String?) ?? '').contains(
                        'mp4',
                      ),
                    )
                    .toList();
            final pool = m4a.isNotEmpty ? m4a : audioFormats;

            final selected = switch (quality.toLowerCase()) {
              'low' => pool.reduce(
                (a, b) =>
                    ((a.format['bitrate'] as num?) ?? 0) <
                            ((b.format['bitrate'] as num?) ?? 0)
                        ? a
                        : b,
              ),
              'medium' => pool.reduce(
                (a, b) =>
                    (((a.format['bitrate'] as num?) ?? 128000) - 128000).abs() <
                            (((b.format['bitrate'] as num?) ?? 128000) - 128000)
                                .abs()
                        ? a
                        : b,
              ),
              _ => pool.reduce(
                (a, b) =>
                    ((a.format['bitrate'] as num?) ?? 0) >
                            ((b.format['bitrate'] as num?) ?? 0)
                        ? a
                        : b,
              ),
            };

            final mime = selected.format['mimeType'] as String? ?? 'audio/mp4';
            final bitrate =
                (selected.format['bitrate'] as num?)?.toInt() ?? 128000;
            final durationMs =
                int.tryParse(
                  selected.format['approxDurationMs']?.toString() ?? '0',
                ) ??
                0;
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
              cookies:
                  (isWeb || client == 'ANDROID_MUSIC' || client == 'IOS_MUSIC')
                      ? _cookies
                      : null,
            );
          } else {
            debugPrint(
              '[YTM_ACCOUNT] Client $client returned status $status but no audio formats (adaptiveFormats: ${adaptive.length} total, streamingData: ${streamingData != null})',
            );
          }
        }
      } catch (e) {
        // Session-expiry must surface to callers/UI, not be swallowed as a
        // per-client resolution failure.
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint(
          '[YTM_ACCOUNT] Client $client resolution error for $videoId: $e',
        );
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
    final rc = json['responseContext'];
    if (rc is Map<String, dynamic>) {
      final mainApp = rc['mainAppWebResponseContext'];
      if (mainApp is Map<String, dynamic>) {
        if (mainApp['loggedOut'] == true) return true;
        if (mainApp['datasyncId'] != null &&
            (mainApp['datasyncId'] as String).isNotEmpty) {
          return false;
        }
      }
    }
    if (json.containsKey('contents') ||
        json.containsKey('header') ||
        json.containsKey('continuationContents') ||
        json.containsKey('onResponseReceivedActions') ||
        json.containsKey('frameworkUpdates')) {
      return false;
    }
    final alerts = json['alerts'];
    if (alerts is List) {
      for (final a in alerts) {
        final alertText = a.toString().toLowerCase();
        if (alertText.contains('sign in') || alertText.contains('login')) {
          return true;
        }
      }
    }
    return false;
  }

  String? _extractContinuationToken(dynamic node) {
    if (node is Map<String, dynamic>) {
      // Canonical format: nextContinuationData.continuation
      if (node.containsKey('nextContinuationData')) {
        return node['nextContinuationData']?['continuation'] as String?;
      }
      if (node.containsKey('reloadContinuationData')) {
        return node['reloadContinuationData']?['continuation'] as String?;
      }
      // Newer InnerTube format: continuationEndpoint.continuationCommand.token
      if (node.containsKey('continuationEndpoint')) {
        final token =
            node['continuationEndpoint']?['continuationCommand']?['token']
                as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('continuationCommand')) {
        return node['continuationCommand']?['token'] as String?;
      }
      if (node.containsKey('nextRadioContinuationData')) {
        return node['nextRadioContinuationData']?['continuation'] as String?;
      }
      for (final val in node.values) {
        final token = _extractContinuationToken(val);
        if (token != null) return token;
      }
    } else if (node is List) {
      for (final item in node) {
        final token = _extractContinuationToken(item);
        if (token != null) return token;
      }
    }
    return null;
  }

  /// Reads the account `datasyncId` from `responseContext.mainAppWebResponseContext.datasyncId`.
  /// This is the raw content-binding for the account poToken (kept verbatim, incl. trailing `||`).
  String? _extractDataSyncId(Map<String, dynamic> json) {
    final rc = json['responseContext'];
    if (rc is! Map<String, dynamic>) return null;
    final mainApp = rc['mainAppWebResponseContext'];
    if (mainApp is! Map<String, dynamic>) return null;
    final id = mainApp['datasyncId'];
    if (id is String && id.isNotEmpty) return id;
    return null;
  }

  /// Opportunistically harvests session state (datasyncId, visitorData) from an authenticated
  /// Innertube response. Persists a new datasyncId and seeds it into the native PoTokenManager so
  /// the account-bound token re-mints against the current account.
  void _harvestSessionState(Map<String, dynamic> json) {
    final dsid = _extractDataSyncId(json);
    if (dsid != null && dsid != _dataSyncId) {
      _dataSyncId = dsid;
      _sessionHarvestDebounce?.cancel();
      _sessionHarvestDebounce = null;
      SharedPreferences.getInstance()
          .then((p) {
            p.setString(_dataSyncIdPrefKey, dsid);
          })
          .catchError((Object e) {
            debugPrint('[YTM_ACCOUNT] Failed to persist dataSyncId: $e');
          });
      getIt<YtmService>().setDataSyncId(dsid);
    }
    final rc = json['responseContext'];
    if (rc is Map<String, dynamic>) {
      final vd = rc['visitorData'];
      if (vd is String && vd.isNotEmpty) {
        _sessionVisitorData = vd;
      }
    }
  }

  /// Bootstraps [_dataSyncId] with one lightweight authenticated `browse` call when it is unknown
  /// (e.g. right after login before any library fetch). The datasyncId is present on any
  /// authenticated response, so a home browse is enough to harvest it.
  Future<void> _bootstrapDataSyncId() async {
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
        baseTimeoutSeconds: 8,
      );
      if (res.statusCode == 200) {
        _harvestSessionState(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] datasyncId bootstrap failed: $e');
    }
  }

  List<YtmTrack> _parseInnertubePlaylistTracks(Map<String, dynamic> root) {
    final tracks = <YtmTrack>[];

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        // ── Leaf renderers: parse & stop recursion ──────────────────────────
        if (node.containsKey('musicResponsiveListItemRenderer')) {
          final renderer =
              node['musicResponsiveListItemRenderer'] as Map<String, dynamic>;
          final track = _parseListItemRenderer(renderer);
          if (track != null) tracks.add(track);
          return;
        }
        // ── Container renderers: traverse contents without stopping ─────────
        // YouTube Music now wraps liked-songs tracks inside
        // musicPlaylistShelfRenderer.contents[] and musicShelfRenderer.contents[].
        // Do NOT return after traversing these — fall through to the values loop.
        if (node.containsKey('musicPlaylistShelfRenderer')) {
          final shelf =
              node['musicPlaylistShelfRenderer'] as Map<String, dynamic>;
          final contents = shelf['contents'];
          if (contents is List) {
            for (final item in contents) {
              traverse(item);
            }
          }
          return;
        }
        if (node.containsKey('musicShelfRenderer')) {
          final shelf = node['musicShelfRenderer'] as Map<String, dynamic>;
          final contents = shelf['contents'];
          if (contents is List) {
            for (final item in contents) {
              traverse(item);
            }
          }
          return;
        }
        if (node.containsKey('playlistPanelVideoRenderer')) {
          final renderer =
              node['playlistPanelVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
          final title =
              titleRuns?.isNotEmpty == true
                  ? titleRuns![0]['text'] as String? ?? 'Unknown Title'
                  : 'Unknown Title';
          final artistRuns =
              renderer['shortBylineText']?['runs'] as List<dynamic>?;
          final artist =
              artistRuns?.isNotEmpty == true
                  ? artistRuns![0]['text'] as String? ?? 'Unknown Artist'
                  : 'Unknown Artist';
          final lengthRuns = renderer['lengthText']?['runs'] as List<dynamic>?;
          final lengthText =
              lengthRuns?.isNotEmpty == true
                  ? lengthRuns![0]['text'] as String?
                  : null;
          int durationMs = 0;
          if (lengthText != null) {
            final parts =
                lengthText.split(':').map((e) => int.tryParse(e) ?? 0).toList();
            if (parts.length == 2) {
              durationMs = (parts[0] * 60 + parts[1]) * 1000;
            } else if (parts.length == 3) {
              durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
            }
          }
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork =
              thumbnails?.isNotEmpty == true
                  ? thumbnails!.last['url'] as String?
                  : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(
              YtmTrack(
                videoId: videoId,
                title: title,
                artist: artist,
                duration: Duration(milliseconds: durationMs),
                artworkUrl: artwork,
              ),
            );
          }
          return;
        } else if (node.containsKey('playlistVideoRenderer')) {
          final renderer =
              node['playlistVideoRenderer'] as Map<String, dynamic>;
          final videoId = renderer['videoId'] as String?;
          final title =
              renderer['title']?['runs']?[0]?['text'] as String? ??
              'Unknown Title';
          final artist =
              renderer['shortBylineText']?['runs']?[0]?['text'] as String? ??
              'Unknown Artist';
          final lengthSeconds =
              int.tryParse(renderer['lengthSeconds']?.toString() ?? '0') ?? 0;
          final thumbnails =
              renderer['thumbnail']?['thumbnails'] as List<dynamic>?;
          final artwork =
              thumbnails?.isNotEmpty == true
                  ? thumbnails!.last['url'] as String?
                  : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(
              YtmTrack(
                videoId: videoId,
                title: title,
                artist: artist,
                duration: Duration(seconds: lengthSeconds),
                artworkUrl: artwork,
              ),
            );
          }
          return;
        } else if (node.containsKey('musicTwoRowItemRenderer')) {
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          String? vid =
              renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
                  as String?;
          vid ??=
              renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['navigationEndpoint']?['watchEndpoint']?['videoId']
                  as String?;
          vid ??=
              renderer['thumbnailOverlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
                  as String?;
          vid ??=
              renderer['navigationEndpoint']?['watchPlaylistEndpoint']?['videoId']
                  as String?;
          vid ??= renderer['onTap']?['watchEndpoint']?['videoId'] as String?;

          if (vid != null && vid.length == 11) {
            final titleRuns = renderer['title']?['runs'] as List<dynamic>?;
            final title =
                titleRuns?.isNotEmpty == true
                    ? titleRuns![0]['text'] as String? ?? 'Unknown Title'
                    : 'Unknown Title';

            String artist = 'Unknown Artist';
            int durationMs = 0;

            final subRuns = renderer['subtitle']?['runs'] as List<dynamic>?;
            if (subRuns != null && subRuns.isNotEmpty) {
              final texts =
                  subRuns
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
            final thumbRenderer =
                renderer['thumbnailRenderer']?['musicThumbnailRenderer'] ??
                renderer['thumbnail']?['musicThumbnailRenderer'];
            final thumbs =
                (thumbRenderer?['thumbnail']?['thumbnails'] ??
                        renderer['thumbnail']?['thumbnails'])
                    as List<dynamic>?;
            if (thumbs != null && thumbs.isNotEmpty) {
              artworkUrl = thumbs.last['url'] as String?;
              if (artworkUrl != null) {
                artworkUrl = artworkUrl.replaceAll(
                  RegExp(r'=w\d+-h\d+[^?]*'),
                  '=s1200',
                );
                artworkUrl = artworkUrl.replaceAll(
                  RegExp(r'=s\d+[^?]*'),
                  '=s1200',
                );
              }
            }

            tracks.add(
              YtmTrack(
                videoId: vid,
                title: title,
                artist: artist,
                duration: Duration(milliseconds: durationMs),
                artworkUrl: artworkUrl,
              ),
            );
            return;
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
    return tracks;
  }

  YtmTrack? _parseListItemRenderer(Map<String, dynamic> renderer) {
    try {
      final playlistItemData =
          renderer['playlistItemData'] as Map<String, dynamic>?;
      String? videoId = playlistItemData?['videoId'] as String?;

      videoId ??=
          renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;
      videoId ??=
          renderer['overlay']?['musicItemThumbnailOverlayRenderer']?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint']?['videoId']
              as String?;
      videoId ??=
          renderer['doubleTapEndpoint']?['watchEndpoint']?['videoId']
              as String?;

      if (videoId == null || videoId.length != 11) {
        final flexColumns =
            renderer['flexColumns'] as List<dynamic>? ?? const [];
        for (final col in flexColumns) {
          final runs =
              col['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                  as List<dynamic>?;
          if (runs != null) {
            for (final r in runs) {
              final nav = r['navigationEndpoint'] as Map<String, dynamic>?;
              final vid = nav?['watchEndpoint']?['videoId'] as String?;
              if (vid != null && vid.length == 11) {
                videoId = vid;
                break;
              }
            }
          }
          if (videoId != null) break;
        }
      }

      // Deep scan the renderer for any 11-char videoId if still null
      if (videoId == null || videoId.length != 11) {
        String? findVideoId(dynamic node) {
          if (node is Map<String, dynamic>) {
            if (node.containsKey('watchEndpoint')) {
              final vid = node['watchEndpoint']?['videoId'] as String?;
              if (vid != null && vid.length == 11) return vid;
            }
            if (node.containsKey('videoId')) {
              final vid = node['videoId'] as String?;
              if (vid != null && vid.length == 11) return vid;
            }
            for (final v in node.values) {
              final res = findVideoId(v);
              if (res != null) return res;
            }
          } else if (node is List) {
            for (final item in node) {
              final res = findVideoId(item);
              if (res != null) return res;
            }
          }
          return null;
        }

        videoId = findVideoId(renderer);
      }

      if (videoId == null || videoId.length != 11) return null;

      String title = 'Unknown Title';
      String artist = 'Unknown Artist';
      int durationMs = 0;

      final flexColumns = renderer['flexColumns'] as List<dynamic>? ?? const [];
      if (flexColumns.isNotEmpty) {
        final col0Runs =
            flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col0Runs is List && col0Runs.isNotEmpty) {
          final t =
              col0Runs.map((r) => r['text']?.toString() ?? '').join('').trim();
          if (t.isNotEmpty) title = t;
        }
      }
      if (flexColumns.length > 1) {
        final col1Runs =
            flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col1Runs is List && col1Runs.isNotEmpty) {
          final texts =
              col1Runs
                  .map((r) => r['text']?.toString().trim() ?? '')
                  .where((t) => t.isNotEmpty && t != '•' && t != '·')
                  .toList();
          for (final t in texts) {
            if (t.toLowerCase() != 'song' &&
                t.toLowerCase() != 'video' &&
                artist == 'Unknown Artist') {
              artist = t;
            }
          }
        }
      }

      final fixedCols = renderer['fixedColumns'] as List<dynamic>? ?? const [];
      if (fixedCols.isNotEmpty) {
        final durText =
            fixedCols[0]['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs']?[0]?['text']
                as String?;
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
      final thumbnails =
          renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
              as List<dynamic>?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        artworkUrl = thumbnails.last['url'] as String?;
        if (artworkUrl != null) {
          artworkUrl = artworkUrl.replaceAll(
            RegExp(r'=w\d+-h\d+[^?]*'),
            '=s1200',
          );
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

              results.add(
                YtmAccountPlaylist(
                  playlistId: cleanId,
                  title: title.isNotEmpty ? title : 'Playlist',
                  subtitle: subtitle,
                  artworkUrl: artwork,
                ),
              );
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
                final r =
                    flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                        as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  title = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String subtitle = 'YouTube Music';
              if (flexCols != null && flexCols.length > 1) {
                final r =
                    flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                        as List<dynamic>?;
                if (r != null && r.isNotEmpty) {
                  subtitle = r.map((e) => e['text']?.toString() ?? '').join();
                }
              }

              String? artwork;
              final thumbs =
                  renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                      as List<dynamic>?;
              if (thumbs != null && thumbs.isNotEmpty) {
                artwork = thumbs.last['url'] as String?;
              }

              results.add(
                YtmAccountPlaylist(
                  playlistId: cleanId,
                  title: title,
                  subtitle: subtitle,
                  artworkUrl: artwork,
                ),
              );
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

  void dispose() {
    _sessionHarvestDebounce?.cancel();
    loginState.dispose();
  }
}
