// test/db/migration_resilience_test.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

import 'legacy_schema.dart';

void main() {
  test('a failing v11 constraint step does not brick the database open',
      () async {
    final db = openLegacyDatabase(4, extraSql: [
      // Duplicate local path so the v11 dedup DELETE has a loser to remove...
      "INSERT INTO songs (id, title, artist, album, duration_ms, path, play_count) "
          "VALUES (78, 'Duplicate Track', 'Legacy Artist', 'Legacy Album', 210000, '/music/legacy.mp3', 0);",
      // ...and a trigger that aborts the migration's DELETE.
      'CREATE TRIGGER block_songs_delete BEFORE DELETE ON songs '
          "BEGIN SELECT RAISE(ABORT, 'blocked'); END;",
    ]);
    addTearDown(db.close);

    // Opening is lazy; the first query triggers the migration.
    final songs = await db.select(db.songsTable).get();

    expect(db.migrationFailed, isTrue,
        reason: 'the failed step must be surfaced, not thrown');
    expect(songs, hasLength(2),
        reason: 'the rolled-back migration must leave legacy rows intact');

    // The database must stay fully usable after the swallowed failure.
    await db.customStatement('DROP TRIGGER block_songs_delete;');
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: const Value(79),
          title: 'After Failure',
          path: '/music/after.mp3',
        ));
    expect((await db.select(db.songsTable).get()).length, 3);
  });
}
