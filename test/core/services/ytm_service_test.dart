// test/core/services/ytm_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmException classification properties', () {
    test('isNetwork flags timeout and network errors', () {
      expect(const YtmException('YTM_NETWORK').isNetwork, isTrue);
      expect(const YtmException('YTM_TIMEOUT').isNetwork, isTrue);
      expect(const YtmException('YTM_FAILED').isNetwork, isFalse);
    });

    test('isBotBlocked flags bot keywords and recaptcha', () {
      expect(const YtmException('YTM_BOT_BLOCKED').isBotBlocked, isTrue);
      expect(const YtmException('YTM_RECAPTCHA').isBotBlocked, isTrue);
      expect(const YtmException('YTM_FAILED', 'Sign in to confirm you are not a bot').isBotBlocked, isTrue);
      expect(const YtmException('YTM_FAILED', 'LOGIN_REQUIRED').isBotBlocked, isTrue);
      expect(const YtmException('YTM_NETWORK').isBotBlocked, isFalse);
    });

    test('isAuth flags auth codes and unauthenticated details', () {
      expect(const YtmException('YTM_AUTH').isAuth, isTrue);
      expect(const YtmException('LOGIN_REQUIRED').isAuth, isTrue);
      expect(const YtmException('YTM_FAILED', 'Unauthenticated user').isAuth, isTrue);
      expect(const YtmException('YTM_NETWORK').isAuth, isFalse);
    });

    test('isFatal correctly identifies blocking errors', () {
      expect(const YtmException('YTM_NETWORK').isFatal, isTrue);
      expect(const YtmException('YTM_BOT_BLOCKED').isFatal, isTrue);
      expect(const YtmException('YTM_DISABLED').isFatal, isTrue);
      expect(const YtmException('YTM_AUTH').isFatal, isTrue);
      expect(const YtmException('YTM_UNAVAILABLE').isFatal, isFalse);
    });
  });
}
