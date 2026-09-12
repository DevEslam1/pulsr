import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';
import 'package:pulsr/domain/usecases/playlist_io_usecases.dart';

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

SongsTableData _song({
  required int id,
  required String path,
  String? title,
  String source = SongSource.local,
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
    source: source,
    isDownloaded: false,
  );
}

void main() {
  group('PLS parsing', () {
    test('reads absolute paths in FileN order', () {
      final useCase = PlaylistImportUseCase(_FakeRepository(const []));
      final paths = useCase.parsePlsContent(
        '[playlist]\n'
        'File1=/music/a.mp3\n'
        'Title1=Artist - A\n'
        'File2=/music/b.mp3\n'
        'Title2=Artist - B\n'
        'NumberOfEntries=2\n'
        'Version=2\n',
      );

      expect(paths, ['/music/a.mp3', '/music/b.mp3']);
    });

    test('handles relative paths, comments, quotes and case-insensitive keys',
        () {
      final useCase = PlaylistImportUseCase(_FakeRepository(const []));
      final paths = useCase.parsePlsContent(
        '# a comment\n'
        '[playlist]\n'
        'file1=tracks/one.mp3\n'
        'Title1=One\n'
        'FILE2="tracks/two.mp3"\n'
        'Title2=Two\n'
        'NumberOfEntries=2\n'
        'Version=2\n',
      );

      expect(paths, ['tracks/one.mp3', 'tracks/two.mp3']);
    });
  });

  group('WPL parsing', () {
    test('decodes entities and supports single/double quotes', () {
      final useCase = PlaylistImportUseCase(_FakeRepository(const []));
      final paths = useCase.parseWplContent(
        '<?wpl version="1.0"?>\n'
        '<smil>\n'
        '  <body>\n'
        '    <seq>\n'
        '      <media src="C:\\Music\\A &amp; B.mp3"/>\n'
        "      <media src='C:\\Music\\&lt;live&gt;.flac'/>\n"
        '    </seq>\n'
        '  </body>\n'
        '</smil>\n',
      );

      expect(paths, [
        'C:\\Music\\A & B.mp3',
        'C:\\Music\\<live>.flac',
      ]);
    });
  });

  group('M3U regression', () {
    test('skips directives and comments', () {
      final useCase = PlaylistImportUseCase(_FakeRepository(const []));
      final paths = useCase.parseM3uContent(
        '#EXTM3U\n'
        '#EXTINF:180,Artist - A\n'
        '/music/a.mp3\n'
        '#EXTINF:200,Artist - B\n'
        '/music/b.mp3\n',
      );

      expect(paths, ['/music/a.mp3', '/music/b.mp3']);
    });
  });

  group('export content round-trips', () {
    final songs = [
      _song(id: 1, path: '/music/a.mp3', title: 'A'),
      _song(id: 2, path: 'C:\\Music\\B & <live>.flac', title: 'B'),
      _song(id: 3, path: 'ytmusic://abc', source: SongSource.youtube),
    ];

    test('PLS generator then parser preserves local paths only', () {
      final exporter = PlaylistExportUseCase();
      final importer = PlaylistImportUseCase(_FakeRepository(const []));

      final content = exporter.generatePlsContent(songs);
      expect(content, contains('NumberOfEntries=2'));

      final paths = importer.parsePlsContent(content);
      expect(paths, ['/music/a.mp3', 'C:\\Music\\B & <live>.flac']);
    });

    test('WPL generator escapes and parser decodes paths', () {
      final exporter = PlaylistExportUseCase();
      final importer = PlaylistImportUseCase(_FakeRepository(const []));

      final content = exporter.generateWplContent(songs);
      expect(content, contains('&amp;'));
      expect(content, contains('&lt;live&gt;'));

      final paths = importer.parseWplContent(content);
      expect(paths, ['/music/a.mp3', 'C:\\Music\\B & <live>.flac']);
    });
  });

  group('importPlaylistFromFile routing', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pulsr_pls_wpl_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves relative PLS paths against the playlist directory',
        () async {
      final relativeSong = _song(
        id: 1,
        path: '${tempDir.path}/relative.mp3',
      );
      final absoluteSong = _song(
        id: 2,
        path: '${tempDir.path}/absolute.mp3',
      );
      final repo = _FakeRepository([relativeSong, absoluteSong]);
      final useCase = PlaylistImportUseCase(repo);

      final plsFile = File('${tempDir.path}/list.pls');
      await plsFile.writeAsString(
        '[playlist]\n'
        'File1=relative.mp3\n'
        'File2=${absoluteSong.path}\n'
        'NumberOfEntries=2\n'
        'Version=2\n',
      );

      final result = await useCase.importPlaylistFromFile(
        filePath: plsFile.path,
        playlistName: 'Imported PLS',
      );

      final importResult = result.getOrElse((_) => throw StateError('failed'));
      expect(importResult.totalExtractedPaths, 2);
      expect(importResult.matchedTrackCount, 2);
      expect(repo.addedSongIds, containsAll(<int>[1, 2]));
    });

    test('sniffs WPL content when the extension is unknown', () async {
      final song = _song(id: 7, path: '${tempDir.path}/sniffed.flac');
      final repo = _FakeRepository([song]);
      final useCase = PlaylistImportUseCase(repo);

      final wplFile = File('${tempDir.path}/list.dat');
      await wplFile.writeAsString(
        '<?wpl version="1.0"?>\n'
        '<smil><body><seq>\n'
        '<media src="${song.path}"/>\n'
        '</seq></body></smil>\n',
      );

      final result = await useCase.importPlaylistFromFile(
        filePath: wplFile.path,
        playlistName: 'Imported WPL',
      );

      final importResult = result.getOrElse((_) => throw StateError('failed'));
      expect(importResult.totalExtractedPaths, 1);
      expect(importResult.matchedTrackCount, 1);
      expect(repo.addedSongIds, [7]);
    });
  });
}
