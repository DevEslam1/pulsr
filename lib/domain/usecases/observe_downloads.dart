// lib/domain/usecases/observe_downloads.dart
import 'package:injectable/injectable.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class ObserveDownloadsUseCase {
  final IDownloadRepository _repository;

  ObserveDownloadsUseCase(this._repository);

  Stream<DownloadTask> call() => _repository.observeDownloads();

  Future<List<DownloadTask>> getAll() => _repository.getAllDownloads();
}
