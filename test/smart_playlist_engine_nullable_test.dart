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
    String? path,
    String? codec,
    int? bitDepth,
    int? dateAdded,
    int playCount = 0,
    int? year,
    int? lastPlayed,
    String? genre,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: path ?? '/music/$title.mp3',
          codec: Value(codec),
          bitDepth: Value(bitDepth),
          dateAdded: Value(dateAdded),
          playCount: Value(playCount),
          year: Value(year),
          lastPlayed: Value(lastPlayed),
          genre: Value(genre),
        ));
  }

  test('smart playlist with isLossless criteria excludes null bitDepth without error', () async {
    await insertSong(id: 1, title: 'MP3 Track', codec: 'MP3', bitDepth: null);
    await insertSong(id: 2, title: 'FLAC Hi-Res', codec: 'FLAC', bitDepth: 24);

    final criteria = SmartCriteria(
      matchAll: true,
      rules: const [
        SmartRule(
          field: SmartRuleField.isLossless,
          operator: SmartOperator.equals,
          value: 'true',
        ),
      ],
    );

    final results = await engine.evaluateCriteria(criteria);
    expect(results.length, 1);
    expect(results.first.id, 2);
    expect(results.first.title, 'FLAC Hi-Res');
  });

  test('smart playlist with year and decade criteria guards null year columns', () async {
    await insertSong(id: 10, title: 'Unknown Year', year: null);
    await insertSong(id: 11, title: '80s Classic', year: 1985);

    final criteria = SmartCriteria(
      matchAll: true,
      rules: const [
        SmartRule(
          field: SmartRuleField.decade,
          operator: SmartOperator.equals,
          value: '1980',
        ),
      ],
    );

    final results = await engine.evaluateCriteria(criteria);
    expect(results.length, 1);
    expect(results.first.id, 11);
  });
}
