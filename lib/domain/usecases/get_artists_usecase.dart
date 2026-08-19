// lib/domain/usecases/get_artists_usecase.dart
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class GetArtistsUseCase {
  final MusicRepository _repository;

  GetArtistsUseCase(this._repository);

  Stream<List<ArtistsTableData>> watchArtists() {
    return _repository.watchArtists();
  }

  Stream<List<SongsTableData>> watchArtistSongs(int artistId) {
    return _repository.watchArtistSongs(artistId);
  }

  Stream<List<AlbumsTableData>> watchArtistAlbums(int artistId) {
    return _repository.watchArtistAlbums(artistId);
  }
}
