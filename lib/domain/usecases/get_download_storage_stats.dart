// lib/domain/usecases/get_download_storage_stats.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class GetDownloadStorageStatsUseCase {
  final IDownloadRepository _repository;

  GetDownloadStorageStatsUseCase(this._repository);

  Future<Either<AppFailure, StorageStats>> call() =>
      _repository.getStorageStats();
}
