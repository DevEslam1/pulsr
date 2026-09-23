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
import 'package:pulsr/core/services/ytm_oauth_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/lyrics_line.dart';
import '../../domain/models/ytm_track.dart';
import '../constants/channels.dart';
import '../constants/embedded_browser_ua.dart';
import '../errors/ytm_error_classifier.dart';
import '../utils/error_logger.dart';
import '../utils/input_sanitizer.dart';
import '../utils/lrc_parser.dart';
import '../utils/ytm_locale.dart';
import '../utils/ytm_rate_limiter.dart';
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

class YtmPlaylistDetails {
  final String id;
  final String title;
  final String author;
  final String? artworkUrl;
  final List<YtmTrack> tracks;

  const YtmPlaylistDetails({
    required this.id,
    required this.title,
    required this.author,
    this.artworkUrl,
    required this.tracks,
  });
}

enum SessionValidationResult {
  valid,
  invalid,
  unknown,
}

@singleton
class YtmAccountService {
  String? _cachedLikedSongsBrowseId;
  /// Session cookies are full Google auth credentials — stored in
  /// Keystore/Keychain-backed secure storage, never as plaintext prefs. (BUG-023)
  static const String _cookieSecureKey = 'ytm_session_cookies_secure';
  static FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @visibleForTesting
  static void setSecureStorageForTesting(FlutterSecureStorage storage) {
    _secureStorage = storage;
  }
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

  /// Shared persistent HTTP client for the Dart Innertube chain (login-state
  /// resolve path issues up to 9 sequential player requests; keep-alive skips
  /// a fresh TCP+TLS handshake on each). Field, not a ctor param, so the
  /// injectable binding stays untouched.
  final http.Client _innertubeClient = http.Client();

  String? _cookies;
  String? _accountName;
  String? _accountAvatar;
  bool _isInitialized = false;

  /// Raw `datasyncId` of the authenticated account (e.g. "userSessionId||"), harvested from any
  /// authenticated Innertube response. Used as the account-bound poToken content-binding.
  String? _dataSyncId;
  Timer? _sessionHarvestDebounce;
  DateTime? _lastDataSyncBootstrapAttempt;
  bool _dataSyncBootstrapInFlight = false;

  /// `visitorData` harvested from an authenticated response; sent in the WEB_REMIX player context.
  String? _sessionVisitorData;

  /// Bearer token from the Google TV OAuth device flow (captcha-free login).
  /// Mutually exclusive with [_cookies] in practice: OAuth sessions carry no
  /// cookie jar, and cookie sessions carry no bearer.
  String? _oauthAccessToken;

  /// Clients whose formats had no playable URLs (SABR enforcement).
  /// Demoted to tail of resolution chain for 10 minutes.
  final Map<String, DateTime> _sabrDemotedUntil = {};

  void _markSabrDemoted(String client) {
    _sabrDemotedUntil[client] = DateTime.now().add(const Duration(minutes: 10));
    debugPrint('[YTM_ACCOUNT] Client $client marked SABR demoted for 10 minutes');
  }

