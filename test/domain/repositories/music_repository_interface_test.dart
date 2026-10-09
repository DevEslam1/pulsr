// test/domain/repositories/music_repository_interface_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pulsr/core/errors/failures.dart';
import 'package:pulsr/data/db/app_database.dart';
import 'package:pulsr/domain/repositories/music_repository_interface.dart';

/// Exercises the concrete default methods on [IMusicRepository] without
/// implementing the whole (large) interface: a user-defined [noSuchMethod]
/// lets the analyzer accept the unimplemented abstract members.
class _StubRepo extends IMusicRepository {
  _StubRepo({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  final List<SongsTableData> songs;
  final List<AlbumsTableData> albums;
  final List<ArtistsTableData> artists;
  final List<PlaylistsTableData> playlists;

  @override
  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) async =>
      Right(songs);

  @override
  Stream<Result<List<SongsTableData>>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) =>
      Stream<Result<List<SongsTableData>>>.value(Right(songs));

  @override
  Future<Result<List<AlbumsTableData>>> getAlbums() async => Right(albums);

  @override
  Future<Result<List<ArtistsTableData>>> getArtists() async => Right(artists);

  @override
  Future<Result<List<PlaylistsTableData>>> getPlaylists() async =>
      Right(playlists);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SongsTableData _song({
  required int id,
  required String path,
  String source = SongSource.local,
  String title = 'Song',
}) =>
    SongsTableData(
      id: id,
      title: title,
      artist: 'Artist',
      album: 'Album',
      albumId: null,
      durationMs: 0,
      path: path,
      isFavorite: false,
      isMissing: false,
      playCount: 0,
      lastPositionMs: 0,
      source: source,
      isDownloaded: false,
    );

void main() {
  group('IMusicRepository default methods', () {
    test('getLocalSongPaths keeps only local, non-ytmusic paths', () async {
      final repo = _StubRepo(songs: [
        _song(id: 1, path: '/music/a.mp3'),
        _song(id: 2, path: 'ytmusic://vid', source: SongSource.youtube),
        _song(id: 3, path: '/music/b.flac'),
      ]);

      final paths = (await repo.getLocalSongPaths()).getOrElse((_) => []);
      expect(paths, ['/music/a.mp3', '/music/b.flac']);
    });

    test('getLocalSongEntries maps paths to id-less folder entries', () async {
      final repo = _StubRepo(songs: [
        _song(id: 1, path: '/music/a.mp3'),
      ]);

      final entries = (await repo.getLocalSongEntries()).getOrElse((_) => []);
      expect(entries, hasLength(1));
      expect(entries.single.path, '/music/a.mp3');
      expect(entries.single.id, 0);
    });

    test('watchSongsInFolder returns only direct children, case-insensitive',
        () async {
      final repo = _StubRepo(songs: [
        _song(id: 1, path: '/Music/Rock/one.mp3'),
        _song(id: 2, path: '/music/rock/sub/deep.mp3'),
        _song(id: 3, path: r'\Music\Rock\two.mp3'),
        _song(id: 4, path: 'ytmusic://vid', source: SongSource.youtube),
      ]);

      final direct =
          (await repo.watchSongsInFolder('/music/rock').first).getOrElse((_) => []);
      final ids = direct.map((s) => s.id).toSet();
      expect(ids, containsAll([1, 3]));
      expect(ids, isNot(contains(2)), reason: 'subfolder is not a direct child');
      expect(ids, isNot(contains(4)), reason: 'remote rows are excluded');
    });

    test('lookup-by-id defaults scan the full list and return null on miss',
        () async {
      final repo = _StubRepo(
        albums: const [
          AlbumsTableData(id: 7, title: 'A', artist: 'X', songCount: 1),
        ],
        artists: const [
          ArtistsTableData(id: 8, name: 'B', songCount: 1, albumCount: 1),
        ],
        playlists: [
          PlaylistsTableData(
            id: 9,
            name: 'P',
            createdAt: DateTime(2020),
            updatedAt: DateTime(2020),
            isSmart: false,
          ),
        ],
      );

      expect((await repo.getAlbumById(7)).getOrElse((_) => null)?.title, 'A');
      expect((await repo.getAlbumById(99)).getOrElse((_) => null), isNull);
      expect((await repo.getArtistById(8)).getOrElse((_) => null)?.name, 'B');
      expect((await repo.getArtistById(99)).getOrElse((_) => null), isNull);
      expect((await repo.getPlaylistById(9)).getOrElse((_) => null)?.name, 'P');
      expect((await repo.getPlaylistById(99)).getOrElse((_) => null), isNull);
    });
  });

  group('FolderSongEntry', () {
    test('exposes all constructor fields', () {
      const entry = FolderSongEntry(
        path: '/music/a.flac',
        id: 3,
        albumId: 5,
        artworkUri: 'file:///art.jpg',
        remoteArtworkUrl: 'https://cdn/art.jpg',
      );
      expect(entry.path, '/music/a.flac');
      expect(entry.id, 3);
      expect(entry.albumId, 5);
      expect(entry.artworkUri, 'file:///art.jpg');
      expect(entry.remoteArtworkUrl, 'https://cdn/art.jpg');
    });
  });
}
