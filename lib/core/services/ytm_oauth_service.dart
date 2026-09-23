// lib/core/services/ytm_oauth_service.dart
//
// Google OAuth 2.0 Device Authorization Grant (RFC 8628) for the YouTube TV
// (TVHTML5) client.
//
// This exists because Google blocks sign-in inside embedded WebViews by
// policy — the "This browser or app may not be secure" interstitial / captcha
// is not something a UA spoof can reliably beat. The device flow moves the
// credential entry to the user's real browser (google.com/device), which is a
// flow Google explicitly supports for TV / limited-input devices, while the
// app only ever sees a short-lived device code and a token.
//
// The client id / secret below are the public YouTube TV client credentials
// (the same pair `ytmusicapi` and `yt-dlp --username oauth` ship). They are
// not confidential — every install includes them — and can be overridden at
// build time:
//   --dart-define=YTM_OAUTH_CLIENT_ID=...
//   --dart-define=YTM_OAUTH_CLIENT_SECRET=...
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// A pending device-authorization request. The user enters [userCode] at
/// [verificationUrl] on another device while the app polls for the token.
class OAuthDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int intervalSeconds;
  final int expiresInSeconds;
  final DateTime requestedAt;

  const OAuthDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSeconds,
    required this.expiresInSeconds,
    required this.requestedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(requestedAt).inSeconds >= expiresInSeconds;
}

/// Raised when the device-code poll ends with a terminal server verdict.
class OAuthException implements Exception {
  final String code;
  final String? description;
  const OAuthException(this.code, [this.description]);

  @override
  String toString() =>
      'OAuthException($code${description == null ? '' : ': $description'})';
}

/// Terminal outcomes that should stop the poll loop (everything else is a
/// transient `authorization_pending` / `slow_down`).
bool _isTerminalOAuthError(String error) =>
    error == 'access_denied' ||
    error == 'expired_token' ||
    error == 'invalid_grant' ||
    error == 'invalid_client' ||
    error == 'invalid_request' ||
    error == 'unsupported_grant_type';

class YtmOAuthService {
  YtmOAuthService._();
  static final YtmOAuthService shared = YtmOAuthService._();

  static const String _clientId = String.fromEnvironment(
    'YTM_OAUTH_CLIENT_ID',
    defaultValue:
        '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com',
  );
  static const String _clientSecret = String.fromEnvironment(
    'YTM_OAUTH_CLIENT_SECRET',
    defaultValue: 'SboVhoG9s0rNafixCSGGKXAT',
  );
  static const String _scope =
      'https://www.googleapis.com/auth/youtube http://gdata.youtube.com';

  static final Uri _deviceCodeEndpoint =
      Uri.parse('https://oauth2.googleapis.com/device/code');
  static final Uri _tokenEndpoint =
      Uri.parse('https://oauth2.googleapis.com/token');

  static const String _keyAccess = 'ytm_oauth_access_token';
  static const String _keyRefresh = 'ytm_oauth_refresh_token';
  static const String _keyExpiry = 'ytm_oauth_expiry_epoch';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final http.Client _client = http.Client();

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _initialized = false;
  Future<void>? _initFuture;
  Future<bool>? _refreshInFlight;

  /// Bumped on every sign-out. Any async token mutation that started before the
  /// bump refuses to write, so an in-flight refresh can never resurrect a
  /// session the user just logged out of.
  int _authGeneration = 0;

  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;

  /// Current bearer token, or null. May be soft-expired; call [ensureFresh]
  /// before a request to guarantee validity.
  String? get accessToken => _accessToken;

  Future<void> init() {
    if (_initialized) return Future.value();
    // Memoize the in-flight load so concurrent callers share it, but allow a
    // retry if secure storage throws transiently (do not latch failure).
    return _initFuture ??= _loadTokens();
  }

  Future<void> _loadTokens() async {
    try {
      final access = await _storage.read(key: _keyAccess);
      final refresh = await _storage.read(key: _keyRefresh);
      final expiryRaw = await _storage.read(key: _keyExpiry);
      _accessToken = access;
      _refreshToken = refresh;
      final epoch = int.tryParse(expiryRaw ?? '');
      if (epoch != null && epoch > 0) {
        _expiresAt = DateTime.fromMillisecondsSinceEpoch(epoch);
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[YtmOAuth] Failed to load tokens: $e');
      _initFuture = null;
    }
  }

  /// Refreshes the access token when it is missing or within 2 minutes of
  /// expiry. Returns true when a usable token is present afterwards.
  Future<bool> ensureFresh() async {
    await init();
    if (_accessToken == null || _accessToken!.isEmpty) return false;
    final exp = _expiresAt;
    // Unknown expiry: assume valid and let the server reject if not.
    if (exp == null) return true;
    if (exp.difference(DateTime.now()) > const Duration(minutes: 2)) return true;
    // The token is (nearly) expired and cannot be refreshed: treat as signed
    // out instead of reporting a usable session that will 401 on every call.
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      await _clearTokens();
      return false;
    }
    return refresh();
  }

