// test/core/services/ytm_account_service_session_test.dart
//
// Session lifecycle of YtmAccountService driven through its public surface:
// secure-storage persistence and the legacy migration, the init() restore
// chain, validateSessionDetailed()'s status/error mapping, saveSession()'s
// refusal rules and logout()'s teardown, with the Innertube client scripted
// through MockClient and every collaborator mocked. No real HTTP, no plugins.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_circuit_breaker.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmService extends Mock implements YtmService {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

const String _cookieKey = 'ytm_session_cookies_secure';
const String _legacyCookieKey = 'ytm_session_cookies';
const String _validJar = 'SAPISID=sapisid; __Secure-3PSID=psid';
const _ytmChannel = MethodChannel(PulsrChannels.ytm);

late MockYtmService ytm;
late MockSecureStorage secure;
late http.Response Function(http.Request request) responder;
late Future<http.Response> Function(http.Request request) handler;
late int requestCount;

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_ytmChannel, handler);
}

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _authHome({String? datasyncId, String? visitorData}) =>
    _json(200, {
      'responseContext': {
        'mainAppWebResponseContext': {
          if (datasyncId != null) 'datasyncId': datasyncId,
        },
        if (visitorData != null) 'visitorData': visitorData,
      },
      'contents': {
        'singleColumnBrowseResultsRenderer': {},
      },
    });

http.Response _loggedOut() => _json(200, {
      'responseContext': {
        'mainAppWebResponseContext': {'loggedOut': true},
      },
    });

YtmAccountService _service() {
  return YtmAccountService(YtmClientVersionResolver())
    ..debugInnertubeClient = MockClient((request) {
      requestCount++;
      return handler(request);
    });
}

Future<void> _settle() => pumpEventQueue(times: 30);

