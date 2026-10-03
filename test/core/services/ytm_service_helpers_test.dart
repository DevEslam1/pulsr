// test/core/services/ytm_service_helpers_test.dart
//
// The non-network surface of YtmService: YtmException classification and HTTP
// status mapping, every method-channel wrapper, the failure/cooldown ledger,
// search/trending/charts/moods/playlist wrappers, the Tier-2.5 poToken
// refresh-retry and the pure-Dart player fallback. Channels are stubbed, the
// Dart HTTP client is a MockClient — no real IO.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/core/errors/ytm_error_classifier.dart';
import 'package:pulsr/core/services/ytm_account_service.dart';
import 'package:pulsr/core/services/ytm_browse_service.dart';
import 'package:pulsr/core/services/ytm_service.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/core/utils/ytm_rate_limiter.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockYtmAccountService extends Mock implements YtmAccountService {}

class MockYtmBrowseService extends Mock implements YtmBrowseService {}

const _channel = MethodChannel(YtmService.channelName);

late List<YtmService> services;
late Future<Object?> Function(MethodCall call) channelHandler;
late List<MethodCall> channelCalls;

void _mockChannel(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

YtmService _newService() {
  final service = YtmService();
  services.add(service);
  return service;
}

Map<String, Object?> _resultRow({
  String videoId = 'dQw4w9WgXcQ',
  String title = 'Never Gonna Give You Up',
}) =>
    {
      'videoId': videoId,
      'title': title,
      'artist': 'Rick Astley',
      'durationMs': 213000,
      'artworkUrl': 'https://lh3.googleusercontent.com/cover',
    };

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

Map<String, dynamic> _playerBody({
  required String status,
  List<Map<String, Object?>> adaptive = const [],
  List<Map<String, Object?>> formats = const [],
}) =>
    {
      'playabilityStatus': {'status': status},
      'streamingData': {
        'adaptiveFormats': adaptive,
        'formats': formats,
      },
      'videoDetails': {'title': 'Title', 'author': 'Artist'},
    };

Map<String, Object?> _audioFormat({
  String mimeType = 'audio/mp4',
  int bitrate = 128000,
  String url = 'https://example.com/a.m4a',
}) =>
    {
      'mimeType': mimeType,
      'bitrate': bitrate,
      'approxDurationMs': '200000',
      'url': url,
    };

YtmStream _cachedStream({required String videoId}) => YtmStream(
      videoId: videoId,
      url: 'https://cache.example/a.m4a?expire=1800000000',
      mimeType: 'audio/mp4',
      container: 'm4a',
      bitrateKbps: 192,
      duration: const Duration(minutes: 3),
      title: 'Cached',
      artist: 'A',
      expiresAt:
          DateTime.now().add(const Duration(hours: 3)).millisecondsSinceEpoch,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    YtmRateLimiter.debugReset();
    services = [];
    channelCalls = [];
    channelHandler = (call) async => null;
    _mockChannel((call) {
      channelCalls.add(call);
      return channelHandler(call);
    });
  });

  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    _mockChannel(null);
    await getIt.reset();
  });

  group('YtmException', () {
    test('an explicit machine code wins over free-text classification', () {
      const e = YtmException('BOT_CHALLENGE', 'LOGIN_REQUIRED');
      expect(e.signal, YtmBlockSignal.botChallenge);
      expect(e.isAuth, isFalse);
      expect(e.isBotBlocked, isTrue);
    });

    test('httpStatusCode maps each signal group', () {
      expect(const YtmException('CONTENT_GONE').httpStatusCode, 410);
      expect(const YtmException('YTM_BOT_BLOCKED').httpStatusCode, 403);
      expect(const YtmException('IP_BLOCKED').httpStatusCode, 403);
      expect(const YtmException('YTM_AUTH').httpStatusCode, 401);
      expect(const YtmException('YTM_429').httpStatusCode, 429);
      expect(const YtmException('GEO_BLOCKED').httpStatusCode, 451);
      expect(const YtmException('YTM_FAILED').httpStatusCode, 404);
    });

    test('isOffline, isUnavailable and isDisabled name their codes', () {
      expect(const YtmException('YTM_OFFLINE').isOffline, isTrue);
      expect(const YtmException('YTM_OFFLINE').isNetwork, isTrue);
      expect(const YtmException('VIDEO_GONE').isUnavailable, isTrue);
      expect(const YtmException('YTM_UNAVAILABLE').isUnavailable, isTrue);
      expect(const YtmException('YTM_UNSUPPORTED').isDisabled, isTrue);
      expect(const YtmException('YTM_DISABLED').isDisabled, isTrue);
      expect(const YtmException('YTM_429').isThrottled, isTrue);
    });

    test('toString carries the code, trace and details', () {
      const e = YtmException('YTM_FAILED', 'boom', 'trace-9');
      expect(e.toString(), 'YtmException(YTM_FAILED [trace=trace-9]: boom)');
      expect(const YtmException('YTM_FAILED').toString(),
          'YtmException(YTM_FAILED)');
    });
  });

  group('channel wrappers', () {
    test('syncCookies forwards the jar and swallows platform errors', () async {
      final service = _newService();
      await service.syncCookies('SAPISID=a');
      expect(channelCalls.last.method, 'setCookies');
      expect(channelCalls.last.arguments, {'cookies': 'SAPISID=a'});

      channelHandler = (call) async => throw PlatformException(code: 'x');
      await service.syncCookies('again');
    });

    test('clearNativeSession invokes clearCookies and never throws', () async {
      final service = _newService();
      await service.clearNativeSession();
      expect(channelCalls.last.method, 'clearCookies');

      channelHandler = (call) async => throw PlatformException(code: 'x');
      await service.clearNativeSession();
    });

    test('ensurePoTokenReady returns the platform answer or false', () async {
      final service = _newService();
      channelHandler = (call) async => true;
      expect(await service.ensurePoTokenReady(), isTrue);

      channelHandler = (call) async => null;
      expect(await service.ensurePoTokenReady(), isFalse);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.ensurePoTokenReady(), isFalse);
    });

    test('invalidatePoToken tolerates a platform failure', () async {
      final service = _newService();
      await service.invalidatePoToken();
      expect(channelCalls.last.method, 'invalidatePoToken');

      channelHandler = (call) async => throw PlatformException(code: 'x');
      await service.invalidatePoToken();
    });

    test('getPoTokenState normalizes keys and degrades to null', () async {
      final service = _newService();
      channelHandler = (call) async => <Object?, Object?>{
            1: 'one',
            'two': 2,
          };
      expect(await service.getPoTokenState(), {'1': 'one', 'two': 2});

      channelHandler = (call) async => null;
      expect(await service.getPoTokenState(), isNull);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.getPoTokenState(), isNull);
    });

    test('getPlayerPoToken treats an empty answer as null', () async {
      final service = _newService();
      channelHandler = (call) async => 'token-1';
      expect(await service.getPlayerPoToken('dQw4w9WgXcQ'), 'token-1');
      expect(channelCalls.last.arguments, {'videoId': 'dQw4w9WgXcQ'});

      channelHandler = (call) async => '';
      expect(await service.getPlayerPoToken('dQw4w9WgXcQ'), isNull);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.getPlayerPoToken('dQw4w9WgXcQ'), isNull);
    });

    test('getAccountPoToken normalizes keys and degrades to null', () async {
      final service = _newService();
      channelHandler = (call) async => <Object?, Object?>{
            'poToken': 'pt',
            'visitorData': 'vd',
          };
      expect(await service.getAccountPoToken('dsid||'),
          {'poToken': 'pt', 'visitorData': 'vd'});
      expect(channelCalls.last.arguments, {'dataSyncId': 'dsid||'});

      channelHandler = (call) async => null;
      expect(await service.getAccountPoToken('dsid||'), isNull);
    });

    test('setDataSyncId, preWarm and resetIdentities forward their arguments',
        () async {
      final service = _newService();
      await service.setDataSyncId('dsid||');
      expect(channelCalls.last.method, 'setDataSyncId');
      expect(channelCalls.last.arguments, {'dataSyncId': 'dsid||'});

      await service.preWarm();
      expect(channelCalls.last.method, 'preWarm');

      await service.resetIdentities();
      expect(channelCalls.last.method, 'resetIdentities');
    });

    test('isVpnConnected and getLimitedMode default to false', () async {
      final service = _newService();
      channelHandler = (call) async => true;
      expect(await service.isVpnConnected(), isTrue);
      expect(await service.getLimitedMode(), isTrue);

      channelHandler = (call) async => null;
      expect(await service.isVpnConnected(), isFalse);
      expect(await service.getLimitedMode(), isFalse);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.isVpnConnected(), isFalse);
      expect(await service.getLimitedMode(), isFalse);
    });

    test('isWifiConnected fails closed on a platform error', () async {
      final service = _newService();
      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.isWifiConnected(), isFalse);
    });
  });

  group('isAvailable', () {
    test('caches a real answer', () async {
      final service = _newService();
      channelHandler = (call) async => true;
      expect(await service.isAvailable(), isTrue);
      expect(await service.isAvailable(), isTrue);
      expect(
          channelCalls.where((c) => c.method == 'isAvailable'), hasLength(1));
    });

    test('a transient failure is not cached, a disabled verdict is', () async {
      final service = _newService();
      channelHandler =
          (call) async => throw PlatformException(code: 'YTM_NETWORK');
      expect(await service.isAvailable(), isFalse);
      channelHandler = (call) async => true;
      expect(await service.isAvailable(), isTrue);

      final disabled = _newService();
      channelHandler =
          (call) async => throw PlatformException(code: 'YTM_DISABLED');
      expect(await disabled.isAvailable(), isFalse);
      final callsBefore = channelCalls.length;
      expect(await disabled.isAvailable(), isFalse);
      expect(channelCalls.length, callsBefore, reason: 'disabled is terminal');
    });
  });

  group('failure ledger', () {
    test('three non-bot failures trip a per-video cooldown', () {
      final service = _newService();
      expect(service.isVideoCoolingDown('vid1'), isFalse);
      service.recordFailure('vid1', const YtmException('YTM_FAILED'));
      service.recordFailure('vid1', const YtmException('YTM_FAILED'));
      expect(service.isVideoCoolingDown('vid1'), isFalse);
      service.recordFailure('vid1', const YtmException('YTM_FAILED'));
      expect(service.isVideoCoolingDown('vid1'), isTrue);
      expect(service.isBotCoolingDown, isFalse);

      service.debugClearBotCooldown('vid1');
      expect(service.isVideoCoolingDown('vid1'), isFalse);
    });

    test('recordFailure without an error uses the VIDEO_FAILED default', () {
      final service = _newService();
      service.recordFailure('vid2');
      service.recordFailure('vid2');
      service.recordFailure('vid2');
      expect(service.isVideoCoolingDown('vid2'), isTrue);
    });

    test('a bot failure trips both the global notifier and the video', () {
      final service = _newService();
      service.recordFailure('vid3', const YtmException('BOT_CHALLENGE'));
      expect(service.isBotCoolingDown, isTrue);
      expect(service.botCooldownNotifier.value, isTrue);
      expect(service.isVideoCoolingDown('vid3'), isTrue);

      service.debugClearBotCooldown();
      expect(service.isBotCoolingDown, isFalse);
      expect(service.botCooldownNotifier.value, isFalse);
      expect(service.isVideoCoolingDown('vid3'), isFalse);
    });

    test('an IP block uses the longer cooldown but clears the same way', () {
      final service = _newService();
      service.recordFailure('vid4', const YtmException('IP_BLOCKED'));
      expect(service.isBotCoolingDown, isTrue);
      expect(service.breakerMetrics()['failures'], isA<Map>());
      service.debugClearBotCooldown('vid4');
      expect(service.isBotCoolingDown, isFalse);
    });

    test('onAuthExpired emits', () async {
      final service = _newService();
      final events = <void>[];
      final subscription = service.onAuthExpired.listen(events.add);
      service.notifyAuthExpired();
      await pumpEventQueue();
      expect(events, hasLength(1));
      await subscription.cancel();
    });
  });

  group('_guard error mapping through search', () {
    test('a platform signal detail beats a generic error code', () async {
      final service = _newService();
      channelHandler = (call) async => throw PlatformException(
            code: 'YTM_GENERIC',
            message: 'something',
            details: {'signal': 'PO_TOKEN_INVALID', 'traceId': 'trace-1'},
          );

      await expectLater(
        service.search('query'),
        throwsA(isA<YtmException>()
            .having((e) => e.code, 'code', 'PO_TOKEN_INVALID')
            .having((e) => e.traceId, 'traceId', 'trace-1')),
      );
    });

    test('a 429 code feeds the shared rate limiter', () async {
      final service = _newService();
      channelHandler = (call) async => throw PlatformException(code: 'YTM_429');

      await expectLater(service.search('query'), throwsA(isA<YtmException>()));
      expect(YtmRateLimiter.shared.isCoolingDown, isTrue);
    });

    test('LOGIN_REQUIRED notifies the auth-expiry stream', () async {
      final service = _newService();
      channelHandler =
          (call) async => throw PlatformException(code: 'LOGIN_REQUIRED');
      final events = <void>[];
      final subscription = service.onAuthExpired.listen(events.add);

      await expectLater(service.search('query'), throwsA(isA<YtmException>()));
      await pumpEventQueue();
      expect(events, hasLength(1));
      await subscription.cancel();
    });

    test('a missing plugin becomes YTM_UNSUPPORTED after a backoff', () async {
      final service = _newService();
      // No handler at all is what actually produces MissingPluginException.
      _mockChannel(null);
      await expectLater(
        service.search('query'),
        throwsA(isA<YtmException>()
            .having((e) => e.code, 'code', 'YTM_UNSUPPORTED')),
      );
    });
  });

  group('search wrappers', () {
    test('searchContinuation trims, parses and degrades to empty', () async {
      final service = _newService();
      channelHandler = (call) async => [_resultRow()];
      final tracks = await service.searchContinuation('  token  ');
      expect(tracks.single.videoId, 'dQw4w9WgXcQ');
      expect(
          channelCalls.last.arguments, {'continuation': 'token', 'limit': 30});

      expect(await service.searchContinuation('   '), isEmpty);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.searchContinuation('token'), isEmpty);
    });

    test('trending parses channel rows', () async {
      final service = _newService();
      channelHandler = (call) async => [_resultRow(videoId: 'trending001')];
      final tracks = await service.trending();
      expect(tracks.single.videoId, 'trending001');
      expect(channelCalls.last.method, 'trending');
    });

    test('getCharts parses a non-empty answer', () async {
      final service = _newService();
      channelHandler =
          (call) async => call.method == 'getCharts' ? [_resultRow()] : null;
      expect((await service.getCharts()).single.videoId, 'dQw4w9WgXcQ');
    });

    test('getCharts falls back to trending on an empty or failed answer',
        () async {
      final service = _newService();
      channelHandler = (call) async =>
          call.method == 'trending' ? [_resultRow(videoId: 'trending002')] : [];
      expect((await service.getCharts()).single.videoId, 'trending002');

      channelHandler = (call) async {
        if (call.method == 'getCharts') throw PlatformException(code: 'x');
        if (call.method == 'trending') return [_resultRow(videoId: 'trend003')];
        return null;
      };
      expect((await service.getCharts()).single.videoId, 'trend003');
    });

    test('getMoods returns parsed rows or empty', () async {
      final service = _newService();
      channelHandler = (call) async => [_resultRow(videoId: 'moods000001')];
      expect((await service.getMoods()).single.videoId, 'moods000001');

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.getMoods(), isEmpty);
    });
  });

  group('getPlaylistTracks', () {
    test('prefers the registered account service', () async {
      final account = MockYtmAccountService();
      when(() => account
              .fetchPlaylistTracks(any(), maxTracks: any(named: 'maxTracks')))
          .thenAnswer((_) async => [
                const YtmTrack(
                  videoId: 'account0001',
                  title: 'From Account',
                  artist: 'A',
                  duration: Duration.zero,
                ),
              ]);
      getIt.registerSingleton<YtmAccountService>(account);

      final tracks = await _newService().getPlaylistTracks('PLabc');
      expect(tracks.single.videoId, 'account0001');
      expect(channelCalls, isEmpty);
    });

    test('falls through to the native extractor when the account is empty',
        () async {
      final account = MockYtmAccountService();
      when(() => account.fetchPlaylistTracks(any(),
              maxTracks: any(named: 'maxTracks')))
          .thenAnswer((_) async => const []);
      getIt.registerSingleton<YtmAccountService>(account);

      channelHandler = (call) async => call.method == 'getPlaylist'
          ? {
              'tracks': [_streamRow()]
            }
          : null;
      final tracks = await _newService().getPlaylistTracks('PLabc');
      expect(tracks.single.videoId, 'dQw4w9WgXcQ');
    });

    test('maps liked-songs aliases to the native LL playlist', () async {
      channelHandler = (call) async => call.method == 'getPlaylist'
          ? {
              'tracks': [_streamRow()]
            }
          : null;
      await _newService().getPlaylistTracks('LM');
      expect(channelCalls.last.arguments, {'url': 'LL', 'limit': 100});
    });

    test('blank input is empty and a native failure degrades gracefully',
        () async {
      final service = _newService();
      expect(await service.getPlaylistTracks('   '), isEmpty);

      channelHandler = (call) async => throw PlatformException(code: 'x');
      expect(await service.getPlaylistTracks('PLabc'), isEmpty);
    });
  });

  group('resolveStream engine selection', () {
    test('a valid URL-cache entry is served without touching the channel',
        () async {
      final cache = YtmUrlCache.withClock(FakeClock(DateTime.now()));
      getIt.registerSingleton<YtmUrlCache>(cache);
      cache.putStream(_cachedStream(videoId: 'cachedvid01'), quality: 'high');

      final stream = await _newService().resolveStream('cachedvid01');
      expect(stream.url, contains('cache.example'));
      expect(channelCalls, isEmpty);
    });

    test('forceRefresh invalidates the cache and resolves natively', () async {
      final cache = YtmUrlCache.withClock(FakeClock(DateTime.now()));
      getIt.registerSingleton<YtmUrlCache>(cache);
      cache.putStream(_cachedStream(videoId: 'freshvid001'));
      expect(cache.get('freshvid001')!.url, contains('cache.example'));

      channelHandler = (call) async => call.method == 'resolveStream'
          ? _streamRow(videoId: 'freshvid001')
          : null;
      final stream =
          await _newService().resolveStream('freshvid001', forceRefresh: true);
      expect(stream.url, 'https://example.com/stream.m4a');
      // The fresh resolve re-caches the new URL under the same key.
      expect(cache.get('freshvid001')!.url, 'https://example.com/stream.m4a');
    });

    test('Tier-2.5 re-mints a rejected poToken and retries once', () async {
      var nativeCalls = 0;
      channelHandler = (call) async {
        switch (call.method) {
          case 'resolveStream':
            nativeCalls++;
            if (nativeCalls == 1) {
              throw PlatformException(code: 'PO_TOKEN_INVALID');
            }
            return _streamRow();
          case 'ensurePoTokenReady':
            return true;
          default:
            return null;
        }
      };

      final stream = await _newService().resolveStream('dQw4w9WgXcQ');
      expect(stream.url, 'https://example.com/stream.m4a');
      expect(nativeCalls, 2);
      expect(channelCalls.map((c) => c.method),
          containsAll(['invalidatePoToken', 'ensurePoTokenReady']));
    });

    test('inside a bot cooldown the native tier is not re-run', () async {
      var nativeCalls = 0;
      channelHandler = (call) async {
        if (call.method == 'resolveStream') {
          nativeCalls++;
          throw PlatformException(code: 'BOT_CHALLENGE');
        }
        return null;
      };
      final service = _newService();

      await expectLater(
        service.resolveStream('dQw4w9WgXcQ'),
        throwsA(
            isA<YtmException>().having((e) => e.code, 'code', 'BOT_CHALLENGE')),
      );
      await expectLater(
        service.resolveStream('dQw4w9WgXcQ'),
        throwsA(isA<YtmException>()),
      );
      expect(nativeCalls, 1,
          reason: 'the cooldown must prevent a second full native chain');
    });

    test('the pure-Dart client fallback parses adaptive formats', () async {
      channelHandler = (call) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_playerBody(
            status: 'OK',
            adaptive: [
              _audioFormat(bitrate: 64000, url: 'https://x/low.m4a'),
              _audioFormat(bitrate: 128000, url: 'https://x/mid.m4a'),
              _audioFormat(bitrate: 320000, url: 'https://x/high.m4a'),
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final stream = await service.resolveStream('dQw4w9WgXcQ');
      expect(stream.url, 'https://x/high.m4a');
      expect(stream.bitrateKbps, 320);
    });

    test('the Dart fallback reads non-adaptive formats as a backstop',
        () async {
      channelHandler = (call) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_playerBody(
            status: 'OK',
            formats: [
              _audioFormat(bitrate: 96000, url: 'https://x/formats.m4a'),
            ],
          )),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final stream = await service.resolveStream('dQw4w9WgXcQ');
      expect(stream.url, 'https://x/formats.m4a');
    });

    test('all engines failing surfaces YTM_FAILED', () async {
      channelHandler = (call) async => null;
      final service = _newService();
      service.debugHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode(_playerBody(status: 'LOGIN_REQUIRED')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await expectLater(
        service.resolveStream('dQw4w9WgXcQ'),
        throwsA(
            isA<YtmException>().having((e) => e.code, 'code', 'YTM_FAILED')),
      );
    });
  });

  group('handleNetworkChange', () {
    test('clears every route-pinned cache and the native network caches',
        () async {
      final urlCache = YtmUrlCache.withClock(FakeClock(DateTime(2026)));
      getIt.registerSingleton<YtmUrlCache>(urlCache);
      urlCache.putStream(_cachedStream(videoId: 'netchange01'));
      final browse = MockYtmBrowseService();
      when(() => browse.clearCache()).thenReturn(null);
      getIt.registerSingleton<YtmBrowseService>(browse);

      YtmRateLimiter.shared.onRateLimited(30);
      expect(YtmRateLimiter.shared.isCoolingDown, isTrue);

      await _newService().handleNetworkChange();

      expect(urlCache.get('netchange01'), isNull);
      verify(() => browse.clearCache()).called(1);
      expect(YtmRateLimiter.shared.isCoolingDown, isFalse);
      expect(channelCalls.map((c) => c.method), contains('clearNetworkCaches'));
    });
  });
}
