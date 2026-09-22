// lib/features/ytm_search/cubit/ytm_download_cubit.dart
import 'dart:async';
import 'dart:collection';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/yt_download_service.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/ytm_track.dart';
import '../../downloads/cubit/downloads_cubit.dart';
import '../../downloads/cubit/downloads_state.dart';
import '../../player/cubit/player_cubit.dart';

enum YtDownloadStatus { idle, queued, running, paused, done, failed, canceled }

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

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'error': error,
        'progress': progress,
        'speedKbps': speedKbps,
        'etaSeconds': etaSeconds,
      };
  factory YtDownloadItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'idle';
    return YtDownloadItem(
      status: YtDownloadStatus.values.firstWhere((e) => e.name == statusName,
          orElse: () => YtDownloadStatus.idle),
      error: json['error'] as String?,
      progress: (json['progress'] as num?)?.toDouble(),
      speedKbps: (json['speedKbps'] as num?)?.toDouble(),
      etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
    );
  }
}

class YtmDownloadState {
  final Map<String, YtDownloadItem> items;
  const YtmDownloadState({this.items = const {}});
  YtDownloadItem itemFor(String videoId) =>
      items[videoId] ?? const YtDownloadItem();
}

/// Per-row download UI adapter over [DownloadsCubit].
///
/// This class used to own a second, fully independent download engine — its own
/// queue, its own `YtDownloadStatus` enum, and its own `ytm_download_states`
/// preference key — running beside the repository-backed one. Downloads started
/// from search therefore never appeared on the Downloads screen. It now submits
/// every job to [DownloadsCubit] (the single owner of task state, queueing,
/// persistence, and foreground-service integration) and only maps that state
/// back into the per-row [YtDownloadItem] the buttons render.
@singleton
class YtmDownloadCubit extends PulsrCubit<YtmDownloadState> {
  final YtDownloadService _service;
  final PlayerCubit _playerCubit;
  final DownloadsCubit? _injectedDownloadsCubit;
  StreamSubscription<DownloadsState>? _sub;

  /// Video ids whose completed task has already been folded back into the
  /// queue/DB, so the completion side effects run exactly once.
  final LinkedHashSet<String> _reconciledVideoIds = LinkedHashSet<String>();
  final Map<String, bool> _reconcileLocks = {};
  // FIX-C12: Shield recently completed tasks with a 10-second TTL
  final Map<String, int> _recentlyCompleted = {};
  static const int _recentlyCompletedTtlMs = 10000;

  YtmDownloadCubit(
    this._service,
    this._playerCubit, {
    DownloadsCubit? downloadsCubit,
  })  : _injectedDownloadsCubit = downloadsCubit,
        super(const YtmDownloadState()) {
    _subscribe();
  }

  DownloadsCubit get _downloads =>
      _injectedDownloadsCubit ?? getIt<DownloadsCubit>();

  void _subscribe() {
    _sub?.cancel();
    // FIX-A01: autoSub management
    _sub = autoSub(_downloads.stream, _onDownloadsState);
  }

  // Monotonic clock for recently completed TTL checks
  static final Stopwatch _clock = Stopwatch()..start();
  static int get _nowMs => _clock.elapsedMilliseconds;

