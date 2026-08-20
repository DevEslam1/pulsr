// lib/domain/usecases/get_genres_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../models/genre_item.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class GetGenresUseCase {
  final IMusicRepository _repository;

  GetGenresUseCase(this._repository);

  Stream<Result<List<GenreItem>>> watchGenres() {
    return _repository.watchGenres();
  }

  Stream<Result<List<SongsTableData>>> watchGenreSongs(String genre) {
    return _repository.watchGenreSongs(genre);
  }
}
