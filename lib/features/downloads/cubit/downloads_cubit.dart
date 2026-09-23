import 'dart:async';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

import 'package:mutex/mutex.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/repositories/download_repository_interface.dart'; // FIX-I02
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
  final IDownloadRepository? _downloadRepository; // FIX-I02

  StreamSubscription<DownloadTask>? _downloadSub;
  // FIX-A06: Monotonic clock for download event throttling and deletion tracking
  final Stopwatch _throttleStopwatch = Stopwatch()..start();
  int get _nowMs => _throttleStopwatch.elapsedMilliseconds;
  final Map<String, int> _lastEmitTimeByVideoId = {};
  Timer? _storageStatsDebounceTimer; // FIX-A14: debounce storage stats refresh

  /// Tombstones for recently deleted tasks. A pre-delete emission can still be
  /// in flight on the broadcast stream when [deleteDownload] completes; without
  /// this the stale event resurrects the task in state and it never progresses
  /// (the repository has already dropped it, so no further events ever come).
  static const int _deletedIgnoreWindowMs = 5000;
  final Map<String, int> _deletedAtMsByVideoId = {};
  // FIX-G2: Single-writer mutex for tombstone mutations
  final Mutex _deleteMutex = Mutex();

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
    this._getStorageStatsUseCase, [
    this._downloadRepository, // FIX-I02
  ]) : super(const DownloadsState()) {
    _init();
  }

  Future<void> _pruneDeletedTombstones() async {
    await _deleteMutex.protect(() async {
      final now = _nowMs;
      _deletedAtMsByVideoId.removeWhere(
          (_, deletedAt) => now - deletedAt >= _deletedIgnoreWindowMs);
    });
  }

  Future<void> _init() async {
    // Reset tombstones at start of init
    await _deleteMutex.protect(() async {
      _deletedAtMsByVideoId.clear();
    });
    await _pruneDeletedTombstones();
    safeEmit(state.copyWith(isLoading: true));
    try {
      // FIX-I02: Reconcile on boot from cubit init rather than repository constructor
      await (_downloadRepository?.reconcileOnBoot() ?? _observeDownloadsUseCase.reconcileOnBoot());
      // Subscribe BEFORE hydrating: getAll() reads the repository's live task
      // map (which is updated before every stream event is emitted), so the
      // snapshot includes everything emitted up to call time, and events
      // emitted after the subscription flow through the listener. The old
      // order (snapshot first, subscribe after) permanently lost any task
      // event emitted inside the gap.
      _subscribeToDownloadUpdates();
      await loadInitialTasks();
      await refreshStorageStats();
      // B-11 / FIX-C4: Periodic prune of deleted tombstones older than ignore window
      autoTimer(Timer.periodic(const Duration(seconds: 30), (_) {
        if (isClosed) return;
        _pruneDeletedTombstones();
      }));
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

  Future<void> _onTaskEvent(DownloadTask task) async {
    if (isClosed) return;
    // Events are flowing again: reset the resubscribe backoff.
    _resubscribeAttempts = 0;

    final shouldDrop = await _deleteMutex.protect(() async {
      final now = _nowMs;
      _deletedAtMsByVideoId
          .removeWhere((_, deletedAt) => now - deletedAt >= _deletedIgnoreWindowMs);
      if (_deletedAtMsByVideoId.containsKey(task.videoId)) return true;

      final currentTasks = state.tasks;
      final existingTask = currentTasks[task.videoId];
      if (existingTask != null && existingTask == task) return true;

      final lastEmit = _lastEmitTimeByVideoId[task.videoId] ?? 0;
      final isProgressOnly = existingTask != null &&
          existingTask.status == task.status &&
          task.status == DownloadStatus.downloading &&
          task.progress < 1.0;

      if (isProgressOnly && (now - lastEmit < 100)) {
        return true;
      }

      _lastEmitTimeByVideoId[task.videoId] = now;
      return false;
    });
    if (shouldDrop || isClosed) {
      return;
    }

    final updatedTasks = Map<String, DownloadTask>.unmodifiable({
      ...state.tasks,
      task.videoId: task,
    });

    safeEmit(state.copyWith(tasks: updatedTasks));

    await _deleteMutex.protect(() async {
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
          _lastEmitTimeByVideoId.removeWhere((videoId, _) {
            final t = updatedTasks[videoId];
            return t == null || t.status.isTerminal;
          });
          if (_lastEmitTimeByVideoId.length > _maxThrottleEntries) {
            final entries = _lastEmitTimeByVideoId.entries.toList()
              ..sort((a, b) => a.value.compareTo(b.value));
            final toRemove = entries.take(_lastEmitTimeByVideoId.length - _maxThrottleEntries);
            for (final e in toRemove) {
              _lastEmitTimeByVideoId.remove(e.key);
            }
          }
        }
      }

      // FIX-H03: Clean up throttle entry for all terminal states
      if (task.status.isTerminal ||
          task.status == DownloadStatus.complete ||
          task.status == DownloadStatus.failed) {
        _lastEmitTimeByVideoId.remove(task.videoId);
      }
    });

    if (task.status.isTerminal ||
        task.status == DownloadStatus.complete ||
        task.status == DownloadStatus.failed) {
      _scheduleDebouncedStorageStats(); // FIX-A14: debounce rapid updates
    }
  }

  // FIX-A14: 300ms debounce on storage stats refresh to prevent disk thrashing
  void _scheduleDebouncedStorageStats() {
    _storageStatsDebounceTimer?.cancel();
    _storageStatsDebounceTimer = autoTimer(Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) {
        refreshStorageStats();
      }
    }));
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
      await _deleteMutex.protect(() async {
        _deletedAtMsByVideoId.remove(task.videoId);
      });
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

  /// Re-queues every failed task with pacing, for one-tap recovery after a
  /// batch hit rate limits or lost connectivity. Permanent failures
  /// (unavailable/geo/auth) will fail again individually; transient ones get
  /// the staggered spacing they need. Returns the number re-queued.
  Future<int> retryAllFailed({int delayMs = 500}) async {
    final failedIds = state.tasks.values
        .where((t) => t.status == DownloadStatus.failed)
        .map((t) => t.videoId)
        .toList();
    var queued = 0;
    for (var i = 0; i < failedIds.length; i++) {
      if (isClosed) break;
      if (i > 0 && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (isClosed) break;
      final result = await _retryDownloadUseCase(failedIds[i]);
      // FIX-M07: Check isClosed immediately after async retry use-case
      if (isClosed) break;
      if (result.isRight()) queued++;
    }
    if (!isClosed && failedIds.isNotEmpty && queued == 0) {
      safeEmit(state.copyWith(
          errorMessage: 'Could not retry failed downloads'));
    }
    return queued;
  }

  // FIX-A13: Cancel download by pausing and removing task
  Future<void> cancelDownload(String videoId) async {
    await pauseDownload(videoId);
    await deleteDownload(videoId);
  }

  Future<void> deleteDownload(String videoId) async {
    final result = await _deleteDownloadUseCase(videoId);
    if (isClosed) return;
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (_) async {
        await _deleteMutex.protect(() async {
          _lastEmitTimeByVideoId.remove(videoId);
          _deletedAtMsByVideoId[videoId] = _nowMs;
        });
        final remaining = Map<String, DownloadTask>.from(state.tasks)
          ..remove(videoId);
        safeEmit(state.copyWith(
          tasks: Map<String, DownloadTask>.unmodifiable(remaining),
          clearErrorMessage: true,
        ));
        _scheduleDebouncedStorageStats(); // FIX-A14
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
  Future<void> close() async {
    _storageStatsDebounceTimer?.cancel(); // FIX-A14
    _resubscribeTimer?.cancel();
    // C-01: Await the mutex-protected tombstone clear. Previously the returned
    // future was dropped, so `super.close()` could complete while the clear was
    // still queued behind an in-flight write — leaving dirty tombstones behind.
    await _deleteMutex.protect(() async {
      _deletedAtMsByVideoId.clear();
    });
    _lastEmitTimeByVideoId.clear();
    await super.close();
  }
}
