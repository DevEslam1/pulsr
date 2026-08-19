// lib/domain/usecases/get_favorites_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

@singleton
class GetFavoritesUseCase {
  final MusicRepository _repository;

  GetFavoritesUseCase(this._repository);

  Stream<Result<List<SongsTableData>>> watchFavorites() {
    return _repository.watchFavorites();
  }
}
