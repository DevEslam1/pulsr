// lib/domain/repositories/music_repository_interface.dart
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../models/genre_item.dart';
import '../models/year_item.dart';

abstract class IMusicRepository {
  // --- SONGS ---
  Stream<Result<List<SongsTableData>>> watchAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  });

  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  });

  Future<Result<SongsTableData?>> getSongById(int id);
  Future<Result<SongsTableData?>> getSongByPath(String path);
  Future<Result<SongsTableData?>> getSongByUri(String uri);
  Future<Result<SongsTableData?>> getSongByRemoteId(String remoteId);
  Future<Result<SongsTableData?>> findMatchingLocalSong({String? remoteId, String? title, String? artist});
  Future<Result<List<SongsTableData>>> getSongsByIds(List<int> ids);
  Future<Result<int>> hardDeleteMissingSongs();

  /// Folds a downloaded YouTube row (negative [oldId]) into the positive-id
  /// row the scanner created for [newPath]: merges play stats and re-points
  /// playlist/queue/history children, then deletes the YouTube row. Returns
  /// the surviving positive id, or null when no scanned row could be matched.
  Future<Result<int?>> reconcileDownloadedSong({
    required int oldId,
    required String newPath,
    SongsTableData? fallbackSong,
  });

  Stream<Result<List<SongsTableData>>> watchFavorites();
  Future<Result<List<SongsTableData>>> getFavorites();

  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({int limit = 20});
  Future<Result<List<SongsTableData>>> getRecentlyPlayed({int limit = 20});

  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int limit = 20});
  Stream<Result<List<SongsTableData>>> watchTopPlayed({int limit = 30});

  Future<Result<bool>> toggleFavorite(int songId);
  Future<Result<void>> recordPlayHistory(int songId, {bool completed = false});
  Future<Result<void>> updateLastPosition(int songId, int positionMs);

  // --- ALBUMS ---
  Stream<Result<List<AlbumsTableData>>> watchAlbums();
  Stream<Result<List<SongsTableData>>> watchAlbumSongs(int albumId);
  Future<Result<List<AlbumsTableData>>> getAlbums();
  Future<Result<List<SongsTableData>>> getAlbumSongs(int albumId);

  // --- ARTISTS ---
  Stream<Result<List<ArtistsTableData>>> watchArtists();
  Stream<Result<List<SongsTableData>>> watchArtistSongs(int artistId);
  Future<Result<List<ArtistsTableData>>> getArtists();
  Future<Result<List<SongsTableData>>> getArtistSongs(int artistId);
  Stream<Result<List<AlbumsTableData>>> watchArtistAlbums(int artistId);

  // --- PLAYLISTS ---
  Stream<Result<List<PlaylistsTableData>>> watchPlaylists();
  Future<Result<int>> createPlaylist(String name, {bool isSmart = false, String? smartCriteria});
  Future<Result<void>> renamePlaylist(int playlistId, String newName);
  Future<Result<void>> updateSmartPlaylist(int playlistId, String name, String smartCriteria);
  Future<Result<void>> deletePlaylist(int playlistId);
  Future<Result<List<PlaylistsTableData>>> getPlaylists();
  Stream<Result<List<SongsTableData>>> watchPlaylistSongs(int playlistId);
  Future<Result<List<SongsTableData>>> getPlaylistSongs(int playlistId);
  Future<Result<void>> addSongToPlaylist(int playlistId, int songId);
  Future<Result<void>> addSongsToPlaylist(int playlistId, List<int> songIds);
  Future<Result<void>> removeSongFromPlaylist(int playlistId, int songId);

  // --- EXCLUDED FOLDERS ---
  Stream<Result<List<ExcludedFoldersTableData>>> watchExcludedFolders();
  Future<Result<List<String>>> getExcludedFolderPaths();
  Future<Result<void>> toggleFolderExclusion(String folderPath);

  // --- QUEUE PERSISTENCE ---
  Future<Result<void>> saveQueue(List<int> songIds, int currentIndex, int positionMs);
  Future<Result<List<QueueItemsTableData>>> getSavedQueue();

  // --- SCAN SYNC ---
  Future<Result<void>> syncScannedMusic({
    required List<SongsTableCompanion> songs,
    required List<AlbumsTableCompanion> albums,
    required List<ArtistsTableCompanion> artists,
  });

  Future<Result<int>> cleanupOrphanedSongs(Set<int> scannedSongIds);

  // --- TAG UPDATES ---
  Future<Result<void>> updateSongTags({
    required String path,
    required String title,
    required String artist,
    required String album,
    String? genre,
    int? year,
    int? trackNumber,
  });

  /// Persists real audio-header fields (read from the file) so the quality
  /// badge reflects actual metadata instead of a filename guess.
  Future<Result<void>> updateAudioQuality({
    required int songId,
    int? sampleRate,
    int? bitDepth,
    int? bitrateKbps,
    String? codec,
  });

  // --- GENRES ---
  Stream<Result<List<GenreItem>>> watchGenres();
  Stream<Result<List<SongsTableData>>> watchGenreSongs(String genre);

  // --- YEARS ---
  Stream<Result<List<YearItem>>> watchYears();
  Stream<Result<List<SongsTableData>>> watchYearSongs(int year);
}
