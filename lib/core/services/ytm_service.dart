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
import '../utils/ytm_locale.dart';
import 'ytm_account_service.dart';
import 'ytm_browse_service.dart';
import 'ytm_client_version_resolver.dart';
import 'ytm_url_cache.dart';
import '../../data/audio/hedged_stream_resolver.dart';
import '../../domain/models/ytm_track.dart';
import '../telemetry/playback_latency_tracker.dart';
import '../utils/error_logger.dart';
import '../utils/l10n_holder.dart';
import '../utils/ytm_rate_limiter.dart';

import '../errors/ytm_error_classifier.dart';

export '../errors/ytm_error_classifier.dart' show YtmException;
import 'ytm_circuit_breaker.dart';
import 'ytm_media_helpers.dart';
part 'ytm_service_internals.dart';
part 'ytm_service_alternates.dart';
part 'ytm_service_dart_resolve.dart';

@lazySingleton
class YtmService {
  static const String channelName = PulsrChannels.ytm;
  static const Duration _defaultSearchTimeout = Duration(seconds: 25);
  static const Duration _defaultResolveTimeout = Duration(seconds: 15);

  /// How long the native multi-client chain runs alone before the Dart account
  /// tier is started alongside it as a hedge.
  ///
  /// The direction is deliberate: every web client now answers with ciphered
  /// formats, so only the native side can turn them into a stream. Giving the
  /// Dart tier the head start meant every tap paid its warm-up mints and a
  /// `/player` request that then handed off, while the extractor waited —
  /// seconds of dead time on a signed-in cold tap. A warm native resolve is
  /// typically 300-800 ms, so this window usually settles the race before the
  /// account hop even starts. Past it the account tier still covers the case
  /// where the native chain is blocked or slow.
  static const Duration _tier1HedgeDelay = Duration(milliseconds: 700);

  final MethodChannel _channel = const MethodChannel(channelName);
  final StreamController<void> _authExpiredController =
      StreamController<void>.broadcast();
  bool _disposed = false;

  /// Shared persistent HTTP client for Dart-side Innertube calls (search
  /// fallback). Keep-alive reuses TCP+TLS across requests; the previous
  /// top-level `http.post` paid a fresh handshake per call (~100-400ms).
  /// (Field, not a ctor param, so injectable codegen stays untouched.)
  http.Client _httpClient = http.Client();

  /// Swaps in a scripted client so tests can drive the InnerTube search
  /// fallback's timing without touching the network.
  @visibleForTesting
  set debugHttpClient(http.Client client) => _httpClient = client;

  bool? _available;

  /// Bot-challenge cooldown: when YouTube flags this IP, every native resolve
  /// burns a full multi-client chain and fails identically. While cooling
  /// down, [resolveStream] skips the native tiers and goes straight to the
  /// remote backend instead of piling up doomed chains (which also starves
  /// the native thread pool into cascading YTM_TIMEOUTs).
  static const _botCooldown = Duration(seconds: 45);

  /// Extended cooldown for IP-level blocks (every client fails instantly).
  static const _ipBlockCooldown = Duration(seconds: 180);

  /// Ceiling for the escalating bot-challenge window: 45s → 90s → 180s.
  /// Retrying a persistent gate every 45s in lockstep is what keeps it
  /// refusing; a longer window also stops burning full native chains.
  static const _maxBotCooldown = Duration(minutes: 3);

  /// Ceiling for the escalating IP-block window: 180s → 360s → 720s.
  static const _maxIpBlockCooldown = Duration(minutes: 12);

  /// A challenge-free gap longer than this resets the escalation streak, so a
  /// single bad minute hours ago does not inflate today's cooldowns.
  static const _challengeStreakDecay = Duration(minutes: 10);

  /// Consecutive challenge episodes (each a window started while no other was
  /// active). Multiplies the next window; reset by any successful resolve, a
  /// network-path change, or [_challengeStreakDecay] of clean time.
  int _challengeStreak = 0;
  DateTime _lastChallengeAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  YtmException? _lastBotChallenge;

  /// Injectable clock for the cooldown ledger; tests advance it instead of
  /// sleeping out real 45s/180s windows.
  DateTime Function() _now = DateTime.now;

  @visibleForTesting
  set debugClock(DateTime Function() clock) => _now = clock;

  /// Remaining bot/IP cooldown, or null when none is active.
  @visibleForTesting
  Duration? get debugBotCooldownRemaining {
    final remaining = _botChallengeUntil.difference(_now());
    return remaining.isNegative ? null : remaining;
  }

  /// Test-only: exercise the success path (cooldown + streak reset).
  @visibleForTesting
  void debugNoteResolveSuccess({String? videoId}) =>
      _noteResolveSuccess(videoId: videoId);

  /// Pushes bot-cooldown transitions to the UI without a polling timer: the
  /// value flips to true when a cooldown starts and back to false exactly when
  /// the window elapses (or a resolve proves the IP is unblocked). The search
  /// screen listens to this instead of a 5-second [Timer.periodic] + setState.
  final ValueNotifier<bool> botCooldownNotifier = ValueNotifier<bool>(false);
  Timer? _botCooldownTimer;

