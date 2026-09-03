import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

/// Phase 5 (B-56): watchRecentlyPlayed must be a single unified query that
/// includes both local and streamed YTM songs ordered by lastPlayed desc and
/// excludes unresolved ytmusic:// placeholder paths.
///
/// Unlike recently_played_consistency_test.dart (which asserts the SQL filter
/// semantics against an inline query), this test exercises the actual
/// repository stream definition in MusicRepository.watchRecentlyPlayed.
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

  Future<void> insertSong({
    required int id,
    required String title,
    required String path,
    required String source,
    required int lastPlayedMs,
  }) async {
    await db.into(db.songsTable).insert(
          SongsTableCompanion.insert(
            id: Value(id),
            title: title,
            path: path,
            isFavorite: const Value(false),
            isMissing: const Value(false),
            playCount: const Value(1),
            lastPlayed: Value(lastPlayedMs),
            lastPositionMs: const Value(0),
            source: Value(source),
            isDownloaded: const Value(false),
          ),
        );
  }

  group('watchRecentlyPlayed unified query (B-56)', () {
    test('streams local + streamed YTM songs and excludes ytmusic:// placeholders',
        () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertSong(
        id: 1,
        title: 'Local Song',
        path: '/storage/music/local.mp3',
        source: SongSource.local,
        lastPlayedMs: now - 1000,
      );
      await insertSong(
        id: 2,
        title: 'Streamed YTM Song',
        path: 'https://googlevideo.com/videoplayback?id=123',
        source: SongSource.youtube,
        lastPlayedMs: now,
      );
      await insertSong(
        id: 3,
        title: 'Placeholder Song',
        path: 'ytmusic://track_xyz',
        source: SongSource.youtube,
        lastPlayedMs: now - 2000,
      );

      final result = await repo.watchRecentlyPlayed().first;

      result.fold(
        (failure) => fail('Expected a successful emission, got $failure'),
        (songs) {
          expect(
            songs.map((s) => s.title),
            equals(['Streamed YTM Song', 'Local Song']),
            reason: 'ordered by lastPlayed desc, ytmusic:// placeholder excluded',
          );
          expect(songs.any((s) => s.path.startsWith('ytmusic://')), isFalse);
        },
      );
    });

    test('respects the limit parameter on the unified stream', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 3; i++) {
        await insertSong(
          id: i,
          title: 'Song $i',
          path: '/storage/music/song_$i.mp3',
          source: SongSource.local,
          lastPlayedMs: now - i,
        );
      }

      final result = await repo.watchRecentlyPlayed(limit: 2).first;

      result.fold(
        (failure) => fail('Expected a successful emission, got $failure'),
        (songs) => expect(
          songs.map((s) => s.title),
          equals(['Song 0', 'Song 1']),
        ),
      );
    });
  });
}
