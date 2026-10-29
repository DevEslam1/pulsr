// lib/data/services/download_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/channels.dart';
import '../../core/di/injection.dart';
import '../../core/utils/error_logger.dart';
import '../repositories/lyrics_repository.dart';

/// Service responsible for post-download audio tagging, metadata standardization,
/// and embedded/sidecar lyrics management.
@lazySingleton
class DownloadService {
  static const _tagChannel = MethodChannel(PulsrChannels.tagEditor);

  /// Containers supported by jaudiotagger / native tag editors.
  static const Set<String> _taggableContainers = {
    'm4a',
    'mp4',
    'flac',
    'mp3',
    'ogg',
    'oga',
  };

  final LyricsRepository? _lyricsRepository;

  DownloadService({LyricsRepository? lyricsRepository})
      : _lyricsRepository = lyricsRepository;

  LyricsRepository? get _effectiveLyricsRepo =>
      _lyricsRepository ??
      (getIt.isRegistered<LyricsRepository>()
          ? getIt<LyricsRepository>()
          : null);

  /// Whether a file with [extension] can have metadata embedded.
  static bool carriesTags(String extension) {
    final clean = extension.toLowerCase().replaceAll('.', '').trim();
    return _taggableContainers.contains(clean);
  }

  /// Writes tags and embeds or writes sidecar lyrics for a downloaded file.
  ///
  /// On completion:
  /// - Tags (title, artist, album, track number, cover art) are written.
  /// - Lyrics are fetched from [LyricsRepository].
  /// - If container supports embedded tags, lyrics are embedded into the file.
  /// - If container doesn't support embedded tags or embedding fails, a sidecar `.lrc`
  ///   file is saved alongside the audio file.
  Future<void> tagCompletedDownload({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int? trackNumber,
    String? genre,
    int? year,
    String? artworkPath,
    String? videoId,
    int? durationMs,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      ErrorLogger.log(
        'Cannot tag downloaded track: file does not exist at $filePath',
        category: 'DownloadService',
      );
      return;
    }

    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    final canEmbed = carriesTags(ext);

    // 1. Fetch lyrics via LyricsRepository
    String? lrcContent;
    try {
      final lyricsRepo = _effectiveLyricsRepo;
      if (lyricsRepo != null) {
        lrcContent = await lyricsRepo
            .fetchLyricsLrc(
              title: title,
              artist: artist,
              album: album,
              durationMs: durationMs,
              videoId: videoId,
            )
            .timeout(const Duration(seconds: 10));
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to fetch lyrics for download tagging: $videoId',
        error: e,
        stackTrace: st,
        category: 'DownloadService',
      );
    }

    var embeddedSucceeded = false;

    // 2. Embed tags if container supports it
    if (canEmbed) {
      embeddedSucceeded = await writeTags(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album ?? (title.isNotEmpty ? title : 'Unknown Album'),
        trackNumber: trackNumber ?? 1,
        genre: genre,
        year: year,
        artworkPath: artworkPath,
        lyrics: lrcContent,
      );
    }

    // 3. If container does not support embedded tags or embedding failed,
    // write sidecar .lrc alongside the audio file.
    if ((!canEmbed || !embeddedSucceeded) &&
        lrcContent != null &&
        lrcContent.trim().isNotEmpty) {
      await saveSidecarLrc(filePath, lrcContent);
    }
  }

  /// Writes tags directly into supported audio containers via platform tag editor.
  Future<bool> writeTags({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int? trackNumber,
    String? genre,
    int? year,
    String? artworkPath,
    String? lyrics,
  }) =>
      writeAudioTags(
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        trackNumber: trackNumber,
        genre: genre,
        year: year,
        artworkPath: artworkPath,
        lyrics: lyrics,
      );

  /// Shared static implementation for writing audio container tags with retry.
  static Future<bool> writeAudioTags({
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int? trackNumber,
    String? genre,
    int? year,
    String? artworkPath,
    String? lyrics,
  }) async {
    final normalizedAlbum =
        (album != null && album.isNotEmpty) ? album : 'Unknown Album';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _tagChannel.invokeMethod<Object?>('writeTags', {
          'path': filePath,
          'title': title,
          'artist': artist,
          'album': normalizedAlbum,
          'genre': genre,
          'year': year,
          'trackNumber': trackNumber ?? 1,
          'comment': null,
          'lyrics': lyrics,
          'artworkPath': artworkPath,
          'removeArtwork': false,
        });
        if (result is Map && result['verified'] == false) {
          ErrorLogger.log(
            'writeTags unverified on $filePath: ${result['verifiedFields']}',
            category: 'DownloadService',
          );
        }
        return true;
      } on PlatformException catch (e) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        } else {
          ErrorLogger.log(
            'writeTags failed on $filePath: ${e.message}',
            error: e,
            category: 'DownloadService',
          );
        }
      } catch (e, st) {
        ErrorLogger.log(
          'writeTags unexpected error on $filePath',
          error: e,
          stackTrace: st,
          category: 'DownloadService',
        );
        break;
      }
    }
    return false;
  }

  /// Saves sidecar .lrc alongside audio file.
  Future<void> saveSidecarLrc(String audioFilePath, String lrcContent) =>
      writeSidecarLrc(audioFilePath, lrcContent);

  /// Shared static implementation for saving a sidecar `.lrc` alongside [audioFilePath].
  static Future<void> writeSidecarLrc(
      String audioFilePath, String lrcContent) async {
    if (audioFilePath.startsWith('content:')) return;
    try {
      final lrcPath = '${p.withoutExtension(audioFilePath)}.lrc';
      final lrcFile = File(lrcPath);
      await lrcFile.writeAsString(lrcContent, flush: true);
      ErrorLogger.addBreadcrumb(
        'Saved sidecar .lrc at $lrcPath',
        category: 'DownloadService',
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to save sidecar .lrc for $audioFilePath',
        error: e,
        stackTrace: st,
        category: 'DownloadService',
      );
    }
  }
}
