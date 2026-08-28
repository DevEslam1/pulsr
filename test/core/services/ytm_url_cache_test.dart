// test/core/services/ytm_url_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YtmUrlCache — Task 2 Unit Tests', () {
    late FakeClock clock;
    late YtmUrlCache cache;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000000));
      cache = YtmUrlCache.withClock(
        clock,
        capacity: 3,
        ttl: const Duration(hours: 4),
      );
    });

    test('cache hit returns valid url and updates LRU position', () {
      cache.put('vid1', 'https://googlevideo.com/1', quality: 'high');
      expect(cache.contains('vid1'), isTrue);

      final entry = cache.get('vid1');
      expect(entry, isNotNull);
      expect(entry!.url, equals('https://googlevideo.com/1'));

      // Put more items to test LRU ordering
      cache.put('vid2', 'https://googlevideo.com/2');
      // Access vid1 again to make vid2 the LRU
      cache.get('vid1');
      cache.put('vid3', 'https://googlevideo.com/3');
      // Adding 4th item with capacity=3 should evict vid2, NOT vid1
      cache.put('vid4', 'https://googlevideo.com/4');

      expect(cache.get('vid1'), isNotNull);
      expect(cache.get('vid2'), isNull); // Evicted!
      expect(cache.get('vid3'), isNotNull);
      expect(cache.get('vid4'), isNotNull);
    });

    test('cache entries expire after configured TTL (4h)', () {
      cache.put('vid1', 'https://googlevideo.com/1');
      expect(cache.get('vid1'), isNotNull);

      // Advance clock by 3h 59m — still valid
      clock.advance(const Duration(hours: 3, minutes: 59));
      expect(cache.get('vid1'), isNotNull);

      // Advance past 4h — should expire
      clock.advance(const Duration(minutes: 2));
      expect(cache.get('vid1'), isNull);
      expect(cache.contains('vid1'), isFalse);
    });

    test('parses expire query parameter with safety margin', () {
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      // Stream expires in 60 minutes (3600 seconds)
      final urlWithExpire =
          'https://rr1---sn.googlevideo.com/videoplayback?expire=${nowSec + 3600}&id=xyz';

      cache.put('vidExp', urlWithExpire);
      final entry = cache.get('vidExp');
      expect(entry, isNotNull);

      // Expiry should be 3600 - 300 (5 min safety margin) = 3300s = 55 minutes from start
      expect(entry!.expiresAt, equals(clock.now().add(const Duration(minutes: 55))));

      // Advance by 54 minutes -> still valid
      clock.advance(const Duration(minutes: 54));
      expect(cache.get('vidExp'), isNotNull);

      // Advance past 55 minutes -> expired due to proactive margin
      clock.advance(const Duration(minutes: 2));
      expect(cache.get('vidExp'), isNull);
    });

    test('invalidate removes specific video or quality', () {
      cache.put('vid1', 'https://googlevideo.com/high', quality: 'high');
      cache.put('vid1', 'https://googlevideo.com/low', quality: 'low');
      cache.put('vid2', 'https://googlevideo.com/vid2');

      expect(cache.length, equals(3));

      // Invalidate specific quality
      cache.invalidate('vid1', quality: 'low');
      expect(cache.get('vid1', quality: 'low'), isNull);
      expect(cache.get('vid1', quality: 'high'), isNotNull);

      // Invalidate entire videoId
      cache.invalidate('vid1');
      expect(cache.get('vid1', quality: 'high'), isNull);
      expect(cache.get('vid2'), isNotNull);

      // Clear all
      cache.clear();
      expect(cache.length, equals(0));
    });

    test('LRU eviction capacity limit strictly maintained', () {
      final smallCache = YtmUrlCache.withClock(clock, capacity: 2);
      smallCache.put('a', 'http://a');
      smallCache.put('b', 'http://b');
      expect(smallCache.length, equals(2));

      smallCache.put('c', 'http://c');
      expect(smallCache.length, equals(2));
      expect(smallCache.get('a'), isNull);
      expect(smallCache.get('b'), isNotNull);
      expect(smallCache.get('c'), isNotNull);
    });

    test('Stale-While-Revalidate triggers background refresh callback in second half of TTL', () {
      cache.put('vidSWTR', 'https://googlevideo.com/swtr');
      bool refreshed = false;

      // Advance by 1h (age < 2h = ttl/2) -> fresh, no callback triggered
      clock.advance(const Duration(hours: 1));
      final freshEntry = cache.get('vidSWTR', onStaleRevalidate: (_) => refreshed = true);
      expect(freshEntry, isNotNull);
      expect(freshEntry!.isStaleWhileRevalidate(clock.now()), isFalse);
      expect(refreshed, isFalse);

      // Advance past 2h (age = 2h 30m >= ttl/2) -> SWTR window: returns entry AND triggers callback
      clock.advance(const Duration(hours: 1, minutes: 30));
      final swtrEntry = cache.get('vidSWTR', onStaleRevalidate: (vid) {
        expect(vid, equals('vidSWTR'));
        refreshed = true;
      });
      expect(swtrEntry, isNotNull);
      expect(swtrEntry!.isStaleWhileRevalidate(clock.now()), isTrue);
      expect(refreshed, isTrue);
    });

    test('evictDeadUrl blacklists dead 403 URL and prevents re-serving', () {
      cache.put('vidDead', 'https://googlevideo.com/dead');
      expect(cache.get('vidDead'), isNotNull);

      // Evict dead URL
      cache.evictDeadUrl('vidDead', 'https://googlevideo.com/dead');
      expect(cache.get('vidDead'), isNull);

      // Even if put back with old dead URL, get rejects it until fresh distinct URL
      cache.put('vidDead', 'https://googlevideo.com/fresh');
      expect(cache.get('vidDead'), isNotNull);
      expect(cache.getUrl('vidDead'), equals('https://googlevideo.com/fresh'));
    });
  });
}
