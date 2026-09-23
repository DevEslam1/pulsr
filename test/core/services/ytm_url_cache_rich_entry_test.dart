// test/core/services/ytm_url_cache_rich_entry_test.dart
//
// F1 regression. The lazy playback source (`YtmResolvingSource._createInner`)
// writes a URL-only entry with `put()` immediately after
// `YtmService.resolveStream` stored the real container/MIME/bitrate/duration
// through `putStream()`. Both use the same `videoId:quality` key, so the rich
// record used to be replaced by a URL-only one — and a later cache hit then
// rebuilt the stream with `duration: Duration.zero` and a container guessed
// from the URL, defeating the duration backfill in the download path.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

const _url1 = 'https://rr1---sn-x.googlevideo.com/videoplayback?id=abc';
const _url2 = 'https://rr2---sn-y.googlevideo.com/videoplayback?id=zzz';

YtmStream _stream({String url = _url1}) => YtmStream(
      videoId: 'vidRich',
      url: url,
      mimeType: 'audio/webm',
      container: 'webm',
      bitrateKbps: 256,
      duration: const Duration(minutes: 4, seconds: 33),
      title: 'Title',
      artist: 'Artist',
      userAgent: 'UA',
      expiresAt:
          DateTime.now().add(const Duration(hours: 4)).millisecondsSinceEpoch,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmUrlCache - rich entry survives a stream-less re-put (F1)', () {
    late FakeClock clock;
    late YtmUrlCache cache;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000000));
      cache = YtmUrlCache.withClock(clock,
          capacity: 8, ttl: const Duration(hours: 4));
    });

    test('a later plain put() for the same url keeps the stored stream', () {
      final stream = _stream();
      cache.putStream(stream, quality: 'high');
      expect(cache.getStream('vidRich')!.duration,
          equals(const Duration(minutes: 4, seconds: 33)));

      // Exactly what `YtmResolvingSource._createInner` does right after the
      // resolver has already cached the rich entry.
      cache.put('vidRich', stream.url, quality: 'high', userAgent: 'UA');

      final after = cache.getStream('vidRich');
      expect(after, isNotNull);
      expect(after!.duration, equals(const Duration(minutes: 4, seconds: 33)));
      expect(after.container, equals('webm'));
      expect(after.bitrateKbps, equals(256));
      expect(after.mimeType, equals('audio/webm'));
    });

    test('a plain put() for a different url inherits the rich metadata with updated url',
        () {
      cache.putStream(_stream(), quality: 'high');
      cache.put('vidRich', _url2, quality: 'high');

      final entry = cache.get('vidRich');
      expect(entry, isNotNull);
      expect(entry!.url, equals(_url2));
      expect(entry.stream, isNotNull);
      expect(entry.stream!.url, equals(_url2));
      expect(entry.stream!.duration, equals(const Duration(minutes: 4, seconds: 33)));
      expect(entry.stream!.container, equals('webm'));
      expect(cache.getStream('vidRich')!.duration, equals(const Duration(minutes: 4, seconds: 33)));
    });

    test('the rich stream survives an LRU touch and a re-put', () {
      cache.putStream(_stream(), quality: 'high');
      cache.put('otherVideo1', _url2);
      cache.get('vidRich');
      cache.put('vidRich', _url1, quality: 'high');
      expect(cache.getStream('vidRich')!.duration.inMinutes, equals(4));
    });

    test('a quality-specific slot is not affected', () {
      cache.putStream(_stream(), quality: 'low');
      expect(cache.getStream('vidRich', quality: 'low')!.duration.inMinutes,
          equals(4));
      // The high slot was never written.
      expect(cache.getStream('vidRich', quality: 'high'), isNull);
    });
  });
}