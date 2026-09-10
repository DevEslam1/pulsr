// lib/features/downloads/cubit/downloads_cubit.dart
import 'dart:async';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

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
import 'downloads_state.dart';

@singleton
class DownloadsCubit extends PulsrCubit<DownloadsState> {
  final QueueDownloadUseCase _queueDownloadUseCase;
  final PauseDownloadUseCase _pauseDownloadUseCase;
  final ResumeDownloadUseCase _resumeDownloadUseCase;
  final RetryDownloadUseCase _retryDownloadUseCase;
  final DeleteDownloadUseCase _deleteDownloadUseCase;
  final ObserveDownloadsUseCase _observeDownloadsUseCase;
  final GetDownloadStorageStatsUseCase _getStorageStatsUseCase;

  StreamSubscription<DownloadTask>? _downloadSub;
  final Map<String, int> _lastEmitTimeByVideoId = {};

  /// Tombstones for recently deleted tasks. A pre-delete emission can still be
  /// in flight on the broadcast stream when [deleteDownload] completes; without
  /// this the stale event resurrects the task in state and it never progresses
  /// (the repository has already dropped it, so no further events ever come).
  static const int _deletedIgnoreWindowMs = 5000;
  final Map<String, int> _deletedAtMsByVideoId = {};

  /// Storage-stat refreshes are fired unawaited from the task listener and
  /// from delete paths; concurrent runs could complete out of order and let a
  /// stale result overwrite a fresh one. Serialized with trailing coalescing.
  bool _statsRefreshInFlight = false;
  bool _statsRefreshQueued = false;

  Timer? _resubscribeTimer;
  int _resubscribeAttempts = 0;

