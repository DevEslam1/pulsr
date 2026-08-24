import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import '../constants/audio_formats.dart';
import '../router/app_router.dart';
import '../utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';

@singleton
class FileIntentHandler {
  static const MethodChannel _channel = MethodChannel('com.pulsr.music/file_opener');
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
      final initialUri = await _channel.invokeMethod<String>('getInitialAudioUri');
      if (initialUri != null) {
        await handleAudioUri(initialUri);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to check initial audio URI', error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }

  Future<void> handleAudioUri(String uriOrPath) async {
    try {
      String cleanPath = Uri.decodeFull(uriOrPath);
      if (cleanPath.startsWith('file://')) {
        cleanPath = cleanPath.replaceFirst('file://', '');
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
        final segment = parsedUri?.pathSegments.isNotEmpty == true ? parsedUri!.pathSegments.last : null;
        if (segment != null && segment.isNotEmpty) {
          title = Uri.decodeComponent(segment).replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        }
      } else {
        final file = File(cleanPath);
        final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'Audio File';
        title = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        try {
          if (file.existsSync()) {
            fileSize = file.lengthSync();
          }
        } catch (_) {}
      }

      final tempSong = SongsTableData(
        id: -1 * (math.Random().nextInt(900000) + 100000),
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
      ErrorLogger.log('Failed to handle external audio URI: $uriOrPath', error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }
}
