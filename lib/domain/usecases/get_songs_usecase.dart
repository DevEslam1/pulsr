// lib/domain/usecases/get_songs_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class GetSongsUseCase {
  final IMusicRepository _repository;

  GetSongsUseCase(this._repository);

  Stream<Result<List<SongsTableData>>> watchSongs({
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

  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({int limit = 20}) {
    return _repository.watchRecentlyPlayed(limit: limit);
  }

  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int limit = 20}) {
    return _repository.watchRecentlyAdded(limit: limit);
  }

  Stream<Result<List<SongsTableData>>> watchTopPlayed({int limit = 30}) {
    return _repository.watchTopPlayed(limit: limit);
  }

  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) {
    return _repository.getAllSongs(
      sortBy: sortBy,
      ascending: ascending,
      limit: limit,
      offset: offset,
    );
  }
}
