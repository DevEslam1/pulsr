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
}
