// test/core/services/ytm_url_cache_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

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
      expect(entry!.expiresAt,
          equals(clock.now().add(const Duration(minutes: 55))));

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

    test('restore() caps disk file read at 2 MB and ignores larger/corrupt files',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ytm_url_cache_restore_');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_pathProviderChannel, null);
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        return tempDir.path;
      });

      final futureExpiryMs =
          clock.now().add(const Duration(hours: 2)).millisecondsSinceEpoch;
      final oversizedPayload = jsonEncode([
        {
          'videoId': 'vidHuge',
          'url': 'https://googlevideo.com/huge',
          'quality': 'high',
          'expiresAt': futureExpiryMs,
        },
        {
          'videoId': 'vidPad',
          'url': 'https://googlevideo.com/${'a' * (2 * 1024 * 1024 + 512)}',
          'quality': 'high',
          'expiresAt': futureExpiryMs,
        },
      ]);
      final file = File('${tempDir.path}/ytm_url_cache_v1.json')
        ..writeAsStringSync(oversizedPayload);
      expect(file.lengthSync(), greaterThan(2 * 1024 * 1024));

      await cache.restore();
      expect(cache.length, 0);

      // Corrupt file under 2 MB is also safely ignored.
      final corruptCache = YtmUrlCache.withClock(clock);
      file.writeAsStringSync('{not valid json');
      await corruptCache.restore();
      expect(corruptCache.length, 0);
    });
  });

  group('YtmUrlCache — verification stamps', () {
    late FakeClock clock;
    late YtmUrlCache cache;

    setUp(() {
      clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000000));
      cache = YtmUrlCache.withClock(clock,
          capacity: 8, ttl: const Duration(hours: 4));
    });

    test('a fresh put() is unverified until markVerified', () {
      cache.put('vid1', 'https://x/a');
      expect(cache.get('vid1')!.isVerified, isFalse);
      expect(cache.isVerified('vid1'), isFalse);

      cache.markVerified('vid1');
      expect(cache.get('vid1')!.isVerified, isTrue);
      expect(cache.isVerified('vid1'), isTrue);
    });

    test('put(verifiedAt:) records the stamp directly', () {
      final at = clock.now().subtract(const Duration(seconds: 20));
      cache.put('vid1', 'https://x/a', verifiedAt: at);

      expect(cache.get('vid1')!.verifiedAt, at);
      expect(cache.isVerified('vid1'), isTrue);
    });

    test('a stamp staler than maxAge no longer counts as verified', () {
      cache.put('vid1', 'https://x/a');
      cache.markVerified('vid1');

      clock.advance(const Duration(seconds: 91));
      expect(cache.isVerified('vid1'), isFalse);
      expect(cache.isVerified('vid1', maxAge: const Duration(minutes: 5)),
          isTrue,
          reason: "the stamp is still there; only the caller's window moved");
    });

    test('isVerified is false for missing, expired and other-quality slots',
        () {
      expect(cache.isVerified('missing'), isFalse);

      cache.put('vid1', 'https://x/a', quality: 'low');
      cache.markVerified('vid1', quality: 'low');
      expect(cache.isVerified('vid1'), isFalse,
          reason: 'the high slot was never written');
      expect(cache.isVerified('vid1', quality: 'low'), isTrue);

      clock.advance(const Duration(hours: 5));
      expect(cache.isVerified('vid1', quality: 'low'), isFalse);
    });

    test('markVerified is a no-op for a key the cache does not hold', () {
      cache.markVerified('ghost');

      expect(cache.contains('ghost'), isFalse);
      expect(cache.length, 0);
    });

    test('verification survives a re-store of the same URL only', () {
      cache.put('vid1', 'https://x/a');
      cache.markVerified('vid1');

      cache.put('vid1', 'https://x/a', userAgent: 'UA');
      expect(cache.isVerified('vid1'), isTrue,
          reason: 'same URL and signature, so the probe result still holds');

      cache.put('vid1', 'https://x/b');
      expect(cache.isVerified('vid1'), isFalse,
          reason: 'a different URL carries a different signature');
    });

    test('putStream stamps a fresh mint as verified for the probe window', () {
      cache.put('vid1', 'https://x/a', verifiedAt: clock.now());
      expect(cache.isVerified('vid1'), isTrue);

      cache.putStream(YtmStream(
        videoId: 'vid1',
        url: 'https://x/b',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: const Duration(minutes: 3),
        title: 'T',
        artist: 'A',
      ));

      // A URL the resolver just minted skips the pre-flight probe: probing it
      // added a full round trip (up to the 2 s budget) to every first play of
      // a pre-resolved track. A dead signature still costs one 403 + the
      // source's single re-resolve, the same remedy a failed probe triggers.
      expect(cache.isVerified('vid1'), isTrue,
          reason: 'fresh mint is the freshest URL the app can hold');

      clock.advance(const Duration(minutes: 5));
      expect(cache.isVerified('vid1'), isFalse,
          reason: 'outside the window the entry is unproven again');
    });
  });
}
