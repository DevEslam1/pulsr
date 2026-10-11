// test/data/db/fts_repair_watch_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('repairFtsIndex re-runs an active FTS search watch', () async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: const Value(1),
          title: 'Sunshine',
          path: '/music/sun.mp3',
        ));

    // Simulate a damaged/missing index while the watch is active.
    await db.customStatement('DROP TABLE songs_fts;');

    final result = await repo
        .watchAllSongs(searchQuery: 'sunshine')
        .firstWhere((r) => r.isRight())
        .timeout(const Duration(seconds: 5));

    final songs = result.getOrElse((_) => []);
    expect(songs.map((s) => s.title), contains('Sunshine'));
  });
}
