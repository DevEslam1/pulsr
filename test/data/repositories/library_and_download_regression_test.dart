// test/data/repositories/library_and_download_regression_test.dart
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/core/services/yt_download_service.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/bpm_override_store.dart';
import 'package:pulsr/data/audio/song_rating_store.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/repositories/download_repository_impl.dart';
import 'package:pulsr/data/repositories/music_repository.dart';
import 'package:pulsr/data/repositories/smart_playlist_engine.dart';
import 'package:pulsr/domain/models/download_task.dart';
import 'package:pulsr/domain/models/smart_playlist_criteria.dart';
import 'package:pulsr/domain/usecases/folder_usecases.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockYtDownloadService extends Mock implements YtDownloadService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MusicRepository repo;

  setUpAll(() {
    registerFallbackValue(const SongsTableData(
      id: -1,
      title: 'Fallback',
      artist: 'Fallback',
      album: '',
      path: 'ytmusic://fallback',
      source: SongSource.youtube,
      remoteId: 'fallback',
      durationMs: 1000,
      isFavorite: false,
      playCount: 0,
      lastPositionMs: 0,
      isMissing: false,
      isDownloaded: false,
    ));
    registerFallbackValue(<String>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MusicRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<SongsTableData> insertSong({
    required int id,
    required String title,
    String artist = 'Artist',
    String album = 'Album',
    int? albumId,
    int? artistId,
    String? genre,
    int? year,
    int playCount = 0,
    int trackNumber = 0,
    int discNumber = 1,
    String? path,
    String source = SongSource.local,
    String? remoteId,
    int? cueStartMs,
    String? cueFile,
  }) async {
    final effectivePath = path ?? '/music/s_$id.mp3';
    await db.into(db.songsTable).insert(SongsTableCompanion.insert(
          id: Value(id),
          title: title,
          artist: Value(artist),
          album: Value(album),
          albumId: Value(albumId),
          artistId: Value(artistId),
          genre: Value(genre),
          year: Value(year),
          playCount: Value(playCount),
          trackNumber: Value(trackNumber),
          discNumber: Value(discNumber),
          path: effectivePath,
          source: Value(source),
          remoteId: Value(remoteId),
          cueStartMs: Value(cueStartMs),
          cueFile: Value(cueFile),
        ));
    return (await repo.getSongById(id)).getOrElse((_) => null)!;
  }

  _MockYtDownloadService buildYtDownloadMock() {
    final ytService = _MockYtDownloadService();
    when(() => ytService.setMaxConcurrentDownloads(any())).thenReturn(null);
    when(() => ytService.downloadPolicyBlock()).thenAnswer((_) async => null);
    when(() => ytService.getDownloadedPath(any())).thenReturn(null);
    when(() => ytService.markPaused(any())).thenReturn(null);
    when(() => ytService.clearPaused(any())).thenReturn(null);
    when(() => ytService.cancel(any())).thenReturn(null);
    when(() => ytService.deleteArtifactsFor(any())).thenAnswer((_) async {});
    when(() => ytService.cleanOrphanPartFiles(
          protectedVideoIds: any(named: 'protectedVideoIds'),
        )).thenAnswer((_) async {});
    return ytService;
  }

  DownloadTask downloadTask(String videoId) => DownloadTask(
        id: videoId,
        videoId: videoId,
        title: 'YT $videoId',
        artist: 'Artist',
        createdAt: DateTime(2026, 1, 1),
      );

  group('C-07 DownloadRepositoryImpl run token & teardown serialization', () {
    test('pause/cancel + immediate queueDownload waits and keeps new token',
        () async {
      final ytService = buildYtDownloadMock();

      final firstGate = Completer<Either<AppFailure, int>>();
      var calls = 0;
      when(() => ytService.download(
            any(),
            bypassInternalQueue: any(named: 'bypassInternalQueue'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) {
        calls++;
        if (calls == 1) return firstGate.future;
        return Future.value(const Right(999));
      });

      final dlRepo = DownloadRepositoryImpl(ytService, db);
      addTearDown(dlRepo.dispose);

      final tmpDir = Directory.systemTemp.createTempSync('dl_repo_reg_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final savedFile = File(p.join(tmpDir.path, 'saved.m4a'))
        ..writeAsBytesSync([0, 1, 2, 3]);

      await insertSong(
        id: 999,
        title: 'YT Song',
        path: savedFile.path,
        source: SongSource.local,
        remoteId: 'vidRace0001',
      );

      final firstRes = await dlRepo.queueDownload(downloadTask('vidRace0001'));
      expect(firstRes.isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);

      await dlRepo.pauseDownload('vidRace0001');
      final requeueFuture = dlRepo.queueDownload(downloadTask('vidRace0001'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Second run must NOT start while firstGate is still unwinding!
      expect(calls, 1);

      firstGate.complete(const Left(DownloadFailure('Download canceled')));
      final secondRes = await requeueFuture;
      expect(secondRes.isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final tasks = await dlRepo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.complete);
      expect(calls, 2);
    });

    test('StorageFailure fails immediately without exhausting retries',
        () async {
      final ytService = buildYtDownloadMock();

      var calls = 0;
      when(() => ytService.download(
            any(),
            bypassInternalQueue: any(named: 'bypassInternalQueue'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        calls++;
        return const Left(StorageFailure('No space left on device'));
      });

      final dlRepo = DownloadRepositoryImpl(ytService, db);
      addTearDown(dlRepo.dispose);

      final res = await dlRepo.queueDownload(downloadTask('vidDisk0001'));
      expect(res.isRight(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(calls, 1);
      final tasks = await dlRepo.getAllDownloads();
      expect(tasks.single.status, DownloadStatus.failed);
    });
  });

  group('H-27, H-28, H-29, H-30 MusicRepository & FolderUseCases', () {
    test('H-27 articleInsensitive + COLLATE NOCASE parity between table & FTS',
        () async {
      await insertSong(
          id: 1, title: 'the apple', artist: 'CommonArtist', path: '/music/1.mp3');
      await insertSong(
          id: 2, title: 'An Ant', artist: 'CommonArtist', path: '/music/2.mp3');
      await insertSong(
          id: 3, title: 'Zebra', artist: 'CommonArtist', path: '/music/3.mp3');

      final tableRes =
          (await repo.watchAllSongs(sortBy: 'title', ascending: true).first)
              .getOrElse((_) => []);
      expect(tableRes.map((s) => s.title).toList(),
          ['An Ant', 'the apple', 'Zebra']);

      // FTS5 index is auto-populated by songs_fts_insert SQLite triggers.
      final ftsRes = (await repo.watchAllSongs(
        searchQuery: 'commonartist',
        sortBy: 'title',
        ascending: true,
      ).first)
          .getOrElse((_) => []);
      expect(ftsRes.map((s) => s.title).toList(),
          ['An Ant', 'the apple', 'Zebra']);
    });

    test(
        'H-28 reactive excludedFolders updates watchAlbums/AlbumSongs/Artist/Genres/Years',
        () async {
      await db.into(db.artistsTable).insert(
          ArtistsTableCompanion.insert(id: const Value(10), name: 'Artist A'));
      await db.into(db.albumsTable).insert(AlbumsTableCompanion.insert(
            id: const Value(20),
            title: 'Album A',
            artist: const Value('Artist A'),
            year: const Value(2005),
            songCount: const Value(1),
          ));
      await insertSong(
        id: 1,
        title: 'Zeta',
        artist: 'Artist A',
        album: 'Album A',
        artistId: 10,
        albumId: 20,
        genre: 'Rock',
        year: 2022,
        playCount: 5,
        path: '/music/keep/a.mp3',
      );
      await insertSong(
        id: 2,
        title: 'Alpha',
        artist: 'Artist A',
        album: 'Album A',
        artistId: 10,
        albumId: 20,
        genre: 'Jazz',
        year: 2024,
        playCount: 5,
        path: '/music/secret/b.mp3',
      );

      final genresStream = repo.watchGenres();
      final yearsStream = repo.watchYears();
      final albumSongsStream = repo.watchAlbumSongs(20);
      final artistSongsStream = repo.watchArtistSongs(10);
      final albumsStream = repo.watchAlbums();

      expect(
        (await artistSongsStream.first)
            .getOrElse((_) => [])
            .map((s) => s.title),
        ['Alpha', 'Zeta'],
      );
      expect((await albumsStream.first).getOrElse((_) => []).length, 1);

      final futureExcludedAlbumSongs = albumSongsStream
          .firstWhere((r) => r.getOrElse((_) => []).length == 1);
      final futureExcludedArtistSongs = artistSongsStream
          .firstWhere((r) => r.getOrElse((_) => []).length == 1);
      final futureExcludedGenres =
          genresStream.firstWhere((r) => r.getOrElse((_) => []).length == 1);
      final futureExcludedYears =
          yearsStream.firstWhere((r) => r.getOrElse((_) => []).length == 1);

      await db.into(db.excludedFoldersTable).insert(
          ExcludedFoldersTableCompanion.insert(folderPath: '/music/secret/'));

      expect((await futureExcludedAlbumSongs).getOrElse((_) => []).single.id, 1);
      expect(
          (await futureExcludedArtistSongs).getOrElse((_) => []).single.id, 1);
      expect(
          (await futureExcludedGenres).getOrElse((_) => []).single.name, 'Rock');
      expect((await futureExcludedYears).getOrElse((_) => []).single.year, 2022);
    });

    test(
        'H-28 & H-29 updateSongTags updates albums.year, compilation albumArtist, & CUE rows',
        () async {
      await db.into(db.albumsTable).insert(AlbumsTableCompanion.insert(
            id: const Value(30),
            title: 'Comp',
            artist: const Value('Various Artists'),
            year: const Value(1999),
            songCount: const Value(2),
          ));
      await insertSong(
        id: 1,
        title: 'Track 1',
        artist: 'Guest One',
        album: 'Comp',
        albumId: 30,
        year: 1999,
        path: '/music/disc.flac',
      );
      await insertSong(
        id: 2,
        title: 'Chapter 1',
        artist: 'Guest One',
        album: 'Comp',
        albumId: 30,
        year: 1999,
        path: '/music/disc.flac',
        cueFile: '/music/disc.cue',
        cueStartMs: 0,
      );

      final res = await repo.updateSongTags(
        path: '/music/disc.flac',
        title: 'Track 1 Updated',
        artist: 'Guest Two',
        album: 'Comp',
        albumArtist: 'Various Artists',
        genre: 'Electronic',
        year: 2024,
        isCompilation: true,
      );
      expect(res.isRight(), isTrue);

      final cueSong = (await repo.getSongById(2)).getOrElse((_) => null)!;
      expect(cueSong.genre, 'Electronic');
      expect(cueSong.year, 2024);

      final albumRow =
          (await repo.getAlbumById(cueSong.albumId!)).getOrElse((_) => null)!;
      expect(albumRow.artist, 'Various Artists');
      expect(albumRow.year, 2024);
    });

    test(
        'H-30 FolderUseCases ancestor & separator normalization + deterministic folder order',
        () async {
      await insertSong(
          id: 1,
          title: 'Beta Track',
          trackNumber: 2,
          path: '/music/sub/nested/b.mp3');
      await insertSong(
          id: 2,
          title: 'Alpha Track',
          trackNumber: 1,
          path: '/music/sub/nested/a.mp3');
      await db.into(db.excludedFoldersTable).insert(
          ExcludedFoldersTableCompanion.insert(folderPath: r'\music\sub\'));

      final folders = (await FolderUseCases(repo).getFolderHierarchy())
          .getOrElse((_) => []);
      expect(folders.single.path, '/music/sub/nested');
      expect(folders.single.isExcluded, isTrue);

      final inFolder =
          (await repo.watchSongsInFolder('/music/sub/nested/').first)
              .getOrElse((_) => []);
      expect(inFolder.map((s) => s.id).toList(), [2, 1]);
    });
  });

  group('M-01 SmartPlaylistEngine sorts & >900 chunking', () {
    test('supports artist/album/bpm CASE-INSENSITIVE sorts & >900 narrowed IDs',
        () async {
      final ratingStore = SongRatingStore();
      final bpmStore = BpmOverrideStore();
      await ratingStore.ready;
      await bpmStore.ready;

      await db.batch((batch) {
        batch.insertAll(
          db.songsTable,
          [
            for (var i = 1; i <= 950; i++)
              SongsTableCompanion.insert(
                id: Value(i),
                title: 'Title ${951 - i}',
                artist:
                    Value(i == 1 ? 'b-artist' : (i == 2 ? 'A-Artist' : 'Z-Artist')),
                album: Value('Album $i'),
                playCount: Value(i),
                path: '/music/s_$i.mp3',
              ),
          ],
        );
      });

      for (var i = 1; i <= 940; i++) {
        await ratingStore.setRating('$i', 4);
      }
      final song1 = (await repo.getSongById(1)).getOrElse((_) => null)!;
      final song2 = (await repo.getSongById(2)).getOrElse((_) => null)!;
      await bpmStore.setBpmForTrack(PulsrAudioHandler.trackKeyFor(song1), 90);
      await bpmStore.setBpmForTrack(PulsrAudioHandler.trackKeyFor(song2), 148);

      final engine = SmartPlaylistEngine(
        db,
        ratingStore: ratingStore,
        bpmOverrideStore: bpmStore,
      );

      final artistSorted = await engine.evaluateCriteria(const SmartCriteria(
        sortBy: 'artist',
        sortAscending: true,
        limit: 3,
      ));
      expect(artistSorted.first.id, 2);
      expect(artistSorted[1].id, 1);

      final bpmSorted = await engine.evaluateCriteria(const SmartCriteria(
        sortBy: 'bpm',
        sortAscending: false,
        limit: 5,
      ));
      expect(bpmSorted.first.id, 2);

      // Rating > 0 rule triggers _narrowIdsForDartRules with 940 IDs (> 900 chunking)
      final highIds = await engine.evaluateCriteria(const SmartCriteria(
        rules: [
          SmartRule(
            field: SmartRuleField.rating,
            operator: SmartOperator.greaterThanOrEqual,
            value: '3',
          ),
        ],
        sortBy: 'artist',
        sortAscending: true,
      ));
      expect(highIds.length, 940);

      final watched = await engine
          .watchCriteria(const SmartCriteria(
            rules: [
              SmartRule(
                field: SmartRuleField.rating,
                operator: SmartOperator.greaterThanOrEqual,
                value: '3',
              ),
            ],
            sortBy: 'bpm',
            sortAscending: false,
            limit: 10,
          ))
          .first;
      expect(watched.length, 10);
      expect(watched.first.id, 2);
    });
  });
}
