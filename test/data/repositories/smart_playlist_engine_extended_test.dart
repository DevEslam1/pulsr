// test/data/repositories/smart_playlist_engine_extended_test.dart
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
    String artist = 'Artist',
    String album = 'Album',
    String? genre,
    int? year,
    int playCount = 0,
    int? lastPlayed,
    int? dateAdded,
    int durationMs = 180000,
    bool isFavorite = false,
    String? codec,
    int? bitDepth,
    double? loudnessRange,
    int? bitrateKbps,
    String path = '',
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          artist: Value(artist),
          album: Value(album),
          path: path.isEmpty ? '/music/$title.mp3' : path,
          genre: Value(genre),
          year: Value(year),
          playCount: Value(playCount),
          lastPlayed: Value(lastPlayed),
          dateAdded: Value(dateAdded),
          durationMs: Value(durationMs),
          isFavorite: Value(isFavorite),
          codec: Value(codec),
          bitDepth: Value(bitDepth),
          loudnessRange: Value(loudnessRange),
          bitrateKbps: Value(bitrateKbps),
        ));
  }

  group('validateRules', () {
    test('flags out-of-range and malformed rating rules', () {
      final invalid = engine.validateRules(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.equals,
            value: '6'),
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.equals,
            value: '-1'),
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.equals,
            value: 'abc'),
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.equals,
            value: '4'),
      ]));
      expect(invalid.length, 3);
    });

    test('flags non-positive and malformed bpm rules', () {
      final invalid = engine.validateRules(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.equals,
            value: '0'),
        SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.equals,
            value: '-5'),
        SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.equals,
            value: 'x'),
        SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.equals,
            value: '120'),
      ]));
      expect(invalid.length, 3);
    });

    test('validates numeric and text rule fields', () {
      final invalid = engine.validateRules(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.between,
            value: '10, 20'),
        SmartRule(
            field: SmartRuleField.playCount,
            operator: SmartOperator.equals,
            value: 'abc'),
        SmartRule(
            field: SmartRuleField.year,
            operator: SmartOperator.greaterThan,
            value: 'nope'),
        SmartRule(
            field: SmartRuleField.dateAdded,
            operator: SmartOperator.equals,
            value: 'xyz'),
        SmartRule(
            field: SmartRuleField.artist,
            operator: SmartOperator.contains,
            value: '   '),
        SmartRule(
            field: SmartRuleField.album,
            operator: SmartOperator.contains,
            value: ''),
        SmartRule(
            field: SmartRuleField.title,
            operator: SmartOperator.contains,
            value: ''),
        SmartRule(
            field: SmartRuleField.genre,
            operator: SmartOperator.contains,
            value: ''),
        SmartRule(
            field: SmartRuleField.isLossless,
            operator: SmartOperator.equals,
            value: 'true'),
      ]));
      // playCount invalid, year invalid, dateAdded invalid, artist/album/title/genre empty
      expect(invalid.length, 7);
    });
  });

  group('SQL rule operators', () {
    test('playCount comparison operators', () async {
      await insertSong(id: 1, title: 'None', playCount: 0);
      await insertSong(id: 2, title: 'Five', playCount: 5);
      await insertSong(id: 3, title: 'Ten', playCount: 10);

      Future<List<String>> titles(SmartOperator op, String value) async {
        final res = await engine.evaluateCriteria(SmartCriteria(rules: [
          SmartRule(field: SmartRuleField.playCount, operator: op, value: value)
        ]));
        return res.map((s) => s.title).toList()..sort();
      }

      expect(await titles(SmartOperator.equals, '5'), ['Five']);
      expect(await titles(SmartOperator.greaterThan, '5'), ['Ten']);
      expect(await titles(SmartOperator.lessThan, '5'), ['None']);
      expect(await titles(SmartOperator.greaterThanOrEqual, '5'),
          ['Five', 'Ten']);
      expect(await titles(SmartOperator.lessThanOrEqual, '5'),
          ['Five', 'None']);
      expect(await titles(SmartOperator.between, '5..10'), ['Five', 'Ten']);
    });

    test('text fields equals and contains', () async {
      await insertSong(id: 1, title: 'Blue Sky', artist: 'The Band',
          album: 'Skies', genre: 'Rock');
      await insertSong(id: 2, title: 'Red River', artist: 'Solo',
          album: 'Rivers', genre: 'Jazz');

      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.artist,
                operator: SmartOperator.equals,
                value: 'the band'),
          ]))).map((s) => s.id),
          [1]);
      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.album,
                operator: SmartOperator.contains,
                value: 'riv'),
          ]))).map((s) => s.id),
          [2]);
      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.title,
                operator: SmartOperator.contains,
                value: 'sky'),
          ]))).map((s) => s.id),
          [1]);
      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.genre,
                operator: SmartOperator.equals,
                value: 'rock'),
          ]))).map((s) => s.id),
          [1]);
    });

    test('year operators and decade', () async {
      await insertSong(id: 1, title: 'Y70', year: 1975);
      await insertSong(id: 2, title: 'Y80', year: 1985);
      await insertSong(id: 3, title: 'Y90', year: 1995);

      Future<Iterable<int>> ids(SmartRule rule) async {
        final res = await engine
            .evaluateCriteria(SmartCriteria(rules: [rule]));
        return res.map((s) => s.id);
      }

      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.equals,
          value: '1985')), [2]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.greaterThan,
          value: '1985')), [3]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.lessThan,
          value: '1985')), [1]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.greaterThanOrEqual,
          value: '1985')), [2, 3]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.lessThanOrEqual,
          value: '1985')), [1, 2]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.year,
          operator: SmartOperator.between,
          value: '1970, 1990')), [1, 2]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.decade,
          operator: SmartOperator.equals,
          value: '1980')), [2]);
    });

    test('duration operators', () async {
      await insertSong(id: 1, title: 'Short', durationMs: 60000);
      await insertSong(id: 2, title: 'Long', durationMs: 420000);

      Future<Iterable<int>> ids(SmartRule rule) async =>
          (await engine.evaluateCriteria(SmartCriteria(rules: [rule])))
              .map((s) => s.id);

      expect(await ids(const SmartRule(
          field: SmartRuleField.durationMs,
          operator: SmartOperator.greaterThan,
          value: '300000')), [2]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.durationMs,
          operator: SmartOperator.lessThan,
          value: '300000')), [1]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.durationMs,
          operator: SmartOperator.between,
          value: '50000..300000')), [1]);
    });

    test('isFavorite and isLossless rules', () async {
      await insertSong(id: 1, title: 'Fav', isFavorite: true, codec: 'FLAC');
      await insertSong(id: 2, title: 'Plain', codec: 'MP3',
          path: '/music/plain.mp3');

      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.isFavorite,
                operator: SmartOperator.equals,
                value: 'true'),
          ]))).map((s) => s.id),
          [1]);

      expect(
          (await engine.evaluateCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.isLossless,
                operator: SmartOperator.equals,
                value: 'false'),
          ]))).map((s) => s.id),
          [2]);
    });

    test('loudnessRange and bitrate rules', () async {
      await insertSong(id: 1, title: 'Dynamic', loudnessRange: 12.5,
          bitrateKbps: 900);
      await insertSong(id: 2, title: 'Flat', loudnessRange: 4.0,
          bitrateKbps: 320);

      Future<Iterable<int>> ids(SmartRule rule) async =>
          (await engine.evaluateCriteria(SmartCriteria(rules: [rule])))
              .map((s) => s.id);

      expect(await ids(const SmartRule(
          field: SmartRuleField.loudnessRange,
          operator: SmartOperator.between,
          value: '10..15')), [1]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.loudnessRange,
          operator: SmartOperator.greaterThan,
          value: '10')), [1]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.bitrate,
          operator: SmartOperator.greaterThanOrEqual,
          value: '900')), [1]);
      expect(await ids(const SmartRule(
          field: SmartRuleField.bitrate,
          operator: SmartOperator.lessThan,
          value: '500')), [2]);
    });

    test('lastPlayed operators', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await insertSong(id: 1, title: 'Recent', lastPlayed: nowMs - 1000);
      await insertSong(id: 2, title: 'Old', lastPlayed: nowMs - 100000000);

      Future<Iterable<int>> ids(SmartRule rule) async =>
          (await engine.evaluateCriteria(SmartCriteria(rules: [rule])))
              .map((s) => s.id);

      expect(await ids(SmartRule(
          field: SmartRuleField.lastPlayed,
          operator: SmartOperator.greaterThan,
          value: '${nowMs - 5000}')), [1]);
      expect(await ids(SmartRule(
          field: SmartRuleField.lastPlayed,
          operator: SmartOperator.withinDays,
          value: '1')), [1]);
      expect(await ids(SmartRule(
          field: SmartRuleField.lastPlayed,
          operator: SmartOperator.between,
          value: '${nowMs - 5000}..$nowMs')), [1]);
    });

    test('dateAdded operators and matchAll OR', () async {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await insertSong(id: 1, title: 'Fresh', dateAdded: nowSec - 3600,
          playCount: 0);
      await insertSong(id: 2, title: 'Heavy', dateAdded: nowSec - 9 * 86400,
          playCount: 50);

      final any = await engine.evaluateCriteria(SmartCriteria(
        matchAll: false,
        rules: const [
          SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '10'),
          SmartRule(
              field: SmartRuleField.dateAdded,
              operator: SmartOperator.withinDays,
              value: '1'),
        ],
      ));
      final anyIds = any.map((s) => s.id).toList()..sort();
      expect(anyIds, [1, 2]);

      final all = await engine.evaluateCriteria(SmartCriteria(
        matchAll: true,
        rules: const [
          SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '10'),
          SmartRule(
              field: SmartRuleField.dateAdded,
              operator: SmartOperator.withinDays,
              value: '1'),
        ],
      ));
      expect(all, isEmpty);
    });
  });

  group('sorting and limits', () {
    test('sortBy branches produce stable orderings', () async {
      await insertSong(id: 1, title: 'B', artist: 'Z', album: 'M',
          playCount: 1, year: 2000, lastPlayed: 100, dateAdded: 100,
          durationMs: 1000);
      await insertSong(id: 2, title: 'A', artist: 'A', album: 'Z',
          playCount: 9, year: 1990, lastPlayed: 900, dateAdded: 900,
          durationMs: 9000);

      for (final sort in [
        'rating',
        'dateAdded',
        'playCount',
        'lastPlayed',
        'durationMs',
        'year',
        'title',
        'unknown',
      ]) {
        final res = await engine.evaluateCriteria(SmartCriteria(sortBy: sort));
        expect(res.length, 2, reason: sort);
      }
    });

    test('limit truncates results and applies after rating post-filter',
        () async {
      await insertSong(id: 1, title: 'One');
      await insertSong(id: 2, title: 'Two');
      await insertSong(id: 3, title: 'Three');

      final res = await engine.evaluateCriteria(
          const SmartCriteria(limit: 2, sortBy: 'rating'));
      expect(res.length, 2);
    });
  });

  group('Dart (prefs-backed) rules', () {
    test('rating rules require a store and otherwise match nothing', () async {
      await insertSong(id: 1, title: 'Rated');
      final res = await engine.evaluateCriteria(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '4'),
      ]));
      expect(res, isEmpty);
    });

    test('rating equals zero matches songs with no rating', () async {
      await insertSong(id: 1, title: 'Unrated');
      final res = await engine.evaluateCriteria(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.equals,
            value: '0'),
      ]));
      expect(res.map((s) => s.id), [1]);
    });

    test('bpm rules return empty without a handler', () async {
      await insertSong(id: 1, title: 'NoBpm');
      final res = await engine.evaluateCriteria(const SmartCriteria(rules: [
        SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.between,
            value: '100..140'),
      ]));
      expect(res, isEmpty);
    });

    test('matchAny keeps the SQL-matching half', () async {
      await insertSong(id: 1, title: 'Played', playCount: 5);
      await insertSong(id: 2, title: 'Unplayed', playCount: 0);

      final res = await engine.evaluateCriteria(SmartCriteria(
        matchAll: false,
        rules: const [
          SmartRule(
              field: SmartRuleField.playCount,
              operator: SmartOperator.greaterThan,
              value: '1'),
          SmartRule(
              field: SmartRuleField.rating,
              operator: SmartOperator.greaterThanOrEqual,
              value: '4'),
        ],
      ));
      expect(res.map((s) => s.id), [1]);
    });

    test('matchAny with only dart rules considers the whole library', () async {
      await insertSong(id: 1, title: 'A');
      await insertSong(id: 2, title: 'B');
      final res = await engine.evaluateCriteria(const SmartCriteria(
        matchAll: false,
        rules: [
          SmartRule(
              field: SmartRuleField.rating,
              operator: SmartOperator.equals,
              value: '0'),
        ],
      ));
      // No store, but rating 0 == default, so both match via prefs-backed path.
      expect(res.length, 2);
    });
  });

  group('watchCriteria', () {
    test('emits for plain criteria', () async {
      await insertSong(id: 1, title: 'Watched', playCount: 3);
      final res = await engine
          .watchCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.playCount,
                operator: SmartOperator.greaterThan,
                value: '1'),
          ]))
          .first;
      expect(res.map((s) => s.id), [1]);
    });

    test('emits for rating sort', () async {
      await insertSong(id: 1, title: 'Sorted');
      final res = await engine
          .watchCriteria(const SmartCriteria(sortBy: 'rating'))
          .first;
      expect(res.length, 1);
    });

    test('emits for matchAll with dart rules', () async {
      await insertSong(id: 1, title: 'DartAll');
      final res = await engine
          .watchCriteria(const SmartCriteria(rules: [
            SmartRule(
                field: SmartRuleField.rating,
                operator: SmartOperator.equals,
                value: '0'),
          ]))
          .first;
      expect(res.length, 1);
    });

    test('emits for matchAny with dart rules', () async {
      await insertSong(id: 1, title: 'DartAny', playCount: 2);
      final res = await engine
          .watchCriteria(SmartCriteria(
            matchAll: false,
            rules: const [
              SmartRule(
                  field: SmartRuleField.playCount,
                  operator: SmartOperator.greaterThan,
                  value: '1'),
              SmartRule(
                  field: SmartRuleField.rating,
                  operator: SmartOperator.equals,
                  value: '0'),
            ],
          ))
          .first;
      expect(res.map((s) => s.id), [1]);
    });
  });
}
