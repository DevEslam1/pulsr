// test/data/repositories/article_sort_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

/// Verifies that title/artist/album sorts ignore a leading English article in
/// SQL, while every other sort key keeps its previous ordering.
void main() {
  late AppDatabase db;
  late MusicRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSong({
    required int id,
    required String title,
    required String artist,
    required String album,
    int durationMs = 0,
    int? year,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          artist: Value(artist),
          album: Value(album),
          durationMs: Value(durationMs),
          year: Value(year),
          path: '/music/test_$id.flac',
        ));
  }

  Future<List<int>> orderedIds({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    final result = await repository.getAllSongs(
      sortBy: sortBy,
      ascending: ascending,
      limit: limit,
      offset: offset,
    );
    final songs = result.getOrElse((_) => <SongsTableData>[]);
    return songs.map((song) => song.id).toList();
  }

  /// The four reference rows: two of them collapse to `Beatles` once the
  /// article is ignored.
  Future<void> insertReferenceRows() async {
    await insertSong(
        id: 1, title: 'The Beatles', artist: 'X1', album: 'X1');
    await insertSong(
        id: 2, title: 'A Perfect Circle', artist: 'X2', album: 'X2');
    await insertSong(id: 3, title: 'Anathema', artist: 'X3', album: 'X3');
    await insertSong(id: 4, title: 'Beatles', artist: 'X4', album: 'X4');
  }

  Future<void> insertAlbum({required int id, required String title}) async {
    await db.into(db.albumsTable).insert(AlbumsTableCompanion.insert(
          id: Value(id),
          title: title,
          songCount: const Value(1),
        ));
  }

  Future<void> insertArtist({required int id, required String name}) async {
    await db.into(db.artistsTable).insert(ArtistsTableCompanion.insert(
          id: Value(id),
          name: name,
          songCount: const Value(1),
        ));
  }

  Future<List<String>> albumTitles() async {
    final result = await repository.watchAlbums().first;
    return result
        .getOrElse((_) => <AlbumsTableData>[])
        .map((album) => album.title)
        .toList();
  }

  Future<List<String>> artistNames() async {
    final result = await repository.watchArtists().first;
    return result
        .getOrElse((_) => <ArtistsTableData>[])
        .map((artist) => artist.name)
        .toList();
  }

  group('article-insensitive SQL ordering', () {
    test('title: The Beatles sorts next to Beatles, after Anathema', () async {
      await insertReferenceRows();

      // Stripped: Anathema < Beatles = Beatles < Perfect Circle. The Beatles /
      // Beatles tie is broken by id (1 before 4).
      expect(await orderedIds(sortBy: 'title'), [3, 1, 4, 2]);
    });

    test('artist: leading article is ignored for the primary term',
        () async {
      await insertSong(id: 1, title: 'Z1', artist: 'The Beatles', album: 'A1');
      await insertSong(
          id: 2, title: 'Z2', artist: 'A Perfect Circle', album: 'A2');
      await insertSong(id: 3, title: 'Z3', artist: 'Anathema', album: 'A3');
      await insertSong(id: 4, title: 'Z4', artist: 'Beatles', album: 'A4');

      // Beatles/Beatles tie is broken by the article-insensitive title: Z1
      // precedes Z4, so `The Beatles` (id 1) comes before `Beatles` (id 4).
      expect(await orderedIds(sortBy: 'artist'), [3, 1, 4, 2]);
    });

    test('album: leading article is ignored for the primary term', () async {
      await insertSong(id: 1, title: 'Z1', artist: 'Y1', album: 'The Beatles');
      await insertSong(
          id: 2, title: 'Z2', artist: 'Y2', album: 'A Perfect Circle');
      await insertSong(id: 3, title: 'Z3', artist: 'Y3', album: 'Anathema');
      await insertSong(id: 4, title: 'Z4', artist: 'Y4', album: 'Beatles');

      expect(await orderedIds(sortBy: 'album'), [3, 1, 4, 2]);
    });

    test('descending sort reverses the article-insensitive order', () async {
      await insertReferenceRows();

      expect(await orderedIds(sortBy: 'title', ascending: false), [2, 1, 4, 3]);
    });

    test('article detection is case-insensitive', () async {
      await insertSong(id: 20, title: 'THE BEATLES', artist: 'X', album: 'X');
      await insertSong(id: 21, title: 'Cat', artist: 'X', album: 'X');

      // Without article handling 'Cat' < 'THE BEATLES'; with it 'BEATLES' <
      // 'Cat', so the article row moves first.
      expect(await orderedIds(sortBy: 'title'), [20, 21]);
    });

    test('article is detected after a leading quote or bracket', () async {
      await insertSong(id: 10, title: '"The Beatles', artist: 'X', album: 'X');
      await insertSong(
          id: 11, title: '(A Perfect Circle)', artist: 'X', album: 'X');
      await insertSong(id: 12, title: 'Anathema', artist: 'X', album: 'X');

      // Stripped: Anathema < Beatles < Perfect Circle).
      expect(await orderedIds(sortBy: 'title'), [12, 10, 11]);
    });

    test('paging stays consistent with the full ordering', () async {
      await insertReferenceRows();

      final full = await orderedIds(sortBy: 'title');
      final firstPage = await orderedIds(sortBy: 'title', limit: 2);
      final secondPage =
          await orderedIds(sortBy: 'title', limit: 2, offset: 2);

      expect([...firstPage, ...secondPage], full);
    });
  });

  group('albums and artists follow the songs tab ordering', () {
    test('albums: The Beatles precedes Bowie', () async {
      await insertAlbum(id: 1, title: 'Bowie');
      await insertAlbum(id: 2, title: 'The Beatles');
      await insertAlbum(id: 3, title: 'Abbey Road');

      expect(await albumTitles(), ['Abbey Road', 'The Beatles', 'Bowie']);
    });

    test('artists: The Beatles precedes Bowie', () async {
      await insertArtist(id: 1, name: 'Bowie');
      await insertArtist(id: 2, name: 'The Beatles');
      await insertArtist(id: 3, name: 'ABBA');

      expect(await artistNames(), ['ABBA', 'The Beatles', 'Bowie']);
    });

    test('songs keep article-insensitive artist ordering', () async {
      await insertSong(id: 1, title: 'T1', artist: 'Bowie', album: 'X');
      await insertSong(id: 2, title: 'T2', artist: 'The Beatles', album: 'X');

      expect(await orderedIds(sortBy: 'artist'), [2, 1]);
    });
  });

  group('non-article sort keys are unchanged', () {
    test('duration ignores titles that look like articles', () async {
      await insertSong(
          id: 1, title: 'The Beatles', artist: 'X', album: 'X', durationMs: 400);
      await insertSong(
          id: 2,
          title: 'A Perfect Circle',
          artist: 'X',
          album: 'X',
          durationMs: 100);
      await insertSong(
          id: 3, title: 'Anathema', artist: 'X', album: 'X', durationMs: 300);
      await insertSong(
          id: 4, title: 'Beatles', artist: 'X', album: 'X', durationMs: 200);

      expect(await orderedIds(sortBy: 'duration'), [2, 4, 3, 1]);
      expect(await orderedIds(sortBy: 'duration', ascending: false),
          [1, 3, 4, 2]);
    });

    test('year sorts by the year column, not by title', () async {
      await insertSong(
          id: 1, title: 'The Beatles', artist: 'X', album: 'X', year: 1999);
      await insertSong(
          id: 2, title: 'A Perfect Circle', artist: 'X', album: 'X', year: 2001);
      await insertSong(
          id: 3, title: 'Anathema', artist: 'X', album: 'X', year: 1990);
      await insertSong(
          id: 4, title: 'Beatles', artist: 'X', album: 'X', year: 2005);

      expect(await orderedIds(sortBy: 'year'), [3, 1, 2, 4]);
    });

    test('ties on a numeric key still fall through to id ascending', () async {
      await insertSong(
          id: 8, title: 'Zeta', artist: 'X', album: 'X', durationMs: 500);
      await insertSong(
          id: 7, title: 'Alpha', artist: 'X', album: 'X', durationMs: 500);

      expect(await orderedIds(sortBy: 'duration'), [7, 8]);
    });
  });
}
