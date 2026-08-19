// lib/domain/usecases/toggle_favorite_usecase.dart
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../../data/repositories/music_repository.dart';

class ToggleFavoriteUseCase {
  final MusicRepository _repository;

  ToggleFavoriteUseCase(this._repository);

  Future<Either<AppFailure, bool>> call(int songId) {
    return _repository.toggleFavorite(songId);
  }
}
