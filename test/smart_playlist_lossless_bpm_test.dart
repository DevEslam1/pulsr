// test/smart_playlist_lossless_bpm_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';

/// Regression tests for the SmartPlaylistEngine fixes:
///
/// * `isLossless=false` must match LOSSY tracks (it previously returned the
///   lossless predicate regardless of the requested value), and
/// * the `bpm` rule (no BPM column indexed) must be skipped safely instead
///   of filtering everything out.
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
    required String path,
    String? codec,
    int? bitDepth,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: path,
          codec: Value(codec),
          bitDepth: Value(bitDepth),
        ));
  }

  group('SmartPlaylistEngine lossless / bpm rules', () {
    test('isLossless=true matches lossless containers and hi-bit-depth',
        () async {
      await insertSong(
          id: 1, title: 'FlacTrack', path: '/m/a.flac', codec: 'FLAC');
      await insertSong(
          id: 2, title: 'HiResMp3', path: '/m/b.mp3', codec: 'MP3', bitDepth: 24);
      await insertSong(
          id: 3, title: 'PlainMp3', path: '/m/c.mp3', codec: 'MP3', bitDepth: 16);

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.isLossless,
            operator: SmartOperator.equals,
            value: 'true',
          ),
        ],
      ));

      final titles = result.map((s) => s.title).toSet();
      expect(titles, containsAll({'FlacTrack', 'HiResMp3'}));
      expect(titles, isNot(contains('PlainMp3')));
    });

    test('isLossless=false matches lossy tracks, not lossless ones',
        () async {
      await insertSong(
          id: 1, title: 'FlacTrack', path: '/m/a.flac', codec: 'FLAC');
      await insertSong(
          id: 2, title: 'PlainMp3', path: '/m/c.mp3', codec: 'MP3', bitDepth: 16);

      for (final falsy in ['false', '0', 'no']) {
        final result = await engine.evaluateCriteria(SmartCriteria(
          rules: [
            SmartRule(
              field: SmartRuleField.isLossless,
              operator: SmartOperator.equals,
              value: falsy,
            ),
          ],
        ));
        final titles = result.map((s) => s.title).toSet();
        expect(titles, contains('PlainMp3'), reason: 'value=$falsy');
        expect(titles, isNot(contains('FlacTrack')), reason: 'value=$falsy');
      }
    });

    test('bpm rule is skipped safely and returns all songs', () async {
      await insertSong(id: 1, title: 'One', path: '/m/1.mp3', codec: 'MP3');
      await insertSong(id: 2, title: 'Two', path: '/m/2.mp3', codec: 'MP3');

      final result = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.bpm,
            operator: SmartOperator.greaterThan,
            value: '120',
          ),
        ],
      ));

      expect(result.map((s) => s.title).toSet(), {'One', 'Two'});
    });
  });
}
