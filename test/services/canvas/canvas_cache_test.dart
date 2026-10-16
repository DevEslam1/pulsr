// test/services/canvas/canvas_cache_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsr/services/canvas/canvas_artwork.dart';
import 'package:pulsr/services/canvas/canvas_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_canvas_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CanvasCache Memory LRU', () {
    test('maintains bounded memory LRU entries', () {
      final cache =
          CanvasCache(maxMemoryEntries: 3, customCacheDirPath: tempDir.path);

      cache.putInMemory('k1', const CanvasArtwork(videoUrl: 'u1', title: 'T1'));
      cache.putInMemory('k2', const CanvasArtwork(videoUrl: 'u2', title: 'T2'));
      cache.putInMemory('k3', const CanvasArtwork(videoUrl: 'u3', title: 'T3'));

      expect(cache.getFromMemory('k1')?.title, 'T1');
      expect(cache.getFromMemory('k2')?.title, 'T2');
      expect(cache.getFromMemory('k3')?.title, 'T3');

      // Adding 4th entry evicts oldest (k1 was accessed, so k2 is now oldest after k1 was accessed, wait:
      // k1 accessed, then k2 accessed, then k3 accessed -> oldest is k1? No, k1 was accessed, then k2, then k3.
      // So k1 is oldest of the 3 accessed? Let's check:
      // put k1, put k2, put k3 -> order: k1, k2, k3
      // get k1 -> moves k1 to end: k2, k3, k1
      // put k4 -> evicts k2!
      cache.putInMemory('k4', const CanvasArtwork(videoUrl: 'u4', title: 'T4'));

      expect(cache.getFromMemory('k1'), isNull);
      expect(cache.getFromMemory('k2')?.title, 'T2');
      expect(cache.getFromMemory('k3')?.title, 'T3');
      expect(cache.getFromMemory('k4')?.title, 'T4');
    });

    test('supports negative caching (null entries)', () {
      final cache = CanvasCache(customCacheDirPath: tempDir.path);
      cache.putInMemory('miss_key', null);

      expect(cache.hasInMemory('miss_key'), isTrue);
      expect(cache.getFromMemory('miss_key'), isNull);
    });
  });

  group('CanvasCache Disk LRU', () {
    test('downloads video and enforces max byte boundary', () async {
      // 500 bytes max limit for test
      const maxLimit = 500;
      final mockClient = MockClient((request) async {
        // Return 200 bytes of data
        return http.Response.bytes(List<int>.filled(200, 42), 200);
      });

      final cache = CanvasCache(
        client: mockClient,
        maxDiskBytes: maxLimit,
        customCacheDirPath: tempDir.path,
      );

      final path1 =
          await cache.getOrDownloadVideo('https://example.com/v1.mp4');
      expect(path1, isNotNull);
      expect(File(path1!).existsSync(), isTrue);

      final path2 =
          await cache.getOrDownloadVideo('https://example.com/v2.mp4');
      expect(path2, isNotNull);
      expect(File(path2!).existsSync(), isTrue);

      // Total is now ~400 bytes, which is <= 500 bytes.
      expect(await cache.currentDiskUsageBytes(), 400);

      // Third download brings total to 600 bytes > 500 bytes limit -> oldest file evicted!
      final path3 =
          await cache.getOrDownloadVideo('https://example.com/v3.mp4');
      expect(path3, isNotNull);
      expect(File(path3!).existsSync(), isTrue);

      // Usage should be <= maxLimit (400 bytes because oldest file was evicted)
      final currentUsage = await cache.currentDiskUsageBytes();
      expect(currentUsage <= maxLimit, isTrue);

      // Oldest file should be evicted
      expect(File(path1).existsSync(), isFalse);
    });
  });
}
