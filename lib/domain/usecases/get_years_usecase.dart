// lib/domain/usecases/get_years_usecase.dart
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/music_repository.dart';
import '../models/year_item.dart';

@singleton
class GetYearsUseCase {
  final MusicRepository _repository;

  GetYearsUseCase(this._repository);

  Stream<Result<List<YearItem>>> watchYears() {
    return _repository.watchYears();
  }

  Stream<Result<List<SongsTableData>>> watchYearSongs(int year) {
    return _repository.watchYearSongs(year);
  }
}
