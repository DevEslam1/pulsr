// lib/domain/usecases/reorder_downloads.dart
// DL-14: Input validation guard.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

import '../../core/errors/failures.dart';
import '../repositories/download_repository_interface.dart';

@singleton
class ReorderDownloadsUseCase {
  final IDownloadRepository _repository;

  ReorderDownloadsUseCase(this._repository);

  Future<Either<AppFailure, Unit>> call(List<String> orderedVideoIds) async {
    if (orderedVideoIds.isEmpty) {
      return const Left(ValidationFailure('Ordered video IDs list cannot be empty'));
    }
    return _repository.reorderQueue(orderedVideoIds);
  }
}

