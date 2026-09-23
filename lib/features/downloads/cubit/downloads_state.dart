import 'package:flutter/foundation.dart';
import '../../../domain/models/download_task.dart';

class DownloadsState {
  final Map<String, DownloadTask> tasks;
  final StorageStats storageStats;
  final bool isLoading;
  final String? errorMessage;

  final List<DownloadTask>? _cachedTaskList;

  const DownloadsState({
    this.tasks = const {},
    this.storageStats = const StorageStats(),
    this.isLoading = false,
    this.errorMessage,
    List<DownloadTask>? cachedTaskList,
  }) : _cachedTaskList = cachedTaskList;

  List<DownloadTask> get taskList =>
      _cachedTaskList ??
      (tasks.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

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
    final nextTasks = tasks ?? this.tasks;
    final precomputedList = tasks != null
        ? (nextTasks.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        : _cachedTaskList;
    return DownloadsState(
      tasks: nextTasks,
      storageStats: storageStats ?? this.storageStats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      cachedTaskList: precomputedList,
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

  // FIX-L2: Use Object.hashAllUnordered for order-independent tasks map hash code
  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(
            tasks.entries.map((e) => Object.hash(e.key, e.value))),
        storageStats,
        isLoading,
        errorMessage,
      );
}
