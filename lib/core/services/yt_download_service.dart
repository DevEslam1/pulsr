// lib/core/services/yt_download_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pulsr/domain/models/ytm_audio_quality.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart' show Value;
import '../../data/audio/adaptive_buffer_engine.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/lyrics_repository.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../data/services/download_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../constants/channels.dart';
import '../di/injection.dart';
import '../errors/failures.dart';
import '../errors/ytm_error_classifier.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';
import '../widgets/cached_artwork.dart';
import 'yt_download_artifact_store.dart';
import 'yt_download_file_naming.dart';
import 'yt_download_quality_policy.dart';
import 'yt_download_transfer_math.dart';
import 'yt_download_transfer_policy.dart';
import 'ytm_service.dart';
import 'ytm_url_cache.dart';

/// Where a download currently is, for driving progress UI.
enum YtDownloadStage {
  queued,
  resolving,
  downloading,
  tagging,
  saving,
  indexing,
  done,
  canceled
}

class YtDownloadProgress {
  final YtDownloadStage stage;

  /// 0..1 during [YtDownloadStage.downloading], null when indeterminate.
  final double? fraction;
  final double? speedKbps;
  final int? etaSeconds;

  const YtDownloadProgress(this.stage,
      [this.fraction, this.speedKbps, this.etaSeconds]);
}

class _QueuedDownload {
  final SongsTableData song;
  final void Function(YtDownloadProgress)? onProgress;
  final Completer<Result<int>> completer;

  /// Per-download quality requested by the caller (the long-press picker), or
  /// null to fall back to the persisted download-quality default.
  final YtmAudioQuality? quality;
  bool isCanceled = false;

  _QueuedDownload({
    required this.song,
    required this.onProgress,
    required this.completer,
    this.quality,
  });
}

/// Raised when a server answers a ranged chunk request with `200 OK`, i.e. it
/// is sending the whole body and the four-way split cannot be honoured. Private
/// and never surfaced to callers: the parallel path catches it and retries the
/// transfer as a single request.
class _RangeIgnored implements Exception {
  const _RangeIgnored();

  @override
  String toString() => 'Server ignored the Range header';
}

enum _ForegroundPhase { idle, starting, running, stopping }

/// Hardened YouTube Download Service.
///
/// Features:
/// - Max 3 concurrent downloads with FIFO queue
/// - Pre-download PoToken attestation verification
/// - Transparent 403 re-resolution & Range header resume
/// - Multi-threaded chunked parallel downloading
/// - User-friendly bot block handling and cancellation tokens
@lazySingleton
class YtDownloadService {
  static const _downloadChannel = MethodChannel(PulsrChannels.ytDownload);
  int _maxConcurrentDownloads = 3;

  /// Completed-download paths by video id. Bounded: nothing ever removed an
  /// entry, so it grew for the whole process lifetime.
  final Map<String, String> _downloadedFilePaths = {};
  final Map<String, String> _downloadedContentUris = {};
  static const int _maxDownloadedPaths = 128;

  String? getDownloadedPath(String videoId) => _downloadedFilePaths[videoId];

  /// MediaStore URI captured when [videoId] was saved, used to delete the row
  /// by URI instead of resolving it by path later.
  String? getDownloadedContentUri(String videoId) =>
      _downloadedContentUris[videoId];

  /// Drops the cached path for [videoId] after its file/row was removed, so a
  /// later completion cannot resurrect a stale path.
  void forgetDownloadedPath(String videoId) {
    _downloadedFilePaths.remove(videoId);
    _downloadedContentUris.remove(videoId);
  }

  void _rememberDownloadedPath(String videoId, String path,
      {String? contentUri}) {
    _downloadedFilePaths.remove(videoId);
    _downloadedFilePaths[videoId] = path;
    _downloadedContentUris.remove(videoId);
    if (contentUri != null && contentUri.isNotEmpty) {
      _downloadedContentUris[videoId] = contentUri;
    }
    while (_downloadedFilePaths.length > _maxDownloadedPaths) {
      final evicted = _downloadedFilePaths.keys.first;
      _downloadedFilePaths.remove(evicted);
      _downloadedContentUris.remove(evicted);
    }
  }

  /// Kept in step with [DownloadSettings.maxConcurrent] by
  /// [DownloadRepositoryImpl]; the class used to hard-code 3 independently of
  /// the user's setting, so raising the preference changed nothing.
  void setMaxConcurrentDownloads(int value) {
    _maxConcurrentDownloads = value.clamp(1, 5);
  }

  final HttpClient _http;
  final YtmService _ytmService;
  // ignore: unused_field - kept for future single-file rescan without full library scan (dedup fix)
  final MediaScannerService _scanner;
  final IMusicRepository _repository;

  final Queue<_QueuedDownload> _queue = Queue<_QueuedDownload>();
  final Map<String, _QueuedDownload> _activeDownloads = {};
  static const int _maxCanceledIds = 200;
  final Set<String> _canceledVideoIds = <String>{};

  /// Per-download quality overrides requested from the search row's picker.
  final YtDownloadQualityPolicy _qualityPolicy = YtDownloadQualityPolicy();

  /// Records the quality the user picked for the next download of [videoId].
  void setPendingDownloadQuality(String videoId, YtmAudioQuality quality) {
    _qualityPolicy.setPending(videoId, quality);
  }

  /// Foreground-service lifecycle. A start is asynchronous, so "running" must
  /// only be claimed after the platform confirms it, and an idle stop that
  /// arrives while a start is in flight has to be deferred instead of racing
  /// the service into existence.
  _ForegroundPhase _foregroundPhase = _ForegroundPhase.idle;
  int _foregroundStartsInFlight = 0;
  bool _foregroundStopRequested = false;

  bool _processing =
      false; // FIX-A03: Guard against re-entrant calls in _processQueue
  /// FIX-A05/C05: track resolved stream duration.
  /// F12: bounded — it used to hold one entry per video id for the whole
  /// process lifetime, and nothing ever removed one.
  static const int _maxResolvedStreams = 128;
  final Map<String, YtmStream> _resolvedStreams = {};

  /// Video ids the user paused. While any entry is present the download
  /// foreground service is deliberately kept alive so the notification — and
  /// with it the Resume action — survives a pause (C-7). Without this, pausing
  /// emptied the active set and `_stopForegroundServiceIfIdle` tore the
  /// notification down, leaving no way back.
  final Set<String> _pausedVideoIds = <String>{};

  /// When each paused id was marked, so a marker that is never resumed or
  /// deleted can expire (F14).
  final Map<String, DateTime> _pausedSince = {};

  /// How long a paused marker keeps the foreground service alive on its own.
  /// Nothing else ever drops one, so a paused-then-abandoned download held the
  /// service — and the process — up indefinitely on API < 35, where there is
  /// no dataSync foreground-time cap to end it.
  static const Duration _pausedMarkerIdleWindow = Duration(minutes: 30);

  /// Marks [videoId] as paused so the foreground service is not stopped while
  /// it is waiting to be resumed.
  void markPaused(String videoId) {
    _pausedVideoIds.add(videoId);
    _pausedSince[videoId] = DateTime.now();
  }

  /// Clears the paused marker and stops the foreground service if that leaves
  /// nothing running or waiting.
  void clearPaused(String videoId) {
    _pausedVideoIds.remove(videoId);
    _pausedSince.remove(videoId);
    _stopForegroundServiceIfIdle();
  }

  /// Drops paused markers older than [_pausedMarkerIdleWindow].
  void _pruneExpiredPausedMarkers() {
    if (_pausedSince.isEmpty) return;
    final cutoff = DateTime.now().subtract(_pausedMarkerIdleWindow);
    _pausedSince.removeWhere((id, since) {
      if (since.isBefore(cutoff)) {
        _pausedVideoIds.remove(id);
        return true;
      }
      return false;
    });
  }

  /// Returns last resolved YtmStream for videoId if available
  YtmStream? getResolvedStream(String videoId) => _resolvedStreams[videoId];

