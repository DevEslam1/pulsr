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
import 'package:pulsr/domain/models/ytm_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../errors/failures.dart';
import '../utils/error_logger.dart';
import '../widgets/cached_artwork.dart';
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

  const YtDownloadProgress(this.stage, [this.fraction]);
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
  static const _downloadChannel = MethodChannel('com.pulsr.music/yt_download');
  static const _tagChannel = MethodChannel('com.pulsr.music/tag_editor');
  static const int _maxConcurrentDownloads = 3;

  final HttpClient _http;
  final YtmService _ytmService;
  final MediaScannerService _scanner;
  final IMusicRepository _repository;

  final Queue<_QueuedDownload> _queue = Queue<_QueuedDownload>();
  final Map<String, _QueuedDownload> _activeDownloads = {};
  final Set<String> _canceledVideoIds = {};

  YtDownloadService(
      this._http, this._ytmService, this._scanner, this._repository);

  /// Cancels an active or queued download.
  void cancel(String videoId) {
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
        task.completer
            .complete(const Left(DownloadFailure('Download canceled')));
        continue;
      }

      _activeDownloads[videoId] = task;
      _executeDownload(task).then((result) {
        task.completer.complete(result);
      }).catchError((e) {
        task.completer.complete(Left(DownloadFailure('Download error: $e')));
      }).whenComplete(() {
        _activeDownloads.remove(videoId);
        _processQueue();
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
    try {
      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.resolving));

      // 1. Ensure PoToken attestation is fresh before requesting stream
      await _ytmService.ensurePoTokenReady();

      final quality = prefs.getString('setting_download_quality') ?? 'high';
      var stream = await _ytmService.resolveStream(videoId, quality: quality);

      final ext = stream.container.isNotEmpty ? stream.container : 'm4a';
      final dir = await getTemporaryDirectory();
      temp = File(p.join(dir.path, 'ytdl_$videoId.$ext'));

      if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
        return const Left(DownloadFailure('Download canceled'));
      }

      // Download high-res master artwork in parallel with the audio stream
      Future<String?>? artworkFuture;
      final rawArtUrl = song.remoteArtworkUrl;
      if (rawArtUrl != null && rawArtUrl.isNotEmpty) {
        final artUrl = CachedArtwork.upgradeToHighResArtwork(rawArtUrl);
        artworkFuture = Future(() async {
          try {
            final artFile = File(p.join(dir.path, 'ytdl_art_$videoId.jpg'));
            await _downloadFileResilient(artUrl, artFile, task, null);
            if (await artFile.exists() && await artFile.length() > 0) {
              tempArt = artFile;
              return artFile.path;
            }
          } catch (e) {
            ErrorLogger.log('Parallel artwork download failed',
                error: e, category: 'YTM');
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
      if (temp != null && await temp.exists()) {
        await temp.delete().catchError((_) => temp!);
      }
      if (tempArt != null && await tempArt!.exists()) {
        await tempArt!.delete().catchError((_) => tempArt!);
      }
    }
  }

  Future<void> _downloadAudioWithRetry({
    required YtmStream stream,
    required String videoId,
    required String quality,
    required File dest,
    required _QueuedDownload task,
    required void Function(YtDownloadProgress)? onProgress,
  }) async {
    var currentUrl = stream.url;
    var attempts = 0;
    const maxAttempts = 3;

    while (attempts < maxAttempts) {
      try {
        if (task.isCanceled || _canceledVideoIds.contains(videoId)) {
          throw const DownloadFailure('Download canceled');
        }

        await _downloadFileResilient(currentUrl, dest, task, onProgress);
        return;
      } catch (e) {
        attempts++;
        debugPrint(
            '[YtDownloadService] Download attempt $attempts failed for $videoId: $e');

        if (attempts >= maxAttempts ||
            task.isCanceled ||
            _canceledVideoIds.contains(videoId)) {
          rethrow;
        }

        // Re-resolve stream URL with fresh token
        await _ytmService.invalidatePoToken();
        await _ytmService.ensurePoTokenReady();
        final freshStream =
            await _ytmService.resolveStream(videoId, quality: quality);
        currentUrl = freshStream.url;
      }
    }
  }

  static const int _concurrentChunks = 4;
  static const int _minChunkThreshold = 1024 * 1024; // 1 MB

  Future<void> _downloadFileResilient(
    String url,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress,
  ) async {
    final uri = Uri.parse(url);

    // Initial probe to test HTTP Range support and fetch content length
    try {
      final probeReq = await _http.openUrl('GET', uri);
      probeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final probeResp = await probeReq.close();

      final contentRange =
          probeResp.headers.value(HttpHeaders.contentRangeHeader);
      int total = -1;
      if (contentRange != null && contentRange.contains('/')) {
        total = int.tryParse(contentRange.split('/').last) ?? -1;
      }
      await probeResp.drain<void>();

      if (probeResp.statusCode == HttpStatus.forbidden ||
          probeResp.statusCode == HttpStatus.unauthorized) {
        throw const YtmException(
            'YTM_BOT_BLOCKED', 'HTTP 403 Forbidden on stream probe');
      }

      if (probeResp.statusCode == HttpStatus.partialContent &&
          total >= _minChunkThreshold) {
        await _downloadParallel(uri, dest, total, task, onProgress);
        return;
      }
    } catch (e) {
      if (e is YtmException || e is DownloadFailure) rethrow;
    }

    await _downloadSequential(uri, dest, task, onProgress);
  }

  Future<void> _downloadParallel(
    Uri uri,
    File dest,
    int total,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress,
  ) async {
    final chunkSize = (total / _concurrentChunks).ceil();
    final tempParts = <File>[];
    final dir = dest.parent;

    var totalReceived = 0;
    var lastEmitTime = 0;

    try {
      final futures = <Future<void>>[];

      for (var i = 0; i < _concurrentChunks; i++) {
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
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
          final resp = await req.close();

          if (resp.statusCode == HttpStatus.forbidden ||
              resp.statusCode == 429) {
            throw const YtmException(
                'YTM_BOT_BLOCKED', 'Rate limited or forbidden');
          }

          if (resp.statusCode != HttpStatus.partialContent &&
              resp.statusCode != HttpStatus.ok) {
            throw DownloadFailure(
                'Server returned ${resp.statusCode} for chunk $i');
          }

          final sink = partFile.openWrite();
          try {
            await for (final chunk in resp) {
              if (task.isCanceled ||
                  _canceledVideoIds.contains(task.song.remoteId)) {
                throw const DownloadFailure('Download canceled');
              }
              sink.add(chunk);
              totalReceived += chunk.length;
              if (onProgress != null && total > 0) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - lastEmitTime > 80 || totalReceived == total) {
                  lastEmitTime = now;
                  onProgress(YtDownloadProgress(
                    YtDownloadStage.downloading,
                    (totalReceived / total).clamp(0.0, 1.0),
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

      final outSink = dest.openWrite();
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
    } finally {
      for (final part in tempParts) {
        if (await part.exists()) {
          await part.delete().catchError((_) => part);
        }
      }
    }
  }

  Future<void> _downloadSequential(
    Uri uri,
    File dest,
    _QueuedDownload task,
    void Function(YtDownloadProgress)? onProgress,
  ) async {
    final request = await _http.getUrl(uri);
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
    final sink = dest.openWrite();
    var received = 0;
    var lastEmitTime = 0;

    try {
      await for (final chunk in response) {
        if (task.isCanceled || _canceledVideoIds.contains(task.song.remoteId)) {
          throw const DownloadFailure('Download canceled');
        }
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null && total > 0) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastEmitTime > 80 || received == total) {
            lastEmitTime = now;
            onProgress(YtDownloadProgress(
                YtDownloadStage.downloading, received / total));
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
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
      });
    } on PlatformException catch (e) {
      ErrorLogger.log('Tagging downloaded track failed: ${e.code}',
          category: 'YTM');
    }
  }

  static String _sanitize(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }
}
