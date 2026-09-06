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
import 'xdm_backend_service.dart';
import 'ytm_account_service.dart';
import 'ytm_client_version_resolver.dart';
import 'ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';
import '../telemetry/playback_latency_tracker.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';

import '../errors/ytm_error_classifier.dart';

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
  static const _botCooldown = Duration(seconds: 90);
  /// Extended cooldown for IP-level blocks (every client fails instantly).
  static const _ipBlockCooldown = Duration(seconds: 180);
  DateTime _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  YtmException? _lastBotChallenge;

  bool get isBotCoolingDown => DateTime.now().isBefore(_botChallengeUntil);

  void _noteBotChallenge(YtmException e) {
    _lastBotChallenge = e;
    // Use extended cooldown for IP-level blocks: these don't resolve by
    // just waiting a minute, and retrying only deepens the block. Keyed off
    // the parsed signal, not off `isNetwork`, so an offline blip no longer
    // buys a 3-minute cooldown that outlives the outage.
    final cooldown = e.isIpBlocked ? _ipBlockCooldown : _botCooldown;
    _botChallengeUntil = DateTime.now().add(cooldown);
  }

  /// Any successful resolve proves the IP is not blocked, so an active cooldown
  /// must end: a fixed window kept skipping the native tiers (the only ones
  /// that produce high-bitrate streams) for minutes after YouTube let us back
  /// in, and every retry inside the window rethrew the stale challenge.
  void _noteResolveSuccess() {
    if (_lastBotChallenge == null &&
        _botChallengeUntil.millisecondsSinceEpoch == 0) {
      return;
    }
    _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBotChallenge = null;
  }

  /// Test-only: clears bot-cooldown state.
  void debugClearBotCooldown() {
    _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBotChallenge = null;
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
      return value ?? true;
    } on YtmException {
      return true;
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
      String apiKey = const String.fromEnvironment(
        'YTM_API_KEY',
        defaultValue: 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30',
      );
      String clientVersion = '1.20250820.01.00';
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

  Future<List<YtmTrack>> getPlaylistTracks(String urlOrId,
      {int limit = 100}) async {
    final cleanUrlOrId = switch (urlOrId.trim()) {
      'LM' ||
      'VLLM' ||
      'FEmusic_liked_videos' ||
      'FEmusic_liked_tracks' ||
      'VLSE' =>
        'LL',
      _ => urlOrId.trim(),
    };

    final resolvedUrl = cleanUrlOrId.startsWith('http')
        ? cleanUrlOrId
        : 'https://www.youtube.com/playlist?list=$cleanUrlOrId';

    // 1. Native Extractor
    try {
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

    // 2. Engine 3: Remote yt-dlp backend fallback if enabled
    try {
      if (getIt.isRegistered<XdmBackendService>()) {
        final xdm = getIt<XdmBackendService>();
        if (await xdm.isEnabled()) {
          final account = getIt.isRegistered<YtmAccountService>()
              ? getIt<YtmAccountService>()
              : null;
          final playlistTracks = await xdm.getPlaylist(
            resolvedUrl,
            limit: limit,
            cookies: account?.cookies,
          );
          if (playlistTracks.isNotEmpty) {
            return playlistTracks;
          }
        }
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Remote yt-dlp playlist fallback: $e');
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

  /// Resolves audio stream using multi-tier fallback:
  /// (1) Direct authenticated account stream (if logged in)
  /// (2) Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
  /// (3) Engine 3: Remote yt-dlp backend (XdmBackendService)
  Future<YtmStream> resolveStream(String videoId,
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
    final inBotCooldown = isBotCoolingDown;
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
          // Guard: skip Tier-1 if dataSyncId is not yet available. Without a
          // valid dataSyncId we cannot mint an account-bound poToken, so the
          // chain would use a guest token paired with auth cookies — a mismatch
          // YouTube rejects with LOGIN_REQUIRED / UNPLAYABLE on every client.
          // Tier-2 (native extractor) handles unauthenticated resolution cleanly.
          if (account.dataSyncId == null || account.dataSyncId!.isEmpty) {
            debugPrint('[YTM_SERVICE] Skipping Tier-1 for $videoId: dataSyncId '
                'not yet ready (session warming in progress). Tier-2 will handle.');
          } else {
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
              _noteResolveSuccess();
              return directStream;
            }
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
        _noteBotChallenge(e);
      }
    }

    // 2. Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
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
      final raw = await _guard(
        () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
          'videoId': videoId,
          'quality': quality,
        }),
        timeout: _defaultResolveTimeout,
      );

      final stream = raw == null ? null : YtmStream.fromChannel(raw);
      if (stream != null) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        urlCache?.putStream(stream, quality: quality);
        _noteResolveSuccess();
        return stream;
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native stream resolution failed: $e');
      // Same guest-fallback rule as Tier-1: a native LOGIN_REQUIRED (often
      // caused by stale synced cookies) must still try the remote backend
      // before surfacing auth to the UI.
      firstError ??= e;
      // The cooldown short-circuit itself must not extend the window, or a
      // retry loop would hold it open forever (fixed window from first hit).
      if (!inBotCooldown &&
          e is YtmException &&
          (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
        _noteBotChallenge(e);
      }
    }

    // 3. Engine 3: Remote yt-dlp backend fallback if enabled and healthy
    try {
      try {
        _tracker?.markStage(PlaybackStage.clientRequestSent);
      } catch (_) {}
      if (getIt.isRegistered<XdmBackendService>()) {
        final xdm = getIt<XdmBackendService>();
        if (await xdm.isEnabled()) {
          final account = getIt.isRegistered<YtmAccountService>()
              ? getIt<YtmAccountService>()
              : null;
          final remoteStream = await xdm.resolveStream(
            videoId,
            quality: quality,
            cookies: account?.cookies,
          );
          if (remoteStream != null) {
            try {
              _tracker?.markStage(PlaybackStage.urlObtained);
            } catch (_) {}
            urlCache?.putStream(remoteStream, quality: quality);
            // The remote backend resolving does not clear a YouTube-side
            // cooldown: it proves the *backend's* IP is fine, not this device's.
            return remoteStream;
          }
        }
      }
    } catch (e) {
      debugPrint(
          '[YTM_SERVICE] Remote yt-dlp backend stream resolution fallback: $e');
      if (e is YtmException && (e.isBotBlocked || e.isThrottled)) {
        rethrow;
      }
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
