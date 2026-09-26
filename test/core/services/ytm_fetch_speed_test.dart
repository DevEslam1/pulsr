// test/core/services/ytm_fetch_speed_test.dart
//
// Before/after gate for the "fetch songs faster" work.
//
// Every case measures a *latency shape*, not correctness: a slow engine must be
// overtaken by a faster one instead of blocking it. Each one fails against the
// pre-change strictly-sequential code and passes once the hedges land, so a
// green run of this file is the evidence the change actually took.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_client_version_resolver.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';

class MockYtmService extends Mock implements YtmService {}

class MockYtmAccountService extends Mock implements YtmAccountService {}

const _channel = MethodChannel(YtmService.channelName);

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

Future<void> _ms(int millis) =>
    Future<void>.delayed(Duration(milliseconds: millis));

Map<String, Object?> _streamRow({String videoId = 'dQw4w9WgXcQ'}) => {
      'videoId': videoId,
      'url': 'https://example.com/stream.m4a',
      'mimeType': 'audio/mp4',
      'container': 'm4a',
      'bitrateKbps': 128,
      'durationMs': 213000,
      'title': 'Never Gonna Give You Up',
      'artist': 'Rick Astley',
    };

/// A `/search` response the Dart InnerTube walker can actually extract tracks
/// from (it looks for `musicTwoRowItemRenderer` anywhere in the tree).
String _innertubeSearchBody(String videoId) => jsonEncode({
      'contents': {
        'tabbedSearchResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicShelfRenderer': {
                          'contents': [
                            {
                              'musicTwoRowItemRenderer': {
                                'navigationEndpoint': {
                                  'watchEndpoint': {'videoId': videoId},
                                },
                                'title': {
                                  'runs': [
                                    {'text': 'Hedged Song'}
                                  ],
                                },
                                'subtitle': {
                                  'runs': [
                                    {'text': 'Hedged Artist'}
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
              },
            },
          ],
        },
      },
    });

/// A `/player` response the pure-Dart fallback accepts for [url].
String _playerOkBody(String url, {int bitrate = 128000}) => jsonEncode({
      'playabilityStatus': {'status': 'OK'},
      'streamingData': {
        'adaptiveFormats': [
          {
            'mimeType': 'audio/mp4',
            'bitrate': bitrate,
            'itag': 140,
            'approxDurationMs': '213000',
            'url': url,
          },
        ],
      },
      'videoDetails': {'title': 'Hedged', 'author': 'Fast Client'},
    });

/// Two consecutive `LOGIN_REQUIRED` answers short-circuit the 9-client Dart
/// player chain, so the fake backend costs 2 round trips rather than 9.
http.Response _playerReject() => http.Response(
      jsonEncode({
        'playabilityStatus': {'status': 'LOGIN_REQUIRED', 'reason': 'nope'},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    YtmRateLimiter.debugReset();
    _mockChannel((_) async => null);
  });

  tearDown(() {
    _mockChannel((_) async => null);
    if (getIt.isRegistered<YtmService>()) getIt.unregister<YtmService>();
    if (getIt.isRegistered<YtmAccountService>()) {
      getIt.unregister<YtmAccountService>();
    }
  });

  group('search: a slow native extractor must not gate the InnerTube fallback',
      () {
    test('the hedge answers while the native search is still running',
        () async {
      _mockChannel((call) async {
        if (call.method == 'search') {
          await _ms(3000);
          return [
            {'videoId': 'nativeslow1', 'title': 'Native', 'artist': 'N'}
          ];
        }
        return null;
      });

      final service = YtmService();
      service.debugHttpClient = MockClient((request) async {
        await _ms(150);
        return http.Response(
          _innertubeSearchBody('inntubehed1'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final stopwatch = Stopwatch()..start();
      final results = await service.searchWithFallback('some query');
      stopwatch.stop();

      expect(results, isNotEmpty);
      expect(results.first.videoId, equals('inntubehed1'));
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1500),
        reason: 'InnerTube must be allowed to overtake a 3s native search, '
            'not queue behind it (took ${stopwatch.elapsedMilliseconds}ms)',
      );
    });

    test('a fast native search still wins without paying for the fallback',
        () async {
      _mockChannel((call) async {
        if (call.method == 'search') {
          await _ms(100);
          return [
            {'videoId': 'nativefast1', 'title': 'Native', 'artist': 'N'}
          ];
        }
        return null;
      });

      var fallbackCalls = 0;
      final service = YtmService();
      service.debugHttpClient = MockClient((request) async {
        fallbackCalls++;
        await _ms(150);
        return http.Response(
          _innertubeSearchBody('inntubehed1'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final results = await service.searchWithFallback('some query');

      expect(results.first.videoId, equals('nativefast1'));
      expect(fallbackCalls, equals(0),
          reason: 'the hedge delay must keep the happy path single-request');
    });
  });

  group('resolve: a slow Tier-1 account chain must not gate the native tier',
      () {
    test('the native tier is started while Tier-1 is still running', () async {
      final account = MockYtmAccountService();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.dataSyncId).thenReturn(null);
      when(() => account.ensureDataSyncId()).thenAnswer((_) async {});
      when(() => account.resolvePlayerStream(any(),
              quality: any(named: 'quality')))
          .thenAnswer((_) async {
        await _ms(4000);
        return null;
      });
      getIt.registerSingleton<YtmAccountService>(account);

      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          await _ms(500);
          return _streamRow();
        }
        return null;
      });

      final stopwatch = Stopwatch()..start();
      final stream = await YtmService().resolveStream('dQw4w9WgXcQ');
      stopwatch.stop();

      expect(stream, isNotNull);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'a 4s Tier-1 must not delay a 500ms native answer '
            '(took ${stopwatch.elapsedMilliseconds}ms)',
      );
    });

    test('a fast Tier-1 still wins without starting the native tier',
        () async {
      final account = MockYtmAccountService();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.dataSyncId).thenReturn('dsid||');
      when(() => account.resolvePlayerStream(any(),
              quality: any(named: 'quality')))
          .thenAnswer((_) async {
        await _ms(50);
        return const YtmStream(
          videoId: 'dQw4w9WgXcQ',
          url: 'https://example.com/a.m4a',
          mimeType: 'audio/mp4',
          container: 'm4a',
          bitrateKbps: 128,
          duration: Duration(milliseconds: 213000),
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
        );
      });
      getIt.registerSingleton<YtmAccountService>(account);

      var nativeCalls = 0;
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          nativeCalls++;
          return _streamRow();
        }
        return null;
      });

      final stream = await YtmService().resolveStream('dQw4w9WgXcQ');

      expect(stream.url, contains('a.m4a'));
      expect(nativeCalls, equals(0),
          reason: 'the hedge delay must keep the happy path single-chain');
    });
  });

  group('Tier-1 prep: poToken/session work must overlap, not queue', () {
    test('state read and content-bound mint run alongside the warm-ups',
        () async {
      getIt.registerSingleton<YtmService>(YtmService());

      // Three 700 ms steps. Sequential: 2100 ms. Overlapped: 1400 ms.
      _mockChannel((call) async {
        switch (call.method) {
          case 'ensurePoTokenReady':
            await _ms(700);
            return true;
          case 'getPoTokenState':
            await _ms(700);
            return {
              'isReady': true,
              'streamingPoToken': 'guest-token',
              'visitorData': 'guest-visitor',
            };
          case 'getPlayerPoToken':
            await _ms(700);
            return 'content-token';
          default:
            return null;
        }
      });

      final account = YtmAccountService(YtmClientVersionResolver());
      account.debugInnertubeClient = MockClient((_) async => _playerReject());

      final stopwatch = Stopwatch()..start();
      final stream = await account.resolvePlayerStream('dQw4w9WgXcQ');
      stopwatch.stop();

      expect(stream, isNull,
          reason: 'the fake backend rejects every client; the test measures '
              'prep time only');
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1700),
        reason: 'getPoTokenState and getPlayerPoToken must not queue behind '
            'each other (took ${stopwatch.elapsedMilliseconds}ms)',
      );
    });
  });

  group('search: the results a user is most likely to tap get warmed', () {
    late MockYtmService service;

    setUp(() {
      service = MockYtmService();
    });

    test('a settled search warms the top results, not just the first',
        () async {
      final top = YtmTrack.fromChannel({
        'videoId': 'topvideoid1',
        'title': 'Top',
        'artist': 'A',
        'durationMs': 1000,
      })!;
      final second = YtmTrack.fromChannel({
        'videoId': 'secondid222',
        'title': 'Second',
        'artist': 'B',
        'durationMs': 1000,
      })!;
      final third = YtmTrack.fromChannel({
        'videoId': 'thirdid3333',
        'title': 'Third',
        'artist': 'C',
        'durationMs': 1000,
      })!;
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => [top, second, third]);
      when(() => service.isBotCoolingDown).thenReturn(false);
      when(() => service.resolveStream(any())).thenAnswer((_) async =>
          const YtmStream(
              videoId: 'topvideoid1',
              url: 'https://example.com/a.m4a',
              mimeType: 'audio/mp4',
              container: 'm4a',
              bitrateKbps: 128,
              duration: Duration(milliseconds: 200000),
              title: 'Top',
              artist: 'Someone'));

      final cubit = YtmSearchCubit(service: service);
      cubit.onQueryChanged('something');
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      verify(() => service.resolveStream('topvideoid1')).called(1);
      verify(() => service.resolveStream('secondid222')).called(1);
      verify(() => service.resolveStream('thirdid3333')).called(1);
      await cubit.close();
    });
  });

  group('resolve: the Dart-level hedge is a real second chain, not a promise', () {
    test('two concurrent default resolves still share one native chain',
        () async {
      var resolveCalls = 0;
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          resolveCalls++;
          await _ms(400);
          return _streamRow();
        }
        return null;
      });

      final service = YtmService();
      final results = await Future.wait([
        service.resolveStream('dQw4w9WgXcQ'),
        service.resolveStream('dQw4w9WgXcQ'),
      ]);

      expect(results, hasLength(2));
      expect(resolveCalls, equals(1),
          reason: 'coalescing must still dedupe identical in-flight resolves');
    });

    test('coalesce:false opts an attempt out so it runs its own chain',
        () async {
      var resolveCalls = 0;
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          resolveCalls++;
          await _ms(300);
          return _streamRow();
        }
        return null;
      });

      final service = YtmService();
      await Future.wait([
        service.resolveStream('dQw4w9WgXcQ'),
        service.resolveStream('dQw4w9WgXcQ', coalesce: false),
      ]);

      expect(resolveCalls, equals(2),
          reason: 'the hedge needs a genuinely independent second chain');
    });
  });

  group('resolve: the pure-Dart client chain must not run back-to-back', () {
    test('a slow Dart client no longer gates a fast one', () async {
      // Native yields nothing, so resolution falls through to the Dart chain.
      _mockChannel((call) async => null);

      final service = YtmService();
      service.debugHttpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final clientName =
            ((body['context'] as Map)['client'] as Map)['clientName'] as String;
        if (clientName == 'ANDROID_VR') {
          // The first client in the old sequential chain: slow, then refuses.
          await _ms(2000);
          return _playerReject();
        }
        // Every other client answers at once with a real stream.
        await _ms(50);
        return http.Response(
          _playerOkBody('https://example.com/a.m4a'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final stopwatch = Stopwatch()..start();
      final stream = await service.resolveStream('dQw4w9WgXcQ');
      stopwatch.stop();

      expect(stream.url, contains('a.m4a'));
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1500),
        reason: 'a 2s first client must not hold the chain before a 50ms one '
            'answers (took ${stopwatch.elapsedMilliseconds}ms)',
      );
    });
  });
}
