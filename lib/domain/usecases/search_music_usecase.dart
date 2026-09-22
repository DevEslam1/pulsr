// lib/domain/usecases/search_music_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class SearchMusicUseCase {
  final IMusicRepository _repository;

  SearchMusicUseCase(this._repository);

  // FIX-H4: Add limit parameter defaulting to 500 to prevent unbounded query load
  Stream<Result<List<SongsTableData>>> searchSongs(String query,
      {List<String> excludedFolders = const [], int limit = 500}) {
    return _repository.watchAllSongs(
      searchQuery: query,
      excludedFolders: excludedFolders,
      limit: limit,
    );
  }
}
