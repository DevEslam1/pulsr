// lib/core/errors/ytm_error_classifier.dart
import 'package:just_audio/just_audio.dart';

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

  bool get isOffline => isNetwork;

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
          !details!.toLowerCase().contains('age') &&
          !details!.toLowerCase().contains('inappropriate') &&
          (_botWord.hasMatch(details!) ||
              details!.contains('Sign in to confirm you') ||
              details!.contains('Sign in to confirm that you')));

  /// YouTube is rate-limiting this IP. Waiting helps; rotating identity does not.
  bool get isThrottled =>
      signal == YtmBlockSignal.rateLimited ||
      code == 'RATE_LIMITED' ||
      code == 'YTM_429';

  /// YouTube answered, but refused this IP / route.
  bool get isIpBlocked =>
      signal == YtmBlockSignal.ipBlocked || code == 'IP_BLOCKED';

  /// The track is age-restricted (+18). This is a property of the track, not
  /// the account: prompting for a fresh login cannot make it playable.
  bool get isAgeRestricted =>
      signal == YtmBlockSignal.ageRestricted || code == 'AGE_RESTRICTED';

  /// A cooperative cancellation (thread/coroutine interrupted), not a network
  /// verdict and not a reason to rotate identity or cool down.
  bool get isInterrupted =>
      signal == YtmBlockSignal.interrupted || code == 'INTERRUPTED';

  /// A failure that a retry of the same resolve chain cannot fix. Distinct
  /// from [isFatal]: an age-restricted or unavailable track should be skipped,
  /// not pause playback for the whole queue.
  bool get isTerminalResolveFailure =>
      isDisabled || isBotBlocked || isThrottled || isAuth || isAgeRestricted;

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
      signal == YtmBlockSignal.ageRestricted ||
      code == 'VIDEO_GONE' ||
      code == 'GEO_BLOCKED' ||
      code == 'AGE_RESTRICTED' ||
      code == 'YTM_UNAVAILABLE';

  /// The build has no extractor compiled in.
  bool get isDisabled => code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED';

  /// HTTP status code representing this error for audio proxy responses (e.g. 404/410 aborts ExoPlayer retries).
  int get httpStatusCode {
    return switch (signal) {
      YtmBlockSignal.videoGone => 410,
      YtmBlockSignal.botChallenge || YtmBlockSignal.ipBlocked => 403,
      YtmBlockSignal.ageRestricted => 403,
      YtmBlockSignal.signInRequired => 401,
      YtmBlockSignal.rateLimited => 429,
      YtmBlockSignal.geoBlocked => 451,
      YtmBlockSignal.interrupted => 499,
      _ => 404,
    };
  }

  @override
  String toString() =>
      'YtmException($code${traceId != null ? ' [trace=$traceId]' : ''}${details == null ? '' : ': $details'})';
}

/// Discrete signals corresponding to Kotlin YtmBlockSignal.
///
/// Mirrors `YtmBlockSignal.kt` one-for-one, [networkUnavailable] included: the
/// native side reports a transport failure as `YTM_NETWORK` precisely so it is
/// not confused with a 403/429 *response*, and a Dart enum without that member
/// forced `fromCode` to return null and let the code fall through ten substring
/// scans before reaching its handler.
enum YtmBlockSignal {
  rateLimited,
  ipBlocked,
  botChallenge,
  poTokenInvalid,
  clientDeprecated,
  geoBlocked,
  signInRequired,
  videoGone,
  networkUnavailable,
  signatureDecipherFailed,
  sabrEnforced,

  /// The track is age-restricted (+18). Distinct from [signInRequired] so the
  /// UI does not tell a signed-in user their session expired for a video that
  /// simply cannot be played without age verification.
  ageRestricted,

  /// A cooperative cancellation (thread/coroutine interrupted).
  interrupted;

