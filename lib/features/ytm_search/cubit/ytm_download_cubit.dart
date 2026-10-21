// lib/features/ytm_search/cubit/ytm_download_cubit.dart
import 'dart:async';
import 'dart:collection';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../core/bloc/base_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/yt_download_service.dart';
import '../../../core/utils/error_logger.dart';

export '../../../core/utils/batch_download_l10n.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/download_task.dart';
import '../../../domain/models/ytm_track.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../downloads/cubit/downloads_cubit.dart';
import '../../downloads/cubit/downloads_state.dart';
import '../../player/cubit/player_cubit.dart';

enum YtDownloadStatus { idle, queued, running, paused, done, failed, canceled }

/// How a single song fared at admission time, before any bytes move.
enum _AdmitOutcome { queued, alreadyActive, alreadyLocal, failed }

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
@lazySingleton
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

  /// Upper bound on [_reconciledVideoIds]; oldest entries are evicted first.
  static const int _maxReconciledIds = 500;

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
    _recentlyCompleted.removeWhere(
        (_, completedAt) => now - completedAt >= _recentlyCompletedTtlMs);

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
        while (_reconciledVideoIds.length > _maxReconciledIds) {
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
        return const YtDownloadItem(status: YtDownloadStatus.done, progress: 1);
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
    } catch (e, st) {
      // Was `catch (_) {}`: a failed duration backfill silently left the
      // library row with a stale/zero duration. Keep it non-fatal but log it.
      ErrorLogger.log('Failed to backfill downloaded track duration',
          error: e, stackTrace: st, category: 'YtmDownloadCubit');
    }

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
      } catch (e, st) {
        // H-12: Log and surface the failure. Swallowing it left a placeholder
        // (negative-ID) entry in the queue with no user-visible explanation.
        ErrorLogger.log('Failed to link downloaded file to queue',
            error: e, stackTrace: st, category: 'YtmDownloadCubit');
        emitEffect(const ShowToastEffect(
            'Downloaded file could not be linked to the queue.'));
      }
    }
  }

  Future<void> download(SongsTableData song) async {
    final result = await _admit(song);
    if (result.outcome == _AdmitOutcome.failed &&
        result.error != null &&
        !isClosed) {
      // The row itself flips to failed below; the toast tells the user why
      // even if the row is scrolled off (e.g. Wi-Fi-only mode blocking it).
      emitEffect(ShowToastEffect(result.error!));
    }
  }

  /// Single admission path shared by [download] and [downloadAllDetailed].
  ///
  /// Ordering matters: dedupe against the library happens before the row is
  /// optimistically flipped to queued, and a paused row resumes through
  /// [DownloadsCubit.resumeDownload] (not a fresh queue) so the service's
  /// paused marker is cleared — the old `download()` queued a brand-new task
  /// over the paused one and left the notification's Resume action stale.
  Future<({_AdmitOutcome outcome, String? error})> _admit(
      SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      return (outcome: _AdmitOutcome.alreadyLocal, error: null);
    }

    final current = state.itemFor(videoId);
    if (current.status == YtDownloadStatus.queued ||
        current.status == YtDownloadStatus.running) {
      return (outcome: _AdmitOutcome.alreadyActive, error: null);
    }

    if (current.status == YtDownloadStatus.paused) {
      final resumed = await _downloads.resumeDownload(videoId);
      if (isClosed) return (outcome: _AdmitOutcome.alreadyActive, error: null);
      if (resumed.isRight()) {
        return (outcome: _AdmitOutcome.queued, error: null);
      }
      final message =
          resumed.getLeft().toNullable()?.message ?? 'Download failed';
      _set(videoId,
          YtDownloadItem(status: YtDownloadStatus.failed, error: message));
      return (outcome: _AdmitOutcome.failed, error: message);
    }

    // Already a local library track (a completed earlier download, or a file
    // that was installed outside this UI): re-fetching it would create a
    // duplicate file and a duplicate row.
    if (await _alreadyInLibrary(videoId)) {
      if (!isClosed) {
        _set(videoId,
            const YtDownloadItem(status: YtDownloadStatus.done, progress: 1));
      }
      return (outcome: _AdmitOutcome.alreadyLocal, error: null);
    }

    _reconciledVideoIds.remove(videoId);
    _set(videoId,
        const YtDownloadItem(status: YtDownloadStatus.queued, progress: 0));

    final result = await _downloads.queueDownload(_taskFor(song, videoId));
    if (isClosed) return (outcome: _AdmitOutcome.queued, error: null);
    if (result.isRight()) {
      final admission = result.toNullable()!.admission;
      switch (admission) {
        case DownloadAdmission.queued:
          return (outcome: _AdmitOutcome.queued, error: null);
        case DownloadAdmission.alreadyActive:
          return (outcome: _AdmitOutcome.alreadyActive, error: null);
        case DownloadAdmission.alreadyComplete:
          _set(videoId,
              const YtDownloadItem(status: YtDownloadStatus.done, progress: 1));
          return (outcome: _AdmitOutcome.alreadyLocal, error: null);
      }
    }

    final message = result.getLeft().toNullable()?.message ?? 'Download failed';
    _set(videoId,
        YtDownloadItem(status: YtDownloadStatus.failed, error: message));
    return (outcome: _AdmitOutcome.failed, error: message);
  }

  /// Whether an active local row already exists for [videoId]. Fails open: a
  /// lookup error must not block a download the user asked for.
  Future<bool> _alreadyInLibrary(String videoId) async {
    if (!getIt.isRegistered<IMusicRepository>()) return false;
    try {
      final result = await getIt<IMusicRepository>().getSongByRemoteId(videoId);
      return result.isRight() && result.getOrElse((_) => null) != null;
    } catch (e, st) {
      ErrorLogger.log('Download library dedupe lookup failed for $videoId',
          error: e, stackTrace: st, category: 'YtmDownloadCubit');
      return false;
    }
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

  /// Queues multiple songs for download in batch and reports what actually
  /// happened to each track.
  ///
  /// Admissions are awaited one at a time but transfers are not: the
  /// repository/service schedulers still cap concurrent transfers (and their
  /// resolves), so the old ~500ms admission stagger was never what protected
  /// YouTube from a 429 burst. Awaiting buy us honesty — [queued] counts tasks
  /// that were genuinely admitted, and a policy block surfaces as
  /// `failed: N, firstError: ...` instead of a success toast over zero
  /// downloads.
  ///
  /// The returned record has:
  /// - [queued]: newly admitted downloads,
  /// - [alreadyActive]: already queued/running in this session,
  /// - [skippedLocal]: already on device (or a local row exists),
  /// - [capped]: beyond [maxBatch], left for a follow-up run,
  /// - [failed]: admission refused (network policy, storage, invalid id),
  ///   with [firstError] carrying the first refusal message.
  Future<
          ({
            int queued,
            int skippedLocal,
            int alreadyActive,
            int capped,
            int failed,
            String? firstError,
          })>
      downloadAllDetailed(Iterable<SongsTableData> songs,
          {int maxBatch = 50}) async {
    var queuedCount = 0;
    var skippedLocal = 0;
    var alreadyActive = 0;
    var capped = 0;
    var failed = 0;
    String? firstError;
    for (final song in songs) {
      if (isClosed) break;
      final videoId = song.remoteId;
      if (videoId == null || videoId.isEmpty) continue;

      // Skip tracks already local on disk or already marked downloaded — but a
      // row whose file was deleted (`isMissing`) is a tombstone and must be
      // allowed to download again. The old check skipped those forever, so a
      // deleted download could never be re-fetched.
      if ((song.source == SongSource.local || song.isDownloaded) &&
          !song.isMissing) {
        skippedLocal++;
        continue;
      }

      // Count already-running rows before the batch cap: they occupy a slot
      // already and must be reported as active, not as capped.
      final current = state.itemFor(videoId);
      if (current.status == YtDownloadStatus.queued ||
          current.status == YtDownloadStatus.running) {
        alreadyActive++;
        continue;
      }
      // A paused row is resumed, not admitted, so the cap does not apply.
      if (current.status != YtDownloadStatus.paused &&
          queuedCount + failed >= maxBatch) {
        capped++;
        continue;
      }

      final result = await _admit(song);
      if (isClosed) break;
      switch (result.outcome) {
        case _AdmitOutcome.queued:
          queuedCount++;
        case _AdmitOutcome.alreadyActive:
          alreadyActive++;
        case _AdmitOutcome.alreadyLocal:
          skippedLocal++;
        case _AdmitOutcome.failed:
          failed++;
          firstError ??= result.error;
      }
    }
    return (
      queued: queuedCount,
      skippedLocal: skippedLocal,
      alreadyActive: alreadyActive,
      capped: capped,
      failed: failed,
      firstError: firstError,
    );
  }

  Future<int> downloadAll(Iterable<SongsTableData> songs,
          {int maxBatch = 50}) async =>
      (await downloadAllDetailed(songs, maxBatch: maxBatch)).queued;

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
    safeEmit(YtmDownloadState(
        items: Map<String, YtDownloadItem>.unmodifiable(
            {...state.items, videoId: item})));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _lastEmitTimeByVideoId.clear();
    _reconciledVideoIds.clear();
    _reconcileLocks.clear();
    return super.close();
  }
}
