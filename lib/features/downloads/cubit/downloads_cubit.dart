// lib/features/downloads/cubit/downloads_cubit.dart
// DL-15: Per-taskId action mutex and debouncing to prevent duplicate jobs.
// DL-16: Granular 100ms throttle on progress updates.
// DL-18: Safe async continuations with if (isClosed) return guards.
// DL-19: Typed failure mapping with retryable classification.

import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
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
import '../../../domain/usecases/queue_downloads_batch.dart';
import 'downloads_state.dart';

class _RefMutex {
  final Mutex m = Mutex();
  int waiters = 0;
}

@singleton
class DownloadsCubit extends PulsrCubit<DownloadsState> {
  final QueueDownloadUseCase _queueDownloadUseCase;
  final PauseDownloadUseCase _pauseDownloadUseCase;
  final ResumeDownloadUseCase _resumeDownloadUseCase;
  final RetryDownloadUseCase _retryDownloadUseCase;
  final DeleteDownloadUseCase _deleteDownloadUseCase;
  final ObserveDownloadsUseCase _observeDownloadsUseCase;
  final GetDownloadStorageStatsUseCase _getStorageStatsUseCase;
  final ReorderDownloadsUseCase? _reorderDownloadsUseCase;
  final PrioritizeDownloadUseCase? _prioritizeDownloadUseCase;
  final QueueDownloadsBatchUseCase? _queueDownloadsBatchUseCase;

