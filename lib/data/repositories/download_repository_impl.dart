// lib/data/repositories/download_repository_impl.dart
// DL-01: Reconcile interrupted tasks on boot.
// DL-03: Safe method channel wrapper with FeatureDisabledFailure support.
// DL-04: Storage preflight before queueing.
// DL-06: Duplicate queue protection.
// DL-09: Debounced and distinct download updates.
// DL-15: Per-task action lock to prevent double-tap races.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/errors/failures.dart';
import '../../data/services/ytm_service.dart';
import '../downloads/yt_download_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/ytm_rate_limiter.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/retry_policy.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/download_repository_interface.dart';
import '../../domain/repositories/music_repository_interface.dart';

@Singleton(as: IDownloadRepository)
class DownloadRepositoryImpl implements IDownloadRepository {
  static const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
  static const String _prefKey = 'pulsr_download_tasks_v2';
  static const int _maxConcurrent = 3;

  /// Bounded auto-retry budget for transient failures (network drop, stream
  /// expiry, interrupted transfer). Permanent failures never auto-retry.
  static const int _maxAutoRetries = 2;
  final RetryPolicy _retryPolicy = const RetryPolicy();

  /// Dart-side mirror of the native DownloadTimeoutHandler: a download that
  /// produces no progress for the stall window is cancelled and fails
  /// retryable instead of hanging on a silent socket forever.
  static const String _prefStallWindowSeconds =
      'setting_download_progress_timeout';
  static const int _defaultStallWindowSeconds = 30;
  static const int _minStallWindowSeconds = 10;
  static const int _maxStallWindowSeconds = 3600;
  static const Duration _stallCheckInterval = Duration(seconds: 5);

  final YtDownloadService _ytDownloadService;
  final Mutex _queueMutex = Mutex();

  final Map<String, DownloadTask> _tasks = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _activeVideoIds = {};
  final Set<String> _pausedVideoIds = {};
  final Map<String, Mutex> _taskLocks = {}; // DL-15: Serialized action lock per videoId
  final Map<String, Completer<void>> _activeCompleters = {};
  final StreamController<DownloadTask> _streamController =
      StreamController<DownloadTask>.broadcast();

  Future<void>? _bootReconciliationFuture;
  Timer? _saveDebounce;
  final Map<String, int> _lastProgressEmitMs = {};

  StorageStats? _cachedStorageStats;
  DateTime? _storageStatsCacheTime;
  static const Duration _storageStatsTtl = Duration(seconds: 5);

  DownloadRepositoryImpl(
    this._ytDownloadService,
  ) {
    _bootReconciliationFuture = reconcileOnBoot();
  }

  @override
  Stream<DownloadTask> observeDownloads() async* {
    // Replay current tasks for late subscribers (e.g., Cubit recreated after navigation)
    // so they don't miss last DownloadTask state until next progress tick.
    for (final task in _tasks.values) {
      yield task;
    }
    yield* _streamController.stream;
  }

  @override
  Future<List<DownloadTask>> getAllDownloads() async {
    await (_bootReconciliationFuture ?? Future<void>.value());
    return _tasks.values.toList();
  }