  /// Requests a device + user code. [scope] defaults to the YouTube scope.
  Future<OAuthDeviceCode> requestDeviceCode() async {
    final res = await _client
        .post(
          _deviceCodeEndpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'client_id': _clientId, 'scope': _scope}),
        )
        .timeout(const Duration(seconds: 15));
    final json = _decode(res.body);
    if (res.statusCode != 200 || json == null) {
      throw OAuthException(
        (json?['error'] as String?) ?? 'http_${res.statusCode}',
        json?['error_description'] as String?,
      );
    }
    final deviceCode = json['device_code'] as String?;
    final userCode = json['user_code'] as String?;
    final verificationUrl = (json['verification_url'] ??
            json['verification_uri']) as String?;
    if (deviceCode == null ||
        userCode == null ||
        verificationUrl == null ||
        deviceCode.isEmpty ||
        userCode.isEmpty ||
        verificationUrl.isEmpty) {
      throw const OAuthException(
          'invalid_response', 'Authorization server omitted codes');
    }
    return OAuthDeviceCode(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: verificationUrl,
      intervalSeconds: (json['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (json['expires_in'] as num?)?.toInt() ?? 1800,
      requestedAt: DateTime.now(),
    );
  }

  /// Polls the token endpoint until the user approves, denies, or the code
  /// expires. [onTick] is invoked after each poll for UI progress. Honours the
  /// RFC 8628 `slow_down` back-off.
  Future<bool> pollForToken(
    OAuthDeviceCode code, {
    void Function()? onTick,
    bool Function()? isCancelled,
  }) async {
    var interval = code.intervalSeconds.clamp(1, 60);
    var pollCount = 0;
    const maxPolls = 60;
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (!code.isExpired &&
        pollCount < maxPolls &&
        DateTime.now().isBefore(deadline)) {
      pollCount++;
      if (isCancelled?.call() ?? false) return false;
      await Future.delayed(Duration(seconds: interval));
      if (isCancelled?.call() ?? false) return false;
      onTick?.call();

      final http.Response res;
      try {
        res = await _client
            .post(
              _tokenEndpoint,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'client_id': _clientId,
                'client_secret': _clientSecret,
                'device_code': code.deviceCode,
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              }),
            )
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // A transient blip during a long device grant must not abort the whole
        // flow: keep polling until the code expires or the user cancels.
        debugPrint('[YtmOAuth] device poll transport error: $e');
        if (isCancelled?.call() ?? false) return false;
        continue;
      }
      final json = _decode(res.body);
      if (json == null) continue;

      final access = json['access_token'] as String?;
      final error = json['error'] as String?;

      if (access != null && access.isNotEmpty) {
        await _persistTokens(
          accessToken: access,
          refreshToken: json['refresh_token'] as String?,
          expiresInSeconds: (json['expires_in'] as num?)?.toInt(),
        );
        return true;
      }
      if (error == null) continue;
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval += 5;
        continue;
      }
      if (_isTerminalOAuthError(error)) {
        throw OAuthException(error, json['error_description'] as String?);
      }
      // Unknown / transient: keep polling until expiry.
    }
    return false;
  }

  /// Exchanges the refresh token for a new access token. Concurrent callers
  /// share a single in-flight request so overlapping refreshes cannot race the
  /// rotating refresh token.
  Future<bool> refresh() {
    return _refreshInFlight ??= _refreshOnce().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _refreshOnce() async {
    final generation = _authGeneration;
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await _client
          .post(
            _tokenEndpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'client_id': _clientId,
              'client_secret': _clientSecret,
              'refresh_token': refreshToken,
              'grant_type': 'refresh_token',
            }),
          )
          .timeout(const Duration(seconds: 15));
      final json = _decode(res.body);
      final access = json?['access_token'] as String?;
      if (access != null && access.isNotEmpty) {
        await _persistTokens(
          accessToken: access,
          refreshToken: json?['refresh_token'] as String?,
          expiresInSeconds: (json?['expires_in'] as num?)?.toInt(),
        );
        return true;
      }
      // A revoked/consumed refresh token is terminal: clear the dead session so
      // the UI stops claiming the account is connected.
      final error = json?['error'] as String?;
      if (error == 'invalid_grant' || error == 'invalid_client') {
        if (generation == _authGeneration) await _clearTokens();
      }
      return false;
    } catch (e) {
      debugPrint('[YtmOAuth] refresh failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    // Invalidate any in-flight persist/refresh before clearing memory/storage.
    _authGeneration++;
    final tokenToRevoke = _refreshToken ?? _accessToken;
    if (tokenToRevoke != null && tokenToRevoke.isNotEmpty) {
      try {
        await _client
            .post(
              Uri.parse('https://oauth2.googleapis.com/revoke'),
              headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
              body: 'token=${Uri.encodeQueryComponent(tokenToRevoke)}',
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[YtmOAuth] token revocation blip (ignored): $e');
      }
    }
    await _clearTokens();
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    try {
      await _storage.delete(key: _keyAccess);
      await _storage.delete(key: _keyRefresh);
      await _storage.delete(key: _keyExpiry);
    } catch (_) {}
  }

  Future<void> _persistTokens({
    required String accessToken,
    String? refreshToken,
    int? expiresInSeconds,
  }) async {
    final generation = _authGeneration;
    // A sign-out raced this refresh: drop the result instead of writing it.
    if (generation != _authGeneration) return;
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    final ttl = expiresInSeconds ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
    try {
      await _storage.write(key: _keyAccess, value: accessToken);
      if (generation != _authGeneration) return;
      if (_refreshToken != null) {
        await _storage.write(key: _keyRefresh, value: _refreshToken!);
      }
      if (generation != _authGeneration) return;
      await _storage.write(
        key: _keyExpiry,
        value: _expiresAt!.millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      debugPrint('[YtmOAuth] Failed to persist tokens: $e');
    }
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
