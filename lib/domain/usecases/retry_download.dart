// lib/domain/usecases/retry_download.dart
// DL-14: Input validation guard.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class RetryDownloadUseCase {
  final IDownloadRepository _repository;

  RetryDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) async {
    if (videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Invalid video ID'));
    }
    return _repository.retryDownload(videoId);
  }
}

