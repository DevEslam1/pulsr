// lib/core/services/ytm_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../constants/channels.dart';
import '../constants/embedded_browser_ua.dart';
import '../di/injection.dart';
import 'ytm_account_service.dart';
import 'ytm_client_version_resolver.dart';
import 'ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';
import '../telemetry/playback_latency_tracker.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';

import '../errors/ytm_error_classifier.dart';
import 'ytm_circuit_breaker.dart';

/// A failed YTM call with structured block signal and trace ID.
class YtmException implements Exception {
  final String code;
  final String? details;
  final String? traceId;

  const YtmException(this.code, [this.details, this.traceId]);

  /// A bare `bot` substring also matches "bottleneck", "sabotage" and "robots".
  static final RegExp _botWord = RegExp(r'\bbots?\b', caseSensitive: false);

  YtmBlockSignal? get signal {
    // Prefer the explicit machine code (e.g. native BOT_CHALLENGE with a
    // human message like "All clients LOGIN_REQUIRED"): classifying the free
    // text first would misread it as signInRequired and route auth-recovery
    // instead of bot-recovery.
    final explicit = YtmBlockSignal.fromCode(code);
    if (explicit != null) return explicit;
    return YtmErrorClassifier.classifyCode(code, details, traceId).signal;
  }

  /// The device could not reach YouTube at all. Retrying later may work;
  /// retrying the rest of the queue now will not.
  ///
  /// Deliberately excludes [YtmBlockSignal.ipBlocked]: a 403 is a *response*,
  /// so the route works and only the identity is refused. Folding the two
  /// together made every offline blip take the 180s IP-block cooldown.
  bool get isNetwork =>
      signal == YtmBlockSignal.networkUnavailable ||
      code == 'YTM_NETWORK' ||
      code == 'YTM_TIMEOUT' ||
      code == 'YTM_OFFLINE';

  /// YouTube has flagged the IP / client as automated and wants attestation.
  ///
  /// Throttling ([isThrottled]) is not included: callers respond to a bot block
  /// by minting a fresh poToken and retrying at once, which is the worst
  /// possible reaction to a 429. A bare `LOGIN_REQUIRED` is not included
  /// either — that is the normal playabilityStatus of a private or
  /// members-only track, and treating it as a bot block imposed a 90s global
  /// cooldown every time one appeared in a queue.
  bool get isBotBlocked =>
      signal == YtmBlockSignal.botChallenge ||
      signal == YtmBlockSignal.poTokenInvalid ||
      code == 'BOT_CHALLENGE' ||
      code == 'PO_TOKEN_INVALID' ||
      code == 'YTM_PO_TOKEN_INVALID' ||
      code == 'YTM_BOT_BLOCKED' ||
      code == 'YTM_RECAPTCHA' ||
      code == 'RECAPTCHA_REQUIRED' ||
      (details != null &&
          (_botWord.hasMatch(details!) ||
              details!.contains('Sign in to confirm')));

  /// YouTube is rate-limiting this IP. Waiting helps; rotating identity does not.
  bool get isThrottled =>
      signal == YtmBlockSignal.rateLimited ||
      code == 'RATE_LIMITED' ||
      code == 'YTM_429';

  /// YouTube answered, but refused this IP / route.
  bool get isIpBlocked =>
      signal == YtmBlockSignal.ipBlocked || code == 'IP_BLOCKED';

  /// Session has expired or authentication is invalid.
  bool get isAuth =>
      signal == YtmBlockSignal.signInRequired ||
      code == 'SIGN_IN_REQUIRED' ||
      code == 'YTM_AUTH' ||
      code == 'LOGIN_REQUIRED' ||
      (details != null && details!.toLowerCase().contains('unauthenticated'));

  /// Fatal error where looping / skipping the queue will only worsen the block.
  bool get isFatal =>
      isNetwork || isDisabled || isBotBlocked || isThrottled || isAuth;

  /// This one video cannot be played, but others still can.
  bool get isUnavailable =>
      signal == YtmBlockSignal.videoGone ||
      signal == YtmBlockSignal.geoBlocked ||
      code == 'VIDEO_GONE' ||
      code == 'GEO_BLOCKED' ||
      code == 'YTM_UNAVAILABLE';

  /// The build has no extractor compiled in.
  bool get isDisabled => code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED';

  @override
  String toString() =>
      'YtmException($code${traceId != null ? ' [trace=$traceId]' : ''}${details == null ? '' : ': $details'})';
}

@singleton
class YtmService {
  static const String channelName = PulsrChannels.ytm;
  static const Duration _defaultSearchTimeout = Duration(seconds: 25);
  static const Duration _defaultResolveTimeout = Duration(seconds: 15);

  final MethodChannel _channel = const MethodChannel(channelName);
  final StreamController<void> _authExpiredController =
      StreamController<void>.broadcast();

  /// Shared persistent HTTP client for Dart-side Innertube calls (search
  /// fallback). Keep-alive reuses TCP+TLS across requests; the previous
  /// top-level `http.post` paid a fresh handshake per call (~100-400ms).
  /// (Field, not a ctor param, so injectable codegen stays untouched.)
  final http.Client _httpClient = http.Client();

  bool? _available;

