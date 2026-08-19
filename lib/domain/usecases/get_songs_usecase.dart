// lib/domain/usecases/get_songs_usecase.dart
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';

class GetSongsUseCase {
  final MusicRepository _repository;

  GetSongsUseCase(this._repository);

  Stream<List<SongsTableData>> watchSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
    String? searchQuery,
    List<String> excludedFolders = const [],
  }) {
    return _repository.watchAllSongs(
      sortBy: sortBy,
      ascending: ascending,
      limit: limit,
      offset: offset,
      searchQuery: searchQuery,
      excludedFolders: excludedFolders,
    );
  }

  Stream<List<SongsTableData>> watchRecentlyPlayed({int limit = 20}) {
    return _repository.watchRecentlyPlayed(limit: limit);
  }

  Stream<List<SongsTableData>> watchRecentlyAdded({int limit = 20}) {
    return _repository.watchRecentlyAdded(limit: limit);
  }

  Stream<List<SongsTableData>> watchTopPlayed({int limit = 30}) {
    return _repository.watchTopPlayed(limit: limit);
  }
}
