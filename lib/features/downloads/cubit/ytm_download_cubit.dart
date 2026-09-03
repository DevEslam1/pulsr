// lib/features/downloads/cubit/ytm_download_cubit.dart
// DL-17: Single source of truth — thin viewer over shared repository stream.
// DL-18: Guard all async continuations with if (isClosed) return.

import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/downloads/yt_download_service.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/repositories/download_repository_interface.dart';
import '../../../domain/usecases/download_lifecycle_usecases.dart';
import '../../../domain/usecases/download_queue_usecases.dart';
import '../../player/cubit/player_cubit.dart';

enum YtDownloadStatus { idle, queued, running, done, failed, canceled }

class YtDownloadItem {
  final YtDownloadStatus status;
  final double? progress;
  final double? speedKbps;
  final int? etaSeconds;
  final String? error;

  const YtDownloadItem({
    this.status = YtDownloadStatus.idle,
    this.progress,
    this.speedKbps,
    this.etaSeconds,
    this.error,
  });

  YtDownloadItem copyWith({
    YtDownloadStatus? status,
    double? progress,
    double? speedKbps,
    int? etaSeconds,
    String? error,
  }) {
    return YtDownloadItem(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      speedKbps: speedKbps ?? this.speedKbps,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {'status': status.name, 'error': error};

  factory YtDownloadItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    return YtDownloadItem(
      status: YtDownloadStatus.values.firstWhere(
        (e) => e.name == statusName,
        orElse: () => YtDownloadStatus.idle,
      ),
      error: json['error'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YtDownloadItem &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          progress == other.progress &&
          speedKbps == other.speedKbps &&
          etaSeconds == other.etaSeconds &&
          error == other.error;

  @override
  int get hashCode =>
      Object.hash(status, progress, speedKbps, etaSeconds, error);
}

class BatchResult {
  final int totalCount;
  final int queuedCount;
  final int failureCount;

  const BatchResult({
    required this.totalCount,
    required this.queuedCount,
    required this.failureCount,
  });

  bool get hasFailures => failureCount > 0;
  bool get allSucceeded => failureCount == 0;
}

class YtmDownloadState {
  final Map<String, YtDownloadItem> items;

  const YtmDownloadState({this.items = const {}});

  YtDownloadItem itemFor(String videoId) =>
      items[videoId] ?? const YtDownloadItem();

  YtmDownloadState copyWith({Map<String, YtDownloadItem>? items}) {
    return YtmDownloadState(
      items: items ?? this.items,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YtmDownloadState &&
          runtimeType == other.runtimeType &&
          _mapsEqual(items, other.items);

  @override
  int get hashCode => Object.hashAll(
      items.entries.map((e) => Object.hash(e.key, e.value)));

  static bool _mapsEqual(
      Map<String, YtDownloadItem> a, Map<String, YtDownloadItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

@singleton
class YtmDownloadCubit extends PulsrCubit<YtmDownloadState> {
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;
  final IDownloadRepository? _repository;
  final QueueDownloadUseCase? _queueUseCase;
  final PauseDownloadUseCase? _pauseUseCase;

  YtmDownloadCubit(
    this._service,
    this._playerCubit, [
    this._repository,
    this._queueUseCase,
    this._pauseUseCase,
  ]) : super(const YtmDownloadState()) {
    _initSharedStream();
  }

  QueueDownloadUseCase? get _queueUseCaseOrRegistered {
    if (_queueUseCase != null) return _queueUseCase;
    if (getIt.isRegistered<QueueDownloadUseCase>()) {
      return getIt<QueueDownloadUseCase>();
    }
    return null;
  }

  PauseDownloadUseCase? get _pauseUseCaseOrRegistered {
    if (_pauseUseCase != null) return _pauseUseCase;
    if (getIt.isRegistered<PauseDownloadUseCase>()) {
      return getIt<PauseDownloadUseCase>();
    }
    return null;
  }

  void _initSharedStream() {
    final repo =
        _repository ??
        (getIt.isRegistered<IDownloadRepository>()
            ? getIt<IDownloadRepository>()
            : null);
    if (repo != null) {
      repo
          .getAllDownloads()
          .then((tasks) {
            if (isClosed) return;
            final initialMap = <String, YtDownloadItem>{};
            for (final t in tasks) {
              initialMap[t.videoId] = _mapTaskToItem(t);
            }
            if (initialMap.isNotEmpty && !isClosed) {
              safeEmit(
                YtmDownloadState(
                  items: Map.unmodifiable({...state.items, ...initialMap}),
                ),
              );
            }
          })
          .catchError((Object e, StackTrace st) {
            ErrorLogger.log(
              'YtmDownloadCubit getAllDownloads failed',
              error: e,
              stackTrace: st,
              category: 'YtmDownloadCubit',
            );
          });

      autoSub(
        repo.observeDownloads().throttleTime(
          const Duration(milliseconds: 200),
          trailing: true,
        ),
        (task) {
          final item = _mapTaskToItem(task);
          _set(task.videoId, item);
        },
      );
    }
  }

  YtDownloadItem _mapTaskToItem(DownloadTask task) {
    return switch (task.status) {
      DownloadStatus.queued => YtDownloadItem(
        status: YtDownloadStatus.queued,
        progress: task.progress,
      ),
      DownloadStatus.downloading || DownloadStatus.embedding => YtDownloadItem(
        status: YtDownloadStatus.running,
        progress: task.progress,
        speedKbps: task.speedKbps,
        etaSeconds: task.etaSeconds,
      ),
      DownloadStatus.complete => const YtDownloadItem(
        status: YtDownloadStatus.done,
        progress: 1.0,
      ),
      DownloadStatus.failed => YtDownloadItem(
        status: YtDownloadStatus.failed,
        error: task.error,
      ),
      DownloadStatus.paused || DownloadStatus.interrupted =>
        const YtDownloadItem(status: YtDownloadStatus.idle),
      DownloadStatus.canceled =>
        const YtDownloadItem(status: YtDownloadStatus.canceled),
    };
  }

  /// Cancels an active or queued download.
  ///
  /// The service cancellation token fires immediately; when the shared
  /// repository also tracks this task (queue went through
  /// [QueueDownloadUseCase]) it is paused through [PauseDownloadUseCase] so
  /// the downloads hub stops with it. Cubits never touch repositories
  /// directly — Clean Architecture boundary.
  void cancelDownload(String videoId) {
    _service.cancel(videoId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
    final useCase = _pauseUseCaseOrRegistered;
    if (useCase != null) {
      unawaited(useCase(videoId).then((result) {
        result.fold(
          (f) => ErrorLogger.log(
            'cancelDownload($videoId) pause failed: ${f.message}',
            category: 'YtmDownloadCubit',
          ),
          (_) {},
        );
      }).catchError((Object e, StackTrace st) {
        ErrorLogger.log('cancelDownload($videoId) failed',
            error: e, stackTrace: st, category: 'YtmDownloadCubit');
      }));
    }
  }

  /// Starts a download for [song].
  ///
  /// When the app is fully wired (DI configured), the intent goes through
  /// [QueueDownloadUseCase] so the shared repository owns the task — same
  /// single source of truth as the downloads hub. Progress and completion
  /// then arrive exclusively via the repository stream subscription.
  ///
  /// Falls back to driving [YtDownloadService] directly only when the use
  /// case is not registered (bare-constructed cubits in unit tests).
  Future<void> download(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    final current = state.itemFor(videoId);
    if ([
      YtDownloadStatus.running,
      YtDownloadStatus.queued,
      YtDownloadStatus.done,
    ].contains(current.status)) {
      return;
    }

    // Fresh user intent: a previous failed/canceled attempt must not block a
    // new download. This reset deliberately bypasses the terminal guard in
    // _set (which only protects the observation path from STALE downgrades).
    _forceSet(
      videoId,
      const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0),
    );

    // Preferred path: queue through the shared repository (use case), so the
    // task is tracked, throttled and rate-limited in one place.
    final queueUseCase = _queueUseCaseOrRegistered;
    if (queueUseCase != null) {
      final useCase = queueUseCase;
      try {
        final result = await useCase(
          DownloadTask(
            id: 'yt_$videoId',
            videoId: videoId,
            title: song.title,
            artist: song.artist,
            artworkUrl: song.remoteArtworkUrl ?? song.artworkUri,
            createdAt: DateTime.now(),
          ),
        );
        if (isClosed) return;
        result.fold(
          (failure) {
            if (failure is AlreadyQueuedFailure) {
              // Already tracked by the repository — the stream will surface
              // its real state; not a user-facing error.
              return;
            }
            _set(
              videoId,
              YtDownloadItem(status: YtDownloadStatus.failed, error: failure.message),
            );
          },
          (_) {
            // Restore the pre-use-case behavior: when a search-initiated
            // download completes, the player queue's stale search row swaps
            // to the reconciled positive-id library row. The reconciled id
            // travels on DownloadTask.librarySongId (recorded by the
            // repository in the same completion commit) — no direct service
            // or music-repository coupling from this cubit.
            _watchForDownloadedSong(videoId, song.id);
          },
        );
      } catch (e, st) {
        ErrorLogger.log('queueDownload via use case failed for $videoId',
            error: e, stackTrace: st, category: 'YtmDownloadCubit');
        if (!isClosed) {
          _set(
            videoId,
            const YtDownloadItem(
                status: YtDownloadStatus.failed, error: 'Download failed'),
          );
        }
      }
      return;
    }

    final result = await _service.download(
      song,
      onProgress: (p) {
        if (isClosed) return;
        if (p.stage == YtDownloadStage.canceled) {
          _set(
            videoId,
            const YtDownloadItem(status: YtDownloadStatus.canceled),
          );
          return;
        }
        _set(
          videoId,
          YtDownloadItem(
            status:
                p.stage == YtDownloadStage.queued
                    ? YtDownloadStatus.queued
                    : YtDownloadStatus.running,
            progress:
                p.stage == YtDownloadStage.downloading ? p.fraction : null,
            speedKbps:
                p.stage == YtDownloadStage.downloading ? p.speedKbps : null,
            etaSeconds:
                p.stage == YtDownloadStage.downloading ? p.etaSeconds : null,
          ),
        );
      },
    );

    if (isClosed) return;
    if (result.isLeft()) {
      final message =
          result.getLeft().toNullable()?.message ?? 'Download failed';
      _set(
        videoId,
        YtDownloadItem(status: YtDownloadStatus.failed, error: message),
      );
      return;
    }

    final newId = result.getOrElse((_) => song.id);
    await _playerCubit.swapReconciledSong(song.id, newId);
    if (!isClosed) {
      _set(videoId, const YtDownloadItem(status: YtDownloadStatus.done));
    }
  }

  /// One-shot completion watcher for a queued (use-case path) download.
  ///
  /// Listens on the shared repository stream until the task reaches a
  /// terminal state; on completion it swaps the player's search row for the
  /// reconciled library row. The subscription self-terminates on the first
  /// terminal event and is cancelled with the cubit (autoSub).
  void _watchForDownloadedSong(String videoId, int searchSongId) {
    final repo = _repository ??
        (getIt.isRegistered<IDownloadRepository>()
            ? getIt<IDownloadRepository>()
            : null);
    if (repo == null) return;
    StreamSubscription<DownloadTask>? sub;
    sub = autoSub(
      repo
          .observeDownloads()
          .where((t) => t.videoId == videoId)
          .where((t) => t.status == DownloadStatus.complete)
          .take(1),
      (task) {
        final newId = task.librarySongId;
        if (sub != null) {
          unawaited(sub.cancel());
          removeFromComposite(sub);
        }
        if (isClosed || newId == null || newId == searchSongId) return;
        unawaited(_playerCubit.swapReconciledSong(searchSongId, newId));
      },
      onDone: () {
        if (sub != null) removeFromComposite(sub);
      },
    );
  }


  int downloadAll(
    Iterable<SongsTableData> songs, {
    void Function(BatchResult)? onCompleted,
  }) {
    int queuedCount = 0;
    final total = songs.length;
    final futures = <Future<bool>>[];

    for (final song in songs) {
      final videoId = song.remoteId;
      if (videoId == null || videoId.isEmpty) continue;
      if (song.source == SongSource.local) continue;

      final current = state.itemFor(videoId);
      if ([
        YtDownloadStatus.running,
        YtDownloadStatus.queued,
        YtDownloadStatus.done,
      ].contains(current.status)) {
        continue;
      }

      queuedCount++;
      futures.add(
        download(song).then((_) async {
          await Future<void>.delayed(Duration.zero);
          final item = state.itemFor(videoId);
          return item.status == YtDownloadStatus.failed;
        }).catchError((e) => true),
      );
    }

    if (futures.isNotEmpty) {
      Future.wait(futures)
          .then((results) {
            if (!isClosed) {
              final failureCount = results.where((e) => e == true).length;
              onCompleted?.call(
                BatchResult(
                  totalCount: total,
                  queuedCount: queuedCount,
                  failureCount: failureCount,
                ),
              );
            }
          })
          .catchError((Object e, StackTrace st) {
            ErrorLogger.log(
              'Batch download in YtmDownloadCubit failed',
              error: e,
              stackTrace: st,
              category: 'YtmDownloadCubit',
            );
          });
    } else {
      onCompleted?.call(
        BatchResult(totalCount: total, queuedCount: 0, failureCount: 0),
      );
    }

    return queuedCount;
  }

  /// Unguarded write used ONLY for fresh user intent (a new download after a
  /// failed/canceled attempt). Everything event-driven goes through [_set].
  void _forceSet(String videoId, YtDownloadItem item) {
    safeEmit(
      YtmDownloadState(
        items: Map.unmodifiable({...state.items, videoId: item}),
      ),
    );
  }

  void _set(String videoId, YtDownloadItem item) {
    // FIX(retry vs stale): `done` is sticky (never downgraded). `failed` /
    // `canceled` are retryable BUT only via an explicit queued signal —
    // a real retry always starts as queued, then running. A stale
    // downloading/running event landing directly on canceled/failed (no
    // intermediate queued) is a throttled-stream race and must stay blocked.
    // Fresh user intent via download() bypasses this entirely with _forceSet.
    final current = state.items[videoId];
    if (current != null) {
      if (current.status == YtDownloadStatus.done &&
          item.status != YtDownloadStatus.done) {
        return; // Block stale downgrade of a completed download.
      }
      if ((current.status == YtDownloadStatus.failed ||
              current.status == YtDownloadStatus.canceled) &&
          item.status == YtDownloadStatus.running) {
        return; // Stale running event — retry must arrive as queued first.
      }
    }
    safeEmit(
      YtmDownloadState(
        items: Map.unmodifiable({...state.items, videoId: item}),
      ),
    );
  }
}
