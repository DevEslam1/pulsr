// lib/data/repositories/download_repository_impl.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, StringExpressionOperators, Value;
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/channels.dart';
import '../../core/errors/failures.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/network/connectivity_guard.dart';
import '../../core/services/yt_download_service.dart';
import '../../core/utils/error_logger.dart';
import '../../core/utils/metadata_placeholders.dart';
import '../models/download_settings.dart';
import '../../domain/models/download_task.dart';
import '../../core/di/injection.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/download_repository_interface.dart';
import '../db/app_database.dart';
import '../services/library_maintenance_service.dart';

part 'download_repository_execution.dart';

@Singleton(as: IDownloadRepository)
class DownloadRepositoryImpl implements IDownloadRepository {
  static const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
  static const String _prefKey = 'pulsr_download_tasks_v2';
  static const String _autoPausedPrefKey = 'pulsr_download_auto_paused_v1';
  static final _random = Random();

  final YtDownloadService _ytDownloadService;
  final AppDatabase? _db;

  late final LibraryMaintenanceService _libraryMaintenance =
      LibraryMaintenanceService(
    database: () => _effectiveDb,
    channel: _downloadChannel,
  );

  AppDatabase? get _effectiveDb =>
      _db ?? (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);

  /// Effective concurrency, refreshed from [DownloadSettings] whenever a task
  /// is admitted. The user-facing setting used to be dead code (a hard-coded 3
  /// lived here AND in [YtDownloadService]); both now honour the preference.
  int _maxConcurrent = 3;

  final Map<String, DownloadTask> _tasks = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _activeVideoIds = {};
  final Set<String> _pausedVideoIds = {};
  final Set<String> _pausingVideoIds = {};

  /// Tasks paused automatically — by the Wi-Fi/offline policy or by a lost
  /// connection — not by the user. Only these are auto-resumed when the
  /// network path returns; a manual pause stays put.
  final Set<String> _autoPausedVideoIds = {};

  /// Suppresses slot refills while the policy watchdog pauses the whole queue;
  /// otherwise each pause immediately started the next not-yet-paused task,
  /// only for the same watchdog pass to cancel it again.
  bool _enforcingPolicy = false;
  final Map<String, Completer<void>> _activeCompleters = {};
  final StreamController<DownloadTask> _streamController =
      StreamController<DownloadTask>.broadcast();

  Timer? _saveDebounce;
  Future<void> _persistChain = Future<void>.value();
  bool _needsPersist = false;
  bool _persistDirty = false;
  String? _lastPersistedJson;
  final Map<String, int> _lastProgressEmitMs = {};
  final Map<String, int> _lastProgressPersistMs = {};
  final Map<String, double> _lastProgressPersistFraction = {};
  static const int _progressCheckpointMs = 5000;
  static const double _progressCheckpointMinDelta = 0.05;

  StorageStats? _cachedStorageStats;
  DateTime? _storageStatsCacheTime;
  static const Duration _storageStatsTtl = Duration(seconds: 5);
  Timer? _policyWatchdog;

  DownloadRepositoryImpl(
    this._ytDownloadService, [
    this._db,
  ]) {
    // FIX-I02: Move reconcileOnBoot() call OUT of the constructor to DownloadsCubit._init()
    // C-7/C-9: the native foreground service reports notification-driven
    // pause/resume/cancel and foreground degradation back on this channel.
    _downloadChannel.setMethodCallHandler(_handleNativeDownloadCall);
  }

  /// Handles the download foreground service's callbacks.
  ///
  /// The notification's Pause/Resume/Cancel buttons run in the service, which
  /// owns no transfer state — the Dart engine does. These callbacks are how the
  /// service's intent reaches it (C-7); degradation notices are logged because
  /// the ongoing notification already carries the user-visible signal (C-9).
  Future<void> _handleNativeDownloadCall(MethodCall call) async {
    final args = call.arguments;
    final videoId = args is Map ? args['videoId'] as String? : null;
    switch (call.method) {
      case 'onDownloadCancelled':
        if (videoId != null && videoId.isNotEmpty) {
          await deleteDownload(videoId);
        }
        break;
      case 'onDownloadPaused':
        if (videoId != null && videoId.isNotEmpty) {
          await pauseDownload(videoId);
        }
        break;
      case 'onDownloadResumed':
        if (videoId != null && videoId.isNotEmpty) {
          await resumeDownload(videoId);
        }
        break;
      case 'onDownloadServiceDegraded':
        final stage = args is Map ? args['stage'] : null;
        ErrorLogger.log(
            'Download foreground service degraded ($stage): the download '
            'continues without foreground protection',
            category: 'Download');
        break;
    }
  }

  /// Mirrors an in-app pause/resume state into the native notification (C-7).
  void _notifyNativePaused(String videoId, bool paused) {
    _downloadChannel.invokeMethod('setDownloadPaused', {
      'videoId': videoId,
      'paused': paused,
    }).catchError((_) => null);
  }

  @override
  Stream<DownloadTask> observeDownloads() => _streamController.stream;

  @override
  Future<List<DownloadTask>> getAllDownloads() async {
    return _tasks.values.toList();
  }

  @override
  Future<Either<AppFailure, QueueDownloadResult>> queueDownload(
      DownloadTask task) async {
    final videoId = task.videoId;
    // FIX-A15: Validate task.videoId with RegExp(r'^[A-Za-z0-9_-]{11}$') before proceeding
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      return const Left(DownloadFailure('Invalid video ID'));
    }

