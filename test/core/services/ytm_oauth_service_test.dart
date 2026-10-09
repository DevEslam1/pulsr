// test/core/services/ytm_oauth_service_test.dart
//
// Reachable-branch coverage for the Google device-authorization service. The
// class has no client-injection seam (its http.Client is a private final
// field), so the network round-trips (requestDeviceCode, pollForToken's token
// exchange, refresh, revoke) are exercised only through their pre-network
// guards; the transport-dependent branches are documented as unreachable from
// a unit test. Secure-storage state is seeded through the plugin's own mock.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_oauth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accessKey = 'ytm_oauth_access_token';
  const expiryKey = 'ytm_oauth_expiry_epoch';

  group('value objects', () {
    test('OAuthDeviceCode.isExpired flips on the requested-at deadline', () {
      final fresh = OAuthDeviceCode(
        deviceCode: 'd',
        userCode: 'u',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 5,
        expiresInSeconds: 1800,
        requestedAt: DateTime.now(),
      );
      expect(fresh.isExpired, isFalse);

      final stale = OAuthDeviceCode(
        deviceCode: 'd',
        userCode: 'u',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 5,
        expiresInSeconds: 1,
        requestedAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      expect(stale.isExpired, isTrue);
    });

    test('OAuthException.toString includes the description when present', () {
      expect(const OAuthException('access_denied').toString(),
          'OAuthException(access_denied)');
      expect(const OAuthException('access_denied', 'user said no').toString(),
          'OAuthException(access_denied: user said no)');
    });
  });

  // This test must run before the singleton has latched its token state; it is
  // declared first so it wins the one-shot init().
  group('session lifecycle', () {
    test('init loads an expired persisted session and ensureFresh clears it',
        () async {
      final pastEpoch = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch
          .toString();
      FlutterSecureStorage.setMockInitialValues({
        accessKey: 'stale-token',
        expiryKey: pastEpoch,
      });

      final service = YtmOAuthService.shared;
      await service.init();
      expect(service.accessToken, 'stale-token');
      expect(service.isSignedIn, isTrue);

      // Expired and unrefreshable -> the session is dropped, not reported live.
      expect(await service.ensureFresh(), isFalse);
      expect(service.isSignedIn, isFalse);
      expect(service.accessToken, isNull);
    });

    test('refresh returns false when there is no refresh token', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(await YtmOAuthService.shared.refresh(), isFalse);
    });

    test('signOut with no token clears state without a revoke round-trip',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      await YtmOAuthService.shared.signOut();
      expect(YtmOAuthService.shared.isSignedIn, isFalse);
    });

    test('a second init shares the memoised future and stays signed out',
        () async {
      final service = YtmOAuthService.shared;
      await service.init();
      expect(service.isSignedIn, isFalse);
    });
  });

  group('pollForToken pre-network guards', () {
    test('returns false immediately for an already-expired device code',
        () async {
      final code = OAuthDeviceCode(
        deviceCode: 'd',
        userCode: 'u',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 5,
        expiresInSeconds: 1,
        requestedAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      expect(await YtmOAuthService.shared.pollForToken(code), isFalse);
    });

    test('returns false when the caller cancels before the first poll',
        () async {
      final code = OAuthDeviceCode(
        deviceCode: 'd',
        userCode: 'u',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 1,
        expiresInSeconds: 1800,
        requestedAt: DateTime.now(),
      );
      expect(
        await YtmOAuthService.shared
            .pollForToken(code, isCancelled: () => true),
        isFalse,
      );
    });
  });
}
