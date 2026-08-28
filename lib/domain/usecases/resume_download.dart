// lib/domain/usecases/resume_download.dart
// DL-14: Input validation guard.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

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

