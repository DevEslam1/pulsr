// test/data/audio/audio_memory_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/audio/audio_memory_manager.dart';

void main() {
  group('Phase 4 — AudioMemoryManager 32MB Budget & LRU Eviction Tests', () {
    late AudioMemoryManager manager;
    int evictionCalls = 0;

    setUp(() {
      evictionCalls = 0;
      manager = AudioMemoryManager(
        onEvictOldestCacheRequested: () => evictionCalls++,
      );
    });

    test('calculateHeadSize calculates proper size for compressed vs lossless',
        () {
      // 320 kbps compressed stream: (320,000 / 8) * 10 = 400,000 bytes (~400KB)
      final mp3Size = AudioMemoryManager.calculateHeadSize(bitrateKbps: 320);
      expect(mp3Size, equals(400000));

      // 24-bit 192kHz lossless: 192000 * 2 * 3 * 10 = 11,520,000 clamped to 4MB max
      final flacSize = AudioMemoryManager.calculateHeadSize(
          sampleRate: 192000, bitDepth: 24);
      expect(flacSize, equals(4 * 1024 * 1024));
    });

    test('canPreload gates false when battery is constrained', () {
      expect(manager.canPreload(isBatteryConstrained: true), isFalse);
      expect(manager.canPreload(isBatteryConstrained: false), isTrue);
    });

    test('registerPreload enforces 32MB hard cap via LRU eviction', () {
      const entrySize = 4 * 1024 * 1024; // 4MB per entry

      // Add 8 entries = 32MB (fits exactly)
      for (int i = 0; i < 8; i++) {
        manager.registerPreload('entry_$i', entrySize);
      }
      expect(manager.currentPreloadBytes, equals(32 * 1024 * 1024));
      expect(manager.preloadedHeadCount, equals(8));
      expect(evictionCalls, equals(0));

      // Add 9th entry = 36MB -> evicts entry_0 (oldest)
      manager.registerPreload('entry_8', entrySize);
      expect(manager.currentPreloadBytes, equals(32 * 1024 * 1024));
      expect(manager.preloadedHeadCount, equals(8));
      expect(evictionCalls, equals(1));

      // Add 10th entry -> evicts entry_1
      manager.registerPreload('entry_9', entrySize);
      expect(manager.currentPreloadBytes, equals(32 * 1024 * 1024));
      expect(manager.preloadedHeadCount, equals(8));
      expect(evictionCalls, equals(2));
    });
  });
}