  YtDownloadService(
      this._http, this._ytmService, this._scanner, this._repository);

  static const Duration _stallTimeout = YtDownloadTransferMath.stallTimeout;

  /// Bytes [stream] is expected to occupy on disk, from its own metadata.
  static int estimateBytes(YtmStream stream) =>
      YtDownloadTransferMath.estimateBytes(stream);

  /// Quality a transfer should request. An explicit per-download [override]
  /// wins; otherwise the persisted download-quality default, then the
  /// streaming-quality fallback, then `high`. The download setting is checked
  /// first so the separate Download Quality row actually governs downloads.
  @visibleForTesting
  static String resolveDownloadQuality({
    YtmAudioQuality? override,
    String? downloadQuality,
    String? streamingQuality,
  }) =>
      YtDownloadQualityPolicy.resolve(
        override: override,
        downloadQuality: downloadQuality,
        streamingQuality: streamingQuality,
      );

  /// Disk space this service insists on before starting a download of
  /// [stream], including the scratch the parallel path needs (F3).
  @visibleForTesting
  static int requiredPreflightBytes(YtmStream stream) =>
      YtDownloadTransferMath.requiredPreflightBytes(stream);

  /// Stamp value written beside a partial so a resume can tell whether those
  /// bytes belong to the body it is about to request (F6). Body identity, not
  /// the URL: see [YtDownloadTransferMath.resumeStampFor].
  @visibleForTesting
  static String resumeStampFor({
    required String container,
    int? expectedBytes,
    String? videoId,
  }) =>
      YtDownloadTransferMath.resumeStampFor(
          container: container, expectedBytes: expectedBytes, videoId: videoId);

  /// Whether a `.part` carrying [stampContents] may be resumed against
  /// [urlStamp].
  @visibleForTesting
  static bool resumeStampMatches(String? stampContents, String urlStamp) =>
      YtDownloadTransferMath.resumeStampMatches(stampContents, urlStamp);

  /// How much life a URL needs left for this download to finish on it.
  static Duration requiredLifetime(YtmStream stream) =>
      YtDownloadTransferMath.requiredLifetime(stream);

