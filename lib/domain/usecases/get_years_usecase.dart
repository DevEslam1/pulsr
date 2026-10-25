// lib/domain/usecases/get_years_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../models/year_item.dart';
import '../repositories/music_repository_interface.dart';

@singleton
class GetYearsUseCase {
  final IMusicRepository _repository;

  GetYearsUseCase(this._repository);

  Stream<Result<List<YearItem>>> watchYears({
    List<String> excludedFolders = const [],
  }) {
    return _repository.watchYears(excludedFolders: excludedFolders);
  }

  Stream<Result<List<SongsTableData>>> watchYearSongs(int year) {
    return _repository.watchYearSongs(year);
  }
}
