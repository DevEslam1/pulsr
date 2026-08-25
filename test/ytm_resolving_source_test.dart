// test/ytm_resolving_source_test.dart
//
// YtmResolvingSource defers stream-URL resolution to the first byte request and
// hands byte streaming/caching to a LockCachingAudioSource. just_audio marks
// StreamAudioSource @experimental; we exercise it intentionally here, matching
// the production ignore in ytm_resolving_source.dart.
// ignore_for_file: experimental_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/ytm_resolving_source.dart';

void main() {
  group('YtmResolvingSource', () {
    test('a failed resolve is not cached — the next request re-resolves',
        () async {
      var calls = 0;
      final source = YtmResolvingSource(
        videoId: 'abc123',
        resolve: () async {
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
        resolve: () async {
          calls++;
          return 'https://example.com/stream.m4a';
        },
      );

      // Building a whole queue of these must do zero network I/O up front.
      expect(calls, 0);
    });
  });
}