  /// DL-03: Safe invoker for native download channel
  Future<T?> _safeInvoke<T>(String method, [dynamic arguments]) async {
    try {
      return await _downloadChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Either<AppFailure, String>> queueDownload(DownloadTask task) async {
    final videoId = task.videoId;
    if (videoId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      return const Left(ValidationFailure('Invalid video ID: must be exactly 11 characters'));
    }

    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      final existing = _tasks[videoId];
      // DL-06: Dedupe if already active, queued, or paused
      if (existing != null &&
          (existing.status == DownloadStatus.downloading ||
              existing.status == DownloadStatus.queued ||
              existing.status == DownloadStatus.embedding ||
              existing.status == DownloadStatus.paused ||
              existing.status == DownloadStatus.interrupted)) {
        return const Left(AlreadyQueuedFailure('Task is already queued or active'));
      }
      if (existing != null && existing.status == DownloadStatus.complete) {
        if (existing.filePath != null) {
          try {
            final exists = await File(existing.filePath!).exists();
            if (exists) {
              return const Left(AlreadyQueuedFailure('Task is already downloaded and complete'));
            }
          } catch (_) {}
        }
      }

      // DL-04: Storage preflight with 1.1x safety factor + 5MB buffer
      try {
        final freeBytes = await _safeInvoke<int>('getFreeDiskSpace') ?? 0;
        const estBitrateKbps = 160;
        const estDurationSeconds = 240;
        const safetyFactor = 1.1;
        const neededBytes = (estDurationSeconds * (estBitrateKbps * 1000 ~/ 8) * safetyFactor) +
            (5 * 1024 * 1024);

        if (freeBytes > 0 && freeBytes < neededBytes.toInt()) {
          const failure = InsufficientStorageFailure(
            'Insufficient storage space for downloading audio',
          );
          ErrorLogger.log(
            'queueDownload($videoId) storage preflight failed: '
            'needed=$neededBytes free=$freeBytes',
            category: 'DownloadsRepository',
          );
          return Left(failure);
        }
      } catch (_) {}

      // Consult the shared YTM rate limiter before queueing so a burst of
      // downloads cannot burn the IP-level token bucket and trigger 429s.
      // Limiter failures must never block queueing.
      try {
        await YtmRateLimiter.shared
            .acquirePermit(priority: YtmRequestPriority.background);
      } catch (e) {
        ErrorLogger.log('YtmRateLimiter acquirePermit failed; continuing',
            error: e, category: 'DownloadsRepository');
      }

      final queuedTask = task.copyWith(
        status: DownloadStatus.queued,
        progress: 0.0,
        error: null,
      );

      _pausedVideoIds.remove(videoId);
      _updateTask(queuedTask);

      if (!_activeVideoIds.contains(videoId) && !_queue.contains(videoId)) {
        _queue.add(videoId);
      }

      await _safeInvoke<void>('startDownloadForeground', {
        'videoId': videoId,
        'title': task.title,
      });

      _processQueue();
      return Right(task.id);
    });
  }

  @override
  Future<Either<AppFailure, Unit>> pauseDownload(String videoId) async {
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      final task = _tasks[videoId];
      if (task == null) {
        ErrorLogger.log(
          'pauseDownload($videoId): task not found',
          category: 'DownloadsRepository',
        );
        return const Left(DownloadFailure('Task not found'));
      }

      _pausedVideoIds.add(videoId);
      _queue.remove(videoId);

      if (_activeVideoIds.contains(videoId)) {
        _ytDownloadService.cancel(videoId);
        final c = _activeCompleters[videoId];
        if (c != null) {
          try {
            await c.future.timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
      }

      _updateTask(task.copyWith(
        status: DownloadStatus.paused,
        clearSpeedKbps: true,
        clearEtaSeconds: true,
        clearTotalBytes: true,
      ));
      return const Right(unit);
    });
  }

