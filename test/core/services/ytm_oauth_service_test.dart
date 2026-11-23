// test/core/services/ytm_oauth_service_test.dart
//
// Reachable-branch coverage for the Google device-authorization service. The
// class has no client-injection seam (its http.Client is a private final
// field), so the network round-trips (requestDeviceCode, pollForToken's token
// exchange, refresh, revoke) are exercised only through their pre-network
// guards; the transport-dependent branches are documented as unreachable from
// a unit test. Secure-storage state is seeded through the plugin's own mock.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('signOut during in-flight pollForToken prevents session resurrection',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final service = YtmOAuthService.shared;
      final tokenGate = Completer<http.Response>();
      service.debugHttpClient = MockClient((request) {
        if (request.url.path.endsWith('/token')) {
          return tokenGate.future;
        }
        return Future.value(http.Response('{}', 200));
      });

      final code = OAuthDeviceCode(
        deviceCode: 'd',
        userCode: 'u',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 1,
        expiresInSeconds: 1800,
        requestedAt: DateTime.now(),
      );

      var ticked = false;
      final pollFuture = service.pollForToken(
        code,
        onTick: () => ticked = true,
      );

      while (!ticked) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Sign out while the token exchange HTTP request is still in-flight.
      await service.signOut();

      tokenGate.complete(http.Response(
        jsonEncode({
          'access_token': 'resurrected-token',
          'refresh_token': 'resurrected-refresh',
          'expires_in': 3600,
        }),
        200,
      ));

      final result = await pollFuture;
      expect(result, isFalse);
      expect(service.isSignedIn, isFalse);
      expect(service.accessToken, isNull);
    });

    test('signOut during in-flight refresh prevents session resurrection',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final service = YtmOAuthService.shared;

      // Step 1: seed a valid session (with refresh token) via pollForToken.
      service.debugHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'initial-access',
            'refresh_token': 'initial-refresh',
            'expires_in': 3600,
          }),
          200,
        );
      });
      final code = OAuthDeviceCode(
        deviceCode: 'd2',
        userCode: 'u2',
        verificationUrl: 'https://google.com/device',
        intervalSeconds: 1,
        expiresInSeconds: 1800,
        requestedAt: DateTime.now(),
      );
      expect(await service.pollForToken(code), isTrue);
      expect(service.isSignedIn, isTrue);

      // Step 2: start refresh() and pause it mid-flight.
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<http.Response>();
      service.debugHttpClient = MockClient((request) {
        if (request.url.path.endsWith('/token')) {
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          return refreshGate.future;
        }
        return Future.value(http.Response('', 200));
      });

      final refreshFuture = service.refresh();
      await refreshStarted.future;

      // Sign out while refresh is in-flight.
      await service.signOut();

      // Complete the refresh HTTP response with fresh tokens.
      refreshGate.complete(http.Response(
        jsonEncode({
          'access_token': 'zombie-access',
          'refresh_token': 'zombie-refresh',
          'expires_in': 3600,
        }),
        200,
      ));

      final refreshed = await refreshFuture;
      expect(refreshed, isFalse);
      expect(service.isSignedIn, isFalse);
      expect(service.accessToken, isNull);
    });
  });
}
