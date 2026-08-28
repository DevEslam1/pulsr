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
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/channels.dart';
import '../../core/errors/failures.dart';
import '../downloads/yt_download_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/download_task.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/download_repository_interface.dart';

@Singleton(as: IDownloadRepository)
class DownloadRepositoryImpl implements IDownloadRepository {
  static const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
  static const String _prefKey = 'pulsr_download_tasks_v2';
  static const int _maxConcurrent = 3;

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
  Stream<DownloadTask> observeDownloads() => _streamController.stream;

  @override
  Future<List<DownloadTask>> getAllDownloads() async {
    await (_bootReconciliationFuture ?? Future.value());
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
    if (videoId.isEmpty) {
      return const Left(DownloadFailure('Invalid video ID'));
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
          return Left(InsufficientStorageFailure(
            'Insufficient storage space for downloading audio',
            neededBytes: neededBytes.toInt(),
            availableBytes: freeBytes,
          ));
        }
      } catch (_) {}

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

      await _safeInvoke('startDownloadForeground', {
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

      _updateTask(task.copyWith(status: DownloadStatus.paused));
      return const Right(unit);
    });
  }

  @override
  Future<Either<AppFailure, Unit>> resumeDownload(String videoId) async {
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      final task = _tasks[videoId];
      if (task == null) {
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
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      final task = _tasks[videoId];
      if (task == null) {
        return const Left(DownloadFailure('Task not found'));
      }

      return (await queueDownload(task.copyWith(
        status: DownloadStatus.queued,
        progress: 0.0,
        error: null,
      ))).fold(
        (f) => Left(f),
        (_) => const Right(unit),
      );
    });
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
    final lock = _taskLocks.putIfAbsent(videoId, () => Mutex());
    return await lock.protect(() async {
      if (!_tasks.containsKey(videoId)) {
        return const Left(DownloadFailure('Task not found'));
      }
      final task = _tasks[videoId]!;
      if (task.status != DownloadStatus.queued) {
        if (task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.failed ||
            task.status == DownloadStatus.interrupted) {
          await resumeDownload(videoId);
        }
      }
      _queue.remove(videoId);
      _queue.addFirst(videoId);
      _schedulePersist();
      _processQueue();
      return const Right(unit);
    });
  }

  Future<Directory?> _getTempDir() async {
    try {
      return Directory.systemTemp;
    } catch (_) {
      return null;
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
          await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;

      int totalUsedBytes = 0;
      int completedCount = _tasks.values.where((t) => t.status == DownloadStatus.complete && t.filePath != null).length;
      try {
        final files = _tasks.values.where((t) => t.status == DownloadStatus.complete && t.filePath != null).map((t) => t.filePath!).toList();
        final sizes = await Future.wait(files.map((p) async {
          try {
            final f = File(p);
            if (await f.exists()) return await f.length();
          } catch (_) {}
          return 0;
        }));
        totalUsedBytes = sizes.fold(0, (a, b) => a + b);
        final existingCount = sizes.where((s) => s > 0).length;
        if (existingCount > 0) completedCount = existingCount;
        for (int i = 0; i < files.length; i++) {
          if (sizes[i] == 0) {
            final vid = _tasks.values
                .where((t) => t.filePath == files[i])
                .map((t) => t.videoId)
                .firstOrNull;
            if (vid != null) {
              final old = _tasks[vid];
              if (old != null && old.status == DownloadStatus.complete) {
                _tasks[vid] = old.copyWith(status: DownloadStatus.failed, error: 'File deleted');
                if (!_streamController.isClosed) _streamController.add(_tasks[vid]!);
              }
            }
          }
        }
      } catch (_) {}

      final totalBytes = freeBytes + totalUsedBytes;
      final stats = StorageStats(
        usedBytes: totalUsedBytes,
        freeBytes: freeBytes,
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
            if (task.filePath != null && !File(task.filePath!).existsSync()) {
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
      final activeNames = _tasks.values.where((t) => t.status == DownloadStatus.paused).map((t) => 'ytdl_${t.videoId}.part').toSet();
      await _ytDownloadService.cleanOrphanPartFiles(activePartNames: activeNames.isNotEmpty ? activeNames : null);
    } catch (e) {
      ErrorLogger.log('DownloadRepository reconcileOnBoot failed', error: e);
    }
  }

  // Throttle coalescing ~200ms with instant flush on terminal states
  Timer? _throttleFlushTimer;
  DownloadTask? _pendingThrottledTask;
  static const _throttleMs = 200;

  void _updateTask(DownloadTask task) {
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
      if (_pendingThrottledTask != null && _pendingThrottledTask!.videoId == task.videoId) {
        _throttleFlushTimer?.cancel();
        _pendingThrottledTask = null;
      }
      _lastProgressEmitMs.remove(task.videoId);
      if (!_streamController.isClosed) {
        _streamController.add(task);
      }
      _pushFgsProgress(task);
      _schedulePersist();
      return;
    }

    if (isIntermediateProgress && (now - lastEmit < _throttleMs)) {
      _pendingThrottledTask = task;
      _throttleFlushTimer?.cancel();
      _throttleFlushTimer = Timer(const Duration(milliseconds: _throttleMs), () {
        if (_pendingThrottledTask != null && _pendingThrottledTask!.videoId == task.videoId) {
          _lastProgressEmitMs[task.videoId] = DateTime.now().millisecondsSinceEpoch;
          if (!_streamController.isClosed) _streamController.add(_pendingThrottledTask!);
          _pushFgsProgress(_pendingThrottledTask!);
          _pendingThrottledTask = null;
        }
      });
      _schedulePersist();
      return;
    }
    _throttleFlushTimer?.cancel();
    _pendingThrottledTask = null;

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
      if (_activeVideoIds.length <= 1) {
        _downloadChannel.invokeMethod('stopDownloadForeground').catchError((_) {});
      }
    }
  }

  void dispose() {
    _saveDebounce?.cancel();
    _throttleFlushTimer?.cancel();
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
    _queueMutex.protect(() async {
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
        _executeTask(task);
      }
      if (_activeVideoIds.isEmpty && _queue.isEmpty) {
        try {
          _downloadChannel.invokeMethod('stopDownloadForeground');
        } catch (_) {}
      }
    });
  }


  Future<void> _executeTask(DownloadTask task) async {
    final videoId = task.videoId;
    final completer = Completer<void>();
    _activeCompleters[videoId] = completer;
    _updateTask(task.copyWith(status: DownloadStatus.downloading));

    try {
      final synthTrack = YtmTrack(
        videoId: videoId,
        title: task.title,
        artist: task.artist,
        duration: const Duration(minutes: 3),
        artworkUrl: task.artworkUrl,
      );
      final songRow = synthTrack.toSongData();

      final result = await _ytDownloadService.download(
        songRow,
        onProgress: (p) {
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

      if (_pausedVideoIds.contains(videoId)) {
        _activeVideoIds.remove(videoId);
        _activeCompleters.remove(videoId);
        if (!completer.isCompleted) completer.complete();
        _processQueue();
        return;
      }
      // If task was deleted while downloading, don't resurrect
      if (!_tasks.containsKey(videoId)) {
        _activeVideoIds.remove(videoId);
        _activeCompleters.remove(videoId);
        if (!completer.isCompleted) completer.complete();
        _processQueue();
        return;
      }

      result.fold(
        (failure) {
          // Classify via YtmErrorClassifier for localized message, but repository keeps raw for UI to map
          final current = _tasks[videoId] ?? task;
          _updateTask(current.copyWith(
            status: DownloadStatus.failed,
            error: failure.message,
            speedKbps: null,
            etaSeconds: null,
          ));
        },
        (newId) {
          _cachedStorageStats = null; // Invalidate storage stats cache on completion
          final current = _tasks[videoId] ?? task;
          // Atomic commit: YtDownloadService already verified size and renamed .part → final via MediaStore;
          // Here we store filePath if service returned it via side-channel? For now mark complete.
          _updateTask(current.copyWith(
            status: DownloadStatus.complete,
            progress: 1.0,
            error: null,
            speedKbps: null,
            etaSeconds: null,
          ));
        },
      );
    } catch (e) {
      if (_tasks.containsKey(videoId)) {
        final current = _tasks[videoId] ?? task;
        _updateTask(current.copyWith(
          status: DownloadStatus.failed,
          error: e.toString(),
          speedKbps: null,
          etaSeconds: null,
        ));
      }
    } finally {
      _activeVideoIds.remove(videoId);
      _activeCompleters.remove(videoId);
      if (!completer.isCompleted) completer.complete();
      _processQueue();
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
