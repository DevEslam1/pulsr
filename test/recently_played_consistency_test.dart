import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Recently Played Consistency (B-43 / B-56)', () {
    test('returns both local and streamed YTM songs with lastPlayed, excluding ytmusic:// protocol', () async {
      final now = DateTime.now();

      // 1. Local track played
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(1),
              title: 'Local Song',
              artist: const Value('Artist A'),
              album: const Value('Album A'),
              durationMs: const Value(180000),
              path: '/storage/music/local.mp3',
              isFavorite: const Value(false),
              isMissing: const Value(false),
              playCount: const Value(1),
              lastPlayed: Value(now.millisecondsSinceEpoch - 1000),
              lastPositionMs: const Value(50000),
              source: const Value(SongSource.local),
              isDownloaded: const Value(false),
            ),
          );

      // 2. Streamed online YTM track played (source = youtube, path = cache/http URL)
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(2),
              title: 'Streamed YTM Song',
              artist: const Value('Artist B'),
              album: const Value('Album B'),
              durationMs: const Value(200000),
              path: 'https://googlevideo.com/videoplayback?id=123',
              isFavorite: const Value(false),
              isMissing: const Value(false),
              playCount: const Value(1),
              lastPlayed: Value(now.millisecondsSinceEpoch),
              lastPositionMs: const Value(10000),
              source: const Value(SongSource.youtube),
              isDownloaded: const Value(false),
            ),
          );

      // 3. Unresolved ytmusic:// placeholder path (should be excluded)
      await db.into(db.songsTable).insert(
            SongsTableCompanion.insert(
              id: const Value(3),
              title: 'Placeholder Song',
              artist: const Value('Artist C'),
              album: const Value('Album C'),
              durationMs: const Value(210000),
              path: 'ytmusic://track_xyz',
              isFavorite: const Value(false),
              isMissing: const Value(false),
              playCount: const Value(1),
              lastPlayed: Value(now.millisecondsSinceEpoch - 2000),
              lastPositionMs: const Value(0),
              source: const Value(SongSource.youtube),
              isDownloaded: const Value(false),
            ),
          );

      final results = await (db.select(db.songsTable)
            ..where((t) =>
                t.lastPlayed.isNotNull() &
                t.isMissing.equals(false) &
                t.path.like('ytmusic://%').not())
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.lastPlayed, mode: OrderingMode.desc)
            ]))
          .get();

      expect(results.length, equals(2));
      expect(results[0].title, equals('Streamed YTM Song'));
      expect(results[1].title, equals('Local Song'));
      expect(results.any((s) => s.path.startsWith('ytmusic://')), isFalse);
    });
  });
}
