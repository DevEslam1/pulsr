// lib/features/downloads/cubit/downloads_state.dart
// DL-19: Typed failures and retryable classification.

import 'package:flutter/foundation.dart';
import '../../../core/errors/failures.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/retry_policy.dart';

class DownloadsState {
  final Map<String, DownloadTask> tasks;
  final StorageStats storageStats;
  final bool isLoading;
  final String? errorMessage;
  final AppFailure? failure;

  const DownloadsState({
    this.tasks = const {},
    this.storageStats = const StorageStats(),
    this.isLoading = false,
    this.errorMessage,
    this.failure,
  });

  List<DownloadTask> get taskList => tasks.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get activeCount =>
      tasks.values.where((t) => t.status.isActive).length;

  int get pausedCount =>
      tasks.values.where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.interrupted).length;

  bool get hasPausedTasks => pausedCount > 0;

  int get completedCount =>
      tasks.values.where((t) => t.status == DownloadStatus.complete).length;

  bool get isErrorRetryable => failure != null
      ? RetryPolicy.isRetryableError(failure!.message)
      : RetryPolicy.isRetryableError(errorMessage);

  DownloadsState copyWith({
    Map<String, DownloadTask>? tasks,
    StorageStats? storageStats,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return DownloadsState(
      tasks: tasks ?? this.tasks,
      storageStats: storageStats ?? this.storageStats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadsState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          failure == other.failure &&
          storageStats == other.storageStats &&
          mapEquals(tasks, other.tasks);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(tasks.entries.map((e) => Object.hash(e.key, e.value))),
        storageStats,
        isLoading,
        errorMessage,
        failure,
      );
}

