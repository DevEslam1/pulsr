// lib/domain/usecases/search_music_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

@singleton
class SearchMusicUseCase {
  final MusicRepository _repository;

  SearchMusicUseCase(this._repository);

  Stream<Result<List<SongsTableData>>> searchSongs(String query, {List<String> excludedFolders = const []}) {
    return _repository.watchAllSongs(
      searchQuery: query,
      excludedFolders: excludedFolders,
    );
  }
}
