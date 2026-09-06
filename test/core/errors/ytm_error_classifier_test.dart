// test/core/errors/ytm_error_classifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_service.dart';

void main() {
  group('YtmErrorClassifier Tests', () {
    test('classifies network and timeout errors correctly', () {
      const netEx = YtmException('YTM_NETWORK', 'Socket closed');
      final info = YtmErrorClassifier.classify(netEx);

      expect(info.message, contains('No connection'));
      expect(info.recoveryAction, equals(YtmRecoveryAction.retryWithBackoff));
    });

    test('classifies bot blocked errors correctly', () {
      const botEx = YtmException(
          'YTM_BOT_BLOCKED', 'Sign in to confirm that you are not a bot');
      final info = YtmErrorClassifier.classify(botEx);

      expect(info.signal, equals(YtmBlockSignal.botChallenge));
      expect(info.recoveryAction,
          equals(YtmRecoveryAction.invalidatePoTokenAndRetry));
    });

    test('classifies recaptcha challenges correctly', () {
      const recaptchaEx = YtmException('YTM_RECAPTCHA', 'Captcha required');
      final info = YtmErrorClassifier.classify(recaptchaEx);

      expect(info.signal, equals(YtmBlockSignal.botChallenge));
      expect(info.recoveryAction,
          equals(YtmRecoveryAction.invalidatePoTokenAndRetry));
    });

    test('classifies session expired / auth errors correctly', () {
      const authEx = YtmException('YTM_AUTH', 'Session expired');
      final info = YtmErrorClassifier.classify(authEx);

      expect(info.signal, equals(YtmBlockSignal.signInRequired));
      expect(info.recoveryAction, equals(YtmRecoveryAction.showLoginPrompt));
    });

    test('classifies unavailable tracks correctly', () {
      const unavailEx =
          YtmException('YTM_UNAVAILABLE', 'Video is private or deleted');
      final info = YtmErrorClassifier.classify(unavailEx);

      expect(info.signal, equals(YtmBlockSignal.videoGone));
      expect(info.recoveryAction, equals(YtmRecoveryAction.skipToNextTrack));
    });

    test('classifies disabled build errors correctly', () {
      const disabledEx = YtmException('YTM_DISABLED');
      final info = YtmErrorClassifier.classify(disabledEx);

      expect(info.message, contains('not available in this build'));
      expect(info.recoveryAction, equals(YtmRecoveryAction.none));
    });

    test('classifies 403 Forbidden stream errors correctly', () {
      final forbiddenErr = Exception('HTTP Status Error: 403');
      final info = YtmErrorClassifier.classify(forbiddenErr);

      expect(info.signal, equals(YtmBlockSignal.ipBlocked));
      expect(info.recoveryAction, equals(YtmRecoveryAction.rotatePath));
    });

    test('classifies 407 Proxy Authentication errors correctly', () {
      final proxyErr =
          Exception('curl: (7) CONNECT tunnel failed, response 407');
      final info = YtmErrorClassifier.classify(proxyErr);

      expect(info.signal, equals(YtmBlockSignal.ipBlocked));
      expect(info.recoveryAction, equals(YtmRecoveryAction.rotatePath));

      const proxyEx = YtmException('YTM_PROXY_AUTH');
      final infoCode = YtmErrorClassifier.classify(proxyEx);
      expect(
          infoCode.recoveryAction, equals(YtmRecoveryAction.rotatePath));
    });
  });

  // The playback path and the download path both have to answer "resolve a new
  // URL, or retry this one?", and they need opposite remedies: a dropped
  // connection treated as a burned URL throws away a working URL, deletes the
  // bytes already on disk and pays for a fresh multi-client resolve, while a
  // burned URL treated as a blip retries a dead URL until the attempts run out.
  group('isUrlBurned', () {
    test('is true for the statuses that spend a URL', () {
      expect(YtmErrorClassifier.isUrlBurned(Exception('HTTP Status Error: 403')),
          isTrue);
      expect(YtmErrorClassifier.isUrlBurned(Exception('HTTP 404 on resume')),
          isTrue);
      expect(
          YtmErrorClassifier.isUrlBurned(
              const YtmException('YTM_429', 'HTTP 429 Retry-After: 30')),
          isTrue);
      expect(YtmErrorClassifier.isUrlBurned(Exception('HTTP 410 Gone')), isTrue);
      expect(
          YtmErrorClassifier.isUrlBurned(
              Exception('response code 416 Range Not Satisfiable')),
          isTrue);
    });

    test('is false for a 5xx, which is YouTube\'s own hiccup', () {
      expect(YtmErrorClassifier.isUrlBurned(Exception('HTTP 500')), isFalse);
      expect(YtmErrorClassifier.isUrlBurned(Exception('HTTP 503')), isFalse);
    });

    test('is false for transport failures', () {
      expect(
          YtmErrorClassifier.isUrlBurned(
              Exception('SocketException: Connection reset by peer')),
          isFalse);
      expect(
          YtmErrorClassifier.isUrlBurned(
              Exception('TimeoutException after 0:00:45.000000')),
          isFalse);
      expect(
          YtmErrorClassifier.isUrlBurned(
              const YtmException('YTM_NETWORK', 'Failed host lookup')),
          isFalse);
    });

    test('is not fooled by digits that are not a status', () {
      // A byte count, a bitrate or an itag in the message used to be read as an
      // HTTP verdict by a bare `contains('403')`.
      expect(
          YtmErrorClassifier.isUrlBurned(
              Exception('Connection closed before full body clen=4030099 itag=251')),
          isFalse);
      expect(
          YtmErrorClassifier.isUrlBurned(
              const DownloadFailureLike('Incomplete download: 100/200 bytes')),
          isFalse);
    });

    test('is true for a bot interstitial and a rate-limit phrase', () {
      expect(
          YtmErrorClassifier.isUrlBurned(Exception(
              'Sign in to confirm you’re not a bot')),
          isTrue);
      expect(
          YtmErrorClassifier.isUrlBurned(Exception('Too many requests')),
          isTrue);
    });
  });
}

/// Stands in for `DownloadFailure`, which lives behind an fpdart import the
/// classifier does not need: what matters here is a plain object whose
/// `toString()` carries byte counts.
class DownloadFailureLike {
  final String message;
  const DownloadFailureLike(this.message);

  @override
  String toString() => 'DownloadFailure: $message';
}
