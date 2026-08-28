// lib/domain/usecases/queue_downloads_batch.dart
// DL-12: Granular batch download result reporting (queued, skipped, failures).
// DL-14: Input validation guard.

import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

class BatchDownloadResult {
  final int totalCount;
  final int queuedCount;
  final int skippedDuplicatesCount;
  final List<String> taskIds;
  final Map<String, AppFailure> failedIds;
  final List<AppFailure> failures;

  const BatchDownloadResult({
    required this.totalCount,
    required this.queuedCount,
    required this.skippedDuplicatesCount,
    required this.taskIds,
    this.failedIds = const {},
    required this.failures,
  });

  bool get hasFailures => failures.isNotEmpty || failedIds.isNotEmpty;
  bool get allSucceeded => failures.isEmpty && failedIds.isEmpty && skippedDuplicatesCount == 0;
}

@singleton
class QueueDownloadsBatchUseCase {
  final IDownloadRepository _repository;

  QueueDownloadsBatchUseCase(this._repository);

  Future<List<Either<AppFailure, String>>> call(
    List<DownloadTask> tasks, {
    int? maxConcurrent,
  }) async {
    if (tasks.isEmpty) return [];
    final results = <Either<AppFailure, String>>[];
    for (final t in tasks) {
      final r = await _repository.queueDownload(t);
      results.add(r);
    }
    return results;
  }

  Future<BatchDownloadResult> executeWithBatchResult(List<DownloadTask> tasks) async {
    int queuedCount = 0;
    int skippedDuplicatesCount = 0;
    final taskIds = <String>[];
    final failedIds = <String, AppFailure>{};
    final failures = <AppFailure>[];

    for (final task in tasks) {
      final res = await _repository.queueDownload(task);
      res.fold(
        (failure) {
          if (failure is AlreadyQueuedFailure) {
            skippedDuplicatesCount++;
          } else {
            failures.add(failure);
            final key = task.id.isNotEmpty ? task.id : task.videoId;
            failedIds[key] = failure;
          }
        },
        (taskId) {
          queuedCount++;
          taskIds.add(taskId);
        },
      );
    }

    return BatchDownloadResult(
      totalCount: tasks.length,
      queuedCount: queuedCount,
      skippedDuplicatesCount: skippedDuplicatesCount,
      taskIds: taskIds,
      failedIds: failedIds,
      failures: failures,
    );
  }
}

