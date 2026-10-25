// Repository-level discovery exclusion suite: songs inside hidden folders must
// never leak into recently played/added, top played, genres, years, stats or
// downloaded queries.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/music_repository.dart';

void main() {
  late AppDatabase db;
  late MusicRepository repo;

  const excluded = ['/music/hidden'];

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSong({
    required int id,
    required String path,
    String title = 'Track',
    String genre = 'Rock',
    int year = 2020,
    int playCount = 1,
    int lastPlayed = 1,
    bool isDownloaded = false,
    String? remoteId,
    int? dateAdded,
  }) async {
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          path: path,
          genre: Value(genre),
          year: Value(year),
          playCount: Value(playCount),
          lastPlayed: Value(lastPlayed),
          isDownloaded: Value(isDownloaded),
          remoteId: Value(remoteId),
          dateAdded: Value(dateAdded ?? id),
          source: const Value(SongSource.local),
        ));
  }

  setUp(() async {
    await insertSong(id: 1, path: '/music/visible/a.mp3', title: 'Visible');
    await insertSong(id: 2, path: '/music/hidden/b.mp3', title: 'Hidden');
    // Same prefix but not inside the excluded folder: must stay visible.
    await insertSong(
        id: 3, path: '/music/hidden2/c.mp3', title: 'HiddenSibling');
    await insertSong(
        id: 4,
        path: '/music/hidden/d.mp3',
        title: 'HiddenDownload',
        isDownloaded: true);
    await insertSong(
        id: 5,
        path: '/music/visible/dl.mp3',
        title: 'VisibleDownload',
        isDownloaded: true);
  });

  test('recently played excludes hidden folders', () async {
    final res = await repo
        .watchRecentlyPlayed(
          limit: 50,
          excludedFolders: excluded,
        )
        .first;
    final titles = res.getOrElse((_) => []).map((s) => s.title).toList();
    expect(titles, containsAll(['Visible', 'HiddenSibling']));
    expect(titles, isNot(contains('Hidden')));
  });

  test('recently added excludes hidden folders', () async {
    final res = await repo
        .watchRecentlyAdded(
          limit: 50,
          excludedFolders: excluded,
        )
        .first;
    final titles = res.getOrElse((_) => []).map((s) => s.title).toList();
    expect(titles, isNot(contains('Hidden')));
    expect(titles, contains('Visible'));
  });

  test('top played excludes hidden folders', () async {
    final res = await repo
        .watchTopPlayed(
          limit: 50,
          excludedFolders: excluded,
        )
        .first;
    final titles = res.getOrElse((_) => []).map((s) => s.title).toList();
    expect(titles, isNot(contains('Hidden')));
    expect(titles, contains('Visible'));
  });

  test('genres and years exclude hidden-folder counts', () async {
    final genres = await repo.watchGenres(excludedFolders: excluded).first;
    final rock =
        genres.getOrElse((_) => []).firstWhere((g) => g.name == 'Rock');
    expect(rock.songCount, 3);

    final years = await repo.watchYears(excludedFolders: excluded).first;
    final year2020 =
        years.getOrElse((_) => []).firstWhere((y) => y.year == 2020);
    expect(year2020.songCount, 3);
  });

  test(
      'downloaded stream returns rows beyond a paginated page and respects '
      'exclusions', () async {
    final res = await repo
        .watchDownloadedSongs(
          excludedFolders: excluded,
        )
        .first;
    final titles = res.getOrElse((_) => []).map((s) => s.title).toList();
    expect(titles, isNot(contains('HiddenDownload')));
    expect(titles, contains('VisibleDownload'));
  });
}
