import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/usecases/playlist_io_usecases.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

SongsTableData _song({
  required int id,
  required String path,
  String? title,
  int? cueStartMs,
  int? cueEndMs,
}) {
  return SongsTableData(
    id: id,
    title: title ?? 'Track $id',
    artist: 'Artist $id',
    album: 'Album',
    durationMs: 180000,
    path: path,
    isFavorite: false,
    isMissing: false,
    playCount: 0,
    lastPositionMs: 0,
    source: SongSource.local,
    isDownloaded: false,
    cueStartMs: cueStartMs,
    cueEndMs: cueEndMs,
  );
}

class FakeMusicRepository implements IMusicRepository {
  List<SongsTableData> songs = [];
  bool addSongsShouldFail = false;
  List<int> addedSongIds = [];

  @override
  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    List<String> excludedFolders = const [],
  }) async =>
      Right(songs);

  @override
  Future<Result<int>> createPlaylist(String name,
          {bool isSmart = false, String? smartCriteria}) async =>
      const Right(42);

  @override
  Future<Result<void>> addSongsToPlaylist(
      int playlistId, List<int> songIds) async {
    if (addSongsShouldFail) {
      return const Left(DatabaseFailure('DB insert failed'));
    }
    addedSongIds.addAll(songIds);
    return const Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMusicRepository fakeRepo;
  late PlaylistExportUseCase exportUseCase;
  late PlaylistImportUseCase importUseCase;

  setUp(() {
    fakeRepo = FakeMusicRepository();
    exportUseCase = PlaylistExportUseCase();
    importUseCase = PlaylistImportUseCase(fakeRepo);
  });

  group('PlaylistExportUseCase fixes', () {
    test('emits #EXTVLCOPT:start-time=0.000 whenever cueStartMs is 0', () {
      final songWithZeroCue = _song(
        id: 1,
        path: '/music/album.flac',
        cueStartMs: 0,
        cueEndMs: 120000,
      );

      final m3u = exportUseCase.generateM3uContent([songWithZeroCue]);
      expect(m3u, contains('#EXTVLCOPT:start-time=0.000'));
      expect(m3u, contains('#EXTVLCOPT:stop-time=120.000'));
    });

    test('exportToFile sanitizes dot, dotdot, and empty playlistName to "playlist"', () async {
      final fileDot = await exportUseCase.exportToFile('.', []);
      expect(fileDot.path, endsWith('playlist.m3u'));
      if (fileDot.existsSync()) fileDot.deleteSync();

      final fileDotDot = await exportUseCase.exportToFile('..', []);
      expect(fileDotDot.path, endsWith('playlist.m3u'));
      if (fileDotDot.existsSync()) fileDotDot.deleteSync();

      final fileEmpty = await exportUseCase.exportToFile('   ', []);
      expect(fileEmpty.path, endsWith('playlist.m3u'));
      if (fileEmpty.existsSync()) fileEmpty.deleteSync();
    });
  });

  group('PlaylistImportUseCase fixes', () {
    test('never falls back to non-CUE container track when targetCueStartMs != null fails to match', () async {
      final tempDir = Directory.systemTemp.createTempSync('playlist_cue_test_');
      final playlistFile = File('${tempDir.path}/test.m3u');
      playlistFile.writeAsStringSync(
        '#EXTM3U\n'
        '#EXTINF:180,Artist - Non-existent chapter\n'
        '#EXTVLCOPT:start-time=999.000\n'
        '/music/album.flac\n',
      );

      fakeRepo.songs = [
        _song(id: 10, path: '/music/album.flac', cueStartMs: null), // Container track
        _song(id: 11, path: '/music/album.flac', cueStartMs: 0), // Track 1 at 0ms
      ];

      final result = await importUseCase.importPlaylistFromFile(
        filePath: playlistFile.path,
        playlistName: 'Test Playlist',
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected success: $l'),
        (res) {
          // Track with start-time=999s (999000ms) did NOT match cueStartMs=0 (±500ms)
          // and must NOT have fallen back to container song id 10!
          expect(res.matchedTrackCount, 0);
          expect(res.unmatchedPaths.length, 1);
        },
      );

      tempDir.deleteSync(recursive: true);
    });

    test('round-trips CUE Track 1 (cueStartMs == 0) and moved CUE album to new path', () async {
      final tempDir = Directory.systemTemp.createTempSync('playlist_cue_moved_test_');
      final discOldPath = '/storage/emulated/0/Music/OldFolder/album.flac';
      final discNewPath = '/storage/emulated/0/Music/NewFolder/album.flac';

      // 1. Export M3U containing CUE Track 1 (cueStartMs: 0) and Track 2 (cueStartMs: 120000)
      final track1Old = _song(id: 1, path: discOldPath, cueStartMs: 0, cueEndMs: 120000, title: 'Intro');
      final track2Old = _song(id: 2, path: discOldPath, cueStartMs: 120000, cueEndMs: 240000, title: 'Verse');
      final m3uContent = exportUseCase.generateM3uContent([track1Old, track2Old]);

      expect(m3uContent, contains('#EXTVLCOPT:start-time=0.000'));
      expect(m3uContent, contains('#EXTVLCOPT:start-time=120.000'));

      final playlistFile = File('${tempDir.path}/moved_cue.m3u');
      playlistFile.writeAsStringSync(m3uContent);

      // 2. Repository has the songs at the NEW album path
      final track1New = _song(id: 101, path: discNewPath, cueStartMs: 0, cueEndMs: 120000, title: 'Intro');
      final track2New = _song(id: 102, path: discNewPath, cueStartMs: 120000, cueEndMs: 240000, title: 'Verse');
      fakeRepo.songs = [track1New, track2New];
      fakeRepo.addedSongIds.clear();

      // 3. Import playlist
      final result = await importUseCase.importPlaylistFromFile(
        filePath: playlistFile.path,
        playlistName: 'Moved CUE Playlist',
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Expected success: $l'),
        (res) {
          expect(res.matchedTrackCount, 2);
          expect(res.unmatchedPaths, isEmpty);
          expect(fakeRepo.addedSongIds, [101, 102],
              reason: 'Both Track 1 (0ms) and Track 2 should match at the new album path');
        },
      );

      tempDir.deleteSync(recursive: true);
    });

    test('returns Left(failure) if addSongsToPlaylist fails', () async {
      final tempDir = Directory.systemTemp.createTempSync('playlist_err_test_');
      final playlistFile = File('${tempDir.path}/test.m3u');
      playlistFile.writeAsStringSync(
        '#EXTM3U\n'
        '#EXTINF:180,Artist - Track 1\n'
        '/music/track1.mp3\n',
      );

      fakeRepo.songs = [
        _song(id: 1, path: '/music/track1.mp3'),
      ];
      fakeRepo.addSongsShouldFail = true;

      final result = await importUseCase.importPlaylistFromFile(
        filePath: playlistFile.path,
        playlistName: 'Test Playlist',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, contains('DB insert failed')),
        (r) => fail('Expected failure'),
      );

      tempDir.deleteSync(recursive: true);
    });
  });
}