  void _onDownloadsState(DownloadsState downloads) {
    if (isClosed) return;

    final now = _nowMs;
    // FIX-C12: Prune recently completed tasks past TTL
    _recentlyCompleted.removeWhere((_, completedAt) => now - completedAt >= _recentlyCompletedTtlMs);

    // FIX-C12: Prune only IDs that are not in tasks AND are not in _recentlyCompleted
    _reconciledVideoIds.removeWhere((id) {
      if (downloads.tasks.containsKey(id)) return false;
      if (_recentlyCompleted.containsKey(id)) return false;
      return true;
    });

    final mapped = <String, YtDownloadItem>{};
    for (final task in downloads.tasks.values) {
      mapped[task.videoId] = _mapTask(task);
      if (task.status == DownloadStatus.complete) {
        _recentlyCompleted[task.videoId] = now;
      }
    }
    // Canceled lives only here: the repository deletes the task on cancel, so a
    // canceled row keeps its state until the song is downloaded again.
    for (final entry in state.items.entries) {
      if (entry.value.status == YtDownloadStatus.canceled) {
        mapped.putIfAbsent(entry.key, () => entry.value);
      }
    }

    safeEmit(YtmDownloadState(items: mapped));

    for (final task in downloads.tasks.values) {
      if (task.status == DownloadStatus.complete &&
          !_reconciledVideoIds.contains(task.videoId) &&
          !(_reconcileLocks[task.videoId] ?? false)) {
        _reconcileLocks[task.videoId] = true;
        _reconciledVideoIds.add(task.videoId);
        _recentlyCompleted[task.videoId] = now;
        // FIX-H04 / B-06: Cap reconciled IDs at 500, evicting oldest (insertion order)
        while (_reconciledVideoIds.length > 250) {
          _reconciledVideoIds.remove(_reconciledVideoIds.first);
        }
        unawaited(_onDownloadComplete(task).whenComplete(() {
          _reconcileLocks.remove(task.videoId);
        }));
      }
    }
  }

