import 'package:flutter/foundation.dart';
import '../../../domain/models/download_task.dart';

class DownloadsState {
  final Map<String, DownloadTask> tasks;
  final StorageStats storageStats;
  final bool isLoading;
  final String? errorMessage;

  const DownloadsState({
    this.tasks = const {},
    this.storageStats = const StorageStats(),
    this.isLoading = false,
    this.errorMessage,
  });

  List<DownloadTask> get taskList => tasks.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get activeCount =>
      tasks.values.where((t) => t.status.isActive).length;

  int get completedCount =>
      tasks.values.where((t) => t.status == DownloadStatus.complete).length;

  DownloadsState copyWith({
    Map<String, DownloadTask>? tasks,
    StorageStats? storageStats,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return DownloadsState(
      tasks: tasks ?? this.tasks,
      storageStats: storageStats ?? this.storageStats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadsState &&
          runtimeType == other.runtimeType &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage &&
          storageStats == other.storageStats &&
          mapEquals(tasks, other.tasks);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(tasks.entries.map((e) => Object.hash(e.key, e.value))),
        storageStats,
        isLoading,
        errorMessage,
      );
}
