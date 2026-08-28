// lib/domain/usecases/reorder_downloads.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class ReorderDownloadsUseCase {
  final IDownloadRepository _repository;

  ReorderDownloadsUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(List<String> orderedVideoIds) =>
      _repository.reorderQueue(orderedVideoIds);
}