  @override
  Future<Either<AppFailure, Unit>> resumeDownload(String videoId) async {
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      final task = _tasks[videoId];
      if (task == null) {
        ErrorLogger.log(
          'resumeDownload($videoId): task not found',
          category: 'DownloadsRepository',
        );
        return const Left(DownloadFailure('Task not found'));
      }

      if (_queue.contains(videoId) || _activeVideoIds.contains(videoId)) {
        return const Right(unit);
      }

      _pausedVideoIds.remove(videoId);
      final queuedTask = task.copyWith(status: DownloadStatus.queued, error: null);
      _updateTask(queuedTask);

      if (!_activeVideoIds.contains(videoId) && !_queue.contains(videoId)) {
        _queue.add(videoId);
      }

      try {
        await _downloadChannel.invokeMethod('startDownloadForeground', {
          'videoId': videoId,
          'title': task.title,
        });
      } catch (_) {}

      _processQueue();
      return const Right(unit);
    });
  }

  @override
  Future<Either<AppFailure, Unit>> retryDownload(String videoId) async {
    DownloadTask? taskToRetry;
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    final precheck = await lock.protect(() async {
      final task = _tasks[videoId];
      if (task == null) {
        ErrorLogger.log(
          'retryDownload($videoId): task not found',
          category: 'DownloadsRepository',
        );
        return const Left<DownloadFailure, Unit>(DownloadFailure('Task not found'));
      }
      // Prepare retry task outside lock to avoid re-entrancy deadlock (queueDownload also locks same videoId)
      taskToRetry = task.copyWith(
        status: DownloadStatus.queued,
        progress: 0.0,
        error: null,
      );
      return null;
    });
    if (precheck != null) return precheck;
    if (taskToRetry == null) {
      return const Left(DownloadFailure('Task not found'));
    }
    // Now call queueDownload without holding the per-task lock
    return (await queueDownload(taskToRetry!)).fold(
      (f) => Left(f),
      (_) => const Right(unit),
    );
  }

  @override
  Future<Either<AppFailure, Unit>> deleteDownload(String videoId) async {
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    final result = await lock.protect(() async {
      final task = _tasks[videoId];
      _pausedVideoIds.remove(videoId);
      _queue.remove(videoId);

      if (_activeVideoIds.contains(videoId)) {
        _ytDownloadService.cancel(videoId);
        final completer = _activeCompleters[videoId];
        if (completer != null && !completer.isCompleted) {
          try {
            await completer.future.timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
        _activeVideoIds.remove(videoId);
        _activeCompleters.remove(videoId);
      }

      try {
        await _ytDownloadService.cleanOrphanPartFiles(activePartNames: {});
      } catch (_) {}
      if (task?.filePath != null) {
        try {
          final f = File(task!.filePath!);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
        try {
          final part = File('${task!.filePath!}.part');
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
      try {
        final dir = await _getTempDir();
        if (dir != null) {
          final prefix = 'ytdl_$videoId';
          await for (final e in dir.list()) {
            if (e is File && e.path.contains(prefix)) {
              try {
                await e.delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      _tasks.remove(videoId);
      _cachedStorageStats = null;
      try {
        await _downloadChannel.invokeMethod('stopDownloadForeground');
      } catch (_) {}
      _schedulePersist();
      _processQueue();
      return const Right<AppFailure, Unit>(unit);
    });
    if (!lock.isLocked) {
      _taskLocks.remove(videoId);
    }
    return result;
  }

  @override
  Future<Either<AppFailure, Unit>> reorderQueue(List<String> orderedVideoIds) async {
    return _queueMutex.protect(() async {
      final newQueue = Queue<String>();
      for (final vid in orderedVideoIds) {
        if (_queue.contains(vid)) newQueue.add(vid);
      }
      // Add any queued items not in the ordered list
      for (final vid in _queue) {
        if (!newQueue.contains(vid)) newQueue.add(vid);
      }
      _queue.clear();
      _queue.addAll(newQueue);
      _schedulePersist();
      return const Right(unit);
    });
  }


  @override
  Future<Either<AppFailure, Unit>> prioritizeDownload(String videoId) async {
    bool needsResume = false;
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    final precheck = await lock.protect(() async {
      if (!_tasks.containsKey(videoId)) {
        return const Left<DownloadFailure, Unit>(DownloadFailure('Task not found'));
      }
      final task = _tasks[videoId]!;
      if (task.status != DownloadStatus.queued) {
        if (task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.failed ||
            task.status == DownloadStatus.interrupted) {
          needsResume = true;
        }
      }
      return null;
    });
    if (precheck != null) return precheck;
    // Resume outside the per-task lock to avoid re-entrancy (resumeDownload also locks same id)
    if (needsResume) {
      await resumeDownload(videoId);
    }
    // Re-acquire queue mutex for mutation; call _processQueue outside to avoid nested lock deadlock
    final queueResult = await _queueMutex.protect(() async {
      // Re-check existence after resume
      if (!_tasks.containsKey(videoId)) {
        return const Left<DownloadFailure, Unit>(DownloadFailure('Task not found'));
      }
      _queue.remove(videoId);
      _queue.addFirst(videoId);
      _schedulePersist();
      return const Right<DownloadFailure, Unit>(unit);
    });
    if (queueResult.isRight()) {
      _processQueue();
    }
    return queueResult;
  }

  Future<Directory?> _getTempDir() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      try {
        return Directory.systemTemp;
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Future<Either<AppFailure, StorageStats>> getStorageStats() async {
    final now = DateTime.now();
    if (_cachedStorageStats != null &&
        _storageStatsCacheTime != null &&
        now.difference(_storageStatsCacheTime!) < _storageStatsTtl) {
      return Right(_cachedStorageStats!);
    }

    try {
      final freeBytes =
          await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? -1;
      // If platform returns error sentinel, treat as unavailable (don't compute total)
      final effectiveFree = freeBytes >= 0 ? freeBytes : 0;

      int totalUsedBytes = 0;
      int completedCount = _tasks.values.where((t) => t.status == DownloadStatus.complete && t.filePath != null).length;
      final filePaths = <String>{};
      for (final t in _tasks.values) {
        if (t.status == DownloadStatus.complete && t.filePath != null) {
          filePaths.add(t.filePath!);
        }
      }
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final extDir = await getExternalStorageDirectory();
        for (final baseDir in [docDir, extDir]) {
          if (baseDir != null && await baseDir.exists()) {
            await for (final entity in baseDir.list(recursive: true, followLinks: false)) {
              if (entity is File && !entity.path.endsWith('.part') && !entity.path.contains('cache')) {
                filePaths.add(entity.path);
              }
            }
          }
        }
      } catch (_) {}

      try {
        final sizes = await Future.wait(filePaths.map((p) async {
          try {
            final f = File(p);
            if (await f.exists()) return await f.length();
          } catch (_) {}
          return 0;
        }));
        totalUsedBytes = sizes.fold(0, (a, b) => a + b);
        final existingCount = sizes.where((s) => s > 0).length;
        if (existingCount > 0) completedCount = existingCount;
      } catch (_) {}

      // Do NOT mutate task status inside a getter - surface inconsistency via stats only.
      // File-missing correction is handled by reconcileOnBoot and explicit refresh, not here.
      // If needed, caller can invoke a separate `reconcileFiles()` method.

      final totalBytes = effectiveFree + totalUsedBytes;
      final stats = StorageStats(
        usedBytes: totalUsedBytes,
        freeBytes: effectiveFree,
        totalBytes: totalBytes > 0 ? totalBytes : 1,
        downloadedSongsCount: completedCount,
      );

      _cachedStorageStats = stats;
      _storageStatsCacheTime = now;
      return Right(stats);
    } catch (e) {
      return Left(StorageFailure('Failed to calculate storage stats: $e'));
    }
  }

  @override
  Future<void> reconcileOnBoot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_prefKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final list = jsonDecode(rawJson) as List<dynamic>;
        for (final item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued) {
            _tasks[task.videoId] = task.copyWith(status: DownloadStatus.paused);
          } else if (task.status == DownloadStatus.complete) {
            // Avoid blocking main isolate with existsSync(); do async check off-main where possible.
            // For boot we still need sync but guard with try and fallback to async deferred check.
            bool exists = false;
            if (task.filePath != null) {
              try {
                exists = await File(task.filePath!).exists();
              } catch (_) {
                exists = false;
              }
            }
            if (!exists && task.filePath != null) {
              _tasks[task.videoId] =
                  task.copyWith(status: DownloadStatus.failed, error: 'File deleted');
            } else {
              _tasks[task.videoId] = task;
            }
          } else {
            _tasks[task.videoId] = task;
          }
        }
      }
      // Include interrupted as well as paused for part-file protection
      final activeNames = _tasks.values
          .where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.interrupted)
          .map((t) => 'ytdl_${t.videoId}.part')
          .toSet();
      await _ytDownloadService.cleanOrphanPartFiles(activePartNames: activeNames.isNotEmpty ? activeNames : null);
    } catch (e) {
      ErrorLogger.log('DownloadRepository reconcileOnBoot failed', error: e);
    }
  }

  // Throttle coalescing ~200ms with instant flush on terminal states - per videoId to avoid dropping concurrent progress
  final Map<String, Timer> _throttleFlushTimers = {};
  final Map<String, DownloadTask> _pendingThrottledTasks = {};
  static const _throttleMs = 200;
  bool _disposed = false;

  void _updateTask(DownloadTask task) {
    if (_disposed) return;
    _tasks[task.videoId] = task;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastProgressEmitMs[task.videoId] ?? 0;
    final isIntermediateProgress = task.status == DownloadStatus.downloading &&
        task.progress > 0.0 &&
        task.progress < 1.0;
    final isTerminal = task.status == DownloadStatus.complete ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.interrupted;

    if (isTerminal) {
      _throttleFlushTimers[task.videoId]?.cancel();
      _throttleFlushTimers.remove(task.videoId);
      _pendingThrottledTasks.remove(task.videoId);
      _lastProgressEmitMs.remove(task.videoId);
      if (!_streamController.isClosed) {
        _streamController.add(task);
      }
      _pushFgsProgress(task);
      _schedulePersist();
      return;
    }

    if (isIntermediateProgress && (now - lastEmit < _throttleMs)) {
      _pendingThrottledTasks[task.videoId] = task;
      _throttleFlushTimers[task.videoId]?.cancel();
      _throttleFlushTimers[task.videoId] = Timer(const Duration(milliseconds: _throttleMs), () {
        final pending = _pendingThrottledTasks.remove(task.videoId);
        _throttleFlushTimers.remove(task.videoId);
        if (pending != null && !_disposed) {
          _lastProgressEmitMs[pending.videoId] = DateTime.now().millisecondsSinceEpoch;
          if (!_streamController.isClosed) _streamController.add(pending);
          _pushFgsProgress(pending);
        }
      });
      _schedulePersist();
      return;
    }
    _throttleFlushTimers[task.videoId]?.cancel();
    _throttleFlushTimers.remove(task.videoId);
    _pendingThrottledTasks.remove(task.videoId);

    _lastProgressEmitMs[task.videoId] = now;
    if (!_streamController.isClosed) {
      _streamController.add(task);
    }
    _pushFgsProgress(task);
    _schedulePersist();
  }

  void _pushFgsProgress(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      final pct = (task.progress * 100).round().clamp(0, 100);
      _downloadChannel.invokeMethod('updateDownloadProgress', {
        'videoId': task.videoId,
        'title': task.title,
        'progress': pct,
      }).catchError((_) {});
    } else if (task.status == DownloadStatus.complete || task.status == DownloadStatus.failed) {
      // Only stop FGS if no active downloads AND queue empty - otherwise next queued item would need background start
      if (_activeVideoIds.length <= 1 && _queue.isEmpty) {
        _downloadChannel.invokeMethod('stopDownloadForeground').catchError((_) {});
      }
    }
  }

  void dispose() {
    _disposed = true;
    _saveDebounce?.cancel();
    for (final t in _throttleFlushTimers.values) {
      t.cancel();
    }
    _throttleFlushTimers.clear();
    _pendingThrottledTasks.clear();
    _lastProgressEmitMs.clear();
    if (!_streamController.isClosed) _streamController.close();
  }

  void _schedulePersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawList = _tasks.values.map((t) => t.toJson()).toList();
        await prefs.setString(_prefKey, jsonEncode(rawList));
      } catch (_) {}
    });
  }

  void _processQueue() {
    unawaited(_queueMutex.protect(() async {
      while (_activeVideoIds.length < _maxConcurrent && _queue.isNotEmpty) {
        final videoId = _queue.removeFirst();

        if (_pausedVideoIds.contains(videoId)) {
          continue;
        }

        final task = _tasks[videoId];
        if (task == null || task.status == DownloadStatus.complete) {
          continue;
        }

        _activeVideoIds.add(videoId);
        unawaited(_executeTask(task));
      }
      if (_activeVideoIds.isEmpty && _queue.isEmpty) {
        try {
          unawaited(_downloadChannel.invokeMethod('stopDownloadForeground'));
        } catch (_) {}
      }
    }));
  }


  /// Transient failures are worth an automatic bounded retry; permanent ones
  /// (storage full, permissions, feature disabled, bot-blocked) are not.
  bool _isTransientFailure(AppFailure failure) {
    if (failure is InsufficientStorageFailure ||
        failure is PermissionDeniedFailure ||
        failure is AlreadyQueuedFailure ||
        failure is FeatureDisabledFailure ||
        failure is ValidationFailure) {
      return false;
    }
    if (failure is NetworkFailure ||
        failure is InterruptedFailure ||
        failure is FgsTimeoutFailure) {
      return true;
    }
    return RetryPolicy.isRetryableError(failure.message);
  }

  /// Maps an unexpected exception to a typed failure — exceptions must never
  /// surface as raw strings on the task, so the UI keeps retry semantics.
  AppFailure _mapExceptionToFailure(Object e) {
    if (e is SocketException || e is HttpException || e is TimeoutException) {
      return NetworkFailure('Network error during download', e);
    }
    if (e is FileSystemException) {
      final m = e.message.toLowerCase();
      final code = e.osError?.errorCode;
      if (m.contains('no space') || m.contains('enospc') || code == 28) {
        return InsufficientStorageFailure('Insufficient storage space', error: e);
      }
      return DownloadFailure('File error during download: ${e.message}', e);
    }
    return GenericDownloadFailure(e.toString(), e);
  }

  Future<bool> _tryUpdateTaskStatus(
    DownloadTask current,
    DownloadStatus targetStatus, {
    double? progress,
    double? speedKbps,
    int? etaSeconds,
    String? error,
    bool clearError = false,
    bool clearSpeedKbps = false,
    bool clearEtaSeconds = false,
    bool clearTotalBytes = false,
    int? librarySongId,
    String? filePath,
  }) async {
    final lock = _taskLocks.putIfAbsent(current.videoId, () => Mutex());
    return await lock.protect(() async {
      final latest = _tasks[current.videoId] ?? current;
      final validation = TransitionGuard.validate(latest.status, targetStatus);
      return validation.fold(
        (failure) {
          ErrorLogger.log(
            'Illegal state transition rejected for ${latest.videoId}: ${latest.status} -> $targetStatus',
            category: 'DownloadsRepository',
          );
          return false;
        },
        (_) {
          _updateTask(latest.copyWith(
            status: targetStatus,
            progress: progress,
            speedKbps: speedKbps,
            etaSeconds: etaSeconds,
            error: error,
            clearError: clearError,
            clearSpeedKbps: clearSpeedKbps,
            clearEtaSeconds: clearEtaSeconds,
            clearTotalBytes: clearTotalBytes,
            librarySongId: librarySongId,
            filePath: filePath,
          ));
          return true;
        },
      );
    });
  }

  Future<void> _executeTask(DownloadTask task) async {
    final videoId = task.videoId;
    final completer = Completer<void>();
    _activeCompleters[videoId] = completer;

    // D-07: Add Wi-Fi-only and offline-only checks before starting download
    try {
      final prefs = await SharedPreferences.getInstance();
      final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
      if (offlineOnly) {
        await _tryUpdateTaskStatus(task, DownloadStatus.failed,
            error: 'Offline Only Mode is active in Settings');
        _activeCompleters.remove(videoId);
        completer.complete();
        return;
      }
      final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
      if (wifiOnly) {
        final isWifi = await (getIt.isRegistered<YtmService>()
            ? getIt<YtmService>().isWifiConnected()
            : Future.value(true));
        if (!isWifi) {
          await _tryUpdateTaskStatus(task, DownloadStatus.interrupted,
              error: 'Wi-Fi Only Mode is active. Connect to Wi-Fi to download.');
          _activeCompleters.remove(videoId);
          completer.complete();
          return;
        }
      }
    } catch (_) {}

    // D-01: Validate status transition via TransitionGuard
    await _tryUpdateTaskStatus(task, DownloadStatus.downloading, clearError: true);

    // Stall watchdog (Dart-side mirror of DownloadTimeoutHandler): cancels the
    // service's cancellation token when no progress arrives within the window
    // so a silent socket can never wedge the task as "downloading" forever.
    var lastProgressMs = DateTime.now().millisecondsSinceEpoch;
    var stalled = false;
    var stallWindowSeconds = _defaultStallWindowSeconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      final configured = prefs.getInt(_prefStallWindowSeconds);
      if (configured != null) {
        stallWindowSeconds = configured.clamp(
            _minStallWindowSeconds, _maxStallWindowSeconds);
      }
    } catch (_) {}
    final watchdog = Timer.periodic(_stallCheckInterval, (_) {
      if (stalled) return;
      final idleFor =
          DateTime.now().millisecondsSinceEpoch - lastProgressMs;
      if (idleFor > stallWindowSeconds * 1000) {
        stalled = true;
        ErrorLogger.log(
          'Download stall detected for $videoId: no progress for '
          '$stallWindowSeconds s — cancelling attempt',
          category: 'DownloadsRepository',
        );
        _ytDownloadService.cancel(videoId);
      }
    });

    try {
      final synthTrack = YtmTrack(
        videoId: videoId,
        title: task.title,
        artist: task.artist,
        duration: const Duration(minutes: 3),
        artworkUrl: task.artworkUrl,
      );
      final songRow = synthTrack.toSongData();

      int? completedLibraryId;
      var attempt = 0;
      while (true) {
        attempt++;
        lastProgressMs = DateTime.now().millisecondsSinceEpoch;
        stalled = false;
        final result = await _ytDownloadService.download(
          songRow,
          onProgress: (p) {
            lastProgressMs = DateTime.now().millisecondsSinceEpoch;
            if (_pausedVideoIds.contains(videoId)) return;

            final progressTask = _tasks[videoId] ?? task;
            _updateTask(progressTask.copyWith(
              status: DownloadStatus.downloading,
              progress: p.fraction ?? progressTask.progress,
              speedKbps: p.speedKbps,
              etaSeconds: p.etaSeconds,
            ));
          },
        );

        // Pause / delete honored at the first await boundary after the
        // download finishes — never resurrect a paused or removed task.
        if (_pausedVideoIds.contains(videoId) || !_tasks.containsKey(videoId)) {
          return;
        }

        await result.fold(
          (failure) async {
            final current = _tasks[videoId] ?? task;
            // A watchdog-cancel masquerades as "Download canceled" downstream;
            // re-label it so the UI/retry classifier sees a retryable timeout.
            final message = stalled
                ? 'Download timed out: no progress for $stallWindowSeconds seconds'
                : failure.message;
            final transient =
                _isTransientFailure(failure) && attempt <= _maxAutoRetries;
            await _tryUpdateTaskStatus(
              current,
              transient
                  ? DownloadStatus.interrupted
                  : DownloadStatus.failed,
              error: message,
              clearSpeedKbps: true,
              clearEtaSeconds: true,
            );
            if (transient) {
              ErrorLogger.log(
                'Transient download failure for $videoId '
                '(attempt $attempt/$_maxAutoRetries): $message',
                category: 'DownloadsRepository',
              );
            } else {
              ErrorLogger.log(
                'Download failed for $videoId: $message',
                category: 'DownloadsRepository',
              );
            }
          },
          (newId) async {
            _cachedStorageStats = null; // Invalidate storage stats cache on completion
            final current = _tasks[videoId] ?? task;
            // Atomic commit: YtDownloadService already verified size and renamed .part → final via MediaStore.
            // librarySongId travels with the terminal event so observers (e.g.
            // the player swap after a search-initiated download) can follow
            // the reconciled row without a second lookup.
            await _tryUpdateTaskStatus(
              current,
              DownloadStatus.complete,
              progress: 1.0,
              clearError: true,
              clearSpeedKbps: true,
              clearEtaSeconds: true,
              librarySongId: newId,
            );
            completedLibraryId = newId;
          },
        );

        // Record the on-disk path of the reconciled library row so storage
        // stats, delete, and boot integrity checks can operate on the file.
        final newId = completedLibraryId;
        if (newId != null && _tasks.containsKey(videoId)) {
          completedLibraryId = null;
          final musicRepo = getIt.isRegistered<IMusicRepository>()
              ? getIt<IMusicRepository>()
              : null;
          if (musicRepo != null) {
            final rowResult = await musicRepo.getSongById(newId);
            rowResult.fold(
              (f) => ErrorLogger.log(
                  'Post-download row lookup failed for $videoId: ${f.message}',
                  category: 'DownloadsRepository'),
              (row) {
                final path = row?.path;
                final current = _tasks[videoId];
                if (path == null ||
                    path.isEmpty ||
                    current == null ||
                    current.status != DownloadStatus.complete) {
                  return;
                }
                _cachedStorageStats = null;
                _updateTask(current.copyWith(filePath: path));
              },
            );
          }
        }

        final latest = _tasks[videoId];
        if (latest == null) return;
        if (latest.status != DownloadStatus.interrupted) break;

        // Transient failure path: wait with exponential backoff, then retry.
        // Cancellation (pause/delete) during the wait aborts the retry loop.
        final delay = _retryPolicy.delayForAttempt(attempt);
        await Future<void>.delayed(delay);
        if (_pausedVideoIds.contains(videoId) || !_tasks.containsKey(videoId)) {
          return;
        }
        await _tryUpdateTaskStatus(
          _tasks[videoId]!,
          DownloadStatus.downloading,
          clearError: true,
        );
      }
    } catch (e) {
      if (_tasks.containsKey(videoId)) {
        final failure = _mapExceptionToFailure(e);
        final current = _tasks[videoId] ?? task;
        await _tryUpdateTaskStatus(
          current,
          DownloadStatus.failed,
          error: failure.message,
          clearSpeedKbps: true,
          clearEtaSeconds: true,
        );
      }
      ErrorLogger.log('Download task $videoId threw unexpectedly',
          error: e, category: 'DownloadsRepository');
    } finally {
      watchdog.cancel();
      _activeVideoIds.remove(videoId);
      _activeCompleters.remove(videoId);
      if (!completer.isCompleted) completer.complete();
      _processQueue();
    }
  }
}

// _FirstOrNull removed - use collection's firstOrNull from dart extensions where needed