  /// Cancels an active or queued download.
  void cancel(String videoId) {
    while (_canceledVideoIds.length >= _maxCanceledIds) {
      _canceledVideoIds.remove(_canceledVideoIds.first);
    }
    _canceledVideoIds.add(videoId);
    _qualityPolicy.discardPending(videoId);
    final active = _activeDownloads[videoId];
    if (active != null) {
      active.isCanceled = true;
      active.onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.canceled));
    }
  }

  /// Downloads [song] (which must be a `source == youtube` row) and returns the
  /// surviving positive song id once it is a local library track.
  ///
  /// [quality] is the per-download picker override; when null the pending
  /// picker request for this video id (if any) is used, then the persisted
  /// `setting_download_quality`, then the streaming quality, then `high`.
  ///
  /// When [bypassInternalQueue] is true (used by [DownloadRepositoryImpl],
  /// which already schedules concurrency and queue order), the task skips
  /// [_queue] and starts immediately while still registering in
  /// [_activeDownloads] for deduplication, cancellation, and foreground-service
  /// lifecycle tracking.
  Future<Result<int>> download(
    SongsTableData song, {
    void Function(YtDownloadProgress)? onProgress,
    YtmAudioQuality? quality,
    bool bypassInternalQueue = false,
  }) async {
    if (song.source != SongSource.youtube) {
      return const Left(
          DownloadFailure('Only YouTube tracks can be downloaded'));
    }
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      return const Left(DownloadFailure('Track has no video id'));
    }

    _canceledVideoIds.remove(videoId);

    final completer = Completer<Result<int>>();
    // Chain onto an existing job for the same video rather than starting a
    // second one. The queue was not consulted, so two taps before the first
    // download started put two tasks in it; the second was only recognised as a
    // duplicate once it reached the front, and until then it held a slot and
    // reported its own progress over the first one's.
    final existing = _activeDownloads[videoId] ??
        _queue.cast<_QueuedDownload?>().firstWhere(
              (t) => t?.song.remoteId == videoId && !(t?.isCanceled ?? true),
              orElse: () => null,
            );
    if (existing != null) {
      existing.completer.future
          .then(completer.complete, onError: completer.completeError);
      return completer.future;
    }

    // Consume the picker override only now that this call actually creates a
    // job. Taking it before the dedupe check swallowed the quality the user
    // picked whenever a double-tap chained onto the first tap's job, so the
    // eventual retry ran at the default quality.
    final requestedQuality = quality ?? _qualityPolicy.takePending(videoId);

    final task = _QueuedDownload(
      song: song,
      onProgress: onProgress,
      completer: completer,
      quality: requestedQuality,
    );

    _startForegroundService(videoId, song.title);

    if (bypassInternalQueue) {
      ErrorLogger.addBreadcrumb(
          'Download dispatched directly: ${task.song.remoteId}',
          category: 'download',
          data: {'videoId': task.song.remoteId ?? ''});
      _startTaskExecution(task);
      return completer.future;
    }

    _queue.add(task);
    onProgress?.call(const YtDownloadProgress(YtDownloadStage.queued));
    ErrorLogger.addBreadcrumb('Download queued: ${task.song.remoteId}',
        category: 'download', data: {'videoId': task.song.remoteId ?? ''});
    _processQueue();

    return completer.future;
  }

  /// Brings the native download notification up for the first queued job.
  ///
  /// Android stops an app's threads soon after it leaves the foreground unless a
  /// foreground service is running, so without this a download started from the
  /// search screen simply stopped when the user switched apps — the very moment
  /// a user expects a download to keep going.
  void _startForegroundService(String videoId, String title) {
    _foregroundStartsInFlight++;
    if (_foregroundPhase != _ForegroundPhase.running) {
      _foregroundPhase = _ForegroundPhase.starting;
    }
    _downloadChannel.invokeMethod('startDownloadForeground', {
      'videoId': videoId,
      'title': title,
    }).then((ok) {
      // F13: only claim foreground protection once the platform confirms it.
      // The flag used to be raised before the call, so a degraded start
      // (Android 12+ background-start refusal, Doze) left Dart believing the
      // download was protected and it never retried — while every later
      // progress publish went to a service that was not there.
      _foregroundStartsInFlight--;
      if (ok == true) {
        _foregroundPhase = _ForegroundPhase.running;
      } else if (_foregroundStartsInFlight == 0 &&
          _foregroundPhase == _ForegroundPhase.starting) {
        _foregroundPhase = _ForegroundPhase.idle;
      }
      _drainDeferredForegroundStop();
    }).catchError((_) {
      _foregroundStartsInFlight--;
      // A second start may have confirmed while this one failed; keep running.
      if (_foregroundStartsInFlight == 0 &&
          _foregroundPhase == _ForegroundPhase.starting) {
        _foregroundPhase = _ForegroundPhase.idle;
      }
      _drainDeferredForegroundStop();
      return null;
    });
  }

  void _drainDeferredForegroundStop() {
    if (!_foregroundStopRequested || _foregroundStartsInFlight > 0) return;
    _foregroundStopRequested = false;
    _stopForegroundServiceIfIdle();
  }

  /// Tears the notification down once, when nothing is left to download.
  void _stopForegroundServiceIfIdle() {
    if (_activeDownloads.isNotEmpty || _queue.isNotEmpty) return;
    // A paused download is not idle: the notification must stay up so the user
    // can resume it (C-7).
    _pruneExpiredPausedMarkers();
    if (_pausedVideoIds.isNotEmpty) return;

    switch (_foregroundPhase) {
      case _ForegroundPhase.idle:
        return;
      case _ForegroundPhase.starting:
        // The service may exist the moment the platform answers; stop it then
        // instead of leaking it for a queue that is already empty.
        _foregroundStopRequested = true;
        return;
      case _ForegroundPhase.stopping:
        return;
      case _ForegroundPhase.running:
        break;
    }

    _foregroundPhase = _ForegroundPhase.stopping;
    _downloadChannel.invokeMethod('stopDownloadForeground').then((_) {
      if (_foregroundPhase == _ForegroundPhase.stopping) {
        _foregroundPhase = _ForegroundPhase.idle;
      }
    }).catchError((_) {
      if (_foregroundPhase == _ForegroundPhase.stopping) {
        _foregroundPhase = _ForegroundPhase.idle;
      }
      return null;
    });
  }

  /// F8: every publish is a `startService(ACTION_UPDATE)` on the platform
  /// channel and the transfer loops call this many times a second per download
  /// — up to ~36 service starts a second with three concurrent transfers, each
  /// one rebuilding the notification. Coalescing to 250ms keeps the visible
  /// progress responsive at a fraction of the IPC cost. A terminal value is
  /// always published so the notification cannot be left stale.
  static const int _foregroundPublishMinIntervalMs = 250;
  final Map<String, int> _lastForegroundPublishMs = {};

  void _publishForegroundProgress(
      String videoId, String title, double? fraction) {
    if (_foregroundPhase != _ForegroundPhase.running || fraction == null) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastForegroundPublishMs[videoId] ?? 0;
    final isTerminal = fraction >= 1.0;
    if (!isTerminal && now - last < _foregroundPublishMinIntervalMs) return;
    _lastForegroundPublishMs[videoId] = now;
    _downloadChannel.invokeMethod('updateDownloadProgress', {
      'videoId': videoId,
      'title': title,
      'progress': (fraction * 100).round().clamp(0, 100),
    }).catchError((_) => null);
  }

  void _processQueue() {
    if (_processing) {
      return; // FIX-A03: Guard against re-entrant calls with a _processing bool flag
    }
    _processing = true; // FIX-A03: Mark processing active
    try {
      while (_activeDownloads.length < _maxConcurrentDownloads &&
          _queue.isNotEmpty) {
        final task = _queue.removeFirst();
        final videoId = task.song.remoteId!;

        if (_canceledVideoIds.contains(videoId) || task.isCanceled) {
          _canceledVideoIds.remove(videoId);
          if (!task.completer.isCompleted) {
            task.completer
                .complete(const Left(DownloadFailure('Download canceled')));
          }
          continue;
        }

        if (_activeDownloads.containsKey(videoId)) {
          _activeDownloads[videoId]!.completer.future.then((res) {
            if (!task.completer.isCompleted) {
              task.completer.complete(res);
            }
          }, onError: (Object e, StackTrace st) {
            if (!task.completer.isCompleted) {
              task.completer.completeError(e, st);
            }
          });
          continue;
        }

        _startTaskExecution(task);
      }
      _stopForegroundServiceIfIdle();
    } finally {
      _processing =
          false; // FIX-A03: Reset flag when queue processing turn completes
    }
  }

  void _startTaskExecution(_QueuedDownload task) {
    final videoId = task.song.remoteId!;
    _activeDownloads[videoId] = task;
    _executeDownload(task).then((result) {
      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }
    }).catchError((e) {
      if (!task.completer.isCompleted) {
        task.completer.complete(Left(DownloadFailure('Download error: $e')));
      }
    }).whenComplete(() {
      _activeDownloads.remove(videoId);
      if (_queue.isNotEmpty) {
        Future.microtask(_processQueue);
      } else {
        _stopForegroundServiceIfIdle();
      }
    });
  }

  /// Returns a failure when the current network policy forbids downloading, or
  /// null when the transfer may proceed.
  ///
  /// Shared by the pre-queue gate in [DownloadRepositoryImpl] and the
  /// execution-time check in [_executeDownload], so the decision is made from a
  /// single place. Previously the repository admitted tasks and this service
  /// only rejected them once a slot had been consumed.
  Future<AppFailure?> downloadPolicyBlock() async {
    final prefs = await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      return const DownloadFailure('Offline Only Mode is active in Settings');
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        return const DownloadFailure(
            'Wi-Fi Only Mode is active. Connect to Wi-Fi to download.');
      }
    }
    return null;
  }

  Future<Result<int>> _executeDownload(_QueuedDownload task) async {
    final song = task.song;
    final videoId = song.remoteId!;
    final onProgress = task.onProgress;

    final policyBlock = await downloadPolicyBlock();
    if (policyBlock != null) {
      return Left(policyBlock);
    }

    File? temp;
    File? tempArt;
    Future<String?>? artworkFuture;
    try {
      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.resolving));
      ErrorLogger.addBreadcrumb('Download resolving: $videoId',
          category: 'download', data: {'videoId': videoId});

      // 1. Ensure PoToken attestation is fresh before requesting stream
      await _ytmService.ensurePoTokenReady();

      final prefs = await SharedPreferences.getInstance();
      final quality = resolveDownloadQuality(
        override: task.quality,
        downloadQuality: prefs.getString('setting_download_quality'),
        streamingQuality: prefs.getString('setting_streaming_quality'),
      );
      final dir = await getTemporaryDirectory();
      // Download high-res master artwork in parallel with stream resolution
      final rawArtUrl = song.remoteArtworkUrl;
      if (rawArtUrl != null && rawArtUrl.isNotEmpty) {
        final artUrl = CachedArtwork.upgradeToHighResArtwork(rawArtUrl);
        artworkFuture = Future(() async {
          final artFile = File(p.join(dir.path, 'ytdl_art_$videoId.jpg'));
          for (var attempt = 1; attempt <= 2; attempt++) {
            try {
              if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
                return null;
              }
              await _downloadFileResilient(artUrl, artFile, task, null);
              if (await artFile.exists() && await artFile.length() > 0) {
                tempArt = artFile;
                return artFile.path;
              }
            } catch (e) {
              ErrorLogger.log('Artwork download attempt $attempt failed',
                  error: e, category: 'YTM');
              if (attempt < 2) {
                await Future.delayed(const Duration(seconds: 1));
              }
            }
          }
          return null;
        });
      }

      var stream = await _resolveDownloadStream(videoId, quality);

      // Pre-download storage check (BUG-06)
      try {
        final freeBytes =
            await _downloadChannel.invokeMethod<int>('getFreeDiskSpace');
        if (freeBytes != null && freeBytes > 0) {
          // F3: see [requiredPreflightBytes].
          final requiredSpace = requiredPreflightBytes(stream);
          const minSafetyBytes = 100 * 1024 * 1024; // 100MB minimum buffer
          if (freeBytes < minSafetyBytes || freeBytes < requiredSpace) {
            return const Left(
                DownloadFailure('Insufficient storage space for download'));
          }
        }
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }

      var ext = safeExtension(stream.container);
      temp = File(p.join(dir.path, 'ytdl_$videoId.$ext'));

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0));
      ErrorLogger.addBreadcrumb('Download started: $videoId container=$ext',
          category: 'download', data: {'videoId': videoId, 'ext': ext});

      // Mirror progress into the foreground notification so the user can see it
      // with the app closed — the whole point of running the service.
      void reportProgress(YtDownloadProgress p) {
        onProgress?.call(p);
        if (p.stage == YtDownloadStage.downloading) {
          // F5: byte progress reaching 1.0 does NOT mean the job is finished —
          // tagging, saving and indexing still run — and the foreground service
          // treats `progress == 100` as "remove this job, and stop the service
          // if it was the last one". Reporting 1.0 here tore the ongoing
          // notification (and its Resume action) down a few hundred
          // milliseconds early, so hold at 99 until the `done` stage.
          final capped = p.fraction?.clamp(0.0, 0.99);
          _publishForegroundProgress(videoId, song.title, capped);
        }
      }

      // 2. Download audio with transparent 403 re-resolution & resume (206 verified)
      stream = await _downloadAudioWithRetry(
        stream: stream,
        videoId: videoId,
        quality: quality,
        dest: temp,
        task: task,
        onProgress: reportProgress,
      );

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      // Download integrity verification (BUG-12)
      if (!await temp.exists()) {
        return const Left(DownloadFailure('Downloaded file was not created'));
      }
      final tempSize = await temp.length();
      if (tempSize < 1024) {
        return const Left(
            DownloadFailure('Downloaded audio file is corrupt or incomplete'));
      }
      // A body served without a Content-Length cannot be size-checked against
      // the response, so check it against what the stream said it was. Below
      // half the expected bytes the transfer was truncated, and committing it
      // produced a track that plays for twenty seconds and stops.
      final expectedBytes = estimateBytes(stream);
      if (stream.duration.inSeconds > 0 && tempSize < expectedBytes ~/ 2) {
        return Left(DownloadFailure(
            'Download incomplete: ${tempSize ~/ 1024}KB of ~${expectedBytes ~/ 1024}KB'));
      }

      // The container has to be read from the bytes, not taken on trust. A URL
      // cache entry written by the playback path carries no YtmStream, so its
      // container was *guessed* from the URL and defaulted to m4a — which wrote
      // WebM/Opus bytes into a .m4a and then handed them to the MP4 tagger.
      var mimeType = stream.mimeType;
      final sniffed = await _sniffContainer(temp);
      if (sniffed != null) {
        mimeType = sniffed.mime;
        final sniffedExt = safeExtension(sniffed.ext);
        if (sniffedExt != ext) {
          ErrorLogger.addBreadcrumb(
              'Download container corrected: $ext → ${sniffed.ext}',
              category: 'download',
              data: {'videoId': videoId});
          ext = sniffedExt;
          File? renamed;
          try {
            renamed = await temp.rename(p.join(dir.path, 'ytdl_$videoId.$ext'));
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          if (renamed != null) temp = renamed;
        }
      }

      // 3. Tagging — artwork embed + tag standardization (TagEditorPlugin) & lyrics fetch
      String? lrcText;
      try {
        final lyricsRepo = getIt.isRegistered<LyricsRepository>()
            ? getIt<LyricsRepository>()
            : null;
        if (lyricsRepo != null) {
          lrcText = await lyricsRepo
              .fetchLyricsLrc(
                title: song.title,
                artist: song.artist,
                album: song.album,
                durationMs: song.durationMs,
                videoId: videoId,
              )
              .timeout(const Duration(seconds: 8));
        }
      } catch (e, st) {
        ErrorLogger.log('Download lyrics lookup non-critical failure: $videoId',
            error: e, stackTrace: st, category: 'download');
      }

      var embeddedLyrics = false;
      if (DownloadService.carriesTags(ext)) {
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.tagging));
        ErrorLogger.addBreadcrumb('Download tagging: $videoId',
            category: 'download');
        final artPath = artworkFuture != null ? await artworkFuture : null;
        embeddedLyrics =
            await _tag(temp.path, song, artworkPath: artPath, lyrics: lrcText);
      }

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.saving));
      ErrorLogger.addBreadcrumb('Download saving to MediaStore: $videoId',
          category: 'download', data: {'videoId': videoId});
      // sanitizeFilename, not _sanitize: the hardened version caps the name at
      // 180 *bytes* and dodges the Windows reserved device names. Capping at 120
      // characters let a CJK or emoji title exceed the filesystem's byte limit
      // and MediaStore refused the insert with an opaque failure.
      final displayName = sanitizeFilename(song.artist, song.title, ext);
      final saved =
          await _downloadChannel.invokeMethod<Object?>('saveToMusic', {
        'sourcePath': temp.path,
        'displayName': displayName,
        'title': song.title,
        'mimeType': mimeType,
      });
      // New platform builds return {path, contentUri}; older ones returned the
      // path directly, so accept both while the Kotlin side rolls forward.
      final finalPath = saved is Map
          ? saved['path']?.toString()
          : (saved is String ? saved : null);
      final contentUri = saved is Map ? saved['contentUri']?.toString() : null;
      if (finalPath == null || finalPath.isEmpty) {
        return const Left(DownloadFailure('MediaStore did not return a path'));
      }
      _rememberDownloadedPath(videoId, finalPath, contentUri: contentUri);

      // If container does not support embedded tags or embedding failed, save sidecar .lrc
      if ((!embeddedLyrics || !DownloadService.carriesTags(ext)) &&
          lrcText != null &&
          lrcText.trim().isNotEmpty) {
        await DownloadService.writeSidecarLrc(finalPath, lrcText);
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
      ErrorLogger.addBreadcrumb('Download indexing: $videoId',
          category: 'download', data: {'path': finalPath});
      final realBitrate = stream.bitrateKbps > 0
          ? stream.bitrateKbps
          : (quality == 'low'
              ? 64
              : quality == 'medium'
                  ? 128
                  : 160);
      final realCodec = mimeType.contains('webm') ||
              mimeType.contains('opus') ||
              ext == 'webm'
          ? 'OPUS'
          : 'AAC';
      final reconciled = await _repository.reconcileDownloadedSong(
        oldId: song.id,
        newPath: finalPath,
        fallbackSong: song.copyWith(
          bitrateKbps: Value(realBitrate),
          codec: Value(realCodec),
          sampleRate: Value(realCodec == 'OPUS' ? 48000 : 44100),
        ),
      );

      // FIX: Downloaded song repeated twice — full rescan after reconcile creates duplicate path row
      // The file is already indexed via reconcile (old YTM row → local). Triggering a full MediaStore scan
      // inserts a second row with the new MediaStore id for the same file path, causing the double entry
      // on local. Do not rescan the whole library here; deduplication is handled inside reconcile.
      // If needed, a lightweight single-file rescan can be done, but the reconciled row is sufficient.

      final result = reconciled.fold(
        (f) => Left<AppFailure, int>(f),
        (newId) {
          if (newId == null) {
            ErrorLogger.log('Download indexing missing library row: $videoId',
                category: 'download');
            return const Left<AppFailure, int>(DownloadFailure(
                'Downloaded file was not found in the library'));
          }
          onProgress?.call(const YtDownloadProgress(YtDownloadStage.done, 1));
          // F5: the only place allowed to report a finished transfer to the
          // foreground service, now that the byte progress is capped at 99.
          _publishForegroundProgress(videoId, song.title, 1);
          ErrorLogger.addBreadcrumb('Download done: $videoId',
              category: 'download', data: {'newId': newId});
          return Right<AppFailure, int>(newId);
        },
      );
      return result;
    } on YtmException catch (e) {
      final classified = YtmErrorClassifier.classify(e);
      ErrorLogger.log(
          'YTM download YtmException: ${e.code} → ${classified.message}',
          error: e,
          category: 'download');
      if (e.isBotBlocked) {
        return Left(DownloadFailure(
          classified.message,
          e,
        ));
      }
      return Left(DownloadFailure(
        e.isNetwork ? 'No connection while downloading' : classified.message,
        e,
      ));
    } on PlatformException catch (e) {
      ErrorLogger.log('YT download native call failed: ${e.code}',
          error: e, category: 'YTM');
      return Left(
          DownloadFailure(e.message ?? 'Failed to save the download', e));
    } catch (e, st) {
      ErrorLogger.log('YT download failed',
          error: e, stackTrace: st, category: 'YTM');
      return Left(DownloadFailure('Download failed: $e', e));
    } finally {
      _canceledVideoIds.remove(videoId);
      if (artworkFuture != null) {
        try {
          final resolvedArtPath = await artworkFuture;
          if (resolvedArtPath != null) {
            final resolvedArtFile = File(resolvedArtPath);
            if (await resolvedArtFile.exists()) {
              await resolvedArtFile.delete().catchError((_) => resolvedArtFile);
            }
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
      if (temp != null) {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
      if (tempArt != null) {
        try {
          if (await tempArt!.exists()) {
            await tempArt!.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
      _lastForegroundPublishMs.remove(videoId);
    }
  }

  Future<YtmStream> resolveDownloadStream(String videoId,
      [String quality = 'high', bool forceRefresh = false]) async {
    if (forceRefresh && getIt.isRegistered<YtmUrlCache>()) {
      // Nothing used to evict the entry, so the "transparent re-resolution"
      // after a 403 read the same dead URL straight back out of the cache and
      // retried it until the attempts ran out.
      getIt<YtmUrlCache>().invalidate(videoId);
    }

    // Remote backend decommissioned: native resolution only.
    // Prefer M4A (AAC) for downloads: universally supported by all music players & car stereos,
    // enables metadata/cover-art embedding, and avoids Android MediaStore .webm.oga mangling.
    final native = await _ytmService.resolveStream(videoId,
        quality: quality, forceRefresh: forceRefresh, preferM4a: true);
    final resolved = native.withResolvedExpiry();
    _resolvedStreams[videoId] =
        resolved; // FIX-A05/C05: Store resolved stream for duration lookup
    if (_resolvedStreams.length > _maxResolvedStreams) {
      // F12: drop the oldest ids rather than growing for the process lifetime.
      for (final id in _resolvedStreams.keys
          .take(_resolvedStreams.length - _maxResolvedStreams)
          .toList()) {
        _resolvedStreams.remove(id);
      }
    }
    return resolved;
  }

  Future<YtmStream> _resolveDownloadStream(String videoId, String quality,
          {bool forceRefresh = false}) =>
      resolveDownloadStream(videoId, quality, forceRefresh);

  /// Downloads the audio into [dest], re-resolving when the URL is the problem.
  /// Returns the stream the bytes actually came from — its container decides the
  /// file extension, the MIME type and whether the MP4 tagger may run.
  Future<YtmStream> _downloadAudioWithRetry({
    required YtmStream stream,
    required String videoId,
    required String quality,
    required File dest,
    required _QueuedDownload task,
    required void Function(YtDownloadProgress)? onProgress,
  }) async {
    var currentStream = stream;
    var attempts = 0;
    // 5 attempts: transient blips (dropped socket, 5xx, timeout) are common
    // on mobile, and the repository adds its own outer retries on top.
    const maxAttempts = 5;

    while (true) {
      try {
        if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
          throw const DownloadFailure('Download canceled');
        }

        // Re-resolve anything that cannot survive the whole transfer. The
        // 5-minute playback default was the wrong bar for a download: a long
        // track on a slow link outlived it and died at 403 mid-file.
        if (currentStream.isExpiringSoon(requiredLifetime(currentStream))) {
          debugPrint(
              '[YtDownloadService] Stream for $videoId cannot outlive the download, re-resolving...');
          currentStream = await _resolveDownloadStream(videoId, quality,
              forceRefresh: true);
        }

        await _downloadFileResilient(
          currentStream.url,
          dest,
          task,
          onProgress,
          userAgent: currentStream.userAgent,
          cookies: currentStream.cookies,
          expectedBytes: estimateBytes(currentStream),
          container: currentStream.container,
        );
        return currentStream;
      } catch (e) {
        attempts++;
        debugPrint(
            '[YtDownloadService] Download attempt $attempts failed for $videoId: $e');

        if (e is FileSystemException ||
            e is StorageFailure ||
            attempts >= maxAttempts ||
            task.isCanceled ||
            _canceledVideoIds.contains(videoId)) {
          rethrow;
        }

        // 429 → honour Retry-After (capped by the limiter) before anything else,
        // and tell the shared limiter: this is googlevideo answering *this*
        // device, so the native bucket is exactly the right one to cool down.
        if (e is YtmException &&
            (e.code == 'YTM_429' ||
                e.details?.contains('Retry-After') == true)) {
          final retryMatch =
              RegExp(r'Retry-After:\s*(\d+)').firstMatch(e.details ?? '');
          final retrySec =
              retryMatch != null ? int.tryParse(retryMatch.group(1)!) : null;
          YtmRateLimiter.shared.onRateLimited(retrySec);
          final backoff = YtmRateLimiter.shared.cooldownRemaining;
          await Future.delayed(backoff > Duration.zero
              ? backoff
              : Duration(
                  milliseconds:
                      (1000 * (1 << (attempts - 1))).clamp(1000, 15000)));
        }

        if (!YtmErrorClassifier.isUrlBurned(e)) {
          // A dropped connection, not a refusal: the URL still works and the
          // bytes already on disk are still valid, so the retry resumes from
          // them. Re-resolving here threw a good URL away and — because the
          // next lines used to run unconditionally — invalidated a working
          // poToken and paid for a fresh BotGuard round every time a socket
          // hiccuped.
          await Future.delayed(Duration(
              milliseconds: (400 * (1 << (attempts - 1))).clamp(400, 8000)));
          continue;
        }

        // Burned URL: honour any active rate-limit cooldown BEFORE
        // re-resolving, otherwise the fresh resolve fails fast against the
        // cooldown and burns through all attempts in milliseconds — the
        // "first N succeed, rest fail instantly" batch pattern.
        final cooldown = YtmRateLimiter.shared.cooldownRemaining;
        if (cooldown > Duration.zero) {
          // Cap the wait so one 429 doesn't wedge a slot for minutes; the
          // outer repository retry covers longer blocks.
          final wait = cooldown <= const Duration(seconds: 30)
              ? cooldown
              : const Duration(seconds: 30);
          await Future.delayed(wait);
          if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
            rethrow;
          }
        } else if (_ytmService.isBotCoolingDown) {
          // Egress/bot block with no rate-limiter window: back off briefly so
          // the re-resolve below doesn't slam straight into the fail-fast.
          await Future.delayed(Duration(
              milliseconds: (1000 * (1 << (attempts - 1))).clamp(1000, 8000)));
          if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
            rethrow;
          }
        }

        final signal = YtmErrorClassifier.classify(e).signal;
        if (signal == YtmBlockSignal.botChallenge ||
            signal == YtmBlockSignal.poTokenInvalid) {
          await _ytmService.invalidatePoToken();
          await _ytmService.ensurePoTokenReady();
        }
        currentStream =
            await _resolveDownloadStream(videoId, quality, forceRefresh: true);
      }
    }
  }

  Future<void> _downloadFileResilient(
    String url,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    int? expectedBytes,
    String? container,
  }) async {
    final uri = Uri.parse(url);
    int total = -1;
    var rangesSupported = false;

    // The probe is allowed to fail — a server that dislikes `bytes=0-0` still
    // serves the whole body — but the transfer that follows is not. Both used to
    // sit in this one `try`, so a StorageFailure or a dropped socket four chunks
    // into the parallel download was swallowed and answered by re-downloading
    // the entire file sequentially: on a full disk, twice the writing for the
    // same ENOSPC, and on a flaky link, no resume and no error the caller could
    // classify.
    try {
      final probeReq = await _http.openUrl('GET', uri);
      YtDownloadTransferPolicy.applyHeaders(probeReq, userAgent,
          cookies: cookies, range: 'bytes=0-0');
      final probeResp =
          await probeReq.close().timeout(const Duration(seconds: 20));

      final acceptRanges =
          probeResp.headers.value(HttpHeaders.acceptRangesHeader);
      final contentRange =
          probeResp.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null && contentRange.contains('/')) {
        total = int.tryParse(contentRange.split('/').last) ?? -1;
      }
      if (total <= 0 && probeResp.contentLength > 0) {
        total = probeResp.contentLength;
      }
      await probeResp.drain<void>();

      if (probeResp.statusCode == HttpStatus.forbidden ||
          probeResp.statusCode == HttpStatus.unauthorized) {
        throw YtmException(
            'YTM_BOT_BLOCKED', 'HTTP ${probeResp.statusCode} on stream probe');
      }

      rangesSupported = probeResp.statusCode == HttpStatus.partialContent &&
          acceptRanges != 'none';
    } catch (e) {
      if (e is YtmException || e is DownloadFailure) rethrow;
      debugPrint(
          '[YtDownloadService] Range probe failed ($e); using a single request');
    }

    if (rangesSupported &&
        total >= YtDownloadTransferPolicy.minChunkThreshold) {
      await _downloadParallel(uri, dest, total, task, onProgress,
          userAgent: userAgent, cookies: cookies, container: container);
      return;
    }

    await _downloadSequential(uri, dest, task, onProgress,
        userAgent: userAgent,
        cookies: cookies,
        expectedBytes: expectedBytes,
        container: container);
  }

  Future<void> _downloadParallel(
    Uri uri,
    File dest,
    int total,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    String? container,
  }) async {
    if (total < YtDownloadTransferPolicy.minChunkThreshold) {
      await _downloadSequential(uri, dest, task, onProgress,
          userAgent: userAgent,
          cookies: cookies,
          expectedBytes: total,
          container: container);
      return;
    }

    final stopwatch = Stopwatch()..start();
    double throughputMbps = 10.0;
    try {
      if (getIt.isRegistered<AdaptiveBufferEngine>()) {
        throughputMbps = getIt<AdaptiveBufferEngine>().averageNetworkSpeedMbps;
      }
    } catch (_) {}
    final concurrentChunks = YtDownloadTransferPolicy.optimalChunkCount(
      total,
      throughputMbps: throughputMbps,
    );
    final chunkSize = (total / concurrentChunks).ceil();
    final tempParts = <File>[];
    final dir = dest.parent;
    final stamp = File('${dest.path}.parts');

    // Parts left behind by an earlier attempt are reusable only if they were
    // written for a body of exactly this size and container: `total` fixes
    // every chunk boundary, and a retry that re-resolves to a different format
    // (webm where the first attempt got m4a) carries different bytes at the
    // same offsets. Identity is not the URL, so a 403 re-resolution of the
    // same body still resumes. The legacy `'$total'` stamp is deliberately not
    // accepted: it cannot prove the container matches.
    final expectedStamp = resumeStampFor(
        container: container ?? 'bin',
        expectedBytes: total,
        videoId: task.song.remoteId);
    var resumable = false;
    try {
      if (await stamp.exists()) {
        final existing = (await stamp.readAsString()).trim();
        resumable = existing == expectedStamp;
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
    try {
      await stamp.writeAsString(expectedStamp, flush: true);
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }

    final chunkReceived = List<int>.filled(concurrentChunks, 0);
    var baseReceived = 0;
    var lastEmitTime = 0;
    var mergeCompleted = false;
    var keepParts = false;

    try {
      // FIX-A02: Outer try to catch _RangeIgnored outside the inner try/finally
      try {
        try {
          final freeBytes =
              await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
          // Peak usage is twice the body: the four parts all exist while the
          // merged copy is being written. Checking against `total` alone let a
          // download start with just enough room for the parts and hit ENOSPC
          // halfway through the merge, which threw away the whole transfer.
          if (freeBytes > 0 && freeBytes < total * 2) {
            throw const DownloadFailure('Insufficient storage space');
          }
        } catch (e) {
          if (e is DownloadFailure) rethrow;
        }

        final futures = <Future<void>>[];

        for (var i = 0; i < concurrentChunks; i++) {
          final chunkIndex = i;
          final start = i * chunkSize;
          final end =
              (i == concurrentChunks - 1) ? total - 1 : (start + chunkSize - 1);
          if (start >= total) break;

          final partFile =
              File(p.join(dir.path, '${p.basename(dest.path)}.part$i'));
          tempParts.add(partFile);

          futures.add(() async {
            final expectedSize = end - start + 1;
            var have = 0;
            try {
              if (await partFile.exists()) {
                have = resumable ? await partFile.length() : 0;
                // Longer than its slot means the part was written for different
                // boundaries; there is nothing safe to keep.
                if (have > expectedSize) have = 0;
                if (have == 0) await partFile.delete();
              }
            } catch (_) {
              have = 0;
            }
            chunkReceived[chunkIndex] = have;
            baseReceived += have;
            // Already complete from an earlier attempt. Asking anyway would send
            // `bytes=${end + 1}-$end` and come back 416.
            if (have == expectedSize) return;

            if (task.isCanceled ||
                _canceledVideoIds.contains(task.song.remoteId)) {
              throw const DownloadFailure('Download canceled');
            }

            final req = await _http.getUrl(uri);
            YtDownloadTransferPolicy.applyHeaders(req, userAgent,
                cookies: cookies, range: 'bytes=${start + have}-$end');
            final resp = await req.close().timeout(_stallTimeout);

            if (resp.statusCode == 429) {
              final retryAfter =
                  resp.headers.value(HttpHeaders.retryAfterHeader);
              final retrySec = int.tryParse(retryAfter ?? '');
              await resp.drain<void>();
              throw YtmException('YTM_429',
                  'HTTP 429 Rate limited${retrySec != null ? ' Retry-After: $retrySec' : ''}');
            }
            if (resp.statusCode == HttpStatus.forbidden ||
                resp.statusCode == HttpStatus.unauthorized) {
              await resp.drain<void>();
              throw YtmException('YTM_BOT_BLOCKED',
                  'HTTP ${resp.statusCode} on chunk $chunkIndex');
            }
            // A 200 to a ranged request means the whole body is coming: written
            // into this part it is neither the chunk that was asked for nor a
            // resume, so the transfer goes to the sequential path instead of
            // merging four copies of the same file.
            if (resp.statusCode == HttpStatus.ok) {
              await resp.drain<void>();
              throw const _RangeIgnored();
            }
            if (resp.statusCode != HttpStatus.partialContent) {
              await resp.drain<void>();
              throw DownloadFailure(
                  'HTTP ${resp.statusCode} for chunk $chunkIndex');
            }

            final sink = partFile.openWrite(
                mode: have > 0 ? FileMode.append : FileMode.write);
            try {
              // Per-event watchdog. A googlevideo edge that accepts the request
              // and then stops sending used to hang the download until the OS
              // gave up minutes later, with the notification frozen at whatever
              // percentage it had reached and no retry ever attempted.
              await for (final chunk in resp.timeout(_stallTimeout)) {
                if (task.isCanceled ||
                    _canceledVideoIds.contains(task.song.remoteId)) {
                  throw const DownloadFailure('Download canceled');
                }
                try {
                  sink.add(chunk);
                } on FileSystemException catch (e) {
                  final m = e.message.toLowerCase();
                  if (m.contains('no space') ||
                      m.contains('enospc') ||
                      e.osError?.errorCode == 28) {
                    throw const StorageFailure(
                        'Storage full while writing chunk');
                  }
                  rethrow;
                }
                chunkReceived[chunkIndex] += chunk.length;
                final totalReceived = chunkReceived.reduce((a, b) => a + b);
                if (onProgress != null && total > 0) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (now - lastEmitTime > 80 || totalReceived >= total) {
                    lastEmitTime = now;
                    final elapsedSeconds =
                        stopwatch.elapsedMilliseconds / 1000.0;
                    final movedThisAttempt =
                        (totalReceived - baseReceived).clamp(0, total);
                    final speedKbps = elapsedSeconds > 0
                        ? (movedThisAttempt / elapsedSeconds) / 1024.0
                        : 0.0;
                    final fraction = (totalReceived / total).clamp(0.0, 1.0);
                    final remainingBytes =
                        (total - totalReceived).clamp(0, total);
                    final etaSeconds = (speedKbps > 0 && remainingBytes > 0)
                        ? (remainingBytes / (speedKbps * 1024.0)).round()
                        : null;

                    onProgress(YtDownloadProgress(
                      YtDownloadStage.downloading,
                      fraction,
                      speedKbps,
                      etaSeconds,
                    ));
                  }
                }
              }
              await sink.flush();
              final totalBytes = chunkReceived.reduce((a, b) => a + b);
              _sampleThroughput(totalBytes, stopwatch.elapsed);
            } on FileSystemException catch (e) {
              final m = e.message.toLowerCase();
              if (m.contains('no space') ||
                  m.contains('enospc') ||
                  e.osError?.errorCode == 28) {
                throw const StorageFailure('Storage full while writing chunk');
              }
              rethrow;
            } finally {
              await sink.close();
            }
          }());
        }

        await Future.wait(futures);

        // Check cancellation BEFORE merge to prevent corrupt file
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }

        // Verify total received byte sum and chunk file integrity
        if (total > 0) {
          final totalReceivedBytes = chunkReceived.reduce((a, b) => a + b);
          if (totalReceivedBytes != total) {
            throw DownloadFailure(
                'Parallel download byte mismatch: received $totalReceivedBytes, expected $total');
          }
          final chunkCount = tempParts.length;
          for (int i = 0; i < chunkCount; i++) {
            final part = tempParts[i];
            if (!await part.exists()) {
              throw DownloadFailure('Chunk $i file missing after download');
            }
            final partSize = await part.length();
            final expectedSize = (i == chunkCount - 1)
                ? total - (chunkSize * (chunkCount - 1))
                : chunkSize;
            if (partSize != expectedSize) {
              throw DownloadFailure(
                  'Chunk $i incomplete: $partSize/$expectedSize bytes');
            }
          }
        }

        // Final cancellation check right before merge
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }

        final outPartFile = File('${dest.path}.part');
        final outSink = outPartFile.openWrite();
        try {
          for (final part in tempParts) {
            if (task.isCanceled ||
                _canceledVideoIds.contains(task.song.remoteId)) {
              throw const DownloadFailure('Download canceled');
            }
            if (await part.exists()) {
              await outSink.addStream(part.openRead());
            }
          }
          await outSink.flush();
        } finally {
          await outSink.close();
        }

        // Verify merged total size and atomically rename (BUG-014)
        if (total > 0) {
          final finalSize = await outPartFile.length();
          if (finalSize != total) {
            await outPartFile.delete().catchError((_) => outPartFile);
            throw DownloadFailure(
                'Merged file size mismatch: $finalSize/$total');
          }
        }
        if (await outPartFile.exists()) {
          if (await dest.exists()) {
            await dest.delete();
          }
          await outPartFile.rename(dest.path);
        }
        mergeCompleted = true;
      } catch (e) {
        if (e is _RangeIgnored) {
          rethrow; // FIX-A02: Bubble _RangeIgnored to outer catch
        }
        keepParts = _partsWorthKeeping(e);
        rethrow;
      } finally {
        final outPartFile = File('${dest.path}.part');
        try {
          if (await outPartFile.exists()) {
            await outPartFile.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }

        // Parts used to be deleted unconditionally, so a cancel or a single
        // dropped socket at 95% threw away every byte of all four chunks and the
        // next attempt started from zero.
        if (mergeCompleted || !keepParts) {
          for (final part in tempParts) {
            try {
              if (await part.exists()) {
                await part.delete();
              }
            } catch (_) {
              // Best-effort: failure intentionally ignored on this non-critical path.
            }
          }
          try {
            if (await stamp.exists()) {
              await stamp.delete();
            }
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
        }

        if (!mergeCompleted) {
          try {
            if (await dest.exists()) {
              await dest.delete();
            }
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
        }
      }
    } on _RangeIgnored {
      // A server that ignores Range mid-transfer leaves `.part0..3` full-body
      // duplicates and a `.parts` stamp that do not describe the sequential
      // retry's output. Sweep them before it runs so the committed file is the
      // only artifact left behind (deleting an already-removed file is a
      // no-op, and this stays correct even if the inner finally changes).
      for (final part in tempParts) {
        try {
          if (await part.exists()) {
            await part.delete();
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
      }
      try {
        if (await stamp.exists()) {
          await stamp.delete();
        }
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
      debugPrint(
          '[YtDownloadService] Server ignored Range mid-transfer; retrying as a single request');
      await _downloadSequential(uri, dest, task, onProgress,
          userAgent: userAgent,
          cookies: cookies,
          expectedBytes: total,
          container: container);
    }
  }

  /// Whether the `.partN` files already on disk are worth keeping after [e].
  ///
  /// A cancel, a dropped socket or a refused URL leave every byte written so
  /// far valid — the next attempt resumes from them, and the `.parts` stamp
  /// guards against resuming into a differently-sized format. A size or
  /// integrity mismatch means the bytes themselves are suspect, and a full disk
  /// is only made worse by holding on to them.
  static bool _partsWorthKeeping(Object e) {
    // Range-ignored means the `.partN` files hold whole-body duplicates, not
    // the ranged chunks; nothing in them can be resumed or merged.
    if (e is _RangeIgnored) return false;
    if (e is StorageFailure) return false;
    if (e is DownloadFailure) {
      final m = e.message.toLowerCase();
      return !m.contains('mismatch') &&
          !m.contains('incomplete') &&
          !m.contains('missing');
    }
    return true;
  }

  Future<void> _downloadSequential(
    Uri uri,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    int? expectedBytes,
    String? container,
    bool allowResume = true,
    int retryCount = 0, // FIX-A01: Add retryCount parameter (max 1)
  }) async {
    final stopwatch = Stopwatch()..start();
    final partFile = File('${dest.path}.part');
    // F6: a `.part` is only resumable against the same body that wrote it. The
    // stamp identifies container + expected size rather than the URL, so a
    // re-resolved (freshly signed) URL for the same body resumes, while a
    // quality/format change does not.
    final stampFile = File('${dest.path}.part.stamp');
    final resumeStamp = YtDownloadTransferMath.resumeStampFor(
        container: container ?? 'bin',
        expectedBytes: expectedBytes,
        videoId: task.song.remoteId);
    int resumeOffset = 0;
    try {
      if (await partFile.exists()) {
        resumeOffset = allowResume ? await partFile.length() : 0;
        var stampMatches = false;
        try {
          if (await stampFile.exists()) {
            stampMatches =
                resumeStampMatches(await stampFile.readAsString(), resumeStamp);
          }
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        if (resumeOffset > 0 && !stampMatches) {
          // Written for a different body, or by a build without the stamp:
          // nothing in it is known to line up, so start over.
          try {
            await partFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          resumeOffset = 0;
        }
        // Keep resume only if meaningful (>64k) to avoid overhead for tiny partials
        if (resumeOffset < 64 * 1024) {
          try {
            await partFile.delete();
          } catch (_) {
            // Best-effort: failure intentionally ignored on this non-critical path.
          }
          resumeOffset = 0;
        }
      }
      try {
        await stampFile.writeAsString(resumeStamp, flush: true);
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    } catch (_) {
      resumeOffset = 0;
    }

    final request = await _http.openUrl('GET', uri);
    if (resumeOffset > 0) {
      YtDownloadTransferPolicy.applyHeaders(request, userAgent,
          cookies: cookies, range: 'bytes=$resumeOffset-');
    } else {
      YtDownloadTransferPolicy.applyHeaders(request, userAgent,
          cookies: cookies);
    }
    final response = await request.close().timeout(_stallTimeout);

    // 429 / Retry-After aware backoff + jitter integration
    if (response.statusCode == 429) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      final retrySec = int.tryParse(retryAfter ?? '');
      // Drain body before throwing so connection reused
      await response.drain<void>();
      throw YtmException('YTM_429',
          'HTTP 429 Too Many Requests${retrySec != null ? ' Retry-After: $retrySec' : ''}');
    }
    if (response.statusCode == HttpStatus.forbidden ||
        response.statusCode == HttpStatus.unauthorized) {
      await response.drain<void>();
      throw YtmException(
          'YTM_BOT_BLOCKED', 'HTTP ${response.statusCode} on stream request');
    }

    // Resume correctness: if we sent Range, server MUST reply 206. A 200 means it ignored Range
    // → appending would corrupt file. Discard stale part and restart.
    if (resumeOffset > 0) {
      if (response.statusCode == HttpStatus.ok) {
        await response.drain<void>();
        try {
          await partFile.delete();
        } catch (_) {
          // Best-effort: failure intentionally ignored on this non-critical path.
        }
        // FIX-A01: On second occurrence, throw DownloadFailure('Server does not support resume')
        if (retryCount >= 1) {
          throw const DownloadFailure('Server does not support resume');
        }
        // Retry from scratch with incremented retryCount
        return _downloadSequential(uri, dest, task, onProgress,
            userAgent: userAgent,
            cookies: cookies,
            expectedBytes: expectedBytes,
            container: container,
            allowResume: false,
            retryCount: retryCount + 1); // FIX-A01
      }
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw DownloadFailure('HTTP ${response.statusCode} on resume');
      }
    } else {
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw DownloadFailure('HTTP ${response.statusCode} on stream request');
      }
    }

    // Determine total expected size for atomic commit verification
    final total = response.contentLength; // remaining bytes
    // If resumed, total via Content-Range: bytes start-end/total
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    int? expectedFinalSize;
    if (contentRange != null && contentRange.contains('/')) {
      expectedFinalSize = int.tryParse(contentRange.split('/').last);
    } else if (total > 0) {
      expectedFinalSize = resumeOffset + total;
    }
    // Fallback: if server gave contentLength as full size even for 206, handle
    if (resumeOffset > 0 && total > 0 && expectedFinalSize == null) {
      expectedFinalSize = resumeOffset + total;
    }

    final sink = resumeOffset > 0
        ? partFile.openWrite(mode: FileMode.append)
        : partFile.openWrite();
    var received = resumeOffset;
    var lastEmitTime = 0;
    final baseReceived = resumeOffset;

    try {
      // Per-event watchdog, same as the chunked path: a stalled edge node used
      // to hold the transfer open indefinitely with the progress bar frozen.
      await for (final chunk in response.timeout(_stallTimeout)) {
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final effectiveTotal = expectedFinalSize ?? total;
          final fraction = effectiveTotal > 0
              ? (received / effectiveTotal).clamp(0.0, 1.0).toDouble()
              : null;
          if (now - lastEmitTime > 80 ||
              (effectiveTotal > 0 && received >= effectiveTotal)) {
            lastEmitTime = now;
            final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
            final speedKbps = elapsedSeconds > 0
                ? ((received - baseReceived) / elapsedSeconds) / 1024.0
                : 0.0;
            final remainingBytes =
                effectiveTotal > 0 ? effectiveTotal - received : 0;
            final etaSeconds = (speedKbps > 0 && remainingBytes > 0)
                ? (remainingBytes / (speedKbps * 1024.0)).round()
                : null;

            onProgress(YtDownloadProgress(
              YtDownloadStage.downloading,
              fraction,
              speedKbps,
              etaSeconds,
            ));
          }
        }
      }
      await sink.flush();
      _sampleThroughput(received - baseReceived, stopwatch.elapsed);
    } on FileSystemException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('no space') ||
          msg.contains('enospc') ||
          e.osError?.errorCode == 28) {
        throw const StorageFailure('Storage full while writing download');
      }
      rethrow;
    } finally {
      await sink.close();
    }

    if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
      // Keep .part for resume if partially downloaded; don't delete on cancel (pause semantics)
      throw const DownloadFailure('Download canceled');
    }

    // Atomic commit: verify size == expected, fsync, then rename
    if (await partFile.exists()) {
      final finalSize = await partFile.length();

      if (expectedFinalSize != null && expectedFinalSize > 0) {
        if (finalSize < expectedFinalSize) {
          // Keep the part: every byte in it is valid and the next attempt
          // resumes from here. The old check only fired when `total > 0`, so a
          // server that sent no length at all had its truncated body renamed
          // over `dest` and committed as a complete download.
          throw DownloadFailure(
              'Incomplete download: $finalSize/$expectedFinalSize bytes');
        }
        if (finalSize > expectedFinalSize) {
          // More bytes than the body holds: a resumed request was answered from
          // offset 0 and a second copy got appended. Nothing here is salvageable
          // and keeping it would only resume from a worse offset.
          await partFile.delete().catchError((_) => partFile);
          throw DownloadFailure(
              'Oversized download: $finalSize/$expectedFinalSize bytes');
        }
      } else if (expectedBytes != null &&
          expectedBytes > 0 &&
          finalSize < expectedBytes ~/ 2) {
        // Unknown-length body (`contentLength == -1` and no Content-Range): the
        // duration-derived estimate is the only bar available, and committing a
        // half-sized file as complete is worse than retrying.
        throw DownloadFailure(
            'Suspiciously small download: ${finalSize ~/ 1024}KB of ~${expectedBytes ~/ 1024}KB');
      }

      if (finalSize < 1024) {
        await partFile.delete().catchError((_) => partFile);
        throw const DownloadFailure('Downloaded file too small — corrupt');
      }
      // fsync before rename for durability (atomic commit)
      try {
        final raf = await partFile.open(mode: FileMode.append);
        await raf.flush();
        await raf.close();
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
      if (await dest.exists()) {
        await dest.delete();
      }
      await partFile.rename(dest.path);
      try {
        if (await stampFile.exists()) {
          await stampFile.delete();
        }
      } catch (_) {
        // Best-effort: failure intentionally ignored on this non-critical path.
      }
    }
  }

  /// Sweeps stale download scratch files while preserving active, queued and
  /// explicitly protected ids.
  Future<void> cleanOrphanPartFiles({
    Set<String>? activePartNames,
    Set<String>? protectedVideoIds,
  }) async {
    try {
      await YtDownloadArtifactStore.sweepOrphans(
        await getTemporaryDirectory(),
        busyVideoIds: {
          ..._activeDownloads.keys,
          ..._queue.map((t) => t.song.remoteId).whereType<String>(),
          ...?protectedVideoIds,
        },
        activePartNames: activePartNames,
      );
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  /// Removes every scratch file for [videoId].
  Future<void> deleteArtifactsFor(String videoId) async {
    if (videoId.isEmpty) return;
    // A live download owns its partial; deleting under it would leave the writer
    // appending to an unlinked handle and commit a truncated file.
    if (_activeDownloads.containsKey(videoId)) return;
    try {
      await YtDownloadArtifactStore.deleteFor(
          await getTemporaryDirectory(), videoId);
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }

  Future<bool> _tag(String path, SongsTableData song,
      {String? artworkPath, String? lyrics}) {
    return DownloadService.writeAudioTags(
      filePath: path,
      title: song.title,
      artist: song.artist,
      album: song.album.isNotEmpty ? song.album : 'Unknown Album',
      genre: song.genre,
      year: song.year,
      trackNumber: song.trackNumber ?? 1,
      artworkPath: artworkPath,
      lyrics: lyrics,
    );
  }

  /// F11: [ext] arrives from the resolver and from byte sniffing and is then
  /// interpolated straight into a file name, so it has to be a bare container
  /// extension and nothing that could carry a path separator or a traversal
  /// segment.
  static String safeExtension(String? ext) =>
      YtDownloadFileNaming.safeExtension(ext);

  static String sanitizeFilename(String artist, String title, String ext) =>
      YtDownloadFileNaming.sanitizeFilename(artist, title, ext);

  /// The container the bytes on disk actually are, or null for a header nothing
  /// recognises. The URL is not a trustworthy source; the bytes are.
  @visibleForTesting
  static ({String ext, String mime})? sniffContainerBytes(List<int> header) =>
      YtDownloadFileNaming.sniffContainerBytes(header);

  static Future<({String ext, String mime})?> _sniffContainer(File file) =>
      YtDownloadFileNaming.sniffContainer(file);

  void _sampleThroughput(int bytes, Duration elapsed) {
    try {
      if (getIt.isRegistered<AdaptiveBufferEngine>()) {
        getIt<AdaptiveBufferEngine>().sampleThroughput(bytes, elapsed);
      }
    } catch (_) {
      // Best-effort: failure intentionally ignored on this non-critical path.
    }
  }
}
