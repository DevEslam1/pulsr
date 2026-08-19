// lib/domain/usecases/get_favorites_usecase.dart
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class GetFavoritesUseCase {
  final MusicRepository _repository;

  GetFavoritesUseCase(this._repository);

  Stream<List<SongsTableData>> watchFavorites() {
    return _repository.watchFavorites();
  }
}
