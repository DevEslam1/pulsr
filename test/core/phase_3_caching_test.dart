import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/services/artwork_cache_manager.dart';
import 'package:pulsr/core/services/library_cache_manager.dart';
import 'package:pulsr/core/services/settings_cache.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 - Caching, Persistence & Offline Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'SettingsCache provides synchronous access and write-through persistence',
        () async {
      SharedPreferences.setMockInitialValues({
        'test_bool': true,
        'test_int': 42,
        'test_string': 'hello_pulsr',
      });

      final cache = SettingsCache();
      await cache.init();

      // Synchronous reads
      expect(cache.getBool('test_bool'), isTrue);
      expect(cache.getInt('test_int'), equals(42));
      expect(cache.getString('test_string'), equals('hello_pulsr'));
      expect(cache.getString('non_existent', defaultValue: 'default_val'),
          equals('default_val'));

      // Synchronous write-through
      await cache.setBool('dynamic_flag', true);
      expect(cache.getBool('dynamic_flag'), isTrue);

      await cache.setString('mode', 'audiophile');
      expect(cache.getString('mode'), equals('audiophile'));

      await cache.remove('test_string');
      expect(
          cache.getString('test_string', defaultValue: 'none'), equals('none'));
    });

    test('ArtworkCacheManager memory LRU and prefetch work without error',
        () async {
      final manager = ArtworkCacheManager();

      // Put test bytes
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await manager.put('art_key_1', dummyBytes);

      final retrieved = await manager.get('art_key_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.length, equals(5));

      // Prefetch test
      await manager.prefetch(['art_key_1', 'art_key_2']);

      // Clear cache
      await manager.clearAllCache();
    });

    test('LibrarySnapshot serializes and deserializes songs correctly', () {
      final song = SongsTableData(
        id: 101,
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        durationMs: 354000,
        path: '/storage/music/queen.mp3',
        isFavorite: false,
        isMissing: false,
        playCount: 5,
        lastPositionMs: 0,
        source: 'local',
        isDownloaded: false,
      );

      final snapshot = LibrarySnapshot(
        songs: [song],
        totalSongCount: 1,
        albumCount: 1,
        artistCount: 1,
        timestamp: DateTime.now(),
      );

      final jsonMap = snapshot.toJson();
      final restored = LibrarySnapshot.fromJson(jsonMap);

      expect(restored.songs.length, equals(1));
      expect(restored.songs.first.title, equals('Bohemian Rhapsody'));
      expect(restored.songs.first.artist, equals('Queen'));
      expect(restored.totalSongCount, equals(1));
      expect(restored.albumCount, equals(1));
    });
  });
}
