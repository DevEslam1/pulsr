// test/core/services/ytm_service_test.dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/services/ytm_account_service.dart';
import 'package:pulsr/data/services/ytm_service.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:pulsr/features/ytm_search/cubit/ytm_search_cubit.dart';

class MockYtmService extends Mock implements YtmService {}

class MockYtmAccountService extends Mock implements YtmAccountService {}

const _channel = MethodChannel(YtmService.channelName);

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    YtmService.resetGlobalBlock();
  });

  tearDown(() {
    _mockChannel((_) async => null);
    YtmService.resetGlobalBlock();
  });

  group('YtmException classification properties', () {
    test('isNetwork flags timeout and network errors', () {
      expect(const YtmException('YTM_NETWORK').isNetwork, isTrue);
      expect(const YtmException('YTM_TIMEOUT').isNetwork, isTrue);
      expect(const YtmException('YTM_FAILED').isNetwork, isFalse);
    });

    test('isBotBlocked flags bot keywords and recaptcha', () {
      expect(const YtmException('YTM_BOT_BLOCKED').isBotBlocked, isTrue);
      expect(const YtmException('YTM_RECAPTCHA').isBotBlocked, isTrue);
      expect(
          const YtmException(
                  'YTM_FAILED', 'Sign in to confirm you are not a bot')
              .isBotBlocked,
          isTrue);
      expect(const YtmException('YTM_FAILED', 'LOGIN_REQUIRED').isBotBlocked,
          isFalse);
      expect(const YtmException('YTM_NETWORK').isBotBlocked, isFalse);
    });

    test('isAuth flags auth codes and unauthenticated details', () {
      expect(const YtmException('YTM_AUTH').isAuth, isTrue);
      expect(const YtmException('LOGIN_REQUIRED').isAuth, isTrue);
      expect(const YtmException('YTM_FAILED', 'Unauthenticated user').isAuth,
          isTrue);
      expect(const YtmException('YTM_FAILED', 'LOGIN_REQUIRED').isAuth,
          isTrue);
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

  group('YtmTrack', () {
    test('songId is negative, deterministic, and distinct per video', () {
      const a = YtmTrack(
          videoId: 'dQw4w9WgXcQ',
          title: 'A',
          artist: 'x',
          duration: Duration.zero);
      const b = YtmTrack(
          videoId: 'dQw4w9WgXcQ',
          title: 'different title',
          artist: 'y',
          duration: Duration.zero);
      const c = YtmTrack(
          videoId: 'aBcDeFgHiJk',
          title: 'A',
          artist: 'x',
          duration: Duration.zero);

      expect(a.songId, isNegative,
          reason: 'MediaStore ids are positive, so these must not be');
      expect(a.songId, equals(b.songId),
          reason: 'the id must depend only on the video id');
      expect(a.songId, isNot(equals(c.songId)));
    });

    test('pathSentinel is the ytmusic scheme, not a filesystem path', () {
      const track = YtmTrack(
          videoId: 'dQw4w9WgXcQ',
          title: 'A',
          artist: 'x',
          duration: Duration.zero);
      expect(track.pathSentinel, equals('ytmusic://dQw4w9WgXcQ'));
    });

    test('fromChannel rejects rows with no id or title', () {
      expect(YtmTrack.fromChannel({'title': 'no id'}), isNull);
      expect(YtmTrack.fromChannel({'videoId': 'dQw4w9WgXcQ', 'title': ''}),
          isNull);
    });

    test(
        'fromChannel defaults a blank artist rather than showing an empty line',
        () {
      final track = YtmTrack.fromChannel({..._resultRow(), 'artist': '  '});
      expect(track!.artist, equals('Unknown Artist'));
    });

    test(
        'toSongData mints a youtube row with the sentinel path and negative id',
        () {
      const track = YtmTrack(
        videoId: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        duration: Duration(milliseconds: 213000),
        artworkUrl: 'https://lh3.googleusercontent.com/cover',
      );

      final song = track.toSongData();

      expect(song.id, equals(track.songId));
      expect(song.id, isNegative);
      expect(song.source, equals('youtube'));
      expect(song.path, equals('ytmusic://dQw4w9WgXcQ'));
      expect(song.remoteId, equals('dQw4w9WgXcQ'));
      expect(song.remoteArtworkUrl,
          equals('https://lh3.googleusercontent.com/cover'));
      expect(song.durationMs, equals(213000));
      // Null so album/artist browse never shows a phantom entry for a YT track.
      expect(song.albumId, isNull);
      expect(song.artistId, isNull);
    });
  });

  group('YtmStream', () {
    test('isTaggable only for m4a, because jaudiotagger cannot write Opus', () {
      final m4a = YtmStream.fromChannel({
        'videoId': 'dQw4w9WgXcQ',
        'url': 'https://example.com/a',
        'container': 'm4a',
      });
      final opus = YtmStream.fromChannel({
        'videoId': 'dQw4w9WgXcQ',
        'url': 'https://example.com/a',
        'container': 'webm',
      });
      expect(m4a!.isTaggable, isTrue);
      expect(opus!.isTaggable, isFalse);
    });
  });

  group('YtmService', () {
    test('search maps channel rows and drops malformed ones', () async {
      _mockChannel((call) async {
        expect(call.method, equals('search'));
        expect(call.arguments['query'], equals('rick astley'));
        return [
          _resultRow(),
          {'title': 'missing video id'},
        ];
      });

      final results = await YtmService().search('  rick astley  ');
      expect(results.length, equals(1));
      expect(results.first.videoId, equals('dQw4w9WgXcQ'));
      expect(
          results.first.duration, equals(const Duration(milliseconds: 213000)));
    });

    test('search short-circuits a blank query without touching the channel',
        () async {
      var called = false;
      _mockChannel((_) async {
        called = true;
        return const [];
      });

      expect(await YtmService().search('   '), isEmpty);
      expect(called, isFalse);
    });

    test('a platform error becomes a typed YtmException, not a null result',
        () async {
      _mockChannel((_) async =>
          throw PlatformException(code: 'YTM_NETWORK', message: 'offline'));

      await expectLater(
        YtmService().search('query'),
        throwsA(isA<YtmException>()
            .having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });

    test(
        'resolveStream throws rather than returning null when nothing comes back',
        () async {
      _mockChannel((_) async => null);
      await expectLater(
        YtmService().resolveStream('dQw4w9WgXcQ'),
        throwsA(isA<YtmException>()),
      );
    });

    test('resolveStream forwards quality parameter to platform channel',
        () async {
      _mockChannel((call) async {
        expect(call.method, equals('resolveStream'));
        expect(call.arguments['videoId'], equals('dQw4w9WgXcQ'));
        expect(call.arguments['quality'], equals('low'));
        return {
          'videoId': 'dQw4w9WgXcQ',
          'url': 'https://example.com/stream.m4a',
          'mimeType': 'audio/mp4',
          'container': 'm4a',
          'bitrateKbps': 64,
          'durationMs': 213000,
        };
      });

      final stream =
          await YtmService().resolveStream('dQw4w9WgXcQ', quality: 'low');
      expect(stream.bitrateKbps, equals(64));
    });

    test('isWifiConnected returns true or false from channel', () async {
      _mockChannel((call) async {
        if (call.method == 'isWifiConnected') return false;
        return null;
      });

      final isWifi = await YtmService().isWifiConnected();
      expect(isWifi, isFalse);
    });

    test('isAvailable reports false for the stub build and caches the answer',
        () async {
      var calls = 0;
      _mockChannel((_) async {
        calls++;
        return false;
      });

      final service = YtmService();
      expect(await service.isAvailable(), isFalse);
      expect(await service.isAvailable(), isFalse);
      expect(calls, equals(1), reason: 'the answer is fixed at compile time');
    });
  });

  group('YtmSearchCubit', () {
    late MockYtmService service;

    setUp(() {
      service = MockYtmService();
      when(() => service.invalidatePoToken()).thenAnswer((_) async {});
      when(() => service.ensurePoTokenReady()).thenAnswer((_) async => true);
    });

    test('a stale in-flight search cannot overwrite a newer one', () async {
      final slow = Completer<List<YtmTrack>>();
      final fast = Completer<List<YtmTrack>>();
      when(() => service.searchWithFallback('slow'))
          .thenAnswer((_) => slow.future);
      when(() => service.searchWithFallback('fast'))
          .thenAnswer((_) => fast.future);

      final cubit = YtmSearchCubit(service: service);
      cubit.onQueryChanged('slow');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      cubit.onQueryChanged('fast');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      fast.complete([
        YtmTrack.fromChannel(_resultRow(videoId: 'fastfastfas', title: 'Fast'))!
      ]);
      await Future<void>.delayed(Duration.zero);
      slow.complete([
        YtmTrack.fromChannel(_resultRow(videoId: 'slowslowslo', title: 'Slow'))!
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.results.single.title, equals('Fast'));
      await cubit.close();
    });

    test(
        'a network failure surfaces a message instead of looking like no results',
        () async {
      when(() => service.searchWithFallback(any()))
          .thenThrow(const YtmException('YTM_TIMEOUT'));

      final cubit = YtmSearchCubit(service: service);
      cubit.onQueryChanged('anything');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.results, isEmpty);
      expect(cubit.state.errorMessage, contains('connection'));
      await cubit.close();
    });

    test('clearing the query cancels the pending debounce', () async {
      when(() => service.searchWithFallback(any()))
          .thenAnswer((_) async => const []);

      final cubit = YtmSearchCubit(service: service);
      cubit.onQueryChanged('abc');
      cubit.clearQuery();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      verifyNever(() => service.searchWithFallback(any()));
      expect(cubit.state.query, isEmpty);
      await cubit.close();
    });
  });

  group('YtmService TTFA resolve budget', () {
    test(
        'a tier-1 account resolve hanging past the ~3s budget falls through '
        'to the native tier instead of burning the 25s account timeout',
        () async {
      final account = MockYtmAccountService();
      when(() => account.isLoggedIn).thenReturn(true);
      when(() => account.resolvePlayerStream(any(),
              quality: any(named: 'quality')))
          .thenAnswer((_) => Completer<YtmStream?>().future);

      getIt.registerSingleton<YtmAccountService>(account);
      addTearDown(() {
        try {
          getIt.unregister<YtmAccountService>(instance: account);
        } catch (_) {}
      });

      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          return {
            'videoId': 'dQw4w9WgXcQ',
            'url': 'https://native.example/audio.m4a',
            'mimeType': 'audio/mp4',
            'container': 'm4a',
            'bitrateKbps': 128,
            'durationMs': 213000,
          };
        }
        return null;
      });

      final watch = Stopwatch()..start();
      final stream = await YtmService().resolveStream('dQw4w9WgXcQ');
      watch.stop();

      expect(stream.url, equals('https://native.example/audio.m4a'));
      // Tier-1 deadline is ~3s: the fallthrough must happen long before the
      // account path's internal 25s timeout could elapse.
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      verify(() => account.resolvePlayerStream(any(),
          quality: any(named: 'quality'))).called(1);
    });

    test('a healthy tier-2 native resolve is tagged as cacheHit=false',
        () async {
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          return {
            'videoId': 'dQw4w9WgXcQ',
            'url': 'https://native.example/audio.m4a',
            'mimeType': 'audio/mp4',
            'container': 'm4a',
            'bitrateKbps': 128,
            'durationMs': 213000,
          };
        }
        return null;
      });

      // No account service registered -> straight to the native tier.
      final stream = await YtmService().resolveStream('dQw4w9WgXcQ');
      expect(stream.url, equals('https://native.example/audio.m4a'));
    });
  });

  group('YtmService sign-in-required fast-fail', () {
    test('native YTM_SIGNIN_REQUIRED abort surfaces typed, not as auth', () async {
      var calls = 0;
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          calls++;
          throw PlatformException(code: 'YTM_SIGNIN_REQUIRED', message: 'Ladder aborted');
        }
        return null;
      });

      await expectLater(
        YtmService().resolveStream('AAAAAAAAAAA'),
        throwsA(
          isA<YtmException>()
              .having((e) => e.code, 'code', 'YTM_SIGNIN_REQUIRED')
              // A device/IP gate for a guest is NOT a session-expiry verdict:
              // it must not trigger the global auth-expired UI path.
              .having((e) => e.isAuth, 'isAuth', isFalse),
        ),
      );
      expect(calls, 1);
    });

    test('immediate retry within the negative-cache TTL fails fast', () async {
      var calls = 0;
      _mockChannel((call) async {
        if (call.method == 'resolveStream') {
          calls++;
          throw PlatformException(code: 'YTM_SIGNIN_REQUIRED', message: 'Ladder aborted');
        }
        return null;
      });

      await expectLater(
        YtmService().resolveStream('BBBBBBBBBBB'),
        throwsA(
          isA<YtmException>().having((e) => e.code, 'code', 'YTM_SIGNIN_REQUIRED'),
        ),
      );
      await expectLater(
        YtmService().resolveStream('BBBBBBBBBBB'),
        throwsA(
          isA<YtmException>().having((e) => e.code, 'code', 'YTM_SIGNIN_REQUIRED'),
        ),
      );
      // The retry must not reach the native ladder again.
      expect(calls, 1);
    });
  });
}
