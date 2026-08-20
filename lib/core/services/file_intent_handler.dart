// lib/core/services/file_intent_handler.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import '../router/app_router.dart';
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
    } catch (_) {}
  }

  Future<void> handleAudioUri(String uriOrPath) async {
    try {
      String cleanPath = Uri.decodeFull(uriOrPath);
      if (cleanPath.startsWith('file://')) {
        cleanPath = cleanPath.replaceFirst('file://', '');
      }

      // 1. Check if song already exists in library database
      final songsRes = await _repository.getAllSongs();
      final allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);

      SongsTableData? match;
      for (final s in allSongs) {
        if (s.path == cleanPath || s.uri == uriOrPath || s.path == uriOrPath) {
          match = s;
          break;
        }
      }

      if (match != null) {
        await _playerCubit.playSong(match);
        rootNavigatorKey.currentContext?.push('/now-playing');
        return;
      }

      // 2. If not yet indexed in database, build standalone playable SongsTableData
      // Use negative ID to guarantee zero collision with positive MediaStore database IDs
      final file = File(cleanPath);
      final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'Audio File';
      final title = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

      final tempSong = SongsTableData(
        id: -1 * (math.Random().nextInt(900000) + 100000),
        title: title,
        artist: 'External Audio',
        album: 'Files',
        durationMs: 0,
        path: cleanPath,
        uri: uriOrPath,
        fileSize: file.existsSync() ? file.lengthSync() : null,
        isFavorite: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await _playerCubit.playSong(tempSong);
      rootNavigatorKey.currentContext?.push('/now-playing');
    } catch (_) {}
  }
}
