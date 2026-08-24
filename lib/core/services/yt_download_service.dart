// lib/core/services/yt_download_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../errors/failures.dart';
import '../utils/error_logger.dart';
import 'ytm_service.dart';

/// Where a download currently is, for driving progress UI.
enum YtDownloadStage { resolving, downloading, tagging, saving, indexing, done }

class YtDownloadProgress {
  final YtDownloadStage stage;

  /// 0..1 during [YtDownloadStage.downloading], null when indeterminate.
  final double? fraction;

  const YtDownloadProgress(this.stage, [this.fraction]);
}

/// Turns a streaming YouTube row into a permanent local file: resolves a fresh
/// URL, downloads the M4A, tags it, hands it to the native MediaStore writer,
/// then folds the negative YT row into the scanned local row.
@lazySingleton
class YtDownloadService {
  static const _downloadChannel = MethodChannel('com.pulsr.music/yt_download');
  static const _tagChannel = MethodChannel('com.pulsr.music/tag_editor');

  final HttpClient _http;
  final YtmService _ytmService;
  final MediaScannerService _scanner;
  final IMusicRepository _repository;

  YtDownloadService(this._http, this._ytmService, this._scanner, this._repository);

  /// Downloads [song] (which must be a `source == youtube` row) and returns the
  /// surviving positive song id once it is a local library track.
  Future<Result<int>> download(
    SongsTableData song, {
    void Function(YtDownloadProgress)? onProgress,
  }) async {
    if (song.source != SongSource.youtube) {
      return const Left(DownloadFailure('Only YouTube tracks can be downloaded'));
    }
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      return const Left(DownloadFailure('Track has no video id'));
    }

    final prefs = await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      return const Left(DownloadFailure('Offline Only Mode is active in Settings'));
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        return const Left(DownloadFailure('Wi-Fi Only Mode is active. Connect to Wi-Fi to download.'));
      }
    }

    File? temp;
    try {
      onProgress?.call(const YtDownloadProgress(YtDownloadStage.resolving));
      final quality = prefs.getString('setting_download_quality') ?? 'high';
      final stream = await _ytmService.resolveStream(videoId, quality: quality);

      final ext = stream.container.isNotEmpty ? stream.container : 'm4a';
      final dir = await getTemporaryDirectory();
      temp = File(p.join(dir.path, 'ytdl_$videoId.$ext'));

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.downloading, 0));
      await _downloadTo(stream.url, temp, onProgress);

      // jaudiotagger can only write real M4A; skip tagging Opus/WebM downloads.
      if (stream.isTaggable) {
        onProgress?.call(const YtDownloadProgress(YtDownloadStage.tagging));
        await _tag(temp.path, song);
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.saving));
      final displayName = '${_sanitize(song.artist)} - ${_sanitize(song.title)}.$ext';
      final finalPath = await _downloadChannel.invokeMethod<String>('saveToMusic', {
        'sourcePath': temp.path,
        'displayName': displayName,
        'title': song.title,
        'mimeType': stream.mimeType,
      });
      if (finalPath == null || finalPath.isEmpty) {
        return const Left(DownloadFailure('MediaStore did not return a path'));
      }

      onProgress?.call(const YtDownloadProgress(YtDownloadStage.indexing));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _scanner.scanDeviceLibrary();

      final reconciled = await _repository.reconcileDownloadedSong(
        oldId: song.id,
        newPath: finalPath,
      );
      return reconciled.fold(
        (f) => Left(f),
        (newId) {
          if (newId == null) {
            return const Left(DownloadFailure('Downloaded file was not found in the library'));
          }
          onProgress?.call(const YtDownloadProgress(YtDownloadStage.done, 1));
          return Right(newId);
        },
      );
    } on YtmException catch (e) {
      return Left(DownloadFailure(
        e.isNetwork ? 'No connection while downloading' : 'Could not resolve this track',
        e,
      ));
    } on PlatformException catch (e) {
      ErrorLogger.log('YT download native call failed: ${e.code}', error: e, category: 'YTM');
      return Left(DownloadFailure(e.message ?? 'Failed to save the download', e));
    } catch (e, st) {
      ErrorLogger.log('YT download failed', error: e, stackTrace: st, category: 'YTM');
      return Left(DownloadFailure('Download failed', e));
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete().catchError((_) => temp!);
      }
    }
  }

  Future<void> _downloadTo(String url, File dest, void Function(YtDownloadProgress)? onProgress) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw DownloadFailure('Server returned ${response.statusCode}');
    }
    final total = response.contentLength;
    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null && total > 0) {
          onProgress(YtDownloadProgress(YtDownloadStage.downloading, received / total));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<void> _tag(String path, SongsTableData song) async {
    File? tempArt;
    try {
      String? artworkPath;
      final artUrl = song.remoteArtworkUrl;
      if (artUrl != null && artUrl.isNotEmpty) {
        try {
          final dir = await getTemporaryDirectory();
          final videoId = song.remoteId ?? song.id.toString();
          tempArt = File(p.join(dir.path, 'ytdl_art_$videoId.jpg'));
          await _downloadTo(artUrl, tempArt, null);
          if (await tempArt.exists() && await tempArt.length() > 0) {
            artworkPath = tempArt.path;
          }
        } catch (e) {
          // If artwork download fails, still write text metadata
          ErrorLogger.log('Downloading artwork for tag failed', error: e, category: 'YTM');
        }
      }

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
      // A tag failure must not abort the download — the file still plays.
      ErrorLogger.log('Tagging downloaded track failed: ${e.code}', category: 'YTM');
    } finally {
      if (tempArt != null && await tempArt.exists()) {
        await tempArt.delete().catchError((_) => tempArt!);
      }
    }
  }

  /// Strips characters MediaStore/filesystems reject in a DISPLAY_NAME.
  static String _sanitize(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }
}