    await _reloadSettings();

    // Refuse before admitting the task: a Wi-Fi-only/offline-only download used
    // to be accepted, shown as queued, and only then fail mid-transfer.
    final policyBlock = await _ytDownloadService.downloadPolicyBlock();
    if (policyBlock != null) {
      return Left(policyBlock);
    }

    final existing = _tasks[videoId];
    // Dedupe: if already downloading, tagging or queued, return the existing
    // id instead of admitting a second writer. `tagging` was missing here, so
    // re-tapping a track while its bytes were being saved reset the row to
    // "queued" at 0% even though the same job was still finishing.
    if (existing != null && existing.status.isActive) {
      return Right(QueueDownloadResult(
        taskId: existing.id,
        admission: DownloadAdmission.alreadyActive,
      ));
    }
    if (existing != null && existing.status == DownloadStatus.complete) {
      // Check if file still exists on disk — off main thread via async check
      if (existing.filePath != null) {
        try {
          final exists = await File(existing.filePath!).exists();
          if (exists) {
            return Right(QueueDownloadResult(
              taskId: existing.id,
              admission: DownloadAdmission.alreadyComplete,
            ));
          }
        } catch (e) {
          ErrorLogger.addBreadcrumb(
            'Could not verify completed file, re-admitting: $videoId ($e)',
            category: 'Download',
          );
        }
      }
      // File missing → allow re-download (treat as failed)
    }

    // Storage preflight with typed error (ENOSPC)
    try {
      final freeBytes =
          await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
      if (freeBytes > 0 && freeBytes < 20 * 1024 * 1024) {
        return const Left(
            StorageFailure('Insufficient storage space for downloading audio'));
      }
    } catch (e) {
      ErrorLogger.addBreadcrumb(
        'Free-space preflight unavailable; admission continues ($e)',
        category: 'Download',
      );
    }

    // Mirror sanitize done in YtDownloadService; ensures / \ : * ? etc not in paths
    // A retry may arrive with only the identity (title/artist); keep the
    // metadata captured by the original admission so tagging, lyrics lookup
    // and the picker's quality survive a failed/restarted attempt.
    final queuedTask = task.copyWith(
      status: DownloadStatus.queued,
      progress: 0.0,
      clearError: true,
      clearSpeedKbps: true,
      clearEtaSeconds: true,
      artworkUrl: task.artworkUrl ?? existing?.artworkUrl,
      sourceSongId: task.sourceSongId ?? existing?.sourceSongId,
      album: task.album ?? existing?.album,
      durationMs: task.durationMs ?? existing?.durationMs,
      quality: task.quality ?? existing?.quality,
    );

