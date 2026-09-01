// lib/domain/usecases/download_lifecycle_usecases.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class PauseDownloadUseCase {
  final IDownloadRepository _repository;

  PauseDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) async {
    if (videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Invalid video ID'));
    }
    return _repository.pauseDownload(videoId);
  }
}

@singleton
class ResumeDownloadUseCase {
  final IDownloadRepository _repository;

  ResumeDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) async {
    if (videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Invalid video ID'));
    }
    return _repository.resumeDownload(videoId);
  }
}

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

@singleton
class DeleteDownloadUseCase {
  final IDownloadRepository _repository;

  DeleteDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) async {
    if (videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Invalid video ID'));
    }
    return _repository.deleteDownload(videoId);
  }
}