  void _syncBotCooldownNotifier() {
    if (_disposed) return;
    _botCooldownTimer?.cancel();
    _botCooldownTimer = null;
    final remaining = _botChallengeUntil.difference(_now());
    if (remaining <= Duration.zero) {
      if (botCooldownNotifier.value) botCooldownNotifier.value = false;
      return;
    }
    if (!botCooldownNotifier.value) botCooldownNotifier.value = true;
    _botCooldownTimer = Timer(remaining, () {
      if (_now().isBefore(_botChallengeUntil)) {
        _syncBotCooldownNotifier();
      } else if (botCooldownNotifier.value) {
        botCooldownNotifier.value = false;
      }
    });
  }

  // FIX-C01: Per-video failure tracking (trip only if 3 failures for that videoId within 60s)
  final Map<String, List<DateTime>> _videoFailures = {};
  final Map<String, DateTime> _videoCooldownUntil = {};

  /// Per-video resolved loudness cache (dB) for stream loudness normalization.
  final Map<String, double> _loudnessByVideoId = {};

  /// Returns the resolved loudness offset in dB for the given [videoId], if known.
  double? getLoudnessDb(String videoId) => _loudnessByVideoId[videoId];

  /// Records the resolved loudness offset in dB for the given [videoId].
  void recordLoudness(String videoId, double? loudnessDb) {
    if (loudnessDb != null) _capMap(_loudnessByVideoId, videoId, loudnessDb);
  }

  /// Caps the per-video failure/cooldown maps so a long session with many
  /// distinct failing videoIds can't grow them without bound. Entries with no
  /// failure in the last 60s (or an already-expired cooldown) are evicted once
  /// the map crosses the cap.
  static const int _maxVideoFailureKeys = 256;
  void _pruneVideoFailureMaps(DateTime now) {
    if (_videoFailures.length > _maxVideoFailureKeys) {
      _videoFailures.removeWhere((_, times) =>
          times.isEmpty || now.difference(times.last).inSeconds > 60);
    }
    if (_videoCooldownUntil.length > _maxVideoFailureKeys) {
      _videoCooldownUntil.removeWhere((_, until) => !now.isBefore(until));
    }
  }

  /// Per-signal breaker + metrics. Existing bot/video cooldowns stay as the
  /// fast path; the breaker adds bounded per-signal windows and observability.
  final YtmCircuitBreaker breaker = YtmCircuitBreaker();

  /// Diagnostics snapshot for logs/settings UI.
  Map<String, dynamic> breakerMetrics() => breaker.metrics();

