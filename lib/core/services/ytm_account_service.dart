// lib/core/services/ytm_account_service.dart
import 'dart:async';
import 'dart:convert';
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
import 'package:pulsr/core/services/ytm_account_models.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'ytm_account_models.dart';

import '../../domain/models/lyrics_line.dart';
import '../../domain/models/ytm_track.dart';
import '../constants/channels.dart';
import '../constants/embedded_browser_ua.dart';
import '../errors/ytm_error_classifier.dart';
import '../utils/error_logger.dart';
import '../utils/l10n_holder.dart';
import '../utils/input_sanitizer.dart';
import '../utils/lrc_parser.dart';
import '../utils/ytm_locale.dart';
import '../utils/ytm_rate_limiter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    hide AndroidOptions;
import 'ytm_cookie_codec.dart';
import 'ytm_media_helpers.dart';

part 'ytm_account_service_parsing.dart';
part 'ytm_account_service_datasync.dart';

enum SessionValidationResult {
  valid,
  invalid,
  unknown,
}

@lazySingleton
class YtmAccountService {
  String? _cachedLikedSongsBrowseId;
  bool _isFetchingLikedSongs = false;
  Future<List<YtmTrack>>? _likedSongsInFlight;
  int _sessionGeneration = 0;
  bool _disposed = false;
  Future<void>? _initFuture;

  YtmService? get _ytmService =>
      getIt.isRegistered<YtmService>() ? getIt<YtmService>() : null;

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
  http.Client? _innertubeClient;
  http.Client get _http => _innertubeClient ??= http.Client();

  /// Swaps in a scripted client so tests can drive the Tier-1 player chain's
  /// timing without touching the network.
  @visibleForTesting
  set debugInnertubeClient(http.Client client) {
    if (!identical(_innertubeClient, client)) {
      _innertubeClient?.close();
    }
    _innertubeClient = client;
  }

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
    debugPrint(
        '[YTM_ACCOUNT] Client $client marked SABR demoted for 10 minutes');
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

