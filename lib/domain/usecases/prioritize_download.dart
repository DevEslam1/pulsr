// lib/domain/usecases/prioritize_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class PrioritizeDownloadUseCase {
  final IDownloadRepository _repository;

  PrioritizeDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) =>
      _repository.prioritizeDownload(videoId);
}
