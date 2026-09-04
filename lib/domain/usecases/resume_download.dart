// lib/domain/usecases/resume_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class ResumeDownloadUseCase {
  final IDownloadRepository _repository;

  ResumeDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) =>
      _repository.resumeDownload(videoId);
}