  /// Wording of YouTube's age wall, whatever client answered it.
  ///
  /// Kept next to [_botSubstrings] because the two were confused: an age wall
  /// says "sign in to confirm your age", which contains the bot phrase
  /// "sign in to confirm", so a +18 track used to count as an egress/bot
  /// verdict against the very chain that was trying to resolve it.
  static const _ageGateSubstrings = [
    'confirm your age',
    'confirm you are 18',
    "confirm you're 18",
    'age-restricted',
    'age restricted',
    'age verification',
    'inappropriate for some users',
    'mature content',
    'over 18',
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
  bool get isFetchingLikedSongs => _isFetchingLikedSongs;

  /// Raw datasyncId of the authenticated account — null until the first authenticated
  /// Innertube response is harvested. Used externally to gate account-bound poToken minting.
  String? get dataSyncId => _dataSyncId;
  String? get sessionVisitorData => _sessionVisitorData;

  String get _clientVersion => _versionResolver.clientVersion;
  String get _apiKey => _versionResolver.apiKey;

  Future<void> init() {
    if (_isInitialized) return Future.value();
    return _initFuture ??= _initImpl().whenComplete(() {
      _initFuture = null;
    });
  }

  Future<void> _initImpl() async {
    final initGen = _sessionGeneration;
    try {
      await _versionResolver.init();
      final rawNative = await getNativeCookiesFromDomains();
      if (_disposed || initGen != _sessionGeneration) return;
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
        final stored = await _readStoredCookies();
        if (_disposed || initGen != _sessionGeneration) return;
        _cookies = stored;
      }
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || initGen != _sessionGeneration) return;
      _accountName = prefs.getString(_accountNamePrefKey);
      _accountAvatar = prefs.getString(_accountAvatarPrefKey);
      _dataSyncId ??= prefs.getString(_dataSyncIdPrefKey);

      if (_cookies != null && _cookies!.isNotEmpty) {
        final ytmService = _ytmService;
        if (ytmService != null) {
          unawaited(ytmService.syncCookies(_cookies!));
          final dsid = _dataSyncId;
          if (dsid != null && dsid.isNotEmpty) {
            unawaited(ytmService.setDataSyncId(dsid));
          }
        }

        // Validate session asynchronously off the startup critical path so init() does
        // not block app launch or hit the 8-second startup timeout.
        final cookiesUnderValidation = _cookies;
        unawaited(() async {
          try {
            final ok = await validateSession();
            // A login/sign-out completed while the old jar was being checked:
            // never apply the stale verdict to the new session.
            if (_disposed ||
                initGen != _sessionGeneration ||
                _cookies != cookiesUnderValidation) {
              return;
            }
            if (!ok) {
              await _deleteStoredCookies(); // dead session: wipe, don't poison WebView
              _cookies = null;
              _accountName = null;
              _accountAvatar = null;
              _clearAccountScopedCaches();
              try {
                final p = await SharedPreferences.getInstance();
                await p.remove(_accountNamePrefKey);
                await p.remove(_accountAvatarPrefKey);
                await p.remove(_dataSyncIdPrefKey);
              } catch (_) {}
              loginState.value = isLoggedIn;
              final service = _ytmService;
              if (service != null) {
                try {
                  await service.clearNativeSession();
                  await service.syncCookies('');
                } catch (e, st) {
                  ErrorLogger.log(
                    'Failed clearing native YTM session after invalid boot check',
                    error: e,
                    stackTrace: st,
                    category: 'YTM_ACCOUNT',
                  );
                }
              }
            } else {
              final freshDsid = _dataSyncId;
              if (freshDsid != null && freshDsid.isNotEmpty) {
                await _ytmService?.setDataSyncId(freshDsid);
              }
              if (_cookies != null && _cookies!.isNotEmpty) {
                await _persistCookies(_cookies!);
              }
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
          if (_disposed || initGen != _sessionGeneration) return;
          if (oauth.isSignedIn) {
            _oauthAccessToken = oauth.accessToken;
            _accountName ??= 'Google TV';
            unawaited(() async {
              try {
                final refreshed = await oauth.ensureFresh();
                if (_disposed || initGen != _sessionGeneration) return;
                if (refreshed) {
                  _oauthAccessToken = oauth.accessToken;
                } else if (oauth.lastRefreshFailedTerminally ||
                    !oauth.isSignedIn) {
                  await logout();
                }
              } catch (_) {}
            }());
          }
        } catch (e) {
          debugPrint('[YTM_ACCOUNT] OAuth session restore failed: $e');
        }
      }

      if (_disposed || initGen != _sessionGeneration) return;
      _isInitialized = true;
      loginState.value = isLoggedIn;

      // A session restored from storage may have no dataSyncId (validation was
      // transiently blocked, or the harvest response lacked it). Bootstrap it in
      // the background so signed-in resolves can mint an account-bound poToken
      // instead of endlessly falling through to the guest chain.
      if (isLoggedIn &&
          !isOAuthSession &&
          (_dataSyncId == null || _dataSyncId!.isEmpty)) {
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
      final res = isOAuthSession
          ? await _postWithRetry(
              Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
              headers: _buildHeaders(),
              body: jsonEncode({
                'context': _buildClientContext('WEB_REMIX'),
                'browseId': 'FEmusic_library_playlists',
              }),
              baseTimeoutSeconds: 5,
              maxAttempts: 1,
            )
          : await _postWithRetry(
              Uri.parse(
                  'https://www.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&key=$_apiKey'),
              headers: _buildHeaders(origin: 'https://www.youtube.com')
                ..['x-youtube-client-name'] = '1'
                ..['x-youtube-client-version'] =
                    _versionResolver.webClientVersion,
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': _versionResolver.webClientVersion,
                  },
                },
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
      final hasIdentity = _extractDataSyncId(json) != null ||
          _findShelfNode(json, 'activeAccountHeaderRenderer') != null;
      if (hasIdentity) {
        return SessionValidationResult.valid;
      }
      if (isOAuthSession &&
          (json.containsKey('contents') || json.containsKey('header'))) {
        return SessionValidationResult.valid;
      }
      // Ambiguous browse stub (e.g. test fixtures with `contents` only) stays
      // unknown so non-auth payloads never forge `.valid`, while responses
      // without identity or browse contents (logged-out menu) are invalid.
      if (json.containsKey('contents')) {
        return SessionValidationResult.unknown;
      }
      return SessionValidationResult.invalid;
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
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  static String normalizeCookieHeader(String raw) =>
      YtmCookieCodec.normalizeCookieHeader(raw);

  static String scopeCookiesForYouTube(String raw) =>
      YtmCookieCodec.scopeCookiesForYouTube(raw);

  void _clearAccountScopedCaches() {
    _dataSyncId = null;
    _sessionVisitorData = null;
    _cachedLikedSongsBrowseId = null;
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        getIt<YtmUrlCache>().clear();
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    try {
      if (getIt.isRegistered<YtmBrowseService>()) {
        getIt<YtmBrowseService>().clearCache();
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  void _notifyLoginState(bool loggedIn) {
    if (loginState.value == loggedIn && loggedIn) {
      // Force notification on re-login / account switch while already marked logged in.
      loginState.value = false;
    }
    loginState.value = loggedIn;
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
    final gen = ++_sessionGeneration;
    _oauthAccessToken = null;
    _accountAvatar = null;
    _clearAccountScopedCaches();
    _cookies = jar;
    await _persistCookies(jar);
    if (_disposed || gen != _sessionGeneration) return false;

    // Sync to native CookieManager and invalidate stale poTokens
    final ytmService = _ytmService;
    if (ytmService != null) {
      await ytmService.syncCookies(jar);
      await ytmService.invalidatePoToken();
    }

    // ACCOUNT_CHOOSER / LOGIN_INFO hold opaque base64 blobs, not human names.
    // Use a stable honest label; real account metadata is harvested later.
    const name = 'YouTube Music Account';
    _accountName = name;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || gen != _sessionGeneration) return false;
    await prefs.setString(_accountNamePrefKey, name);
    await prefs.remove(_accountAvatarPrefKey);
    await prefs.remove(_dataSyncIdPrefKey);

    _notifyLoginState(true);

    // Eagerly bootstrap session state in the background so dataSyncId is ready
    // before the first playSong call. Run in unawaited block so saveSession
    // returns immediately to the login UI without hanging for up to 45s.
    unawaited(() async {
      try {
        await _warmSession();
      } catch (e) {
        debugPrint('[YTM_ACCOUNT] Session warming failed (non-fatal): $e');
      }
      if (_disposed || gen != _sessionGeneration) return;
      // If _warmSession didn't harvest a dataSyncId (e.g. home browse returned
      // an unexpected shape), do an explicit lightweight bootstrap fetch.
      if (_dataSyncId == null || _dataSyncId!.isEmpty) {
        debugPrint(
            '[YTM_ACCOUNT] dataSyncId not yet available after warm, bootstrapping...');
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
  Future<void> adoptOAuthSession() async {
    final gen = ++_sessionGeneration;
    final oauth = YtmOAuthService.shared;
    await oauth.init();
    if (!await oauth.ensureFresh()) return;
    if (_disposed || gen != _sessionGeneration) return;
    _cookies = null;
    _clearAccountScopedCaches();
    _oauthAccessToken = oauth.accessToken;
    _accountName = 'Google TV';
    _accountAvatar = null;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || gen != _sessionGeneration) return;
    await prefs.setString(_accountNamePrefKey, _accountName!);
    await prefs.remove(_accountAvatarPrefKey);
    await prefs.remove(_dataSyncIdPrefKey);
    _notifyLoginState(isLoggedIn);
    // Warm session state (visitorData) off the critical path.
    unawaited(() async {
      try {
        if (_disposed || gen != _sessionGeneration) return;
        await _warmSession();
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }());
  }

  Future<void> logout() async {
    _sessionGeneration++;
    _cookies = null;
    _oauthAccessToken = null;
    _accountName = null;
    _accountAvatar = null;
    // Account-scoped browse and stream caches: must not leak into the next
    // account's library fetch or playback after a switch.
    _clearAccountScopedCaches();
    await _deleteStoredCookies();
    try {
      await YtmOAuthService.shared.signOut();
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountNamePrefKey);
    await prefs.remove(_accountAvatarPrefKey);
    await prefs.remove(_dataSyncIdPrefKey);
    loginState.value = false;

    // The WebView jar first: the native store re-reads it whenever its own prefs
    // are empty, so clearing native before the jar leaves a window (and, if the
    // jar survives, a cold start) in which the session comes straight back.
    try {
      await _deleteSessionWebViewCookies();
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    try {
      final ytmService = _ytmService;
      if (ytmService != null) {
        // Marks the native store signed out, expires the tracked cookie names in
        // CookieManager, and drops the account-bound poToken + dataSyncId. Plain
        // `syncCookies('')` does none of the last three.
        await ytmService.clearNativeSession();
        await ytmService.syncCookies('');
        await ytmService.invalidatePoToken();
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  /// Cookie scopes owned by the YTM sign-in flow, as `(url, domain)` pairs.
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
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    if (deletedAny) return;
    // Scoped deletion unsupported on this platform — fall back to a full wipe
    // rather than leaving session cookies behind.
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
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
          debugPrint(
              '[YTM_ACCOUNT] Warmed session returned unauthenticated — keeping session, notifying expiry check');
          _ytmService?.notifyAuthExpired();
          return;
        }
        try {
          _harvestSessionState(json);
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        // Set-Cookie is now ingested for every 2xx in _postWithRetry, so this
        // path no longer needs its own copy.
        debugPrint('[YTM_ACCOUNT] Session warmed successfully');
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] Session warming error (non-fatal): $e');
    }
  }
  static List<String> splitSetCookies(String header) =>
      YtmCookieCodec.splitSetCookies(header);

  static String mergeSetCookieInto(String current, String setCookieHeader) =>
      YtmCookieCodec.mergeSetCookieInto(current, setCookieHeader);

  void _ingestSetCookies(String setCookieHeader) {
    final current = _cookies ?? '';
    final merged = mergeSetCookieInto(current, setCookieHeader);
    if (merged.isEmpty || merged == current) return;

    _cookies = merged;
    // Persist via the secure-storage path — never a plaintext prefs copy.
    unawaited(_persistCookies(merged));
    // Keep the native cookie store (used by the extractor) in sync with the
    // refreshed jar so the two layers never drift apart.
    final ytm = _ytmService;
    if (ytm != null) {
      unawaited(ytm.syncCookies(merged));
    }
  }

  /// Hydrates cookie jar from native CookieManager only when no OAuth session
  /// or in-memory cookie jar is active, so background/native cookies never
  /// overwrite an OAuth session or rotated session cookies.
  Future<void> _maybeHydrateNativeCookies() async {
    if (isOAuthSession || (_cookies != null && _cookies!.isNotEmpty)) return;
    try {
      final rawNative = await getNativeCookiesFromDomains();
      final nativeCookies =
          rawNative == null ? null : scopeCookiesForYouTube(rawNative);
      if (nativeCookies != null &&
          nativeCookies.isNotEmpty &&
          looksLikeSignedInCookies(nativeCookies) &&
          !isOAuthSession &&
          (_cookies == null || _cookies!.isEmpty)) {
        _cookies = nativeCookies;
        unawaited(_persistCookies(nativeCookies));
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
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
  Map<String, String>? _resignHeaders(Map<String, String>? headers) {
    if (headers == null) return null;
    if (!isLoggedIn) {
      if (!headers.containsKey('Cookie') &&
          !headers.containsKey('Authorization') &&
          !headers.containsKey('x-goog-authuser')) {
        return headers;
      }
      return Map<String, String>.from(headers)
        ..remove('Cookie')
        ..remove('Authorization')
        ..remove('x-goog-authuser');
    }
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

  static bool looksLikeSignedInCookies(String rawCookies) =>
      YtmCookieCodec.looksLikeSignedInCookies(rawCookies);

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
        throw const YtmException('IP_BLOCKED', 'IP block circuit breaker open');
      }
    }

    // Keep the OAuth bearer fresh before the first request of a paging walk.
    if (isOAuthSession) {
      try {
        if (await YtmOAuthService.shared.ensureFresh()) {
          _oauthAccessToken = YtmOAuthService.shared.accessToken;
        } else if (_oauthAccessToken != null && _oauthAccessToken!.isNotEmpty) {
          if (YtmOAuthService.shared.lastRefreshFailedTerminally) {
            // Expired AND the server rejected the refresh grant: the session
            // is dead. Tear it down so the UI stops claiming it is connected.
            await logout();
            throw const YtmException('YTM_AUTH', 'Session expired');
          }
          // Network/timeout: keep the session; fail this request only.
          throw const YtmException(
              'YTM_OFFLINE', 'Could not refresh the session while offline');
        }
      } on YtmException {
        rethrow;
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }
    var oauthRetriedAfter401 = false;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await YtmRateLimiter.shared
            .acquirePermit(maxWait: const Duration(seconds: 10));
        final timeout = Duration(seconds: baseTimeoutSeconds + attempt * 5);
        final res = await _http
            .post(uri, headers: _resignHeaders(headers), body: body)
            .timeout(timeout);
        // A 401 on an OAuth session is an expired bearer: refresh and retry
        // once even when maxAttempts == 1 (e.g. validation calls).
        if (res.statusCode == 401 &&
            isOAuthSession &&
            !oauthRetriedAfter401) {
          oauthRetriedAfter401 = true;
          final refreshed = await YtmOAuthService.shared.refresh();
          if (refreshed) {
            _oauthAccessToken = YtmOAuthService.shared.accessToken;
            attempt--;
            continue;
          }
          if (YtmOAuthService.shared.lastRefreshFailedTerminally) {
            // Refresh rejected by the server: the bearer is dead. Invalidate
            // the session so the UI stops claiming it is connected.
            await logout();
            throw const YtmException('YTM_AUTH', 'Session expired');
          }
          // Transient refresh failure (offline/timeout): keep the session and
          // report a retryable offline error instead of signing the user out.
          throw const YtmException(
              'YTM_OFFLINE', 'Could not refresh the session while offline');
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
            // A single 403 is often a private/members-only/geo refusal, not an
            // IP ban. Opening the global 10-minute IP breaker on it took
            // library/browse/search down entirely. Only arm the breaker when
            // the body carries a real bot/interstitial verdict.
            final verdict =
                YtmErrorClassifier.classifyCode('response', res.body);
            if (verdict.signal == YtmBlockSignal.botChallenge) {
              breaker?.recordFailure(YtmBlockSignal.botChallenge);
            }
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
              } catch (_) {
                // Best-effort: failure intentionally ignored on this non-critical path.
              }
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
            _ytmService?.notifyAuthExpired();
            continue;
          }

          _harvestSessionState(json);
          final playlists = _parseInnertubeAccountPlaylists(json);
          var currentJson = json;
          final seenTokens = <String>{};

          if (playlists.isEmpty) {
            final initToken = _extractContinuationToken(json);
            if (initToken != null &&
                initToken.isNotEmpty &&
                seenTokens.add(initToken)) {
              final contRes = await _postWithRetry(
                Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                headers: headers,
                body: jsonEncode({
                  'context': _buildClientContext('WEB_REMIX'),
                  'continuation': initToken,
                }),
              );
              if (contRes.statusCode == 200) {
                final contJson =
                    jsonDecode(contRes.body) as Map<String, dynamic>;
                _harvestSessionState(contJson);
                final contPlaylists =
                    _parseInnertubeAccountPlaylists(contJson);
                if (contPlaylists.isNotEmpty) {
                  playlists.addAll(contPlaylists);
                  currentJson = contJson;
                }
              }
            }
          }

          if (playlists.isNotEmpty) {
            final seenIds = {for (final p in playlists) p.playlistId};
            var pageCount = 0;
            const maxPages = 10;
            while (pageCount < maxPages) {
              pageCount++;
              final ctoken = _extractContinuationToken(currentJson);
              if (ctoken == null ||
                  ctoken.isEmpty ||
                  !seenTokens.add(ctoken)) {
                break;
              }
              try {
                final contRes = await _postWithRetry(
                  Uri.parse('$_innertubeBrowseUrl&key=$_apiKey'),
                  headers: headers,
                  body: jsonEncode({
                    'context': _buildClientContext('WEB_REMIX'),
                    'continuation': ctoken,
                  }),
                );
                if (contRes.statusCode != 200) break;
                currentJson =
                    jsonDecode(contRes.body) as Map<String, dynamic>;
                _harvestSessionState(currentJson);
                final more = _parseInnertubeAccountPlaylists(currentJson);
                final added =
                    more.where((p) => seenIds.add(p.playlistId)).toList();
                if (added.isEmpty) break;
                playlists.addAll(added);
              } catch (e) {
                debugPrint(
                    '[YTM_ACCOUNT] Account playlists continuation error on page $pageCount: $e');
                break;
              }
            }
            return playlists;
          }
        }
      } catch (e) {
        if (e is YtmException && e.isAuth) rethrow;
        debugPrint(
            '[YTM_ACCOUNT] Failed fetching account playlists ($bId): $e');
        if (e is YtmException &&
            (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
          break;
        }
      }
    }
    return [];
  }

  /// Fetches private Liked Music playlist (VLLM, FEmusic_liked_videos, LM).
  Future<List<YtmTrack>> fetchLikedSongs({int maxTracks = 200}) {
    if (!isLoggedIn) {
      return Future.error(
        const YtmException('YTM_AUTH', 'Not signed in to YouTube Music'),
      );
    }
    final existing = _likedSongsInFlight;
    if (existing != null) {
      return existing.then((tracks) => tracks.take(maxTracks).toList());
    }
    _isFetchingLikedSongs = true;
    late final Future<List<YtmTrack>> future;
    future = _fetchLikedSongsImpl(maxTracks: maxTracks).whenComplete(() {
      if (identical(_likedSongsInFlight, future)) {
        _likedSongsInFlight = null;
        _isFetchingLikedSongs = false;
      }
    });
    _likedSongsInFlight = future;
    return future;
  }

  Future<List<YtmTrack>> _fetchLikedSongsImpl({int maxTracks = 200}) async {
    try {
      await _maybeHydrateNativeCookies();

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
          if (e is YtmException &&
              (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
            break;
          }
        }
      }

      final breaker =
          getIt.isRegistered<YtmService>() ? getIt<YtmService>().breaker : null;
      final isBlocked = breaker != null &&
          (!breaker.shouldAllow(YtmBlockSignal.botChallenge) ||
              !breaker.shouldAllow(YtmBlockSignal.rateLimited) ||
              !breaker.shouldAllow(YtmBlockSignal.ipBlocked));

      if (!isBlocked) {
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
                debugPrint('[YTM_ACCOUNT] Next endpoint $pId parsed nothing '
                    '(${response.body.length} B, keys: ${json.keys.take(8).join(', ')})');
              }
            }
          } catch (e) {
            debugPrint('[YTM_ACCOUNT] Next endpoint query error for $pId: $e');
            if (e is YtmException &&
                (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
              break;
            }
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
          debugPrint(
              '[YTM_ACCOUNT] Account playlists liked resolution error: $e');
        }

        // Try Native Kotlin Innertube browse with full WebView cookie jar
        try {
          debugPrint(
              '[YTM_ACCOUNT] Attempting Native Kotlin Innertube fallback for liked songs...');
          final ytmService = _ytmService;
          final nativeTracks = ytmService == null
              ? const <YtmTrack>[]
              : await ytmService.getPlaylistTracks('VLLM', limit: maxTracks);
          if (nativeTracks.isNotEmpty) {
            debugPrint(
                '[YTM_ACCOUNT] Native Kotlin fallback returned ${nativeTracks.length} liked songs');
            return nativeTracks.take(maxTracks).toList();
          }
        } catch (e) {
          debugPrint('[YTM_ACCOUNT] Native Kotlin fallback failed: $e');
        }
      }

      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Fetches details and tracks for any YouTube / YouTube Music playlist by URL or ID.
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
        title: L10nHolder.current?.likedMusic ?? 'Liked Music',
        author: L10nHolder.current?.ytmAutoPlaylistAuthor ?? 'Auto Playlist',
        artworkUrl: likedTracks.firstOrNull?.artworkUrl,
        tracks: likedTracks,
      );
    }

    await _maybeHydrateNativeCookies();

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

            // Follow continuation pages up to maxTracks. The page cap mirrors
            // fetchLikedSongs so a full 5,000-item playlist is reachable.
            var pageCount = 0;
            const maxPages = 100;
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
        final contents = json['contents'];
        final singleColumn = contents is Map<String, dynamic>
            ? contents['singleColumnMusicWatchNextResultsRenderer']
            : null;
        final playlistNode = singleColumn is Map<String, dynamic>
            ? singleColumn['playlist']
            : null;
        final panel = playlistNode is Map<String, dynamic>
            ? playlistNode['playlistPanelRenderer']
            : null;
        if (panel is Map<String, dynamic>) {
          if (panel['title'] is String &&
              (panel['title'] as String).trim().isNotEmpty) {
            playlistTitle = (panel['title'] as String).trim();
          } else if (panel['title']?['runs'] is List) {
            final t = (panel['title']['runs'] as List)
                .map((r) => r['text']?.toString() ?? '')
                .join()
                .trim();
            if (t.isNotEmpty) playlistTitle = t;
          } else if (panel['title']?['simpleText'] != null) {
            final t = panel['title']['simpleText'].toString().trim();
            if (t.isNotEmpty) playlistTitle = t;
          }
        }
        final headerInfo = _extractPlaylistHeaderInfo(json);
        if (headerInfo['title'] != null &&
            headerInfo['title']!.isNotEmpty &&
            headerInfo['title'] != 'YouTube Playlist' &&
            !headerInfo['title']!.startsWith('Playlist (')) {
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
            artworkUrl: playlistArtwork ?? uniqueTracks.firstOrNull?.artworkUrl,
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

  /// Fetches radio / autoplay tracks for a given videoId via the InnerTube /next endpoint.
  Future<List<YtmTrack>> fetchRadioTracks(
    String videoId, {
    int maxTracks = 25,
  }) async {
    if (videoId.isEmpty) return const [];
    try {
      final headers = _buildHeaders();
      final body = jsonEncode({
        'context': _buildClientContext('WEB_REMIX'),
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
      });
      final response = await _postWithRetry(
        Uri.parse(
            'https://music.youtube.com/youtubei/v1/next?prettyPrint=false&key=$_apiKey'),
        headers: headers,
        body: body,
        baseTimeoutSeconds: 10,
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final tracks = _parseInnertubePlaylistTracks(json);
        if (tracks.isNotEmpty) {
          final seen = <String>{};
          final unique = <YtmTrack>[];
          for (final t in tracks) {
            if (t.videoId != videoId && seen.add(t.videoId)) {
              unique.add(t);
              if (unique.length >= maxTracks) break;
            }
          }
          if (unique.isNotEmpty) return unique;
        }
      }
    } catch (e) {
      debugPrint('[YTM_ACCOUNT] fetchRadioTracks error for $videoId: $e');
    }

    // Fallback: try playlist fetch with RDAMVM$videoId
    try {
      final fallbackTracks =
          await fetchPlaylistTracks('RDAMVM$videoId', maxTracks: maxTracks);
      return fallbackTracks.where((t) => t.videoId != videoId).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, String?> _extractPlaylistHeaderInfo(Map<String, dynamic> root) {
    String? title;
    String? author;
    String? artwork;

    void checkHeaderNode(Map<String, dynamic> header) {
      if (title == null) {
        if (header['title'] is String) {
          final t = (header['title'] as String).trim();
          if (t.isNotEmpty && t != 'YouTube Playlist' && t != 'Playlist') {
            title = t;
          }
        } else if (header['title'] is Map) {
          final titleObj = header['title'] as Map<String, dynamic>;
          final titleRuns = titleObj['runs'] as List<dynamic>?;
          if (titleRuns != null && titleRuns.isNotEmpty) {
            final t =
                titleRuns.map((r) => r['text']?.toString() ?? '').join().trim();
            if (t.isNotEmpty && t != 'YouTube Playlist' && t != 'Playlist') {
              title = t;
            }
          }
          if (title == null && titleObj['simpleText'] != null) {
            final t = titleObj['simpleText'].toString().trim();
            if (t.isNotEmpty && t != 'YouTube Playlist' && t != 'Playlist') {
              title = t;
            }
          }
          if (title == null && titleObj['text'] != null) {
            final t = titleObj['text'].toString().trim();
            if (t.isNotEmpty && t != 'YouTube Playlist' && t != 'Playlist') {
              title = t;
            }
          }
        }
      }

      // Prioritize straplineTextOne / straplineText / owner as they contain the actual author/creator
      final straplineRuns = (header['straplineTextOne']?['runs'] ??
          header['straplineText']?['runs'] ??
          header['strapline']?['runs'] ??
          header['owner']?['runs'] ??
          header['shortBylineText']?['runs']) as List<dynamic>?;
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

      final thumbRenderer = header['thumbnail']
              ?['croppedSquareThumbnailRenderer'] ??
          header['thumbnail']?['musicThumbnailRenderer'];
      final thumbs = (thumbRenderer?['thumbnail']?['thumbnails'] ??
          header['thumbnail']?['thumbnails']) as List<dynamic>?;
      if (thumbs != null && thumbs.isNotEmpty && artwork == null) {
        artwork = thumbs.last['url'] as String?;
      }
    }

    void traverse(dynamic node) {
      if (node is Map<String, dynamic>) {
        const headerKeys = [
          'musicDetailHeaderRenderer',
          'musicResponsiveHeaderRenderer',
          'musicVisualHeaderRenderer',
          'musicHeaderRenderer',
          'playlistHeaderRenderer',
          'playlistPanelRenderer',
          'playlistPanelHeaderRenderer',
        ];
        for (final k in headerKeys) {
          if (node.containsKey(k) && node[k] is Map<String, dynamic>) {
            checkHeaderNode(node[k] as Map<String, dynamic>);
          }
        }
        if (node.containsKey('musicEditablePlaylistDetailHeaderRenderer')) {
          final ed = node['musicEditablePlaylistDetailHeaderRenderer']
              as Map<String, dynamic>;
          final inner = ed['header']?['musicResponsiveHeaderRenderer']
              as Map<String, dynamic>?;
          if (inner != null) checkHeaderNode(inner);
        }
        for (final entry in node.entries) {
          if (entry.key.endsWith('HeaderRenderer') &&
              entry.value is Map<String, dynamic>) {
            checkHeaderNode(entry.value as Map<String, dynamic>);
          }
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

    await _maybeHydrateNativeCookies();

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
            final dataList = timedShelf['timedLyricsData'] as List<dynamic>?;
            if (dataList != null && dataList.isNotEmpty) {
              for (final item in dataList) {
                if (item is Map<String, dynamic>) {
                  String text = '';
                  final lyricLine = item['lyricLine'];
                  if (lyricLine is String) {
                    text = lyricLine;
                  } else if (lyricLine is Map &&
                      lyricLine.containsKey('runs')) {
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
  Future<String?> _mintPlayerPoToken(String videoId) async {
    final ytm = _ytmService;
    if (ytm == null) return null;
    try {
      return await ytm
          .getPlayerPoToken(videoId)
          .timeout(const Duration(seconds: 4));
    } catch (e, st) {
      ErrorLogger.log('Failed to mint content-bound player poToken',
          error: e, stackTrace: st, category: 'YTM_ACCOUNT');
      return null;
    }
  }

  /// [guestClientsEnabled] false restricts the chain to the clients that accept
  /// the signed-in session (WEB_REMIX), skipping the guest client sweep. The
  /// guest sweep duplicates the native extractor request for request and cannot
  /// decipher a ciphered format, so the player passes `false` when it already
  /// knows the pass is a guest one and the native chain is running alongside.
  /// Defaults to true: the age-gate rescue and the alternate-stream search must
  /// keep walking the full chain.
  Future<YtmStream?> resolvePlayerStream(String videoId,
      {String quality = 'high', bool guestClientsEnabled = true}) async {
    try {
      return await _resolvePlayerStreamInternal(videoId,
              quality: quality, guestClientsEnabled: guestClientsEnabled)
          .timeout(const Duration(seconds: 50));
    } on TimeoutException {
      debugPrint(
          '[YTM_ACCOUNT] Global stream resolution timed out after 50s for $videoId');
      return null;
    }
  }

  Future<YtmStream?> _resolvePlayerStreamInternal(String videoId,
      {String quality = 'high', bool guestClientsEnabled = true}) async {
    // BotGuard requires a poToken on WEB_REMIX player requests regardless of login.
    // Authenticated → the token must be content-bound to the account's datasyncId, sent WITH
    // the session cookies + SAPISIDHASH. Unauthenticated → a guest token bound to guest visitorData.
    final isAuthenticated =
        isLoggedIn && _cookies != null && _cookies!.isNotEmpty;

    // Without a session and without the guest clients there is no request this
    // chain can make that the native extractor is not already making better (it
    // can decipher). Bail before the warm-ups rather than spend them on a dead
    // chain — this is the guest pass's whole point.
    final boundDsid = _dataSyncId;
    if (!guestClientsEnabled &&
        (!isAuthenticated || boundDsid == null || boundDsid.isEmpty)) {
      debugPrint('[YTM_ACCOUNT] Guest clients disabled and no account-bound '
          'session for $videoId — handing off to the native tier.');
      return null;
    }

    // The session warm-up (a browse round-trip) and the BotGuard warm-up (a
    // local generator spin-up) touch different subsystems, so they are started
    // together and only awaited afterwards: queued back-to-back they put up to
    // 5 s of pure waiting in front of the first /player request on a cold
    // start, which is exactly the budget the cold bucket does not have.
    final sessionWarm = (_dataSyncId == null && isAuthenticated)
        ? _warmSession().timeout(const Duration(seconds: 3), onTimeout: () {})
        : Future<void>.value();
    // Warm the native BotGuard attestation once so both the account-bound and
    // guest minting below have a live generator instead of a cold WebView.
    final tokenReady = () async {
      final ytm = _ytmService;
      if (ytm == null) return;
      try {
        await ytm.ensurePoTokenReady().timeout(const Duration(seconds: 2));
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }();
    await sessionWarm;
    await tokenReady;

    // Two attestation pairs, kept strictly apart. A poToken is only valid for
    // the identity it was minted against, and the session cookies are only
    // valid alongside the account-bound one — so the authenticated WEB_REMIX
    // request uses (account token, session visitorData, cookies) while every
    // guest client in the chain uses (guest token, guest visitorData, no
    // cookies). Crossing them is what YouTube answers with LOGIN_REQUIRED /
    // "confirm you're not a bot".
    String? accountPoToken;
    String? accountVisitorData;
    bool hadAccountPoToken =
        false; // true only when account-bound token minted successfully
    // Whether this pass may carry the session (cookies + SAPISIDHASH). Only an
    // account-bound poToken earns that; otherwise the pass runs as a clean guest.
    var useSessionAuth = isAuthenticated;

    // Guest pair, needed by every non-WEB_REMIX client in the chain even when
    // signed in — those clients are only reachable as guests. Started right
    // after the generator is ready: it only *reads* PoTokenManager, so it runs
    // alongside the account-bound / content-bound mints instead of queueing
    // behind them.
    String? guestPoToken;
    String? guestVisitorData;
    // Only the guest clients read this pair; with them disabled the whole read
    // (a 2 s-bounded platform round-trip) is dead weight in front of a request
    // that will not be made.
    final guestState = !guestClientsEnabled
        ? Future<void>.value()
        : () async {
            final ytm = _ytmService;
            if (ytm == null) return;
            try {
              final poState = await ytm
                  .getPoTokenState()
                  .timeout(const Duration(seconds: 2));
              guestPoToken = poState?['streamingPoToken'] as String?;
              guestVisitorData = poState?['visitorData'] as String?;
            } catch (_) {
              // Best-effort: failure intentionally ignored on this non-critical path.
            }
          }();

    Future<Map<String, dynamic>?>? accountMint;
    // Web-shaped clients send the token as `serviceIntegrityDimensions`, which
    // must be bound to the *video*; the visitor-bound streaming token makes
    // YouTube answer UNPLAYABLE "Video unavailable" even though a token is
    // attached. Mint the content-bound one up front (null when unavailable, in
    // which case the request goes out without a token rather than the wrong one).
    Future<String?>? playerMint;

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
        final ytm = _ytmService;
        if (ytm != null) {
          accountMint = () async {
            final account = await ytm
                .getAccountPoToken(dsid)
                .timeout(const Duration(seconds: 2));
            return account;
          }();
        }
      }
    }
    if (!useSessionAuth) {
      playerMint = _mintPlayerPoToken(videoId);
    }

    if (accountMint != null) {
      try {
        final account = await accountMint;
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
        // With the guest clients disabled there is nothing to demote *to*: the
        // session-bearing client needs the token that just failed to mint.
        if (!guestClientsEnabled) {
          debugPrint(
              '[YTM_ACCOUNT] Account-bound poToken unavailable for $videoId and '
              'guest clients are disabled — handing off to the native tier.');
          return null;
        }
        debugPrint(
            '[YTM_ACCOUNT] Account-bound poToken unavailable for $videoId — '
            'running Tier-1 as a guest pass (no session cookies).');
        useSessionAuth = false;
        accountPoToken = null;
        accountVisitorData = null;
      }
    }

    String? playerPoToken;
    if (!useSessionAuth && guestClientsEnabled) {
      // The account mint may be what demoted this pass to a guest one, so the
      // content-bound token is only awaited here when it could not be started
      // up front. [_mintPlayerPoToken] never throws.
      playerMint ??= _mintPlayerPoToken(videoId);
      playerPoToken = await playerMint;
    }
    await guestState;

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

    // A guest-restricted pass keeps only the session-bearing client: every
    // other entry is a request the native extractor is already making, and a
    // ciphered answer from them cannot be used here anyway.
    final allowedChain = guestClientsEnabled
        ? rawChain
        : rawChain.where((c) => c == 'WEB_REMIX').toList();

    final clientChain = [
      ...allowedChain.where((c) => !_isSabrDemoted(c)),
      ...allowedChain.where(_isSabrDemoted),
    ];

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
            // An age gate is a property of the track, not of the egress: a
            // guest client's LOGIN_REQUIRED / "Sign in to confirm your age" is
            // the expected answer for +18 content and says nothing about the
            // IP or the session. Counting it as a block short-circuited the
            // chain after two guests — before the authenticated WEB_REMIX
            // (third in the guest order) could ever be tried.
            final isAgeGate = status == 'LOGIN_REQUIRED' &&
                _ageGateSubstrings
                    .any((sub) => statusReason.toLowerCase().contains(sub));
            final isBotBlock = !isAgeGate &&
                (status.contains('BOT') ||
                    _botSubstrings.any((sub) => statusReason
                        .toLowerCase()
                        .contains(sub.toLowerCase())));
            final isBlockSignal = isBotBlock ||
                (!acceptsSessionAuth &&
                    status == 'LOGIN_REQUIRED' &&
                    !isAgeGate);
            if (isBlockSignal) {
              consecutiveBlockSignals++;
              if (consecutiveBlockSignals >= 2) {
                debugPrint(
                    '[YTM_ACCOUNT] Short-circuiting Dart chain: $consecutiveBlockSignals consecutive bot blocks for $videoId');
                throw YtmException(
                  'BOT_CHALLENGE',
                  'Short-circuited Dart chain after $consecutiveBlockSignals consecutive bot blocks for $videoId',
                );
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
          var hasCipheredAudio = false;
          for (final f in adaptive) {
            final mime = f['mimeType'] as String? ?? '';
            final streamUrl = _extractUrlFromFormat(f);
            final isCipher =
                f.containsKey('signatureCipher') || f.containsKey('cipher');
            if (mime.startsWith('audio/')) {
              if (isCipher) hasCipheredAudio = true;
              if (streamUrl != null && streamUrl.isNotEmpty) {
                audioFormats.add((format: f, url: streamUrl));
              }
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
            final audioConfig =
                data['playerConfig']?['audioConfig'] as Map<String, dynamic>?;
            final loudnessDb =
                (audioConfig?['loudnessDb'] as num?)?.toDouble() ??
                    (audioConfig?['perVideoLoudnessDb'] as num?)?.toDouble();

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
              loudnessDb: loudnessDb,
              // The player response never states an expiry of its own, but the
              // URL it hands back always carries one. Left null, `isExpired` and
              // `isExpiringSoon` answer false for the whole ~6-hour life of the
              // URL and then keep answering false after it dies, so nothing
              // re-resolves and the URL cache stores it with the wrong lifetime.
            ).withResolvedExpiry();
          } else {
            debugPrint(
                '[YTM_ACCOUNT] Client $client returned status $status but no direct audio formats (adaptiveFormats: ${adaptive.length} total, ciphered: $hasCipheredAudio)');
            if (hasCipheredAudio) {
              if (acceptsSessionAuth && !guestClientsEnabled) {
                debugPrint(
                    '[YTM_ACCOUNT] WEB_REMIX formats require native decipher; handing off to native tier');
                return null;
              }
            } else if (adaptive.isNotEmpty) {
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
            throw YtmException(
              'BOT_CHALLENGE',
              'Short-circuited Dart chain after $consecutiveBlockSignals consecutive block/rate-limit signals for $videoId',
            );
          }
        }
      } catch (e) {
        // Session-expiry and short-circuit bot challenges must surface to callers,
        // not be swallowed as a per-client resolution failure.
        if (e is YtmException &&
            (e.isAuth || e.isBotBlocked || e.isIpBlocked || e.isThrottled)) {
          rethrow;
        }
        debugPrint(
            '[YTM_ACCOUNT] Client $client resolution error for $videoId: $e');
      }
    }
    return null;
  }


  /// Searches for a map containing [key] in the InnerTube JSON tree.
  Map<String, dynamic>? _findShelfNode(dynamic node, String key,
      [int depth = 0]) {
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
            final token =
                contEndpoint['continuationCommand']?['token'] as String?;
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
    final mainApp =
        rc is Map<String, dynamic> ? rc['mainAppWebResponseContext'] : null;
    final id =
        (mainApp is Map<String, dynamic> ? mainApp['datasyncId'] : null) ??
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
      _ytmService?.setDataSyncId(dsid);
    }
    final rc = json['responseContext'];
    if (rc is Map<String, dynamic>) {
      final vd = rc['visitorData'];
      if (vd is String && vd.isNotEmpty) {
        _sessionVisitorData = vd;
      }
    }
    final accountHeader = _findShelfNode(json, 'activeAccountHeaderRenderer');
    if (accountHeader != null) {
      String? harvestedName;
      final nameNode = accountHeader['accountName'];
      if (nameNode is String && nameNode.trim().isNotEmpty) {
        harvestedName = nameNode.trim();
      } else if (nameNode is Map<String, dynamic>) {
        final runs = nameNode['runs'];
        if (runs is List && runs.isNotEmpty) {
          final joined =
              runs.map((r) => r['text']?.toString() ?? '').join().trim();
          if (joined.isNotEmpty) harvestedName = joined;
        } else if (nameNode['simpleText'] is String) {
          final text = (nameNode['simpleText'] as String).trim();
          if (text.isNotEmpty) harvestedName = text;
        }
      }
      if (harvestedName != null && harvestedName != _accountName) {
        _accountName = harvestedName;
        unawaited(SharedPreferences.getInstance().then((p) {
          p.setString(_accountNamePrefKey, harvestedName!);
        }).catchError((e) {
          debugPrint('[YTM_ACCOUNT] Failed to persist accountName: $e');
        }));
      }

      final thumbs = accountHeader['accountPhoto']?['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        final avatarUrl = last is Map ? last['url'] as String? : null;
        if (avatarUrl != null &&
            avatarUrl.isNotEmpty &&
            avatarUrl != _accountAvatar) {
          _accountAvatar = avatarUrl;
          unawaited(SharedPreferences.getInstance().then((p) {
            p.setString(_accountAvatarPrefKey, avatarUrl);
          }).catchError((e) {
            debugPrint('[YTM_ACCOUNT] Failed to persist accountAvatar: $e');
          }));
        }
      }
    }
  }

  /// Public, throttled trigger for [_bootstrapDataSyncId].
  Future<void> ensureDataSyncId() async {
    if (!isLoggedIn || isOAuthSession) return;
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

  String _accountMenuDiagnostic = '';

  @disposeMethod
  void dispose() {
    _disposed = true;
    _sessionHarvestDebounce?.cancel();
    loginState.dispose();
    try {
      _innertubeClient?.close();
      _innertubeClient = null;
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }
}
