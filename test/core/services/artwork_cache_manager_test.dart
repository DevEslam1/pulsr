// test/core/services/artwork_cache_manager_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/services/artwork_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Uint8List _bytes(int length, [int fill = 1]) =>
    Uint8List.fromList(List<int>.filled(length, fill));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  final manager = ArtworkCacheManager();

  setUpAll(() {
    tempRoot = Directory.systemTemp.createTempSync('artwork_cache_test');
  });

  tearDownAll(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'setting_max_cache_size_mb': ArtworkCacheManager.defaultMaxCacheSizeMb
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      return tempRoot.path;
    });
    await manager.init();
    await manager.clearAllCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  group('init / configuration', () {
    test('defaults the max cache size and reads a custom pref', () async {
      expect(ArtworkCacheManager.defaultMaxCacheSizeMb, 100);
      await manager.init();
      expect(manager.maxCacheSizeMb, 100);

      SharedPreferences.setMockInitialValues({'setting_max_cache_size_mb': 42});
      await manager.init();
      expect(manager.maxCacheSizeMb, 42);
    });

    test('setMaxCacheSizeMb persists the new value', () async {
      await manager.setMaxCacheSizeMb(321);
      expect(manager.maxCacheSizeMb, 321);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('setting_max_cache_size_mb'), 321);
    });

    test('init survives a missing path_provider implementation', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        throw MissingPluginException('no path_provider');
      });

      await expectLater(manager.init(), completes);
    });
  });

  group('put / get memory paths', () {
    test('small payloads round-trip through the strong memory cache', () async {
      final payload = _bytes(64, 9);
      await manager.put('mem-key', payload);

      final loaded = await manager.get('mem-key');
      expect(loaded, isNotNull);
      expect(loaded, payload);
    });

    test('large payloads use the weak memory cache and still round-trip',
        () async {
      expect(ArtworkCacheManager.largePayloadThreshold, 512 * 1024);
      final payload = _bytes(ArtworkCacheManager.largePayloadThreshold + 1, 3);
      await manager.put('large-key', payload);

      final loaded = await manager.get('large-key');
      expect(loaded, isNotNull);
      expect(loaded!.length, payload.length);
    });

    test('null and empty payloads are ignored', () async {
      await manager.put('null-key', null);
      await manager.put('empty-key', Uint8List(0));

      expect(await manager.get('null-key'), isNull);
      expect(await manager.get('empty-key'), isNull);
    });

    test('an unknown key resolves to null', () async {
      expect(await manager.get('never-written'), isNull);
    });

    test('overwriting a key replaces the bytes and the memory accounting',
        () async {
      await manager.put('dup-key', _bytes(10, 1));
      await manager.put('dup-key', _bytes(20, 2));

      final loaded = await manager.get('dup-key');
      expect(loaded!.length, 20);
      expect(loaded.first, 2);
    });

    test('many small inserts evict old memory entries without throwing',
        () async {
      for (var i = 0; i < 151; i++) {
        await manager.put('bulk-$i', _bytes(16, i % 255));
      }
      // Every entry was also persisted to disk, so the oldest still resolves.
      expect(await manager.get('bulk-0'), isNotNull);
      expect((await manager.get('bulk-0'))!.length, 16);
    });
  });

  group('disk cache', () {
    test('trimMemoryForPressure keeps disk data readable', () async {
      final payload = _bytes(128, 7);
      await manager.put('disk-key', payload);

      manager.trimMemoryForPressure();

      final loaded = await manager.get('disk-key');
      expect(loaded, isNotNull);
      expect(loaded, payload);
    });

    test('getDiskCacheSizeBytes reflects written files and clears to zero',
        () async {
      await manager.clearAllCache();
      expect(await manager.getDiskCacheSizeBytes(), 0);

      await manager.put('size-key', _bytes(256, 5));
      expect(await manager.getDiskCacheSizeBytes(), 256);

      await manager.clearAllCache();
      expect(await manager.getDiskCacheSizeBytes(), 0);
    });

    test('remove deletes both memory and disk copies', () async {
      await manager.put('remove-key', _bytes(64, 1));
      expect(await manager.get('remove-key'), isNotNull);

      await manager.remove('remove-key');

      expect(await manager.get('remove-key'), isNull);
      expect(await manager.getDiskCacheSizeBytes(), 0);
    });

    test('remove on a missing key does not throw', () async {
      await expectLater(manager.remove('ghost-key'), completes);
    });

    test('keys are hashed into stable, collision-free file names', () async {
      await manager.put('a', _bytes(4, 1));
      await manager.put('b', _bytes(4, 2));

      // Different keys must not share a cache file.
      expect(await manager.getDiskCacheSizeBytes(), 8);
    });

    test('a zero max size evicts every file in the background isolate',
        () async {
      await manager.put('evict-1', _bytes(300, 1));
      await manager.put('evict-2', _bytes(300, 2));
      expect(await manager.getDiskCacheSizeBytes(), greaterThan(0));

      await manager.setMaxCacheSizeMb(0);

      var size = await manager.getDiskCacheSizeBytes();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (size > 0 && DateTime.now().isBefore(deadline)) {
        await manager.setMaxCacheSizeMb(0);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        size = await manager.getDiskCacheSizeBytes();
      }
      expect(size, 0);
    });
  });

  group('prefetch', () {
    test('warms keys that are not already in memory', () async {
      await manager.put('prefetch-1', _bytes(32, 1));
      manager.trimMemoryForPressure();

      await manager.prefetch(['prefetch-1', 'prefetch-2', '']);

      expect(await manager.get('prefetch-1'), isNotNull);
      // prefetch-2 was never written anywhere, so it stays a miss.
      expect(await manager.get('prefetch-2'), isNull);
    });
  });

  group('toLowQualityArtworkUrl', () {
    test('rewrites googleusercontent size suffixes', () {
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
            'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj'),
        'https://lh3.googleusercontent.com/abc=w200-h200-l80-rj',
      );
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
            'https://lh3.googleusercontent.com/abc=s1200'),
        'https://lh3.googleusercontent.com/abc=w200-h200-l80-rj',
      );
    });

    test('honours custom dimensions', () {
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
          'https://lh3.googleusercontent.com/abc=w50-h50',
          width: 320,
          height: 240,
        ),
        'https://lh3.googleusercontent.com/abc=w320-h240-l80-rj',
      );
    });

    test('appends a size suffix when none is present', () {
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
            'https://lh3.googleusercontent.com/no-size'),
        'https://lh3.googleusercontent.com/no-size=w200-h200-l80-rj',
      );
    });

    test('rewrites ggpht.com the same way', () {
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
            'https://yt3.ggpht.com/x=w800-h800'),
        'https://yt3.ggpht.com/x=w200-h200-l80-rj',
      );
    });

    test('downgrades ytimg maxresdefault thumbnails', () {
      expect(
        ArtworkCacheManager.toLowQualityArtworkUrl(
            'https://i.ytimg.com/vi/id/maxresdefault.jpg'),
        'https://i.ytimg.com/vi/id/hqdefault.jpg',
      );
    });

    test('leaves unrelated URLs untouched', () {
      const url = 'https://example.com/cover.jpg';
      expect(ArtworkCacheManager.toLowQualityArtworkUrl(url), url);
    });
  });
}
