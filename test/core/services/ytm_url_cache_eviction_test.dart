// test/core/services/ytm_url_cache_eviction_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/ytm_url_cache.dart';
import 'package:pulsr/core/telemetry/clock.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
const _diskFileName = 'ytm_url_cache_v1.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late Directory testDir;
  late FakeClock clock;
  late YtmUrlCache cache;

  setUpAll(() {
    tempRoot = Directory.systemTemp.createTempSync('ytm_url_cache_test');
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    // A fresh directory per test: debounced persist timers from earlier tests
    // can still be in flight and must not clobber this test's cache file.
    testDir = Directory.systemTemp.createTempSync('run');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      return testDir.path;
    });
    final diskFile = File('${testDir.path}/$_diskFileName');
    if (diskFile.existsSync()) diskFile.deleteSync();

    clock = FakeClock(DateTime.fromMillisecondsSinceEpoch(1000000000));
    cache = YtmUrlCache.withClock(clock,
        capacity: 8, ttl: const Duration(hours: 4));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  Future<String?> readDiskEventually(File file,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) {
        final raw = file.readAsStringSync();
        if (raw.isNotEmpty) {
          try {
            jsonDecode(raw);
            return raw;
          } catch (_) {
            // Mid-write or still-empty content; keep polling.
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  group('YtmUrlCacheEntry', () {
    final fetched = DateTime.fromMillisecondsSinceEpoch(1000);
    final expires = DateTime.fromMillisecondsSinceEpoch(2000);

    YtmUrlCacheEntry entry({YtmStream? stream}) => YtmUrlCacheEntry(
          videoId: 'vid1',
          url:
              'https://rr1---sn.googlevideo.com/videoplayback?mime=audio%2Fwebm',
          fetchedAt: fetched,
          expiresAt: expires,
          userAgent: 'UA',
          cookies: 'COOKIE=1',
          stream: stream,
        );

    test('isExpired is inclusive of the expiry instant', () {
      final e = entry();
      expect(e.isExpired(DateTime.fromMillisecondsSinceEpoch(1999)), isFalse);
      expect(e.isExpired(expires), isTrue);
      expect(e.isExpired(DateTime.fromMillisecondsSinceEpoch(2001)), isTrue);
    });

    test('remainingTtl never goes negative', () {
      final e = entry();
      expect(e.remainingTtl(DateTime.fromMillisecondsSinceEpoch(1000)),
          const Duration(seconds: 1));
      expect(e.remainingTtl(DateTime.fromMillisecondsSinceEpoch(5000)),
          Duration.zero);
    });

    test('toStream returns the embedded rich stream when present', () {
      const stream = YtmStream(
        videoId: 'vid1',
        url: 'https://x/a',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: Duration(seconds: 30),
        title: 'T',
        artist: 'A',
      );
      expect(identical(entry(stream: stream).toStream(), stream), isTrue);
    });

    test('toStream reconstructs webm streams from the URL', () {
      final stream = entry().toStream();
      expect(stream.mimeType, 'audio/webm');
      expect(stream.container, 'webm');
      expect(stream.bitrateKbps, 256);
      expect(stream.userAgent, 'UA');
      expect(stream.cookies, 'COOKIE=1');
      expect(stream.expiresAt, expires.millisecondsSinceEpoch);
      expect(stream.duration, Duration.zero);
    });

    test('toStream reconstructs m4a streams and quality bitrates', () {
      final e = YtmUrlCacheEntry(
        videoId: 'vid2',
        url: 'https://x/audio?id=1',
        fetchedAt: fetched,
        expiresAt: expires,
      );
      expect(e.toStream().mimeType, 'audio/mp4');
      expect(e.toStream().container, 'm4a');
      expect(e.toStream(quality: 'medium').bitrateKbps, 128);
      expect(e.toStream(quality: 'low').bitrateKbps, 64);
    });
  });

  group('get / getUrl / getStream / contains / needsRefresh', () {
    test('getUrl and getStream surface the stored values', () {
      cache.put('vid1', 'https://googlevideo.com/a');
      expect(cache.getUrl('vid1'), 'https://googlevideo.com/a');
      expect(cache.getStream('vid1'), isNotNull);
      expect(cache.getStream('missing'), isNull);
      expect(cache.getUrl('missing'), isNull);
    });

    test('contains does not promote the entry to MRU', () {
      final small = YtmUrlCache.withClock(clock, capacity: 2);
      small.put('a', 'https://x/a');
      small.put('b', 'https://x/b');
      expect(small.contains('a'), isTrue);
      small.put('c', 'https://x/c');
      // contains('a') must not have refreshed its aging.
      expect(small.contains('a'), isFalse);
      expect(small.contains('c'), isTrue);
    });

    test('contains drops expired entries', () {
      cache.put('vid1', 'https://x/a');
      clock.advance(const Duration(hours: 5));
      expect(cache.contains('vid1'), isFalse);
      expect(cache.length, 0);
    });

    test('needsRefresh is true for a missing key', () {
      expect(cache.needsRefresh('nope'), isTrue);
    });

    test('needsRefresh is true inside the refresh threshold', () {
      cache.put('vid1', 'https://x/a');
      expect(
        cache.needsRefresh('vid1',
            refreshThreshold: const Duration(hours: 4, minutes: 1)),
        isTrue,
      );
      expect(
        cache.needsRefresh('vid1',
            refreshThreshold: const Duration(minutes: 10)),
        isFalse,
      );
    });

    test('needsRefresh removes and reports expired entries', () {
      cache.put('vid1', 'https://x/a');
      clock.advance(const Duration(hours: 5));
      expect(cache.needsRefresh('vid1'), isTrue);
      expect(cache.length, 0);
    });
  });

  group('put validation and expiry resolution', () {
    test('blank video ids and urls are ignored', () {
      cache.put('', 'https://x/a');
      cache.put('   ', 'https://x/a');
      cache.put('vid1', '');
      cache.put('vid1', '   ');
      expect(cache.length, 0);
    });

    test('an unparseable url is ignored', () {
      cache.put('vid1', 'http://[::1');
      expect(cache.length, 0);
    });

    test('an earlier explicit expiry caps the default TTL', () {
      final explicit = clock.now().add(const Duration(minutes: 30));
      cache.put('vid1', 'https://x/a', explicitExpiry: explicit);

      final entry = cache.get('vid1');
      expect(entry!.expiresAt, explicit);
    });

    test('a URL expire stamp earlier than the explicit expiry wins', () {
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      final explicit = clock.now().add(const Duration(hours: 2));
      cache.put(
        'vid1',
        'https://x/a?expire=${nowSec + 600}',
        explicitExpiry: explicit,
      );

      // 600s stamp minus the 5 minute safety margin = 300s from now.
      expect(cache.get('vid1')!.expiresAt,
          clock.now().add(const Duration(seconds: 300)));
    });

    test('an already-expired explicit expiry drops any stored entry', () {
      cache.put('vid1', 'https://x/a');
      expect(cache.get('vid1'), isNotNull);

      cache.put('vid1', 'https://x/b',
          explicitExpiry: clock.now().subtract(const Duration(seconds: 1)));

      expect(cache.get('vid1'), isNull);
      expect(cache.length, 0);
    });

    test('a stamp inside the safety margin is not cached', () {
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      cache.put('vid1', 'https://x/a?expire=${nowSec + 120}');
      expect(cache.get('vid1'), isNull);
    });

    test('a past URL stamp is treated as dead, not as no stamp', () {
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      cache.put('vid1', 'https://x/a?expire=${nowSec - 3600}');
      expect(cache.get('vid1'), isNull);
    });

    test('millisecond epoch stamps are accepted', () {
      final modernClock =
          FakeClock(DateTime.fromMillisecondsSinceEpoch(1712345678000));
      final modernCache = YtmUrlCache.withClock(modernClock);
      modernCache.put('vid1', 'https://x/a?expire=1712349278000');
      expect(modernCache.get('vid1')!.expiresAt,
          modernClock.now().add(const Duration(minutes: 55)));
    });

    test('path-segment expiry stamps are parsed too', () {
      final nowSec = clock.now().millisecondsSinceEpoch ~/ 1000;
      cache.put('vid1', 'https://x/expire/${nowSec + 600}/videoplayback');
      expect(cache.get('vid1')!.expiresAt,
          clock.now().add(const Duration(seconds: 300)));
    });

    test('parseUrlExpiryStamp handles query, path, seconds, millis and junk',
        () {
      expect(YtmUrlCache.parseUrlExpiryStamp('https://x/a?expire=1712345678'),
          DateTime.fromMillisecondsSinceEpoch(1712345678 * 1000));
      expect(
          YtmUrlCache.parseUrlExpiryStamp('https://x/a?expire=1712345678000'),
          DateTime.fromMillisecondsSinceEpoch(1712345678000));
      expect(YtmUrlCache.parseUrlExpiryStamp('https://x/expire/1712345678/a'),
          DateTime.fromMillisecondsSinceEpoch(1712345678 * 1000));
      expect(YtmUrlCache.parseUrlExpiryStamp('https://x/a?expire=0'), isNull);
      expect(YtmUrlCache.parseUrlExpiryStamp('https://x/a?expire=abc'), isNull);
      expect(YtmUrlCache.parseUrlExpiryStamp('https://x/a'), isNull);
      expect(YtmUrlCache.parseUrlExpiryStamp('not a url'), isNull);
    });

    test('userAgent and cookies carry forward when omitted', () {
      cache.put('vid1', 'https://x/a', userAgent: 'UA', cookies: 'C=1');
      cache.put('vid1', 'https://x/a');

      final entry = cache.get('vid1')!;
      expect(entry.userAgent, 'UA');
      expect(entry.cookies, 'C=1');
    });

    test('a different URL inherits rich metadata with the new url', () {
      const stream = YtmStream(
        videoId: 'vid1',
        url: 'https://x/a',
        mimeType: 'audio/webm',
        container: 'webm',
        bitrateKbps: 256,
        duration: Duration(minutes: 3),
        title: 'T',
        artist: 'A',
        userAgent: 'OLD-UA',
      );
      cache.putStream(stream);

      cache.put('vid1', 'https://x/b', userAgent: 'NEW-UA');

      final entry = cache.get('vid1')!;
      expect(entry.url, 'https://x/b');
      expect(entry.stream!.url, 'https://x/b');
      expect(entry.stream!.userAgent, 'NEW-UA');
      expect(entry.stream!.duration, const Duration(minutes: 3));
      expect(entry.stream!.container, 'webm');
    });

    test('putStream without an expiry gets the default TTL', () {
      const stream = YtmStream(
        videoId: 'vid1',
        url: 'https://x/a',
        mimeType: 'audio/mp4',
        container: 'm4a',
        bitrateKbps: 128,
        duration: Duration(minutes: 3),
        title: 'T',
        artist: 'A',
      );
      cache.putStream(stream);
      expect(cache.get('vid1')!.expiresAt,
          clock.now().add(YtmUrlCache.defaultTtl));
    });

    test('putting an existing key does not grow past capacity', () {
      for (var i = 0; i < 8; i++) {
        cache.put('vid$i', 'https://x/$i');
      }
      expect(cache.length, 8);
      cache.put('vid7', 'https://x/updated');
      expect(cache.length, 8);
      expect(cache.getUrl('vid7'), 'https://x/updated');
    });
  });

  group('invalidate', () {
    test('invalidating an unknown video is a safe no-op', () {
      cache.put('vid1', 'https://x/a');
      cache.invalidate('other');
      cache.invalidate('vid1', quality: 'low');
      expect(cache.length, 1);
      expect(cache.get('vid1'), isNotNull);
    });

    test('invalidate without quality removes every quality slot', () {
      cache.put('vid1', 'https://x/high', quality: 'high');
      cache.put('vid1', 'https://x/low', quality: 'low');
      cache.put('vid2', 'https://x/vid2');

      cache.invalidate('vid1');

      expect(cache.length, 1);
      expect(cache.get('vid2'), isNotNull);
    });
  });

  group('restore / persist', () {
    File diskFile() => File('${testDir.path}/$_diskFileName');

    test('restore is a no-op when no disk file exists', () async {
      await cache.restore();
      expect(cache.length, 0);
    });

    test('restore ignores an empty or non-list cache file', () async {
      diskFile().writeAsStringSync('   ');
      await cache.restore();
      expect(cache.length, 0);

      final fresh = YtmUrlCache.withClock(clock);
      diskFile().writeAsStringSync('{"not":"a list"}');
      await fresh.restore();
      expect(fresh.length, 0);
    });

    test('restore keeps only entries with meaningful life left', () async {
      final now = clock.now().millisecondsSinceEpoch;
      diskFile().writeAsStringSync(jsonEncode([
        {
          'videoId': 'keep',
          'url': 'https://x/keep',
          'quality': 'high',
          'expiresAt': now + const Duration(hours: 2).inMilliseconds,
        },
        {
          'videoId': 'short',
          'url': 'https://x/short',
          'quality': 'high',
          'expiresAt': now + const Duration(minutes: 5).inMilliseconds,
        },
        {'videoId': 'no-url', 'expiresAt': now + 99999999},
        {'url': 'https://x/no-id', 'expiresAt': now + 99999999},
        {'videoId': 'no-expiry', 'url': 'https://x/no-expiry'},
        'junk-entry',
        {
          'videoId': 'string-expiry',
          'url': 'https://x/string',
          'expiresAt': '${now + const Duration(hours: 3).inMilliseconds}',
        },
      ]));

      await cache.restore();

      expect(cache.getUrl('keep'), 'https://x/keep');
      expect(cache.getUrl('short'), isNull);
      expect(cache.getUrl('no-url'), isNull);
      expect(cache.getUrl('no-id'), isNull);
      expect(cache.getUrl('no-expiry'), isNull);
      expect(cache.getUrl('string-expiry'), 'https://x/string');
    });

    test('restore rebuilds the rich stream from persisted metadata', () async {
      final now = clock.now().millisecondsSinceEpoch;
      diskFile().writeAsStringSync(jsonEncode([
        {
          'videoId': 'rich',
          'url': 'https://x/rich',
          'quality': 'high',
          'expiresAt': now + const Duration(hours: 2).inMilliseconds,
          'userAgent': 'UA',
          'mimeType': 'audio/webm',
          'container': 'webm',
          'bitrateKbps': 256,
          'durationMs': 185000,
          'title': 'Rich Title',
          'artist': 'Rich Artist',
        },
      ]));

      await cache.restore();

      final stream = cache.getStream('rich')!;
      expect(stream.mimeType, 'audio/webm');
      expect(stream.container, 'webm');
      expect(stream.bitrateKbps, 256);
      expect(stream.duration, const Duration(milliseconds: 185000));
      expect(stream.title, 'Rich Title');
      expect(stream.artist, 'Rich Artist');
      expect(stream.userAgent, 'UA');
    });

    test('restore coerces string numeric metadata and defaults container',
        () async {
      final now = clock.now().millisecondsSinceEpoch;
      diskFile().writeAsStringSync(jsonEncode([
        {
          'videoId': 'coerced',
          'url': 'https://x/coerced',
          'expiresAt': now + const Duration(hours: 2).inMilliseconds,
          'mimeType': 'audio/mp4',
          'bitrateKbps': '128',
          'durationMs': '60000',
        },
      ]));

      await cache.restore();

      final stream = cache.getStream('coerced')!;
      expect(stream.container, 'm4a');
      expect(stream.bitrateKbps, 128);
      expect(stream.duration, const Duration(minutes: 1));
      expect(stream.title, 'YouTube Track');
      expect(stream.artist, 'YouTube Music');
    });

    test('restore tolerates corrupt JSON', () async {
      diskFile().writeAsStringSync('{definitely not json');
      await expectLater(cache.restore(), completes);
      expect(cache.length, 0);
    });

    test('restore only runs once per instance', () async {
      final now = clock.now().millisecondsSinceEpoch;
      diskFile().writeAsStringSync(jsonEncode([
        {
          'videoId': 'first',
          'url': 'https://x/first',
          'expiresAt': now + const Duration(hours: 2).inMilliseconds,
        }
      ]));
      await cache.restore();
      expect(cache.length, 1);

      // A second restore call must not re-read the file or double-add.
      diskFile().writeAsStringSync('[]');
      await cache.restore();
      expect(cache.length, 1);
    });

    test('a debounced persist writes guest entries and skips cookie ones',
        () async {
      await cache.restore(); // sets the disk file for later persists
      cache.put('guest', 'https://x/guest');
      cache.put('cookie', 'https://x/cookie',
          cookies: 'SID=secret', quality: 'low');

      cache.clear();
      cache.put('guest2', 'https://x/guest2');

      // The persist is debounced by 3 seconds; let the real timer fire.
      final raw = await readDiskEventually(diskFile());
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(decoded, hasLength(1));
      expect(decoded.single['videoId'], 'guest2');
      expect(raw.contains('secret'), isFalse);
    });

    test('a persist after clear removes every entry from disk', () async {
      await cache.restore();
      cache.put('guest', 'https://x/guest');

      cache.clear();

      final raw = await readDiskEventually(diskFile());
      expect(raw, isNotNull);
      expect(jsonDecode(raw!), isEmpty);
    });
  });
}
