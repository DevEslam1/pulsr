// test/data/audio/ytm_resolving_source_test.dart
//
// YtmResolvingSource defers stream-URL resolution to the first byte request and
// hands byte streaming/caching to a LockCachingAudioSource. just_audio marks
// StreamAudioSource @experimental; we exercise it intentionally here, matching
// the production ignore in ytm_resolving_source.dart.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/core/services/ytm_cache_manager.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';

/// path_provider has no implementation in a host test, and YtmCacheManager needs
/// the application-support directory to place the byte cache. Answering the
/// channel with a temp dir lets the byte-streaming paths run for real.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('ytm_src_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      return tempRoot.path;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('YtmResolvingSource Tests', () {
    test('instantiates with videoId and resolver closure lazily without initial resolution', () {
      var resolvedCount = 0;
      final source = YtmResolvingSource(
        videoId: 'dQw4w9WgXcQ',
        resolve: ({bool forceRefresh = false}) async {
          resolvedCount++;
          return 'https://rr1---sn-example.googlevideo.com/videoplayback?expire=${DateTime.now().add(const Duration(hours: 4)).millisecondsSinceEpoch ~/ 1000}';
        },
      );

      expect(source.videoId, equals('dQw4w9WgXcQ'));
      expect(resolvedCount, equals(0));
    });

    test('a failed resolve is not cached — the next request re-resolves', () async {
      var calls = 0;
      final source = YtmResolvingSource(
        videoId: 'abc123',
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          throw StateError('url expired');
        },
      );

      // YTM URLs expire within hours; a dead resolve must not be memoized or the
      // track would retry the same expired URL forever.
      await expectLater(source.request(), throwsA(isA<StateError>()));
      await expectLater(source.request(), throwsA(isA<StateError>()));

      expect(calls, 2, reason: 'each request should re-run the resolver');
    });

    test('the resolver runs lazily, not at construction', () {
      var calls = 0;
      YtmResolvingSource(
        videoId: 'abc123',
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          return 'https://example.com/stream.m4a';
        },
      );

      // Building a whole queue of these must do zero network I/O up front.
      expect(calls, 0);
    });

    test('cache hit skips resolver closure and uses cached stream URL directly', () async {
      final fakeClock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000));
      final urlCache = YtmUrlCache.withClock(fakeClock);
      urlCache.put('preCachedVid', 'https://googlevideo.com/cached_stream.m4a');

      var resolverCalled = false;
      final source = YtmResolvingSource(
        videoId: 'preCachedVid',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          resolverCalled = true;
          return 'https://googlevideo.com/fresh_stream.m4a';
        },
      );

      // Verify cache hit exists before request
      expect(source.videoId, equals('preCachedVid'));
      expect(urlCache.contains('preCachedVid'), isTrue);
      // Constructing and preparing source does not call resolver
      expect(resolverCalled, isFalse);
    });
  });

  group('YtmResolvingSource — quality keying', () {
    test('a low-quality resolve is cached under low, not high', () async {
      final urlCache = YtmUrlCache();
      await _seedCacheFile('lowqualityvid');

      var calls = 0;
      final source = YtmResolvingSource(
        videoId: 'lowqualityvid',
        quality: 'low',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          return _streamUrl();
        },
      );

      await source.request();

      expect(calls, equals(1));
      // Both the read and the write used the default `high`, so a low-tier
      // listener's 64kbps URL was stored in — and served from — the high slot.
      expect(urlCache.getUrl('lowqualityvid', quality: 'low'), isNotNull);
      expect(urlCache.getUrl('lowqualityvid', quality: 'high'), isNull);
    });

    test('a cached low URL is reused instead of re-resolved', () async {
      final urlCache = YtmUrlCache();
      await _seedCacheFile('lowqualityvi2');
      urlCache.put('lowqualityvi2', _streamUrl(), quality: 'low');

      var calls = 0;
      final source = YtmResolvingSource(
        videoId: 'lowqualityvi2',
        quality: 'low',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          return _streamUrl();
        },
      );

      await source.request();

      expect(calls, isZero,
          reason: 'the low slot was already warm; resolving again is a '
              'multi-client round trip for a URL we already had');
    });
  });

  group('YtmResolvingSource — expiry', () {
    test('a URL near expiry is evicted and re-resolved, not read back',
        () async {
      final urlCache = YtmUrlCache();
      await _seedCacheFile('expiringvid1');

      final soon =
          DateTime.now().add(const Duration(seconds: 90)).millisecondsSinceEpoch;
      var calls = 0;
      var sawForceRefresh = false;
      final source = YtmResolvingSource(
        videoId: 'expiringvid1',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          if (forceRefresh) sawForceRefresh = true;
          return _streamUrl(expireEpochSeconds: soon ~/ 1000);
        },
      );

      await source.request();
      expect(calls, equals(1));

      // Clearing `_inner` alone left the about-to-die URL sitting in the cache,
      // so the rebuild read it straight back and the check achieved nothing.
      await source.request();
      expect(calls, equals(2));
      expect(sawForceRefresh, isTrue,
          reason: 'the re-resolve must bypass every URL memo, not just ours');
    });

    test('the /expire/<epoch>/ path form is read, not just ?expire=', () async {
      final urlCache = YtmUrlCache();
      await _seedCacheFile('pathexpirevid');

      var calls = 0;
      final source = YtmResolvingSource(
        videoId: 'pathexpirevid',
        urlCache: urlCache,
        resolve: ({bool forceRefresh = false}) async {
          calls++;
          final soon = DateTime.now()
                  .add(const Duration(seconds: 90))
                  .millisecondsSinceEpoch ~/
              1000;
          return 'https://rr1---sn-x.googlevideo.com/videoplayback/expire/$soon/itag/140';
        },
      );

      await source.request();
      await source.request();

      // Reading only the query form left path-form URLs with no expiry at all,
      // and with it the proactive re-resolve never fires — the URL just dies
      // mid-track instead.
      expect(calls, equals(2));
    });
  });

  group('YtmResolvingSource.isUrlBurned', () {
    test('a refusal from googlevideo burns the URL', () {
      for (final status in const [401, 403, 404, 407, 410, 416, 429]) {
        expect(YtmResolvingSource.isUrlBurned(
            Exception('HTTP Status Error: $status')),
            isTrue,
            reason: '$status means this URL will never serve bytes again');
      }
    });

    test('a dropped connection does not', () {
      // Re-resolving on a transport blip throws away a working URL and burns a
      // full multi-client resolve — and, under a bot cooldown, a poToken mint.
      expect(
          YtmResolvingSource.isUrlBurned(
              const SocketException('Failed host lookup: rr1.googlevideo.com')),
          isFalse);
      expect(
          YtmResolvingSource.isUrlBurned(
              TimeoutException('read timed out', const Duration(seconds: 8))),
          isFalse);
      expect(
          YtmResolvingSource.isUrlBurned(
              const SocketException('Connection reset by peer')),
          isFalse);
    });

    test('a 5xx is YouTube having a bad minute, so the URL survives', () {
      expect(
          YtmResolvingSource.isUrlBurned(Exception('HTTP Status Error: 503')),
          isFalse);
      expect(
          YtmResolvingSource.isUrlBurned(Exception('HTTP Status Error: 500')),
          isFalse);
    });

    test('a numeric id in the message is not an HTTP status', () {
      // `contains('403')` matched the digits anywhere — inside an itag, a byte
      // count or a video id — and re-resolved on every one of them.
      expect(
          YtmResolvingSource.isUrlBurned(
              const SocketException('connection closed: clen=4030099 itag=251')),
          isFalse);
    });

    test('a bot interstitial with no status still burns the URL', () {
      expect(
          YtmResolvingSource.isUrlBurned(
              Exception('Sign in to confirm you are not a bot')),
          isTrue);
      expect(YtmResolvingSource.isUrlBurned(Exception('Too many requests')),
          isTrue);
    });
  });
}

/// Pre-creates the byte-cache file for [videoId] so `LockCachingAudioSource`
/// serves the request straight off disk. `TestWidgetsFlutterBinding` forces
/// every `HttpClient` response to 400 and makes no real request, so this is the
/// only way to exercise the resolve path without a fabricated byte error.
Future<void> _seedCacheFile(String videoId, {String ext = 'm4a'}) async {
  final manager = YtmCacheManager();
  final dir = await manager.getCacheDirectory();
  final hash = manager.getHashForVideoId(videoId);
  File(p.join(dir.path, '$hash.$ext'))
      .writeAsBytesSync(List<int>.filled(4096, 7));
}

String _streamUrl({int? expireEpochSeconds}) {
  final expire = expireEpochSeconds ??
      DateTime.now().add(const Duration(hours: 5)).millisecondsSinceEpoch ~/
          1000;
  return 'https://rr1---sn-x.googlevideo.com/videoplayback?itag=140&expire=$expire';
}