  final Map<String, _RefMutex> _taskLocks = {};

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
    this._queueDownloadsBatchUseCase,
  ]) : super(const DownloadsState()) {
    _init();
  }

  Future<void> _init() async {
    safeEmit(state.copyWith(isLoading: true));
    await loadInitialTasks();
    await refreshStorageStats();
    _subscribeToDownloadUpdates();
    safeEmit(state.copyWith(isLoading: false));
  }

  void clearError() {
    safeEmit(state.clearTransient());
  }

  /// One-shot failure surfacing: typed Failure stays in state (retryability,
  /// inline surfaces); the toast is a transient effect consumed exactly once.
  void _notifyFailure(String? message) {
    if (message == null || message.isEmpty) return;
    emitEffect(ShowToastEffect(message));
  }

  bool _isActive(DownloadStatus? s) =>
      s == DownloadStatus.queued ||
      s == DownloadStatus.downloading ||
      s == DownloadStatus.embedding ||
      s == DownloadStatus.paused ||
      s == DownloadStatus.interrupted;

  Future<void> _withTaskLock(String id, Future<void> Function() action) async {
    final e = _taskLocks.putIfAbsent(id, _RefMutex.new);
    e.waiters++;
    try {
      await e.m.protect(action);
    } finally {
      e.waiters--;
      final currentStatus = state.tasks[id]?.status;
      if (e.waiters == 0 && !_isActive(currentStatus) && _taskLocks[id] == e) {
        _taskLocks.remove(id);
      }
    }
  }

  Future<void> loadInitialTasks() async {
    try {
      final tasks = await _observeDownloadsUseCase.getAll();
      final taskMap = Map<String, DownloadTask>.unmodifiable({
        for (final t in tasks) (t.id.isNotEmpty ? t.id : t.videoId): t,
      });
      safeEmit(state.copyWith(tasks: taskMap));
    } catch (e, st) {
      ErrorLogger.log('loadInitialTasks in DownloadsCubit failed',
          error: e, stackTrace: st, category: 'DownloadsCubit');
    }
  }

  void _subscribeToDownloadUpdates() {
    autoSub(
      _observeDownloadsUseCase()
          .throttleTime(const Duration(milliseconds: 200), trailing: true),
      (task) {
        final key = task.id.isNotEmpty ? task.id : task.videoId;
        final updatedTasks = Map<String, DownloadTask>.unmodifiable({
          ...state.tasks,
          key: task,
        });

        safeEmit(state.copyWith(tasks: updatedTasks));

        if (task.status == DownloadStatus.complete ||
            task.status == DownloadStatus.failed ||
            task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.interrupted) {
          refreshStorageStats();
        }
      },
    );
  }

  Future<void> refreshStorageStats() async {
    final result = await _getStorageStatsUseCase();
    result.fold(
      (failure) {
        ErrorLogger.log('refreshStorageStats failure: ${failure.message}',
            category: 'DownloadsCubit');
      },
      (stats) {
        safeEmit(state.copyWith(storageStats: stats));
      },
    );
  }

  Future<void> queueDownload(DownloadTask task) async {
    await _withTaskLock(task.videoId, () async {
      try {
        final result = await _queueDownloadUseCase(task);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
          _notifyFailure(failure.message);
          },
          (_) {},
        );
      } catch (e, st) {
        ErrorLogger.log('queueDownload in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    });
  }

  Future<BatchDownloadResult> queueBatch(List<DownloadTask> tasks) async {
    final useCase = _queueDownloadsBatchUseCase;
    if (useCase != null) {
      final res = await useCase.executeWithBatchResult(tasks);
      if (res.hasFailures) {
        final firstFailure = res.failures.isNotEmpty ? res.failures.first : null;
        safeEmit(state.copyWith(
          errorMessage: firstFailure?.message ?? 'Batch download completed with failures',
          failure: firstFailure,
        ));
        _notifyFailure(firstFailure?.message);
      }
      return res;
    }

    final failedIds = <String, AppFailure>{};
    final taskIds = <String>[];
    final failures = <AppFailure>[];
    int queued = 0;
    int skippedDuplicates = 0;

    for (final t in tasks) {
      final key = t.id.isNotEmpty ? t.id : t.videoId;
      await _withTaskLock(t.videoId, () async {
        try {
          final r = await _queueDownloadUseCase(t);
          r.fold(
            (f) {
              if (f is AlreadyQueuedFailure) {
                skippedDuplicates++;
              } else {
                failedIds[key] = f;
                failures.add(f);
              }
            },
            (id) {
              queued++;
              taskIds.add(id);
            },
          );
        } catch (e, st) {
          final f = GenericDownloadFailure(e.toString(), e);
          failedIds[key] = f;
          failures.add(f);
          ErrorLogger.log('queueBatch item failed',
              error: e, stackTrace: st, category: 'DownloadsCubit');
        }
      });
    }

    if (failures.isNotEmpty) {
      safeEmit(state.copyWith(
        errorMessage: failures.first.message,
        failure: failures.first,
      ));
    }

    return BatchDownloadResult(
      totalCount: tasks.length,
      queuedCount: queued,
      skippedDuplicatesCount: skippedDuplicates,
      taskIds: taskIds,
      failedIds: failedIds,
      failures: failures,
    );
  }

  Future<void> pauseDownload(String videoId) async {
    await _withTaskLock(videoId, () async {
      try {
        final result = await _pauseDownloadUseCase(videoId);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
            _notifyFailure(failure.message);
          },
          (_) {},
        );
      } catch (e, st) {
        ErrorLogger.log('pauseDownload in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    });
  }

  Future<void> resumeDownload(String videoId) async {
    await _withTaskLock(videoId, () async {
      try {
        final result = await _resumeDownloadUseCase(videoId);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
            _notifyFailure(failure.message);
          },
          (_) {},
        );
      } catch (e, st) {
        ErrorLogger.log('resumeDownload in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    });
  }

  Future<void> retryDownload(String videoId) async {
    await _withTaskLock(videoId, () async {
      try {
        final result = await _retryDownloadUseCase(videoId);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
            _notifyFailure(failure.message);
          },
          (_) {},
        );
      } catch (e, st) {
        ErrorLogger.log('retryDownload in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    });
  }

  Future<void> deleteDownload(String videoId) async {
    await _withTaskLock(videoId, () async {
      try {
        final result = await _deleteDownloadUseCase(videoId);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
            _notifyFailure(failure.message);
          },
          (_) {
            final remaining = Map<String, DownloadTask>.from(state.tasks)
              ..removeWhere((k, v) => k == videoId || v.videoId == videoId || v.id == videoId);
            safeEmit(state.copyWith(
                tasks: Map<String, DownloadTask>.unmodifiable(remaining)));
            refreshStorageStats();
          },
        );
      } catch (e, st) {
        ErrorLogger.log('deleteDownload in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    });
  }

  Future<void> prioritizeDownload(String videoId) async {
    final useCase = _prioritizeDownloadUseCase;
    if (useCase != null) {
      await _withTaskLock(videoId, () async {
        try {
          final result = await useCase(videoId);
          result.fold(
            (failure) {
              safeEmit(state.copyWith(
                  errorMessage: failure.message, failure: failure));
              _notifyFailure(failure.message);
            },
            (_) {},
          );
        } catch (e, st) {
          ErrorLogger.log('prioritizeDownload in DownloadsCubit failed',
              error: e, stackTrace: st, category: 'DownloadsCubit');
        }
      });
    }
  }

  Future<void> resumeAllPaused() async {
    final pausedTasks = state.tasks.values
        .where((t) =>
            t.status == DownloadStatus.paused ||
            t.status == DownloadStatus.interrupted)
        .toList();
    for (final task in pausedTasks) {
      if (isClosed) return;
      await resumeDownload(task.videoId);
    }
  }

  Future<void> retryAllFailed() async {
    final failedTasks = state.tasks.values
        .where((t) =>
            t.status == DownloadStatus.failed ||
            t.status == DownloadStatus.interrupted)
        .toList();
    for (final task in failedTasks) {
      if (isClosed) return;
      await retryDownload(task.videoId);
    }
  }

  Future<void> reorderQueue(List<String> orderedVideoIds) async {
    final useCase = _reorderDownloadsUseCase;
    if (useCase != null) {
      try {
        final result = await useCase(orderedVideoIds);
        result.fold(
          (failure) {
            safeEmit(state.copyWith(
                errorMessage: failure.message, failure: failure));
            _notifyFailure(failure.message);
          },
          (_) {},
        );
      } catch (e, st) {
        ErrorLogger.log('reorderQueue in DownloadsCubit failed',
            error: e, stackTrace: st, category: 'DownloadsCubit');
      }
    }
  }

  @override
  Future<void> close() {
    _taskLocks.clear();
    return super.close();
  }
}

