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
    test('withinDays on dateAdded matches second-granularity Unix timestamps',
        () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(
          id: 10,
          title: 'FreshSec',
          dateAdded: nowSec - 3600); // 1 hour ago in sec
      await insertSong(
          id: 20,
          title: 'OldSec',
          dateAdded: nowSec - (30 * 86400)); // 30 days ago in sec

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
      expect(result.map((s) => s.title), contains('FreshSec'));
      expect(result.map((s) => s.title), isNot(contains('OldSec')));
    });

    test('withinDays on lastPlayed matches second-granularity Unix timestamps',
        () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(
          id: 101, title: 'PlayedRecently', lastPlayed: nowSec - 3600);
      await insertSong(
          id: 102, title: 'PlayedLongAgo', lastPlayed: nowSec - (60 * 86400));

      final criteria = SmartCriteria(
        rules: const [
          SmartRule(
            field: SmartRuleField.lastPlayed,
            operator: SmartOperator.withinDays,
            value: '14',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.map((s) => s.title), contains('PlayedRecently'));
      expect(result.map((s) => s.title), isNot(contains('PlayedLongAgo')));
    });

    test('isLossless rule matches FLAC, WAV, ALAC, AIFF, DSF, and DFF',
        () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(201),
            title: 'DsdDsf',
            path: '/music/track.dsf',
          ));
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(202),
            title: 'DsdDff',
            path: '/music/track.dff',
          ));
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(203),
            title: 'Mp3Lossy',
            path: '/music/track.mp3',
          ));

      final criteria = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.isLossless,
            operator: SmartOperator.equals,
            value: '',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      final titles = result.map((s) => s.title).toList();
      expect(titles, contains('DsdDsf'));
      expect(titles, contains('DsdDff'));
      expect(titles, isNot(contains('Mp3Lossy')));
    });

    test('withinDays with default 30 days when value missing', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(
          id: 1,
          title: 'WithinDefault',
          dateAdded: nowSec - (20 * 86400)); // 20 days
      await insertSong(
          id: 2, title: 'TooOld', dateAdded: nowSec - (45 * 86400)); // 45 days

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
      await insertSong(
          id: 1,
          title: 'Matches Both',
          playCount: 10,
          dateAdded: nowSec - 3600);
      await insertSong(
          id: 2,
          title: 'Only Plays',
          playCount: 10,
          dateAdded: nowSec - (60 * 86400));
      await insertSong(
          id: 3, title: 'Only Fresh', playCount: 0, dateAdded: nowSec - 3600);

      final criteria = SmartCriteria(
        rules: const [
          SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '5'),
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

    test('between operator matches numeric ranges correctly', () async {
      await insertSong(
          id: 301, title: 'EightiesSong', year: 1985, playCount: 25);
      await insertSong(
          id: 302, title: 'SeventiesSong', year: 1975, playCount: 5);
      await insertSong(
          id: 303, title: 'NinetiesSong', year: 1995, playCount: 100);

      // Between with comma
      final criteriaYear = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.year,
            operator: SmartOperator.between,
            value: '1980, 1989',
          ),
        ],
      );
      final resYear = await engine.evaluateCriteria(criteriaYear);
      expect(resYear.map((s) => s.title), contains('EightiesSong'));
      expect(resYear.map((s) => s.title), isNot(contains('SeventiesSong')));
      expect(resYear.map((s) => s.title), isNot(contains('NinetiesSong')));

      // Between with dots
      final criteriaPlays = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.between,
            value: '10..50',
          ),
        ],
      );
      final resPlays = await engine.evaluateCriteria(criteriaPlays);
      expect(resPlays.map((s) => s.title), contains('EightiesSong'));
      expect(resPlays.map((s) => s.title), isNot(contains('SeventiesSong')));
      expect(resPlays.map((s) => s.title), isNot(contains('NinetiesSong')));
    });

    test('bpm rule field is ignored safely and returns all songs', () async {
      await insertSong(id: 401, title: 'Song1');
      await insertSong(id: 402, title: 'Song2');

      final criteria = const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.equals,
            value: '120',
          ),
        ],
      );

      final result = await engine.evaluateCriteria(criteria);
      expect(result.length, 2);
    });

    test('empty criteria returns all songs', () async {
      await insertSong(id: 1, title: 'A');
      await insertSong(id: 2, title: 'B');

      final result = await engine.evaluateCriteria(const SmartCriteria());
      expect(result.length, 2);
    });
  });
}