  bool isVideoCoolingDown(String videoId) {
    final until = _videoCooldownUntil[videoId];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
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
      final now = _now();
      _pruneVideoFailureMaps(now);
      final failures = _videoFailures.putIfAbsent(videoId, () => []);
      failures.removeWhere((t) => now.difference(t).inSeconds > 60);
      failures.add(now);
      if (failures.length >= 3) {
        _videoCooldownUntil[videoId] = now.add(_videoFailureCooldown);
      }
    }
  }

  /// Notes a post-resolve playback failure (a stream URL that 403s mid-track)
  /// into the same ledger resolve failures feed, so a bot/IP verdict surfaced
  /// during playback engages the cooldown for the queue's next resolves.
  ///
  /// Only egress verdicts qualify: a burned URL or a dropped connection is
  /// remedied by re-resolving, and must not silence the native tiers.
  /// [videoId] may be empty for a pseudo-song with no remote id, in which case
  /// only the global cooldown is affected.
  void notePlaybackFailure(String videoId, Object error) {
    final info = YtmErrorClassifier.classify(error);
    final signal = info.signal;
    if (signal == null ||
        (signal != YtmBlockSignal.botChallenge &&
            signal != YtmBlockSignal.ipBlocked &&
            signal != YtmBlockSignal.poTokenInvalid &&
            signal != YtmBlockSignal.rateLimited)) {
      return;
    }
    recordFailure(
      videoId,
      // Always rebuild from the classified signal: a source-born
      // `YtmException` may carry a mangled code, and the classifier's verdict
      // is the authoritative one.
      YtmException(
        signal.wireCode,
        error is YtmException ? (error.details ?? info.message) : info.message,
        error is YtmException ? error.traceId : null,
      ),
    );
  }

  bool get isBotCoolingDown => _now().isBefore(_botChallengeUntil);

  /// Window for a *new* challenge episode: the signal's base cooldown doubled
  /// per consecutive episode, capped, with a clean-gap reset for the streak.
  /// Episodes (not raw events) are counted so the account and native tiers
  /// noting the same challenge — and retry loops — cannot inflate the streak.
  Duration _nextChallengeWindow(YtmException e, DateTime now) {
    // Decay is measured from the end of the previous episode, when one existed:
    // time spent inside a block is not "clean time", and with the IP ceiling
    // (12m) longer than the decay (10m), measuring from the challenge start
    // would reset the streak before every follow-up IP episode.
    final cleanSince = _botChallengeUntil.isAfter(_lastChallengeAt)
        ? _botChallengeUntil
        : _lastChallengeAt;
    if (now.difference(cleanSince) > _challengeStreakDecay) {
      _challengeStreak = 0;
    }
    _lastChallengeAt = now;
    _challengeStreak = (_challengeStreak + 1).clamp(1, 5);
    final isIp = e.isIpBlocked;
    final base = isIp ? _ipBlockCooldown : _botCooldown;
    final cap = isIp ? _maxIpBlockCooldown : _maxBotCooldown;
    final scaled = base * (1 << (_challengeStreak - 1));
    return scaled > cap ? cap : scaled;
  }

  void _noteBotChallenge(YtmException e, {String? videoId}) {
    if (e.isBotBlocked || e.isIpBlocked || e.isThrottled) {
      _lastBotChallenge = e;
    }
    final signal = e.signal;
    if (signal != null) breaker.recordFailure(signal);
    final now = _now();
    final blocked = e.isBotBlocked || e.isIpBlocked || e.isThrottled;

    if (blocked) {
      // While a window is active it is never extended: one resolve attempt can
      // note a challenge from both racing tiers, and a retry loop would
      // otherwise hold the window open forever instead of outlasting it.
      if (!_botChallengeUntil.isAfter(now)) {
        _botChallengeUntil = now.add(_nextChallengeWindow(e, now));
      }
      if (videoId != null && videoId.isNotEmpty) {
        _videoCooldownUntil[videoId] = _botChallengeUntil;
      }
    }

    // FIX-C01: per-video failure ledger (3 failures within 60s) for the
    // non-block failures; a repeated single-video failure gets skipped too.
    if (videoId != null && videoId.isNotEmpty) {
      _pruneVideoFailureMaps(now);
      final failures = _videoFailures.putIfAbsent(videoId, () => []);
      failures.removeWhere((t) => now.difference(t).inSeconds > 60);
      failures.add(now);
      if (!blocked && failures.length >= 3) {
        _videoCooldownUntil[videoId] = now.add(_videoFailureCooldown);
      }
    }
    _syncBotCooldownNotifier();
  }

  /// Any successful resolve proves the IP is not blocked, so an active cooldown
  /// must end: a fixed window kept skipping the native tiers (the only ones
  /// that produce high-bitrate streams) for minutes after YouTube let us back
  /// in, and every retry inside the window rethrew the stale challenge.
  void _noteResolveSuccess({String? videoId}) {
    breaker.recordSuccess();
    // A success proves the egress is clean again, so escalation restarts from
    // the base window rather than punishing the next unrelated blip.
    _challengeStreak = 0;
    _lastChallengeAt = DateTime.fromMillisecondsSinceEpoch(0);
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
    breaker.reset();
    if (videoId != null) {
      _videoFailures.remove(videoId);
      _videoCooldownUntil.remove(videoId);
    } else {
      _videoFailures.clear();
      _videoCooldownUntil.clear();
    }
    _challengeStreak = 0;
    _lastChallengeAt = DateTime.fromMillisecondsSinceEpoch(0);
    _botChallengeUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastBotChallenge = null;
    _syncBotCooldownNotifier();
  }

  Stream<void> get onAuthExpired => _authExpiredController.stream;

  void notifyAuthExpired() {
    if (_disposed) return;
    _authExpiredController.add(null);
  }

  @disposeMethod
  void dispose() {
    _disposed = true;
    _botCooldownTimer?.cancel();
    _botCooldownTimer = null;
    botCooldownNotifier.dispose();
    _authExpiredController.close();
    try {
      _httpClient.close();
    } catch (e, st) {
      ErrorLogger.log('Failed to close YTM HTTP client during dispose',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  /// Synchronizes cookies into the native extractor's encrypted session store.
  /// The login WebView owns its CookieManager jar; importing a raw header must
  /// not blindly replay domain-less credentials into browser origins.
  Future<void> syncCookies(String cookies) async {
    try {
      await _channel.invokeMethod<bool>('setCookies', {'cookies': cookies});
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
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
      final token = await _channel.invokeMethod<String>('getPlayerPoToken',
          {'videoId': videoId}).timeout(const Duration(seconds: 4));
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  /// Pre-warms BotGuard WebView and Capability Matrix.
  Future<void> preWarm() async {
    try {
      await _channel.invokeMethod<bool>('preWarm');
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  /// Pushes a JSON capability override to the native client matrix.
  ///
  /// The native side validates it, persists it, and re-applies it on the next
  /// start. This is the only way to change client versions, priorities or token
  /// requirements without shipping a release; see [refreshClientCapabilitiesFrom]
  /// for the fetch wrapper and `YTM_CAPABILITIES_URL` for the opt-in switch.
  Future<bool> updateClientCapabilities(String json) async {
    if (json.trim().isEmpty) return false;
    try {
      final applied = await _channel.invokeMethod<bool>(
          'updateClientCapabilities',
          {'json': json}).timeout(const Duration(seconds: 4));
      return applied ?? false;
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
      return false;
    }
  }

  /// Native capability-matrix load state, for diagnostics.
  Future<Map<String, dynamic>?> getClientCapabilitiesState() async {
    try {
      final state = await _channel
          .invokeMethod<Map<Object?, Object?>>('getClientCapabilitiesState')
          .timeout(const Duration(seconds: 2));
      if (state == null) return null;
      return state.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Fetches a capability override from [url] and applies it.
  ///
  /// Opt-in only: `main` calls this when the build defines `YTM_CAPABILITIES_URL`,
  /// so a default build makes no extra request and the packaged asset stays
  /// authoritative. Failures are silent by design - a missing or malformed
  /// override must never disturb startup.
  Future<bool> refreshClientCapabilitiesFrom(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      // The native parser rejects anything unreasonable, but a 64 KB cap keeps a
      // misconfigured URL from becoming a memory problem on the startup path.
      if (response.bodyBytes.length > 64 * 1024) return false;
      return await updateClientCapabilities(response.body);
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
      return false;
    }
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
  }

  /// Drops any in-flight resolve for [videoId].
  ///
  /// Deliberately does **not** touch [YtmUrlCache]: each quality has its own
  /// slot, the resolver evicts a burned URL itself, and evicting here turned
  /// every adaptive-quality step into a fresh network resolve of a URL that was
  /// still perfectly good.
  void forgetInFlightResolve(String videoId) {
    _inFlightStreamResolves.removeWhere((k, _) => k.startsWith('$videoId:'));
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
    // Futures already running cannot be cancelled, but no new caller should
    // attach to a resolve bound to the old egress.
    _inFlightStreamResolves.clear();
    YtmRateLimiter.shared.resetAfterNetworkChange();
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        getIt<YtmUrlCache>().clear();
      }
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
    try {
      if (getIt.isRegistered<YtmBrowseService>()) {
        getIt<YtmBrowseService>().clearCache();
      }
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
    try {
      await _channel
          .invokeMethod<bool>('clearNetworkCaches')
          .timeout(const Duration(seconds: 3));
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
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
  ///
  /// The two engines race instead of queueing. Native is asked first and, when
  /// it answers inside [_searchHedgeDelay], it wins outright — the fallback is
  /// never started, so the happy path still costs exactly one search. Past the
  /// hedge delay the Dart InnerTube search starts alongside it, which is what
  /// used to be a full wait on native's 25s budget before the second engine was
  /// even attempted. Whichever hands back a non-empty list first wins.
  static const Duration _searchHedgeDelay = Duration(milliseconds: 900);

  Future<List<YtmTrack>> searchWithFallback(String query,
      {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final winner = Completer<List<YtmTrack>>();
    List<YtmTrack> nativeResults = const [];
    List<YtmTrack>? fallbackResults;
    var nativeDone = false;
    var fallbackDone = false;
    var fallbackStarted = false;
    Timer? hedge;

    void decide() {
      if (winner.isCompleted) return;
      if (nativeResults.isNotEmpty) {
        winner.complete(nativeResults);
      } else if (fallbackResults != null && fallbackResults!.isNotEmpty) {
        winner.complete(fallbackResults!);
      } else if (nativeDone && fallbackDone) {
        winner.complete(const []);
      }
    }

    void startFallback() {
      if (fallbackStarted || winner.isCompleted) return;
      fallbackStarted = true;
      _searchInnertube(trimmed, limit: limit).then((results) {
        fallbackResults = results;
        fallbackDone = true;
        decide();
      }).catchError((Object e) {
        debugPrint('[YTM_SERVICE] Innertube fallback search failed: $e');
        fallbackDone = true;
        decide();
      });
    }

    hedge = Timer(_searchHedgeDelay, startFallback);

    search(trimmed, limit: limit).then((results) {
      nativeResults = results;
      nativeDone = true;
      hedge?.cancel();
      // Empty rather than thrown: promote the fallback now instead of waiting
      // out the hedge delay for a native answer that already said "nothing".
      if (results.isNotEmpty) {
        decide();
      } else {
        startFallback();
      }
    }).catchError((Object e) {
      debugPrint('[YTM_SERVICE] Native search failed, trying fallbacks: $e');
      nativeDone = true;
      hedge?.cancel();
      startFallback();
    });

    return winner.future;
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

      final localeArgs = _localeArgs();
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': clientVersion,
            'hl': localeArgs['lang'] ?? 'en',
            'gl': localeArgs['country'] ?? 'US',
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
        'x-youtube-client-name': '67',
        'x-youtube-client-version': clientVersion,
        'x-goog-authuser': '0',
        'X-Goog-Api-Key': apiKey,
      };

      if (getIt.isRegistered<YtmAccountService>()) {
        final account = getIt<YtmAccountService>();
        final visitorData = account.sessionVisitorData;
        if (visitorData != null && visitorData.isNotEmpty) {
          headers['X-Goog-Visitor-Id'] = visitorData;
        }
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

      await YtmRateLimiter.shared
          .acquirePermit(maxWait: const Duration(seconds: 15));
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

        _collectSearchTracks(json, tracks);
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
      debugPrint('[YTM_SERVICE] Innertube search HTTP ${response.statusCode}');
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
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
      if (accountService != null && !accountService.isFetchingLikedSongs) {
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

  Future<List<YtmTrack>> getRadioTracks(String videoId,
      {int limit = 25}) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return const [];

    // 1. Direct Dart InnerTube API via YtmAccountService
    try {
      final accountService = getIt.isRegistered<YtmAccountService>()
          ? getIt<YtmAccountService>()
          : null;
      if (accountService != null) {
        final tracks =
            await accountService.fetchRadioTracks(cleanId, maxTracks: limit);
        if (tracks.isNotEmpty) {
          return tracks;
        }
      }
    } catch (e) {
      debugPrint(
          '[YTM_SERVICE] fetchRadioTracks via YtmAccountService error: $e');
    }

    // 2. Fallback to getPlaylistTracks with RDAMVM$videoId
    try {
      final fallbackTracks =
          await getPlaylistTracks('RDAMVM$cleanId', limit: limit);
      return fallbackTracks.where((t) => t.videoId != cleanId).toList();
    } catch (e) {
      debugPrint('[YTM_SERVICE] getRadioTracks fallback error: $e');
      return const [];
    }
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

  /// Cache of original video IDs mapped to discovered working alternative video IDs
  /// for age-restricted / unplayable content.
  final Map<String, String> _alternateVideoIds = {};

  /// Resolves an alternative playable stream for a track when the primary
  /// [originalVideoId] is age-restricted, region-blocked, or unplayable.
  /// Resolves audio: account stream, then the native multi-client extractor.
  /// Coalesces identical non-force resolves; a hedged caller can disable
  /// [coalesce] so its second attempt is genuinely independent, and
  /// [forceRefresh] always performs a fresh resolve.
  Future<YtmStream> resolveStream(String videoId,
      {String quality = 'high',
      bool forceRefresh = false,
      bool coalesce = true,
      bool preferM4a = false,
      String? title,
      String? artist,
      Duration? duration}) {
    if (forceRefresh) {
      return _resolveStreamInner(videoId,
          quality: quality,
          forceRefresh: true,
          preferM4a: preferM4a,
          title: title,
          artist: artist,
          duration: duration);
    }
    if (!coalesce) {
      return _resolveStreamInner(videoId,
          quality: quality,
          forceRefresh: false,
          preferM4a: preferM4a,
          title: title,
          artist: artist,
          duration: duration);
    }
    final key =
        '$videoId:${YtmUrlCache.qualitySlot(quality, preferM4a: preferM4a)}';
    final existing = _inFlightStreamResolves[key];
    if (existing != null) {
      // Join the in-flight resolve; do not wrap it in a substitute search per
      // caller. The registered future already runs that search on its way out
      // (`_resolveStreamInner`), so a per-caller catchError fired the whole
      // three-query search once per waiter — twice for a prefetch + playback
      // pair — adding exactly the request volume a challenged route punishes.
      return existing
          .timeout(_defaultResolveTimeout + const Duration(seconds: 5));
    }
    final fut = _resolveStreamInner(videoId,
        quality: quality,
        forceRefresh: false,
        preferM4a: preferM4a,
        title: title,
        artist: artist,
        duration: duration);
    _inFlightStreamResolves[key] = fut;
    return fut.whenComplete(() {
      if (identical(_inFlightStreamResolves[key], fut)) {
        _inFlightStreamResolves.remove(key);
      }
    });
  }

  /// Rescues an age-gated (+18) track with the signed-in account.
  ///
  /// Runs a single authenticated `WEB` player request natively. It exists
  /// because an age gate is decided by the *account*, not by the egress or the
  /// client protocol: with no session attached every client answers
  /// LOGIN_REQUIRED / "Sign in to confirm your age" for the same video, so
  /// rotating clients can never pass one. Returns null when the gate holds
  /// (the account itself is not age-verified) or the native side is absent.
  Future<YtmStream?> resolveAgeGatedStream(String videoId,
      {String quality = 'high', bool preferM4a = false}) async {
    try {
      final raw = await _guard(
        () => _channel
            .invokeMethod<Map<Object?, Object?>>('resolveAgeGatedStream', {
          'videoId': videoId,
          'quality': quality,
          if (preferM4a) 'preferM4a': true,
        }),
        timeout: _defaultResolveTimeout,
        maxRetries: 0,
      );
      if (raw == null) return null;
      return YtmStream.fromChannel(raw);
    } catch (e) {
      debugPrint('[YTM_SERVICE] Age-gate rescue failed for $videoId: $e');
      return null;
    }
  }

  Future<YtmStream> _resolveStreamInner(String videoId,
      {String quality = 'high',
      bool forceRefresh = false,
      bool preferM4a = false,
      String? title,
      String? artist,
      Duration? duration}) async {
    if (!forceRefresh && _alternateVideoIds.containsKey(videoId)) {
      final altId = _alternateVideoIds[videoId];
      if (altId != null && altId != videoId) {
        try {
          return await _resolveStreamInner(
            altId,
            quality: quality,
            forceRefresh: false,
            preferM4a: preferM4a,
            title: title,
            artist: artist,
            duration: duration,
          );
        } catch (_) {
          _alternateVideoIds.remove(videoId);
        }
      }
    }

    // Check Task 2 in-memory URL cache first
    final urlCache =
        getIt.isRegistered<YtmUrlCache>() ? getIt<YtmUrlCache>() : null;
    final cacheQuality = YtmUrlCache.qualitySlot(quality, preferM4a: preferM4a);
    if (forceRefresh) {
      urlCache?.invalidate(videoId, quality: cacheQuality);
    } else {
      final cachedEntry = urlCache?.get(videoId, quality: cacheQuality);
      if (cachedEntry != null && !cachedEntry.isExpired()) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (e, st) {
          ErrorLogger.log('Non-critical YTM operation failed',
              error: e, stackTrace: st, category: 'YTM');
        }
        final cachedStream = cachedEntry.toStream(quality: quality);
        recordLoudness(videoId, cachedStream.loudnessDb);
        return cachedStream;
      }
    }

    // Remember the most actionable failure so the caller gets an actionable
    // error (e.g. BOT_CHALLENGE → "verification" + poToken recovery) instead
    // of a generic timeout or dead end.
    Object? firstError;

    int errorPriority(Object? err) {
      if (err is! YtmException) return 0;
      if (err.isBotBlocked) return 6;
      if (err.isIpBlocked) return 5;
      if (err.isThrottled) return 4;
      if (err.isAuth) return 3;
      if (err.isOffline || err.code == 'YTM_TIMEOUT') return 2;
      return 1;
    }

    void recordError(Object? err) {
      if (err == null) return;
      if (firstError == null ||
          errorPriority(err) > errorPriority(firstError)) {
        firstError = err;
      }
    }

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
        } catch (e, st) {
          ErrorLogger.log('Non-critical YTM operation failed',
              error: e, stackTrace: st, category: 'YTM');
        }
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
    } catch (e, st) {
      ErrorLogger.log('Non-critical YTM operation failed',
          error: e, stackTrace: st, category: 'YTM');
    }
    // Tier-1 (authenticated account InnerTube) and Tier-2 (native multi-client
    // extractor) used to run strictly one after the other, so a slow Tier-1
    // charged its whole 50 s budget before the native chain — normally the
    // faster of the two — was even started. They now race with the native chain
    // on the hot path and the Dart account tier hedging it, because every web
    // client now answers with ciphered formats that only the native side can
    // decipher: a Tier-1 head start was pure added latency (warm-up mints plus
    // a request that always handed off), not a shortcut. First stream back
    // wins; the loser's result is dropped. Because a MethodChannel call cannot
    // be cancelled once invoked, the only cost of losing the race is the single
    // extra chain the hedge already decided to spend.
    Timer? accountHedge;
    Object? nativeError;

    final accountService = getIt.isRegistered<YtmAccountService>()
        ? getIt<YtmAccountService>()
        : null;
    final accountLoggedIn = accountService != null && accountService.isLoggedIn;
    // An account-bound pass is the only one worth racing the native chain for:
    // it carries the session (cookies + account-bound poToken), which is the
    // only way past an age gate or a signed-in-only restriction. Everything
    // else is a guest, and a guest chain duplicates the native extractor.
    final accountBound = accountService != null &&
        accountService.isLoggedIn &&
        (accountService.dataSyncId?.trim().isNotEmpty ?? false);

    // 1. Direct authenticated YouTube Music InnerTube Player API if logged in
    Future<YtmStream?> runAccountTier() async {
      try {
        if (!inBotCooldown && accountService != null) {
          final account = accountService;
          if (account.isLoggedIn) {
            // Do NOT skip Tier-1 on a missing dataSyncId, and do not hand the
            // session to Tier-2 instead: resolvePlayerStream detects the
            // unbound account itself and runs a clean guest pass (no session
            // cookies). That is strictly better than Tier-2's WEB_REMIX
            // pairing session cookies with a guest poToken — the mismatch
            // YouTube answers with UNPLAYABLE "Video unavailable" /
            // LOGIN_REQUIRED. What the guest pass must not do is sweep the
            // guest clients: those requests are exactly the native chain's, and
            // only the native side can decipher what they return. So the pass
            // is restricted to the session-bearing client
            // (guestClientsEnabled: false).
            //
            // Kick a (throttled) dataSyncId bootstrap in parallel so later
            // tracks resolve with the account-bound token; the current resolve
            // is restricted to the session-bearing client, so with no session
            // yet it issues nothing and leaves the work to the native tier.
            if (!accountBound) {
              debugPrint(
                  '[YTM_SERVICE] Tier-1 running as guest pass for $videoId: '
                  'dataSyncId not yet ready; bootstrapping in background.');
              unawaited(account.ensureDataSyncId());
            }
            try {
              _tracker?.markStage(PlaybackStage.clientRequestSent);
              _tracker?.markStage(PlaybackStage.poTokenNeeded);
            } catch (e, st) {
              ErrorLogger.log('Non-critical YTM operation failed',
                  error: e, stackTrace: st, category: 'YTM');
            }
            // Guest passes are the only case that restricts the chain; an
            // account-bound pass keeps the default, full chain.
            final directStream = accountBound
                ? await account.resolvePlayerStream(videoId, quality: quality)
                : await account.resolvePlayerStream(videoId,
                    quality: quality, guestClientsEnabled: false);
            if (directStream != null) {
              try {
                _tracker?.markStage(PlaybackStage.urlObtained);
              } catch (e, st) {
                ErrorLogger.log('Non-critical YTM operation failed',
                    error: e, stackTrace: st, category: 'YTM');
              }
              // putStream, not put: the entry keeps the real container, MIME and
              // bitrate. put() alone let a later cache hit rebuild the stream by
              // guessing them from the URL, which wrote Opus bytes into a .m4a.
              urlCache?.putStream(directStream, quality: quality);
              _noteResolveSuccess(videoId: videoId);
              recordLoudness(videoId, directStream.loudnessDb);
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
          debugPrint(
              '[YTM_SERVICE] Direct account stream auth failure, falling back to guest engines: $e');
          recordError(e);
        } else {
          debugPrint(
              '[YTM_SERVICE] Direct account stream resolution fallback: $e');
          recordError(e);
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
      return null;
    }

    // 2. Native Multi-Client Extractor (NewPipe -> WEB_REMIX -> ANDROID -> IOS -> TV)
    Future<YtmStream?> runNativeTier() async {
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
        } catch (e, st) {
          ErrorLogger.log('Non-critical YTM operation failed',
              error: e, stackTrace: st, category: 'YTM');
        }
        // maxRetries: 0 — the native side already runs its own multi-client
        // hedged chain with internal retries. A Dart-level timeout retry can't
        // cancel the still-running native call, so it just stacks a *second* full
        // 9-client chain on top of the first, the thread-pool starvation this
        // class is trying to avoid. Let a timeout fall through to the Dart tier.
        final raw = await _guard(
          () => _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
            'videoId': videoId,
            'quality': quality,
            if (preferM4a) 'preferM4a': true,
          }),
          timeout: _defaultResolveTimeout,
          maxRetries: 0,
        );

        final stream = raw == null ? null : YtmStream.fromChannel(raw);
        if (stream != null) {
          try {
            _tracker?.markStage(PlaybackStage.urlObtained);
          } catch (e, st) {
            ErrorLogger.log('Non-critical YTM operation failed',
                error: e, stackTrace: st, category: 'YTM');
          }
          urlCache?.putStream(stream, quality: cacheQuality);
          _noteResolveSuccess(videoId: videoId);
          recordLoudness(videoId, stream.loudnessDb);
          return stream;
        }
      } catch (e) {
        debugPrint('[YTM_SERVICE] Native stream resolution failed: $e');
        // Same guest-fallback rule as Tier-1: a native LOGIN_REQUIRED (often
        // caused by stale synced cookies) must still try the remote backend
        // before surfacing auth to the UI.
        recordError(e);
        nativeError = e;
        // The cooldown short-circuit itself must not extend the window, or a
        // retry loop would hold it open forever (fixed window from first hit).
        if (!inBotCooldown &&
            e is YtmException &&
            (e.isBotBlocked || e.isThrottled || e.isIpBlocked)) {
          _noteBotChallenge(e, videoId: videoId);
        }
      }
      return null;
    }

    final winner = Completer<YtmStream?>();
    YtmStream? accountResult;
    YtmStream? nativeResult;
    var accountDone = false;
    var nativeDone = false;
    var nativeStarted = false;

    void settle() {
      if (winner.isCompleted) return;
      if (accountResult != null) {
        winner.complete(accountResult);
      } else if (nativeResult != null) {
        winner.complete(nativeResult);
      } else if (accountDone && nativeDone) {
        winner.complete(null);
      }
    }

    var accountStarted = false;

    void startNativeTier() {
      if (nativeStarted || winner.isCompleted) return;
      nativeStarted = true;
      runNativeTier().then((stream) {
        nativeResult = stream;
        nativeDone = true;
        settle();
      }).catchError((Object e) {
        debugPrint('[YTM_SERVICE] Native tier crashed: $e');
        nativeDone = true;
        settle();
      });
    }

    void startAccountTier() {
      accountHedge?.cancel();
      if (accountStarted || winner.isCompleted) return;
      accountStarted = true;
      runAccountTier().then((stream) {
        accountResult = stream;
        accountDone = true;
        settle();
      }).catchError((Object e) {
        debugPrint('[YTM_SERVICE] Account tier crashed: $e');
        accountDone = true;
        settle();
      });
    }

    // Logged out: Tier-1 has no session to carry and the Dart chain is a guest
    // sweep of the same clients the native extractor is about to ask — and only
    // the native side can decipher what they return. Skip it entirely and mark
    // it done so the race can still settle on the native answer.
    if (!accountLoggedIn) {
      debugPrint('[YTM_SERVICE] No account session for $videoId — going '
          'straight to the native tier');
      accountDone = true;
    }

    // The native extractor owns the hot path: it is the only engine that can
    // decipher the ciphered formats every web client returns, so it starts on
    // the next event-loop turn. The Dart account tier hedges *it* instead of
    // the other way around: giving Tier-1 the head start made every tap pay
    // its warm-up mints and a WEB_REMIX request that then handed ciphered
    // formats straight back to the native side, while the extractor was held
    // behind [_tier1HedgeDelay] — measured as seconds added to tap-to-sound.
    startNativeTier();
    if (accountLoggedIn) {
      accountHedge = Timer(_tier1HedgeDelay, startAccountTier);
    }

    final racedStream = await winner.future;
    accountHedge?.cancel();
    if (racedStream != null) return racedStream;

    // 2.5 PoToken refresh-and-retry (on-device only, no XDM backend).
    // A stale/mismatched BotGuard token fails every client identically; one
    // invalidate + mint + single native retry recovers without burning the
    // full Dart chain or imposing a bot cooldown on a non-bot failure.
    // (Read into a local first: `nativeError` is written from the native
    // tier's closure, so the type test below cannot promote it in place.)
    final nativeErr = nativeError;
    if (nativeErr is YtmException &&
        nativeErr.signal == YtmBlockSignal.poTokenInvalid &&
        breaker.shouldAllow(YtmBlockSignal.poTokenInvalid)) {
      try {
        debugPrint(
            '[YTM_SERVICE] Tier-2.5 poToken refresh-and-retry for $videoId');
        await invalidatePoToken().timeout(const Duration(seconds: 3));
        final ready =
            await ensurePoTokenReady().timeout(const Duration(seconds: 6));
        if (ready) {
          // maxRetries: 0 — this tier IS the single deliberate retry; a
          // timeout retry here would stack a second native chain (see tier 2).
          final raw = await _guard(
            () =>
                _channel.invokeMethod<Map<Object?, Object?>>('resolveStream', {
              'videoId': videoId,
              'quality': quality,
              if (preferM4a) 'preferM4a': true,
            }),
            timeout: _defaultResolveTimeout,
            maxRetries: 0,
          );
          final stream = raw == null ? null : YtmStream.fromChannel(raw);
          if (stream != null) {
            try {
              _tracker?.markStage(PlaybackStage.urlObtained);
            } catch (e, st) {
              ErrorLogger.log('Non-critical YTM operation failed',
                  error: e, stackTrace: st, category: 'YTM');
            }
            urlCache?.putStream(stream, quality: cacheQuality);
            _noteResolveSuccess(videoId: videoId);
            recordLoudness(videoId, stream.loudnessDb);
            return stream;
          }
        }
      } catch (e) {
        debugPrint('[YTM_SERVICE] Tier-2.5 retry failed: $e');
        if (e is YtmException) breaker.classifyAndRecord(e);
      }
    }

    // 2.4 Age-gate rescue (+18).
    // An age gate is not evidence that the *account* is refused: every tier
    // above may have asked as a guest (Tier-1 demotes itself to a guest pass
    // when it cannot mint an account-bound poToken, and the native chain only
    // carries the session on WEB_REMIX). When the accumulated verdict is
    // AGE_RESTRICTED while signed in, ask once more with the session attached
    // on WEB — the client YouTube runs age verification on. If that also
    // refuses, the gate really is account-level and the UI copy is right.
    final nativeAge = nativeErr;
    final tierAge = firstError;
    final YtmException? ageVerdict = nativeAge is YtmException &&
            nativeAge.isAgeRestricted
        ? nativeAge
        : (tierAge is YtmException && tierAge.isAgeRestricted ? tierAge : null);
    if (ageVerdict != null &&
        getIt.isRegistered<YtmAccountService>() &&
        getIt<YtmAccountService>().isLoggedIn) {
      debugPrint(
          '[YTM_SERVICE] $videoId is age-gated — retrying with the signed-in WEB session');
      final rescued = await resolveAgeGatedStream(videoId,
          quality: quality, preferM4a: preferM4a);
      if (rescued != null) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (e, st) {
          ErrorLogger.log('Non-critical YTM operation failed',
              error: e, stackTrace: st, category: 'YTM');
        }
        urlCache?.putStream(rescued, quality: cacheQuality);
        _noteResolveSuccess(videoId: videoId);
        recordLoudness(videoId, rescued.loudnessDb);
        return rescued;
      }
      debugPrint(
          '[YTM_SERVICE] Age gate held with the session attached for $videoId — '
          'the account itself is not age-verified; no client can pass it');
    }

    // 2.9 While an egress block is active, the pure-Dart sweep below pays three
    // 12s client timeouts for the same refusal. Surface the structured block
    // immediately so the UI can explain it and the queue can skip on instead of
    // stalling for another half minute per track.
    if (inBotCooldown) {
      final blocked = firstError;
      if (blocked is YtmException &&
          (blocked.isBotBlocked ||
              blocked.isIpBlocked ||
              blocked.isThrottled)) {
        throw blocked;
      }
      throw const YtmException('BOT_CHALLENGE',
          'YouTube is blocking this network. Try another connection or a proxy.');
    }

    // 3. Pure-Dart InnerTube Stream Resolver (Desktop / Non-Android / Native Plugin Fallback)
    try {
      debugPrint(
          '[YTM_SERVICE] Attempting Dart InnerTube stream resolution for $videoId');
      final dartStream = await _resolveStreamDart(videoId,
          quality: quality, preferM4a: preferM4a);
      if (dartStream != null) {
        try {
          _tracker?.markStage(PlaybackStage.urlObtained);
        } catch (e, st) {
          ErrorLogger.log('Non-critical YTM operation failed',
              error: e, stackTrace: st, category: 'YTM');
        }
        urlCache?.putStream(dartStream, quality: cacheQuality);
        _noteResolveSuccess(videoId: videoId);
        recordLoudness(videoId, dartStream.loudnessDb);
        return dartStream;
      }
    } catch (e) {
      debugPrint('[YTM_SERVICE] Dart InnerTube stream resolution failed: $e');
      recordError(e);
    }

    // All engines failed: if title is present and error is playability/restriction, attempt alternative track
    final err = firstError;
    if (title != null &&
        title.trim().isNotEmpty &&
        (err == null || YtmMediaHelpers.isPlayabilityOrRestrictedError(err))) {
      debugPrint(
          '[YTM_SERVICE] Direct stream resolution unplayable for "$videoId" ($title). Attempting alternative stream resolution...');
      final altStream = await resolveAlternateStream(
        title,
        artist,
        originalVideoId: videoId,
        quality: quality,
        preferM4a: preferM4a,
        expectedDuration: duration,
      );
      if (altStream != null) {
        return altStream;
      }
    }

    if (err is YtmException) throw err;
    if (err != null) throw err;
    throw const YtmException(
        'YTM_FAILED', 'No stream returned from any engine');
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
        // Back off before a retry: a tight loop hammers a struggling route.
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
        final isFatalCode = failure.isTerminalResolveFailure;

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
