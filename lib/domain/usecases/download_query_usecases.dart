// lib/domain/usecases/download_query_usecases.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class ObserveDownloadsUseCase {
  final IDownloadRepository _repository;

  ObserveDownloadsUseCase(this._repository);

  Stream<DownloadTask> call() => _repository.observeDownloads();

  Future<List<DownloadTask>> getAll() => _repository.getAllDownloads();
}

@singleton
class GetDownloadStorageStatsUseCase {
  final IDownloadRepository _repository;

  GetDownloadStorageStatsUseCase(this._repository);

  Future<Either<AppFailure, StorageStats>> call() =>
      _repository.getStorageStats();
}
