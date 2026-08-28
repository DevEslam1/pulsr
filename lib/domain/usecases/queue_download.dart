// lib/domain/usecases/queue_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class QueueDownloadUseCase {
  final IDownloadRepository _repository;

  QueueDownloadUseCase(this._repository);

  Future<Either<AppFailure, String>> call(DownloadTask task) =>
      _repository.queueDownload(task);
}
