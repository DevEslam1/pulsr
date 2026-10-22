// Regression tests for "Failed to add to playlist" on YouTube Music results:
// playlist_entries.song_id is an FK, but search results exist only in memory.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/domain/models/ytm_track.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // The production connection enables FK enforcement in beforeOpen; the
    // in-memory test executor does not, so opt in to mirror the real failure.
    await db.customStatement('PRAGMA foreign_keys = ON;');
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  const track = YtmTrack(
    videoId: 'vid42',
    title: 'Streamed Song',
    artist: 'YouTube',
    duration: Duration(minutes: 3),
  );

  Future<int> createPlaylist(String name) async =>
      (await repo.createPlaylist(name)).getOrElse((_) => -1);

  group('ensureSongPersisted', () {
    test('persists an in-memory YouTube track without favoriting it', () async {
      final song = track.toSongData();
      final id = (await repo.ensureSongPersisted(song))
          .getOrElse((failure) => -999);
      expect(id, song.id);

      final row = await (db.select(db.songsTable)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.source, SongSource.youtube);
      expect(row.path, 'ytmusic://vid42');
      expect(row.remoteId, 'vid42');
      expect(row.isFavorite, isFalse);
      expect(row.isDownloaded, isFalse);
    });

    test('is idempotent for repeated adds of the same track', () async {
      final song = track.toSongData();
      final first = (await repo.ensureSongPersisted(song))
          .getOrElse((failure) => -999);
      final second = (await repo.ensureSongPersisted(song))
          .getOrElse((failure) => -999);
      expect(second, first);

      final rows = await (db.select(db.songsTable)
            ..where((t) => t.remoteId.equals('vid42')))
          .get();
      expect(rows, hasLength(1));
    });

    test('reuses the downloaded local row for the same remote id', () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(500),
            title: 'Streamed Song',
            path: '/music/downloaded.m4a',
            remoteId: const Value('vid42'),
          ));

      final id = (await repo.ensureSongPersisted(track.toSongData()))
          .getOrElse((failure) => -999);
      expect(id, 500);
      final rows = await db.select(db.songsTable).get();
      expect(rows, hasLength(1));
    });

    test('resolves a stale local row id by path', () async {
      await db.into(db.songsTable).insert(SongsTableCompanion.insert(
            id: const Value(500),
            title: 'Local Song',
            path: '/music/local.mp3',
          ));

      const stale = SongsTableData(
        id: 999,
        title: 'Local Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 0,
        path: '/music/local.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
      );
      final id = (await repo.ensureSongPersisted(stale))
          .getOrElse((failure) => -999);
      expect(id, 500);
    });

    test('fails when a local song no longer exists anywhere', () async {
      const missing = SongsTableData(
        id: 999,
        title: 'Gone',
        artist: 'Artist',
        album: 'Album',
        durationMs: 0,
        path: '/music/gone.mp3',
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
        source: SongSource.local,
      );
      final result = await repo.ensureSongPersisted(missing);
      expect(result.isLeft(), isTrue);
    });
  });

  group('adding online songs to playlists', () {
    test('inserting an unpersisted YouTube id fails the FK', () async {
      final playlistId = await createPlaylist('Mix');
      final result = await repo.addSongToPlaylist(playlistId, track.songId);
      final failure = result.fold((f) => f, (_) => null);
      expect(failure, isNotNull);
      expect(failure!.error.toString().toUpperCase(), contains('FOREIGN KEY'));
    });

    test('persisting first lets the playlist membership succeed', () async {
      final playlistId = await createPlaylist('Mix');
      final id = (await repo.ensureSongPersisted(track.toSongData()))
          .getOrElse((failure) => -999);

      final add = await repo.addSongToPlaylist(playlistId, id);
      expect(add.isRight(), isTrue);

      final songs =
          (await repo.getPlaylistSongs(playlistId)).getOrElse((_) => []);
      expect(songs.map((s) => s.id), [id]);
    });
  });
}