  YtDownloadItem _mapTask(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.queued:
        return const YtDownloadItem(
            status: YtDownloadStatus.queued, progress: 0);
      case DownloadStatus.downloading:
        return YtDownloadItem(
          status: YtDownloadStatus.running,
          progress: task.progress,
          speedKbps: task.speedKbps,
          etaSeconds: task.etaSeconds,
        );
      case DownloadStatus.tagging:
        return const YtDownloadItem(
            status: YtDownloadStatus.running, progress: 1);
      case DownloadStatus.paused:
        return const YtDownloadItem(status: YtDownloadStatus.paused);
      case DownloadStatus.complete:
        return const YtDownloadItem(
            status: YtDownloadStatus.done, progress: 1);
      case DownloadStatus.failed:
        return YtDownloadItem(
            status: YtDownloadStatus.failed, error: task.error);
    }
  }

  /// After a task lands in the library: backfill the duration the stream
  /// resolved (a search row often has none) and swap the stale negative-id
  /// remote row in the queues for the positive local one.
  Future<void> _onDownloadComplete(DownloadTask task) async {
    final videoId = task.videoId;
    final localId = task.localSongId;

    try {
      final resolved = _service.getResolvedStream(videoId);
      if (localId != null &&
          resolved != null &&
          resolved.duration > Duration.zero) {
        final db = getIt<AppDatabase>();
        await (db.update(db.songsTable)..where((t) => t.id.equals(localId)))
            .write(SongsTableCompanion(
                durationMs: Value(resolved.duration.inMilliseconds)));
      }
    } catch (_) {}

    final oldId = task.sourceSongId ??
        YtmTrack(
          videoId: videoId,
          title: task.title,
          artist: task.artist,
          duration: Duration.zero,
        ).songId;
    if (localId != null) {
      try {
        await _playerCubit.swapReconciledSong(oldId, localId);
      } catch (_) {}
    }
  }

  Future<void> download(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    final current = state.itemFor(videoId);
    if (current.status == YtDownloadStatus.queued ||
        current.status == YtDownloadStatus.running) {
      return;
    }

    _reconciledVideoIds.remove(videoId);
    _set(videoId,
        const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0));

    await _downloads.queueDownload(_taskFor(song, videoId));
  }

  DownloadTask _taskFor(SongsTableData song, String videoId) => DownloadTask(
        id: videoId,
        videoId: videoId,
        title: song.title,
        artist: song.artist,
        status: DownloadStatus.queued,
        artworkUrl: song.remoteArtworkUrl,
        sourceSongId: song.id,
        createdAt: DateTime.now(),
      );

  void cancelDownload(String videoId) {
    _downloads.cancelDownload(videoId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.canceled));
  }

  /// Queues multiple songs for download in batch.
  /// Starts are staggered (~500ms apart) so N simultaneous resolves don't trip
  /// YouTube's 429/bot throttles — the "first few succeed, rest fail" pattern.
  /// Returns the number of songs newly queued.
  ///
  /// Staggered starts are generation-guarded: starting a new batch or closing
  /// the cubit cancels pending delayed starts from the previous batch instead
  /// of firing them into a dead/changed queue. See [downloadAllDetailed] for
  /// the honest skipped/capped counts the UI surfaces.
  int _batchGeneration = 0;

  /// Cancels pending staggered starts from the current batch (already-queued
  /// downloads keep running).
  void cancelPendingBatch() => _batchGeneration++;

  int downloadAll(Iterable<SongsTableData> songs, {int maxBatch = 50}) =>
      downloadAllDetailed(songs, maxBatch: maxBatch).queued;

  ({int queued, int skippedLocal, int alreadyActive, int capped}) downloadAllDetailed(
      Iterable<SongsTableData> songs,
      {int maxBatch = 50}) {
    final generation = ++_batchGeneration;
    var queuedCount = 0;
    var skippedLocal = 0;
    var alreadyActive = 0;
    var capped = 0;
    for (final song in songs) {
      final videoId = song.remoteId;
      if (videoId == null || videoId.isEmpty) continue;

      // Skip tracks that are already local on disk
      if (song.source == SongSource.local) {
        skippedLocal++;
        continue;
      }

      final current = state.itemFor(videoId);
      if (current.status == YtDownloadStatus.queued ||
          current.status == YtDownloadStatus.running) {
        alreadyActive++;
        continue;
      }

      if (queuedCount >= maxBatch) {
        capped++;
        continue;
      }

      final index = queuedCount;
      queuedCount++;
      if (index == 0) {
        download(song);
      } else {
        // Staggered start; unawaited by design (fire-and-forget batch) but
        // generation-guarded so a superseded batch never fires.
        Future.delayed(Duration(milliseconds: 500 * index), () {
          if (!isClosed && generation == _batchGeneration) download(song);
        });
      }
    }
    return (
      queued: queuedCount,
      skippedLocal: skippedLocal,
      alreadyActive: alreadyActive,
      capped: capped,
    );
  }

  Future<void> retryDownload(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) return;
    _reconciledVideoIds.remove(videoId);
    _set(videoId, const YtDownloadItem(status: YtDownloadStatus.idle));
    await download(song);
  }

  final Map<String, int> _lastEmitTimeByVideoId = {};
  static const int _maxThrottleEntries = 200;

  void _set(String videoId, YtDownloadItem item) {
    if (isClosed) return;

    if (_lastEmitTimeByVideoId.length >= _maxThrottleEntries &&
        !_lastEmitTimeByVideoId.containsKey(videoId)) {
      _lastEmitTimeByVideoId.remove(_lastEmitTimeByVideoId.keys.first);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastEmit = _lastEmitTimeByVideoId[videoId] ?? 0;

    // Throttle progress updates to at most 5/sec per videoId. State transitions
    // and completion are emitted immediately.
    final currentItem = state.itemFor(videoId);
    final isIntermediateProgress = item.status == YtDownloadStatus.running &&
        currentItem.status == YtDownloadStatus.running &&
        item.progress != null &&
        item.progress! < 1.0;

    if (isIntermediateProgress && (now - lastEmit < 200)) {
      return;
    }

    _lastEmitTimeByVideoId[videoId] = now;
    safeEmit(YtmDownloadState(items: {...state.items, videoId: item}));
  }

  @override
  Future<void> close() async {
    _batchGeneration++;
    await _sub?.cancel();
    _sub = null;
    _lastEmitTimeByVideoId.clear();
    _reconciledVideoIds.clear();
    _reconcileLocks.clear();
    return super.close();
  }
}
