// test/artwork_lru_cache_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/core/widgets/cached_artwork.dart';

void main() {
  group('ArtworkLruCache Unit Tests', () {
    test('Stores and retrieves artwork bytes', () {
      final cache = ArtworkLruCache.withCapacity(5);
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);

      cache.put('key1', sampleBytes);

      expect(cache.containsKey('key1'), isTrue);
      expect(cache.get('key1'), equals(sampleBytes));
      expect(cache.length, equals(1));
    });

    test('Stores null values for missing artwork', () {
      final cache = ArtworkLruCache.withCapacity(5);

      cache.put('key_null', null);

      expect(cache.containsKey('key_null'), isTrue);
      expect(cache.get('key_null'), isNull);
    });

    test('Evicts least recently used item when capacity exceeded (max 200 items logic)', () {
      final capacity = 3;
      final cache = ArtworkLruCache.withCapacity(capacity);

      cache.put('item1', Uint8List.fromList([1]));
      cache.put('item2', Uint8List.fromList([2]));
      cache.put('item3', Uint8List.fromList([3]));

      expect(cache.length, equals(3));

      // Access item1 to make it recently used -> order becomes: item2, item3, item1
      cache.get('item1');

      // Put item4 -> should evict item2
      cache.put('item4', Uint8List.fromList([4]));

      expect(cache.length, equals(3));
      expect(cache.containsKey('item2'), isFalse);
      expect(cache.containsKey('item1'), isTrue);
      expect(cache.containsKey('item3'), isTrue);
      expect(cache.containsKey('item4'), isTrue);
    });

    test('Clears all items', () {
      final cache = ArtworkLruCache.withCapacity(10);
      cache.put('item1', Uint8List.fromList([1]));
      cache.put('item2', Uint8List.fromList([2]));

      cache.clear();

      expect(cache.length, equals(0));
      expect(cache.containsKey('item1'), isFalse);
    });

    test('Default singleton cache has max capacity of 200', () {
      final cache = ArtworkLruCache();
      expect(cache.maxCapacity, equals(200));
    });
  });
}
