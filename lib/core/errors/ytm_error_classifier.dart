// lib/core/errors/ytm_error_classifier.dart
import '../services/ytm_service.dart';

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
  networkUnavailable;

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
      case 'CLIENT_DEPRECATED':
      case 'YTM_400':
        return YtmBlockSignal.clientDeprecated;
      case 'GEO_BLOCKED':
      case 'YTM_GEO_BLOCKED':
        return YtmBlockSignal.geoBlocked;
      case 'SIGN_IN_REQUIRED':
      case 'AGE_RESTRICTED':
      case 'LOGIN_REQUIRED':
      case 'YTM_AUTH':
        return YtmBlockSignal.signInRequired;
      case 'VIDEO_GONE':
      case 'CONTENT_GONE':
      case 'YTM_UNAVAILABLE':
      case 'YTM_404':
        return YtmBlockSignal.videoGone;
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
  static final RegExp _botWordPattern = RegExp(r'\bbots?\b', caseSensitive: false);

  static int? _httpStatusIn(String text) {
    final match = _httpStatusPattern.firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Signal a well-known HTTP status maps to, or null when the status carries
  /// no verdict of its own (2xx/3xx and 5xx, which are YouTube-side hiccups).
  static YtmBlockSignal? _signalForHttpStatus(int? status) {
    switch (status) {
      case 429:
        return YtmBlockSignal.rateLimited;
      case 401:
        return YtmBlockSignal.signInRequired;
      case 403:
      case 407:
        return YtmBlockSignal.ipBlocked;
      case 400:
        return YtmBlockSignal.clientDeprecated;
      case 404:
      case 410:
        return YtmBlockSignal.videoGone;
      default:
        return null;
    }
  }

  /// True for a 5xx: YouTube's own fault, so retry rather than skip the track.
  /// `contains('unavailable')` used to read a 503 as a deleted video.
  static bool _isServerError(int? status) => status != null && status >= 500 && status <= 599;

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
    final status = _httpStatusIn(error.toString());
    if (status != null) return _burnedStatuses.contains(status);
    final signal = classify(error).signal;
    return signal != null && signal != YtmBlockSignal.networkUnavailable;
  }

  static YtmErrorInfo classify(Object error, [String? traceId]) {
    if (error is YtmException) {
      return classifyCode(error.code, error.details, traceId ?? error.traceId);
    }

    final errStr = error.toString().toLowerCase();

    // Phrase checks run before the HTTP status because they are the more
    // specific verdict: YouTube's bot interstitial can arrive as a 403, and
    // invalidating the poToken beats rotating the network path there.

    // 1. Bot challenges / verification
    if (errStr.contains('not a bot') ||
        errStr.contains('confirm you') ||
        errStr.contains('recaptcha') ||
        errStr.contains('bot_block') ||
        errStr.contains('botguard') ||
        errStr.contains('unusual traffic') ||
        errStr.contains('automated queries')) {
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
    if (errStr.contains('socketexception') ||
        errStr.contains('timeoutexception') ||
        errStr.contains('httpexception') ||
        errStr.contains('handshakeexception') ||
        errStr.contains('connection closed') ||
        errStr.contains('connection reset') ||
        errStr.contains('connection refused') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('network is unreachable') ||
        errStr.contains('software caused connection abort')) {
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

  static YtmErrorInfo classifyCode(String code, [String? details, String? traceId]) {
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

    if (_botWordPattern.hasMatch(combined) ||
        combined.contains('recaptcha') ||
        combined.contains('botguard') ||
        combined.contains('unusual traffic')) {
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
    if (detailLower.contains('socketexception') ||
        detailLower.contains('timeoutexception') ||
        detailLower.contains('handshakeexception') ||
        detailLower.contains('connection closed') ||
        detailLower.contains('connection reset') ||
        detailLower.contains('connection refused') ||
        detailLower.contains('failed host lookup') ||
        detailLower.contains('network is unreachable')) {
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

  static YtmErrorInfo _mapSignal(YtmBlockSignal signal, String? details, String? traceId) {
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
    }
  }
}
