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
    final validatedLimit = limit?.clamp(0, 1000);
    final validatedOffset = offset != null ? (offset < 0 ? 0 : offset) : null;
    final validatedQuery = (searchQuery != null && searchQuery.length > 200)
        ? searchQuery.substring(0, 200)
        : searchQuery;

    return _repository.watchAllSongs(
      sortBy: sortBy,
      ascending: ascending,
      limit: validatedLimit,
      offset: validatedOffset,
      searchQuery: validatedQuery,
      excludedFolders: excludedFolders,
    );
  }

  Stream<Result<List<SongsTableData>>> watchRecentlyPlayed({int limit = 20}) {
    final validatedLimit = limit.clamp(1, 500);
    return _repository.watchRecentlyPlayed(limit: validatedLimit);
  }

  Future<Result<void>> clearRecentlyPlayed() {
    return _repository.clearRecentlyPlayed();
  }

  Stream<Result<List<SongsTableData>>> watchRecentlyAdded({int limit = 20}) {
    final validatedLimit = limit.clamp(1, 500);
    return _repository.watchRecentlyAdded(limit: validatedLimit);
  }

  Stream<Result<List<SongsTableData>>> watchTopPlayed({int limit = 30}) {
    final validatedLimit = limit.clamp(1, 500);
    return _repository.watchTopPlayed(limit: validatedLimit);
  }

  Future<Result<List<SongsTableData>>> getAllSongs({
    String sortBy = 'title',
    bool ascending = true,
    int? limit,
    int? offset,
  }) {
    final validatedLimit = limit?.clamp(0, 1000);
    final validatedOffset = offset != null ? (offset < 0 ? 0 : offset) : null;

    return _repository.getAllSongs(
      sortBy: sortBy,
      ascending: ascending,
      limit: validatedLimit,
      offset: validatedOffset,
    );
  }
}
