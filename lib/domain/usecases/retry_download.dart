// lib/domain/usecases/retry_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class RetryDownloadUseCase {
  final IDownloadRepository _repository;

  RetryDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) =>
      _repository.retryDownload(videoId);
}
