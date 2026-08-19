// lib/domain/usecases/get_albums_usecase.dart
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class GetAlbumsUseCase {
  final MusicRepository _repository;

  GetAlbumsUseCase(this._repository);

  Stream<List<AlbumsTableData>> watchAlbums() {
    return _repository.watchAlbums();
  }

  Stream<List<SongsTableData>> watchAlbumSongs(int albumId) {
    return _repository.watchAlbumSongs(albumId);
  }
}
