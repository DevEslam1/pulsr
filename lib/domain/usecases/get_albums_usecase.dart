// lib/domain/usecases/get_albums_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class GetAlbumsUseCase {
  final IMusicRepository _repository;

  GetAlbumsUseCase(this._repository);

  Stream<Result<List<AlbumsTableData>>> watchAlbums() {
    return _repository.watchAlbums();
  }

  Stream<Result<List<SongsTableData>>> watchAlbumSongs(int albumId) {
    return _repository.watchAlbumSongs(albumId);
  }
}
