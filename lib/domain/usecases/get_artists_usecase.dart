// lib/domain/usecases/get_artists_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

@singleton
class GetArtistsUseCase {
  final MusicRepository _repository;

  GetArtistsUseCase(this._repository);

  Stream<Result<List<ArtistsTableData>>> watchArtists() {
    return _repository.watchArtists();
  }

  Stream<Result<List<SongsTableData>>> watchArtistSongs(int artistId) {
    return _repository.watchArtistSongs(artistId);
  }

  Stream<Result<List<AlbumsTableData>>> watchArtistAlbums(int artistId) {
    return _repository.watchArtistAlbums(artistId);
  }
}
