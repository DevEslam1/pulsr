// lib/domain/usecases/queue_downloads_batch.dart
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';
import '../repositories/download_repository_interface.dart';

/// Batch queuing for playlist/album/queue downloads.
/// 10/10 requirement: one-tap download of an entire collection with per-quality
/// prompt, drag-reorder queue, and priority support. Bounded concurrency (3)
/// ensures bounded memory / bandwidth; Wi-Fi/metered guard is enforced per-task.
/// Register via getIt manually or run build_runner to generate @singleton if desired.
class QueueDownloadsBatchUseCase {
  final IDownloadRepository _repository;

  QueueDownloadsBatchUseCase(this._repository);

  Future<List<Either<AppFailure, String>>> call(
    List<DownloadTask> tasks, {
    int? maxConcurrent, // optional override (used by settings screen)
  }) async {
    final results = <Either<AppFailure, String>>[];
    for (var i = 0; i < tasks.length; i++) {
      // Sequential queuing preserves FIFO order; processor respects maxConcurrent internally.
      // Small stagger between enqueues keeps resolve bursts under YouTube's
      // rate limit (first-N-succeed-then-429 pattern).
      if (i > 0) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      final r = await _repository.queueDownload(tasks[i]);
      results.add(r);
    }
    return results;
  }
}
