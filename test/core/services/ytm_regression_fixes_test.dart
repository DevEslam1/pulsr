// test/core/services/ytm_regression_fixes_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/constants/channels.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/services/ytm_cache_manager.dart';
import 'package:pulsr/core/services/ytm_circuit_breaker.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_oauth_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockYtmService extends Mock implements YtmService {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

const _ytmChannel = MethodChannel(PulsrChannels.ytm);
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

_MockSecureStorage _setupSecureMock() {
  final secure = _MockSecureStorage();
  when(() => secure.read(key: any(named: 'key')))
      .thenAnswer((_) async => null);
  when(() => secure.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      )).thenAnswer((_) async {});
  when(() => secure.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  YtmAccountService.setSecureStorageForTesting(secure);
  return secure;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    YtmAccountService.setSecureStorageForTesting(const FlutterSecureStorage());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ytmChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    await getIt.reset();
    YtmRateLimiter.debugReset();
  });

  group('C-04 & H-10 YtmAccountService regressions', () {
    test(
        'validateSessionDetailed treats bare guest contents (and int datasyncId) as unknown',
        () async {
      SharedPreferences.setMockInitialValues({});
      _setupSecureMock();

      final account = YtmAccountService(YtmClientVersionResolver());
      account.debugInnertubeClient = MockClient((req) async {
        // Bare 'contents' stub with non-String datasyncId (12345) must neither
        // throw a TypeError nor falsely report SessionValidationResult.valid.
        return _json(200, {
          'responseContext': {
            'mainAppWebResponseContext': {'datasyncId': 12345},
          },
          'contents': {},
        });
      });
      await account.saveSession('SAPISID=s1; __Secure-3PSID=p1');

      final status = await account.validateSessionDetailed();
      expect(status, SessionValidationResult.unknown);
    });

    test('validateSessionDetailed accepts confirmed account_menu identity',
        () async {
      SharedPreferences.setMockInitialValues({});
      _setupSecureMock();

      final account = YtmAccountService(YtmClientVersionResolver());
      account.debugInnertubeClient = MockClient((req) async {
        expect(req.url.path, contains('account/account_menu'));
        return _json(200, {
          'actions': [
            {
              'openPopupAction': {
                'popup': {
                  'multiPageMenuRenderer': {
                    'header': {
                      'activeAccountHeaderRenderer': {
                        'accountName': {
                          'runs': [
                            {'text': 'Alice'}
                          ],
                        },
                      },
                    },
                  },
                },
              },
            },
          ],
        });
      });
      await account.saveSession('SAPISID=s1; __Secure-3PSID=p1');

      final status = await account.validateSessionDetailed();
      expect(status, SessionValidationResult.valid);
      expect(account.accountName, 'Alice');
    });

    test('concurrent fetchLikedSongs coalesce and logout avoids GetIt crash',
        () async {
      SharedPreferences.setMockInitialValues({});
      _setupSecureMock();

      final account = YtmAccountService(YtmClientVersionResolver());
      final gate = Completer<void>();
      var likedBrowseCalls = 0;
      account.debugInnertubeClient = MockClient((req) async {
        if (req.url.path.contains('browse') &&
            req.body.contains('FEmusic_liked_tracks')) {
          likedBrowseCalls++;
          await gate.future;
          return _json(200, {
            'contents': {
              'musicPlaylistShelfRenderer': {
                'contents': [
                  {
                    'musicResponsiveListItemRenderer': {
                      'playlistItemData': {'videoId': 'dQw4w9WgXcQ'},
                      'flexColumns': [
                        {
                          'musicResponsiveListItemFlexColumnRenderer': {
                            'text': {
                              'runs': [
                                {'text': 'Song One'}
                              ],
                            },
                          },
                        },
                        {
                          'musicResponsiveListItemFlexColumnRenderer': {
                            'text': {
                              'runs': [
                                {'text': 'Artist One'}
                              ],
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
          });
        }
        return _json(200, {});
      });

      await account.saveSession('SAPISID=s1; __Secure-3PSID=p1');
      final f1 = account.fetchLikedSongs();
      final f2 = account.fetchLikedSongs();
      gate.complete();
      final res = await Future.wait([f1, f2]);
      expect(likedBrowseCalls, 1);
      expect(res[0].single.videoId, 'dQw4w9WgXcQ');
      expect(res[1].single.videoId, 'dQw4w9WgXcQ');

      await account.logout();
      expect(account.isLoggedIn, isFalse);
      // Should not throw StateError from unregistered getIt<YtmService>()
      await account.resolvePlayerStream('vid1', guestClientsEnabled: false);
    });

    test('OAuth 401 triggers refresh and retries even when maxAttempts == 1',
        () async {
      SharedPreferences.setMockInitialValues({});
      _setupSecureMock();

      final futureEpoch = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch
          .toString();
      FlutterSecureStorage.setMockInitialValues({
        'ytm_oauth_access_token': 'old-access',
        'ytm_oauth_refresh_token': 'refresh-tok',
        'ytm_oauth_expiry_epoch': futureEpoch,
      });

      var refreshCalls = 0;
      YtmOAuthService.shared.debugHttpClient = MockClient((req) async {
        refreshCalls++;
        return _json(200, {
          'access_token': 'new-access',
          'expires_in': 3600,
        });
      });

      final account = YtmAccountService(YtmClientVersionResolver());
      final authHeaders = <String>[];
      var recordRequests = false;
      account.debugInnertubeClient = MockClient((req) async {
        if (recordRequests) {
          authHeaders.add(req.headers['authorization'] ?? '');
          if (authHeaders.length == 1) {
            return _json(401, {
              'error': {'code': 401}
            });
          }
        }
        return _json(200, {'contents': {}});
      });

      await YtmOAuthService.shared.init();
      await account.adoptOAuthSession();
      // Let background _warmSession finish before testing validateSessionDetailed.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      recordRequests = true;
      // validateSessionDetailed uses maxAttempts: 1 internally; 401 refreshes once.
      final result = await account.validateSessionDetailed();
      expect(result, SessionValidationResult.valid);
      expect(refreshCalls, 1);
      expect(authHeaders, ['Bearer old-access', 'Bearer new-access']);
      await YtmOAuthService.shared.signOut();
    });
  });

  group('H-10 CircuitBreaker & VersionResolver regressions', () {
    test('YtmCircuitBreaker requires threshold hits for bot & IP signals', () {
      final breaker = YtmCircuitBreaker();
      breaker.recordFailure(YtmBlockSignal.botChallenge);
      breaker.recordFailure(YtmBlockSignal.botChallenge);
      expect(breaker.shouldAllow(YtmBlockSignal.botChallenge), isTrue);

      breaker.recordFailure(YtmBlockSignal.botChallenge);
      expect(breaker.shouldAllow(YtmBlockSignal.botChallenge), isFalse);

      breaker.recordFailure(YtmBlockSignal.ipBlocked);
      breaker.recordFailure(YtmBlockSignal.ipBlocked);
      expect(breaker.shouldAllow(YtmBlockSignal.ipBlocked), isTrue);
      breaker.recordFailure(YtmBlockSignal.ipBlocked);
      expect(breaker.shouldAllow(YtmBlockSignal.ipBlocked), isFalse);
    });

    test('YtmClientVersionResolver isolates www.youtube.com 2.x from WEB_REMIX',
        () async {
      SharedPreferences.setMockInitialValues({});
      final resolver = YtmClientVersionResolver();
      final client = MockClient((req) async {
        if (req.url.host == 'music.youtube.com') {
          throw http.ClientException('music host unreachable');
        }
        if (req.url.host == 'www.youtube.com') {
          return http.Response(
            '{"INNERTUBE_CONTEXT_CLIENT_VERSION":"2.20260404.01.00",'
            '"INNERTUBE_API_KEY":"AIzaSyWebMockKey000000000000000",'
            '"STS":66666}',
            200,
          );
        }
        return http.Response('', 404);
      });

      final pushed = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_ytmChannel, (call) async {
        pushed.add(call);
        return null;
      });

      await resolver.refresh(client: client);
      expect(resolver.clientVersion, startsWith('1.'));
      expect(resolver.webClientVersion, '2.20260404.01.00');
      expect(resolver.clientVersionFor('WEB'), '2.20260404.01.00');
      expect(resolver.clientVersionFor('WEB_REMIX'), startsWith('1.'));
      expect(
        pushed.where((c) =>
            c.method == 'setClientVersion' &&
            (c.arguments as Map)['clientVersion'] == '2.20260404.01.00'),
        isEmpty,
      );
    });

    test('YtmOAuthService recreates client after dispose', () async {
      final service = YtmOAuthService.shared;
      service.dispose();
      service.debugHttpClient = MockClient((req) async => _json(200, {
            'device_code': 'dc',
            'user_code': 'uc',
            'verification_url': 'https://google.com/device',
            'expires_in': 900,
            'interval': 5,
          }));
      final code = await service.requestDeviceCode();
      expect(code.deviceCode, 'dc');
    });
  });

  group('H-11 YtmService, UrlCache, CacheManager & BrowseService', () {
    test('searchWithFallback throws when both native and Dart engines fail',
        () async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_ytmChannel, (call) async {
        if (call.method == 'search') {
          throw PlatformException(code: 'YTM_NETWORK', message: 'offline');
        }
        return null;
      });
      final ytm = YtmService();
      addTearDown(ytm.dispose);
      ytm.debugHttpClient = MockClient((_) async => _json(503, {}));

      await expectLater(
        ytm.searchWithFallback('test query'),
        throwsA(isA<YtmException>()),
      );
    });

    test('handleNetworkChange bumps epoch and drops in-flight cache writes',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = Directory.systemTemp.createTempSync('ytm_reg_url_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (_) async => tempDir.path);

      final urlCache = YtmUrlCache.withClock(
        FakeClock(DateTime(2026, 5, 1)),
      );
      getIt.registerSingleton<YtmUrlCache>(urlCache);

      final resolveGate = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_ytmChannel, (call) async {
        if (call.method == 'resolveStream') {
          return resolveGate.future;
        }
        return null;
      });

      final ytm = YtmService();
      addTearDown(ytm.dispose);

      final future = ytm.resolveStream('vidEpoch1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Network changes mid-resolve: clears cache & bumps _egressEpoch
      ytm.handleNetworkChange();

      resolveGate.complete({
        'videoId': 'vidEpoch1',
        'url': 'https://rr1---sn.googlevideo.com/videoplayback?expire=1900000000',
        'mimeType': 'audio/mp4',
        'container': 'm4a',
        'bitrateKbps': 128,
        'durationMs': 180000,
      });

      await future;
      expect(urlCache.get('vidEpoch1'), isNull);
    });

    test('YtmUrlCache drops stale cookies on URL swap & parses quality:m4a',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('ytm_url_cookie_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (_) async => tempDir.path);

      final cache = YtmUrlCache.withClock(FakeClock(DateTime(2026, 5, 1)));
      await cache.restore();
      cache.put(
        'v1',
        'https://rr1/old?mime=audio%2Fmp4',
        cookies: 'SID=secret',
        userAgent: 'OldUA',
      );
      // URL changed without explicit cookies -> must NOT inherit old cookies/UA
      cache.put('v1', 'https://rr2/new?mime=audio%2Fwebm');

      final entry = cache.get('v1')!;
      expect(entry.cookies, isNull);
      expect(entry.userAgent, isNull);
      expect(entry.toStream(quality: 'medium:m4a').bitrateKbps, 128);

      // clear() flushes empty array via microtask without 3s debounce delay
      cache.clear();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final raw =
          File('${tempDir.path}/ytm_url_cache_v1.json').readAsStringSync();
      expect(jsonDecode(raw), isEmpty);
    });

    test('YtmCacheManager.cacheFileName sanitizes quality colons', () {
      expect(
        YtmCacheManager.cacheFileName('abc', 'medium:m4a', 'm4a'),
        'abc.medium_m4a.m4a',
      );
    });

    test('YtmBrowseService queries FEmusic_new_releases before search fallback',
        () async {
      final mockYtm = _MockYtmService();
      when(() => mockYtm.browseMusicSection('FEmusic_new_releases', limit: 15))
          .thenAnswer((_) async => const []);
      when(() => mockYtm.searchWithFallback('New Music Releases', limit: 15))
          .thenAnswer((_) async => const []);

      final browse = YtmBrowseService(mockYtm);
      await browse.getNewReleases();

      verify(() => mockYtm.browseMusicSection('FEmusic_new_releases', limit: 15))
          .called(1);
    });
  });
}