    _pausedVideoIds.remove(videoId);
    _autoPausedVideoIds.remove(videoId);
    if (existing != null && existing.status == DownloadStatus.paused) {
      // Re-admitting a paused task is a resume: clear the service-side paused
      // marker and the notification's Resume action, otherwise the job stays
      // flagged paused in the service and the notification is never refreshed.
      _ytDownloadService.clearPaused(videoId);
      _notifyNativePaused(videoId, false);
    }
    _updateTask(queuedTask, allowInsert: true);

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
    return Right(QueueDownloadResult(
      taskId: task.id,
      admission: DownloadAdmission.queued,
    ));
  }

  @override
  Future<Either<AppFailure, Unit>> pauseDownload(String videoId) =>
      _pauseTask(videoId, byPolicy: false);

  /// Pauses [videoId]. [byPolicy] marks the pause as automatic (policy or
  /// connectivity), so [resumeAutoPaused] may undo it when the network
  /// returns.
  Future<Either<AppFailure, Unit>> _pauseTask(
    String videoId, {
    required bool byPolicy,
    String? error,
  }) async {
    final task = _tasks[videoId];
    if (task == null) {
      return const Left(DownloadFailure('Task not found'));
    }
    // Pausing a finished/failed row is a stale notification echo, not a state
    // change: overwriting `complete` with `paused` made a landed download
    // reappear as resumable (and a resume then fetched a second copy).
    if (task.status.isTerminal) {
      return const Right(unit);
    }
    if (byPolicy) {
      _autoPausedVideoIds.add(videoId);
    } else {
      // A deliberate pause outranks the watchdog: never auto-resume it.
      _autoPausedVideoIds.remove(videoId);
    }
    if (task.status == DownloadStatus.paused) {
      // Idempotent pause: keep the native Resume action and the service's
      // paused marker in sync even when the row was already paused (e.g. a
      // notification action arriving after a restart).
      _ytDownloadService.markPaused(videoId);
      _notifyNativePaused(videoId, true);
      return const Right(unit);
    }

    _pausedVideoIds.add(videoId);
    _queue.remove(videoId);
    // Keep the download foreground service (and its Resume action) alive (C-7).
    _ytDownloadService.markPaused(videoId);

    if (_activeVideoIds.contains(videoId)) {
      _pausingVideoIds.add(videoId);
      _ytDownloadService.cancel(videoId);
      // Await active completer briefly so that appended .part resume logic sees stable state
      final c = _activeCompleters[videoId];
      if (c != null) {
        try {
          await c.future.timeout(const Duration(seconds: 2));
        } catch (e) {
          ErrorLogger.addBreadcrumb(
            'Pause timed out waiting for the canceled job: $videoId ($e)',
            category: 'Download',
          );
        }
      }
      // Note: do NOT remove videoId from _activeVideoIds on 2s timeout;
      // keep it owned by _executeTask's finally block and keep _pausingVideoIds
      // marked so resumeDownload cannot spawn a duplicate writer on the same .part file.
    }

    // The job may have finished saving/tagging while the cancel was in flight
    // (pause lost the race); never downgrade a terminal row.
    final latest = _tasks[videoId];
    if (latest == null) {
      return const Right(unit);
    }
    if (latest.status.isTerminal) {
      _pausedVideoIds.remove(videoId);
      _ytDownloadService.clearPaused(videoId);
      return const Right(unit);
    }
    _updateTask(latest.copyWith(
      status: DownloadStatus.paused,
      error: error,
      clearError: error == null,
      clearSpeedKbps: true,
      clearEtaSeconds: true,
    ));
    _notifyNativePaused(videoId, true);
    // Pausing an active transfer frees a slot; without this the next queued
    // track waited for an unrelated completion before starting.
    _processQueue();
    return const Right(unit);
  }

  /// Parks a task that cannot make progress for an environmental reason
  /// (policy or connectivity), preserving its partial and its place in the
  /// auto-resume set. [error] is shown on the paused tile when the reason is
  /// not obvious from the paused state itself.
  void _parkAutoPaused(String videoId, DownloadTask current, {String? error}) {
    _autoPausedVideoIds.add(videoId);
    _pausedVideoIds.add(videoId);
    _ytDownloadService.markPaused(videoId);
    _notifyNativePaused(videoId, true);
    _updateTask(current.copyWith(
      status: DownloadStatus.paused,
      error: error,
      clearError: error == null,
      clearSpeedKbps: true,
      clearEtaSeconds: true,
    ));
  }

  @override
  Future<Either<AppFailure, Unit>> resumeDownload(String videoId) async {
    final task = _tasks[videoId];
    if (task == null) {
      return const Left(DownloadFailure('Task not found'));
    }
    // Prevent spawning a duplicate writer while pause cancellation is in flight.
    if (_pausingVideoIds.contains(videoId) || _activeVideoIds.contains(videoId)) {
      return const Right(unit);
    }
    // Resume is only meaningful for a paused task. A duplicate tap, a stale
    // notification action, or an admission racing the completion tail used to
    // re-queue a complete/active row and fetch a second copy.
    if (task.status != DownloadStatus.paused) {
      return const Right(unit);
    }

    await _reloadSettings();
    final policyBlock = await _ytDownloadService.downloadPolicyBlock();
    if (policyBlock != null) {
      return Left(policyBlock);
    }

    _pausedVideoIds.remove(videoId);
    _autoPausedVideoIds.remove(videoId);
    _ytDownloadService.clearPaused(videoId);
    _notifyNativePaused(videoId, false);
    final queuedTask = task.copyWith(
      status: DownloadStatus.queued,
      clearError: true,
      clearSpeedKbps: true,
      clearEtaSeconds: true,
    );
    _updateTask(queuedTask);

    if (!_activeVideoIds.contains(videoId) && !_queue.contains(videoId)) {
      _queue.add(videoId);
    }

    // Stream URL may be expired (~6h); YtDownloadService re-resolves on retry
    // inside _downloadAudioWithRetry, and raises the notification itself.
    _processQueue();
    return const Right(unit);
  }

  /// Resumes downloads that were paused automatically, once the policy allows
  /// transferring again. Called on network-path changes; user pauses are not
  /// touched. Returns how many tasks were re-queued.
  @override
  Future<int> resumeAutoPaused() async {
    if (_autoPausedVideoIds.isEmpty) return 0;
    await _reloadSettings();
    if (await _ytDownloadService.downloadPolicyBlock() != null) return 0;
    // The monitor fires for losses as well as gains; resuming while the
    // device is still offline would just fail (and re-park) every task.
    if (!await ConnectivityGuard.hasConnection()) return 0;

    var resumed = 0;
    for (final videoId in List<String>.of(_autoPausedVideoIds)) {
      final task = _tasks[videoId];
      if (task == null || task.status != DownloadStatus.paused) {
        _autoPausedVideoIds.remove(videoId);
        continue;
      }
      final result = await resumeDownload(videoId);
      if (result.isRight()) resumed++;
    }
    return resumed;
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
      clearError: true,
      clearSpeedKbps: true,
      clearEtaSeconds: true,
    )))
        .fold(
      (f) => Left(f),
      (_) => const Right(unit),
    );
  }

  @override
  Future<Either<AppFailure, Unit>> deleteDownload(String videoId) async {
    var task = _tasks[videoId];
    _pausedVideoIds.remove(videoId);
    _pausingVideoIds.remove(videoId);
    _autoPausedVideoIds.remove(videoId);
    _queue.remove(videoId);
    // A deleted task must not keep the foreground service alive through its
    // paused marker (C-7).
    _ytDownloadService.clearPaused(videoId);

    // Delete-while-downloading race: cancel → await job completion → then delete
    if (_activeVideoIds.contains(videoId)) {
      _ytDownloadService.cancel(videoId);
      final completer = _activeCompleters[videoId];
      if (completer != null && !completer.isCompleted) {
        try {
          await completer.future.timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      // Re-read: the job may have completed during the wait, and only the
      // completed row knows the local id/file path that must be removed.
      task = _tasks[videoId] ?? task;
      final filePath = task?.filePath;
      if (filePath != null) {
        try {
          final f = File(filePath);
          if (await f.exists()) {
            final len1 = await f.length();
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (await f.exists()) {
              final len2 = await f.length();
              if (len2 > len1) {
                // File is still being actively written, wait additional grace period
                await Future<void>.delayed(const Duration(seconds: 5));
              }
            }
          }
        } catch (_) {}
      }
      _activeVideoIds.remove(videoId);
      _activeCompleters.remove(videoId);
    }

    _tasks.remove(videoId);
    _ytDownloadService.releaseForeground(videoId);
    // A late progress tick or a queued flush must not keep the deleted task's
    // bookkeeping alive.
    _throttleFlushTimers.remove(videoId)?.cancel();
    _pendingThrottledTasks.remove(videoId);
    _lastProgressEmitMs.remove(videoId);
    _lastProgressPersistMs.remove(videoId);

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

    // Delete the library row and file this download produced. Leaving the row
    // behind was the "ghost track" bug: it stayed in the library until a full
    // scan, and `downloadAllDetailed` then refused to re-download an
    // `isDownloaded` row whose file was gone.
    await _libraryMaintenance.removeDownloadedArtifacts(
      localSongId: task?.localSongId,
      filePath: task?.filePath,
      contentUri: task?.contentUri ??
          _ytDownloadService.getDownloadedContentUri(videoId),
    );
    _ytDownloadService.forgetDownloadedPath(videoId);

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
      int freeBytes = 0;
      int? realTotalBytes;
      try {
        freeBytes =
            await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
      } catch (e, st) {
        ErrorLogger.log('Could not read free disk space via platform channel',
            error: e, stackTrace: st, category: 'Download');
      }
      try {
        realTotalBytes =
            await _downloadChannel.invokeMethod<int>('getTotalDiskSpace');
      } catch (e, st) {
        ErrorLogger.log('Could not read total disk space via platform channel',
            error: e, stackTrace: st, category: 'Download');
      }

      int totalUsedBytes = 0;
      int completedCount = 0;
      try {
        final completedTasks = _tasks.values
            .where((t) => t.status == DownloadStatus.complete)
            .toList();
        final db = _effectiveDb;
        var mutated = false;

        final sizes = await Future.wait(completedTasks.map((t) async {
          // 1. Direct fileSize if present and non-zero. Trust the recorded size:
          // completion and boot reconciliation both author it, and re-stat'ing
          // every completed file here was a full-library disk walk per refresh.
          if (t.fileSize != null && t.fileSize! > 0) {
            return t.fileSize!;
          }

          // 2. Direct filePath if present
          if (t.filePath != null && t.filePath!.isNotEmpty) {
            try {
              final f = File(t.filePath!);
              if (await f.exists()) {
                final len = await f.length();
                final current = _tasks[t.videoId];
                if (current != null &&
                    current.status == DownloadStatus.complete &&
                    current.fileSize != len) {
                  _tasks[t.videoId] = current.copyWith(fileSize: len);
                  mutated = true;
                }
                return len;
              }
            } catch (e, st) {
              ErrorLogger.log('Failed checking file length for download',
                  error: e, stackTrace: st, category: 'Download');
            }
          }

          // 3. Fallback to localSongId (or remoteId) query in database
          if (db != null) {
            try {
              SongsTableData? song;
              if (t.localSongId != null) {
                song = await (db.select(db.songsTable)
                      ..where((s) => s.id.equals(t.localSongId!)))
                    .getSingleOrNull();
              }
              song ??= await (db.select(db.songsTable)
                    ..where((s) =>
                        s.remoteId.equals(t.videoId) &
                        (s.source.equals(SongSource.local) |
                            s.isDownloaded.equals(true)) &
                        s.isMissing.equals(false))
                    ..limit(1))
                  .getSingleOrNull();
              if (song != null) {
                if (song.fileSize != null && song.fileSize! > 0) {
                  final current = _tasks[t.videoId];
                  if (current != null &&
                      current.status == DownloadStatus.complete) {
                    _tasks[t.videoId] = current.copyWith(
                      localSongId: song.id,
                      filePath: song.path,
                      fileSize: song.fileSize,
                    );
                    mutated = true;
                  }
                  return song.fileSize!;
                }
                final f = File(song.path);
                if (await f.exists()) {
                  final len = await f.length();
                  final current = _tasks[t.videoId];
                  if (current != null &&
                      current.status == DownloadStatus.complete) {
                    _tasks[t.videoId] = current.copyWith(
                      localSongId: song.id,
                      filePath: song.path,
                      fileSize: len,
                    );
                    mutated = true;
                  }
                  return len;
                }
              }
            } catch (e, st) {
              ErrorLogger.log('Failed querying downloaded song row',
                  error: e, stackTrace: st, category: 'Download');
            }
          }

          return 0;
        }));

        if (mutated) {
          _schedulePersist();
        }

        totalUsedBytes = sizes.fold(0, (a, b) => a + b);
        completedCount = sizes.where((s) => s > 0).length;
        if (completedCount == 0 && completedTasks.isNotEmpty) {
          completedCount = completedTasks.length;
        }
      } catch (e, st) {
        ErrorLogger.log('Failed aggregating completed download sizes',
            error: e, stackTrace: st, category: 'Download');
      }

      final total = (realTotalBytes != null && realTotalBytes > 0)
          ? realTotalBytes
          : 0;
      final stats = StorageStats(
        usedBytes: totalUsedBytes,
        freeBytes: freeBytes,
        totalBytes: total > 0 ? total : 1,
        downloadedSongsCount: completedCount,
      );

      _cachedStorageStats = stats;
      _storageStatsCacheTime = now;
      return Right(stats);
    } catch (e) {
      return Left(StorageFailure('Failed to calculate storage stats: $e'));
    }
  }

  /// Loads the persisted download preferences and applies the concurrency
  /// limit to both this repository's scheduler and the underlying
  /// [YtDownloadService], which keeps its own queue and would otherwise cap the
  /// effective parallel transfers at its own hard-coded 3.
  Future<void> _reloadSettings() async {
    try {
      final settings = await DownloadSettings.load();
      _maxConcurrent = settings.maxConcurrent.clamp(1, 5);
      _ytDownloadService.setMaxConcurrentDownloads(_maxConcurrent);
    } catch (e, st) {
      ErrorLogger.log('DownloadRepository settings reload failed',
          error: e, stackTrace: st, category: 'Download');
    }
  }

  @override
  Future<void> reconcileOnBoot() async {
    await _reloadSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAutoPaused = prefs.getStringList(_autoPausedPrefKey);
      if (savedAutoPaused != null) {
        _autoPausedVideoIds.addAll(savedAutoPaused);
      }
      final rawJson = prefs.getString(_prefKey);
      final interruptedSaves = <String>{};
      var bootMutated = false;
      if (rawJson != null && rawJson.isNotEmpty) {
        final list = jsonDecode(rawJson) as List<dynamic>;
        for (final item in list) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.tagging) {
            // Restore interrupted downloads as paused on startup (process death reconciliation)
            if (task.status == DownloadStatus.tagging) {
              // The file may already be in the library; re-downloading it
              // would produce a duplicate MediaStore entry.
              interruptedSaves.add(task.videoId);
            }
            _pausedVideoIds.add(task.videoId);
            _autoPausedVideoIds.add(task.videoId);
            _tasks[task.videoId] = task.copyWith(
              status: DownloadStatus.paused,
              clearSpeedKbps: true,
              clearEtaSeconds: true,
            );
            bootMutated = true;
          } else {
            if (task.status == DownloadStatus.paused) {
              _pausedVideoIds.add(task.videoId);
            }
            _tasks[task.videoId] = task;
          }
        }
      }
      // FIX-A06: Reconcile completed tasks asynchronously in batched parallel
      // chunks (no main-thread existsSync/lengthSync blocking).
      await _reconcileCompletedFiles();
      await _reconcileInterruptedSaves(interruptedSaves);
      _pausedVideoIds.removeWhere(
          (id) => _tasks[id]?.status != DownloadStatus.paused);
      _autoPausedVideoIds.removeWhere(
          (id) => _tasks[id]?.status != DownloadStatus.paused);
      if (bootMutated) {
        _schedulePersist(immediateOnTerminal: true);
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
    } catch (e) {
      ErrorLogger.log('DownloadRepository reconcileOnBoot failed', error: e);
    }
  }

  /// FIX-A06: Reconciles completed tasks against disk, marking deleted files as failed.
  Future<void> _reconcileCompletedFiles() async {
    final completedTasks = _tasks.values
        .where((t) => t.status == DownloadStatus.complete)
        .toList(growable: false);
    if (completedTasks.isEmpty) return;

    final db = _effectiveDb;
    final prefetchedSongs = <int, SongsTableData>{};
    if (db != null) {
      // Fetch the library row for every completed task, not only for missing
      // file metadata: a download completed before the metadata-repair fix may
      // still carry "Unknown Artist" on its tile, and the row is the truth.
      final songIds = completedTasks
          .where((t) => t.localSongId != null)
          .map((t) => t.localSongId!)
          .toSet()
          .toList(growable: false);
      const dbChunkSize = 400;
      for (var i = 0; i < songIds.length; i += dbChunkSize) {
        final chunk =
            songIds.sublist(i, (i + dbChunkSize).clamp(0, songIds.length));
        try {
          final rows = await (db.select(db.songsTable)
                ..where((s) => s.id.isIn(chunk)))
              .get();
          for (final row in rows) {
            prefetchedSongs[row.id] = row;
          }
        } catch (e, st) {
          ErrorLogger.log('Failed batch-fetching boot download metadata',
              error: e, stackTrace: st, category: 'Download');
        }
      }
    }

    final pendingDbUpdates = <int, SongsTableCompanion>{};
    const ioConcurrency = 32;
    for (var i = 0; i < completedTasks.length; i += ioConcurrency) {
      final batch = completedTasks.sublist(
          i, (i + ioConcurrency).clamp(0, completedTasks.length));
      await Future.wait(
        batch.map((task) => _reconcileCompletedTask(
              task,
              prefetchedSongs: prefetchedSongs,
              pendingDbUpdates: pendingDbUpdates,
            )),
      );
    }

    if (pendingDbUpdates.isNotEmpty && db != null) {
      try {
        await db.transaction(() async {
          await db.batch((b) {
            for (final entry in pendingDbUpdates.entries) {
              b.update(
                db.songsTable,
                entry.value,
                where: (s) => s.id.equals(entry.key),
              );
            }
          });
        });
      } catch (e, st) {
        ErrorLogger.log('Failed batch updating reconciled song metadata',
            error: e, stackTrace: st, category: 'Download');
      }
    }
  }

  /// A process kill between `saveToMusic` and the completion write leaves a
  /// task persisted as `tagging` while its file already sits in the library.
  /// Resuming it would download the same audio again (and MediaStore would
  /// suffix a second copy), so adopt the existing local row instead.
  Future<void> _reconcileInterruptedSaves(Set<String> videoIds) async {
    if (videoIds.isEmpty) return;
    final db = _effectiveDb;
    if (db == null) return;
    for (final videoId in videoIds) {
      final task = _tasks[videoId];
      if (task == null || task.status != DownloadStatus.paused) continue;
      try {
        final row = await (db.select(db.songsTable)
              ..where((s) =>
                  s.remoteId.equals(videoId) &
                  s.source.equals(SongSource.local) &
                  s.isMissing.equals(false))
              ..limit(1))
            .getSingleOrNull();
        if (row == null || row.path.isEmpty) continue;
        final file = File(row.path);
        if (!await file.exists()) continue;
        var size = row.fileSize;
        if (size == null || size <= 0) size = await file.length();
        final ext = p.extension(row.path).replaceFirst('.', '').toLowerCase();
        _pausedVideoIds.remove(videoId);
        _autoPausedVideoIds.remove(videoId);
        _updateTask(task.copyWith(
          status: DownloadStatus.complete,
          progress: 1.0,
          clearError: true,
          clearSpeedKbps: true,
          clearEtaSeconds: true,
          localSongId: row.id,
          filePath: row.path,
          fileSize: size,
          format: ext.isEmpty ? null : ext,
          bitrate: row.bitrateKbps,
        ));
        _cachedStorageStats = null;
        ErrorLogger.addBreadcrumb(
            'Recovered interrupted download from the library: $videoId',
            category: 'Download');
      } catch (e, st) {
        ErrorLogger.log('Failed reconciling interrupted download save',
            error: e, stackTrace: st, category: 'Download');
      }
    }
  }

  /// Reconciles a single completed [task] against disk, marking a deleted file
  /// as failed. Used right after a completion so one track does not trigger a
  /// stat of the entire download history.
  Future<void> _reconcileCompletedTask(
    DownloadTask task, {
    Map<int, SongsTableData>? prefetchedSongs,
    Map<int, SongsTableCompanion>? pendingDbUpdates,
  }) async {
    final db = _effectiveDb;
    try {
      var filePath = task.filePath;
      var fileSize = task.fileSize;

      SongsTableData? song;
      if (task.localSongId != null) {
        final songId = task.localSongId!;
        song = prefetchedSongs?[songId];
        if (song == null && prefetchedSongs == null && db != null) {
          song = await (db.select(db.songsTable)
                ..where((s) => s.id.equals(songId)))
              .getSingleOrNull();
        }
        if (song != null) {
          filePath ??= song.path;
          fileSize ??= song.fileSize;
        }
      }

      if (song == null && db != null) {
        song = await (db.select(db.songsTable)
              ..where((s) =>
                  s.remoteId.equals(task.videoId) &
                  (s.source.equals(SongSource.local) |
                      s.isDownloaded.equals(true)) &
                  s.isMissing.equals(false))
              ..limit(1))
            .getSingleOrNull();
        if (song == null && filePath != null && filePath.isNotEmpty) {
          song = await (db.select(db.songsTable)
                ..where((s) => s.path.lower().equals(filePath!.toLowerCase()))
                ..limit(1))
              .getSingleOrNull();
        }
        if (song != null) {
          filePath ??= song.path;
          fileSize ??= song.fileSize;
        }
      }

      var updated = song != null && task.localSongId != song.id
          ? task.copyWith(localSongId: song.id)
          : task;
      var changed = updated.localSongId != task.localSongId;

      // MediaStore derives TITLE from the file name when tags are missing
      // ("Artist - Title"), which still passes the placeholder check.
      final rowTitleLooksLikeFileName = song != null &&
          MetadataPlaceholders.isUnknownArtist(song.artist) &&
          song.title.toLowerCase().contains(task.title.toLowerCase()) &&
          song.title != task.title;

      // The library row may have been repaired (stream metadata, tagger, or a
      // previous scanner pass) after this download was persisted. Refresh the
      // tile's metadata without touching real task values with placeholders.
      if (song != null) {
        if (MetadataPlaceholders.isRealTitle(song.title) &&
            !rowTitleLooksLikeFileName &&
            song.title != updated.title) {
          updated = updated.copyWith(title: song.title);
          changed = true;
        }
        if (MetadataPlaceholders.isRealArtist(song.artist) &&
            song.artist != updated.artist) {
          updated = updated.copyWith(artist: song.artist);
          changed = true;
        }
        if (MetadataPlaceholders.isRealAlbum(song.album) &&
            song.album != updated.album) {
          updated = updated.copyWith(album: song.album);
          changed = true;
        }
        if (song.durationMs > 0 && song.durationMs != updated.durationMs) {
          updated = updated.copyWith(durationMs: song.durationMs);
          changed = true;
        }
        if (filePath == null && song.path.isNotEmpty) {
          filePath = song.path;
        }
        if (fileSize == null && song.fileSize != null) {
          fileSize = song.fileSize;
        }

        // Legacy repair: an earlier scanner pass could have replaced the
        // library row with MediaStore placeholders while the persisted task
        // still remembers the real online metadata. Restore it.
        final repairTitle = (MetadataPlaceholders.isUnknownTitle(song.title) ||
                    rowTitleLooksLikeFileName) &&
                MetadataPlaceholders.isRealTitle(task.title)
            ? task.title
            : song.title;
        final repairArtist =
            MetadataPlaceholders.isUnknownArtist(song.artist) &&
                    MetadataPlaceholders.isRealArtist(task.artist)
                ? task.artist
                : song.artist;
        final repairAlbum = MetadataPlaceholders.isUnknownAlbum(song.album) &&
                MetadataPlaceholders.isRealAlbum(task.album)
            ? task.album!
            : song.album;
        final database = db;
        final songRowId = song.id;
        if (database != null &&
            (repairTitle != song.title ||
                repairArtist != song.artist ||
                repairAlbum != song.album)) {
          final companion = SongsTableCompanion(
            title: Value(repairTitle),
            artist: Value(repairArtist),
            album: Value(repairAlbum),
          );
          if (pendingDbUpdates != null) {
            pendingDbUpdates[songRowId] = companion;
          } else {
            await (database.update(database.songsTable)
                  ..where((s) => s.id.equals(songRowId)))
                .write(companion);
          }
        }
      }

      if (filePath != null) {
        final f = File(filePath);
        if (!await f.exists()) {
          _updateTask(updated.copyWith(
            filePath: filePath,
            fileSize: fileSize,
            status: DownloadStatus.failed,
            error: 'File deleted',
          ));
          return;
        }
        if (fileSize == null || fileSize <= 0) {
          fileSize = await f.length();
        }
      }

      if (updated.filePath != filePath || updated.fileSize != fileSize) {
        updated = updated.copyWith(filePath: filePath, fileSize: fileSize);
        changed = true;
      }
      if (changed) _updateTask(updated);
    } catch (e, st) {
      ErrorLogger.log('Failed reconciling completed download file',
          error: e, stackTrace: st, category: 'Download');
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

  void _updateTask(DownloadTask task, {bool allowInsert = false}) {
    if (_streamController.isClosed) return;
    // A task removed by deleteDownload must never be resurrected by a late
    // progress/completion/failure update. Only admission may insert a new key.
    if (!allowInsert && !_tasks.containsKey(task.videoId)) return;
    final previous = _tasks[task.videoId];
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
    // saving/indexing is the crash-sensitive window: the file may already be
    // in MediaStore. Persist it immediately instead of after the 800 ms
    // debounce so boot recovery knows to adopt/reconcile it.
    final isSaving = task.status == DownloadStatus.tagging;
    final meaningfulStateChange = previous == null ||
        previous.status != task.status ||
        previous.filePath != task.filePath ||
        previous.fileSize != task.fileSize ||
        previous.error != task.error ||
        previous.title != task.title ||
        previous.artist != task.artist ||
        previous.localSongId != task.localSongId ||
        previous.contentUri != task.contentUri;
    if (meaningfulStateChange) {
      _persistDirty = true;
    }

    if (isIntermediateProgress &&
        (now - lastEmit < _throttleMs) &&
        !isTerminal) {
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
      // Progress is not persisted on every tick, but a crash mid-download must
      // not roll the row back to 0%. A 5s checkpoint bounds both losses.
      _checkpointProgress(videoId, now, task.progress);
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
      _lastProgressPersistMs.remove(videoId);
      _lastProgressPersistFraction.remove(videoId);
    }
    if (isIntermediateProgress) {
      _checkpointProgress(videoId, now, task.progress);
    } else if (meaningfulStateChange) {
      _schedulePersist(immediateOnTerminal: isTerminal || isSaving);
    }
  }

  void _checkpointProgress(String videoId, int now, double progress) {
    final last = _lastProgressPersistMs[videoId] ?? 0;
    if (now - last < _progressCheckpointMs) return;
    final lastFraction = _lastProgressPersistFraction[videoId] ?? -1.0;
    if ((progress - lastFraction).abs() < _progressCheckpointMinDelta) return;
    _lastProgressPersistMs[videoId] = now;
    _lastProgressPersistFraction[videoId] = progress;
    _persistDirty = true;
    _schedulePersist();
  }

  Future<void> dispose() async {
    _downloadChannel.setMethodCallHandler(null);
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _policyWatchdog?.cancel();
    _policyWatchdog = null;
    // Flush pending state so terminal states are never lost
    // on a fast close/kill after the debounce window opened.
    if (_persistDirty || _needsPersist) {
      await _persistNow();
    }
    _pausingVideoIds.clear();
    // FIX-A07: Cancel all _throttleFlushTimers entries BEFORE closing _streamController
    for (final timer in _throttleFlushTimers.values) {
      timer.cancel();
    }
    _throttleFlushTimers.clear();
    _pendingThrottledTasks.clear();
    _lastProgressEmitMs.clear();
    _lastProgressPersistMs.clear();
    _lastProgressPersistFraction.clear();
    // FIX-A07: Guard _streamController.close() with if (!_streamController.isClosed)
    if (!_streamController.isClosed) await _streamController.close();
  }

  void _schedulePersist({bool immediateOnTerminal = false}) {
    if (immediateOnTerminal) {
      _saveDebounce?.cancel();
      _saveDebounce = null;
      unawaited(_persistNow());
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () async {
      await _persistNow();
    });
  }

  /// Preferences are not a database: an unbounded history of completed tasks
  /// was re-encoded on every terminal event and re-decoded on every boot.
  ///
  /// Terminal rows are pruned by age, not by "newest N": dropping the newest-N
  /// tail used to discard metadata for files that are still on disk and made
  /// those downloads look lost after a restart. Non-terminal rows are always
  /// kept (they are the resume/recovery state).
  static const int _maxPersistedTasks = 2000;

  Future<void> _persistNow() {
    _needsPersist = true;
    _persistChain = _persistChain.then((_) async {
      if (!_needsPersist) return;
      _needsPersist = false;
      await _persistNowInternal();
    }).catchError((e, st) {
      _needsPersist = false;
      ErrorLogger.log('Failed persisting download queue',
          error: e, stackTrace: st, category: 'Download');
    });
    return _persistChain;
  }

  Future<void> _persistNowInternal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final live = <DownloadTask>[];
      final terminal = <DownloadTask>[];
      for (final task in _tasks.values) {
        // Keep terminal rows for files the user may still manage; the hard
        // 2000-row cap bounds prefs size. Age-based pruning made downloads
        // older than 30 days vanish while their files stayed on disk.
        if (task.status.isTerminal) {
          terminal.add(task);
        } else {
          live.add(task);
        }
      }
      terminal.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final room = max(0, _maxPersistedTasks - live.length);
      final tasks = [
        ...live,
        ...terminal.take(room),
      ];
      final rawList = tasks.map((t) => t.toJson()).toList();
      final encoded = jsonEncode(rawList);
      if (encoded != _lastPersistedJson) {
        if (!await prefs.setString(_prefKey, encoded)) {
          ErrorLogger.log('Download queue persistence was rejected by prefs',
              category: 'Download');
        } else {
          _lastPersistedJson = encoded;
        }
      }
      _persistDirty = false;
      final validAutoPaused = _autoPausedVideoIds
          .where((id) => _tasks[id]?.status == DownloadStatus.paused)
          .toList(growable: false);
      await prefs.setStringList(_autoPausedPrefKey, validAutoPaused);
    } catch (e, st) {
      // Swallowing this used to make a failed write indistinguishable from a
      // successful one, so the next boot silently lost every active task.
      ErrorLogger.log('Failed persisting download queue',
          error: e, stackTrace: st, category: 'Download');
    }
  }

  void _processQueue() {
    if (_enforcingPolicy) return;
    _ensurePolicyWatchdog();
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
    //
    // `keepAlive` is what bridges two sequential jobs: the native notification
    // removes a job at 100% and used to tear itself down before this scheduler
    // started the next transfer, and an FGS started from the background can be
    // refused outright on Android 12+.
    _ytDownloadService.setKeepForegroundAlive(
        _activeVideoIds.isNotEmpty || _queue.isNotEmpty);
    _ensurePolicyWatchdog();
  }

  /// Re-checks Wi-Fi/offline-only policy while transfers are running. The
  /// admission-time check alone let a job keep downloading after the device
  /// left Wi-Fi despite the user's data-saving preference.
  void _ensurePolicyWatchdog() {
    final busy = _activeVideoIds.isNotEmpty || _queue.isNotEmpty;
    if (!busy) {
      _policyWatchdog?.cancel();
      _policyWatchdog = null;
      return;
    }
    _policyWatchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_enforcePolicy());
    });
  }

  Future<void> _enforcePolicy() async {
    AppFailure? block;
    try {
      // Picking up a concurrency change here also lets raising the limit take
      // effect during a long batch without another admission event.
      await _reloadSettings();
      block = await _ytDownloadService.downloadPolicyBlock();
    } catch (e, st) {
      ErrorLogger.log('Download policy watch failed',
          error: e, stackTrace: st, category: 'Download');
      return;
    }
    if (block == null) {
      // New slots may have opened up (higher concurrency); fill them.
      _processQueue();
      return;
    }
    // Pause queued work too. The watchdog used to pause only active transfers,
    // so every queued job started in turn and failed against the same policy
    // instead of waiting for Wi-Fi. These pauses are tagged so a network-path
    // change can resume them automatically.
    final pending = {
      ..._activeVideoIds,
      ..._queue,
    }.toList(growable: false);
    _enforcingPolicy = true;
    try {
      for (final videoId in pending) {
        await _pauseTask(videoId, byPolicy: true, error: block.message);
      }
    } finally {
      _enforcingPolicy = false;
      _processQueue();
    }
  }

  /// Failures worth an automatic retry (network blip, rate limit, bot
  /// challenge, timeout, YouTube 5xx). Permanent ones (video gone, geo block,
  /// auth required) fail immediately so a dead track doesn't hold a slot.
  static bool _isTransientFailure(AppFailure failure) {
    final cause = failure.error;
    final info = YtmErrorClassifier.classify(cause ?? failure.message);
    switch (info.recoveryAction) {
      case YtmRecoveryAction.retryWithBackoff:
      case YtmRecoveryAction.refreshPoTokenAndRetry:
      case YtmRecoveryAction.invalidatePoTokenAndRetry:
      case YtmRecoveryAction.rotateIdentity:
      case YtmRecoveryAction.rotatePath:
        return true;
      case YtmRecoveryAction.none:
      case YtmRecoveryAction.showLoginPrompt:
      case YtmRecoveryAction.skipToNextTrack:
      case YtmRecoveryAction.limitedMode:
        return false;
    }
  }
}
