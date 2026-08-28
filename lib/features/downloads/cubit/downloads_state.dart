// lib/features/downloads/cubit/downloads_state.dart
// DL-19: Typed failures and retryable classification.

import 'package:flutter/foundation.dart';
import '../../../core/errors/failures.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/retry_policy.dart';

class DownloadTaskMap implements Map<String, DownloadTask> {
  final Map<String, DownloadTask> _inner;

  const DownloadTaskMap([this._inner = const {}]);

  @override
  DownloadTask? operator [](Object? key) {
    if (key == null) return null;
    final direct = _inner[key];
    if (direct != null) return direct;
    for (final task in _inner.values) {
      if (task.videoId == key || task.id == key) {
        return task;
      }
    }
    return null;
  }

  @override
  bool containsKey(Object? key) {
    if (key == null) return false;
    if (_inner.containsKey(key)) return true;
    for (final task in _inner.values) {
      if (task.videoId == key || task.id == key) {
        return true;
      }
    }
    return false;
  }

  @override
  bool containsValue(Object? value) => _inner.containsValue(value);

  @override
  Iterable<MapEntry<String, DownloadTask>> get entries => _inner.entries;

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  Iterable<DownloadTask> get values => _inner.values;

  @override
  int get length => _inner.length;

  @override
  bool get isEmpty => _inner.isEmpty;

  @override
  bool get isNotEmpty => _inner.isNotEmpty;

  @override
  void operator []=(String key, DownloadTask value) => throw UnsupportedError('Immutable');
  @override
  void clear() => throw UnsupportedError('Immutable');
  @override
  void addAll(Map<String, DownloadTask> other) => throw UnsupportedError('Immutable');
  @override
  void addEntries(Iterable<MapEntry<String, DownloadTask>> newEntries) => throw UnsupportedError('Immutable');
  @override
  DownloadTask putIfAbsent(String key, DownloadTask Function() ifAbsent) => throw UnsupportedError('Immutable');
  @override
  DownloadTask? remove(Object? key) => throw UnsupportedError('Immutable');
  @override
  void removeWhere(bool Function(String key, DownloadTask value) test) => throw UnsupportedError('Immutable');
  @override
  DownloadTask update(String key, DownloadTask Function(DownloadTask value) update, {DownloadTask Function()? ifAbsent}) => throw UnsupportedError('Immutable');
  @override
  void updateAll(DownloadTask Function(String key, DownloadTask value) update) => throw UnsupportedError('Immutable');
  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(String key, DownloadTask value) convert) => _inner.map(convert);
  @override
  void forEach(void Function(String key, DownloadTask action) action) => _inner.forEach(action);
  @override
  Map<K2, V2> cast<K2, V2>() => _inner.cast<K2, V2>();
}

class DownloadsState {
  final Map<String, DownloadTask> tasks;
  final StorageStats storageStats;
  final bool isLoading;
  final String? errorMessage;
  final AppFailure? failure;

  const DownloadsState({
    this.tasks = const DownloadTaskMap(),
    this.storageStats = const StorageStats(),
    this.isLoading = false,
    this.errorMessage,
    this.failure,
  });

  List<DownloadTask> get taskList {
    final list = tasks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<DownloadTask>.unmodifiable(list);
  }

  DownloadTask? byId(String idOrVideoId) =>
      tasks[idOrVideoId] ??
      tasks.values.cast<DownloadTask?>().firstWhere(
            (t) => t?.videoId == idOrVideoId || t?.id == idOrVideoId,
            orElse: () => null,
          );

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

  DownloadsState clearTransient() {
    return DownloadsState(
      tasks: tasks,
      storageStats: storageStats,
      isLoading: isLoading,
      errorMessage: null,
      failure: null,
    );
  }

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
      tasks: tasks != null ? (tasks is DownloadTaskMap ? tasks : DownloadTaskMap(Map<String, DownloadTask>.unmodifiable(tasks))) : this.tasks,
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
