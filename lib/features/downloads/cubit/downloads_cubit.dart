// lib/features/downloads/cubit/downloads_cubit.dart
// DL-15: Per-taskId action mutex and debouncing to prevent duplicate jobs.
// DL-16: Granular 100ms throttle on progress updates.
// DL-18: Safe async continuations with if (isClosed) return guards.
// DL-19: Typed failure mapping with retryable classification.

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../domain/models/download_task.dart';
import '../../../domain/usecases/delete_download.dart';
import '../../../domain/usecases/get_download_storage_stats.dart';
import '../../../domain/usecases/observe_downloads.dart';
import '../../../domain/usecases/pause_download.dart';
import '../../../domain/usecases/queue_download.dart';
import '../../../domain/usecases/resume_download.dart';
import '../../../domain/usecases/retry_download.dart';
import '../../../domain/usecases/prioritize_download.dart';
import '../../../domain/usecases/reorder_downloads.dart';
import 'downloads_state.dart';

@singleton
class DownloadsCubit extends Cubit<DownloadsState> {
  final QueueDownloadUseCase _queueDownloadUseCase;
  final PauseDownloadUseCase _pauseDownloadUseCase;
  final ResumeDownloadUseCase _resumeDownloadUseCase;
  final RetryDownloadUseCase _retryDownloadUseCase;
  final DeleteDownloadUseCase _deleteDownloadUseCase;
  final ObserveDownloadsUseCase _observeDownloadsUseCase;
  final GetDownloadStorageStatsUseCase _getStorageStatsUseCase;
  final ReorderDownloadsUseCase? _reorderDownloadsUseCase;
  final PrioritizeDownloadUseCase? _prioritizeDownloadUseCase;

  StreamSubscription<DownloadTask>? _downloadSub;
  final Map<String, int> _lastEmitTimeByVideoId = {};
  final Set<String> _inFlightActions = {}; // DL-15: Mutex lock per task

  DownloadsCubit(
    this._queueDownloadUseCase,
    this._pauseDownloadUseCase,
    this._resumeDownloadUseCase,
    this._retryDownloadUseCase,
    this._deleteDownloadUseCase,
    this._observeDownloadsUseCase,
    this._getStorageStatsUseCase, [
    this._reorderDownloadsUseCase,
    this._prioritizeDownloadUseCase,
  ]) : super(const DownloadsState()) {
    _init();
  }

  Future<void> _init() async {
    emit(state.copyWith(isLoading: true));
    await loadInitialTasks();
    await refreshStorageStats();
    _subscribeToDownloadUpdates();
    if (!isClosed) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> loadInitialTasks() async {
    try {
      final tasks = await _observeDownloadsUseCase.getAll();
      if (isClosed) return;
      final taskMap = Map<String, DownloadTask>.unmodifiable({
        for (final t in tasks) t.videoId: t,
      });
      if (!isClosed) {
        emit(state.copyWith(tasks: taskMap));
      }
    } catch (_) {}
  }

  void _subscribeToDownloadUpdates() {
    _downloadSub?.cancel();
    _downloadSub = _observeDownloadsUseCase().listen((task) {
      if (isClosed) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final lastEmit = _lastEmitTimeByVideoId[task.videoId] ?? 0;
      final existingTask = state.tasks[task.videoId];

      final isProgressOnly = existingTask != null &&
          existingTask.status == task.status &&
          task.status == DownloadStatus.downloading &&
          task.progress < 1.0;

      if (isProgressOnly && (now - lastEmit < 100)) {
        return;
      }

      _lastEmitTimeByVideoId[task.videoId] = now;
      final updatedTasks = Map<String, DownloadTask>.unmodifiable({
        ...state.tasks,
        task.videoId: task,
      });

      emit(state.copyWith(tasks: updatedTasks));

      if (task.status == DownloadStatus.complete ||
          task.status == DownloadStatus.failed) {
        refreshStorageStats();
      }
    });
  }

  Future<void> refreshStorageStats() async {
    final result = await _getStorageStatsUseCase();
    if (isClosed) return;
    result.fold(
      (_) {},
      (stats) {
        if (!isClosed) {
          emit(state.copyWith(storageStats: stats));
        }
      },
    );
  }

  Future<void> queueDownload(DownloadTask task) async {
    if (_inFlightActions.contains(task.videoId)) return;
    _inFlightActions.add(task.videoId);

    try {
      final result = await _queueDownloadUseCase(task);
      if (isClosed) return;
      result.fold(
        (failure) {
          emit(state.copyWith(errorMessage: failure.message, failure: failure));
        },
        (_) {},
      );
    } finally {
      _inFlightActions.remove(task.videoId);
    }
  }

  Future<void> pauseDownload(String videoId) async {
    if (_inFlightActions.contains(videoId)) return;
    _inFlightActions.add(videoId);

    try {
      final result = await _pauseDownloadUseCase(videoId);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {},
      );
    } finally {
      _inFlightActions.remove(videoId);
    }
  }

  Future<void> resumeDownload(String videoId) async {
    if (_inFlightActions.contains(videoId)) return;
    _inFlightActions.add(videoId);

    try {
      final result = await _resumeDownloadUseCase(videoId);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {},
      );
    } finally {
      _inFlightActions.remove(videoId);
    }
  }

  Future<void> retryDownload(String videoId) async {
    if (_inFlightActions.contains(videoId)) return;
    _inFlightActions.add(videoId);

    try {
      final result = await _retryDownloadUseCase(videoId);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {},
      );
    } finally {
      _inFlightActions.remove(videoId);
    }
  }

  Future<void> deleteDownload(String videoId) async {
    if (_inFlightActions.contains(videoId)) return;
    _inFlightActions.add(videoId);

    try {
      final result = await _deleteDownloadUseCase(videoId);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {
          if (isClosed) return;
          final remaining = Map<String, DownloadTask>.from(state.tasks)
            ..remove(videoId);
          emit(state.copyWith(tasks: Map<String, DownloadTask>.unmodifiable(remaining)));
          refreshStorageStats();
        },
      );
    } finally {
      _inFlightActions.remove(videoId);
    }
  }

  Future<void> prioritizeDownload(String videoId) async {
    final useCase = _prioritizeDownloadUseCase;
    if (useCase != null) {
      final result = await useCase(videoId);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {},
      );
    }
  }

  Future<void> resumeAllPaused() async {
    final pausedTasks = state.tasks.values
        .where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.interrupted)
        .toList();
    for (final task in pausedTasks) {
      if (isClosed) return;
      await resumeDownload(task.videoId);
    }
  }

  Future<void> retryAllFailed() async {
    final failedTasks = state.tasks.values
        .where((t) => t.status == DownloadStatus.failed || t.status == DownloadStatus.interrupted)
        .toList();
    for (final task in failedTasks) {
      if (isClosed) return;
      await retryDownload(task.videoId);
    }
  }

  Future<void> reorderQueue(List<String> orderedVideoIds) async {
    final useCase = _reorderDownloadsUseCase;
    if (useCase != null) {
      final result = await useCase(orderedVideoIds);
      if (isClosed) return;
      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message, failure: failure)),
        (_) {},
      );
    }
  }

  @override
  Future<void> close() {
    _downloadSub?.cancel();
    _lastEmitTimeByVideoId.clear();
    _inFlightActions.clear();
    return super.close();
  }
}

