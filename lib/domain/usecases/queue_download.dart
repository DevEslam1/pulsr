// lib/domain/usecases/queue_download.dart
// DL-14: Input validation guard returning ValidationFailure for invalid task inputs.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class QueueDownloadUseCase {
  final IDownloadRepository _repository;

  QueueDownloadUseCase(this._repository);

  Future<Either<AppFailure, String>> call(DownloadTask task) async {
    if (task.videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Video ID cannot be empty'));
    }
    if (task.title.trim().isEmpty) {
      return const Left(ValidationFailure('Song title cannot be empty'));
    }
    return _repository.queueDownload(task);
  }
}

