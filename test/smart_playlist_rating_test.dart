// test/smart_playlist_rating_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsr/core/di/injection.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';

/// Regression tests for prefs-backed star ratings in smart playlists:
///
/// * `rating` rules filter in Dart (ratings live in SharedPreferences,
///   invisible to the Drift query),
/// * matchAll ANDs them with SQL rules, matchAny unions correctly,
/// * `sortBy: 'rating'` orders by stars, and the limit applies after
///   filtering (not before).
void main() {
  late AppDatabase db;
  late SmartPlaylistEngine engine;
  late SongRatingStore ratings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = SmartPlaylistEngine(db);
    ratings = SongRatingStore();
    await ratings.ready;
    if (!getIt.isRegistered<SongRatingStore>()) {
      getIt.registerSingleton<SongRatingStore>(ratings);
    }
  });

  tearDown(() async {
    await db.close();
    if (getIt.isRegistered<SongRatingStore>(
        instance: getIt<SongRatingStore>())) {
      // Only unregister the instance this test registered.
      try {
        if (identical(getIt<SongRatingStore>(), ratings)) {
          getIt.unregister<SongRatingStore>();
        }
      } catch (_) {}
    }
  });

  Future<void> insertSong({
    required int id,
    required String title,
    String? genre,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: '/music/$title.mp3',
          genre: Value(genre),
        ));
  }

  group('SmartPlaylistEngine rating rules', () {
    test('matchAll rating>=4 keeps only highly rated tracks', () async {
      await insertSong(id: 1, title: 'Loved');
      await insertSong(id: 2, title: 'Meh');
      await insertSong(id: 3, title: 'Unrated');
      await ratings.setRating('1', 5);
      await ratings.setRating('2', 2);

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '4',
          ),
        ],
      ));

      expect(result.map((s) => s.title).toSet(), {'Loved'});
    });

    test('matchAll combines SQL rules with rating rules', () async {
      await insertSong(id: 1, title: 'RockFav', genre: 'Rock');
      await insertSong(id: 2, title: 'RockMeh', genre: 'Rock');
      await insertSong(id: 3, title: 'PopFav', genre: 'Pop');
      await ratings.setRating('1', 5);
      await ratings.setRating('2', 1);
      await ratings.setRating('3', 5);

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.equals,
            value: 'rock',
          ),
          SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '4',
          ),
        ],
        matchAll: true,
      ));

      expect(result.map((s) => s.title).toSet(), {'RockFav'});
    });

    test('matchAny unions SQL matches with rating matches', () async {
      await insertSong(id: 1, title: 'RockUnrated', genre: 'Rock');
      await insertSong(id: 2, title: 'PopFav', genre: 'Pop');
      await insertSong(id: 3, title: 'JazzMeh', genre: 'Jazz');
      await ratings.setRating('2', 5);
      await ratings.setRating('3', 1);

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.equals,
            value: 'rock',
          ),
          SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '4',
          ),
        ],
        matchAll: false,
      ));

      expect(
        result.map((s) => s.title).toSet(),
        {'RockUnrated', 'PopFav'},
      );
    });

    test('sortBy rating orders by stars with title tiebreak', () async {
      await insertSong(id: 1, title: 'B Song');
      await insertSong(id: 2, title: 'A Song');
      await insertSong(id: 3, title: 'C Song');
      await ratings.setRating('1', 3);
      await ratings.setRating('2', 5);
      await ratings.setRating('3', 5);

      final result = await engine.evaluateCriteria(const SmartCriteria(
        sortBy: 'rating',
        sortAscending: false,
      ));

      expect(
        result.map((s) => s.title).toList(),
        ['A Song', 'C Song', 'B Song'],
      );
    });

    test('limit applies after the rating filter, not before', () async {
      for (var i = 1; i <= 5; i++) {
        await insertSong(id: i, title: 'Track $i');
        await ratings.setRating('$i', 5);
      }

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '4',
          ),
        ],
        sortBy: 'rating',
        sortAscending: false,
        limit: 2,
      ));

      expect(result.length, 2);
    });
  });
}
