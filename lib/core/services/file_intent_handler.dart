import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import '../config/app_config.dart';
import '../constants/audio_formats.dart';
import '../di/injection.dart';
import '../router/app_router.dart';
import '../utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../network/proxy_config.dart';
import 'ytm_service.dart';

@singleton
class FileIntentHandler {
  static const MethodChannel _channel =
      MethodChannel('com.pulsr.music/file_opener');
  static int _nextTempId = -100000;
  final IMusicRepository _repository;
  final PlayerCubit _playerCubit;

  FileIntentHandler(this._repository, this._playerCubit) {
    _initChannel();
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAudioFileOpened') {
        final uri = call.arguments as String?;
        if (uri != null) {
          await handleAudioUri(uri);
        }
      }
    });
  }

  Future<void> checkInitialUri() async {
    try {
      final initialUri =
          await _channel.invokeMethod<String>('getInitialAudioUri');
      if (initialUri != null) {
        await handleAudioUri(initialUri);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to check initial audio URI',
          error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }

  static String? extractYouTubeVideoId(String input) {
    final trimmed = input.trim();
    // Reject anything that looks like a file path when checking raw 11-char ID
    if (!trimmed.contains('/') &&
        !trimmed.contains('\\') &&
        !trimmed.contains('.') &&
        RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    final youTubeShort =
        RegExp(r'youtu\.be\/([a-zA-Z0-9_-]{11})').firstMatch(trimmed);
    if (youTubeShort != null) return youTubeShort.group(1);

    final youTubeLong = RegExp(
            r'(?:v=|\/shorts\/|\/embed\/|\/watch\/|\/v\/)([a-zA-Z0-9_-]{11})')
        .firstMatch(trimmed);
    if (youTubeLong != null) return youTubeLong.group(1);

    final fallback = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(trimmed);
    if (fallback != null) return fallback.group(1);

    return null;
  }

  Future<void> _handleYouTubeLink(String videoId) async {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening YouTube Music track...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      final ytmService = getIt<YtmService>();
      final stream = await ytmService.resolveStream(videoId);

      final track = YtmTrack(
        videoId: videoId,
        title: stream.title.isNotEmpty ? stream.title : 'YouTube Track',
        artist: stream.artist.isNotEmpty ? stream.artist : 'YouTube Music',
        duration: stream.duration,
        artworkUrl: stream.artworkUrl,
      );

      final song = track.toSongData();
      await _playerCubit.playSong(song);
      rootNavigatorKey.currentContext?.push('/now-playing');
    } catch (e, st) {
      ErrorLogger.log('Failed to resolve YouTube link: $videoId',
          error: e, stackTrace: st, category: 'FileIntentHandler');
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Failed to load YouTube track: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> handleAudioUri(String uriOrPath) async {
    try {
      final videoId = extractYouTubeVideoId(uriOrPath);
      if (videoId != null && AppConfig.ytmEnabled) {
        await _handleYouTubeLink(videoId);
        return;
      }

      String cleanPath = Uri.decodeFull(uriOrPath);
      if (cleanPath.startsWith('file://')) {
        cleanPath = cleanPath.replaceFirst('file://', '');
      }

      // Check if this is a shared proxy list text or text file (.txt, .list, .conf, .csv)
      final isTextExt = cleanPath.toLowerCase().endsWith('.txt') ||
          cleanPath.toLowerCase().endsWith('.list') ||
          cleanPath.toLowerCase().endsWith('.conf') ||
          cleanPath.toLowerCase().endsWith('.csv');

      if (isTextExt) {
        try {
          final file = File(cleanPath);
          if (file.existsSync()) {
            final content = await file.readAsString();
            final proxies = ProxyEntry.parseList(content);
            if (proxies.isNotEmpty) {
              rootNavigatorKey.currentContext
                  ?.push('/proxy-settings', extra: content);
              return;
            }
          }
        } catch (_) {}
      } else {
        final parsedProxies = ProxyEntry.parseList(uriOrPath);
        if (parsedProxies.isNotEmpty &&
            !AudioFormats.isPlayableExtension(cleanPath)) {
          rootNavigatorKey.currentContext
              ?.push('/proxy-settings', extra: uriOrPath);
          return;
        }
      }

      if (!AudioFormats.isPlayableExtension(cleanPath)) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Format not supported on this device'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // 1. Fast indexed check if song already exists in library database (Issue #19)
      final pathMatchRes = await _repository.getSongByPath(cleanPath);
      var match = pathMatchRes.fold((l) => null, (r) => r);

      if (match == null && uriOrPath != cleanPath) {
        final uriMatchRes = await _repository.getSongByUri(uriOrPath);
        match = uriMatchRes.fold((l) => null, (r) => r);
      }

      if (match != null) {
        await _playerCubit.playSong(match);
        rootNavigatorKey.currentContext?.push('/now-playing');
        return;
      }

      // 2. If not yet indexed in database, build standalone playable SongsTableData
      // Use negative ID to guarantee zero collision with positive MediaStore database IDs
      final isContentScheme = uriOrPath.startsWith('content://');
      String title = 'Audio File';
      int? fileSize;

      if (isContentScheme) {
        final parsedUri = Uri.tryParse(uriOrPath);
        final segment = parsedUri?.pathSegments.isNotEmpty == true
            ? parsedUri!.pathSegments.last
            : null;
        if (segment != null && segment.isNotEmpty) {
          title = Uri.decodeComponent(segment)
              .replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        }
      } else {
        final file = File(cleanPath);
        final filename = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'Audio File';
        title = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        try {
          if (file.existsSync()) {
            fileSize = file.lengthSync();
          }
        } catch (_) {}
      }

      final tempSong = SongsTableData(
        id: _nextTempId--,
        title: title.isNotEmpty ? title : 'External Audio',
        artist: 'External Audio',
        album: 'Files',
        durationMs: 0,
        path: cleanPath,
        uri: uriOrPath,
        source: SongSource.local,
        fileSize: fileSize,
        isFavorite: false,
        isMissing: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await _playerCubit.playSong(tempSong);
      rootNavigatorKey.currentContext?.push('/now-playing');
    } catch (e, st) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Format not supported on this device'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      ErrorLogger.log('Failed to handle external audio URI: $uriOrPath',
          error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }
}