  /// Throttle bookkeeping is pruned once it grows past this; tasks stuck in
  /// `downloading` forever would otherwise leak an entry each.
  static const int _maxThrottleEntries = 128;

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
    safeEmit(state.copyWith(isLoading: true));
    try {
      // Subscribe BEFORE hydrating: getAll() reads the repository's live task
      // map (which is updated before every stream event is emitted), so the
      // snapshot includes everything emitted up to call time, and events
      // emitted after the subscription flow through the listener. The old
      // order (snapshot first, subscribe after) permanently lost any task
      // event emitted inside the gap.
      _subscribeToDownloadUpdates();
      await loadInitialTasks();
      await refreshStorageStats();
    } catch (e, st) {
      // _init runs from the constructor: an unexpected throw (a use case
      // throwing instead of returning Left) would otherwise escape as an
      // unhandled zone error.
      ErrorLogger.log('Downloads init failed',
          error: e, stackTrace: st, category: 'DownloadsCubit');
      safeEmit(state.copyWith(errorMessage: 'Failed to load downloads'));
    } finally {
      if (!isClosed) {
        safeEmit(state.copyWith(isLoading: false));
      }
    }
  }

  Future<void> loadInitialTasks() async {
    try {
      final tasks = await _observeDownloadsUseCase.getAll();
      final taskMap = Map<String, DownloadTask>.unmodifiable({
        for (final t in tasks) t.videoId: t,
      });
      safeEmit(state.copyWith(tasks: taskMap));
    } catch (e, st) {
      // Was `catch (_) {}`: a failed load was indistinguishable from an empty
      // library. Log it and surface it in state.
      ErrorLogger.log('Failed to load initial download tasks',
          error: e, stackTrace: st, category: 'DownloadsCubit');
      safeEmit(state.copyWith(errorMessage: 'Failed to load downloads'));
    }
  }

  void _subscribeToDownloadUpdates() {
    _downloadSub?.cancel();
    removeFromComposite(_downloadSub);
    _downloadSub = autoSub(
      _observeDownloadsUseCase(),
      _onTaskEvent,
      onError: (Object e, StackTrace st) {
        // One unhandled stream error would auto-cancel the subscription and
        // silently freeze the downloads UI forever. Log, then re-subscribe
        // with capped exponential backoff.
        ErrorLogger.log('Downloads stream error',
            error: e, stackTrace: st, category: 'DownloadsCubit');
        _scheduleStreamResubscribe();
      },
      onDone: () {
        // The repository's broadcast controller only closes on app teardown;
        // there is nothing to resubscribe to after that.
        ErrorLogger.log('Downloads stream closed',
            category: 'DownloadsCubit');
      },
    );
  }

  void _scheduleStreamResubscribe() {
    if (isClosed || _resubscribeTimer != null) return;
    _resubscribeAttempts++;
    final shift = (_resubscribeAttempts - 1).clamp(0, 4).toInt();
    final delay = Duration(milliseconds: 250 << shift);
    _resubscribeTimer = autoTimer(Timer(delay, () {
      _resubscribeTimer = null;
      if (!isClosed) {
        _subscribeToDownloadUpdates();
      }
    }));
  }

  void _onTaskEvent(DownloadTask task) {
    if (isClosed) return;
    // Events are flowing again: reset the resubscribe backoff.
    _resubscribeAttempts = 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    _deletedAtMsByVideoId
        .removeWhere((_, deletedAt) => now - deletedAt >= _deletedIgnoreWindowMs);
    if (_deletedAtMsByVideoId.containsKey(task.videoId)) {
      return;
    }

    final existingTask = state.tasks[task.videoId];

    // True dedupe first: with value equality on DownloadTask this drops no-op
    // ticks regardless of which fields the event carries. (The throttle below
    // only guards progress churn.)
    if (existingTask != null && existingTask == task) return;

    final lastEmit = _lastEmitTimeByVideoId[task.videoId] ?? 0;

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

    safeEmit(state.copyWith(tasks: updatedTasks));

    // Prune throttle bookkeeping: tasks that never reach a terminal state
    // would otherwise leak an entry forever.
    if (_lastEmitTimeByVideoId.length > _maxThrottleEntries) {
      _lastEmitTimeByVideoId.removeWhere((videoId, _) {
        final t = updatedTasks[videoId];
        return t == null ||
            t.status.isTerminal ||
            t.status == DownloadStatus.paused;
      });
      if (_lastEmitTimeByVideoId.length > _maxThrottleEntries) {
        // Pathological growth: reset rather than grow unbounded.
        _lastEmitTimeByVideoId.clear();
      }
    }

    if (task.status == DownloadStatus.complete ||
        task.status == DownloadStatus.failed) {
      _lastEmitTimeByVideoId.remove(task.videoId);
      refreshStorageStats();
    }
  }

  Future<void> refreshStorageStats() async {
    if (_statsRefreshInFlight) {
      _statsRefreshQueued = true;
      return;
    }
    _statsRefreshInFlight = true;
    try {
      do {
        _statsRefreshQueued = false;
        final result = await _getStorageStatsUseCase();
        if (isClosed) return;
        result.fold(
          (_) {},
          (stats) => safeEmit(state.copyWith(storageStats: stats)),
        );
      } while (_statsRefreshQueued && !isClosed);
    } catch (e, st) {
      ErrorLogger.log('Failed to refresh storage stats',
          error: e, stackTrace: st, category: 'DownloadsCubit');
    } finally {
      _statsRefreshInFlight = false;
    }
  }

  Future<void> queueDownload(DownloadTask task) async {
    final result = await _queueDownloadUseCase(task);
    if (result.isRight()) {
      // A fresh queue for this video supersedes any delete tombstone, so the
      // queued event is not swallowed by the stale-emission guard.
      _deletedAtMsByVideoId.remove(task.videoId);
    }
    _applyActionResult(result);
  }

  Future<void> pauseDownload(String videoId) async {
    final result = await _pauseDownloadUseCase(videoId);
    _applyActionResult(result);
  }

  Future<void> resumeDownload(String videoId) async {
    final result = await _resumeDownloadUseCase(videoId);
    _applyActionResult(result);
  }

  Future<void> retryDownload(String videoId) async {
    final result = await _retryDownloadUseCase(videoId);
    _applyActionResult(result);
  }

  Future<void> deleteDownload(String videoId) async {
    final result = await _deleteDownloadUseCase(videoId);
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) {
        _lastEmitTimeByVideoId.remove(videoId);
        _deletedAtMsByVideoId[videoId] = DateTime.now().millisecondsSinceEpoch;
        final remaining = Map<String, DownloadTask>.from(state.tasks)
          ..remove(videoId);
        safeEmit(state.copyWith(
          tasks: Map<String, DownloadTask>.unmodifiable(remaining),
          clearErrorMessage: true,
        ));
        refreshStorageStats();
      },
    );
  }

  /// Surfaces a failure message, or clears a stale one once an action succeeds.
  void _applyActionResult<R>(Either<AppFailure, R> result) {
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) => safeEmit(state.copyWith(clearErrorMessage: true)),
    );
  }

  @override
  Future<void> close() {
    _resubscribeTimer?.cancel();
    _lastEmitTimeByVideoId.clear();
    _deletedAtMsByVideoId.clear();
    return super.close();
  }
}
