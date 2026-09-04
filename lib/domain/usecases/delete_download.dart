// lib/domain/usecases/delete_download.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class DeleteDownloadUseCase {
  final IDownloadRepository _repository;

  DeleteDownloadUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(String videoId) =>
      _repository.deleteDownload(videoId);
}