  /// Machine code for this signal (`botChallenge` → `BOT_CHALLENGE`), the
  /// inverse of [fromCode] for codes the app constructs itself. `name`
  /// upper-cased is not it: it drops the underscore (`BOTCHALLENGE`), and a
  /// [YtmException] built from that code stops being recognised as a bot/IP
  /// verdict by its own `signal`/`isBotBlocked` getters.
  String get wireCode => switch (this) {
        YtmBlockSignal.rateLimited => 'RATE_LIMITED',
        YtmBlockSignal.ipBlocked => 'IP_BLOCKED',
        YtmBlockSignal.botChallenge => 'BOT_CHALLENGE',
        YtmBlockSignal.poTokenInvalid => 'PO_TOKEN_INVALID',
        YtmBlockSignal.clientDeprecated => 'CLIENT_DEPRECATED',
        YtmBlockSignal.geoBlocked => 'GEO_BLOCKED',
        YtmBlockSignal.signInRequired => 'SIGN_IN_REQUIRED',
        YtmBlockSignal.videoGone => 'VIDEO_GONE',
        YtmBlockSignal.networkUnavailable => 'YTM_NETWORK',
        YtmBlockSignal.signatureDecipherFailed => 'SIGNATURE_DECIPHER_FAILED',
        YtmBlockSignal.sabrEnforced => 'SABR_ENFORCED',
        YtmBlockSignal.ageRestricted => 'AGE_RESTRICTED',
        YtmBlockSignal.interrupted => 'INTERRUPTED',
      };

  static YtmBlockSignal? fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'YTM_NETWORK':
      case 'YTM_TIMEOUT':
      case 'YTM_OFFLINE':
      case 'RESOLVE_TIMEOUT':
        return YtmBlockSignal.networkUnavailable;
      case 'RATE_LIMITED':
      case 'YTM_429':
        return YtmBlockSignal.rateLimited;
      case 'IP_BLOCKED':
      case 'FORBIDDEN':
      case 'YTM_403':
        return YtmBlockSignal.ipBlocked;
      case 'BOT_CHALLENGE':
      case 'BOT_CHECK':
      case 'YTM_BOT_BLOCKED':
      case 'YTM_RECAPTCHA':
      case 'RECAPTCHA_REQUIRED':
        return YtmBlockSignal.botChallenge;
      case 'PO_TOKEN_INVALID':
      case 'YTM_PO_TOKEN_INVALID':
        return YtmBlockSignal.poTokenInvalid;
      case 'SABR_ENFORCED':
        return YtmBlockSignal.sabrEnforced;
      case 'AGE_RESTRICTED':
      case 'AGE_CHECK_REQUIRED':
      case 'AGE_VERIFICATION_REQUIRED':
        return YtmBlockSignal.ageRestricted;
      case 'INTERRUPTED':
      case 'INTERRUPTED_IO':
        return YtmBlockSignal.interrupted;
      case 'CLIENT_DEPRECATED':
      case 'YTM_400':
        return YtmBlockSignal.clientDeprecated;
      case 'GEO_BLOCKED':
      case 'YTM_GEO_BLOCKED':
        return YtmBlockSignal.geoBlocked;
      case 'SIGN_IN_REQUIRED':
      case 'LOGIN_REQUIRED':
      case 'YTM_AUTH':
        return YtmBlockSignal.signInRequired;
      case 'VIDEO_GONE':
      case 'CONTENT_GONE':
      case 'YTM_UNAVAILABLE':
      case 'YTM_404':
        return YtmBlockSignal.videoGone;
      case 'SIGNATURE_DECIPHER_FAILED':
        return YtmBlockSignal.signatureDecipherFailed;
      default:
        return null;
    }
  }
}

enum YtmRecoveryAction {
  none,
  retryWithBackoff,
  rotateIdentity,
  rotatePath,
  refreshPoTokenAndRetry,
  invalidatePoTokenAndRetry,
  showLoginPrompt,
  skipToNextTrack,
  limitedMode,
}

class YtmErrorInfo {
  final String message;
  final YtmRecoveryAction recoveryAction;
  final YtmBlockSignal? signal;
  final String? traceId;

  const YtmErrorInfo({
    required this.message,
    required this.recoveryAction,
    this.signal,
    this.traceId,
  });
}

/// Classifies YouTube Music errors into user-friendly messages and automated recovery actions.
class YtmErrorClassifier {
  /// HTTP status embedded in a machine code or an error string.
  ///
  /// The digits must sit in an HTTP-ish context (`HTTP 429`, `status: 403`,
  /// `response 407`, `YTM_404`) rather than appearing anywhere in the text.
  /// A bare `contains('400')` fired on any message that happened to carry a
  /// byte count, a bitrate or a video id and classified it as a deprecated
  /// client; `contains('404')` did the same for "unavailable" and skipped the
  /// track. The trailing lookahead keeps it off longer runs like `1400` and
  /// `500x500`.
  static final RegExp _httpStatusPattern = RegExp(
    r'(?:https?|status(?:\s*code)?|response(?:\s*code)?|code|err(?:or)?|[a-z]_)'
    r'[^0-9]{0,4}([1-5]\d{2})(?![0-9a-z])',
    caseSensitive: false,
  );