  bool _isSabrDemoted(String client) {
    final until = _sabrDemotedUntil[client];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _sabrDemotedUntil.remove(client);
      return false;
    }
    return true;
  }

  static const _botSubstrings = [
    'not a bot',
    'robot',
    'recaptcha',
    'confirm you\'re not a bot',
    'confirm that you\'re not a bot',
    'automated queries',
    'unusual traffic',
    'botguard',
    'verification required',
  ];

  /// Notifies listeners whenever the YTM login state changes (login/logout).
  final loginState = ValueNotifier<bool>(false);

  bool get isLoggedIn =>
      (_cookies != null && _cookies!.isNotEmpty) ||
      (_oauthAccessToken != null && _oauthAccessToken!.isNotEmpty);

  /// True when the active session is an OAuth bearer rather than a cookie jar.
  bool get isOAuthSession =>
      (_cookies == null || _cookies!.isEmpty) &&
      _oauthAccessToken != null &&
      _oauthAccessToken!.isNotEmpty;
  String? get cookies => _cookies;
  String? get accountName => _accountName;
  String? get accountAvatar => _accountAvatar;
  /// Raw datasyncId of the authenticated account — null until the first authenticated
  /// Innertube response is harvested. Used externally to gate account-bound poToken minting.
  String? get dataSyncId => _dataSyncId;
  String? get sessionVisitorData => _sessionVisitorData;

  String get _clientVersion => _versionResolver.clientVersion;
  String get _apiKey => _versionResolver.apiKey;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      await _versionResolver.init();
      final rawNative = await getNativeCookiesFromDomains();
      // The native store answers for several domains at once, so the same
      // `SAPISID` can appear twice with different values. Un-deduplicated, the
      // header carries both while buildAuthorizationHeader hashes only the first
      // — the signature then belongs to an account the request is not making.
      final nativeCookies =
          rawNative == null ? null : scopeCookiesForYouTube(rawNative);
      if (nativeCookies != null &&
          nativeCookies.isNotEmpty &&
          looksLikeSignedInCookies(nativeCookies)) {
        _cookies = nativeCookies;
        await _persistCookies(nativeCookies);
      } else {
        _cookies = await _readStoredCookies();
      }
      final prefs = await SharedPreferences.getInstance();
      _accountName = prefs.getString(_accountNamePrefKey);
      _accountAvatar = prefs.getString(_accountAvatarPrefKey);
      _dataSyncId ??= prefs.getString(_dataSyncIdPrefKey);

      if (_cookies != null && _cookies!.isNotEmpty) {
        final ytmService = getIt<YtmService>();
        unawaited(ytmService.syncCookies(_cookies!));
        final dsid = _dataSyncId;
        if (dsid != null && dsid.isNotEmpty) {
          unawaited(ytmService.setDataSyncId(dsid));
        }

        // Validate session asynchronously off the startup critical path so init() does
        // not block app launch or hit the 8-second startup timeout.
        unawaited(() async {
          try {
            final ok = await validateSession();
            if (!ok) {
              await _deleteStoredCookies(); // dead session: wipe, don't poison WebView
              _cookies = null;
              loginState.value = false;
            } else {
              final freshDsid = _dataSyncId;
              if (freshDsid != null && freshDsid.isNotEmpty) {
                await ytmService.setDataSyncId(freshDsid);
              }
              await _persistCookies(_cookies!);
            }
          } catch (e) {
            debugPrint('[YTM_ACCOUNT] Background session validation error: $e');
          }
        }());
      }

      // Adopt a Google TV OAuth session when no cookie jar is present. This is
      // the captcha-free login path: library/browse/playlist calls use the
      // bearer, while playback still rides the guest engine chain (it needs a
      // datasync-bound poToken, which OAuth does not provide).
      if (_cookies == null || _cookies!.isEmpty) {
        try {
          final oauth = YtmOAuthService.shared;
          await oauth.init();
          if (oauth.isSignedIn) {
            _oauthAccessToken = oauth.accessToken;
            _accountName ??= 'Google TV';
            unawaited(oauth.ensureFresh());
          }
        } catch (e) {
          debugPrint('[YTM_ACCOUNT] OAuth session restore failed: $e');
        }
      }

      _isInitialized = true;
      loginState.value = isLoggedIn;

      // A session restored from storage may have no dataSyncId (validation was
      // transiently blocked, or the harvest response lacked it). Bootstrap it in
      // the background so signed-in resolves can mint an account-bound poToken
      // instead of endlessly falling through to the guest chain.
      if (isLoggedIn && (_dataSyncId == null || _dataSyncId!.isEmpty)) {
        unawaited(ensureDataSyncId());
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to initialize YtmAccountService',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
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
        baseTimeoutSeconds: 5,
        maxAttempts: 1,
      );
      // A 401 is Innertube rejecting the credential itself, which is as
      // definitive as a logged-out body; answering `unknown` for it kept a dead
      // session installed so every later request failed with no way back to the
      // login sheet. A 403 is the opposite case — far more often an IP or bot
      // block than a bad cookie — and init() wipes the jar on any `false`, so it
      // only counts as invalid when the body itself agrees.
      if (res.statusCode == 401) {
        return SessionValidationResult.invalid;
      }
      if (res.statusCode != 200) {
        if (res.statusCode == 403) {
          try {
            final body = jsonDecode(res.body) as Map<String, dynamic>;
            if (_isUnauthenticatedResponse(body)) {
              return SessionValidationResult.invalid;
            }
          } catch (_) {
            // Not JSON (an HTML interstitial): a block, not a verdict.
          }
        }
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

      // Migration: check legacy plaintext pref key, migrate to secure storage, and remove from prefs
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString('ytm_session_cookies');
      if (legacy != null && legacy.isNotEmpty) {
        await _secureStorage.write(key: _cookieSecureKey, value: legacy);
        await prefs.remove('ytm_session_cookies');
        return legacy;
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read cookies from secure storage',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
    }
    return null;
  }

  /// Persists session cookies exclusively to secure storage. (BUG-023)
  Future<void> _persistCookies(String rawCookies) async {
    if (!InputSanitizer.isValidCookie(rawCookies)) {
      debugPrint('[YTM_ACCOUNT] Refusing to persist malformed cookie string');
      return;
    }
    try {
      await _secureStorage.write(key: _cookieSecureKey, value: rawCookies);
      // Ensure plaintext legacy store is purged
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ytm_session_cookies');
    } catch (e, st) {
      ErrorLogger.log('Failed to persist cookies to secure storage',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
      _cookies = rawCookies;
    }
  }

  Future<void> _deleteStoredCookies() async {
    try {
      await _secureStorage.delete(key: _cookieSecureKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ytm_session_cookies');
    } catch (_) {}
  }

  /// Folds a pasted or scraped cookie blob into one well-formed `Cookie` header
  /// value: `name=value` pairs, `; `-joined, last writer wins, no CR/LF and no
  /// leftover cookie attributes.
  ///
  /// The login sheet lets people paste a header by hand and a DevTools copy
  /// brings along newlines, a `Cookie:` prefix and per-cookie attributes such as
  /// `Path=/` or `Expires=Wed, 21 Oct 2026 ...`. Stored verbatim those either
  /// make the http client reject the request outright or reach the native cookie
  /// store as extra header lines, and a duplicated `SAPISID` silently decides
  /// which account gets signed in.
  static String normalizeCookieHeader(String raw) {
    const attributeNames = {
      'path',
      'domain',
      'expires',
      'max-age',
      'samesite',
      'priority',
      'partitioned',
      'secure',
      'httponly',
    };
    final ordered = <String, String>{};
    for (final segment in raw.split(RegExp(r'[;\r\n]'))) {
      var pair = segment.trim();
      if (pair.isEmpty) continue;
      if (pair.toLowerCase().startsWith('cookie:')) {
        pair = pair.substring('cookie:'.length).trim();
      }
      final eq = pair.indexOf('=');
      if (eq <= 0) continue; // `Secure`, `HttpOnly`, or a stray value
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (name.isEmpty || attributeNames.contains(name.toLowerCase())) continue;
      if (name.contains(RegExp(r'[\s,;]'))) continue; // not a cookie name
      ordered[name] = value;
    }
    return ordered.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Cookies that belong to Google's account-management surface and are never
  /// sent to a YouTube host by a real browser.
  ///
  /// The login WebView spans `accounts.google.com` and `music.youtube.com`, and
  /// both the Dart and native jars are keyed by cookie *name* only — so the
  /// account-chooser and identity cookies from the Google side end up in the
  /// same map as the YouTube session and ride along on every InnerTube request.
  /// That is a needless leak of account-management state to a different host,
  /// and an oversized `Cookie` header is itself a bot signal.
  static const Set<String> _googleAccountOnlyCookies = {
    'LSID',
    'LSOLH',
    'ACCOUNT_CHOOSER',
    'SMSV',
    'GAPS',
    'OSID',
    '__Secure-OSID',
    'NID',
    'AEC',
    '1P_JAR',
    'OTZ',
    'SEARCH_SAMESITE',
    'COMPASS',
    'S',
    'SSOSID',
  };

  /// Drops from [raw] the cookies a browser would never send to a YouTube host.
  ///
  /// `__Host-`-prefixed cookies are host-locked by definition — carrying one
  /// across hosts is always wrong — and the names above belong to Google's
  /// account surface. Mirrors `YtmCookieStore.isSendableToYouTube` on the
  /// native side so both jars scope identically.
  static String scopeCookiesForYouTube(String raw) {
    final kept = <String>[];
    for (final pair in normalizeCookieHeader(raw).split('; ')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq);
      if (name.toLowerCase().startsWith('__host-')) continue;
      if (_googleAccountOnlyCookies.contains(name)) continue;
      kept.add(pair);
    }
    return kept.join('; ');
  }

  /// Saves extracted web cookies, warms the session, and triggers fresh attestation.
  Future<bool> saveSession(String rawCookies) async {
    final jar = scopeCookiesForYouTube(rawCookies);
    // A blob with no SAPISID-family cookie and no PSID is not a session. Saving
    // one flipped `loginState` to true, pushed it into the native cookie store
    // and invalidated a working poToken, leaving the UI showing a signed-in
    // account whose every request comes back unauthenticated — and since no
    // caller reads this return value, the only visible symptom was breakage.
    if (!looksLikeSignedInCookies(jar)) {
      debugPrint(
          '[YTM_ACCOUNT] Refusing to save a cookie jar with no session cookies');
      return false;
    }
    _cookies = jar;
    await _persistCookies(jar);

    // Sync to native CookieManager and invalidate stale poTokens
    final ytmService = getIt<YtmService>();
    await ytmService.syncCookies(jar);
    await ytmService.invalidatePoToken();

    // ACCOUNT_CHOOSER / LOGIN_INFO hold opaque base64 blobs, not human names.
    // Use a stable honest label; real account metadata is harvested later.
    const name = 'YouTube Music Account';
    _accountName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountNamePrefKey, name);

    loginState.value = true;

    // Eagerly bootstrap session state in the background so dataSyncId is ready
    // before the first playSong call. Run in unawaited block so saveSession
    // returns immediately to the login UI without hanging for up to 45s.
    unawaited(() async {
      try {
        await _warmSession();
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Session warming failed (non-fatal): $e');
      }
      // If _warmSession didn't harvest a dataSyncId (e.g. home browse returned
      // an unexpected shape), do an explicit lightweight bootstrap fetch.
      if (_dataSyncId == null || _dataSyncId!.isEmpty) {
        debugPrint('[YTM_ACCOUNT] dataSyncId not yet available after warm, bootstrapping...');
        await _bootstrapDataSyncId();
      }
      if (_dataSyncId != null && _dataSyncId!.isNotEmpty) {
        debugPrint('[YTM_ACCOUNT] dataSyncId ready after login');
      } else {
        debugPrint('[YTM_ACCOUNT] dataSyncId still null after bootstrap — '
            'Tier-1 will resolve as a guest until populated');
      }
    }());

    return true;
  }

  /// Adopts a freshly-completed Google TV OAuth device-flow session and
  /// notifies listeners. Called by the OAuth login sheet on success.
  ///
  /// No cookie jar exists for this session, so playback continues through the
  /// guest engine chain; the bearer unlocks library, browse and playlists.
  Future<void> adoptOAuthSession() async {
    final oauth = YtmOAuthService.shared;
    await oauth.init();
    if (!await oauth.ensureFresh()) return;
    _oauthAccessToken = oauth.accessToken;
    _accountName ??= 'Google TV';
    _accountAvatar = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountNamePrefKey, _accountName!);
    loginState.value = isLoggedIn;
    // Warm session state (visitorData) off the critical path.
    unawaited(() async {
      try {
        await _warmSession();
      } catch (_) {}
    }());
  }

  Future<void> logout() async {
    _cookies = null;
    _oauthAccessToken = null;
    _accountName = null;
    _accountAvatar = null;
    _dataSyncId = null;
    _sessionVisitorData = null;
    // Account-scoped browse cache: must not leak into the next account's
    // library fetch after a switch.
    _cachedLikedSongsBrowseId = null;
    await _deleteStoredCookies();
    try {
      await YtmOAuthService.shared.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountNamePrefKey);
    await prefs.remove(_accountAvatarPrefKey);
    await prefs.remove(_dataSyncIdPrefKey);
    loginState.value = false;

    // Resolved stream URLs are cached with the cookie header they were resolved
    // under, so leaving the cache in place kept serving the disconnected
    // session's URLs — and its cookies — until every entry aged out.
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        getIt<YtmUrlCache>().clear();
      }
    } catch (_) {}

    // The WebView jar first: the native store re-reads it whenever its own prefs
    // are empty, so clearing native before the jar leaves a window (and, if the
    // jar survives, a cold start) in which the session comes straight back.
    try {
      await _deleteSessionWebViewCookies();
    } catch (_) {}
    try {
      final ytmService = getIt<YtmService>();
      // Marks the native store signed out, expires the tracked cookie names in
      // CookieManager, and drops the account-bound poToken + dataSyncId. Plain
      // `syncCookies('')` does none of the last three.
      await ytmService.clearNativeSession();
      await ytmService.syncCookies('');
      await ytmService.invalidatePoToken();
    } catch (_) {}
  }

  /// Cookie scopes owned by the YTM sign-in flow, as `(url, domain)` pairs.
  /// Logout clears only these instead of wiping every WebView/Google cookie on
  /// the device.
  ///
  /// Both scopes of each host are listed on purpose. The Google session cookies
  /// are *domain* cookies (`Domain=.youtube.com`, `Domain=.google.com`), and
  /// expiring a name host-only does not remove the domain-scoped cookie of the
  /// same name — it just adds a second, host-scoped one, leaving the live
  /// credential in the jar. The dotted entries used to be turned into the URL
  /// `https://.youtube.com`, which is not a valid host at all, so the domain
  /// cookies were never touched.
  static const List<(String, String?)> _sessionCookieScopes = [
    ('https://youtube.com', '.youtube.com'),
    ('https://youtube.com', null),
    ('https://www.youtube.com', null),
    ('https://music.youtube.com', null),
    ('https://m.youtube.com', null),
    ('https://accounts.youtube.com', null),
    ('https://google.com', '.google.com'),
    ('https://google.com', null),
    ('https://accounts.google.com', null),
    ('https://myaccount.google.com', null),
  ];

  /// Deletes only YTM/Google session cookies from the WebView cookie store.
  /// Public so the login sheet's manual "clear cookies" action stays scoped.
  Future<void> clearSessionWebViewCookies() => _deleteSessionWebViewCookies();

  Future<void> _deleteSessionWebViewCookies() async {
    var deletedAny = false;
    try {
      final cookieManager = CookieManager.instance();
      for (final (url, domain) in _sessionCookieScopes) {
        try {
          await cookieManager.deleteCookies(
            url: WebUri(url),
            domain: domain ?? '',
            path: '/',
          );
          deletedAny = true;
        } catch (_) {
          // One bad scope must not abandon the rest.
        }
      }
    } catch (_) {}
    if (deletedAny) return;
    // Scoped deletion unsupported on this platform — fall back to a full wipe
    // rather than leaving session cookies behind.
    try {
      await CookieManager.instance().deleteAllCookies();
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
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if (_isUnauthenticatedResponse(json)) {
          debugPrint(
              '[YTM_ACCOUNT] Warmed session returned unauthenticated — keeping session, notifying expiry check');
          getIt<YtmService>().notifyAuthExpired();
          return;
        }
        try {
          _harvestSessionState(json);
        } catch (_) {}
        // Set-Cookie is now ingested for every 2xx in _postWithRetry, so this
        // path no longer needs its own copy.
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
            final expires =
                HttpDate.parse(segments[i].trim().substring(8).trim());
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
  Map<String, String> _buildHeaders(
      {String userAgent = '',
      String origin = 'https://music.youtube.com',
      String? fieldMask}) {
    final defaultUa = EmbeddedBrowserUa.desktop;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': userAgent.isNotEmpty ? userAgent : defaultUa,
      'Origin': origin,
      'Referer': '$origin/',
      'x-origin': origin,
      'x-youtube-client-name': '67',
      'x-youtube-client-version': _clientVersion,
      'X-Goog-Api-Key': _apiKey,
    };

    if (_cookies != null && _cookies!.isNotEmpty) {
      headers['x-goog-authuser'] = '0';
      headers['Cookie'] = _cookies!;
      final authHeader = buildAuthorizationHeader(_cookies!, origin: origin);
      if (authHeader != null) {
        headers['Authorization'] = authHeader;
      }
    } else if (_oauthAccessToken != null && _oauthAccessToken!.isNotEmpty) {
      // Google TV OAuth session: InnerTube accepts an OAuth bearer on the
      // WEB_REMIX client (same as `ytmusicapi`), and no cookie jar is involved.
      headers['Authorization'] = 'Bearer $_oauthAccessToken';
    }

    // Innertube hands back a `visitorData` on the first response and expects it
    // echoed on the rest of the session. Without it every call looks like a
    // brand-new visitor, which is one of the cheapest bot signals to trip — and
    // it is the same id the poToken is minted against, so omitting it here can
    // leave the token bound to a visitor the request never claims to be.
    final visitorId = _sessionVisitorData;
    if (visitorId != null && visitorId.isNotEmpty) {
      headers['X-Goog-Visitor-Id'] = visitorId;
    }
    if (fieldMask != null && fieldMask.isNotEmpty) {
      headers['X-Goog-FieldMask'] = fieldMask;
    }

    return headers;
  }

  /// Re-derives the credential-bearing headers from the live cookie jar just
  /// before a request goes out, leaving every other header the caller set alone.
  ///
  /// Callers build headers once and reuse them across a browse loop, up to 20
  /// continuation pages and three backoff attempts. Two things go stale in that
  /// window: SAPISIDHASH embeds the second it was computed, so a paging walk
  /// signs its later pages with a minutes-old timestamp, and the jar itself now
  /// rotates underneath them as [_ingestSetCookies] takes in `Set-Cookie` — a
  /// stale `Cookie` header would keep presenting the superseded values. Doing it
  /// here rather than at each call site means no request can forget.
  Map<String, String>? _resignHeaders(Map<String, String>? headers) {
    if (headers == null) return null;
    // OAuth sessions re-read the (possibly just refreshed) bearer so a retry
    // after a 401 never replays the stale token.
    if (isOAuthSession) {
      final token = YtmOAuthService.shared.accessToken;
      if (token != null && token.isNotEmpty) {
        return {...headers, 'Authorization': 'Bearer $token'};
      }
      return headers;
    }
    // Only requests we signed in the first place: an anonymous call must stay
    // anonymous no matter what happens to be in the jar.
    if (!headers.containsKey('Authorization')) return headers;
    final jar = _cookies;
    if (jar == null || jar.isEmpty) return headers;
    final origin =
        headers['x-origin'] ?? headers['Origin'] ?? 'https://music.youtube.com';
    final fresh = buildAuthorizationHeader(jar, origin: origin);
    if (fresh == null) return headers;
    final visitorId = _sessionVisitorData;
    return {
      ...headers,
      'Cookie': jar,
      'Authorization': fresh,
      if (visitorId != null && visitorId.isNotEmpty)
        'X-Goog-Visitor-Id': visitorId,
    };
  }

  /// Builds the proper Authorization header for YouTube / Google InnerTube requests.
  /// Supports SAPISID (SAPISIDHASH), __Secure-3PAPISID (SAPISID3PHASH), and __Secure-1PAPISID (SAPISID1PHASH).
  static String? buildAuthorizationHeader(String cookies,
      {String origin = 'https://music.youtube.com'}) {
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

    final hasSapisid = valueOf('SAPISID') != null ||
        valueOf('__Secure-3PAPISID') != null ||
        valueOf('__Secure-1PAPISID') != null;
    final hasPsid =
        valueOf('__Secure-3PSID') != null || valueOf('__Secure-1PSID') != null;
    return hasSapisid && hasPsid;
  }

  Map<String, dynamic> _buildClientContext(String clientType,
      [String? videoId]) {
    final clientMap = <String, dynamic>{
      'clientName': clientType,
      'clientVersion': _versionResolver.clientVersionFor(clientType),
      'hl': YtmLocale.hl(),
      'gl': YtmLocale.gl(),
    };

    if (clientType == 'ANDROID_MUSIC') {
      clientMap['clientVersion'] = _versionResolver.androidMusicVersion;
      clientMap['androidSdkVersion'] = 34;
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '14';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'IOS_MUSIC') {
      clientMap['clientVersion'] = _versionResolver.iosMusicVersion;
      clientMap['deviceMake'] = 'Apple';
      clientMap['deviceModel'] = 'iPhone15,3';
      clientMap['osName'] = 'iOS';
      clientMap['osVersion'] = '18.0';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_VR') {
      clientMap['clientVersion'] = _versionResolver.androidVrVersion;
      clientMap['androidSdkVersion'] = 32;
      clientMap['deviceMake'] = 'Oculus';
      clientMap['deviceModel'] = 'Quest 2';
      clientMap['osName'] = 'Android';
      clientMap['osVersion'] = '12';
      clientMap['platform'] = 'MOBILE';
    } else if (clientType == 'ANDROID_CREATOR') {
      clientMap['clientVersion'] = _versionResolver.androidCreatorVersion;
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
        'embedUrl': (videoId != null && videoId.isNotEmpty)
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
  }) async {
    final breaker =
        getIt.isRegistered<YtmService>() ? getIt<YtmService>().breaker : null;
    if (breaker != null) {
      if (!breaker.shouldAllow(YtmBlockSignal.rateLimited)) {
        throw const YtmException(
            'RATE_LIMITED', 'Rate limiter circuit breaker open');
      }
      if (!breaker.shouldAllow(YtmBlockSignal.botChallenge)) {
        throw const YtmException(
            'BOT_CHALLENGE', 'Bot challenge circuit breaker open');
      }
      if (!breaker.shouldAllow(YtmBlockSignal.ipBlocked)) {
        throw const YtmException(
            'IP_BLOCKED', 'IP block circuit breaker open');
      }
    }

    // Keep the OAuth bearer fresh before the first request of a paging walk.
    if (isOAuthSession) {
      try {
        if (await YtmOAuthService.shared.ensureFresh()) {
          _oauthAccessToken = YtmOAuthService.shared.accessToken;
        } else if (_oauthAccessToken != null && _oauthAccessToken!.isNotEmpty) {
          // Expired with no usable refresh token: the session is dead. Tear it
          // down so the UI stops advertising a connected account that 401s.
          await logout();
          throw const YtmException('YTM_AUTH', 'Session expired');
        }
      } on YtmException {
        rethrow;
      } catch (_) {}
    }
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await YtmRateLimiter.shared.acquirePermit();
        final timeout = Duration(seconds: baseTimeoutSeconds + attempt * 5);
        final res = await _innertubeClient
            .post(uri, headers: _resignHeaders(headers), body: body)
            .timeout(timeout);
        // A 401 on an OAuth session is an expired bearer: refresh and retry.
        if (res.statusCode == 401 &&
            isOAuthSession &&
            attempt < maxAttempts - 1) {
          final refreshed = await YtmOAuthService.shared.refresh();
          if (refreshed) {
            _oauthAccessToken = YtmOAuthService.shared.accessToken;
            continue;
          }
          // Refresh failed: the bearer is dead. Invalidate the session so the
          // UI stops claiming it is connected, and hand the 401 back.
          await logout();
          return res;
        }

        // A 403 on a cookie session: attempt a single retry with re-signed headers
        if (res.statusCode == 403 &&
            !isOAuthSession &&
            attempt == 0 &&
            maxAttempts > 1) {
          debugPrint(
              '[YTM_ACCOUNT] HTTP 403 on cookie session, retrying once before failure');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        if (res.statusCode == 429 ||
            res.statusCode >= 500 ||
            res.statusCode == 403) {
          if (res.statusCode == 429) {
            YtmRateLimiter.shared.onRateLimited();
            breaker?.recordFailure(YtmBlockSignal.rateLimited);
          } else if (res.statusCode == 403) {
            breaker?.recordFailure(YtmBlockSignal.ipBlocked);
          }
          final backoffSec = (1 << attempt) + Random().nextInt(2);
          debugPrint(
              '[YTM_ACCOUNT] HTTP ${res.statusCode} encountered. Backing off for ${backoffSec}s (attempt ${attempt + 1}/$maxAttempts)');
          if (attempt < maxAttempts - 1) {
            await Future.delayed(Duration(seconds: backoffSec));
            continue;
          }
        }

        // Only 2xx clears/updates limiter state: a 403/401 must never reset
        // an active cooling window back to "all clear".
        if (res.statusCode >= 200 && res.statusCode < 300) {
          YtmRateLimiter.shared.onSuccess();
          breaker?.recordSuccess();
          // Google rotates the session cookies (notably the `__Secure-*PSID*`
          // family and `SIDCC`) on ordinary authenticated traffic, and drops the
          // old values when the rotation is never acknowledged. Ingesting only
          // inside _warmSession() meant every rotation on a library fetch, a
          // continuation page or a playlist edit was thrown away, so a jar that
          // was valid at login quietly aged out. Gated on `isLoggedIn` so a
          // response to an anonymous call cannot conjure a session out of
          // whatever cookies the edge server happened to set.
          if (isLoggedIn && _cookies != null && _cookies!.isNotEmpty) {
            final setCookie = res.headers['set-cookie'];
            if (setCookie != null && setCookie.isNotEmpty) {
              try {
                _ingestSetCookies(setCookie);
              } catch (_) {}
            }
          }
        }
        return res;
      } on TimeoutException {
        if (attempt == maxAttempts - 1) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
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
                '[YTM_ACCOUNT] Unauthenticated response detected on $bId');
            // `_isUnauthenticatedResponse` is a shape heuristic — a library
            // browse that legitimately answers with a bare shell trips it too —
            // and logout() wipes the cookie jar and the WebView. Signing people
            // out on one odd response is the wrong trade, so get a second,
            // independent verdict from the canonical home browse and only tear
            // the session down when that agrees.
            final verdict = await validateSessionDetailed();
            if (verdict == SessionValidationResult.invalid) {
              await logout();
              throw const YtmException('YTM_AUTH', 'Session expired');
            }
            getIt<YtmService>().notifyAuthExpired();
            continue;
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
            '[YTM_ACCOUNT] Failed fetching account playlists ($bId): $e');
      }
    }
    return [];
  }

  /// Fetches private Liked Music playlist (`VLLM`, `FEmusic_liked_videos`, `LM`).
  Future<List<YtmTrack>> fetchLikedSongs({int maxTracks = 200}) async {
    if (!isLoggedIn) {
      throw const YtmException('YTM_AUTH', 'Not signed in to YouTube Music');
    }

    // Refresh cookies from native CookieManager if needed
    final rawNative = await getNativeCookiesFromDomains();
    final nativeCookies =
        rawNative == null ? null : normalizeCookieHeader(rawNative);
    if (nativeCookies != null &&
        nativeCookies.isNotEmpty &&
        looksLikeSignedInCookies(nativeCookies)) {
      _cookies = nativeCookies;
      unawaited(_persistCookies(nativeCookies));
    }

    final headers = _buildHeaders();
    final orderedBrowseIds = {
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
            '[YTM_ACCOUNT] Liked songs query $bId: HTTP ${response.statusCode}, body length=${response.body.length}');

        if (response.statusCode == 200) {
          var json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json)) {
            debugPrint(
                '[YTM_ACCOUNT] Liked songs returned unauthenticated on $bId, trying next candidate');
            continue;
          }

          _harvestSessionState(json);
          final tracks = _parsePlaylistTracks(json);
          debugPrint(
              '[YTM_ACCOUNT] Liked songs query $bId parsed ${tracks.length} tracks'
              ' (top-level keys: ${json.keys.take(8).join(', ')})');

          if (tracks.isEmpty) {
            debugPrint(
                '[YTM_ACCOUNT] Liked songs query $bId returned 0 tracks '
                '(${response.body.length} B, keys: ${json.keys.take(8).join(', ')})');
            // YouTube Music frequently delivers the liked-songs list only via
            // continuation — the initial browse response is a header shell.
            final initToken = _extractPlaylistContinuationToken(json);
            if (initToken != null && initToken.isNotEmpty) {
              debugPrint(
                  '[YTM_ACCOUNT] Initial browse had 0 tracks but continuation found, fetching...');
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
                final contTracks = _parsePlaylistTracks(contJson);
                debugPrint(
                    '[YTM_ACCOUNT] Browse initial continuation parsed ${contTracks.length} tracks');
                if (contTracks.isNotEmpty) {
                  tracks.addAll(contTracks);
                  // Continue pagination from the continuation response,
                  // not the header shell (its token is already consumed).
                  json = contJson;
                } else {
                  debugPrint(
                      '[YTM_ACCOUNT] Continuation body returned 0 tracks '
                      '(${contRes.body.length} B, keys: ${contJson.keys.take(8).join(', ')})');
                }
              }
            }
          }

          if (tracks.isNotEmpty) {
            _cachedLikedSongsBrowseId = bId;
            final allTracks = List<YtmTrack>.from(tracks);
            // NOTE: when the initial browse was a header shell, `tracks`
            // already contains the first continuation page. `currentJson`
            // must continue from the last continuation response, otherwise
            // pagination replays the consumed token and stalls on duplicates.
            // `json` is reassigned below when that path is taken.
            var currentJson = json;

            final seenVideoIds = tracks.map((t) => t.videoId).toSet();

            // Fetch continuation pages until maxTracks is satisfied.
            var pageCount = 0;
            const maxPages = 100;
            var consecutiveEmptyPages = 0;
            while (allTracks.length < maxTracks && pageCount < maxPages) {
              pageCount++;
              try {
                final ctoken = _extractPlaylistContinuationToken(currentJson);
                if (ctoken == null || ctoken.isEmpty) break;

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
                  final contTracks = _parsePlaylistTracks(currentJson);
                  final newTracks = contTracks
                      .where((t) => seenVideoIds.add(t.videoId))
                      .toList();
                  if (newTracks.isEmpty) {
                    consecutiveEmptyPages++;
                    if (consecutiveEmptyPages >= 3) break;
                    continue;
                  }
                  consecutiveEmptyPages = 0;
                  allTracks.addAll(newTracks);
                } else {
                  break;
                }
              } catch (e) {
                debugPrint(
                    '[YTM_ACCOUNT] Liked songs continuation error on page $pageCount: $e');
                break;
              }
            }
            if (pageCount >= maxPages) {
              debugPrint(
                  '[YTM_ACCOUNT] Hit max continuation pages ($maxPages)');
            }

            return allTracks.take(maxTracks).toList();
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
              'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey'),
          headers: headers,
          body: body,
        );
        debugPrint(
            '[YTM_ACCOUNT] Next endpoint query $pId: HTTP ${response.statusCode}, length=${response.body.length}');
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final tracks = _parseInnertubePlaylistTracks(json);
          debugPrint(
              '[YTM_ACCOUNT] Next endpoint query $pId parsed ${tracks.length} tracks');
          if (tracks.isNotEmpty) {
            return tracks.take(maxTracks).toList();
          } else {
            debugPrint(
                '[YTM_ACCOUNT] Next endpoint $pId parsed nothing '
                '(${response.body.length} B, keys: ${json.keys.take(8).join(', ')})');
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
          '[YTM_ACCOUNT] Discovered ${playlists.length} account playlists for liked songs resolution');
      for (final p in playlists) {
        final lowerTitle = p.title.toLowerCase();
        final isLiked = p.playlistId.contains('LM') ||
            lowerTitle.contains('like') ||
            lowerTitle.contains('aimé') ||
            lowerTitle.contains('favori') ||
            lowerTitle.contains('j\'aime') ||
            lowerTitle.contains('liebling');
        if (isLiked) {
          debugPrint(
              '[YTM_ACCOUNT] Found Liked Music playlist in account: ${p.playlistId} (${p.title})');
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
          '[YTM_ACCOUNT] Attempting Native Kotlin Innertube fallback for liked songs...');
      final ytmService = getIt<YtmService>();
      final nativeTracks =
          await ytmService.getPlaylistTracks('VLLM', limit: maxTracks);
      if (nativeTracks.isNotEmpty) {
        debugPrint(
            '[YTM_ACCOUNT] Native Kotlin fallback returned ${nativeTracks.length} liked songs');
        return nativeTracks.take(maxTracks).toList();
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Native Kotlin fallback failed: $e');
    }

    return [];
  }

  /// Fetches details and tracks for any YouTube / YouTube Music playlist by URL or ID.
  /// Handles:
  /// - User's private & unlisted playlists (when signed in with cookies)
  /// - Public YouTube and YouTube Music playlists (with or without login)
  /// - Curated mixes, albums, and auto-generated playlists (`RDCLAK...`, `OLAK...`, `VL...`)
  /// - Liked Music (`LM`, `VLLM`, `FEmusic_liked_videos`)
  Future<YtmPlaylistDetails?> fetchPlaylistDetails(
    String urlOrId, {
    int maxTracks = 200,
  }) async {
    final rawInput = urlOrId.trim();
    if (rawInput.isEmpty) return null;

    // 1. Extract playlist ID from URL if provided as URL
    String playlistId = rawInput;
    if (playlistId.contains('list=')) {
      final uri = Uri.tryParse(playlistId);
      final listParam = uri?.queryParameters['list'];
      if (listParam != null && listParam.isNotEmpty) {
        playlistId = listParam;
      }
    }

    // Liked songs special handling
    if (playlistId == 'LM' ||
        playlistId == 'VLLM' ||
        playlistId == 'LL' ||
        playlistId == 'FEmusic_liked_videos' ||
        playlistId == 'FEmusic_liked_tracks' ||
        playlistId == 'VLSE') {
      final likedTracks = await fetchLikedSongs(maxTracks: maxTracks);
      return YtmPlaylistDetails(
        id: playlistId,
        title: 'Liked Music',
        author: 'Auto Playlist',
        artworkUrl: likedTracks.firstOrNull?.artworkUrl,
        tracks: likedTracks,
      );
    }

    // Refresh cookies from native CookieManager if needed
    try {
      final rawNative = await getNativeCookiesFromDomains();
      final nativeCookies =
          rawNative == null ? null : normalizeCookieHeader(rawNative);
      if (nativeCookies != null &&
          nativeCookies.isNotEmpty &&
          looksLikeSignedInCookies(nativeCookies)) {
        _cookies = nativeCookies;
        unawaited(_persistCookies(nativeCookies));
      }
    } catch (_) {}

    final headers = _buildHeaders();
    final cleanRawId =
        playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;

    // Candidate browse IDs to try:
    // YouTube Music browse API expects 'VL' prefix for most playlists (e.g. VLPL..., VLRDCLAK...)
    final candidateBrowseIds = <String>[
      if (playlistId.startsWith('VL')) playlistId else 'VL$playlistId',
      if (!playlistId.startsWith('VL')) playlistId else playlistId.substring(2),
    ];

    String playlistTitle = 'YouTube Playlist';
    String playlistAuthor = 'YouTube Music';
    String? playlistArtwork;

    for (final bId in candidateBrowseIds) {
      try {
        final body = jsonEncode({
          'context': _buildClientContext('WEB_REMIX'),
          'browseId': bId,
        });

        final response = await _postWithRetry(
          Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
          headers: headers,
          body: body,
          baseTimeoutSeconds: 10,
        );

        if (response.statusCode == 200) {
          var json = jsonDecode(response.body) as Map<String, dynamic>;
          if (_isUnauthenticatedResponse(json) && isLoggedIn) {
            debugPrint(
                '[YTM_ACCOUNT] Playlist browse returned unauthenticated on $bId');
            continue;
          }

          _harvestSessionState(json);
          final headerInfo = _extractPlaylistHeaderInfo(json);
          if (headerInfo['title'] != null && headerInfo['title']!.isNotEmpty) {
            playlistTitle = headerInfo['title']!;
          }
          if (headerInfo['author'] != null &&
              headerInfo['author']!.isNotEmpty) {
            playlistAuthor = headerInfo['author']!;
          }
          if (headerInfo['artwork'] != null &&
              headerInfo['artwork']!.isNotEmpty) {
            playlistArtwork = headerInfo['artwork'];
          }

          final tracks = _parsePlaylistTracks(json);
          debugPrint(
              '[YTM_ACCOUNT] Playlist browse $bId parsed ${tracks.length} tracks (title: $playlistTitle)');

          // Check if initial response was a header shell with continuation
          if (tracks.isEmpty) {
            final initToken = _extractPlaylistContinuationToken(json);
            if (initToken != null && initToken.isNotEmpty) {
              final contBody = jsonEncode({
                'context': _buildClientContext('WEB_REMIX'),
                'continuation': initToken,
              });
              final contRes = await _postWithRetry(
                Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                headers: headers,
                body: contBody,
                baseTimeoutSeconds: 10,
              );
              if (contRes.statusCode == 200) {
                final contJson =
                    jsonDecode(contRes.body) as Map<String, dynamic>;
                final contTracks = _parsePlaylistTracks(contJson);
                if (contTracks.isNotEmpty) {
                  tracks.addAll(contTracks);
                  // Continue pagination from the continuation response,
                  // not the header shell (its token is already consumed).
                  json = contJson;
                }
              }
            }
          }

          if (tracks.isNotEmpty) {
            final seenVideoIds = tracks.map((t) => t.videoId).toSet();
            final allTracks = List<YtmTrack>.from(tracks);
            var currentJson = json;

            // Follow continuation pages up to maxTracks
            var pageCount = 0;
            const maxPages = 30;
            var consecutiveEmpty = 0;
            while (allTracks.length < maxTracks && pageCount < maxPages) {
              pageCount++;
              final ctoken = _extractPlaylistContinuationToken(currentJson);
              if (ctoken == null || ctoken.isEmpty) break;

              final contBody = jsonEncode({
                'context': _buildClientContext('WEB_REMIX'),
                'continuation': ctoken,
              });

              final contRes = await _postWithRetry(
                Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                headers: headers,
                body: contBody,
                baseTimeoutSeconds: 10,
              );

              if (contRes.statusCode == 200) {
                currentJson = jsonDecode(contRes.body) as Map<String, dynamic>;
                final contTracks = _parsePlaylistTracks(currentJson);
                final newTracks = contTracks
                    .where((t) => seenVideoIds.add(t.videoId))
                    .toList();
                if (newTracks.isEmpty) {
                  consecutiveEmpty++;
                  if (consecutiveEmpty >= 2) break;
                  continue;
                }
                consecutiveEmpty = 0;
                allTracks.addAll(newTracks);
              } else {
                break;
              }
            }

            final uniqueTracks = allTracks;

            playlistArtwork ??= uniqueTracks.firstOrNull?.artworkUrl;

            return YtmPlaylistDetails(
              id: cleanRawId,
              title: playlistTitle,
              author: playlistAuthor,
              artworkUrl: playlistArtwork,
              tracks: uniqueTracks.take(maxTracks).toList(),
            );
          }
        }
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Failed fetching playlist browse ($bId): $e');
      }
    }

    // 2. Fallback: InnerTube /next endpoint with playlistId
    // Resolves mixes, radios, or playlists whose browse endpoint is unavailable
    try {
      final nextBody = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'playlistId': cleanRawId,
        'enablePersistentPlaylistPanel': true,
        'isAudioOnly': true,
      });

      final nextRes = await _postWithRetry(
        Uri.parse(
            'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey'),
        headers: headers,
        body: nextBody,
        baseTimeoutSeconds: 10,
      );

      if (nextRes.statusCode == 200) {
        final json = jsonDecode(nextRes.body) as Map<String, dynamic>;
        final headerInfo = _extractPlaylistHeaderInfo(json);
        if (headerInfo['title'] != null && headerInfo['title']!.isNotEmpty) {
          playlistTitle = headerInfo['title']!;
        }
        if (headerInfo['author'] != null && headerInfo['author']!.isNotEmpty) {
          playlistAuthor = headerInfo['author']!;
        }

        final tracks = _parsePlaylistTracks(json);
        if (tracks.isNotEmpty) {
          final seen = <String>{};
          final uniqueTracks =
              tracks.where((t) => seen.add(t.videoId)).take(maxTracks).toList();
          return YtmPlaylistDetails(
            id: cleanRawId,
            title: playlistTitle != 'YouTube Playlist'
                ? playlistTitle
                : 'Playlist ($cleanRawId)',
            author: playlistAuthor,
            artworkUrl:
                playlistArtwork ?? uniqueTracks.firstOrNull?.artworkUrl,
            tracks: uniqueTracks,
          );
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Next endpoint failed for $cleanRawId: $e');
    }

    return null;
  }

  /// Convenience method to fetch only tracks for a playlist by URL or ID.
  Future<List<YtmTrack>> fetchPlaylistTracks(
    String urlOrId, {
    int maxTracks = 200,
  }) async {
    final details = await fetchPlaylistDetails(urlOrId, maxTracks: maxTracks);
    return details?.tracks ?? const [];
  }

  Map<String, String?> _extractPlaylistHeaderInfo(Map<String, dynamic> root) {
    String? title;
    String? author;
    String? artwork;

    void checkHeaderNode(Map<String, dynamic> header) {
      final titleRuns = header['title']?['runs'] as List<dynamic>?;
      if (titleRuns != null && titleRuns.isNotEmpty && title == null) {
        title = titleRuns.map((r) => r['text']?.toString() ?? '').join();
      }

      // Prioritize straplineTextOne / straplineText / owner as they contain the actual author/creator
      final straplineRuns = (header['straplineTextOne']?['runs'] ??
          header['straplineText']?['runs'] ??
          header['strapline']?['runs'] ??
          header['owner']?['runs']) as List<dynamic>?;
      if (straplineRuns != null && straplineRuns.isNotEmpty && author == null) {
        final text = straplineRuns
            .map((r) => r['text']?.toString().trim() ?? '')
            .where((t) => t.isNotEmpty && t != '•' && t != '·')
            .join(' ');
        if (text.isNotEmpty) author = text;
      }

      final subRuns = (header['subtitle']?['runs'] ??
          header['secondSubtitle']?['runs']) as List<dynamic>?;
      if (subRuns != null && subRuns.isNotEmpty && author == null) {
        // Filter out metadata keywords like "Playlist", "Public", "Private", "Unlisted", or 4-digit years
        final filteredRuns = subRuns.where((r) {
          final t = r['text']?.toString().trim() ?? '';
          final lower = t.toLowerCase();
          return t.isNotEmpty &&
              t != '•' &&
              t != '·' &&
              lower != 'playlist' &&
              lower != 'public' &&
              lower != 'private' &&
              lower != 'unlisted' &&
              !RegExp(r'^\d{4}$').hasMatch(t);
        }).toList();

        if (filteredRuns.isNotEmpty) {
          author = filteredRuns
              .map((r) => r['text']?.toString().trim() ?? '')
              .join(' ');
        } else {
          final text = subRuns
              .map((r) => r['text']?.toString().trim() ?? '')
              .where((t) => t.isNotEmpty && t != '•' && t != '·')
              .join(' ');
          if (text.isNotEmpty) author = text;
        }
      }

      final thumbRenderer =
          header['thumbnail']?['croppedSquareThumbnailRenderer'] ??
              header['thumbnail']?['musicThumbnailRenderer'];
      final thumbs = (thumbRenderer?['thumbnail']?['thumbnails'] ??
          header['thumbnail']?['thumbnails']) as List<dynamic>?;
      if (thumbs != null && thumbs.isNotEmpty && artwork == null) {
        artwork = thumbs.last['url'] as String?;
      }
    }

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        if (node.containsKey('musicDetailHeaderRenderer')) {
          checkHeaderNode(
              node['musicDetailHeaderRenderer'] as Map<String, dynamic>);
        }
        if (node.containsKey('musicResponsiveHeaderRenderer')) {
          checkHeaderNode(
              node['musicResponsiveHeaderRenderer'] as Map<String, dynamic>);
        }
        if (node.containsKey('musicEditablePlaylistDetailHeaderRenderer')) {
          final ed = node['musicEditablePlaylistDetailHeaderRenderer']
              as Map<String, dynamic>;
          final inner = ed['header']?['musicResponsiveHeaderRenderer']
              as Map<String, dynamic>?;
          if (inner != null) checkHeaderNode(inner);
        }
        for (final v in node.values) {
          traverse(v);
        }
      } else if (node is List) {
        for (final item in node) {
          traverse(item);
        }
      }
    }

    traverse(root);
    return {'title': title, 'author': author, 'artwork': artwork};
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
            'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey'),
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
          if (node.containsKey('musicTimedLyricsRenderer')) {
            final timedShelf =
                node['musicTimedLyricsRenderer'] as Map<String, dynamic>;
            final dataList =
                timedShelf['timedLyricsData'] as List<dynamic>?;
            if (dataList != null && dataList.isNotEmpty) {
              for (final item in dataList) {
                if (item is Map<String, dynamic>) {
                  String text = '';
                  final lyricLine = item['lyricLine'];
                  if (lyricLine is String) {
                    text = lyricLine;
                  } else if (lyricLine is Map && lyricLine.containsKey('runs')) {
                    final runs = lyricLine['runs'] as List<dynamic>;
                    text = runs.map((r) => r['text'] as String? ?? '').join();
                  }
                  final cueRange = item['cueRange'] as Map<String, dynamic>?;
                  final startMs = int.tryParse(
                          cueRange?['startTimeMilliseconds']?.toString() ??
                              '0') ??
                      0;
                  lines.add(LyricsLine(
                    timestamp: Duration(milliseconds: startMs),
                    text: text.trim(),
                    source: LyricsSource.ytmusic,
                  ));
                }
              }
              if (lines.isNotEmpty) return;
            }
          }

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
  Future<YtmStream?> resolvePlayerStream(String videoId,
      {String quality = 'high'}) async {
    try {
      return await _resolvePlayerStreamInternal(videoId, quality: quality)
          .timeout(const Duration(seconds: 50));
    } on TimeoutException {
      debugPrint(
          '[YTM_ACCOUNT] Global stream resolution timed out after 50s for $videoId');
      return null;
    }
  }

  Future<YtmStream?> _resolvePlayerStreamInternal(String videoId,
      {String quality = 'high'}) async {
    // BotGuard requires a poToken on WEB_REMIX player requests regardless of login.
    // Authenticated → the token must be content-bound to the account's datasyncId, sent WITH
    // the session cookies + SAPISIDHASH. Unauthenticated → a guest token bound to guest visitorData.
    final isAuthenticated =
        isLoggedIn && _cookies != null && _cookies!.isNotEmpty;

    if (_dataSyncId == null && isLoggedIn) {
      await _warmSession().timeout(const Duration(seconds: 3), onTimeout: () {});
    }

    // Warm the native BotGuard attestation once so both the account-bound and
    // guest minting below have a live generator instead of a cold WebView.
    try {
      await getIt<YtmService>()
          .ensurePoTokenReady()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    // Two attestation pairs, kept strictly apart. A poToken is only valid for
    // the identity it was minted against, and the session cookies are only
    // valid alongside the account-bound one — so the authenticated WEB_REMIX
    // request uses (account token, session visitorData, cookies) while every
    // guest client in the chain uses (guest token, guest visitorData, no
    // cookies). Crossing them is what YouTube answers with LOGIN_REQUIRED /
    // "confirm you're not a bot".
    String? accountPoToken;
    String? accountVisitorData;
    bool hadAccountPoToken = false; // true only when account-bound token minted successfully
    // Whether this pass may carry the session (cookies + SAPISIDHASH). Only an
    // account-bound poToken earns that; otherwise the pass runs as a clean guest.
    var useSessionAuth = isAuthenticated;
    if (isAuthenticated) {
      // dataSyncId guard: if we still don't have a dataSyncId (e.g. first play
      // immediately after login before _warmSession completed) we cannot mint an
      // account-bound token. A guest poToken paired with session cookies is a
      // poisoned combination that YouTube rejects for every client, causing the
      // full LOGIN_REQUIRED cascade — but the remedy is to drop the *cookies*,
      // not to drop Tier-1. Returning null here handed every signed-in
      // resolution to Tier-2, so Tier-1 was effectively off while logged in.
      final dsid = _dataSyncId;
      if (dsid == null || dsid.isEmpty) {
        debugPrint('[YTM_ACCOUNT] dataSyncId not yet available for $videoId — '
            'running Tier-1 as a guest pass (no session cookies).');
        useSessionAuth = false;
      } else {
        try {
          final account = await getIt<YtmService>()
              .getAccountPoToken(dsid)
              .timeout(const Duration(seconds: 2));
          accountPoToken = account?['poToken'] as String?;
          final vd = account?['visitorData'] as String?;
          accountVisitorData =
              _sessionVisitorData ?? (vd != null && vd.isNotEmpty ? vd : null);
          if (accountPoToken != null && accountPoToken.isNotEmpty) {
            hadAccountPoToken = true;
          }
        } catch (e) {
          debugPrint('[YTM_ACCOUNT] Account poToken minting failed: $e');
        }
        // Account-bound minting failed (e.g. BotGuard not ready yet): fall back
        // to a guest pass rather than sending a guest token with session
        // cookies. Both the token and the visitorData must be the guest ones,
        // so drop what the account attempt left behind.
        if (!hadAccountPoToken) {
          debugPrint('[YTM_ACCOUNT] Account-bound poToken unavailable for $videoId — '
              'running Tier-1 as a guest pass (no session cookies).');
          useSessionAuth = false;
          accountPoToken = null;
          accountVisitorData = null;
        }
      }
    }
    // Guest pair, needed by every non-WEB_REMIX client in the chain even when
    // signed in — those clients are only reachable as guests.
    String? guestPoToken;
    String? guestVisitorData;
    try {
      final poState = await getIt<YtmService>()
          .getPoTokenState()
          .timeout(const Duration(seconds: 2));
      guestPoToken = poState?['streamingPoToken'] as String?;
      guestVisitorData = poState?['visitorData'] as String?;
    } catch (_) {}

    // Web-shaped clients send the token as `serviceIntegrityDimensions`, which
    // must be bound to the *video*; the visitor-bound streaming token makes
    // YouTube answer UNPLAYABLE "Video unavailable" even though a token is
    // attached. Mint the content-bound one up front (null when unavailable, in
    // which case the request goes out without a token rather than the wrong one).
    String? playerPoToken;
    if (!useSessionAuth) {
      try {
        playerPoToken = await getIt<YtmService>()
            .getPlayerPoToken(videoId)
            .timeout(const Duration(seconds: 4));
      } catch (e, st) {
        ErrorLogger.log('Failed to mint content-bound player poToken',
            error: e, stackTrace: st, category: 'YTM_ACCOUNT');
      }
    }

    final rawChain = useSessionAuth
        ? [
            'WEB_REMIX', // the only client that carries the session
            'ANDROID_VR', // guest fallbacks from here down
            'ANDROID_MUSIC',
            'IOS_MUSIC',
            'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
            'WEB_EMBEDDED_PLAYER',
            'MWEB',
            'ANDROID_CREATOR',
            'ANDROID_TESTSUITE',
          ]
        : [
            'ANDROID_VR',
            'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
            'WEB_REMIX',
            'WEB_EMBEDDED_PLAYER',
            'MWEB',
            'ANDROID_MUSIC',
            'IOS_MUSIC',
            'ANDROID_CREATOR',
            'ANDROID_TESTSUITE',
          ];

    final clientChain = List<String>.from(rawChain)
      ..sort((a, b) {
        final aDemoted = _isSabrDemoted(a);
        final bDemoted = _isSabrDemoted(b);
        if (aDemoted && !bDemoted) return 1;
        if (!aDemoted && bDemoted) return -1;
        return 0;
      });

    // Track consecutive IP-level blocks to short-circuit early (like the
    // native InnertubeClient chain). When 2+ clients return LOGIN_REQUIRED or
    // UNPLAYABLE the IP is flagged — every remaining client will too.
    var consecutiveBlockSignals = 0;

    for (final client in clientChain) {
      try {
        final isWeb = client == 'WEB_REMIX' ||
            client == 'WEB_EMBEDDED_PLAYER' ||
            client == 'MWEB' ||
            client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER';
        // Only WEB_REMIX may carry the signed-in session. The other web-shaped
        // clients earn their place in this chain precisely by resolving *logged
        // out* on a flagged IP; authenticating them is an auth-context mismatch
        // that YouTube answers with LOGIN_REQUIRED / "confirm you're not a
        // bot". That is what disabled the working fallbacks the moment the user
        // signed in, and it fed the bot-block short-circuit below.
        final acceptsSessionAuth = useSessionAuth && client == 'WEB_REMIX';
        // The token must be bound to the identity the request is made under:
        // datasyncId for the authenticated pass, the videoId for a guest web
        // pass (serviceIntegrityDimensions), visitorData for a guest media URL.
        final poToken = acceptsSessionAuth
            ? accountPoToken
            : (isWeb ? playerPoToken : guestPoToken);
        final visitorData =
            acceptsSessionAuth ? accountVisitorData : guestVisitorData;
        // Diagnostics: the bot-gate log below reports whether a token was
        // actually attached, so "WEB_REMIX bot challenge" is immediately
        // attributable to missing attestation vs rejected attestation.
        final hadPoToken = poToken != null && poToken.isNotEmpty;
        final endpointHost = (client == 'ANDROID_MUSIC' ||
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
          'x-youtube-client-version': _versionResolver.clientVersionFor(client),
          'User-Agent': client == 'ANDROID_MUSIC'
              ? 'com.google.android.apps.youtube.music/${_versionResolver.androidMusicVersion} (Linux; U; Android 14; en_US) gzip'
              : (client == 'IOS_MUSIC'
                  ? 'com.google.ios.youtubemusic/${_versionResolver.iosMusicVersion} (iPhone15,3; U; CPU iOS 18_0 like Mac OS X; en_US)'
                  : (client == 'ANDROID_VR'
                      ? 'com.google.android.apps.youtube.vr.oculus/${_versionResolver.androidVrVersion} (Linux; U; Android 12; en_US; Quest 2) gzip'
                      : (client == 'ANDROID_CREATOR'
                          ? 'com.google.android.apps.youtube.creator/${_versionResolver.androidCreatorVersion} (Linux; U; Android 13; en_US) gzip'
                          : (client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER'
                              ? 'Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36'
                              : (client == 'ANDROID_TESTSUITE'
                                  ? 'com.google.android.youtube/1.9 (Linux; U; Android 9; gzip)'
                                  : (client == 'MWEB'
                                      ? 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36'
                                      : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36')))))),
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
          if (acceptsSessionAuth && _cookies != null && _cookies!.isNotEmpty) {
            headers['x-goog-authuser'] = '0';
            headers['Cookie'] = _cookies!;
            final authHeader =
                buildAuthorizationHeader(_cookies!, origin: origin);
            if (authHeader != null) {
              headers['Authorization'] = authHeader;
            }
          }
        } else {
          headers['X-Origin'] = endpointHost;
          // Keep mobile clients guest-only: attaching WEB session cookies to
          // ANDROID_MUSIC/IOS_MUSIC poisons the fallback that works logged-out
          // (YouTube returns LOGIN_REQUIRED for mismatched auth on these
          // endpoints). Authenticated playback is covered by WEB_REMIX above;
          // mobile clients stay as the guest fallback when login breaks it.
        }

        final clientContext = _buildClientContext(client, videoId);
        if (visitorData != null &&
            visitorData.isNotEmpty &&
            clientContext.containsKey('client') &&
            clientContext['client'] is Map) {
          (clientContext['client'] as Map)['visitorData'] = visitorData;
        }

        final isEmbedClient = client == 'TVHTML5_SIMPLY_EMBEDDED_PLAYER' ||
            client == 'WEB_EMBEDDED_PLAYER';
        final body = jsonEncode({
          'context': clientContext,
          'videoId': videoId,
          'racyCheckOk': true,
          'contentCheckOk': true,
          // TVHTML5 and WEB_EMBEDDED require thirdParty at the root body level
          // (in addition to context.thirdParty set by _buildClientContext).
          // Without this root-level field the server returns ERROR with no streamingData.
          if (isEmbedClient)
            'thirdParty': {
              'embedUrl': 'https://www.youtube.com/watch?v=$videoId'
            },
          // Web clients attest via root-level serviceIntegrityDimensions;
          // mobile clients read playbackContext.contentPlaybackContext.poToken.
          // Sending both keeps every client in the chain covered.
          if (isWeb && poToken != null && poToken.isNotEmpty)
            'serviceIntegrityDimensions': {'poToken': poToken},
          'playbackContext': {
            'contentPlaybackContext': {
              'html5Preference': 'HTML5_PREF_WANTS',
              if (_versionResolver.sts > 0)
                'signatureTimestamp': _versionResolver.sts,
              if (poToken != null && poToken.isNotEmpty) 'poToken': poToken,
            },
          },
        });


        final response = await _postWithRetry(
          Uri.parse(
              '$endpointHost/youtubei/v1/player?prettyPrint=false&key=$_apiKey'),
          headers: headers,
          body: body,
          baseTimeoutSeconds: 5,
          maxAttempts: 1,
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
                '[YTM_ACCOUNT] Client $client returned playability $status ($statusReason, poTokenAttached: $hadPoToken), falling back to next');

            // WEB_REMIX LOGIN_REQUIRED must never logout/throw mid-chain:
            // a single client can report LOGIN_REQUIRED for a bot challenge,
            // a guest-poToken/auth-cookie mismatch, or age-gating while the
            // session itself is still valid. Fall through to the remaining
            // (guest mobile/embed) clients; session expiry is decided by
            // validateSessionDetailed(), not by one player response.
            if (client == 'WEB_REMIX' &&
                status == 'LOGIN_REQUIRED' &&
                _cookies != null &&
                _cookies!.isNotEmpty) {
              debugPrint(
                  '[YTM_ACCOUNT] WEB_REMIX returned LOGIN_REQUIRED, trying next client without logout');
            }
            // IP-block / bot-challenge short-circuit: if two consecutive
            // clients both return genuine bot challenges, every
            // remaining client will too — skip the rest of the chain.
            // Note: UNPLAYABLE indicates per-client catalog restriction, NOT a bot block.
            final isBotBlock = status.contains('BOT') ||
                _botSubstrings.any((sub) =>
                    statusReason.toLowerCase().contains(sub.toLowerCase()));
            final isBlockSignal = isBotBlock ||
                (!acceptsSessionAuth && status == 'LOGIN_REQUIRED');
            if (isBlockSignal) {
              consecutiveBlockSignals++;
              if (consecutiveBlockSignals >= 2) {
                debugPrint(
                    '[YTM_ACCOUNT] Short-circuiting Dart chain: $consecutiveBlockSignals consecutive bot blocks for $videoId');
                return null;
              }
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
            final m4a = audioFormats
                .where((f) =>
                    ((f.format['mimeType'] as String?) ?? '').contains('mp4'))
                .toList();
            final pool = m4a.isNotEmpty ? m4a : audioFormats;

            final selected = switch (quality.toLowerCase()) {
              'low' => pool.reduce((a, b) =>
                  ((a.format['bitrate'] as num?) ?? 0) <
                          ((b.format['bitrate'] as num?) ?? 0)
                      ? a
                      : b),
              'medium' => pool.reduce((a, b) =>
                  (((a.format['bitrate'] as num?) ?? 128000) - 128000).abs() <
                          (((b.format['bitrate'] as num?) ?? 128000) - 128000)
                              .abs()
                      ? a
                      : b),
              _ => pool.reduce((a, b) => ((a.format['bitrate'] as num?) ?? 0) >
                      ((b.format['bitrate'] as num?) ?? 0)
                  ? a
                  : b),
            };

            final mime = selected.format['mimeType'] as String? ?? 'audio/mp4';
            final bitrate =
                (selected.format['bitrate'] as num?)?.toInt() ?? 128000;
            final durationMs = int.tryParse(
                    selected.format['approxDurationMs']?.toString() ?? '0') ??
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
              // Only a stream resolved under the session may be fetched with
              // the session. A guest client's URL must be played back as a
              // guest, or playback re-creates the very auth mismatch the chain
              // just worked around.
              cookies: acceptsSessionAuth ? _cookies : null,
              // The player response never states an expiry of its own, but the
              // URL it hands back always carries one. Left null, `isExpired` and
              // `isExpiringSoon` answer false for the whole ~6-hour life of the
              // URL and then keep answering false after it dies, so nothing
              // re-resolves and the URL cache stores it with the wrong lifetime.
            ).withResolvedExpiry();
          } else {
            debugPrint(
                '[YTM_ACCOUNT] Client $client returned status $status but no audio formats (adaptiveFormats: ${adaptive.length} total, streamingData: ${streamingData != null})');
            if (adaptive.isNotEmpty) {
              _markSabrDemoted(client);
            }
          }
        } else if (response.statusCode == 429 || response.statusCode == 403) {
          debugPrint(
              '[YTM_ACCOUNT] Client $client returned HTTP ${response.statusCode}');
          consecutiveBlockSignals++;
          if (consecutiveBlockSignals >= 2) {
            debugPrint(
                '[YTM_ACCOUNT] Short-circuiting Dart chain: $consecutiveBlockSignals consecutive block/rate-limit signals for $videoId');
            return null;
          }
        }
      } catch (e) {
        // Session-expiry must surface to callers/UI, not be swallowed as a
        // per-client resolution failure.
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint(
            '[YTM_ACCOUNT] Client $client resolution error for $videoId: $e');
      }
    }
    return null;
  }

  String? _extractUrlFromFormat(Map<String, dynamic> format) {
    final directUrl = format['url'] as String?;
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    // Ciphered formats require JS deciphering (signatureCipher `s` + `n` param).
    // Dart has no Rhino engine; returning the raw `url` without `sig=` produces
    // a 403. Let the native `InnertubeClient` / NewPipe tier (which does
    // `JsDecipherCache.decipherSignature`) handle it. Returning null forces the
    // Dart tier to be skipped and the native hedged race to run.
    final cipher = (format['signatureCipher'] ?? format['cipher']) as String?;
    if (cipher != null && cipher.isNotEmpty) {
      debugPrint('[YTM_ACCOUNT] Skipping ciphered format (itag ${format['itag']}) — needs native decipher');
      return null;
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

  String? _extractContinuationToken(dynamic node, [int depth = 0]) {
    // Iterative guard via depth cap: InnerTube payloads are shallow (<30);
    // anything deeper is malformed — bail instead of stack-overflowing.
    if (depth > 40) return null;
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
        final token = node['continuationEndpoint']?['continuationCommand']
            ?['token'] as String?;
        if (token != null && token.isNotEmpty) return token;
      }
      if (node.containsKey('continuationCommand')) {
        return node['continuationCommand']?['token'] as String?;
      }
      if (node.containsKey('nextRadioContinuationData')) {
        return node['nextRadioContinuationData']?['continuation'] as String?;
      }
      for (final val in node.values) {
        final token = _extractContinuationToken(val, depth + 1);
        if (token != null) return token;
      }
    } else if (node is List) {
      // Cap fan-out to avoid pathological payloads pinning the UI thread.
      final limit = node.length > 500 ? 500 : node.length;
      for (var i = 0; i < limit; i++) {
        final token = _extractContinuationToken(node[i], depth + 1);
        if (token != null) return token;
      }
    }
    return null;
  }

  /// Searches for a map containing [key] in the InnerTube JSON tree.
  Map<String, dynamic>? _findShelfNode(dynamic node, String key, [int depth = 0]) {
    if (depth > 25 || node == null) return null;
    if (node is Map<String, dynamic>) {
      if (node.containsKey(key) && node[key] is Map<String, dynamic>) {
        return node[key] as Map<String, dynamic>;
      }
      for (final val in node.values) {
        final found = _findShelfNode(val, key, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findShelfNode(item, key, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Extracts the continuation token strictly from a playlist shelf or continuation.
  /// Never extracts from Suggestions or unrelated shelves.
  String? _extractPlaylistContinuationToken(Map<String, dynamic> root) {
    // 1. Continuation response: continuationContents.musicPlaylistShelfContinuation or musicShelfContinuation
    final contContents = root['continuationContents'] as Map<String, dynamic>?;
    final playlistCont = contContents?['musicPlaylistShelfContinuation']
            as Map<String, dynamic>? ??
        contContents?['musicShelfContinuation'] as Map<String, dynamic>? ??
        _findShelfNode(root, 'musicPlaylistShelfContinuation') ??
        _findShelfNode(root, 'musicShelfContinuation');
    if (playlistCont != null) {
      return _extractTokenFromShelfContinuations(playlistCont);
    }

    // 2. Initial browse response: musicPlaylistShelfRenderer or musicShelfRenderer
    final playlistShelf = _findShelfNode(root, 'musicPlaylistShelfRenderer') ??
        _findShelfNode(root, 'musicShelfRenderer');
    if (playlistShelf != null) {
      return _extractTokenFromShelfContinuations(playlistShelf);
    }

    return null;
  }

  String? _extractTokenFromShelfContinuations(Map<String, dynamic> shelf) {
    final continuations = shelf['continuations'];
    if (continuations is List && continuations.isNotEmpty) {
      for (final c in continuations) {
        if (c is Map<String, dynamic>) {
          final nextData = c['nextContinuationData'];
          if (nextData is Map<String, dynamic>) {
            final token = nextData['continuation'] as String?;
            if (token != null && token.isNotEmpty) return token;
          }
          final contEndpoint = c['continuationEndpoint'];
          if (contEndpoint is Map<String, dynamic>) {
            final token = contEndpoint['continuationCommand']?['token'] as String?;
            if (token != null && token.isNotEmpty) return token;
          }
          final contCmd = c['continuationCommand'];
          if (contCmd is Map<String, dynamic>) {
            final token = contCmd['token'] as String?;
            if (token != null && token.isNotEmpty) return token;
          }
        }
      }
    }
    return null;
  }

  /// Parses tracks strictly belonging to a playlist.
  /// Ignores "Suggestions", "Related", and carousels so playlists only contain
  /// their actual tracks.
  List<YtmTrack> _parsePlaylistTracks(Map<String, dynamic> root) {
    // 1. Check for continuation response: musicPlaylistShelfContinuation or musicShelfContinuation
    final contContents = root['continuationContents'] as Map<String, dynamic>?;
    final playlistCont = contContents?['musicPlaylistShelfContinuation']
            as Map<String, dynamic>? ??
        contContents?['musicShelfContinuation'] as Map<String, dynamic>? ??
        _findShelfNode(root, 'musicPlaylistShelfContinuation') ??
        _findShelfNode(root, 'musicShelfContinuation');
    if (playlistCont != null) {
      final contents = playlistCont['contents'];
      if (contents is List) {
        final tracks = <YtmTrack>[];
        for (final item in contents) {
          if (item is Map<String, dynamic>) {
            final renderer = item['musicResponsiveListItemRenderer']
                as Map<String, dynamic>?;
            if (renderer != null) {
              final track = _parseListItemRenderer(renderer);
              if (track != null) tracks.add(track);
            }
          }
        }
        return tracks;
      }
    }

    // 2. Check for initial browse response: musicPlaylistShelfRenderer or musicShelfRenderer
    final playlistShelf = _findShelfNode(root, 'musicPlaylistShelfRenderer') ??
        _findShelfNode(root, 'musicShelfRenderer');
    if (playlistShelf != null) {
      final contents = playlistShelf['contents'];
      if (contents is List) {
        final tracks = <YtmTrack>[];
        for (final item in contents) {
          if (item is Map<String, dynamic>) {
            final renderer = item['musicResponsiveListItemRenderer']
                as Map<String, dynamic>?;
            if (renderer != null) {
              final track = _parseListItemRenderer(renderer);
              if (track != null) tracks.add(track);
            }
          }
        }
        return tracks;
      }
    }

    // 3. Fallback: For Next endpoint (playlistPanelVideoRenderer) or generic browse,
    // parse while strictly ignoring Suggestions and card carousels.
    return _parseInnertubePlaylistTracks(root, ignoreSuggestions: true);
  }

  /// Reads the account `datasyncId` from `responseContext.mainAppWebResponseContext.datasyncId`
  /// with fallbacks to `responseContext.datasyncId` or root `json['datasyncId']`.
  /// This is the raw content-binding for the account poToken (kept verbatim, incl. trailing `||`).
  String? _extractDataSyncId(Map<String, dynamic> json) {
    final rc = json['responseContext'];
    final mainApp = rc is Map<String, dynamic> ? rc['mainAppWebResponseContext'] : null;
    final id = (mainApp is Map<String, dynamic> ? mainApp['datasyncId'] : null) ??
        (rc is Map<String, dynamic> ? rc['datasyncId'] : null) ??
        json['datasyncId'];
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
      // FIX-C03: unawaited SharedPreferences write with catchError to prevent unhandled async errors
      unawaited(SharedPreferences.getInstance().then((p) {
        p.setString(_dataSyncIdPrefKey, dsid);
      }).catchError((e) {
        debugPrint('[YTM_ACCOUNT] Failed to persist dataSyncId: $e');
      }));
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

  /// Public, throttled trigger for [_bootstrapDataSyncId].
  ///
  /// Called when a resolve needs the account-bound poToken but no dataSyncId is
  /// known yet. Without this the only harvest sites were login and a cold-start
  /// `validateSession()`, so a session restored from storage whose validation
  /// was transiently blocked stayed on the guest chain forever and every
  /// signed-in resolve fell through to the native tier (where WEB_REMIX pairs
  /// session cookies with a guest poToken and returns "Video unavailable").
  Future<void> ensureDataSyncId() async {
    if (!isLoggedIn) return;
    final existing = _dataSyncId;
    if (existing != null && existing.isNotEmpty) return;
    if (_dataSyncBootstrapInFlight) return;
    final now = DateTime.now();
    final last = _lastDataSyncBootstrapAttempt;
    if (last != null && now.difference(last).inSeconds < 60) return;
    _lastDataSyncBootstrapAttempt = now;
    _dataSyncBootstrapInFlight = true;
    try {
      await _bootstrapDataSyncId();
    } finally {
      _dataSyncBootstrapInFlight = false;
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
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final before = _dataSyncId;
        _harvestSessionState(json);
        if ((_dataSyncId == null || _dataSyncId!.isEmpty) ||
            _dataSyncId == before) {
          debugPrint('[YTM_ACCOUNT] datasyncId bootstrap: HTTP 200 but no '
              'datasyncId in response (loggedIn=${!_isUnauthenticatedResponse(json)}, '
              'auth=${isOAuthSession ? 'oauth' : 'cookies'}). Account-bound '
              'playback will stay on the guest pass.');
        }
      } else {
        debugPrint('[YTM_ACCOUNT] datasyncId bootstrap: HTTP ${res.statusCode} '
            '(auth=${isOAuthSession ? 'oauth' : 'cookies'})');
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] datasyncId bootstrap failed: $e');
    }
  }

  List<YtmTrack> _parseInnertubePlaylistTracks(
    Map<String, dynamic> root, {
    bool ignoreSuggestions = false,
  }) {
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
          if (ignoreSuggestions) {
            final titleRuns = shelf['title']?['runs'] as List<dynamic>?;
            final titleText = titleRuns
                    ?.map((r) => r['text']?.toString() ?? '')
                    .join()
                    .toLowerCase() ??
                '';
            final isSuggestions = titleText.contains('suggestion') ||
                titleText.contains('suggested') ||
                titleText.contains('اقتراح') ||
                titleText.contains('sugerencia') ||
                titleText.contains('empfehlung');
            final hasReload = shelf.containsKey('bottomEndpoint') ||
                shelf.containsKey('reloadContinuationData');
            if (isSuggestions || hasReload) {
              return; // Skip suggestions shelf!
            }
          }
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
          final title = titleRuns?.isNotEmpty == true
              ? titleRuns![0]['text'] as String? ?? 'Unknown Title'
              : 'Unknown Title';
          final artistRuns =
              renderer['shortBylineText']?['runs'] as List<dynamic>?;
          final artist = artistRuns?.isNotEmpty == true
              ? artistRuns![0]['text'] as String? ?? 'Unknown Artist'
              : 'Unknown Artist';
          final lengthRuns = renderer['lengthText']?['runs'] as List<dynamic>?;
          final lengthText = lengthRuns?.isNotEmpty == true
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
          final artwork = thumbnails?.isNotEmpty == true
              ? thumbnails!.last['url'] as String?
              : null;

          if (videoId != null && videoId.length == 11) {
            tracks.add(YtmTrack(
              videoId: videoId,
              title: title,
              artist: artist,
              duration: Duration(milliseconds: durationMs),
              artworkUrl: artwork,
            ));
          }
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
          if (ignoreSuggestions) {
            return; // Skip album/playlist tiles in playlist track context
          }
          final renderer =
              node['musicTwoRowItemRenderer'] as Map<String, dynamic>;
          String? vid = renderer['navigationEndpoint']?['watchEndpoint']
              ?['videoId'] as String?;
          vid ??= renderer['thumbnailRenderer']?['musicThumbnailRenderer']
              ?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
          vid ??= renderer['thumbnailOverlay']
                      ?['musicItemThumbnailOverlayRenderer']?['content']
                  ?['musicPlayButtonRenderer']?['playNavigationEndpoint']
              ?['watchEndpoint']?['videoId'] as String?;
          vid ??= renderer['navigationEndpoint']?['watchPlaylistEndpoint']
              ?['videoId'] as String?;
          vid ??= renderer['onTap']?['watchEndpoint']?['videoId'] as String?;

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

      videoId ??= renderer['navigationEndpoint']?['watchEndpoint']?['videoId']
          as String?;
      videoId ??= renderer['overlay']?['musicItemThumbnailOverlayRenderer']
              ?['content']?['musicPlayButtonRenderer']
          ?['playNavigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
      videoId ??= renderer['doubleTapEndpoint']?['watchEndpoint']?['videoId']
          as String?;

      if (videoId == null || videoId.length != 11) {
        final flexColumns =
            renderer['flexColumns'] as List<dynamic>? ?? const [];
        for (final col in flexColumns) {
          final runs = col['musicResponsiveListItemFlexColumnRenderer']?['text']
              ?['runs'] as List<dynamic>?;
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
        final col0Runs = flexColumns[0]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col0Runs is List && col0Runs.isNotEmpty) {
          final t =
              col0Runs.map((r) => r['text']?.toString() ?? '').join('').trim();
          if (t.isNotEmpty) title = t;
        }
      }
      if (flexColumns.length > 1) {
        final col1Runs = flexColumns[1]
            ['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
        if (col1Runs is List && col1Runs.isNotEmpty) {
          final texts = col1Runs
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

  @disposeMethod
  void dispose() {
    _sessionHarvestDebounce?.cancel();
    loginState.dispose();
    try {
      _innertubeClient.close();
    } catch (_) {}
  }
}
