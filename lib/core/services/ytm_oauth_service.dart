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

  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;

  /// Current bearer token, or null. May be soft-expired; call [ensureFresh]
  /// before a request to guarantee validity.
  String? get accessToken => _accessToken;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _accessToken = await _storage.read(key: _keyAccess);
      _refreshToken = await _storage.read(key: _keyRefresh);
      final expiryRaw = await _storage.read(key: _keyExpiry);
      final epoch = int.tryParse(expiryRaw ?? '');
      if (epoch != null && epoch > 0) {
        _expiresAt = DateTime.fromMillisecondsSinceEpoch(epoch);
      }
    } catch (e) {
      debugPrint('[YtmOAuth] Failed to load tokens: $e');
    }
  }

  /// Refreshes the access token when it is missing or within 2 minutes of
  /// expiry. Returns true when a usable token is present afterwards.
  Future<bool> ensureFresh() async {
    await init();
    if (_accessToken == null || _accessToken!.isEmpty) return false;
    final exp = _expiresAt;
    if (exp == null) return true;
    if (exp.difference(DateTime.now()) > const Duration(minutes: 2)) return true;
    if (_refreshToken == null || _refreshToken!.isEmpty) return true;
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
    while (!code.isExpired) {
      if (isCancelled?.call() ?? false) return false;
      await Future.delayed(Duration(seconds: interval));
      if (isCancelled?.call() ?? false) return false;
      onTick?.call();

      final res = await _client
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

  /// Exchanges the refresh token for a new access token.
  Future<bool> refresh() async {
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
      if (access == null || access.isEmpty) return false;
      await _persistTokens(
        accessToken: access,
        refreshToken: json?['refresh_token'] as String?,
        expiresInSeconds: (json?['expires_in'] as num?)?.toInt(),
      );
      return true;
    } catch (e) {
      debugPrint('[YtmOAuth] refresh failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
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
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    final ttl = expiresInSeconds ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
    try {
      await _storage.write(key: _keyAccess, value: accessToken);
      if (_refreshToken != null) {
        await _storage.write(key: _keyRefresh, value: _refreshToken!);
      }
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