void _stubYtmService() {
  when(() => ytm.breaker).thenReturn(YtmCircuitBreaker());
  when(() => ytm.syncCookies(any())).thenAnswer((_) async {});
  when(() => ytm.setDataSyncId(any())).thenAnswer((_) async {});
  when(() => ytm.invalidatePoToken()).thenAnswer((_) async {});
  when(() => ytm.ensurePoTokenReady()).thenAnswer((_) async => true);
  when(() => ytm.getPlayerPoToken(any())).thenAnswer((_) async => null);
  when(() => ytm.getPoTokenState()).thenAnswer((_) async => null);
  when(() => ytm.getAccountPoToken(any())).thenAnswer((_) async => null);
  when(() => ytm.clearNativeSession()).thenAnswer((_) async {});
  when(() => ytm.notifyAuthExpired()).thenReturn(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    YtmRateLimiter.debugReset();
    requestCount = 0;
    responder = (_) => _authHome();
    handler = (request) async => responder(request);

    ytm = MockYtmService();
    _stubYtmService();
    getIt.registerSingleton<YtmService>(ytm);

    secure = MockSecureStorage();
    when(() => secure.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => secure.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});
    when(() => secure.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    YtmAccountService.setSecureStorageForTesting(secure);

    _mockChannel((call) async => null);
  });

  tearDown(() async {
    _mockChannel((call) async => null);
    await getIt.reset();
  });

  group('getNativeCookiesFromDomains', () {
    test('returns the native jar verbatim', () async {
      _mockChannel((call) async {
        if (call.method == 'getCookies') return _validJar;
        return null;
      });
      expect(await _service().getNativeCookiesFromDomains(), _validJar);
    });

    test('returns null when the channel is unavailable', () async {
      _mockChannel((call) async => throw PlatformException(code: 'boom'));
      expect(await _service().getNativeCookiesFromDomains(), isNull);
    });
  });

  group('init', () {
    test('no native and no stored cookies leaves the service signed out',
        () async {
      final service = _service();
      await service.init();
      await _settle();

      expect(service.isLoggedIn, isFalse);
      expect(service.cookies, isNull);
      expect(service.loginState.value, isFalse);
      verifyNever(() => ytm.syncCookies(any()));
    });

    test('valid native cookies are scoped, stored and synced to the service',
        () async {
      _mockChannel((call) async {
        if (call.method == 'getCookies') {
          return '$_validJar; NID=google-only';
        }
        return null;
      });

      final service = _service();
      await service.init();
      await _settle();

      expect(service.isLoggedIn, isTrue);
      expect(service.cookies, _validJar);
      expect(service.loginState.value, isTrue);
      verify(() => secure.write(key: _cookieKey, value: _validJar))
          .called(greaterThanOrEqualTo(1));
      verify(() => ytm.syncCookies(_validJar)).called(greaterThanOrEqualTo(1));
    });

    test('malformed native cookies fall back to the stored jar', () async {
      _mockChannel((call) async {
        if (call.method == 'getCookies') return 'not-a-cookie';
        return null;
      });
      when(() => secure.read(key: _cookieKey))
          .thenAnswer((_) async => _validJar);

      final service = _service();
      await service.init();
      await _settle();

      expect(service.cookies, _validJar);
      expect(service.isLoggedIn, isTrue);
    });

    test('a legacy plaintext prefs jar is migrated into secure storage',
        () async {
      SharedPreferences.setMockInitialValues({_legacyCookieKey: _validJar});
      final service = _service();
      await service.init();
      await _settle();

      expect(service.cookies, _validJar);
      verify(() => secure.write(key: _cookieKey, value: _validJar))
          .called(greaterThanOrEqualTo(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyCookieKey), isNull);
    });

    test('a second init() is a no-op', () async {
      var getCookiesCalls = 0;
      _mockChannel((call) async {
        if (call.method == 'getCookies') getCookiesCalls++;
        return null;
      });

      final service = _service();
      await service.init();
      await service.init();
      expect(getCookiesCalls, 1);
    });

    test('a dead stored session is validated off the startup path and wiped',
        () async {
      when(() => secure.read(key: _cookieKey))
          .thenAnswer((_) async => _validJar);
      responder = (_) => _json(401, {'error': 'unauthorized'});

      final service = _service();
      await service.init();
      // The wipe happens in the unawaited validation, so wait for it.
      await _settle();

      expect(service.isLoggedIn, isFalse);
      expect(service.loginState.value, isFalse);
      verify(() => secure.delete(key: _cookieKey))
          .called(greaterThanOrEqualTo(1));
    });

    test('without cookies the OAuth restore path is attempted', () async {
      final service = _service();
      await service.init();
      await _settle();
      // YtmOAuthService is not signed in under the test binding, so this only
      // proves the restore attempt is non-fatal.
      expect(service.isOAuthSession, isFalse);
      expect(service.isLoggedIn, isFalse);
    });
  });

  group('validateSessionDetailed', () {
    Future<YtmAccountService> loggedIn() async {
      _mockChannel((call) async {
        if (call.method == 'getCookies') return _validJar;
        return null;
      });
      final service = _service();
      await service.init();
      await _settle();
      return service;
    }

    test('is invalid when no session exists', () async {
      expect(
        await _service().validateSessionDetailed(),
        SessionValidationResult.invalid,
      );
    });

    test('200 with contents is valid and harvests session state', () async {
      final service = await loggedIn();
      responder =
          (_) => _authHome(datasyncId: 'dsid||', visitorData: 'visitor-1');

      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.valid,
      );
      expect(service.dataSyncId, 'dsid||');
      expect(service.sessionVisitorData, 'visitor-1');
      verify(() => ytm.setDataSyncId('dsid||')).called(greaterThanOrEqualTo(1));
    });

    test('200 loggedOut body is invalid', () async {
      final service = await loggedIn();
      responder = (_) => _loggedOut();
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.invalid,
      );
    });

    test('401 is invalid', () async {
      final service = await loggedIn();
      responder = (_) => _json(401, const {});
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.invalid,
      );
    });

    test('403 with a loggedOut JSON body is invalid', () async {
      final service = await loggedIn();
      responder = (_) => _json(403, {
            'responseContext': {
              'mainAppWebResponseContext': {'loggedOut': true},
            },
          });
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.invalid,
      );
    });

    test('403 with an HTML interstitial is unknown, not invalid', () async {
      final service = await loggedIn();
      responder = (_) => http.Response('<html>blocked</html>', 403);
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.unknown,
      );
    });

    test('a 500 is unknown, so a transient outage cannot kill the session',
        () async {
      final service = await loggedIn();
      responder = (_) => _json(500, const {});
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.unknown,
      );
    });

    test('an auth YtmException is invalid and any other is unknown', () async {
      final service = await loggedIn();
      responder = (_) => throw const YtmException('YTM_AUTH', 'expired');
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.invalid,
      );

      responder = (_) => throw const YtmException('YTM_FAILED', 'boom');
      expect(
        await service.validateSessionDetailed(),
        SessionValidationResult.unknown,
      );
    });

    test('validateSession() only returns false for a definitive verdict',
        () async {
      final service = await loggedIn();

      responder = (_) => _authHome();
      expect(await service.validateSession(), isTrue);

      responder = (_) => _json(503, const {});
      expect(await service.validateSession(), isTrue);

      responder = (_) => _json(401, const {});
      expect(await service.validateSession(), isFalse);
    });
  });

  group('saveSession', () {
    test('refuses a jar with no session cookies', () async {
      final service = _service();
      expect(await service.saveSession('CONSENT=1; NID=x'), isFalse);
      expect(service.isLoggedIn, isFalse);
      verifyNever(() => ytm.syncCookies(any()));
    });

    test('accepts a signed-in jar and warms the session', () async {
      final service = _service();
      expect(await service.saveSession('NID=google; $_validJar'), isTrue);
      await _settle();

      expect(service.isLoggedIn, isTrue);
      expect(service.cookies, _validJar); // NID scoped away
      expect(service.accountName, 'YouTube Music Account');
      expect(service.loginState.value, isTrue);
      verify(() => ytm.syncCookies(_validJar)).called(1);
      verify(() => ytm.invalidatePoToken()).called(1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ytm_account_name'), 'YouTube Music Account');
    });

    test('an unauthenticated warm response does not undo the save', () async {
      responder = (_) => _loggedOut();
      final service = _service();
      expect(await service.saveSession(_validJar), isTrue);
      await _settle();

      expect(service.isLoggedIn, isTrue);
      verify(() => ytm.notifyAuthExpired()).called(1);
    });
  });

  group('logout', () {
    test('tears down cookies, prefs, native session and poToken', () async {
      when(() => secure.read(key: _cookieKey))
          .thenAnswer((_) async => _validJar);
      final service = _service();
      await service.init();
      await _settle();
      expect(service.isLoggedIn, isTrue);

      await service.logout();

      expect(service.isLoggedIn, isFalse);
      expect(service.cookies, isNull);
      expect(service.accountName, isNull);
      expect(service.loginState.value, isFalse);
      verify(() => secure.delete(key: _cookieKey))
          .called(greaterThanOrEqualTo(1));
      verify(() => ytm.clearNativeSession()).called(1);
      verify(() => ytm.syncCookies('')).called(1);
      verify(() => ytm.invalidatePoToken()).called(greaterThanOrEqualTo(1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ytm_account_name'), isNull);
      expect(prefs.getString('ytm_account_avatar'), isNull);
      expect(prefs.getString('ytm_data_sync_id'), isNull);
    });

    test('clears the account-scoped URL cache', () async {
      final cache = YtmUrlCache.withClock(FakeClock(DateTime(2026)));
      getIt.registerSingleton<YtmUrlCache>(cache);
      cache.putStream(
        YtmStream(
          videoId: 'vidCache',
          url:
              'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1800000000',
          mimeType: 'audio/mp4',
          container: 'm4a',
          bitrateKbps: 128,
          duration: const Duration(minutes: 3),
          title: 'T',
          artist: 'A',
        ),
        quality: 'high',
      );
      expect(cache.get('vidCache'), isNotNull);

      await _service().logout();
      expect(cache.get('vidCache'), isNull);
    });

    test('clearSessionWebViewCookies never throws without the plugin',
        () async {
      await _service().clearSessionWebViewCookies();
    });
  });

  group('ensureDataSyncId', () {
    test('does nothing when signed out', () async {
      final service = _service();
      await service.ensureDataSyncId();
      expect(requestCount, 0);
      expect(service.dataSyncId, isNull);
    });

    test('bootstraps an account id when the warm-up did not harvest one',
        () async {
      // The first (warm) request is gated so the explicit bootstrap can run
      // while it is still in flight, exactly like a slow home browse.
      var calls = 0;
      final warmGate = Completer<void>();
      handler = (request) async {
        calls++;
        if (calls == 1) {
          await warmGate.future;
          return _json(401, const {});
        }
        return _authHome(datasyncId: 'fresh||');
      };

      final service = _service();
      await service.saveSession(_validJar);
      final bootstrap = service.ensureDataSyncId();
      warmGate.complete();
      await bootstrap;
      await _settle();

      expect(service.dataSyncId, 'fresh||');
      verify(() => ytm.setDataSyncId('fresh||'))
          .called(greaterThanOrEqualTo(1));
    });

    test('a recent attempt is throttled instead of hammering browse', () async {
      _mockChannel((call) async {
        if (call.method == 'getCookies') return _validJar;
        return null;
      });
      final service = _service();
      await service.init();
      await _settle();

      final afterInit = requestCount;
      await service.ensureDataSyncId();
      expect(requestCount, afterInit,
          reason: 'the bootstrap throttle is 60s, so a second call is free');
    });
  });
}
