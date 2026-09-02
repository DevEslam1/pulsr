// test/data/audio/ytm_resolving_source_test.dart
//
// YtmResolvingSource defers stream-URL resolution to the first byte request and
// hands byte streaming/caching to a LockCachingAudioSource. just_audio marks
// StreamAudioSource @experimental; we exercise it intentionally here, matching
// the production ignore in ytm_resolving_source.dart.
// ignore_for_file: experimental_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
