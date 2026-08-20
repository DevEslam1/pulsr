// test/smart_playlist_engine_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';

void main() {
  late AppDatabase db;
  late SmartPlaylistEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = SmartPlaylistEngine(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSong({
    required int id,
    required String title,
    int? dateAdded,
    int playCount = 0,
    int? year,
    int? lastPlayed,
    String? genre,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: '/music/$title.mp3',
          dateAdded: Value(dateAdded),
          playCount: Value(playCount),
          year: Value(year),
          lastPlayed: Value(lastPlayed),
          genre: Value(genre),
        ));
  }

  group('SmartPlaylistEngine edge cases', () {
    test('withinDays on dateAdded matches second-granularity timestamps', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(id: 1, title: 'Fresh', dateAdded: nowSec - 3600); // 1 hour ago
      await insertSong(id: 2, title: 'Old', dateAdded: nowSec - (30 * 86400)); // 30 days ago

      final criteria = SmartCriteria(
        rules: const [
          SmartRule(
            field: SmartRuleField.dateAdded,
            operator: SmartOperator.withinDays,
            value: '7',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.map((s) => s.title), contains('Fresh'));
      expect(result.map((s) => s.title), isNot(contains('Old')));
    });

    test('withinDays with default 30 days when value missing', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(id: 1, title: 'WithinDefault', dateAdded: nowSec - (20 * 86400)); // 20 days
      await insertSong(id: 2, title: 'TooOld', dateAdded: nowSec - (45 * 86400)); // 45 days

      final criteria = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.dateAdded,
            operator: SmartOperator.withinDays,
            value: '',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.map((s) => s.title), contains('WithinDefault'));
      expect(result.map((s) => s.title), isNot(contains('TooOld')));
    });

    test('isFavorite rule filters by favorite flag', () async {
      await insertSong(id: 1, title: 'Liked');
      await insertSong(id: 2, title: 'Unliked');
      await (db.update(db.songsTable)..where((t) => t.id.equals(1)))
          .write(const SongsTableCompanion(isFavorite: Value(true)));

      final criteria = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.isFavorite,
            operator: SmartOperator.equals,
            value: 'true',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.length, 1);
      expect(result.first.title, 'Liked');
    });

    test('matchAll combines rules with AND', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(id: 1, title: 'Matches Both', playCount: 10, dateAdded: nowSec - 3600);
      await insertSong(id: 2, title: 'Only Plays', playCount: 10, dateAdded: nowSec - (60 * 86400));
      await insertSong(id: 3, title: 'Only Fresh', playCount: 0, dateAdded: nowSec - 3600);

      final criteria = SmartCriteria(
        rules: const [
          SmartRule(field: SmartRuleField.playCount, operator: SmartOperator.greaterThan, value: '5'),
          SmartRule(
            field: SmartRuleField.dateAdded,
            operator: SmartOperator.withinDays,
            value: '7',
          ),
        ],
        matchAll: true,
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.map((s) => s.title), ['Matches Both']);
    });

    test('empty criteria returns all songs', () async {
      await insertSong(id: 1, title: 'A');
      await insertSong(id: 2, title: 'B');

      final result = await engine.evaluateCriteria(const SmartCriteria());
      expect(result.length, 2);
    });
  });
}