// lib/data/services/ytm_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../core/constants/channels.dart';
import '../../core/constants/embedded_browser_ua.dart';
import '../../core/di/injection.dart';
import 'xdm_backend_service.dart';
import 'ytm_account_service.dart';
import 'ytm_client_version_resolver.dart';
import 'ytm_url_cache.dart';
import '../../domain/models/ytm_track.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../core/utils/error_logger.dart';

import '../../core/errors/ytm_error_classifier.dart';

/// A failed YTM call with structured block signal and trace ID.
class YtmException implements Exception {
  final String code;
  final String? details;
  final String? traceId;

  const YtmException(this.code, [this.details, this.traceId]);

  YtmBlockSignal? get signal =>
      YtmErrorClassifier.classify(details ?? code, traceId).signal;

  /// Retrying later may work; retrying the rest of the queue now will not.
  bool get isNetwork =>
      code == 'YTM_NETWORK' ||
      code == 'YTM_TIMEOUT' ||
      signal == YtmBlockSignal.ipBlocked;

  /// YouTube has flagged the IP / client as automated/bot and requires authentication.
  /// NOTE: rateLimited (429) is intentionally excluded — rate limits should use
  /// backoff, not device-level blocking. LOGIN_REQUIRED is an auth signal handled
  /// by [isAuth], not a bot signal.
  bool get isBotBlocked =>
      signal == YtmBlockSignal.botChallenge ||
      signal == YtmBlockSignal.poTokenInvalid ||
      code == 'BOT_CHALLENGE' ||
      code == 'PO_TOKEN_INVALID' ||
      code == 'YTM_BOT_BLOCKED' ||
      code == 'YTM_RECAPTCHA' ||
      code == 'RECAPTCHA_REQUIRED' ||
      (details != null &&
          (details!.contains('bot') ||
              details!.contains('Sign in to confirm')));

  /// Session has expired or authentication is invalid.
  bool get isAuth =>
      signal == YtmBlockSignal.signInRequired ||
      code == 'SIGN_IN_REQUIRED' ||
      code == 'YTM_AUTH' ||
      code == 'LOGIN_REQUIRED' ||
      (details != null &&
          (details!.toLowerCase().contains('unauthenticated') ||
              details!.contains('LOGIN_REQUIRED')));

  /// Fatal error where looping / skipping the queue will only worsen the block.
  bool get isFatal => isNetwork || isDisabled || isBotBlocked || isAuth;

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

  // Tier-1 (account) deadline for direct authenticated Innertube playback.
  static const Duration _tier1Deadline = Duration(seconds: 20);

  // TTFA hard budget for the native ladder (tier-2).
  static const Duration _resolveFirstAttemptTimeout = Duration(seconds: 20);

  /// TTFA: device-level negative cache — when the native ladder returns
  /// LOGIN_REQUIRED or BotChallenge from every client, the block is at the
  /// device/IP level, not per-video. A single global flag fast-fails ALL
  /// subsequent resolves during the block window instead of re-burning the
  /// full 8–9s dead ladder for each different song.
  // Reduced from 3 min to 90s: with XDM (tier-3) enabled, the next song
  // should try the remote backend immediately rather than fast-failing for
  // 3 full minutes. 90s is enough to avoid hammering a dead ladder while
  // still recovering quickly when network conditions change.
  static const Duration _signinAbortTtl = Duration(seconds: 90);
  static DateTime? _globalBlockUntil;

  @visibleForTesting
  static void resetGlobalBlock() {
    _globalBlockUntil = null;
  }

  final MethodChannel _channel = const MethodChannel(channelName);
  final StreamController<void> _authExpiredController =
      StreamController<void>.broadcast();

