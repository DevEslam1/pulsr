// lib/core/services/yt_download_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart' show Value;
import '../../data/audio/adaptive_buffer_engine.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../constants/channels.dart';
import '../constants/embedded_browser_ua.dart';
import '../di/injection.dart';
import '../errors/failures.dart';
import '../errors/ytm_error_classifier.dart';
import '../utils/error_logger.dart';
import '../utils/ytm_rate_limiter.dart';
import '../widgets/cached_artwork.dart';
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
  bool isCanceled = false;

  _QueuedDownload({
    required this.song,
    required this.onProgress,
    required this.completer,
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
  static const _tagChannel = MethodChannel(PulsrChannels.tagEditor);
  int _maxConcurrentDownloads = 3;

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

  /// True while the native download foreground service is running. Reference
  /// counted by [_activeDownloads] + [_queue] rather than by call site: the
  /// search-screen path went through [download] without ever starting it, so a
  /// download begun from there was an ordinary background task Android was free
  /// to kill the moment the app left the foreground.
  bool _foregroundServiceRunning = false;
  bool _processing = false; // FIX-A03: Guard against re-entrant calls in _processQueue
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

  /// No connection sustains less than this for long; used to turn a byte count
  /// into a pessimistic transfer time so a URL that cannot outlive the download
  /// is replaced before the first byte rather than mid-transfer.
  static const int _pessimisticBytesPerSecond = 48 * 1024; // ~384 kbps

  /// Gap between two received chunks after which the transfer is treated as
  /// dead. Without it a silently half-open socket held a download — and one of
  /// the three concurrency slots — until the OS eventually gave up, which on
  /// mobile can be many minutes.
  static const Duration _stallTimeout = Duration(seconds: 45);

  /// Bytes [stream] is expected to occupy on disk, from its own metadata.
  static int estimateBytes(YtmStream stream) {
    final bitrate = stream.bitrateKbps > 0 ? stream.bitrateKbps : 160;
    final seconds =
        stream.duration.inSeconds > 0 ? stream.duration.inSeconds : 240;
    return seconds * bitrate * 1000 ~/ 8;
  }

  /// Disk space this service insists on before starting a download of
  /// [stream], including the scratch the parallel path needs (F3).
  ///
  /// The true peak is two copies of the body: all four `.partN` chunks exist
  /// while `.part` is being merged, which is the same 2x bar that
  /// [_downloadParallel] checks against. The old `_concurrentChunks + 1` (= 5x)
  /// pre-flight refused downloads that would have completed — a 40-minute
  /// 256kbps track asked for ~394MB free when ~154MB is enough.
  @visibleForTesting
  static int requiredPreflightBytes(YtmStream stream) =>
      estimateBytes(stream) * 2 + (10 * 1024 * 1024);

  /// Stamp value written beside a sequential `.part` so a resume can tell
  /// whether those bytes came from the URL it is about to re-request (F6).
  @visibleForTesting
  static String resumeStampFor(Uri uri) => uri.toString().hashCode.toString();

  /// Whether a `.part` carrying [stampContents] may be resumed against
  /// [urlStamp]. Anything else — a different URL, a missing stamp, or a stamp
  /// written by a build that did not write one — means the bytes on disk are
  /// not known to line up with the body about to be requested.
  @visibleForTesting
  static bool resumeStampMatches(String? stampContents, String urlStamp) =>
      stampContents != null && stampContents.trim() == urlStamp;

  /// How much life a URL needs left for this download to finish on it.
  ///
  /// A download is not a seek: it has to survive from the first byte to the
  /// last, so [YtmStream.isExpiringSoon]'s 5-minute playback default is the
  /// wrong bar — a 40-minute mix on a slow link outlives it and dies at 403
  /// with the bytes already on disk.
  static Duration requiredLifetime(YtmStream stream) {
    final seconds = (estimateBytes(stream) / _pessimisticBytesPerSecond).ceil();
    return Duration(seconds: seconds.clamp(60, 1800)) +
        const Duration(minutes: 2);
  }

  /// Cancels an active or queued download.
  void cancel(String videoId) {
    while (_canceledVideoIds.length >= _maxCanceledIds) {
      _canceledVideoIds.remove(_canceledVideoIds.first);
    }
    _canceledVideoIds.add(videoId);
    final active = _activeDownloads[videoId];
    if (active != null) {
      active.isCanceled = true;
      active.onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.canceled));
    }
  }

  /// Downloads [song] (which must be a `source == youtube` row) and returns the
  /// surviving positive song id once it is a local library track.
  Future<Result<int>> download(
    SongsTableData song, {
    void Function(YtDownloadProgress)? onProgress,
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

    final task = _QueuedDownload(
      song: song,
      onProgress: onProgress,
      completer: completer,
    );

    _queue.add(task);
    onProgress?.call(const YtDownloadProgress(YtDownloadStage.queued));
    ErrorLogger.addBreadcrumb('Download queued: ${task.song.remoteId}',
        category: 'download', data: {'videoId': task.song.remoteId ?? ''});
    _startForegroundService(videoId, song.title);
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
    _downloadChannel.invokeMethod('startDownloadForeground', {
      'videoId': videoId,
      'title': title,
    }).then((ok) {
      // F13: only claim foreground protection once the platform confirms it.
      // The flag used to be raised before the call, so a degraded start
      // (Android 12+ background-start refusal, Doze) left Dart believing the
      // download was protected and it never retried — while every later
      // progress publish went to a service that was not there.
      if (ok == true) _foregroundServiceRunning = true;
    }).catchError((_) {
      _foregroundServiceRunning = false;
      return null;
    });
  }

  /// Tears the notification down once, when nothing is left to download.
  void _stopForegroundServiceIfIdle() {
    if (!_foregroundServiceRunning) return;
    if (_activeDownloads.isNotEmpty || _queue.isNotEmpty) return;
    // A paused download is not idle: the notification must stay up so the user
    // can resume it (C-7).
    _pruneExpiredPausedMarkers();
    if (_pausedVideoIds.isNotEmpty) return;
    _foregroundServiceRunning = false;
    _downloadChannel
        .invokeMethod('stopDownloadForeground')
        .catchError((_) => null);
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
    if (!_foregroundServiceRunning || fraction == null) return;
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
    if (_processing) return; // FIX-A03: Guard against re-entrant calls with a _processing bool flag
    _processing = true; // FIX-A03: Mark processing active
    try {
      while (_activeDownloads.length < _maxConcurrentDownloads &&
          _queue.isNotEmpty) {
        final task = _queue.removeFirst();
        final videoId = task.song.remoteId!;

        if (_canceledVideoIds.contains(videoId) || task.isCanceled) {
          _canceledVideoIds.remove(videoId);
          task.completer
              .complete(const Left(DownloadFailure('Download canceled')));
          continue;
        }

        if (_activeDownloads.containsKey(videoId)) {
          _activeDownloads[videoId]!.completer.future.then(
              task.completer.complete,
              onError: task.completer.completeError);
          continue;
        }

        _activeDownloads[videoId] = task;
        _executeDownload(task).then((result) {
          task.completer.complete(result);
        }).catchError((e) {
          task.completer.complete(Left(DownloadFailure('Download error: $e')));
        }).whenComplete(() {
          _activeDownloads.remove(videoId);
          Future.microtask(_processQueue);
        });
      }
      _stopForegroundServiceIfIdle();
    } finally {
      _processing = false; // FIX-A03: Reset flag when queue processing turn completes
    }
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
      // Use the sound quality the user chose to stream (fallback to setting_download_quality or 'high')
      final quality = prefs.getString('setting_streaming_quality') ??
          prefs.getString('setting_download_quality') ??
          'high';
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
      } catch (_) {}

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
            renamed =
                await temp.rename(p.join(dir.path, 'ytdl_$videoId.$ext'));
          } catch (_) {}
          if (renamed != null) temp = renamed;
        }
      }

      // 3. Tagging — artwork embed + tag standardization (TagEditorPlugin)
      if (ext == 'm4a') {
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.tagging));
        ErrorLogger.addBreadcrumb('Download tagging: $videoId', category: 'download');
        final artPath = artworkFuture != null ? await artworkFuture : null;
        await _tag(temp.path, song, artworkPath: artPath);
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
      final finalPath =
          await _downloadChannel.invokeMethod<String>('saveToMusic', {
        'sourcePath': temp.path,
        'displayName': displayName,
        'title': song.title,
        'mimeType': mimeType,
      });
      if (finalPath == null || finalPath.isEmpty) {
        return const Left(DownloadFailure('MediaStore did not return a path'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
      ErrorLogger.addBreadcrumb('Download indexing: $videoId',
          category: 'download', data: {'path': finalPath});
      final realBitrate = stream.bitrateKbps > 0
          ? stream.bitrateKbps
          : (quality == 'low' ? 64 : quality == 'medium' ? 128 : 160);
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
      ErrorLogger.log('YTM download YtmException: ${e.code} → ${classified.message}',
          error: e, category: 'download');
      if (e.isBotBlocked) {
        return Left(DownloadFailure(
          classified.message,
          e,
        ));
      }
      return Left(DownloadFailure(
        e.isNetwork
            ? 'No connection while downloading'
            : classified.message,
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
        } catch (_) {}
      }
      if (temp != null) {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } catch (_) {}
      }
      if (tempArt != null) {
        try {
          if (await tempArt!.exists()) {
            await tempArt!.delete();
          }
        } catch (_) {}
      }
      _lastForegroundPublishMs.remove(videoId);
    }
  }

  Future<YtmStream> resolveDownloadStream(String videoId, [String quality = 'high',
      bool forceRefresh = false]) async {
    if (forceRefresh && getIt.isRegistered<YtmUrlCache>()) {
      // Nothing used to evict the entry, so the "transparent re-resolution"
      // after a 403 read the same dead URL straight back out of the cache and
      // retried it until the attempts ran out.
      getIt<YtmUrlCache>().invalidate(videoId);
    }

    // Remote backend decommissioned: native resolution only.
    // 1. Native resolution fallback
    final native = await _ytmService.resolveStream(videoId,
        quality: quality, forceRefresh: forceRefresh);
    final resolved = native.withResolvedExpiry();
    _resolvedStreams[videoId] = resolved; // FIX-A05/C05: Store resolved stream for duration lookup
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
          currentStream =
              await _resolveDownloadStream(videoId, quality, forceRefresh: true);
        }

        await _downloadFileResilient(
          currentStream.url,
          dest,
          task,
          onProgress,
          userAgent: currentStream.userAgent,
          cookies: currentStream.cookies,
          expectedBytes: estimateBytes(currentStream),
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

  /// googlevideo URLs are minted for a specific client's User-Agent; sending
  /// the Dart default ("Dart/x.y") trips YouTube's bot heuristics with 403s.
  void _applyStreamHeaders(
    HttpClientRequest req,
    String? userAgent, {
    String? cookies,
    String? range,
  }) {
    final ua = userAgent?.trim();
    if (ua != null && ua.isNotEmpty) {
      req.headers.set(HttpHeaders.userAgentHeader, ua);
    } else {
      req.headers.set(HttpHeaders.userAgentHeader, EmbeddedBrowserUa.desktop);
    }
    if (cookies != null && cookies.isNotEmpty && _cookiesBelongOn(req.uri)) {
      req.headers.set(HttpHeaders.cookieHeader, cookies);
    }
    req.headers.set(HttpHeaders.refererHeader, 'https://music.youtube.com/');
    if (range != null) {
      req.headers.set(HttpHeaders.rangeHeader, range);
    }
  }

  /// Whether the youtube.com session jar has any business on [uri].
  ///
  /// A googlevideo edge node authenticates the request from the signature in the
  /// URL, and a real browser never sends it cookies. The playback path already
  /// withholds them; the download path did not, so every chunk of every download
  /// shipped the live Google session (SAPISID/SID/HSID) to the CDN and looked
  /// unlike the web player it claims to be.
  static bool _cookiesBelongOn(Uri uri) {
    try {
      final host = uri.host.toLowerCase();
      if (host == 'googlevideo.com' || host.endsWith('.googlevideo.com')) {
        return false;
      }
      if (host.endsWith('.c.youtube.com')) return false;
      if (uri.path.contains('/videoplayback')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static const int _concurrentChunks = 4;
  static const int _minChunkThreshold = 1024 * 1024; // 1 MB

  Future<void> _downloadFileResilient(
    String url,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    int? expectedBytes,
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
      _applyStreamHeaders(probeReq, userAgent,
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
        throw YtmException('YTM_BOT_BLOCKED',
            'HTTP ${probeResp.statusCode} on stream probe');
      }

      rangesSupported = probeResp.statusCode == HttpStatus.partialContent &&
          acceptRanges != 'none';
    } catch (e) {
      if (e is YtmException || e is DownloadFailure) rethrow;
      debugPrint(
          '[YtDownloadService] Range probe failed ($e); using a single request');
    }

    if (rangesSupported && total >= _minChunkThreshold) {
      await _downloadParallel(uri, dest, total, task, onProgress,
          userAgent: userAgent, cookies: cookies);
      return;
    }

    await _downloadSequential(uri, dest, task, onProgress,
        userAgent: userAgent, cookies: cookies, expectedBytes: expectedBytes);
  }

  Future<void> _downloadParallel(
    Uri uri,
    File dest,
    int total,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
  }) async {
    if (total < _minChunkThreshold) {
      await _downloadSequential(uri, dest, task, onProgress,
          userAgent: userAgent, cookies: cookies, expectedBytes: total);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final chunkSize = (total / _concurrentChunks).ceil();
    final tempParts = <File>[];
    final dir = dest.parent;
    final stamp = File('${dest.path}.parts');

    // Parts left behind by an earlier attempt are reusable only if they were
    // written for a body of exactly this size: `total` fixes every chunk
    // boundary, and a retry that re-resolves to a different format (webm where
    // the first attempt got m4a) carries different bytes at the same offsets.
    // Without this stamp, resuming across that switch would merge two formats
    // into one file and the size check would happily pass.
    final expectedStamp = '$total|${uri.toString().hashCode}';
    var resumable = false;
    try {
      if (await stamp.exists()) {
        final existing = (await stamp.readAsString()).trim();
        resumable = existing == expectedStamp || existing == '$total';
      }
    } catch (_) {}
    try {
      await stamp.writeAsString(expectedStamp, flush: true);
    } catch (_) {}

    final chunkReceived = List<int>.filled(_concurrentChunks, 0);
    var lastEmitTime = 0;
    var mergeCompleted = false;
    var keepParts = false;

    try { // FIX-A02: Outer try to catch _RangeIgnored outside the inner try/finally
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


      for (var i = 0; i < _concurrentChunks; i++) {
        final chunkIndex = i;
        final start = i * chunkSize;
        final end =
            (i == _concurrentChunks - 1) ? total - 1 : (start + chunkSize - 1);
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
          // Already complete from an earlier attempt. Asking anyway would send
          // `bytes=${end + 1}-$end` and come back 416.
          if (have == expectedSize) return;

          if (task.isCanceled ||
              _canceledVideoIds.contains(task.song.remoteId)) {
            throw const DownloadFailure('Download canceled');
          }

          final req = await _http.getUrl(uri);
          _applyStreamHeaders(req, userAgent,
              cookies: cookies, range: 'bytes=${start + have}-$end');
          final resp = await req.close().timeout(_stallTimeout);

          if (resp.statusCode == 429) {
            final retryAfter = resp.headers.value(HttpHeaders.retryAfterHeader);
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
                if (m.contains('no space') || m.contains('enospc') || e.osError?.errorCode == 28) {
                  throw const StorageFailure('Storage full while writing chunk');
                }
                rethrow;
              }
              chunkReceived[chunkIndex] += chunk.length;
              final totalReceived = chunkReceived.reduce((a, b) => a + b);
              if (onProgress != null && total > 0) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - lastEmitTime > 80 || totalReceived >= total) {
                  lastEmitTime = now;
                  final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
                  final speedKbps = elapsedSeconds > 0
                      ? (totalReceived / elapsedSeconds) / 1024.0
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
            if (m.contains('no space') || m.contains('enospc') || e.osError?.errorCode == 28) {
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
          throw DownloadFailure('Merged file size mismatch: $finalSize/$total');
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
      if (e is _RangeIgnored) rethrow; // FIX-A02: Bubble _RangeIgnored to outer catch
      keepParts = _partsWorthKeeping(e);
      rethrow;
    } finally {
      final outPartFile = File('${dest.path}.part');
      try {
        if (await outPartFile.exists()) {
          await outPartFile.delete();
        }
      } catch (_) {}

      // Parts used to be deleted unconditionally, so a cancel or a single
      // dropped socket at 95% threw away every byte of all four chunks and the
      // next attempt started from zero.
      if (mergeCompleted || !keepParts) {
        for (final part in tempParts) {
          try {
            if (await part.exists()) {
              await part.delete();
            }
          } catch (_) {}
        }
        try {
          if (await stamp.exists()) {
            await stamp.delete();
          }
        } catch (_) {}
      }

      if (!mergeCompleted) {
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (_) {}
      }
    }
  } on _RangeIgnored {
    // Inner finally already cleaned up tempParts and stamp since keepParts is false.
    debugPrint(
        '[YtDownloadService] Server ignored Range mid-transfer; retrying as a single request');
    await _downloadSequential(uri, dest, task, onProgress,
        userAgent: userAgent, cookies: cookies, expectedBytes: total);
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
    bool allowResume = true,
    int retryCount = 0, // FIX-A01: Add retryCount parameter (max 1)
  }) async {
    final stopwatch = Stopwatch()..start();
    final partFile = File('${dest.path}.part');
    // F6: a `.part` is only resumable against the URL that wrote it. The
    // parallel path pins its chunks with a `.parts` stamp precisely so a
    // re-resolve that changed container cannot be merged in; this path had no
    // such guard, so a stale partial could be appended with bytes from a
    // different format at the same offsets and still satisfy the size check.
    final stampFile = File('${dest.path}.part.stamp');
    final urlStamp = resumeStampFor(uri);
    int resumeOffset = 0;
    try {
      if (await partFile.exists()) {
        resumeOffset = allowResume ? await partFile.length() : 0;
        var stampMatches = false;
        try {
          if (await stampFile.exists()) {
            stampMatches =
                resumeStampMatches(await stampFile.readAsString(), urlStamp);
          }
        } catch (_) {}
        if (resumeOffset > 0 && !stampMatches) {
          // Written for a different URL, or by a build without the stamp:
          // nothing in it is known to line up, so start over.
          try {
            await partFile.delete();
          } catch (_) {}
          resumeOffset = 0;
        }
        // Keep resume only if meaningful (>64k) to avoid overhead for tiny partials
        if (resumeOffset < 64 * 1024) {
          try {
            await partFile.delete();
          } catch (_) {}
          resumeOffset = 0;
        }
      }
      try {
        await stampFile.writeAsString(urlStamp, flush: true);
      } catch (_) {}
    } catch (_) {
      resumeOffset = 0;
    }

    final request = await _http.openUrl('GET', uri);
    if (resumeOffset > 0) {
      _applyStreamHeaders(request, userAgent,
          cookies: cookies, range: 'bytes=$resumeOffset-');
    } else {
      _applyStreamHeaders(request, userAgent, cookies: cookies);
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
        } catch (_) {}
        // FIX-A01: On second occurrence, throw DownloadFailure('Server does not support resume')
        if (retryCount >= 1) {
          throw const DownloadFailure('Server does not support resume');
        }
        // Retry from scratch with incremented retryCount
        return _downloadSequential(uri, dest, task, onProgress,
            userAgent: userAgent,
            cookies: cookies,
            expectedBytes: expectedBytes,
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
            final speedKbps =
                elapsedSeconds > 0 ? ((received - baseReceived) / elapsedSeconds) / 1024.0 : 0.0;
            final remainingBytes = effectiveTotal > 0 ? effectiveTotal - received : 0;
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
      if (msg.contains('no space') || msg.contains('enospc') || e.osError?.errorCode == 28) {
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
      } catch (_) {}
      if (await dest.exists()) {
        await dest.delete();
      }
      await partFile.rename(dest.path);
      try {
        if (await stampFile.exists()) {
          await stampFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Sweeps this service's stale temporaries — `ytdl_*` bodies, their `.partN`
  /// chunks, `.parts` stamps and `ytdl_art_*` covers — out of the cache
  /// directory.
  ///
  /// Two things it no longer does. It matched any `name.contains('.part')`,
  /// which in a directory shared with every other plugin meant deleting other
  /// people's partial writes. And it protected nothing belonging to a download
  /// running right now: a slow transfer whose `.part0` had not been appended to
  /// for ten minutes, or a queued track whose parts were written by an earlier
  /// attempt, had them deleted from underneath it.
  Future<void> cleanOrphanPartFiles({
    Set<String>? activePartNames,
    Set<String>? protectedVideoIds,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;

      // `activePartNames` only ever matched an exact basename, so a caller had to
      // know the container extension to name the file — `ytdl_<id>.m4a.part`, its
      // `.part0..3` chunk siblings and the `.parts` stamp. Callers guessed
      // `ytdl_<id>.part`, which matches nothing, so a paused download's partial
      // was swept and its resume restarted from zero. Ids are what a caller
      // actually holds, and they cover every artifact of that download at once.
      final busy = <String>{
        ..._activeDownloads.keys,
        ..._queue.map((t) => t.song.remoteId).whereType<String>(),
        ...?protectedVideoIds,
      };

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('ytdl_')) continue;
        if (activePartNames != null && activePartNames.contains(name)) continue;
        if (busy.any((id) =>
            name.startsWith('ytdl_$id.') ||
            name.startsWith('ytdl_art_$id.'))) {
          continue;
        }
        try {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) >
              const Duration(minutes: 10)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Removes every scratch file this service may have written for [videoId].
  ///
  /// The orphan sweep above only touches files older than ten minutes, so it is
  /// useless right after a delete — the partial of the download the user just
  /// removed is seconds old. This is the immediate counterpart, and it lives
  /// here because the layout is this class's private knowledge: the cache dir
  /// from [getTemporaryDirectory], `ytdl_<id>.<ext>` plus its `.part`,
  /// `.part0..3` and `.parts` siblings, and the `ytdl_art_<id>.<ext>` cover.
  /// The repository used to do this itself against [Directory.systemTemp] — a
  /// different directory entirely on Android — and matched with
  /// `path.contains('ytdl_$videoId')`, which has no boundary, so deleting the
  /// download `abc` would also delete the artifacts of `abcdef`.
  Future<void> deleteArtifactsFor(String videoId) async {
    if (videoId.isEmpty) return;
    // A live download owns its partial; deleting under it would leave the writer
    // appending to an unlinked handle and commit a truncated file.
    if (_activeDownloads.containsKey(videoId)) return;
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;
      final audio = 'ytdl_$videoId.';
      final art = 'ytdl_art_$videoId.';
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(audio) && !name.startsWith(art)) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _tag(String path, SongsTableData song,
      {String? artworkPath}) async {
    // Retry once on transient failures — a flaky tag write must not fail
    // the whole download.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _tagChannel.invokeMethod('writeTags', {
          'path': path,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'genre': song.genre,
          'year': song.year,
          'trackNumber': song.trackNumber,
          'comment': null,
          'lyrics': null,
          'artworkPath': artworkPath,
          'removeArtwork': false,
        });
        return;
      } on PlatformException catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    ErrorLogger.log('Tagging downloaded track failed after retry: $lastError',
        category: 'YTM');
  }

  /// Audio container extensions this service is willing to name a file after.
  static const Set<String> _allowedExtensions = {
    'm4a',
    'webm',
    'opus',
    'mp4',
    'ogg',
    'oga',
    'mp3',
    'flac',
    'aac',
  };

  /// F11: [ext] arrives from the resolver and from byte sniffing and is then
  /// interpolated straight into a file name, so it has to be a bare container
  /// extension and nothing that could carry a path separator or a traversal
  /// segment.
  static String safeExtension(String? ext) {
    final e = (ext ?? '').trim().toLowerCase();
    if (e.isEmpty || e.contains('.') || e.contains('/') || e.contains('\\')) {
      return 'm4a';
    }
    return _allowedExtensions.contains(e) ? e : 'm4a';
  }

  static String sanitizeFilename(String artist, String title, String ext) {
    ext = safeExtension(ext);
    var rawArtist = artist.trim();
    var rawTitle = title.trim();
    if (rawArtist.isEmpty) rawArtist = 'Unknown Artist';
    if (rawTitle.isEmpty) rawTitle = 'Unknown Title';

    // 1. Strip reserved characters and control characters (BUG-015)
    final cleanedArtist =
        rawArtist.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    final cleanedTitle =
        rawTitle.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

    var base = '$cleanedArtist - $cleanedTitle';
    // 2. Check Windows reserved device names
    final baseUpper = base.toUpperCase().split('.').first;
    const reservedNames = {
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9'
    };
    if (reservedNames.contains(baseUpper)) {
      base = '${base}_track';
    }

    // 3. Limit UTF-8 byte length to 180 bytes (BUG-015)
    var encoded = utf8.encode(base);
    if (encoded.length > 180) {
      while (encoded.length > 180 && base.isNotEmpty) {
        base = base.substring(0, base.length - 1);
        encoded = utf8.encode(base);
      }
    }
    // F11: strip trailing dots/spaces — not a valid file-name tail on every
    // target, and the shape a traversal attempt takes once separators are gone.
    base = base.replaceAll(RegExp(r'[. ]+$'), '').trim();
    if (base.isEmpty) base = 'Track';

    return '$base.$ext';
  }

  /// The container the bytes on disk actually are, or null for a header nothing
  /// recognises.
  ///
  /// The URL is not a trustworthy source for this. Entries the playback path
  /// wrote into `YtmUrlCache` carry no [YtmStream], so the container and MIME
  /// that come back with them are *guessed* — and a WebM/Opus body was being
  /// saved as `.m4a`, handed to the MP4 tagger (which fails), and published to
  /// MediaStore as `audio/mp4`, leaving an untagged file with a lying extension
  /// that the scanner then refuses to index.
  @visibleForTesting
  static ({String ext, String mime})? sniffContainerBytes(List<int> header) {
    bool at(int offset, List<int> magic) {
      if (header.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (header[offset + i] != magic[i]) return false;
      }
      return true;
    }

    // ISO-BMFF: 4-byte box length, then 'ftyp'. Covers m4a/mp4/3gp.
    if (at(4, const [0x66, 0x74, 0x79, 0x70])) {
      return (ext: 'm4a', mime: 'audio/mp4');
    }
    // EBML header → Matroska/WebM.
    if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) {
      return (ext: 'webm', mime: 'audio/webm');
    }
    if (at(0, const [0x4F, 0x67, 0x67, 0x53])) {
      return (ext: 'ogg', mime: 'audio/ogg');
    }
    if (at(0, const [0x66, 0x4C, 0x61, 0x43])) {
      return (ext: 'flac', mime: 'audio/flac');
    }
    if (at(0, const [0x49, 0x44, 0x33])) {
      return (ext: 'mp3', mime: 'audio/mpeg');
    }
    // MPEG audio frame sync: eleven set bits.
    if (header.length >= 2 && header[0] == 0xFF && (header[1] & 0xE0) == 0xE0) {
      return (ext: 'mp3', mime: 'audio/mpeg');
    }
    return null;
  }

  static Future<({String ext, String mime})?> _sniffContainer(File file) async {
    try {
      final raf = await file.open();
      try {
        return sniffContainerBytes(await raf.read(32));
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  void _sampleThroughput(int bytes, Duration elapsed) {
    try {
      if (getIt.isRegistered<AdaptiveBufferEngine>()) {
        getIt<AdaptiveBufferEngine>().sampleThroughput(bytes, elapsed);
      }
    } catch (_) {}
  }
}
