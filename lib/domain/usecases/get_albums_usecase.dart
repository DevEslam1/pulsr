// lib/domain/usecases/get_albums_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

@singleton
class GetAlbumsUseCase {
  final MusicRepository _repository;

  GetAlbumsUseCase(this._repository);

  Stream<Result<List<AlbumsTableData>>> watchAlbums() {
    return _repository.watchAlbums();
  }

  Stream<Result<List<SongsTableData>>> watchAlbumSongs(int albumId) {
    return _repository.watchAlbumSongs(albumId);
  }
}
