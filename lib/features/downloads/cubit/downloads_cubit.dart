// lib/features/downloads/cubit/downloads_cubit.dart
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

  StreamSubscription<DownloadTask>? _downloadSub;
  final Map<String, int> _lastEmitTimeByVideoId = {};

  DownloadsCubit(
    this._queueDownloadUseCase,
    this._pauseDownloadUseCase,
    this._resumeDownloadUseCase,
    this._retryDownloadUseCase,
    this._deleteDownloadUseCase,
    this._observeDownloadsUseCase,
    this._getStorageStatsUseCase,
  ) : super(const DownloadsState()) {
    _init();
  }

  Future<void> _init() async {
    emit(state.copyWith(isLoading: true));
    await loadInitialTasks();
    await refreshStorageStats();
    _subscribeToDownloadUpdates();
    emit(state.copyWith(isLoading: false));
  }

  Future<void> loadInitialTasks() async {
    try {
      final tasks = await _observeDownloadsUseCase.getAll();
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

      // Coalesce intermediate progress at ~10Hz (100ms) — prevents rebuild storms
      // from 1000/s chunk callbacks (native parallel emits at ~80ms). Immediate on
      // status transitions / terminal states so pause/complete feels instant.
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
    final result = await _queueDownloadUseCase(task);
    result.fold(
      (failure) {
        emit(state.copyWith(errorMessage: failure.message));
      },
      (_) {},
    );
  }

  Future<void> pauseDownload(String videoId) async {
    final result = await _pauseDownloadUseCase(videoId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) {},
    );
  }

  Future<void> resumeDownload(String videoId) async {
    final result = await _resumeDownloadUseCase(videoId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) {},
    );
  }

  Future<void> retryDownload(String videoId) async {
    final result = await _retryDownloadUseCase(videoId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) {},
    );
  }

  Future<void> deleteDownload(String videoId) async {
    final result = await _deleteDownloadUseCase(videoId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (_) {
        final remaining = Map<String, DownloadTask>.from(state.tasks)
          ..remove(videoId);
        emit(state.copyWith(tasks: Map<String, DownloadTask>.unmodifiable(remaining)));
        refreshStorageStats();
      },
    );
  }

  @override
  Future<void> close() {
    _downloadSub?.cancel();
    _lastEmitTimeByVideoId.clear();
    return super.close();
  }
}
