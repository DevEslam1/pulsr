// test/data/audio/song_rating_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SongRatingStore Unit Tests', () {
    test('default rating is 0 for unrated tracks', () async {
      final store = SongRatingStore();
      await store.ready;

      expect(store.getRating('track_1'), equals(0));
    });

    test('sets and persists star rating (1 to 5)', () async {
      final store = SongRatingStore();
      await store.ready;

      await store.setRating('track_1', 4);
      expect(store.getRating('track_1'), equals(4));

      // Verify persistence across new store instance
      final reloaded = SongRatingStore();
      await reloaded.ready;
      expect(reloaded.getRating('track_1'), equals(4));
    });

    test('clamps rating values to 0..5 range', () async {
      final store = SongRatingStore();
      await store.ready;

      await store.setRating('track_above', 9);
      expect(store.getRating('track_above'), equals(5));

      await store.setRating('track_below', -3);
      expect(store.getRating('track_below'), equals(0));
    });

    test('setting rating to 0 removes the entry', () async {
      final store = SongRatingStore();
      await store.ready;

      await store.setRating('track_1', 5);
      expect(store.getRating('track_1'), equals(5));

      await store.setRating('track_1', 0);
      expect(store.getRating('track_1'), equals(0));
    });
  });
}