  YtmService() {
    // TTFA telemetry: one-way relay of key native timings (poToken mint,
    // ladder client attempts, rate-limiter waits, executor queue wait) pushed
    // by the Kotlin side over the same channel. Purely passive — the native
    // side never waits on a reply.
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'nativeTiming') {
      _relayNativeTiming(call.arguments);
    }
    return null;
  }

  void _relayNativeTiming(dynamic arguments) {
    try {
      if (arguments is! Map) return;
      final name = arguments['name']?.toString();
      final durationMs = (arguments['durationMs'] as num?)?.toInt();
      if (name == null || name.isEmpty || durationMs == null) return;
      final attrs = arguments['attrs'] is Map
          ? (arguments['attrs'] as Map)
              .map((k, v) => MapEntry(k.toString(), v))
          : null;
      _tracker?.markNativeTiming(name, durationMs, attrs: attrs);
    } catch (_) {
      // Telemetry must never affect playback.
    }
  }

  bool? _available;

  Stream<void> get onAuthExpired => _authExpiredController.stream;

  void notifyAuthExpired() {
    if (_authExpiredController.isClosed) return;
    try {
      _authExpiredController.add(null);
    } catch (_) {}
  }

  @disposeMethod
  void dispose() {
    try {
      _authExpiredController.close();
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

  /// Synchronizes cookies into the native CookieManager so the extractor
  /// makes authenticated requests on all YouTube endpoints.
  Future<void> syncCookies(String cookies) async {
    _globalBlockUntil = null;
    try {
      await _channel.invokeMethod<bool>('setCookies', {'cookies': cookies});
    } catch (_) {}
  }

  /// Calls native PoTokenManager to ensure attestation tokens are ready.
  Future<bool> ensurePoTokenReady() async {
    try {
      final ready = await _channel.invokeMethod<bool>('ensurePoTokenReady');
      return ready ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Invalidates BotGuard poToken state on bot-detection block or session logout.
  Future<void> invalidatePoToken() async {
    try {
      await _channel.invokeMethod<bool>('invalidatePoToken');
    } catch (_) {}
  }

  /// Retrieves state of PoTokenManager.
  Future<Map<String, dynamic>?> getPoTokenState() async {
    try {
      final state = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getPoTokenState',
      );
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
      );
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
      await _channel.invokeMethod<bool>('setDataSyncId', {
        'dataSyncId': dataSyncId,
      });
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
    _globalBlockUntil = null;
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

  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final value = await _guard(
        () => _channel.invokeMethod<bool>('isAvailable'),
        timeout: const Duration(seconds: 5),
      );
      return _available = value ?? false;
    } on YtmException {
      return _available = false;
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

  final Map<String, Future<dynamic>> _inFlightCalls = {};

  Future<T> _runCoalesced<T>(String key, Future<T> Function() call) async {
    if (_inFlightCalls.containsKey(key)) {
      return await (_inFlightCalls[key] as Future<T>);
    }
    final future = call();
    _inFlightCalls[key] = future;
    try {
      return await future;
    } finally {
      unawaited(_inFlightCalls.remove(key));
    }
  }

  Future<List<YtmTrack>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    return _runCoalesced('search:$trimmed:$limit', () async {
      final raw = await _guard(
        () => _channel.invokeMethod<List<Object?>>('search', {
          'query': trimmed,
          'limit': limit,
          ..._localeArgs(),
        }),
        timeout: const Duration(seconds: 6),
        maxRetries: 0,
      );

      return _parseTracks(raw);
    });
  }

  /// Search with fallback: First tries fast Innertube JSON search (~200ms),
  /// then falls back to native extractor if empty.
  Future<List<YtmTrack>> searchWithFallback(
    String query, {
    int limit = 30,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Primary: Fast direct Innertube JSON search (~200ms, authenticated when logged in)
    try {
      final innertubeResults = await _searchInnertube(trimmed, limit: limit);
      if (innertubeResults.isNotEmpty) return innertubeResults;
    } catch (e) {
      debugPrint('[YTM_SERVICE] Innertube search failed, trying native extractor: $e');
    }

    // 2. Fallback: Native extractor search (bounded to 6s, zero retries)
    try {
      final results = await search(trimmed, limit: limit);
      if (results.isNotEmpty) return results;
    } catch (e) {
      debugPrint('[YTM_SERVICE] Native search fallback failed: $e');
    }

    return const [];
  }

  Future<List<YtmTrack>> _searchInnertube(
    String query, {
    int limit = 30,
  }) async {
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
      // Log warning if default key is being used (should be overridden via --dart-define YTM_API_KEY)
      if (apiKey == 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30') {
        debugPrint(
          '[YTM_SERVICE] Warning: Using default YTM_API_KEY — override via --dart-define=YTM_API_KEY for production',
        );
      }

      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': clientVersion,
            'hl': 'en',
            'gl': 'US',
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
            final authHeader = YtmAccountService.buildAuthorizationHeader(
              cookies,
            );
            if (authHeader != null) {
              headers['Authorization'] = authHeader;
            }
          }
        }
      }

      final response = await http
          .post(
            Uri.parse(
              'https://music.youtube.com/youtubei/v1/search?prettyPrint=false&key=$apiKey',
            ),
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
              try {
                final r =
                    node['musicResponsiveListItemRenderer']
                        as Map<String, dynamic>;
                final flexCols = r['flexColumns'] as List<dynamic>? ?? [];
                String? videoId;
                String title = 'Unknown Title';
                String artist = 'Unknown Artist';

                final pData = r['playlistItemData'] as Map<String, dynamic>?;
                videoId = pData?['videoId'] as String?;

                if (flexCols.isNotEmpty && flexCols[0] is Map) {
                  final c0Map = flexCols[0] as Map;
                  final runs =
                      c0Map['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                          as List<dynamic>?;
                  if (runs != null && runs.isNotEmpty && runs[0] is Map) {
                    final firstRun = runs[0] as Map;
                    title = firstRun['text'] as String? ?? title;
                    final nav = firstRun['navigationEndpoint'] as Map<String, dynamic>?;
                    videoId ??= nav?['watchEndpoint']?['videoId'] as String?;
                  }
                }
                if (flexCols.length > 1 && flexCols[1] is Map) {
                  final c1Map = flexCols[1] as Map;
                  final runs =
                      c1Map['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                          as List<dynamic>?;
                  if (runs != null && runs.isNotEmpty && runs[0] is Map) {
                    artist = (runs[0] as Map)['text'] as String? ?? artist;
                  }
                }

                if (videoId != null && videoId.length == 11) {
                  tracks.add(
                    YtmTrack(
                      videoId: videoId,
                      title: title,
                      artist: artist,
                      duration: Duration.zero,
                    ),
                  );
                }
              } catch (_) {
                // Per-item failures must not abort the whole search result set.
              }
              return;
            }
            for (final val in node.values) {
              try {
                traverse(val);
              } catch (_) {}
            }
          } else if (node is List) {
            for (final item in node) {
              try {
                traverse(item);
              } catch (_) {}
            }
          }
        }

        try {
          traverse(json);
        } catch (_) {}
        return tracks.take(limit).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<YtmTrack>> trending({int limit = 30}) async {
    try {
      final raw = await _guard(
        () => _channel.invokeMethod<List<Object?>>('trending', {
          'limit': limit,
          ..._localeArgs(),
        }),
        timeout: const Duration(seconds: 5),
        maxRetries: 0,
      );
      final tracks = _parseTracks(raw);
      if (tracks.isNotEmpty) return tracks;
    } catch (_) {}

    // Fallback: fast direct search for top trending music
    return await _searchInnertube('top music hits trending', limit: limit);
  }

  Future<List<YtmTrack>> getPlaylistTracks(
    String urlOrId, {
    int limit = 100,
  }) async {
    final cleanUrlOrId = switch (urlOrId.trim()) {
      'LM' ||
      'VLLM' ||
      'FEmusic_liked_videos' ||
      'FEmusic_liked_tracks' ||
      'VLSE' => 'LL',
      _ => urlOrId.trim(),
    };

    final resolvedUrl =
        cleanUrlOrId.startsWith('http')
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
          final account =
              getIt.isRegistered<YtmAccountService>()
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
  Future<YtmStream> resolveStream(
    String videoId, {
    String quality = 'high',
    bool forceRefresh = false,
  }) async {
    // Y-01: Validate video ID matches 11 valid characters
    if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      throw const YtmException('INVALID_VIDEO_ID', 'Video ID must be exactly 11 characters');
    }

    // Check Task 2 in-memory URL cache first
    final urlCache =
        getIt.isRegistered<YtmUrlCache>() ? getIt<YtmUrlCache>() : null;
    if (!forceRefresh) {
      final cachedEntry = urlCache?.get(videoId, quality: quality);
      if (cachedEntry != null && !cachedEntry.isExpired()) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
          _tracker?.setTag('cacheHit', 'true');
        } catch (_) {}
        return cachedEntry.toStream(quality: quality);
      }
    }

    // TTFA: fast-fail while a device/IP-level bot-block is still fresh.
    // The block is global (all videos share the same IP), so we use a single
    // timestamp rather than a per-videoId map.
    // NOTE: Logged-in users bypass the global block entirely — the block was
    // set by the native ladder (tier-2) which uses different client contexts
    // without the user's cookies. The authenticated WEB_REMIX + cookies path
    // is independent of the native ladder's fate.
    final isLoggedInForBlock = getIt.isRegistered<YtmAccountService>() &&
        getIt<YtmAccountService>().isLoggedIn;
    final globalBlock = _globalBlockUntil;
    if (globalBlock != null) {
      if (DateTime.now().isBefore(globalBlock)) {
        if (!isLoggedInForBlock) {
          throw const YtmException(
            'YTM_SIGNIN_REQUIRED',
            'Sign in to YouTube Music - Google is currently blocking playback '
            'from this device or network',
          );
        }
        // Logged-in: skip fast-fail, let the authenticated path try.
        debugPrint(
          '[YTM_SERVICE] Global block active but user is logged in — '
          'bypassing fast-fail to try authenticated path.',
        );
      } else {
        _globalBlockUntil = null; // block expired, clear it
      }
    }

    return _runCoalesced('resolve:$videoId:$quality', () async {
      var signInRequiredAbort = false;
      YtmException? lastNativeException;
      try {
        _tracker?.markStage(PlaybackStage.pluginEntered);
        _tracker?.setTag('cacheHit', 'false');
      } catch (_) {}

      final account = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      final isLoggedIn = account?.isLoggedIn ?? false;

      // ── Parallel race: tier-1 (account) vs tier-2 (native Kotlin) ──────────
      // Both are fired simultaneously. The first to return a valid URL wins.
      // The other future keeps running but its result is discarded (or cached
      // as a bonus). Auth errors (session expiry) surface immediately and
      // cancel the race. This saves the full slower-path latency vs the old
      // sequential waterfall.
      if (isLoggedIn && account != null) {
        try {
          _tracker?.markStage(PlaybackStage.clientRequestSent);
          _tracker?.markStage(PlaybackStage.poTokenNeeded);
        } catch (_) {}

        YtmStream? t1Result;
        YtmStream? t2Result;
        Object? t1Error;
        Object? t2Error;

        // Fire both tiers at the same time.
        // catchError must return YtmStream? — capture the error as a side-effect
        // and return null so the future chain stays typed correctly.
        final t1Future = account
            .resolvePlayerStream(videoId, quality: quality)
            .timeout(_tier1Deadline)
            .then((s) { t1Result = s; return s; })
            .catchError((Object e) { t1Error = e; return null as YtmStream?; });

        final t2Future = _guard(
          () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
            'videoId': videoId,
            'quality': quality,
          }),
          timeout: _resolveFirstAttemptTimeout,
          maxRetries: 0,
        )
            .then((raw) {
              t2Result = raw == null ? null : YtmStream.fromChannel(raw);
              return t2Result;
            })
            .catchError((Object e) { t2Error = e; return null as YtmStream?; });

        // Use a Completer so we return the instant the FIRST good URL arrives.
        final winner = Completer<YtmStream?>();

        void tryResolve() {
          if (winner.isCompleted) return;
          final t1 = t1Result;
          final t2 = t2Result;
          if (t1 != null && t1.url.trim().isNotEmpty) {
            winner.complete(t1);
          } else if (t2 != null && t2.url.trim().isNotEmpty) {
            winner.complete(t2);
          } else if (t1Error != null && t2Error != null) {
            // Both failed — complete with null so we fall through to tier-3.
            winner.complete(null);
          }
        }

        // Surface auth errors immediately so the UI can prompt re-login.
        void checkAuthError(Object? e) {
          if (e is YtmException && e.isAuth && !e.isBotBlocked) {
            if (!winner.isCompleted) winner.completeError(e);
          }
        }

        unawaited(t1Future.then((_) {
          checkAuthError(t1Error);
          tryResolve();
        }));
        unawaited(t2Future.then((_) {
          checkAuthError(t2Error);
          tryResolve();
        }));

        // Fallback: after both finish ensure we resolve.
        unawaited(Future.wait([t1Future, t2Future]).then((_) {
          if (!winner.isCompleted) winner.complete(null);
        }));

        final winStream = await winner.future;

        if (winStream != null && winStream.url.trim().isNotEmpty) {
          final tierLabel = (t1Result?.url == winStream.url) ? 'account' : 'native';
          try {
            _tracker?.markStage(PlaybackStage.urlObtained);
            _tracker?.setTag('tierUsed', tierLabel);
          } catch (_) {}
          urlCache?.put(
            videoId,
            winStream.url,
            quality: quality,
            userAgent: winStream.userAgent,
            cookies: winStream.cookies,
          );
          // Bonus: if the loser also resolved, cache it for the SWTR window.
          final bonus = (t1Result?.url == winStream.url) ? t2Result : t1Result;
          if (bonus != null && bonus.url.trim().isNotEmpty) {
            urlCache?.put(
              videoId,
              bonus.url,
              quality: quality,
              userAgent: bonus.userAgent,
              cookies: bonus.cookies,
            );
          }
          return winStream;
        }

        // Surface any bot/device-gate signals from the race for tier-3 logic.
        for (final err in [t1Error, t2Error]) {
          if (err is YtmException) {
            // Use throw (not rethrow) since we're not inside a catch clause.
            if (err.isAuth && !err.isBotBlocked) throw err;
            if (err.isBotBlocked || err.code == 'YTM_SIGNIN_REQUIRED') {
              signInRequiredAbort = true;
              // Don't set _globalBlockUntil here — tier-3 (XDM backend) may
              // still succeed. The block is set at the final throw point if
              // ALL tiers fail.
            }
          }
        }
        debugPrint('[YTM_SERVICE] Parallel race (account+native) produced no stream for $videoId — falling to tier-3');
      } else {
        // ── Guest path: native Kotlin only (no account tier) ──────────────────
        try {
          try {
            _tracker?.markStage(PlaybackStage.clientRequestSent);
            _tracker?.markStage(PlaybackStage.poTokenNeeded);
          } catch (_) {}
          final raw = await _guard(
            () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
              'videoId': videoId,
              'quality': quality,
            }),
            timeout: _resolveFirstAttemptTimeout,
            maxRetries: 0,
          );
          final stream = raw == null ? null : YtmStream.fromChannel(raw);
          if (stream != null && stream.url.trim().isNotEmpty) {
            try {
              _tracker?.markStage(PlaybackStage.urlObtained);
              _tracker?.setTag('tierUsed', 'native_guest');
            } catch (_) {}
            urlCache?.put(
              videoId,
              stream.url,
              quality: quality,
              userAgent: stream.userAgent,
              cookies: stream.cookies,
            );
            return stream;
          }
        } catch (e) {
          debugPrint('[YTM_SERVICE] Native stream resolution failed: $e');
          if (e is YtmException) {
            lastNativeException = e;
            final isDeviceGate = e.code == 'YTM_SIGNIN_REQUIRED' ||
                e.isBotBlocked ||
                e.isAuth;
            if (isDeviceGate) {
              signInRequiredAbort = true;
              // Don't set _globalBlockUntil here — tier-3 (XDM backend) may
              // still succeed. The block is set at the final throw point if
              // ALL tiers fail.
              if (e.isAuth && !e.isBotBlocked) rethrow;
            } else if (e.code == 'YTM_TIMEOUT') {
              debugPrint('[YTM_SERVICE] Native timeout — not a device gate, will not set global block');
            }
          }
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
            final acct =
                getIt.isRegistered<YtmAccountService>()
                    ? getIt<YtmAccountService>()
                    : null;
            final remoteStream = await xdm.resolveStream(
              videoId,
              quality: quality,
              cookies: acct?.cookies,
            );
            if (remoteStream != null) {
              try {
                _tracker?.markStage(PlaybackStage.urlObtained);
                _tracker?.setTag('tierUsed', 'xdm');
              } catch (_) {}
              urlCache?.put(
                videoId,
                remoteStream.url,
                quality: quality,
                userAgent: remoteStream.userAgent,
                cookies: remoteStream.cookies,
              );
              return remoteStream;
            }
          }
        }
      } catch (e) {
        debugPrint(
          '[YTM_SERVICE] Remote yt-dlp backend stream resolution fallback: $e',
        );
        if (e is YtmException && (e.isBotBlocked || e.code == 'RATE_LIMITED')) {
          rethrow;
        }
      }

      if (signInRequiredAbort) {
        final isLoggedIn = getIt.isRegistered<YtmAccountService>() &&
            getIt<YtmAccountService>().isLoggedIn;
        if (!isLoggedIn) {
          // Guest: device/IP-level gate — write a global block so every
          // subsequent play fast-fails without re-running the dead ladder.
          _globalBlockUntil = DateTime.now().add(_signinAbortTtl);
          debugPrint('[YTM_SERVICE] Global block set for '
              '${_signinAbortTtl.inSeconds}s '
              '(LOGIN_REQUIRED / BotChallenge on all clients, guest mode)');
          throw const YtmException(
            'YTM_SIGNIN_REQUIRED',
            'Sign in to YouTube Music - Google is blocking playback from this '
            'device or network',
          );
        }
        // Logged-in user: do NOT set _globalBlockUntil — the authenticated
        // WEB_REMIX path may work on the next attempt after poToken refresh
        // or cookie propagation. Surface as auth failure so UI prompts
        // re-login instead of generic YTM_FAILED.
        debugPrint('[YTM_SERVICE] All tiers failed for logged-in user — '
            'surfacing auth failure without setting global block.');
        throw const YtmException(
          'YTM_AUTH',
          'YouTube session expired - please sign in again',
        );
      }
      if (lastNativeException != null) {
        throw lastNativeException;
      }
      throw const YtmException(
        'YTM_FAILED',
        'No stream returned from any engine',
      );
    });
  }

  Future<T?> _guard<T>(
    Future<T?> Function() call, {
    required Duration timeout,
    int maxRetries = 2,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final adaptiveTimeout = timeout + Duration(seconds: attempt * 5);
        return await call().timeout(adaptiveTimeout);
      } on TimeoutException {
        if (attempt == maxRetries) {
          throw const YtmException('YTM_TIMEOUT', 'Request timed out');
        }
      } on MissingPluginException {
        throw const YtmException('YTM_UNSUPPORTED');
      } on SocketException catch (e) {
        // Offline/DNS failure — retry with backoff like YTM_TIMEOUT, surface offline
        if (attempt == maxRetries) {
          ErrorLogger.log('YTM network failure (offline): $e', category: 'YTM');
          throw YtmException('YTM_OFFLINE', 'No internet: ${e.message}');
        }
        await Future<void>.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      } on PlatformException catch (e) {
        final isFatalCode =
            e.code == 'YTM_DISABLED' ||
            e.code == 'YTM_UNSUPPORTED' ||
            e.code == 'YTM_BOT_BLOCKED' ||
            e.code == 'YTM_RECAPTCHA' ||
            e.code == 'LOGIN_REQUIRED' ||
            e.code == 'YTM_AUTH' ||
            e.code == 'YTM_SIGNIN_REQUIRED';

        if (attempt == maxRetries || isFatalCode) {
          ErrorLogger.log(
            'YTM call failed: ${e.code} ${e.message}',
            category: 'YTM',
          );
          if (e.code == 'LOGIN_REQUIRED' || e.code == 'YTM_AUTH') {
            // Suppress false-positive auth-expiry notifications during the
            // 30s post-login grace window — the native ladder may return
            // LOGIN_REQUIRED because cookies haven't propagated to Kotlin yet.
            final inGrace = getIt.isRegistered<YtmAccountService>() &&
                getIt<YtmAccountService>().inPostLoginGrace;
            if (!inGrace) {
              notifyAuthExpired();
            } else {
              debugPrint(
                '[YTM_SERVICE] _guard: LOGIN_REQUIRED suppressed '
                '(within post-login grace window)',
              );
            }
          }
          throw YtmException(e.code, e.message);
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw const YtmException('YTM_FAILED', 'Max retries exhausted');
  }
}

