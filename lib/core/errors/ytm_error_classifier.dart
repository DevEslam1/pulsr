// lib/core/errors/ytm_error_classifier.dart
import '../services/ytm_service.dart';

enum YtmRecoveryAction {
  none,
  retryWithBackoff,
  refreshPoTokenAndRetry,
  invalidatePoTokenAndRetry,
  showLoginPrompt,
  skipToNextTrack,
}

class YtmErrorInfo {
  final String message;
  final YtmRecoveryAction recoveryAction;

  const YtmErrorInfo({
    required this.message,
    required this.recoveryAction,
  });
}

/// Classifies YouTube Music errors into user-friendly messages and automated recovery actions.
class YtmErrorClassifier {
  static YtmErrorInfo classify(Object error) {
    if (error is YtmException) {
      return classifyCode(error.code, error.details);
    }

    final errStr = error.toString().toLowerCase();
    if (errStr.contains('socketexception') ||
        errStr.contains('timeoutexception') ||
        errStr.contains('connection refused') ||
        errStr.contains('network is unreachable')) {
      return const YtmErrorInfo(
        message: 'No connection. Check your network.',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
      );
    }

    if (errStr.contains('429') ||
        errStr.contains('too many requests') ||
        errStr.contains('bot') ||
        errStr.contains('sign in to confirm')) {
      return const YtmErrorInfo(
        message: 'YouTube is busy. Retrying…',
        recoveryAction: YtmRecoveryAction.refreshPoTokenAndRetry,
      );
    }

    if (errStr.contains('recaptcha')) {
      return const YtmErrorInfo(
        message: 'YouTube needs verification. Try again shortly.',
        recoveryAction: YtmRecoveryAction.invalidatePoTokenAndRetry,
      );
    }

    if (errStr.contains('login_required') ||
        errStr.contains('unauthenticated') ||
        errStr.contains('auth')) {
      return const YtmErrorInfo(
        message: 'YouTube session expired. Tap to reconnect.',
        recoveryAction: YtmRecoveryAction.showLoginPrompt,
      );
    }

    if (errStr.contains('404') || errStr.contains('not found') || errStr.contains('unavailable')) {
      return const YtmErrorInfo(
        message: 'This track is unavailable.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
      );
    }

    return const YtmErrorInfo(
      message: 'Something went wrong with YouTube Music.',
      recoveryAction: YtmRecoveryAction.none,
    );
  }

  static YtmErrorInfo classifyCode(String code, [String? details]) {
    final detailLower = details?.toLowerCase() ?? '';

    if (code == 'YTM_NETWORK' || code == 'YTM_TIMEOUT') {
      return const YtmErrorInfo(
        message: 'No connection. Check your network.',
        recoveryAction: YtmRecoveryAction.retryWithBackoff,
      );
    }

    if (code == 'YTM_BOT_BLOCKED' ||
        detailLower.contains('bot') ||
        detailLower.contains('429')) {
      return const YtmErrorInfo(
        message: 'YouTube is busy. Retrying…',
        recoveryAction: YtmRecoveryAction.refreshPoTokenAndRetry,
      );
    }

    if (code == 'YTM_RECAPTCHA' || detailLower.contains('recaptcha')) {
      return const YtmErrorInfo(
        message: 'YouTube needs verification. Try again shortly.',
        recoveryAction: YtmRecoveryAction.invalidatePoTokenAndRetry,
      );
    }

    if (code == 'LOGIN_REQUIRED' ||
        code == 'YTM_AUTH' ||
        detailLower.contains('login_required')) {
      return const YtmErrorInfo(
        message: 'YouTube session expired. Tap to reconnect.',
        recoveryAction: YtmRecoveryAction.showLoginPrompt,
      );
    }

    if (code == 'YTM_UNAVAILABLE' || detailLower.contains('404')) {
      return const YtmErrorInfo(
        message: 'This track is unavailable.',
        recoveryAction: YtmRecoveryAction.skipToNextTrack,
      );
    }

    if (code == 'YTM_DISABLED' || code == 'YTM_UNSUPPORTED') {
      return const YtmErrorInfo(
        message: 'YouTube Music is not available in this build.',
        recoveryAction: YtmRecoveryAction.none,
      );
    }

    return const YtmErrorInfo(
      message: 'Playback failed. Please try again.',
      recoveryAction: YtmRecoveryAction.retryWithBackoff,
    );
  }
}
