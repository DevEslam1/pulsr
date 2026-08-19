// lib/domain/usecases/toggle_favorite_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/repositories/music_repository.dart';

@singleton
class ToggleFavoriteUseCase {
  final MusicRepository _repository;

  ToggleFavoriteUseCase(this._repository);

  Future<Result<bool>> call(int songId) {
    return _repository.toggleFavorite(songId);
  }
}
