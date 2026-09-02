// test/core/errors/ytm_error_classifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/data/services/ytm_service.dart';

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

    test('adversarial non-collision tests: author and country names do not trigger spurious blocks', () {
      // 1. Metadata containing "author" must not classify as signInRequired
      final parseErrWithAuthor = Exception('JSON parse error at {"author": "The Midnight"}');
      final info1 = YtmErrorClassifier.classify(parseErrWithAuthor);
      expect(info1.signal, isNot(equals(YtmBlockSignal.signInRequired)));
      expect(info1.recoveryAction, isNot(equals(YtmRecoveryAction.showLoginPrompt)));

      // 2. Track name containing "Georgia" or "Country Road" must not classify as geoBlocked
      final errWithGeorgia = Exception('Stream decode failed for "Midnight Train to Georgia"');
      final info2 = YtmErrorClassifier.classify(errWithGeorgia);
      expect(info2.signal, isNot(equals(YtmBlockSignal.geoBlocked)));
      expect(info2.recoveryAction, isNot(equals(YtmRecoveryAction.skipToNextTrack)));

      final errWithCountry = Exception('Failed rendering tile for Country Roads genre');
      final info3 = YtmErrorClassifier.classify(errWithCountry);
      expect(info3.signal, isNot(equals(YtmBlockSignal.geoBlocked)));
    });
  });
}
