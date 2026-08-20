// lib/domain/usecases/get_favorites_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class GetFavoritesUseCase {
  final IMusicRepository _repository;

  GetFavoritesUseCase(this._repository);

  Stream<Result<List<SongsTableData>>> watchFavorites() {
    return _repository.watchFavorites();
  }
}
