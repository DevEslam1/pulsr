// lib/core/errors/ytm_error_classifier.dart
import '../../data/services/ytm_service.dart';

/// Discrete signals corresponding to Kotlin YtmBlockSignal
enum YtmBlockSignal {
  rateLimited,
  ipBlocked,
  botChallenge,
  poTokenInvalid,
  clientDeprecated,
  geoBlocked,
  signInRequired,
  videoGone;

  static YtmBlockSignal? fromCode(String code) {
    switch (code.toUpperCase()) {
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
  static YtmErrorInfo classify(Object error, [String? traceId]) {
    if (error is YtmException) {
      return classifyCode(error.code, error.details, traceId);
    }

    final errStr = error.toString().toLowerCase();

    // 1. Bot challenges / verification — MUST run before sign-in check.
    // YouTube's bot gate surfaces as "Sign in to confirm you're not a bot"
    // with status LOGIN_REQUIRED. Classifying it as sign-in causes a logout
    // prompt loop instead of poToken rotation. See YtmException.isBotBlocked.
    if (errStr.contains('not a bot') ||
        errStr.contains('confirm you') ||
        errStr.contains('confirm you\'re not') ||
        errStr.contains('confirm youre not') ||
        errStr.contains('sign in to confirm') ||
        errStr.contains('unusual traffic') ||
        errStr.contains('recaptcha') ||
        errStr.contains('bot_block') ||
        errStr.contains('bot challenge') ||
        errStr.contains('automated queries')) {
      return YtmErrorInfo(
        message: 'YouTube needs verification. Trying alternate route…',
        recoveryAction: YtmRecoveryAction.invalidatePoTokenAndRetry,
        signal: YtmBlockSignal.botChallenge,
        traceId: traceId,
      );
    }

    // 2. Rate limited / 429
    if (errStr.contains('429') ||
        errStr.contains('too many requests') ||
        errStr.contains('rate limit')) {
      return YtmErrorInfo(
        message: 'YouTube is busy. Cooling down…',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        signal: YtmBlockSignal.rateLimited,
        traceId: traceId,
      );
    }

    // 3. PoToken invalid
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

    // 4. IP blocked / 403
    if (errStr.contains('403') ||
        errStr.contains('forbidden') ||
        errStr.contains('ip blocked') ||
        errStr.contains('http status error: 403')) {
      return YtmErrorInfo(
        message: 'Network restricted. Switching route…',
        recoveryAction: YtmRecoveryAction.rotatePath,
        signal: YtmBlockSignal.ipBlocked,
        traceId: traceId,
      );
    }

    // 5. Client deprecated / 400
    if (errStr.contains('400') ||
        errStr.contains('client_deprecated') ||
        errStr.contains('invalid argument') ||
        errStr.contains('api key not valid')) {
      return YtmErrorInfo(
        message: 'Client version outdated. Refreshing configuration…',
        recoveryAction: YtmRecoveryAction.rotateIdentity,
        signal: YtmBlockSignal.clientDeprecated,
        traceId: traceId,
      );
    }

    // 6. Geo blocked (strict boundaries to avoid matching "country" genre or "Georgia")
    if (RegExp(r'\b(geo_blocked|geoblocked|not available in your country|blocked in your region)\b').hasMatch(errStr)) {
      return YtmErrorInfo(
        message: 'This track is restricted in your region.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
        signal: YtmBlockSignal.geoBlocked,
        traceId: traceId,
      );
    }

    // 7. Proxy Auth / Network errors
    if (errStr.contains('407') || errStr.contains('proxy authentication')) {
      return YtmErrorInfo(
        message: 'Backend proxy authentication failed.',
        recoveryAction: YtmRecoveryAction.rotatePath,
        signal: YtmBlockSignal.ipBlocked,
        traceId: traceId,
      );
    }

    if (errStr.contains('socketexception') ||
        errStr.contains('timeoutexception') ||
        errStr.contains('connection refused') ||
        errStr.contains('network is unreachable')) {
      return YtmErrorInfo(
        message: 'No connection. Check your network.',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        traceId: traceId,
      );
    }

    // 8. Sign in required (strict boundaries to avoid matching "author").
    // NOTE: bot-gate phrases are handled in section 1 above and must never
    // fall through to here. AGE_RESTRICTED is unplayable even when authed,
    // so it maps to skip, not login.
    if (RegExp(r'\b(unauthenticated|sign_in_required|session_expired|authentication_required)\b').hasMatch(errStr) ||
        RegExp(r'\bytm_auth\b').hasMatch(errStr) ||
        (errStr.contains('login_required') &&
            !errStr.contains('confirm') &&
            !errStr.contains('not a bot') &&
            !errStr.contains('unusual traffic'))) {
      return YtmErrorInfo(
        message: 'YouTube session expired. Tap to reconnect.',
        recoveryAction: YtmRecoveryAction.showLoginPrompt,
        signal: YtmBlockSignal.signInRequired,
        traceId: traceId,
      );
    }

    if (errStr.contains('age_restricted') ||
        errStr.contains('age restricted')) {
      return YtmErrorInfo(
        message: 'This track is age-restricted and cannot be played.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
        signal: YtmBlockSignal.geoBlocked,
        traceId: traceId,
      );
    }

    // 9. Video gone / 404
    if (errStr.contains('404') ||
        errStr.contains('not found') ||
        errStr.contains('unavailable') ||
        errStr.contains('removed')) {
      return YtmErrorInfo(
        message: 'This track is unavailable.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
        signal: YtmBlockSignal.videoGone,
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
    // Bot-gate check FIRST: "Sign in to confirm you're not a bot" arrives
    // with code LOGIN_REQUIRED / YTM_AUTH but details contain the bot phrase.
    // It must map to botChallenge (poToken rotation), never sign-in prompt.
    final detailsLower = (details ?? '').toLowerCase();
    if (detailsLower.contains('not a bot') ||
        detailsLower.contains('sign in to confirm') ||
        detailsLower.contains('confirm you') ||
        detailsLower.contains('unusual traffic') ||
        detailsLower.contains('automated queries') ||
        detailsLower.contains('recaptcha') ||
        detailsLower.contains('bot_block')) {
      return _mapSignal(YtmBlockSignal.botChallenge, details, traceId);
    }
    final explicitSignal = YtmBlockSignal.fromCode(code);
    if (explicitSignal != null) {
      return _mapSignal(explicitSignal, details, traceId);
    }

    final codeLower = code.toLowerCase();

    if (codeLower.contains('bot') || codeLower.contains('recaptcha')) {
      return _mapSignal(YtmBlockSignal.botChallenge, details, traceId);
    }
    if (codeLower.contains('429') || codeLower.contains('rate_limit')) {
      return _mapSignal(YtmBlockSignal.rateLimited, details, traceId);
    }
    if (codeLower.contains('potoken_broken') || codeLower.contains('po_token_broken') || codeLower.contains('po_token_unavailable')) {
      return YtmErrorInfo(
        message: 'Security subsystem unavailable. Switching to alternate playback mode…',
        recoveryAction: YtmRecoveryAction.limitedMode,
        signal: YtmBlockSignal.poTokenInvalid,
        traceId: traceId,
      );
    }
    if (codeLower.contains('potoken_timeout') || codeLower.contains('po_token_timeout')) {
      return YtmErrorInfo(
        message: 'Security attestation timed out. Retrying…',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        signal: YtmBlockSignal.poTokenInvalid,
        traceId: traceId,
      );
    }
    if (codeLower.contains('potoken') || codeLower.contains('po_token')) {
      return _mapSignal(YtmBlockSignal.poTokenInvalid, details, traceId);
    }
    if (codeLower.contains('geo') || codeLower.contains('region_blocked')) {
      return _mapSignal(YtmBlockSignal.geoBlocked, details, traceId);
    }
    if (codeLower.contains('proxy') || codeLower.contains('407')) {
      return _mapSignal(YtmBlockSignal.ipBlocked, details, traceId);
    }
    if (codeLower.contains('login_required') || codeLower.contains('unauthenticated') || codeLower == 'ytm_auth') {
      return _mapSignal(YtmBlockSignal.signInRequired, details, traceId);
    }
    if (codeLower.contains('403') || codeLower.contains('forbidden')) {
      return _mapSignal(YtmBlockSignal.ipBlocked, details, traceId);
    }
    if (codeLower.contains('400') || codeLower.contains('invalid_argument')) {
      return _mapSignal(YtmBlockSignal.clientDeprecated, details, traceId);
    }
    if (codeLower.contains('404') || codeLower.contains('unavailable') || codeLower.contains('not_found')) {
      return _mapSignal(YtmBlockSignal.videoGone, details, traceId);
    }

    if (code == 'YTM_NETWORK' || code == 'YTM_TIMEOUT' || code == 'RESOLVE_TIMEOUT') {
      return YtmErrorInfo(
        message: 'No connection. Check your network.',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
        traceId: traceId,
      );
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

    return YtmErrorInfo(
      message: 'Playback failed. Please try again.',
      recoveryAction: YtmRecoveryAction.retryWithBackoff,
      traceId: traceId,
    );
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
    }
  }
}

/// Policy governing session invalidation:
/// ONLY a 401 with an explicit session-invalid signal may invalidate cookies.
/// 403-bot / 429 / 5xx must NEVER invalidate cookies.
class YtmSessionPolicy {
  static const _sessionInvalidSignals = [
    'session_expired',
    'request had invalid credentials',
    'account is not signed in',
    'authentication_required',
    'unauthenticated',
    'login_required',
  ];

  static bool shouldInvalidateSession(int status, String body) {
    if (status != 401) return false;
    final lower = body.toLowerCase();
    return _sessionInvalidSignals.any(lower.contains);
  }
}

/// Prevents infinite login prompt loops if an account is blocked or rejected.
class LoginLoopBreaker {
  static final LoginLoopBreaker shared = LoginLoopBreaker();

  int _logins = 0;
  DateTime? _last;

  bool get canAutoRelogin {
    final stale = _last == null ||
        DateTime.now().difference(_last!) > const Duration(minutes: 10);
    if (stale) _logins = 0;
    return _logins < 2;
  }

  void record() {
    _logins++;
    _last = DateTime.now();
  }

  void reset() {
    _logins = 0;
    _last = null;
  }
}