  /// A bare `bot` substring also matches "bottleneck", "sabotage" and "robots",
  /// so the word has to stand alone.
  static final RegExp _botWordPattern =
      RegExp(r'\bbots?\b', caseSensitive: false);

  static int? _httpStatusIn(String text) {
    final match = _httpStatusPattern.firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Signal a well-known HTTP status maps to, or null when the status carries
  /// no verdict of its own (2xx/3xx and 5xx, which are YouTube-side hiccups).
  ///
  /// 403 from YouTube when behind a VPN is commonly a bot/reputation block on
  /// the exit node, not a permanent IP ban — [botChallenge] with
  /// [invalidatePoTokenAndRetry] gives the correct first-attempt recovery;
  /// callers that still fail after a fresh poToken can escalate to rotatePath.
  /// 407 is a proxy authentication failure (wrong credentials or proxy
  /// misconfigured), so it maps to [ipBlocked]+rotatePath rather than being
  /// conflated with a YouTube-side 403 verdict.
  static YtmBlockSignal? _signalForHttpStatus(int? status) {
    switch (status) {
      case 429:
        return YtmBlockSignal.rateLimited;
      case 401:
        return YtmBlockSignal.signInRequired;
      case 403:
        // On VPN exits 403 is often a bot/reputation gate; try poToken first.
        return YtmBlockSignal.botChallenge;
      case 407:
        // Proxy authentication required — path/credential issue, not IP block.
        return YtmBlockSignal.ipBlocked;
      case 400:
        return YtmBlockSignal.clientDeprecated;
      case 408:
        // Request timeout — transient, retry like a network blip rather than
        // falling through to the terminal "something went wrong" branch.
        return YtmBlockSignal.networkUnavailable;
      case 404:
      case 410:
        return YtmBlockSignal.videoGone;
      case 451:
        // Unavailable for legal reasons — geo/regional block; skip the track.
        return YtmBlockSignal.geoBlocked;
      default:
        return null;
    }
  }

  /// True for a 5xx: YouTube's own fault, so retry rather than skip the track.
  /// `contains('unavailable')` used to read a 503 as a deleted video.
  static bool _isServerError(int? status) =>
      status != null && status >= 500 && status <= 599;

  /// Transport wording that means "the route failed", not "YouTube refused
  /// this identity". Kept in one place so the classifier, the free-text
  /// fallback and the URL-burn verdict cannot drift apart.
  static const List<String> _networkPhrases = [
    'socketexception',
    'sockettimeoutexception',
    'connectexception',
    'timeoutexception',
    'httpexception',
    'handshakeexception',
    'sslhandshakeexception',
    'connection closed',
    'connection reset',
    'connection refused',
    'connection aborted',
    'connection failed',
    'connection error',
    'connection timed out',
    'timed out',
    'bad connection',
    'failed host lookup',
    'unable to resolve host',
    'network is unreachable',
    'network unavailable',
    'network error',
    'no route to host',
    'broken pipe',
    'unexpected end of stream',
    'software caused connection abort',
    'econnreset',
    'econnrefused',
    'etimedout',
    'enetunreach',
    'ehostunreach',
    'eai_again',
    'ytm_network',
    'ytm_offline',
  ];

  static bool _isNetworkText(String text) => _networkPhrases.any(text.contains);

  /// +18 and mature-content wording. Some of these also contain the word
  /// "confirm" / "verify", so this must be checked before the bot phrases.
  static const List<String> _agePhrases = [
    'confirm your age',
    'confirm you are 18',
    "confirm you're 18",
    'confirm that you are 18',
    'age-restricted',
    'age restricted',
    'age verification',
    'age verification required',
    'age check required',
    'inappropriate for some users',
    'mature content',
    'adults only',
    'over 18',
    '18+',
  ];

  static bool _isAgeText(String text) => _agePhrases.any(text.contains);

  /// Explicit bot-interstitial wording. Deliberately excludes a bare `robot`
  /// (which matched track/artist names like "Robot Rock") and a bare
  /// `verification required` (which also describes age verification).
  static const List<String> _botPhrases = [
    'not a bot',
    'not a robot',
    "confirm you're not",
    "confirm you’re not",
    'confirm you are not',
    'confirm that you are not',
    'verify you are not',
    "verify you're not",
    'recaptcha',
    'botguard',
    'bot_block',
    'bot check',
    'login_required_bot_check',
    'unusual traffic',
    'automated queries',
  ];

  static bool _isBotText(String text) =>
      _botWordPattern.hasMatch(text) || _botPhrases.any(text.contains);

  /// A [PlayerException] whose message says nothing about the underlying
  /// cause. ExoPlayer reports every source failure as the literal "Source
  /// error" unless the just_audio bridge forwards the cause.
  static bool _isGenericPlayerMessage(String? message) {
    final text = message?.trim().toLowerCase() ?? '';
    return text.isEmpty ||
        text == 'source error' ||
        text == 'playback failed' ||
        text == 'unknown error' ||
        text == 'player error';
  }

  static YtmErrorInfo _networkInfo(String? traceId) => YtmErrorInfo(
        message: 'No connection. Check your network.',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        signal: YtmBlockSignal.networkUnavailable,
        traceId: traceId,
      );

  /// Statuses that mean the *URL itself* is spent, so retrying it verbatim can
  /// only fail again: the signature expired, the IP no longer matches, the
  /// quota is exhausted, or the resource is gone. A 5xx is deliberately absent
  /// — that is YouTube's own hiccup and the same URL usually works next time.
  static const Set<int> _burnedStatuses = {401, 403, 404, 407, 410, 416, 429};

  /// Whether [error] means "resolve a new URL" rather than "try that one again".
  ///
  /// The two need opposite remedies and the cost of confusing them is real: a
  /// dropped connection treated as a burned URL throws away a good URL, deletes
  /// the bytes already cached, and burns a full multi-client resolve (and,
  /// during a bot cooldown, a poToken mint) for a failure YouTube had no part
  /// in — while a burned URL treated as a blip retries the dead URL until the
  /// attempts run out.
  static bool isUrlBurned(Object error) {
    if (error is PlayerException) {
      final message = error.message?.toLowerCase() ?? '';
      // just_audio's Android bridge reports ExoPlaybackException.type: 0 is a
      // source failure, 1 renderer, 2 unexpected. Only a source failure can
      // spend the URL; a renderer error is a decoder problem.
      if (error.code == 0) {
        final status = _httpStatusIn(message);
        if (status != null) return _burnedStatuses.contains(status);
        if (_isNetworkText(message)) return false;
        // A bare "Source error" is most often an expired/failed URL. Treat it
        // as burned so the source re-resolves instead of replaying it.
        return true;
      }
      return false;
    }
    final status = _httpStatusIn(error.toString());
    if (status != null) return _burnedStatuses.contains(status);
    final signal = classify(error).signal;
    return signal != null && signal != YtmBlockSignal.networkUnavailable;
  }

  /// User-facing text for [error].
  ///
  /// A raw `PlayerException.message` is only safe when it names a concrete
  /// cause; ExoPlayer's literal "Source error" / "Playback failed" is not.
  static String displayMessage(Object error) {
    final info = classify(error);
    if (error is PlayerException) {
      final raw = error.message?.trim() ?? '';
      if (raw.isEmpty ||
          raw.toLowerCase().startsWith('source error') ||
          _isGenericPlayerMessage(raw)) {
        return info.message;
      }
      return raw;
    }
    return info.message;
  }

  static YtmErrorInfo classify(Object error, [String? traceId]) {
    if (error is YtmException) {
      return classifyCode(error.code, error.details, traceId ?? error.traceId);
    }

    if (error is PlayerException) {
      final raw = error.message?.trim().toLowerCase() ?? '';
      if (error.code == 0) {
        final status = _httpStatusIn(raw);
        if (status != null && _burnedStatuses.contains(status)) {
          // A googlevideo URL that starts 403ing mid-track is an expired link,
          // not a bot challenge: re-resolve it instead of rotating identity.
          return YtmErrorInfo(
            message: 'Stream link expired. Refreshing…',
            recoveryAction: YtmRecoveryAction.retryWithBackoff,
            traceId: traceId,
          );
        }
        if (_isNetworkText(raw)) return _networkInfo(traceId);
        if (_isAgeText(raw)) {
          return _mapSignal(YtmBlockSignal.ageRestricted, null, traceId);
        }
        if (_isBotText(raw)) {
          return _mapSignal(YtmBlockSignal.botChallenge, null, traceId);
        }
      }
      if (_isGenericPlayerMessage(error.message)) {
        // ExoPlayer reports TYPE_SOURCE as "Source error" and discards the
        // underlying 403/timeout/DNS message. Never show that literal string.
        return YtmErrorInfo(
          message: error.code == 0
              ? 'Stream failed to load. Refreshing the link…'
              : 'Playback failed. Please try again.',
          recoveryAction: YtmRecoveryAction.retryWithBackoff,
          traceId: traceId,
        );
      }
    }

    final errStr = error is PlayerException
        ? '${error.message ?? ''} ${error.toString()}'.toLowerCase()
        : error.toString().toLowerCase();

    // Phrase checks run before the HTTP status because they are the more
    // specific verdict: YouTube's bot interstitial can arrive as a 403, and
    // invalidating the poToken beats rotating the network path there.

    // 0. Age restriction / mature content (MUST run before bot challenge:
    // "sign in to confirm your age" is not a bot interstitial).
    if (_isAgeText(errStr)) {
      return _mapSignal(YtmBlockSignal.ageRestricted, null, traceId);
    }

    // 1. Bot challenges / verification
    if (_isBotText(errStr)) {
      return YtmErrorInfo(
        message: 'YouTube needs verification. Trying alternate route…',
        recoveryAction: YtmRecoveryAction.invalidatePoTokenAndRetry,
        signal: YtmBlockSignal.botChallenge,
        traceId: traceId,
      );
    }

    // 2. PoToken invalid
    if (errStr.contains('potoken') ||
        errStr.contains('po_token') ||
        errStr.contains('empty_adaptive_formats')) {
      return YtmErrorInfo(
        message: 'Refreshing security verification…',
        recoveryAction: YtmRecoveryAction.refreshPoTokenAndRetry,
        signal: YtmBlockSignal.poTokenInvalid,
        traceId: traceId,
      );
    }

    // 2.5 SABR enforced (server-based adaptive bitrate; client protocol state, not bot/geo)
    if (errStr.contains('sabr') ||
        errStr.contains('forcing sabr') ||
        errStr.contains('server-based adaptive bitrate')) {
      return _mapSignal(YtmBlockSignal.sabrEnforced, null, traceId);
    }

    // 3. Rate limited
    if (errStr.contains('too many requests') ||
        errStr.contains('rate limit') ||
        errStr.contains('rate_limit')) {
      return YtmErrorInfo(
        message: 'YouTube is busy. Cooling down…',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        signal: YtmBlockSignal.rateLimited,
        traceId: traceId,
      );
    }

    // 4. Geo blocked. Bare 'country'/'region' are gone: they match ordinary
    // words in a track or channel name that ends up inside an error message.
    if (errStr.contains('geo_blocked') ||
        errStr.contains('geo_restricted') ||
        errStr.contains('country restriction') ||
        errStr.contains('blocked in your country') ||
        errStr.contains('not available in your') ||
        errStr.contains('unavailable in your')) {
      return YtmErrorInfo(
        message: 'This track is restricted in your region.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
        signal: YtmBlockSignal.geoBlocked,
        traceId: traceId,
      );
    }

    // 5. Proxy auth: the path is broken, not the IP.
    if (errStr.contains('proxy authentication') ||
        errStr.contains('proxy_auth')) {
      return YtmErrorInfo(
        message: 'Backend proxy authentication failed.',
        recoveryAction: YtmRecoveryAction.rotatePath,
        signal: YtmBlockSignal.ipBlocked,
        traceId: traceId,
      );
    }

    // 6. Transport failure. Reported as its own signal so no caller mistakes an
    // offline blip for a block and imposes a multi-minute cooldown on it.
    if (_isNetworkText(errStr)) {
      return _networkInfo(traceId);
    }

    // 7. Sign in required (bare 'auth' intentionally NOT matched: it
    // misclassifies artist/track text such as "author" as expired sessions)
    if (errStr.contains('login_required') ||
        errStr.contains('unauthenticated') ||
        errStr.contains('unauthorized') ||
        errStr.contains('authentication required') ||
        errStr.contains('auth failed') ||
        errStr.contains('session expired') ||
        errStr.contains('sign in to access')) {
      return YtmErrorInfo(
        message: 'YouTube session expired. Tap to reconnect.',
        recoveryAction: YtmRecoveryAction.showLoginPrompt,
        signal: YtmBlockSignal.signInRequired,
        traceId: traceId,
      );
    }

    // 8. Video gone. 'unavailable' and 'removed' alone are too weak — the first
    // is also how a 503 and a geo block describe themselves, the second shows
    // up in "removed from playlist" — so the wording has to name the video.
    if (errStr.contains('video_gone') ||
        errStr.contains('content_gone') ||
        errStr.contains('video unavailable') ||
        errStr.contains('video is unavailable') ||
        errStr.contains('no longer available') ||
        errStr.contains('has been removed') ||
        errStr.contains('removed by') ||
        errStr.contains('private video') ||
        errStr.contains('or deleted') ||
        errStr.contains('not found')) {
      return YtmErrorInfo(
        message: 'This track is unavailable.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
        signal: YtmBlockSignal.videoGone,
        traceId: traceId,
      );
    }

    // 9. Structured HTTP status, as the fallback the substring scans used to be.
    final status = _httpStatusIn(errStr);
    final statusSignal = _signalForHttpStatus(status);
    if (statusSignal != null) return _mapSignal(statusSignal, null, traceId);
    if (_isServerError(status)) {
      return YtmErrorInfo(
        message: 'YouTube is having trouble. Retrying…',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        traceId: traceId,
      );
    }

    return YtmErrorInfo(
      message: 'Something went wrong with YouTube Music.',
      recoveryAction: YtmRecoveryAction.none,
      traceId: traceId,
    );
  }

  static YtmErrorInfo classifyCode(String code,
      [String? details, String? traceId]) {
    final explicitSignal = YtmBlockSignal.fromCode(code);
    if (explicitSignal != null) {
      return _mapSignal(explicitSignal, details, traceId);
    }

    final detailLower = details?.toLowerCase() ?? '';
    final codeLower = code.toLowerCase();
    final combined = '$codeLower $detailLower';

    // The status has to come out of the *code*, which is machine-generated and
    // short. Scanning the free-text message for bare digits made any message
    // carrying a byte count or a video id look like an HTTP verdict.
    final codeStatusSignal = _signalForHttpStatus(_httpStatusIn(codeLower));
    if (codeStatusSignal != null) {
      return _mapSignal(codeStatusSignal, details, traceId);
    }

    if (_isAgeText(combined)) {
      return _mapSignal(YtmBlockSignal.ageRestricted, details, traceId);
    }

    if (_isBotText(combined)) {
      return _mapSignal(YtmBlockSignal.botChallenge, details, traceId);
    }
    if (combined.contains('too many requests') ||
        combined.contains('rate_limit') ||
        combined.contains('rate limit')) {
      return _mapSignal(YtmBlockSignal.rateLimited, details, traceId);
    }
    if (combined.contains('potoken') || combined.contains('po_token')) {
      return _mapSignal(YtmBlockSignal.poTokenInvalid, details, traceId);
    }
    if (combined.contains('sabr') ||
        combined.contains('server-based adaptive bitrate')) {
      return _mapSignal(YtmBlockSignal.sabrEnforced, details, traceId);
    }
    if (combined.contains('geo_blocked') ||
        combined.contains('geo_restricted') ||
        combined.contains('country restriction') ||
        combined.contains('blocked in your country') ||
        combined.contains('not available in your') ||
        combined.contains('unavailable in your')) {
      return _mapSignal(YtmBlockSignal.geoBlocked, details, traceId);
    }
    if (combined.contains('proxy')) {
      return _mapSignal(YtmBlockSignal.ipBlocked, details, traceId);
    }
    if (_isNetworkText(combined)) {
      return _networkInfo(traceId);
    }
    if (combined.contains('login_required') ||
        combined.contains('unauthenticated') ||
        combined.contains('unauthorized') ||
        combined.contains('authentication required') ||
        combined.contains('session expired')) {
      return _mapSignal(YtmBlockSignal.signInRequired, details, traceId);
    }
    if (combined.contains('forbidden') || combined.contains('ip_blocked')) {
      return _mapSignal(YtmBlockSignal.ipBlocked, details, traceId);
    }
    if (combined.contains('client_deprecated') ||
        combined.contains('invalid argument') ||
        combined.contains('api key not valid')) {
      return _mapSignal(YtmBlockSignal.clientDeprecated, details, traceId);
    }
    if (combined.contains('video_gone') ||
        combined.contains('content_gone') ||
        combined.contains('video unavailable') ||
        combined.contains('no longer available') ||
        combined.contains('has been removed') ||
        combined.contains('private video') ||
        combined.contains('or deleted') ||
        combined.contains('not found')) {
      return _mapSignal(YtmBlockSignal.videoGone, details, traceId);
    }

    if (code == 'EXTRACTOR_ERROR') {
      return YtmErrorInfo(
        message: 'Stream extraction failed. Switching route…',
        recoveryAction: YtmRecoveryAction.rotateIdentity,
        traceId: traceId,
      );
    }

    if (code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED') {
      return YtmErrorInfo(
        message: 'YouTube Music is not available in this build.',
        recoveryAction: YtmRecoveryAction.none,
        traceId: traceId,
      );
    }

    // Last resort: a transport phrase or an HTTP status hiding in the message.
    final textInfo = _classifyFreeText(detailLower, traceId);
    if (textInfo != null) return textInfo;

    return YtmErrorInfo(
      message: 'Playback failed. Please try again.',
      recoveryAction: YtmRecoveryAction.retryWithBackoff,
      traceId: traceId,
    );
  }

  /// Signals that only a free-text message can carry, applied after every
  /// structured check has declined. Returns null when the text says nothing.
  static YtmErrorInfo? _classifyFreeText(String detailLower, String? traceId) {
    if (detailLower.isEmpty) return null;
    if (_isNetworkText(detailLower)) {
      return _networkInfo(traceId);
    }
    final status = _httpStatusIn(detailLower);
    final statusSignal = _signalForHttpStatus(status);
    if (statusSignal != null) return _mapSignal(statusSignal, null, traceId);
    if (_isServerError(status)) {
      return YtmErrorInfo(
        message: 'YouTube is having trouble. Retrying…',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        traceId: traceId,
      );
    }
    return null;
  }

  static YtmErrorInfo _mapSignal(
      YtmBlockSignal signal, String? details, String? traceId) {
    switch (signal) {
      case YtmBlockSignal.rateLimited:
        return YtmErrorInfo(
          message: 'YouTube is busy. Cooling down…',
          recoveryAction: YtmRecoveryAction.retryWithBackoff,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.ipBlocked:
        return YtmErrorInfo(
          message: 'IP restricted. Switching network path…',
          recoveryAction: YtmRecoveryAction.rotatePath,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.botChallenge:
        return YtmErrorInfo(
          message: 'YouTube verification triggered. Rotating identity…',
          recoveryAction: YtmRecoveryAction.invalidatePoTokenAndRetry,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.poTokenInvalid:
        return YtmErrorInfo(
          message: 'Refreshing proof-of-origin token…',
          recoveryAction: YtmRecoveryAction.refreshPoTokenAndRetry,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.clientDeprecated:
        return YtmErrorInfo(
          message: 'Innertube client version refreshed.',
          recoveryAction: YtmRecoveryAction.rotateIdentity,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.geoBlocked:
        return YtmErrorInfo(
          message: 'This track is restricted in your region.',
          recoveryAction: YtmRecoveryAction.skipToNextTrack,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.signInRequired:
        return YtmErrorInfo(
          message: 'YouTube session expired. Tap to reconnect.',
          recoveryAction: YtmRecoveryAction.showLoginPrompt,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.videoGone:
        return YtmErrorInfo(
          message: 'This track is unavailable.',
          recoveryAction: YtmRecoveryAction.skipToNextTrack,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.networkUnavailable:
        return _networkInfo(traceId);
      case YtmBlockSignal.signatureDecipherFailed:
        return YtmErrorInfo(
          message: 'Signature deciphering unavailable for this format.',
          recoveryAction: YtmRecoveryAction.rotateIdentity,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.sabrEnforced:
        return YtmErrorInfo(
          message: 'YouTube format restriction encountered. Rotating route…',
          recoveryAction: YtmRecoveryAction.rotateIdentity,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.ageRestricted:
        return YtmErrorInfo(
          message:
              'This track is age-restricted (+18) and cannot be played here.',
          recoveryAction: YtmRecoveryAction.skipToNextTrack,
          signal: signal,
          traceId: traceId,
        );
      case YtmBlockSignal.interrupted:
        return YtmErrorInfo(
          message: 'Playback was interrupted.',
          recoveryAction: YtmRecoveryAction.none,
          signal: signal,
          traceId: traceId,
        );
    }
  }
}
