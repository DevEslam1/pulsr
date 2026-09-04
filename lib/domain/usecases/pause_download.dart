// lib/domain/usecases/pause_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class PauseDownloadUseCase {
  final IDownloadRepository _repository;

  PauseDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) =>
      _repository.pauseDownload(videoId);
}
