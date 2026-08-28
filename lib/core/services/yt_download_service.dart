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

import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../constants/channels.dart';
import '../di/injection.dart';
import '../errors/failures.dart';
import '../utils/error_logger.dart';
import '../widgets/cached_artwork.dart';
import 'xdm_backend_service.dart';
import 'ytm_account_service.dart';
import 'ytm_service.dart';

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
  static const int _maxConcurrentDownloads = 3;

  final HttpClient _http;
  final YtmService _ytmService;
  final MediaScannerService _scanner;
  final IMusicRepository _repository;

  final Queue<_QueuedDownload> _queue = Queue<_QueuedDownload>();
  final Map<String, _QueuedDownload> _activeDownloads = {};
  static const int _maxCanceledIds = 200;
  final Set<String> _canceledVideoIds = <String>{};

  YtDownloadService(
      this._http, this._ytmService, this._scanner, this._repository);

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
    final active = _activeDownloads[videoId];
    if (active != null) {
      active.completer.future
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
    _processQueue();

    return completer.future;
  }

  void _processQueue() {
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
  }

  Future<Result<int>> _executeDownload(_QueuedDownload task) async {
    final song = task.song;
    final videoId = song.remoteId!;
    final onProgress = task.onProgress;

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

      // 1. Ensure PoToken attestation is fresh before requesting stream
      await _ytmService.ensurePoTokenReady();

      final quality = prefs.getString('setting_download_quality') ?? 'high';
      var stream = await _resolveDownloadStream(videoId, quality);

      // Pre-download storage check (BUG-06)
      try {
        final freeBytes =
            await _downloadChannel.invokeMethod<int>('getFreeDiskSpace');
        if (freeBytes != null && freeBytes > 0) {
          final estBitrate = stream.bitrateKbps > 0 ? stream.bitrateKbps : 160;
          final estDurationSec =
              stream.duration.inSeconds > 0 ? stream.duration.inSeconds : 240;
          final estimatedBytes =
              (estDurationSec * estBitrate * 1000 ~/ 8) + (5 * 1024 * 1024);
          if (freeBytes < estimatedBytes) {
            return const Left(
                DownloadFailure('Insufficient storage space for download'));
          }
        }
      } catch (_) {}

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
                await Future.delayed(const Duration(seconds: 1));
              }
            }
          }
          return null;
        });
      }

      onProgress
          ?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0));

      // 2. Download audio with transparent 403 re-resolution & resume
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
            DownloadFailure('Downloaded audio file is corrupt or incomplete'));
      }

      // 3. Tagging
      if (stream.isTaggable) {
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.tagging));
        final artPath = artworkFuture != null ? await artworkFuture : null;
        await _tag(temp.path, song, artworkPath: artPath);
      }

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.saving));
      final displayName =
          '${_sanitize(song.artist)} - ${_sanitize(song.title)}.$ext';
      final finalPath =
          await _downloadChannel.invokeMethod<String>('saveToMusic', {
        'sourcePath': temp.path,
        'displayName': displayName,
        'title': song.title,
        'mimeType': stream.mimeType,
      });
      if (finalPath == null || finalPath.isEmpty) {
        return const Left(DownloadFailure('MediaStore did not return a path'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
      final reconciled = await _repository.reconcileDownloadedSong(
        oldId: song.id,
        newPath: finalPath,
        fallbackSong: song,
      );

      unawaited(_scanner.scanDeviceLibrary());

      return reconciled.fold(
        (f) => Left(f),
        (newId) {
          if (newId == null) {
            return const Left(DownloadFailure(
                'Downloaded file was not found in the library'));
          }
          onProgress?.call(const YtDownloadProgress(YtDownloadStage.done, 1));
          return Right(newId);
        },
      );
    } on YtmException catch (e) {
      if (e.isBotBlocked) {
        return const Left(DownloadFailure(
          'YouTube is rate-limiting downloads. Try again in a few minutes.',
        ));
      }
      return Left(DownloadFailure(
        e.isNetwork
            ? 'No connection while downloading'
            : 'Could not resolve this track',
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
            attempts >= maxAttempts ||
            task.isCanceled ||
            _canceledVideoIds.contains(videoId)) {
          rethrow;
        }

        // Transparent 403 / failure re-resolution via same engine chain
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
        final freeBytes =
            await _downloadChannel.invokeMethod<int>('getFreeDiskSpace') ?? 0;
        if (freeBytes > 0 && freeBytes < total) {
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
          if (task.isCanceled ||
              _canceledVideoIds.contains(task.song.remoteId)) {
            throw const DownloadFailure('Download canceled');
          }

          final req = await _http.getUrl(uri);
          _applyStreamHeaders(req, userAgent,
              cookies: cookies, range: 'bytes=$start-$end');
          final resp = await req.close();

          if (resp.statusCode == HttpStatus.forbidden ||
              resp.statusCode == 429) {
            throw const YtmException(
                'YTM_BOT_BLOCKED', 'Rate limited or forbidden');
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
              sink.add(chunk);
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
    } finally {
      for (final part in tempParts) {
        try {
          if (await part.exists()) {
            await part.delete();
          }
        } catch (_) {}
      }
      final outPartFile = File('${dest.path}.part');
      try {
        if (await outPartFile.exists()) {
          await outPartFile.delete();
        }
      } catch (_) {}
      if (!mergeCompleted) {
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (_) {}
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
  }) async {
    final stopwatch = Stopwatch()..start();
    final request = await _http.openUrl('GET', uri);
    _applyStreamHeaders(request, userAgent, cookies: cookies);
    final response = await request.close();

    if (response.statusCode == HttpStatus.forbidden ||
        response.statusCode == 429) {
      throw const YtmException('YTM_BOT_BLOCKED', 'Rate limited or forbidden');
    }

    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw DownloadFailure('Server returned ${response.statusCode}');
    }

    final total = response.contentLength;
    final partFile = File('${dest.path}.part');
    final sink = partFile.openWrite();
    var received = 0;
    var lastEmitTime = 0;

    try {
      await for (final chunk in response) {
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastEmitTime > 80 || (total > 0 && received == total)) {
            lastEmitTime = now;
            final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
            final speedKbps =
                elapsedSeconds > 0 ? (received / elapsedSeconds) / 1024.0 : 0.0;
            final fraction =
                total > 0 ? (received / total).clamp(0.0, 1.0) : null;
            final remainingBytes = total > 0 ? total - received : 0;
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
    } finally {
      await sink.close();
    }

    if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {}
      throw const DownloadFailure('Download canceled');
    }

    if (await partFile.exists()) {
      if (await dest.exists()) {
        await dest.delete();
      }
      await partFile.rename(dest.path);
    }
  }

  Future<void> cleanOrphanPartFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('ytdl_') || name.contains('.part')) {
              try {
                final stat = await entity.stat();
                if (DateTime.now().difference(stat.modified) >
                    const Duration(minutes: 5)) {
                  await entity.delete();
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
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
      });
    } on PlatformException catch (e) {
      ErrorLogger.log('Tagging downloaded track failed: ${e.code}',
          category: 'YTM');
    }
  }

  static String sanitizeFilename(String artist, String title, String ext) {
    var rawArtist = artist.trim();
    var rawTitle = title.trim();
    if (rawArtist.isEmpty) rawArtist = 'Unknown Artist';
    if (rawTitle.isEmpty) rawTitle = 'Unknown Title';

    // 1. Strip reserved characters and control characters (BUG-015)
    var cleanedArtist =
        rawArtist.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    var cleanedTitle =
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
    if (base.isEmpty) base = 'Track';

    return '$base.$ext';
  }

  static String _sanitize(String value, [String? ext]) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    final maxLen = ext != null ? (120 - ext.length - 1).clamp(20, 120) : 120;
    final truncated =
        cleaned.length > maxLen ? cleaned.substring(0, maxLen) : cleaned;
    return truncated.isEmpty ? 'Unknown' : truncated;
  }
}
