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
  int get hashCode {
    // Order-insensitive on purpose: == uses mapEquals, which ignores insertion
    // order, so two maps holding the same entries must produce the same hash
    // regardless of iteration order. (Object.hashAllUnordered would do this
    // directly, but it needs Dart 3.2+ and pubspec declares >=3.0.0; a
    // commutative sum of per-entry hashes achieves the same.)
    var tasksHash = 0;
    for (final entry in tasks.entries) {
      tasksHash += Object.hash(entry.key, entry.value);
    }
    return Object.hash(tasksHash, storageStats, isLoading, errorMessage);
  }
}
