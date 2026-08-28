// lib/features/ytm_search/cubit/ytm_download_cubit.dart
// DL-17: Single source of truth — thin viewer over shared repository stream.
// DL-18: Guard all async continuations with if (isClosed) return.

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../core/di/injection.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/downloads/yt_download_service.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/repositories/download_repository_interface.dart';
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
}

@singleton
class YtmDownloadCubit extends Cubit<YtmDownloadState> {
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;
  final IDownloadRepository? _repository;

  StreamSubscription<DownloadTask>? _repoSub;
  final Map<String, int> _lastEmitTimeByVideoId = {};

  YtmDownloadCubit(
    this._service,
    this._playerCubit, [
    this._repository,
  ]) : super(const YtmDownloadState()) {
    _initSharedStream();
  }

  void _initSharedStream() {
    final repo = _repository ?? (getIt.isRegistered<IDownloadRepository>() ? getIt<IDownloadRepository>() : null);
    if (repo != null) {
      repo.getAllDownloads().then((tasks) {
        if (isClosed) return;
        final initialMap = <String, YtDownloadItem>{};
        for (final t in tasks) {
          initialMap[t.videoId] = _mapTaskToItem(t);
        }
        if (initialMap.isNotEmpty && !isClosed) {
          emit(YtmDownloadState(items: {...state.items, ...initialMap}));
        }
      }).catchError((e, st) {
        ErrorLogger.log('YtmDownloadCubit getAllDownloads failed', error: e, stackTrace: st, category: 'YtmDownloadCubit');
      });

      _repoSub = repo.observeDownloads().listen((task) {
        if (isClosed) return;
        final item = _mapTaskToItem(task);
        _set(task.videoId, item);
      }, onError: (e, st) {
        ErrorLogger.log('YtmDownloadCubit observeDownloads error', error: e, stackTrace: st, category: 'YtmDownloadCubit');
      });
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
      DownloadStatus.paused || DownloadStatus.interrupted => const YtDownloadItem(
          status: YtDownloadStatus.idle,
        ),
    };
  }

  void cancelDownload(String videoId) {
    _service.cancel(videoId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
  }

  Future<void> download(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    final current = state.itemFor(videoId);
    if ([
      YtDownloadStatus.running,
      YtDownloadStatus.queued,
      YtDownloadStatus.done
    ].contains(current.status)) {
      return;
    }

    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0));

    final result = await _service.download(song, onProgress: (p) {
      if (isClosed) return;
      if (p.stage == YtDownloadStage.canceled) {
        _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
        return;
      }
      _set(
        videoId,
        YtDownloadItem(
          status: p.stage == YtDownloadStage.queued
              ? YtDownloadStatus.queued
              : YtDownloadStatus.running,
          progress: p.stage == YtDownloadStage.downloading ? p.fraction : null,
          speedKbps: p.stage == YtDownloadStage.downloading ? p.speedKbps : null,
          etaSeconds: p.stage == YtDownloadStage.downloading ? p.etaSeconds : null,
        ),
      );
    });

    if (isClosed) return;
    if (result.isLeft()) {
      final message = result.getLeft().toNullable()?.message ?? 'Download failed';
      _set(videoId, YtDownloadItem(status: YtDownloadStatus.failed, error: message));
      return;
    }

    final newId = result.getOrElse((_) => song.id);
    await _playerCubit.swapReconciledSong(song.id, newId);
    if (!isClosed) {
      _set(videoId, const YtDownloadItem(status: YtDownloadStatus.done));
    }
  }

  int downloadAll(Iterable<SongsTableData> songs, {void Function(BatchResult)? onCompleted}) {

    int queuedCount = 0;
    int failureCount = 0;
    final total = songs.length;
    final futures = <Future<void>>[];

    for (final song in songs) {
      final videoId = song.remoteId;
      if (videoId == null || videoId.isEmpty) continue;
      if (song.source == SongSource.local) continue;

      final current = state.itemFor(videoId);
      if ([
        YtDownloadStatus.running,
        YtDownloadStatus.queued,
        YtDownloadStatus.done
      ].contains(current.status)) {
        continue;
      }

      queuedCount++;
      futures.add(download(song).catchError((e) {
        failureCount++;
      }));
    }

    if (futures.isNotEmpty) {
      Future.wait(futures).then((_) {
        if (!isClosed) {
          onCompleted?.call(BatchResult(
            totalCount: total,
            queuedCount: queuedCount,
            failureCount: failureCount,
          ));
        }
      }).catchError((e, st) {
        ErrorLogger.log('Batch download in YtmDownloadCubit failed', error: e, stackTrace: st, category: 'YtmDownloadCubit');
      });
    } else {
      onCompleted?.call(BatchResult(
        totalCount: total,
        queuedCount: 0,
        failureCount: 0,
      ));
    }

    return queuedCount;
  }


  static const int _maxThrottleEntries = 200;

  void _set(String videoId, YtDownloadItem item) {
    if (isClosed) return;

    if (_lastEmitTimeByVideoId.length >= _maxThrottleEntries &&
        !_lastEmitTimeByVideoId.containsKey(videoId)) {
      _lastEmitTimeByVideoId.remove(_lastEmitTimeByVideoId.keys.first);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastEmitTimeByVideoId[videoId] ?? 0;

    final currentItem = state.itemFor(videoId);
    final isIntermediateProgress = item.status == YtDownloadStatus.running &&
        currentItem.status == YtDownloadStatus.running &&
        item.progress != null &&
        item.progress! < 1.0;

    if (isIntermediateProgress && (now - lastEmit < 100)) {
      return;
    }

    _lastEmitTimeByVideoId[videoId] = now;
    emit(YtmDownloadState(items: {...state.items, videoId: item}));
  }

  @override
  Future<void> close() {
    _repoSub?.cancel();
    _lastEmitTimeByVideoId.clear();
    return super.close();
  }
}

