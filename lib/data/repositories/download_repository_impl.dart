// lib/data/repositories/download_repository_impl.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/channels.dart';
import '../../core/errors/failures.dart';
import '../../core/services/yt_download_service.dart';
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

  final Map<String, DownloadTask> _tasks = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _activeVideoIds = {};
  final Set<String> _pausedVideoIds = {};
  final Map<String, Completer<void>> _activeCompleters = {};
  final StreamController<DownloadTask> _streamController =
      StreamController<DownloadTask>.broadcast();

  Timer? _saveDebounce;
  final Map<String, int> _lastProgressEmitMs = {};

  StorageStats? _cachedStorageStats;
  DateTime? _storageStatsCacheTime;
  static const Duration _storageStatsTtl = Duration(seconds: 5);

  DownloadRepositoryImpl(
    this._ytDownloadService,
  ) {
    reconcileOnBoot();
  }

  @override
  Stream<DownloadTask> observeDownloads() => _streamController.stream;

  @override
  Future<List<DownloadTask>> getAllDownloads() async {
    return _tasks.values.toList();
  }

  @override
  Future<Either<AppFailure, String>> queueDownload(DownloadTask task) async {
    final videoId = task.videoId;
    if (videoId.isEmpty) {
      return const Left(DownloadFailure('Invalid video ID'));
    }

    final existing = _tasks[videoId];
    // Dedupe: if already downloading or queued, return existing id instead of double-writer
    if (existing != null &&
        (existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.queued)) {
      return Right(existing.id);
    }
    if (existing != null && existing.status == DownloadStatus.complete) {
      // Check if file still exists on disk — off main thread via async check
      if (existing.filePath != null) {
        try {
          final exists = await File(existing.filePath!).exists();
          if (exists) return Right(existing.id);
        } catch (_) {}
      }
      // File missing → allow re-download (treat as failed)
    }

    // Storage preflight with typed error (ENOSPC)
    try {
      final freeBytes =
          await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
      if (freeBytes > 0 && freeBytes < 15 * 1024 * 1024) {
        return const Left(
            StorageFailure('Insufficient storage space for downloading audio'));
      }
    } catch (_) {}

    // Mirror sanitize done in YtDownloadService; ensures / \ : * ? etc not in paths
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

    // The notification is started by YtDownloadService when it accepts the job
    // and torn down only once its own queue and active set are both empty. This
    // layer used to raise it here as well and stop it from three places of its
    // own, none of which could see the service's work — so finishing one of
    // three concurrent downloads killed the notification for the other two, and
    // with it the foreground guarantee that keeps them running.
    _processQueue();
    return Right(task.id);
  }

  @override
  Future<Either<AppFailure, Unit>> pauseDownload(String videoId) async {
    final task = _tasks[videoId];
    if (task == null) {
      return const Left(DownloadFailure('Task not found'));
    }

    _pausedVideoIds.add(videoId);
    _queue.remove(videoId);

    if (_activeVideoIds.contains(videoId)) {
      _ytDownloadService.cancel(videoId);
      // Await active completer briefly so that appended .part resume logic sees stable state
      final c = _activeCompleters[videoId];
      if (c != null) {
        try {
          await c.future.timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    }

    _updateTask(task.copyWith(status: DownloadStatus.paused));
    return const Right(unit);
  }

  @override
  Future<Either<AppFailure, Unit>> resumeDownload(String videoId) async {
    final task = _tasks[videoId];
    if (task == null) {
      return const Left(DownloadFailure('Task not found'));
    }

    _pausedVideoIds.remove(videoId);
    final queuedTask = task.copyWith(status: DownloadStatus.queued, error: null);
    _updateTask(queuedTask);

    if (!_activeVideoIds.contains(videoId) && !_queue.contains(videoId)) {
      _queue.add(videoId);
    }

    // Stream URL may be expired (~6h); YtDownloadService re-resolves on retry
    // inside _downloadAudioWithRetry, and raises the notification itself.
    _processQueue();
    return const Right(unit);
  }

  @override
  Future<Either<AppFailure, Unit>> retryDownload(String videoId) async {
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
  }

  @override
  Future<Either<AppFailure, Unit>> deleteDownload(String videoId) async {
    final task = _tasks[videoId];
    _pausedVideoIds.remove(videoId);
    _queue.remove(videoId);

    // Delete-while-downloading race: cancel → await job completion → then delete
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

    _tasks.remove(videoId);

    // Scratch files: the service owns the cache directory and the naming, so it
    // does the targeted delete. The orphan sweep is a second pass for genuine
    // leftovers, and every task still on the books is named so that a paused
    // download's partial survives it — the old call passed `activePartNames: {}`,
    // protecting nothing.
    try {
      await _ytDownloadService.deleteArtifactsFor(videoId);
      await _ytDownloadService.cleanOrphanPartFiles(
          protectedVideoIds: _tasks.keys.toSet());
    } catch (_) {}

    if (task?.filePath != null) {
      try {
        final f = File(task!.filePath!);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
      // Try .part variant too
      try {
        final part = File('${task!.filePath!}.part');
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }

    _cachedStorageStats = null; // Invalidate storage cache
    // No stopDownloadForeground here: deleting one entry says nothing about the
    // other two that may still be transferring, and this used to stop the
    // service unconditionally.
    _schedulePersist();
    _processQueue();
    return const Right(unit);
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
        // Self-heal: externally deleted files reconciled (mark failed) — also update tasks map
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
            // Restore interrupted downloads as paused on startup (process death reconciliation)
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
      // Keep the partials of everything we still track, so a download paused
      // across a restart can resume from its bytes instead of from zero. Named
      // by video id: the on-disk names carry the container extension
      // (`ytdl_<id>.m4a.part`, `.part0..3`, `.parts`), which this layer never
      // learns, so the old exact-name guess of `ytdl_<id>.part` matched nothing.
      final protected = _tasks.values
          .where((t) => t.status != DownloadStatus.complete)
          .map((t) => t.videoId)
          .toSet();
      await _ytDownloadService.cleanOrphanPartFiles(
          protectedVideoIds: protected.isNotEmpty ? protected : null);
      // Enqueue paused tasks for resumption? Keep paused state; user taps resume re-resolves URL (expiry handled)
    } catch (e) {
      ErrorLogger.log('DownloadRepository reconcileOnBoot failed', error: e);
    }
  }

  // Throttle coalescing ~100ms (was 250) — per-tile ValueNotifier would be
  // ideal, but this prevents rebuild storms from 1000/s chunk callbacks.
  //
  // Keyed by videoId: three downloads run at once and they shared one pending
  // slot and one timer, so B's update overwrote A's and cancelled A's timer,
  // then the `videoId ==` guard threw the loser away. A's tile sat frozen at
  // whatever percentage it happened to be on until it finished.
  final Map<String, Timer> _throttleFlushTimers = {};
  final Map<String, DownloadTask> _pendingThrottledTasks = {};
  static const _throttleMs = 100;

  void _updateTask(DownloadTask task) {
    _tasks[task.videoId] = task;

    final videoId = task.videoId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastProgressEmitMs[videoId] ?? 0;
    final isIntermediateProgress = task.status == DownloadStatus.downloading &&
        task.progress > 0.0 &&
        task.progress < 1.0;
    final isTerminal = task.status == DownloadStatus.complete ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.paused;

    if (isIntermediateProgress && (now - lastEmit < _throttleMs) && !isTerminal) {
      _pendingThrottledTasks[videoId] = task;
      _throttleFlushTimers[videoId]?.cancel();
      _throttleFlushTimers[videoId] =
          Timer(const Duration(milliseconds: _throttleMs), () {
        _throttleFlushTimers.remove(videoId);
        final pending = _pendingThrottledTasks.remove(videoId);
        if (pending == null) return;
        _lastProgressEmitMs[videoId] = DateTime.now().millisecondsSinceEpoch;
        if (!_streamController.isClosed) _streamController.add(pending);
      });
      _schedulePersist();
      return;
    }
    _throttleFlushTimers.remove(videoId)?.cancel();
    _pendingThrottledTasks.remove(videoId);

    _lastProgressEmitMs[videoId] = now;
    if (!_streamController.isClosed) {
      _streamController.add(task);
    }
    if (isTerminal) {
      _lastProgressEmitMs.remove(videoId);
    }
    _schedulePersist();
  }

  void dispose() {
    _saveDebounce?.cancel();
    for (final timer in _throttleFlushTimers.values) {
      timer.cancel();
    }
    _throttleFlushTimers.clear();
    _pendingThrottledTasks.clear();
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
    // The notification's lifetime belongs to YtDownloadService: its queue is the
    // one that actually has jobs in it, and it drains after this one does. This
    // used to stop the service the moment the repository's own sets emptied,
    // which is true while the service is still finishing the last transfer.
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