  /// Bot-challenge cooldown: when YouTube flags this IP, every native resolve
  /// burns a full multi-client chain and fails identically. While cooling
  /// down, [resolveStream] skips the native tiers and goes straight to the
  /// remote backend instead of piling up doomed chains (which also starves
  /// the native thread pool into cascading YTM_TIMEOUTs).
  static const _botCooldown = Duration(seconds: 45);
  /// Extended cooldown for IP-level blocks (every client fails instantly).
  static const _ipBlockCooldown = Duration(seconds: 180);
  DateTime _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  YtmException? _lastBotChallenge;

  /// Pushes bot-cooldown transitions to the UI without a polling timer: the
  /// value flips to true when a cooldown starts and back to false exactly when
  /// the window elapses (or a resolve proves the IP is unblocked). The search
  /// screen listens to this instead of a 5-second [Timer.periodic] + setState.
  final ValueNotifier<bool> botCooldownNotifier = ValueNotifier<bool>(false);
  Timer? _botCooldownTimer;

  void _syncBotCooldownNotifier() {
    _botCooldownTimer?.cancel();
    _botCooldownTimer = null;
    final remaining = _botChallengeUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      if (botCooldownNotifier.value) botCooldownNotifier.value = false;
      return;
    }
    if (!botCooldownNotifier.value) botCooldownNotifier.value = true;
    _botCooldownTimer = Timer(remaining, () {
      if (DateTime.now().isBefore(_botChallengeUntil)) {
        _syncBotCooldownNotifier();
      } else if (botCooldownNotifier.value) {
        botCooldownNotifier.value = false;
      }
    });
  }

  // FIX-C01: Per-video failure tracking (trip only if 3 failures for that videoId within 60s)
  final Map<String, List<DateTime>> _videoFailures = {};
  final Map<String, DateTime> _videoCooldownUntil = {};

  /// Per-signal breaker + metrics. Existing bot/video cooldowns stay as the
  /// fast path; the breaker adds bounded per-signal windows and observability.
  final YtmCircuitBreaker breaker = YtmCircuitBreaker();

  /// Diagnostics snapshot for logs/settings UI.
  Map<String, dynamic> breakerMetrics() => breaker.metrics();

  bool isVideoCoolingDown(String videoId) {
    final until = _videoCooldownUntil[videoId];
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _videoCooldownUntil.remove(videoId);
    return false;
  }

  static const _videoFailureCooldown = Duration(seconds: 30);

  // FIX-C01: Record a failure for a specific videoId
  void recordFailure(String videoId, [YtmException? error]) {
    final err = error ?? const YtmException('VIDEO_FAILED');
    if (err.isBotBlocked || err.isIpBlocked || err.isThrottled) {
      _noteBotChallenge(err, videoId: videoId);
    } else {
      // Non-bot failures track per-video without tripping a global bot challenge
      final now = DateTime.now();
      final failures = _videoFailures.putIfAbsent(videoId, () => []);
      failures.removeWhere((t) => now.difference(t).inSeconds > 60);
      failures.add(now);
      if (failures.length >= 3) {
        _videoCooldownUntil[videoId] = now.add(_videoFailureCooldown);
      }
    }
  }

  bool get isBotCoolingDown => DateTime.now().isBefore(_botChallengeUntil);

  void _noteBotChallenge(YtmException e, {String? videoId}) {
    if (e.isBotBlocked || e.isIpBlocked || e.isThrottled) {
      _lastBotChallenge = e;
    }
    final signal = e.signal;
    if (signal != null) breaker.recordFailure(signal);
    final now = DateTime.now();

    // FIX-C01: Key circuit breaker per videoId (3 failures within 60s)
    if (videoId != null && videoId.isNotEmpty) {
      final failures = _videoFailures.putIfAbsent(videoId, () => []);
      failures.removeWhere((t) => now.difference(t).inSeconds > 60);
      failures.add(now);

      if (e.isIpBlocked || e.isBotBlocked || e.isThrottled) {
        final cooldown = e.isIpBlocked ? _ipBlockCooldown : _botCooldown;
        _videoCooldownUntil[videoId] = now.add(cooldown);
        _botChallengeUntil = now.add(cooldown);
      } else if (failures.length >= 3) {
        _videoCooldownUntil[videoId] = now.add(_videoFailureCooldown);
      }
    } else if (e.isIpBlocked || e.isBotBlocked || e.isThrottled) {
      final cooldown = e.isIpBlocked ? _ipBlockCooldown : _botCooldown;
      _botChallengeUntil = now.add(cooldown);
    }
    _syncBotCooldownNotifier();
  }

  /// Any successful resolve proves the IP is not blocked, so an active cooldown
  /// must end: a fixed window kept skipping the native tiers (the only ones
  /// that produce high-bitrate streams) for minutes after YouTube let us back
  /// in, and every retry inside the window rethrew the stale challenge.
  void _noteResolveSuccess({String? videoId}) {
    breaker.recordSuccess();
    if (videoId != null) {
      _videoFailures.remove(videoId);
      _videoCooldownUntil.remove(videoId);
    }
    if (_lastBotChallenge == null &&
        _botChallengeUntil.millisecondsSinceEpoch == 0) {
      return;
    }
    _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBotChallenge = null;
    _syncBotCooldownNotifier();
  }

  /// Test-only: clears bot-cooldown state.
  void debugClearBotCooldown([String? videoId]) {
    if (videoId != null) {
      _videoFailures.remove(videoId);
      _videoCooldownUntil.remove(videoId);
    } else {
      _videoFailures.clear();
      _videoCooldownUntil.clear();
    }
    _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBotChallenge = null;
    _syncBotCooldownNotifier();
  }

  Stream<void> get onAuthExpired => _authExpiredController.stream;

  void notifyAuthExpired() {
    _authExpiredController.add(null);
  }

  @disposeMethod
  void dispose() {
    _authExpiredController.close();
    try {
      _httpClient.close();
    } catch (_) {}
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

  /// Synchronizes cookies into the native extractor's encrypted session store.
  /// The login WebView owns its CookieManager jar; importing a raw header must
  /// not blindly replay domain-less credentials into browser origins.
  Future<void> syncCookies(String cookies) async {
    try {
      await _channel.invokeMethod<bool>('setCookies', {'cookies': cookies});
    } catch (_) {}
  }

  /// Tears down the native session on an explicit disconnect.
  ///
  /// Stronger than `syncCookies('')`, which only empties the in-process store
  /// and its prefs: this also expires the tracked names in the WebView
  /// CookieManager and drops the account-bound poToken plus the dataSyncId. Both
  /// matter for a durable logout — the native store re-reads the WebView jar
  /// whenever its prefs are empty, so a half-cleared disconnect came back on the
  /// next cold start.
  Future<void> clearNativeSession() async {
    try {
      await _channel
          .invokeMethod<bool>('clearCookies')
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Calls native PoTokenManager to ensure attestation tokens are ready.
  Future<bool> ensurePoTokenReady() async {
    try {
      final ready = await _channel
          .invokeMethod<bool>('ensurePoTokenReady')
          .timeout(const Duration(seconds: 2));
      return ready ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Invalidates BotGuard poToken state on bot-detection block or session logout.
  Future<void> invalidatePoToken() async {
    try {
      await _channel
          .invokeMethod<bool>('invalidatePoToken')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// Retrieves state of PoTokenManager.
  Future<Map<String, dynamic>?> getPoTokenState() async {
    try {
      final state = await _channel
          .invokeMethod<Map<Object?, Object?>>('getPoTokenState')
          .timeout(const Duration(seconds: 2));
      if (state == null) return null;
      return state.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Mints a content-bound (videoId) poToken for a `/player` request.
  ///
  /// Distinct from the visitor-bound `streamingPoToken`, which belongs on media
  /// URLs and — for a guest web player request — makes YouTube answer UNPLAYABLE
  /// "Video unavailable". Used by the Dart account chain's guest pass.
  Future<String?> getPlayerPoToken(String videoId) async {
    try {
      final token = await _channel
          .invokeMethod<String>('getPlayerPoToken', {'videoId': videoId})
          .timeout(const Duration(seconds: 4));
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Mints an account-bound poToken for authenticated WEB_REMIX playback. [dataSyncId] is the raw
  /// account binding harvested from an authenticated Innertube response. Returns
  /// `{poToken, visitorData}` or null on failure.
  Future<Map<String, dynamic>?> getAccountPoToken(String dataSyncId) async {
    try {
      final state = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAccountPoToken',
        {'dataSyncId': dataSyncId},
      ).timeout(const Duration(seconds: 2));
      if (state == null) return null;
      return state.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Seeds the native PoTokenManager with the current account [dataSyncId] so account-bound tokens
  /// mint against the correct account (e.g. restored from prefs at startup).
  Future<void> setDataSyncId(String dataSyncId) async {
    try {
      await _channel
          .invokeMethod<bool>('setDataSyncId', {'dataSyncId': dataSyncId});
    } catch (_) {}
  }

  /// Pre-warms BotGuard WebView and Capability Matrix.
  Future<void> preWarm() async {
    try {
      await _channel.invokeMethod<bool>('preWarm');
    } catch (_) {}
  }

  /// Checks if active connection is via VPN.
  Future<bool> isVpnConnected() async {
    try {
      final vpn = await _channel.invokeMethod<bool>('isVpnConnected');
      return vpn ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Resets identities and visitor data.
  Future<void> resetIdentities() async {
    try {
      await _channel.invokeMethod<bool>('resetIdentities');
    } catch (_) {}
  }

  /// Returns true if native stack is running in limited mode (no poToken).
  Future<bool> getLimitedMode() async {
    try {
      final limited = await _channel.invokeMethod<bool>('getLimitedMode');
      return limited ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Drops every piece of state that is pinned to the previous egress IP.
  ///
  /// Call when the network path changes (VPN up/down, Wi-Fi <-> mobile):
  /// googlevideo URLs carry an IP-bound signature, so any cached URL resolved
  /// before the switch gets a 403 on the new path. The bot/IP cooldown is
  /// also cleared — a block verdict from the old IP must not silence the
  /// native tiers on the new one — and the native DNS TTL cache is dropped so
  /// the next resolve re-resolves the edge for the new route.
  Future<void> handleNetworkChange() async {
    debugClearBotCooldown();
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        getIt<YtmUrlCache>().clear();
      }
    } catch (_) {}
    try {
      await _channel
          .invokeMethod<bool>('clearNetworkCaches')
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
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
    } on YtmException catch (e) {
      // Only a real answer is permanent. A 5s timeout or a transport blip used
      // to be cached as "no extractor in this build", which disabled the whole
      // YouTube Music surface for the rest of the process — while the plugin
      // was there all along and just busy warming up.
      if (e.isDisabled) return _available = false;
      return false;
    }
  }

  Future<bool> isWifiConnected() async {
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isWifiConnected'),
        timeout: const Duration(seconds: 3),
      );
      // Fail closed: this gates Wi-Fi-only mode, a data-cost decision. If we
      // can't confirm Wi-Fi, assuming "connected" would silently permit metered
      // streaming against the user's explicit setting. Treat unknown as not-Wi-Fi.
      return value ?? false;
    } on YtmException {
      return false;
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

  Future<List<YtmTrack>> searchContinuation(String token,
      {int limit = 30}) async {
    if (token.trim().isEmpty) return const [];
    try {
      final raw = await _guard(
        () => _channel.invokeMethod<List<Object?>>('searchContinuation', {
          'continuation': token.trim(),
          'limit': limit,
        }),
        timeout: _defaultSearchTimeout,
      );
      return _parseTracks(raw);
    } catch (e) {
      debugPrint('[YTM_SERVICE] searchContinuation failed: $e');
      return const [];
    }
  }

  /// Search with fallback: First tries native extractor, then falls back to
  /// Innertube search if the extractor returns empty or throws.
  Future<List<YtmTrack>> searchWithFallback(String query,
      {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Try native extractor search
    try {
      final results = await search(trimmed, limit: limit);
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native search failed, trying fallbacks: $e');
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

  Future<List<YtmTrack>> _searchInnertube(String query,
      {int limit = 30}) async {
    try {
      String apiKey = YtmClientVersionResolver.fallbackApiKey;
      String clientVersion = YtmClientVersionResolver.fallbackClientVersion;
      if (getIt.isRegistered<YtmClientVersionResolver>()) {
        final resolver = getIt<YtmClientVersionResolver>();
        apiKey = resolver.apiKey;
        clientVersion = resolver.clientVersion;
      }

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': clientVersion,
            'hl': 'en',
            'gl': 'EG',
          },
        },
        'query': query,
      });

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': EmbeddedBrowserUa.desktop,
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
            final authHeader =
                YtmAccountService.buildAuthorizationHeader(cookies);
            if (authHeader != null) {
              headers['Authorization'] = authHeader;
            }
          }
        }
      }

      await YtmRateLimiter.shared.acquirePermit();
      final response = await _httpClient
          .post(
            Uri.parse(
                'https://music.youtube.com/youtubei/v1/search?prettyPrint=false&key=$apiKey'),
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
              final r = node['musicResponsiveListItemRenderer']
                  as Map<String, dynamic>;
              final flexCols = r['flexColumns'] as List<dynamic>? ?? [];
              String? videoId;
              String title = 'Unknown Title';
              String artist = 'Unknown Artist';

              final pData = r['playlistItemData'] as Map<String, dynamic>?;
              videoId = pData?['videoId'] as String?;

              if (flexCols.isNotEmpty) {
                final c0 = flexCols[0]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
                if (c0 != null && c0.isNotEmpty) {
                  title = c0[0]['text'] as String? ?? title;
                  final nav =
                      c0[0]['navigationEndpoint'] as Map<String, dynamic>?;
                  videoId ??= nav?['watchEndpoint']?['videoId'] as String?;
                }
              }
              if (flexCols.length > 1) {
                final c1 = flexCols[1]
                        ['musicResponsiveListItemFlexColumnRenderer']?['text']
                    ?['runs'] as List<dynamic>?;
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
        YtmRateLimiter.shared.onSuccess();
        return tracks.take(limit).toList();
      }

      // Non-200 from Innertube search: feed the shared limiter so the block
      // signal survives (previously swallowed, indistinguishable from "empty").
      if (response.statusCode == 429) {
        YtmRateLimiter.shared.onRateLimited(
          int.tryParse(response.headers['retry-after'] ?? ''),
        );
      }
      debugPrint(
          '[YTM_SERVICE] Innertube search HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('[YTM_SERVICE] Innertube search error: $e');
    }
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

  Future<List<YtmTrack>> getCharts({int limit = 30}) async {
    try {
      final raw = await _guard(
        () => _channel.invokeMethod<List<Object?>>('getCharts', {
          'limit': limit,
          ..._localeArgs(),
        }),
        timeout: _defaultSearchTimeout,
      );
      if (raw != null && raw.isNotEmpty) return _parseTracks(raw);
    } catch (_) {}
    return trending(limit: limit);
  }

  Future<List<YtmTrack>> getMoods({int limit = 30}) async {
    try {
      final raw = await _guard(
        () => _channel.invokeMethod<List<Object?>>('getMoods', {
          'limit': limit,
          ..._localeArgs(),
        }),
        timeout: _defaultSearchTimeout,
      );
      if (raw != null && raw.isNotEmpty) return _parseTracks(raw);
    } catch (_) {}
    return const [];
  }

  Future<List<YtmTrack>> getPlaylistTracks(String urlOrId,
      {int limit = 100}) async {
    final cleanInput = urlOrId.trim();
    if (cleanInput.isEmpty) return const [];

    // 1. Direct Dart InnerTube API via YtmAccountService
    // Primary engine: authenticated cookies, private playlists, mixes, pagination, works on all platforms.
    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      if (accountService != null) {
        final tracks = await accountService.fetchPlaylistTracks(cleanInput,
            maxTracks: limit);
        if (tracks.isNotEmpty) {
          return tracks;
        }
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Dart InnerTube fetchPlaylistTracks error: $e');
    }

    // 2. Native Multi-Tier Extractor (Android method channel)
    try {
      final cleanUrlOrId = switch (cleanInput) {
        'LM' ||
        'VLLM' ||
        'FEmusic_liked_videos' ||
        'FEmusic_liked_tracks' ||
        'VLSE' =>
          'LL',
        _ => cleanInput,
      };

      final raw = await _guard(
        () => _channel.invokeMethod<Map<Object?, Object?>>('getPlaylist', {
          'url': cleanUrlOrId,
          'limit': limit,
        }),
        timeout: const Duration(seconds: 40),
      );

      if (raw != null) {
        final rawTracks = raw['tracks'] as List<Object?>?;
        final parsed = _parseTracks(rawTracks);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native getPlaylist failed: $e');
    }

    return const [];
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

  PlaybackLatencyTracker? get _tracker =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;

  /// In-flight non-force resolves, keyed `videoId:quality`, so two concurrent
  /// callers for the same track (e.g. the foreground play and a prefetch of the
  /// same id, or a double-tap) share one native chain instead of each launching
  /// their own — which doubled native thread-pool pressure.
  final Map<String, Future<YtmStream>> _inFlightStreamResolves = {};

  /// Resolves audio stream using multi-tier fallback:
  /// (1) Direct authenticated account stream (if logged in)
  /// (2) Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
  /// Remote yt-dlp backend (Engine 3) is decommissioned.
  ///
  /// Coalesces concurrent identical non-force resolves. A `forceRefresh` bypasses
  /// coalescing so it always performs a fresh resolve.
  Future<YtmStream> resolveStream(String videoId,
      {String quality = 'high', bool forceRefresh = false}) {
    if (forceRefresh) {
      return _resolveStreamInner(videoId,
          quality: quality, forceRefresh: true);
    }
    final key = '$videoId:${quality.toLowerCase()}';
    final existing = _inFlightStreamResolves[key];
    if (existing != null) return existing;
    final fut =
        _resolveStreamInner(videoId, quality: quality, forceRefresh: false);
    _inFlightStreamResolves[key] = fut;
    return fut.whenComplete(() {
      if (identical(_inFlightStreamResolves[key], fut)) {
        _inFlightStreamResolves.remove(key);
      }
    });
  }

  Future<YtmStream> _resolveStreamInner(String videoId,
      {String quality = 'high', bool forceRefresh = false}) async {
    // Check Task 2 in-memory URL cache first
    final urlCache =
        getIt.isRegistered<YtmUrlCache>() ? getIt<YtmUrlCache>() : null;
    if (!forceRefresh) {
      final cachedEntry = urlCache?.get(videoId, quality: quality);
      if (cachedEntry != null && !cachedEntry.isExpired()) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        return cachedEntry.toStream(quality: quality);
      }
    }

    // Remember the first classified failure so the caller gets an actionable
    // error (e.g. BOT_CHALLENGE → "verification" + poToken recovery) instead
    // of a generic YTM_FAILED that maps to recoveryAction.none (dead end).
    Object? firstError;
    // FIX-C01: Check per-video cooldown as well as global IP cooldown
    var inBotCooldown = isBotCoolingDown || isVideoCoolingDown(videoId);
    if (inBotCooldown) {
      // Only a stale-attestation block can be cured by a fresh token. A generic
      // bot challenge or an IP block is an egress verdict: the native token is
      // already valid, so `ensurePoTokenReady()` returning true does NOT mean the
      // IP is unblocked. The old code lifted the cooldown whenever the token was
      // "ready", which re-ran the whole native chain for every track on a blocked
      // VPN — the repeated 25s-timeout sweeps seen in the logs.
      final lastSignal = _lastBotChallenge?.signal;
      if (lastSignal == YtmBlockSignal.poTokenInvalid) {
        try {
          final ready =
              await ensurePoTokenReady().timeout(const Duration(seconds: 4));
          if (ready) {
            debugPrint(
                '[YTM_SERVICE] Fresh poToken ready, lifting token cooldown for $videoId');
            _noteResolveSuccess(videoId: videoId);
            inBotCooldown = false;
          }
        } catch (_) {}
      } else {
        debugPrint(
            '[YTM_SERVICE] Block cooldown active (${lastSignal?.name ?? 'unknown'}); failing fast for $videoId');
      }
    }
    if (inBotCooldown) {
      debugPrint(
          '[YTM_SERVICE] Bot cooldown active, skipping native tiers for $videoId');
    }

    try {
      _tracker?.markStage(PlaybackStage.pluginEntered);
    } catch (_) {}
    // 1. Try direct authenticated YouTube Music InnerTube Player API if logged in
    try {
      if (!inBotCooldown && getIt.isRegistered<YtmAccountService>()) {
        final account = getIt<YtmAccountService>();
        if (account.isLoggedIn) {
          // Do NOT gate Tier-1 on dataSyncId. YtmAccountService.resolvePlayerStream
          // already detects a missing/empty dataSyncId and runs its chain as a
          // clean guest pass (no session cookies), which is strictly better than
          // skipping Tier-1 entirely: that handed every signed-in resolution to
          // Tier-2, whose WEB_REMIX request pairs session cookies with a guest
          // poToken — the mismatch YouTube answers with UNPLAYABLE "Video
          // unavailable" / LOGIN_REQUIRED. It was also the reason dataSyncId was
          // never harvested, so the account-bound token could never be minted.
          //
          // Kick a (throttled) dataSyncId bootstrap in parallel so later tracks
          // resolve with the account-bound token; the current resolve proceeds
          // on the guest/native chain meanwhile.
          if (account.dataSyncId == null || account.dataSyncId!.isEmpty) {
            debugPrint('[YTM_SERVICE] Tier-1 running as guest pass for $videoId: '
                'dataSyncId not yet ready; bootstrapping in background.');
            unawaited(account.ensureDataSyncId());
          }
          try {
            _tracker?.markStage(PlaybackStage.clientRequestSent);
            _tracker?.markStage(PlaybackStage.poTokenNeeded);
          } catch (_) {}
          final directStream =
              await account.resolvePlayerStream(videoId, quality: quality);
          if (directStream != null) {
            try {
              _tracker?.markStage(PlaybackStage.urlObtained);
            } catch (_) {}
            // putStream, not put: the entry keeps the real container, MIME and
            // bitrate. put() alone let a later cache hit rebuild the stream by
            // guessing them from the URL, which wrote Opus bytes into a .m4a.
            urlCache?.putStream(directStream, quality: quality);
            _noteResolveSuccess(videoId: videoId);
            return directStream;
          }
        }
      }
    } catch (e) {
      // Never abort the whole chain on a Tier-1 auth failure: an expired or
      // mismatched (guest-poToken + auth-cookies) WEB_REMIX request must fall
      // back to guest native/remote playback, otherwise login breaks public
      // streams that work logged-out. Auth is only surfaced if every tier fails
      // (see final rethrow below).
      if (e is YtmException && e.isAuth) {
        debugPrint('[YTM_SERVICE] Direct account stream auth failure, falling back to guest engines: $e');
        firstError ??= e;
      } else {
        debugPrint('[YTM_SERVICE] Direct account stream resolution fallback: $e');
      }
      // If the account tier hit an IP-level block or a bot challenge, activate
      // cooldown so the native tier doesn't burn through 9 more clients for the
      // same result. A transport failure is excluded on purpose: the next tier
      // may well have a route (remote backend), and cooling down on an offline
      // blip is what made a one-second signal drop look like an IP block.
      if (!inBotCooldown &&
          e is YtmException &&
          (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
        _noteBotChallenge(e, videoId: videoId);
      }
    }

    // 2. Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
    Object? nativeError;
    try {
      // Fail fast with a FRESH per-video exception: rethrowing _lastBotChallenge
      // pastes another video's id + trace id into this video's logs and makes a
      // stale verdict look like a new native failure. The stored challenge is
      // only kept for the cooldown window timing.
      if (inBotCooldown) {
        throw YtmException('BOT_CHALLENGE',
            'Cooling down after YouTube verification challenge ($videoId)');
      }
      try {
        _tracker?.markStage(PlaybackStage.clientRequestSent);
        // Check poToken state heuristically: if we have a cached token, this is warm
        _tracker?.markStage(PlaybackStage.poTokenNeeded);
      } catch (_) {}
      // maxRetries: 0 — the native side already runs its own multi-client
      // hedged chain with internal retries. A Dart-level timeout retry can't
      // cancel the still-running native call, so it just stacks a *second* full
      // 9-client chain on top of the first, the thread-pool starvation this
      // class is trying to avoid. Let a timeout fall through to the Dart tier.
      final raw = await _guard(
        () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
          'videoId': videoId,
          'quality': quality,
        }),
        timeout: _defaultResolveTimeout,
        maxRetries: 0,
      );

      final stream = raw == null ? null : YtmStream.fromChannel(raw);
      if (stream != null) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        urlCache?.putStream(stream, quality: quality);
        _noteResolveSuccess(videoId: videoId);
        return stream;
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native stream resolution failed: $e');
      // Same guest-fallback rule as Tier-1: a native LOGIN_REQUIRED (often
      // caused by stale synced cookies) must still try the remote backend
      // before surfacing auth to the UI.
      firstError ??= e;
      nativeError = e;
      // The cooldown short-circuit itself must not extend the window, or a
      // retry loop would hold it open forever (fixed window from first hit).
      if (!inBotCooldown &&
          e is YtmException &&
          (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
        _noteBotChallenge(e, videoId: videoId);
      }
    }

    // 2.5 PoToken refresh-and-retry (on-device only, no XDM backend).
    // A stale/mismatched BotGuard token fails every client identically; one
    // invalidate + mint + single native retry recovers without burning the
    // full Dart chain or imposing a bot cooldown on a non-bot failure.
    if (nativeError is YtmException &&
        nativeError.signal == YtmBlockSignal.poTokenInvalid &&
        breaker.shouldAllow(YtmBlockSignal.poTokenInvalid)) {
      try {
        debugPrint('[YTM_SERVICE] Tier-2.5 poToken refresh-and-retry for $videoId');
        await invalidatePoToken().timeout(const Duration(seconds: 3));
        final ready = await ensurePoTokenReady().timeout(const Duration(seconds: 6));
        if (ready) {
          // maxRetries: 0 — this tier IS the single deliberate retry; a
          // timeout retry here would stack a second native chain (see tier 2).
          final raw = await _guard(
            () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
              'videoId': videoId,
              'quality': quality,
            }),
            timeout: _defaultResolveTimeout,
            maxRetries: 0,
          );
          final stream = raw == null ? null : YtmStream.fromChannel(raw);
          if (stream != null) {
            try {
              _tracker?.markStage(PlaybackStage.urlObtained);
            } catch (_) {}
            urlCache?.putStream(stream, quality: quality);
            _noteResolveSuccess(videoId: videoId);
            return stream;
          }
        }
      } catch (e) {
        debugPrint('[YTM_SERVICE] Tier-2.5 retry failed: $e');
        if (e is YtmException) breaker.classifyAndRecord(e);
      }
    }

    // 2.9 While an egress block is active, the pure-Dart sweep below pays three
    // 12s client timeouts for the same refusal. Surface the structured block
    // immediately so the UI can explain it and the queue can skip on instead of
    // stalling for another half minute per track.
    if (inBotCooldown) {
      final blocked = firstError;
      if (blocked is YtmException &&
          (blocked.isBotBlocked || blocked.isIpBlocked || blocked.isThrottled)) {
        throw blocked;
      }
      throw const YtmException('BOT_CHALLENGE',
          'YouTube is blocking this network. Try another connection or a proxy.');
    }

    // 3. Pure-Dart InnerTube Stream Resolver (Desktop / Non-Android / Native Plugin Fallback)
    try {
      debugPrint('[YTM_SERVICE] Attempting Dart InnerTube stream resolution for $videoId');
      final dartStream = await _resolveStreamDart(videoId, quality: quality);
      if (dartStream != null) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        urlCache?.putStream(dartStream, quality: quality);
        _noteResolveSuccess(videoId: videoId);
        return dartStream;
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Dart InnerTube stream resolution failed: $e');
      firstError ??= e;
    }

    // All engines failed: surface the first classified engine error so the
    // UI/recovery layer sees the real cause (bot/rate/auth) with its mapped
    // recovery action, not a generic dead-end.
    final err = firstError;
    if (err is YtmException) throw err;
    if (err != null) throw err;
    throw const YtmException('YTM_FAILED', 'No stream returned from any engine');
  }

  /// Pure-Dart fallback that directly queries InnerTube player API using
  /// lightweight clients (e.g. ANDROID_VR, TVHTML5) that provide direct audio
  /// stream URLs without requiring native deciphers or MethodChannels.
  Future<YtmStream?> _resolveStreamDart(String videoId,
      {String quality = 'high'}) async {
    String apiKey = YtmClientVersionResolver.fallbackApiKey;
    if (getIt.isRegistered<YtmClientVersionResolver>()) {
      apiKey = getIt<YtmClientVersionResolver>().apiKey;
    }

    final clients = [
      (
        name: 'ANDROID_VR',
        version: '1.63.27',
        clientNameId: '28',
        ua: 'com.google.android.apps.youtube.vr/1.63.27 (Linux; U; Android 14; en_US) gzip',
        host: 'https://www.youtube.com',
      ),
      (
        name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        version: '2.0',
        clientNameId: '85',
        ua: 'Mozilla/5.0 (PlayStation 4 5.55) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.0 Safari/605.1.15',
        host: 'https://www.youtube.com',
      ),
      (
        name: 'ANDROID',
        version: '19.44.38',
        clientNameId: '3',
        ua: 'com.google.android.youtube/19.44.38 (Linux; U; Android 14; en_US) gzip',
        host: 'https://www.youtube.com',
      ),
    ];

    for (final client in clients) {
      try {
        final body = jsonEncode({
          'context': {
            'client': {
              'clientName': client.name,
              'clientVersion': client.version,
              'hl': 'en',
              'gl': 'US',
            },
          },
          'videoId': videoId,
          'playbackContext': {
            'contentPlaybackContext': {
              'html5Preference': 'HTML5_PREF_WANTS',
            },
          },
        });

        final headers = <String, String>{
          'Content-Type': 'application/json',
          'User-Agent': client.ua,
          'X-Goog-Api-Key': apiKey,
          'x-youtube-client-name': client.clientNameId,
          'x-youtube-client-version': client.version,
        };

        final response = await _httpClient
            .post(
              Uri.parse(
                  '${client.host}/youtubei/v1/player?prettyPrint=false&key=$apiKey'),
              headers: headers,
              body: body,
            )
            // FIX-C06: 12-second timeout per client in _resolveStreamDart
            .timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final playability = data['playabilityStatus'] as Map<String, dynamic>?;
        final status = playability?['status'] as String? ?? '';
        if (status == 'LOGIN_REQUIRED' ||
            status == 'UNPLAYABLE' ||
            status.contains('BOT')) {
          continue;
        }

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) continue;

        final adaptive = (streamingData['adaptiveFormats'] as List<dynamic>? ??
                [])
            .whereType<Map<String, dynamic>>()
            .toList();

        final audioFormats = <({Map<String, dynamic> format, String url})>[];
        for (final f in adaptive) {
          final mime = f['mimeType'] as String? ?? '';
          final streamUrl = f['url'] as String?;
          if (mime.startsWith('audio/') &&
              streamUrl != null &&
              streamUrl.isNotEmpty) {
            audioFormats.add((format: f, url: streamUrl));
          }
        }

        if (audioFormats.isEmpty) {
          final formats = (streamingData['formats'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          for (final f in formats) {
            final streamUrl = f['url'] as String?;
            if (streamUrl != null && streamUrl.isNotEmpty) {
              audioFormats.add((format: f, url: streamUrl));
            }
          }
        }

        if (audioFormats.isEmpty) continue;

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
                      (((b.format['bitrate'] as num?) ?? 128000) - 128000).abs()
                  ? a
                  : b),
          _ => pool.reduce((a, b) =>
              ((a.format['bitrate'] as num?) ?? 0) >
                      ((b.format['bitrate'] as num?) ?? 0)
                  ? a
                  : b),
        };

        final mime = selected.format['mimeType'] as String? ?? 'audio/mp4';
        final bitrate = (selected.format['bitrate'] as num?)?.toInt() ?? 128000;
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
          userAgent: client.ua,
        ).withResolvedExpiry();
      } catch (e) {
        debugPrint('[YTM_SERVICE] Dart client ${client.name} resolve error: $e');
      }
    }

    return null;
  }

  Future<T?> _guard<T>(
    Future<T?> Function() call, {
    required Duration timeout,
    int maxRetries = 1,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final adaptiveTimeout = timeout + Duration(seconds: attempt * 5);
        return await call().timeout(adaptiveTimeout);
      } on TimeoutException {
        if (attempt == maxRetries) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
        // Back off before retrying a timeout: a tight loop hammers an
        // already-struggling route/VPN exit and hastens an IP block.
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } on MissingPluginException {
        throw const YtmException('YTM_UNSUPPORTED');
      } on SocketException catch (e) {
        // Offline/DNS failure — retry with backoff like YTM_TIMEOUT, surface offline
        if (attempt == maxRetries) {
          ErrorLogger.log('YTM network failure (offline): $e', category: 'YTM');
          throw YtmException('YTM_OFFLINE', 'No internet: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } on PlatformException catch (e) {
        // The native side packages `{signal, traceId}` in `details` for every
        // InnertubeException. Both used to be dropped on the floor, so a
        // structured verdict degraded into a substring guess at the message and
        // the trace id never reached the log line that was meant to carry it.
        final detailsMap = e.details is Map ? e.details as Map : null;
        final signalCode = detailsMap?['signal'] as String?;
        final traceId = detailsMap?['traceId'] as String?;
        // Prefer whichever of the two the Dart enum actually recognises: the
        // plugin sets code = signal.code for Innertube failures, but a wrapper
        // higher up can replace the code with a generic one.
        final resolvedCode = YtmBlockSignal.fromCode(e.code) != null
            ? e.code
            : (signalCode ?? e.code);

        final codeUpper = resolvedCode.toUpperCase();
        // Feed 429s into the shared Dart limiter so search/resolve/download
        // all cool down together instead of each retrying against the same IP.
        if (codeUpper.contains('429') ||
            codeUpper.contains('RATE_LIMIT') ||
            (e.message?.toUpperCase().contains('429') ?? false)) {
          YtmRateLimiter.shared.onRateLimited();
        }
        // A full native chain already tried every client: blindly replaying
        // the whole chain 2x more triples thread-pool load and turns one
        // IP-flag into cascading timeouts. Fail fast to the next engine.
        final failure = YtmException(resolvedCode, e.message, traceId);
        final isFatalCode = failure.isDisabled ||
            failure.isBotBlocked ||
            failure.isThrottled ||
            failure.isAuth;

        if (attempt == maxRetries || isFatalCode) {
          ErrorLogger.log(
              'YTM call failed: ${failure.code}'
              '${traceId == null ? '' : ' [trace=$traceId]'} ${e.message}',
              category: 'YTM');
          // Only an unambiguous auth verdict pings the UI: SIGN_IN_REQUIRED is
          // also what a private or members-only track returns, and prompting a
          // re-login for one of those trains the user to ignore the prompt.
          if (resolvedCode == 'LOGIN_REQUIRED' || resolvedCode == 'YTM_AUTH') {
            notifyAuthExpired();
          }
          throw failure;
        }
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw const YtmException('YTM_FAILED', 'Max retries exhausted');
  }
}
