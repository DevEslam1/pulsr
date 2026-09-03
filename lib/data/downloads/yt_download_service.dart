// lib/data/downloads/yt_download_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../scanner/media_scanner_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/errors/failures.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/services/xdm_backend_service.dart';
import '../../data/services/ytm_account_service.dart';
import '../../data/services/ytm_service.dart';
import '../../core/utils/safe_filename.dart';
import '../../domain/models/retry_policy.dart';

import '../../core/utils/app_logger.dart';
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
  bool isPaused = false;

  _QueuedDownload({
    required this.song,
    required this.onProgress,
    required this.completer,
  });
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
  static const int defaultMaxConcurrentDownloads = 3;

  final HttpClient _http;
  final YtmService _ytmService;
  // ignore: unused_field - kept for future single-file rescan without full library scan (dedup fix)
  final MediaScannerService _scanner;
  final IMusicRepository _repository;

  int maxConcurrentDownloads = defaultMaxConcurrentDownloads;

  YtDownloadService(
    this._http,
    this._ytmService,
    this._scanner,
    this._repository,
  );

  final Queue<_QueuedDownload> _queue = Queue<_QueuedDownload>();
  final Map<String, _QueuedDownload> _activeDownloads = {};
  static const int _maxCanceledIds = 200;
  final Set<String> _canceledVideoIds = <String>{};

  /// Latest progress emitted per active videoId so an idempotent re-start of
  /// an already-active download can immediately return the live position.
  final Map<String, YtDownloadProgress> _lastProgressByVideo = {};

  /// Exponential backoff with jitter for rate-limit retries that arrive
  /// without a server-provided Retry-After hint.
  final RetryPolicy _retryPolicy = const RetryPolicy();

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

  /// Pauses an active download gracefully.
  void pause(String videoId) {
    final active = _activeDownloads[videoId];
    if (active != null) {
      active.isPaused = true;
    }
  }

  /// Downloads [song] (which must be a `source == youtube` row) and returns the
  /// surviving positive song id once it is a local library track.
  ///
  /// Idempotent start: if [song] is already downloading, the existing
  /// download's result is returned (plus the latest known progress) instead of
  /// enqueueing a second download.
  Future<Result<int>> download(
    SongsTableData song, {
    void Function(YtDownloadProgress)? onProgress,
  }) async {
    if (song.source != SongSource.youtube) {
      return const Left(
          DownloadFailure('Only YouTube tracks can be downloaded'));
    }
    final videoId = song.remoteId;
    if (videoId == null ||
        videoId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      return const Left(
          ValidationFailure('Invalid video id: must be exactly 11 characters'));
    }

    _canceledVideoIds.remove(videoId);

    final completer = Completer<Result<int>>();
    final active = _activeDownloads[videoId];
    if (active != null) {
      // Already active: piggyback on the existing download, replaying the
      // last known progress so the caller does not start blind.
      final lastProgress = _lastProgressByVideo[videoId];
      if (onProgress != null) {
        onProgress(lastProgress ??
            const YtDownloadProgress(YtDownloadStage.queued));
      }
      unawaited(active.completer.future
          .then(completer.complete, onError: completer.completeError));
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
    _processQueue();

    return completer.future;
  }

  void _processQueue() {
    while (_activeDownloads.length < maxConcurrentDownloads &&
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
      }).catchError((Object e) {
        task.completer.complete(Left(DownloadFailure('Download error: $e')));
      }).whenComplete(() {
        _activeDownloads.remove(videoId);
        Future.microtask(_processQueue);
      });
    }
  }

  Future<Result<int>> _executeDownload(_QueuedDownload task) async {
    final song = task.song;
    final videoId = song.remoteId!;
    // Wrap the caller's callback so the latest progress is always recorded
    // for idempotent piggyback starts of this videoId.
    final onProgress = task.onProgress == null
        ? null
        : (YtDownloadProgress p) {
            _lastProgressByVideo[videoId] = p;
            task.onProgress!(p);
          };

    final prefs = await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      return const Left(
          DownloadFailure('Offline Only Mode is active in Settings'));
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        return const Left(DownloadFailure(
            'Wi-Fi Only Mode is active. Connect to Wi-Fi to download.'));
      }
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
      try {
        await _ytmService.ensurePoTokenReady().timeout(
            const Duration(seconds: 10));
      } catch (e) {
        // Best-effort: resolve chain will surface a structured error.
        AppLogger.debug('_executeDownload failed (non-fatal): $e', category: 'YtDownloadService');
      }

      // Validate quality (prefs corruption → fallback high, never empty).
      var quality = prefs.getString('setting_download_quality') ?? 'high';
      if (quality != 'low' && quality != 'medium' && quality != 'high') {
        quality = 'high';
      }
      var stream = await _resolveDownloadStream(videoId, quality);

      // Freshness: never start chunks on a URL expiring within 5 min —
      // parallel chunks share one URL and all 4 die together on expire.
      if (stream.isExpiringSoon()) {
        stream = await _resolveDownloadStream(videoId, quality);
      }

      // Pre-download storage check (BUG-06 & [D6])
      try {
        final dynamic freeRaw =
            await _downloadChannel.invokeMethod<dynamic>('getFreeDiskSpace').timeout(const Duration(seconds: 2));
        final freeBytes = (freeRaw as num?)?.toInt();
        if (freeBytes != null && freeBytes > 0) {
          final estBitrate = stream.bitrateKbps > 0 ? stream.bitrateKbps : 160;
          final estDurationSec =
              stream.duration.inSeconds > 0 ? stream.duration.inSeconds : 240;
          final estimatedBytes =
              ((estDurationSec * estBitrate * 1000 ~/ 8) * 1.2).toInt() + (5 * 1024 * 1024);
          if (freeBytes < estimatedBytes) {
            return Left(
                InsufficientStorageFailure(
                  'Insufficient storage space for download',
                  neededBytes: estimatedBytes,
                  availableBytes: freeBytes,
                ));
          }
        }
      } catch (e, st) {
        ErrorLogger.log('toInt failed', error: e, stackTrace: st, category: 'YtDownloadService');
      }

      final ext = stream.container.isNotEmpty ? stream.container : 'm4a';
      final dir = await getTemporaryDirectory();
      temp = File(p.join(dir.path, 'ytdl_$videoId.$ext'));

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      // Download high-res master artwork in parallel with the audio stream (with 2-attempt retry)
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
                await Future<void>.delayed(const Duration(seconds: 1));
              }
            }
          }
          return null;
        });
      }

      onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0));
      ErrorLogger.addBreadcrumb('Download started: $videoId container=$ext',
          category: 'download', data: {'videoId': videoId, 'ext': ext});

      // 2. Download audio with transparent 403 re-resolution & resume (206 verified)
      await _downloadAudioWithRetry(
        stream: stream,
        videoId: videoId,
        quality: quality,
        dest: temp,
        task: task,
        onProgress: onProgress,
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
            CorruptDownloadFailure('Downloaded audio file is corrupt or incomplete'));
      }

      // 3. Tagging — artwork embed + tag standardization (TagEditorPlugin)
      if (stream.isTaggable) {
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
      final displayName = SafeFilename.sanitize(
        artist: song.artist,
        title: song.title,
        ext: ext,
      );
      String? finalPath;
      try {
        finalPath = await _downloadChannel.invokeMethod<String>('saveToMusic', {
          'sourcePath': temp.path,
          'displayName': displayName,
          'title': song.title,
          'mimeType': stream.mimeType,
        }).timeout(const Duration(seconds: 20));
      } on MissingPluginException {
        return const Left(FeatureDisabledFailure());
      } catch (e) {
        return Left(DownloadFailure('Failed to save to MediaStore: $e'));
      }
      if (finalPath == null || finalPath.isEmpty) {
        return const Left(DownloadFailure('MediaStore did not return a path'));
      }


      onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
      ErrorLogger.addBreadcrumb('Download indexing: $videoId',
          category: 'download', data: {'path': finalPath});
      final reconciled = await _repository.reconcileDownloadedSong(
        oldId: song.id,
        newPath: finalPath,
        fallbackSong: song,
      );

      // FIX: Downloaded song repeated twice — full rescan after reconcile creates duplicate path row
      // The file is already indexed via reconcile (old YTM row → local). Triggering a full MediaStore scan
      // inserts a second row with the new MediaStore id for the same file path, causing the double entry
      // on local. Do not rescan the whole library here; deduplication is handled inside reconcile.
      // If needed, a lightweight single-file rescan can be done, but the reconciled row is sufficient.

      return await reconciled.fold(
        (f) => Left(f),
        (newId) {
          if (newId == null) {
            ErrorLogger.log('Download indexing missing library row: $videoId',
                category: 'download');
            return const Left(DownloadFailure(
                'Downloaded file was not found in the library'));
          }
          onProgress?.call(const YtDownloadProgress(YtDownloadStage.done, 1));
          ErrorLogger.addBreadcrumb('Download done: $videoId',
              category: 'download', data: {'newId': newId});
          return Right(newId);
        },
      );
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
    } on DownloadFailure catch (e) {
      // Keep typed failures (canceled, corrupt, storage-estimate, …) intact so
      // the repository's retry classification sees the real cause instead of
      // a generic 'Download failed: …' wrapper.
      ErrorLogger.log('YT download failed: ${e.message}',
          error: e, category: 'download');
      return Left(e);
    } on StorageFailure catch (e) {
      ErrorLogger.log('YT download storage failure: ${e.message}',
          error: e, category: 'download');
      return Left(e);
    } on SocketException catch (e) {
      ErrorLogger.log('YT download network dropped: ${e.message}',
          error: e, category: 'download');
      return Left(NetworkFailure('No connection while downloading', e));
    } catch (e, st) {
      ErrorLogger.log('YT download failed',
          error: e, stackTrace: st, category: 'YTM');
      return Left(DownloadFailure('Download failed: $e', e));
    } finally {
      _lastProgressByVideo.remove(videoId);
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
        } catch (e, st) {
          ErrorLogger.log('yt_download_service failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
      }
      if (temp != null) {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } catch (e, st) {
          ErrorLogger.log('yt_download_service failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
      }
      if (tempArt != null) {
        try {
          if (await tempArt!.exists()) {
            await tempArt!.delete();
          }
        } catch (e, st) {
          ErrorLogger.log('yt_download_service failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
      }
    }
  }

  Future<YtmStream> _resolveDownloadStream(String videoId, String quality) async {
    // 1. Backend-first for downloads (Engine 3 as primary download engine)
    try {
      if (getIt.isRegistered<XdmBackendService>()) {
        final xdm = getIt<XdmBackendService>();
        if (await xdm.isEnabled()) {
          final account = getIt.isRegistered<YtmAccountService>()
              ? getIt<YtmAccountService>()
              : null;
          final backendStream = await xdm.resolveStream(
            videoId,
            quality: quality,
            cookies: account?.cookies,
          );
          if (backendStream != null) {
            return backendStream;
          }
        }
      }
    } catch (e) {
      debugPrint('[YtDownloadService] Backend download resolve fallback: $e');
    }

    // 2. Native resolution fallback
    return await _ytmService.resolveStream(videoId, quality: quality);
  }

  Future<void> _downloadAudioWithRetry({
    required YtmStream stream,
    required String videoId,
    required String quality,
    required File dest,
    required _QueuedDownload task,
    required void Function(YtDownloadProgress)? onProgress,
  }) async {
    var currentStream = stream;
    var currentUrl = stream.url;
    var currentUserAgent = stream.userAgent;
    var currentCookies = stream.cookies;
    var attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
          throw const DownloadFailure('Download canceled');
        }

        // Proactive stream re-resolution before expiration (expiresAt - 5 min)
        if (currentStream.isExpiringSoon()) {
          debugPrint(
              '[YtDownloadService] Stream expiring soon for $videoId, proactively re-resolving...');
          currentStream = await _resolveDownloadStream(videoId, quality);
          currentUrl = currentStream.url;
          currentUserAgent = currentStream.userAgent;
          currentCookies = currentStream.cookies;
        }

        await _downloadFileResilient(
          currentUrl,
          dest,
          task,
          onProgress,
          userAgent: currentUserAgent,
          cookies: currentCookies,
        );
        return;
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

        // 429 → Retry-After-aware exponential backoff + jitter before poToken rotation.
        // Falls back to the shared [RetryPolicy] (exponential + jitter) when
        // the server does not dictate a delay.
        if (e is YtmException && (e.code == 'YTM_429' || e.details?.contains('Retry-After') == true)) {
          final retryMatch = RegExp(r'Retry-After:\s*(\d+)').firstMatch(e.details ?? '');
          final retrySec = retryMatch != null ? int.tryParse(retryMatch.group(1)!) : null;
          final backoff = retrySec != null
              ? Duration(seconds: retrySec)
              : _retryPolicy.delayForAttempt(attempts);
          await Future<void>.delayed(backoff);
        }

        // Transparent 403 / failure re-resolution via same engine chain (poToken rotation mid-download)
        await _ytmService.invalidatePoToken();
        await _ytmService.ensurePoTokenReady();
        currentStream = await _resolveDownloadStream(videoId, quality);
        currentUrl = currentStream.url;
        currentUserAgent = currentStream.userAgent;
        currentCookies = currentStream.cookies;
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
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36');
    }
    if (cookies != null && cookies.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, cookies);
    }
    req.headers.set(HttpHeaders.refererHeader, 'https://music.youtube.com/');
    if (range != null) {
      req.headers.set(HttpHeaders.rangeHeader, range);
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
  }) async {
    final uri = Uri.parse(url);

    // Initial probe to test HTTP Range support and fetch content length
    try {
      final probeReq = await _http.openUrl('GET', uri);
      _applyStreamHeaders(probeReq, userAgent,
          cookies: cookies, range: 'bytes=0-0');
      final probeResp = await probeReq.close();

      final acceptRanges =
          probeResp.headers.value(HttpHeaders.acceptRangesHeader);
      final contentRange =
          probeResp.headers.value(HttpHeaders.contentRangeHeader);
      int total = -1;
      if (contentRange != null && contentRange.contains('/')) {
        total = int.tryParse(contentRange.split('/').last) ?? -1;
      }
      if (total <= 0 && probeResp.contentLength > 0) {
        total = probeResp.contentLength;
      }
      await probeResp.drain<void>();

      if (probeResp.statusCode == HttpStatus.forbidden ||
          probeResp.statusCode == HttpStatus.unauthorized) {
        throw const YtmException(
            'YTM_BOT_BLOCKED', 'HTTP 403 Forbidden on stream probe');
      }

      final rangesSupported =
          probeResp.statusCode == HttpStatus.partialContent &&
              acceptRanges != 'none';

      if (rangesSupported && total >= _minChunkThreshold) {
        await _downloadParallel(uri, dest, total, task, onProgress,
            userAgent: userAgent, cookies: cookies);
        return;
      }
    } catch (e) {
      if (e is YtmException || e is DownloadFailure) rethrow;
    }

    await _downloadSequential(uri, dest, task, onProgress,
        userAgent: userAgent, cookies: cookies);
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
          userAgent: userAgent, cookies: cookies);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final chunkSize = (total / _concurrentChunks).ceil();
    final tempParts = <File>[];
    final dir = dest.parent;

    final chunkReceived = List<int>.filled(_concurrentChunks, 0);
    var lastEmitTime = 0;
    bool mergeCompleted = false;

    try {
      try {
        final dynamic freeRaw2 =
            await _downloadChannel.invokeMethod<dynamic>('getFreeDiskSpace').timeout(const Duration(seconds: 2));
        final freeBytes = (freeRaw2 as num?)?.toInt() ?? 0;
        if (freeBytes > 0 && freeBytes < total) {
          throw const DownloadFailure('Insufficient storage space');
        }
      } catch (e) {
        if (e is DownloadFailure) rethrow;
      }

      final chunkResults = <int, File?>{};
      final futures = <Future<void>>[];
      final activeChunkIndices = <int>[];

      for (var i = 0; i < _concurrentChunks; i++) {
        final chunkIndex = i;
        final start = i * chunkSize;
        final end =
            (i == _concurrentChunks - 1) ? total - 1 : (start + chunkSize - 1);
        if (start >= total) break;

        activeChunkIndices.add(i);
        final partFile =
            File(p.join(dir.path, '${p.basename(dest.path)}.part$i'));
        tempParts.add(partFile);

        futures.add(() async {
          if (task.isCanceled ||
              _canceledVideoIds.contains(task.song.remoteId)) {
            throw const DownloadFailure('Download canceled');
          }

          final req = await _http.getUrl(uri);
          _applyStreamHeaders(req, userAgent,
              cookies: cookies, range: 'bytes=$start-$end');
          final resp = await req.close();

          if (resp.statusCode == 429) {
            final retryAfter = resp.headers.value(HttpHeaders.retryAfterHeader);
            final retrySec = int.tryParse(retryAfter ?? '');
            await resp.drain<void>();
            throw YtmException('YTM_429',
                'HTTP 429 Rate limited${retrySec != null ? ' Retry-After: $retrySec' : ''}');
          }
          if (resp.statusCode == HttpStatus.forbidden) {
            await resp.drain<void>();
            throw const YtmException('YTM_BOT_BLOCKED', 'HTTP 403 Forbidden');
          }

          if (resp.statusCode != HttpStatus.partialContent &&
              resp.statusCode != HttpStatus.ok) {
            throw DownloadFailure(
                'Server returned ${resp.statusCode} for chunk $chunkIndex');
          }

          final sink = partFile.openWrite();
          try {
            await for (final chunk in resp) {
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
            chunkResults[chunkIndex] = partFile;
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

      // Verify every chunk index 0..N-1 is present and in order (D-03)
      for (var i = 0; i < activeChunkIndices.length; i++) {
        final chunkIdx = activeChunkIndices[i];
        final res = chunkResults[chunkIdx];
        if (res == null || !await res.exists()) {
          for (final part in tempParts) {
            try {
              if (await part.exists()) await part.delete();
            } catch (e, st) {
              ErrorLogger.log('wait failed', error: e, stackTrace: st, category: 'YtDownloadService');
            }
          }
          throw const CorruptDownloadFailure(
              'Parallel download chunk missing or out of order');
        }
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

      // Verify merged total size and atomically rename (D-04, BUG-014)
      if (total > 0) {
        final finalSize = await outPartFile.length();
        if (finalSize != total) {
          await outPartFile.delete().catchError((_) => outPartFile);
          throw CorruptDownloadFailure(
              'Merged file size mismatch: $finalSize expected $total');
        }
      }
      if (await outPartFile.exists()) {
        if (await dest.exists()) {
          await dest.delete();
        }
        await outPartFile.rename(dest.path);
      }
      mergeCompleted = true;
    } finally {
      for (final part in tempParts) {
        try {
          if (await part.exists()) {
            await part.delete();
          }
        } catch (e, st) {
          ErrorLogger.log('wait failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
      }
      final outPartFile = File('${dest.path}.part');
      try {
        if (await outPartFile.exists()) {
          await outPartFile.delete();
        }
      } catch (e, st) {
        ErrorLogger.log('wait failed', error: e, stackTrace: st, category: 'YtDownloadService');
      }
      if (!mergeCompleted) {
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (e, st) {
          ErrorLogger.log('wait failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
      }
    }
  }

  Future<void> _downloadSequential(
    Uri uri,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress, {
    String? userAgent,
    String? cookies,
    int depth = 0,
  }) async {
    final stopwatch = Stopwatch()..start();
    final partFile = File('${dest.path}.part');
    int resumeOffset = 0;
    try {
      if (await partFile.exists()) {
        resumeOffset = await partFile.length();
        // Keep resume only if meaningful (>64k) to avoid overhead for tiny partials
        if (resumeOffset < 64 * 1024) {
          await partFile.delete();
          resumeOffset = 0;
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Function failed, using fallback', error: e, stackTrace: st, category: 'YtDownloadService');
      resumeOffset = 0;
    }

    final request = await _http.openUrl('GET', uri);
    if (resumeOffset > 0) {
      _applyStreamHeaders(request, userAgent,
          cookies: cookies, range: 'bytes=$resumeOffset-');
    } else {
      _applyStreamHeaders(request, userAgent, cookies: cookies);
    }
    final response = await request.close();

    // 429 / Retry-After aware backoff + jitter integration
    if (response.statusCode == 429) {
      final retryAfter = response.headers.value(HttpHeaders.retryAfterHeader);
      final retrySec = int.tryParse(retryAfter ?? '');
      // Drain body before throwing so connection reused
      await response.drain<void>();
      throw YtmException('YTM_429',
          'HTTP 429 Too Many Requests${retrySec != null ? ' Retry-After: $retrySec' : ''}');
    }
    if (response.statusCode == HttpStatus.forbidden) {
      await response.drain<void>();
      throw const YtmException('YTM_BOT_BLOCKED', 'HTTP 403 Forbidden');
    }

    // Resume correctness: if we sent Range, server MUST reply 206. A 200 means it ignored Range
    // → appending would corrupt file. Discard stale part and restart.
    if (resumeOffset > 0) {
      if (response.statusCode == HttpStatus.ok) {
        await response.drain<void>();
        try {
          await partFile.delete();
        } catch (e, st) {
          ErrorLogger.log('tryParse failed', error: e, stackTrace: st, category: 'YtDownloadService');
        }
        // Retry fresh without Range (recurse once) — guard depth ≤1 to avoid infinite recursion
        if (depth >= 1) {
          throw const DownloadFailure(
              'Server ignored Range header repeatedly — aborting resume retry');
        }
        return _downloadSequential(uri, dest, task, onProgress,
            userAgent: userAgent, cookies: cookies, depth: depth + 1);
      }
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw DownloadFailure('Server returned ${response.statusCode} for resume');
      }
    } else {
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw DownloadFailure('Server returned ${response.statusCode}');
      }
    }

    // Determine total expected size for atomic commit verification
    int total = response.contentLength; // remaining bytes
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
      await for (final chunk in response) {
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }
        if (task.isPaused) {
          sink.add(chunk);
          await sink.flush();
          await sink.close();
          // Distinct from errors: pause is user-intent, resumable — not a failure toast.
          throw const InterruptedFailure('Download paused');
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
      if (expectedFinalSize != null && finalSize != expectedFinalSize) {
        // If server didn't give expected, at least ensure we received contentLength
        if (total > 0 && finalSize < expectedFinalSize) {
          throw DownloadFailure('Incomplete download: $finalSize/$expectedFinalSize bytes');
        }
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
      } catch (e, st) {
        ErrorLogger.log('tryParse failed', error: e, stackTrace: st, category: 'YtDownloadService');
      }
      if (await dest.exists()) {
        await dest.delete();
      }
      await partFile.rename(dest.path);
    }
  }

  Future<void> cleanOrphanPartFiles({Set<String>? activePartNames}) async {
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('ytdl_') || name.contains('.part')) {
              if (activePartNames != null && activePartNames.contains(name)) continue;
              try {
                final stat = await entity.stat();
                if (DateTime.now().difference(stat.modified) >
                    const Duration(minutes: 10)) {
                  await entity.delete();
                }
              } catch (e, st) {
                ErrorLogger.log('cleanOrphanPartFiles failed', error: e, stackTrace: st, category: 'YtDownloadService');
              }
            }
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('cleanOrphanPartFiles failed', error: e, stackTrace: st, category: 'YtDownloadService');
    }
  }

  Future<void> _tag(String path, SongsTableData song,
      {String? artworkPath}) async {
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
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException catch (e) {
      // Tags are best-effort: a slow native tagger must not fail an otherwise
      // fully downloaded file.
      ErrorLogger.log('Tagging downloaded track timed out: $e',
          category: 'YTM');
    } on MissingPluginException catch (e) {
      ErrorLogger.log('Tagging unavailable on this platform: $e',
          category: 'YTM');
    } on PlatformException catch (e) {
      ErrorLogger.log('Tagging downloaded track failed: ${e.code}',
          category: 'YTM');
    }
  }
}

