// lib/domain/usecases/search_music_usecase.dart
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class SearchMusicUseCase {
  final MusicRepository _repository;

  SearchMusicUseCase(this._repository);

  Stream<List<SongsTableData>> searchSongs(String query, {List<String> excludedFolders = const []}) {
    return _repository.watchAllSongs(
      searchQuery: query,
      excludedFolders: excludedFolders,
    );
  }
}
