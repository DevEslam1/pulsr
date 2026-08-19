// lib/domain/usecases/playlist_usecases.dart
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class PlaylistUseCases {
  final MusicRepository _repository;

  PlaylistUseCases(this._repository);

  Stream<List<PlaylistsTableData>> watchPlaylists() {
    return _repository.watchPlaylists();
  }

  Stream<List<SongsTableData>> watchPlaylistSongs(int playlistId) {
    return _repository.watchPlaylistSongs(playlistId);
  }

  Future<Either<AppFailure, int>> createPlaylist(String name, {bool isSmart = false, String? smartCriteria}) {
    return _repository.createPlaylist(name, isSmart: isSmart, smartCriteria: smartCriteria);
  }

  Future<Either<AppFailure, void>> renamePlaylist(int playlistId, String newName) {
    return _repository.renamePlaylist(playlistId, newName);
  }

  Future<Either<AppFailure, void>> deletePlaylist(int playlistId) {
    return _repository.deletePlaylist(playlistId);
  }

  Future<Either<AppFailure, void>> addSongToPlaylist(int playlistId, int songId) {
    return _repository.addSongToPlaylist(playlistId, songId);
  }

  Future<Either<AppFailure, void>> addSongsToPlaylist(int playlistId, List<int> songIds) {
    return _repository.addSongsToPlaylist(playlistId, songIds);
  }

  Future<Either<AppFailure, void>> removeSongFromPlaylist(int playlistId, int songId) {
    return _repository.removeSongFromPlaylist(playlistId, songId);
  }
}
