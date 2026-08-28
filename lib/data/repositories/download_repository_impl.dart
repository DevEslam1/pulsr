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
    if (existing != null && existing.status == DownloadStatus.complete) {
      // Check if file still exists on disk — off main thread via async check
      if (existing.filePath != null) {
        try {
          final exists = await File(existing.filePath!).exists();
          if (exists) return Right(existing.id);
        } catch (_) {}
      }
    }

    // Check storage availability
    try {
      final freeBytes =
          await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
      if (freeBytes > 0 && freeBytes < 15 * 1024 * 1024) {
        return const Left(
            StorageFailure('Insufficient storage space for downloading audio'));
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

    if (_activeVideoIds.contains(videoId)) {
      _ytDownloadService.cancel(videoId);
      _activeVideoIds.remove(videoId);
    }

    if (task?.filePath != null) {
      try {
        final f = File(task!.filePath!);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }

    _tasks.remove(videoId);
    _cachedStorageStats = null; // Invalidate storage cache
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
      // Collect active part names to not delete paused downloads
      final activeNames = _tasks.values.where((t) => t.status == DownloadStatus.paused).map((t) => 'ytdl_${t.videoId}.part').toSet();
      await _ytDownloadService.cleanOrphanPartFiles(activePartNames: activeNames.isNotEmpty ? activeNames : null);
      final rawJson = prefs.getString(_prefKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final list = jsonDecode(rawJson) as List<dynamic>;
        for (final item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued) {
            // Restore interrupted downloads as paused on startup
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
    } catch (e) {
      ErrorLogger.log('DownloadRepository reconcileOnBoot failed', error: e);
    }
  }

  // Throttle pending flush to not drop final intermediate progress
  Timer? _throttleFlushTimer;
  DownloadTask? _pendingThrottledTask;

  void _updateTask(DownloadTask task) {
    _tasks[task.videoId] = task;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastProgressEmitMs[task.videoId] ?? 0;
    final isIntermediateProgress = task.status == DownloadStatus.downloading &&
        task.progress > 0.0 &&
        task.progress < 1.0;
    final isTerminal = task.status == DownloadStatus.complete || task.status == DownloadStatus.failed || task.status == DownloadStatus.paused;

    if (isIntermediateProgress && (now - lastEmit < 250) && !isTerminal) {
      _pendingThrottledTask = task;
      _throttleFlushTimer?.cancel();
      _throttleFlushTimer = Timer(const Duration(milliseconds: 250), () {
        if (_pendingThrottledTask != null && _pendingThrottledTask!.videoId == task.videoId) {
          _lastProgressEmitMs[task.videoId] = DateTime.now().millisecondsSinceEpoch;
          if (!_streamController.isClosed) _streamController.add(_pendingThrottledTask!);
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
    _schedulePersist();
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
  }

  Future<void> _executeTask(DownloadTask task) async {
    final videoId = task.videoId;
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
        _processQueue();
        return;
      }

      result.fold(
        (failure) {
          _updateTask(task.copyWith(
            status: DownloadStatus.failed,
            error: failure.message,
            speedKbps: null,
            etaSeconds: null,
          ));
        },
        (newId) {
          _cachedStorageStats = null; // Invalidate storage stats cache on completion
          _updateTask(task.copyWith(
            status: DownloadStatus.complete,
            progress: 1.0,
            error: null,
            speedKbps: null,
            etaSeconds: null,
          ));
        },
      );
    } catch (e) {
      _updateTask(task.copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
        speedKbps: null,
        etaSeconds: null,
      ));
    } finally {
      _activeVideoIds.remove(videoId);
      _processQueue();
    }
  }
}
