// lib/domain/usecases/prioritize_download.dart
// DL-14: Input validation guard.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class PrioritizeDownloadUseCase {
  final IDownloadRepository _repository;

  PrioritizeDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) async {
    if (videoId.trim().isEmpty) {
      return const Left(ValidationFailure('Invalid video ID'));
    }
    return _repository.prioritizeDownload(videoId);
  }
}

