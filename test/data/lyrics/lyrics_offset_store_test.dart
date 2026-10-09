// test/data/lyrics/lyrics_offset_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/lyrics/lyrics_offset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  String legacyKey(String path) {
    var h = 0;
    for (var i = 0; i < path.length; i++) {
      h = (h * 31 + path.codeUnitAt(i)) & 0x7fffffff;
    }
    return 'lyrics_offset_v1_$h';
  }

  group('LyricsOffsetStore', () {
    test('empty paths are no-ops', () async {
      final store = LyricsOffsetStore();
      expect(await store.getOffsetMs(''), 0);
      await store.setOffsetMs('', 1234);
      await store.clearOffset('');
    });

    test('round-trips an offset and clamps it to +/-5000ms', () async {
      final store = LyricsOffsetStore();
      await store.setOffsetMs('/music/a.flac', 250);
      expect(await store.getOffsetMs('/music/a.flac'), 250);

      await store.setOffsetMs('/music/b.flac', 999999);
      expect(await store.getOffsetMs('/music/b.flac'), 5000);

      await store.setOffsetMs('/music/c.flac', -999999);
      expect(await store.getOffsetMs('/music/c.flac'), -5000);
    });

    test('unknown path reads zero', () async {
      final store = LyricsOffsetStore();
      expect(await store.getOffsetMs('/never/seen.flac'), 0);
    });

    test('clearOffset removes the stored value', () async {
      final store = LyricsOffsetStore();
      await store.setOffsetMs('/music/gone.flac', 42);
      expect(await store.getOffsetMs('/music/gone.flac'), 42);

      await store.clearOffset('/music/gone.flac');
      expect(await store.getOffsetMs('/music/gone.flac'), 0);

      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList('lyrics_offset_index_v1') ?? const [];
      expect(index.any((k) => k.contains('gone')), isFalse);
    });

    test('migrates a legacy hash key lazily on read', () async {
      const path = '/music/legacy.flac';
      final legacy = legacyKey(path);
      SharedPreferences.setMockInitialValues({
        legacy: 321,
        '${legacy}_path': path,
      });

      final store = LyricsOffsetStore();
      expect(await store.getOffsetMs(path), 321);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(legacy), isNull,
          reason: 'legacy value is removed after migration');
      expect(prefs.getString('${legacy}_path'), isNull);
      expect(await store.getOffsetMs(path), 321,
          reason: 'new key now serves the value');
    });

    test('a hash owned by another path reads zero (collision guard)',
        () async {
      const path = '/music/collide.flac';
      final store = LyricsOffsetStore();
      await store.setOffsetMs(path, 77);

      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList('lyrics_offset_index_v1')!;
      final key = index.single;
      await prefs.setString('${key}_path', '/music/someone-else.flac');
      await prefs.setInt(key, 999);

      expect(await store.getOffsetMs(path), 0);
    });

    test('evicts oldest entries beyond maxEntries', () async {
      final store = LyricsOffsetStore();
      for (var i = 0; i <= LyricsOffsetStore.maxEntries; i++) {
        await store.setOffsetMs('/music/evict_$i.flac', i);
      }

      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList('lyrics_offset_index_v1')!;
      expect(index, hasLength(LyricsOffsetStore.maxEntries));
      expect(await store.getOffsetMs('/music/evict_0.flac'), 0,
          reason: 'the oldest offset was evicted');
      expect(
        await store.getOffsetMs('/music/evict_${LyricsOffsetStore.maxEntries}.flac'),
        LyricsOffsetStore.maxEntries,
      );
    });
  });
}
