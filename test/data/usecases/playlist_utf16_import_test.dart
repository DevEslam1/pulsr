// test/data/usecases/playlist_utf16_import_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/data/usecases/playlist_io_usecases.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

class _FakeRepository implements IMusicRepository {
  _FakeRepository(this.songs);

  final List<SongsTableData> songs;
  final List<int> addedSongIds = [];

  @override
  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) async =>
      Right(songs);

  @override
  Future<Result<int>> createPlaylist(String name,
          {bool isSmart = false, String? smartCriteria}) async =>
      Right(42);

  @override
  Future<Result<void>> addSongsToPlaylist(
      int playlistId, List<int> songIds) async {
    addedSongIds.addAll(songIds);
    return Right(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<int> _utf16Bytes(String content,
    {required bool littleEndian, bool withBom = true}) {
  final bytes = <int>[];
  if (withBom) {
    bytes.addAll(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  }
  for (final unit in content.codeUnits) {
    if (littleEndian) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    } else {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
  }
  return bytes;
}

SongsTableData _song({required int id, required String path}) => SongsTableData(
      id: id,
      title: 'Track $id',
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
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulsr_utf16_playlist_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('imports a UTF-16LE (Windows Media Player) M3U with NUL bytes',
      () async {
    final songPath = '${tempDir.path}${Platform.pathSeparator}track one.mp3';
    final repo = _FakeRepository([_song(id: 1, path: songPath)]);
    final useCase = PlaylistImportUseCase(repo);

    final file = File('${tempDir.path}${Platform.pathSeparator}list.m3u');
    await file.writeAsBytes(_utf16Bytes(
      '#EXTM3U\r\n#EXTINF:180,Artist - Track\r\n$songPath\r\n',
      littleEndian: true,
    ));

    final result = await useCase.importPlaylistFromFile(
      filePath: file.path,
      playlistName: 'UTF-16 M3U',
    );

    final importResult = result.getOrElse((_) => throw StateError('failed'));
    expect(importResult.totalExtractedPaths, 1);
    expect(importResult.matchedTrackCount, 1);
    expect(repo.addedSongIds, [1]);
  });

  test('imports a UTF-16BE WPL', () async {
    final songPath = '${tempDir.path}${Platform.pathSeparator}track2.flac';
    final repo = _FakeRepository([_song(id: 2, path: songPath)]);
    final useCase = PlaylistImportUseCase(repo);

    final file = File('${tempDir.path}${Platform.pathSeparator}list.wpl');
    await file.writeAsBytes(_utf16Bytes(
      '<?wpl version="1.0"?>\n'
      '<smil><body><seq>\n'
      '<media src="$songPath"/>\n'
      '</seq></body></smil>\n',
      littleEndian: false,
    ));

    final result = await useCase.importPlaylistFromFile(
      filePath: file.path,
      playlistName: 'UTF-16 WPL',
    );

    final importResult = result.getOrElse((_) => throw StateError('failed'));
    expect(importResult.totalExtractedPaths, 1);
    expect(importResult.matchedTrackCount, 1);
    expect(repo.addedSongIds, [2]);
  });

  test('still rejects NUL-heavy binary files without a UTF BOM', () async {
    final repo = _FakeRepository(const []);
    final useCase = PlaylistImportUseCase(repo);

    final file = File('${tempDir.path}${Platform.pathSeparator}blob.m3u');
    await file.writeAsBytes([0x00, 0x01, 0x02, 0x00, 0x03, 0x00]);

    final result = await useCase.importPlaylistFromFile(
      filePath: file.path,
      playlistName: 'Binary',
    );

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable()?.message, contains('Binary'));
  });
}
