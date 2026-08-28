// lib/domain/repositories/download_repository_interface.dart
import 'package:fpdart/fpdart.dart';
import '../../core/errors/failures.dart';
import '../models/download_task.dart';

abstract class IDownloadRepository {
  /// Queues a new audio download task. Returns the task id on success.
  Future<Either<AppFailure, String>> queueDownload(DownloadTask task);

  /// Pauses an active or queued download.
  Future<Either<AppFailure, Unit>> pauseDownload(String videoId);

  /// Resumes a paused download.
  Future<Either<AppFailure, Unit>> resumeDownload(String videoId);

  /// Retries a failed download.
  Future<Either<AppFailure, Unit>> retryDownload(String videoId);

  /// Deletes a download task and any local file associated with it.
  Future<Either<AppFailure, Unit>> deleteDownload(String videoId);

  /// Single broadcast stream of download task state transitions and progress updates.
  Stream<DownloadTask> observeDownloads();

  /// Retrieves current disk storage utilization and offline songs count.
  Future<Either<AppFailure, StorageStats>> getStorageStats();

  /// Gets all tracked download tasks (active, paused, completed, failed).
  Future<List<DownloadTask>> getAllDownloads();

  /// Reconciles persisted queue and verifies downloaded files integrity on app startup.
  Future<void> reconcileOnBoot();
}
