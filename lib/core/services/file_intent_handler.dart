import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../constants/audio_formats.dart';
import '../di/injection.dart';
import '../router/app_router.dart';
import '../utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../constants/channels.dart';
import '../network/proxy_config.dart';
import '../../data/services/ytm_service.dart';

@singleton
class FileIntentHandler {
  static const MethodChannel _channel = MethodChannel(PulsrChannels.fileOpener);
  static int _tempIdCounter = 0;
  static int _getNextTempId() {
    _tempIdCounter++;
    final unique = DateTime.now().microsecondsSinceEpoch;
    return -(unique * 1000 + (_tempIdCounter % 1000));
  }

  final IMusicRepository _repository;
  final PlayerCubit _playerCubit;

  FileIntentHandler(this._repository, this._playerCubit) {
    _initChannel();
  }

  final Set<String> _recentUris = <String>{};
  Timer? _recentClearTimer;

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onAudioFileOpened') {
          final uri = call.arguments as String?;
          if (uri != null) {
            await handleAudioUri(uri);
          }
        }
      } catch (e, st) {
        ErrorLogger.log('FileIntent channel handler error', error: e, stackTrace: st, category: 'FileIntentHandler');
      }
    });
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _recentClearTimer?.cancel();
  }

  bool _isDuplicateUri(String uri) {
    if (_recentUris.contains(uri)) return true;
    _recentUris.add(uri);
    _recentClearTimer?.cancel();
    _recentClearTimer = Timer(const Duration(seconds: 3), () => _recentUris.clear());
    return false;
  }

  Future<void> checkInitialUri() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    try {
      final initialUri =
          await _channel.invokeMethod<String>('getInitialAudioUri').timeout(const Duration(seconds: 2));
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
        RegExp(r'(?:https?:\/\/)?(?:www\.)?youtu\.be\/([a-zA-Z0-9_-]{11})')
            .firstMatch(trimmed);
    if (youTubeShort != null) return youTubeShort.group(1);

    final youTubeLong = RegExp(
            r'(?:https?:\/\/)?(?:(?:[a-zA-Z0-9-]+\.)*youtube\.com|youtube-nocookie\.com)\/(?:(?:watch\?.*?v=)|(?:v|embed|shorts)\/)([a-zA-Z0-9_-]{11})')
        .firstMatch(trimmed);
    if (youTubeLong != null) return youTubeLong.group(1);

    // Fallback: only if it contains youtube.com or youtu.be
    if (trimmed.contains('youtube.com') || trimmed.contains('youtu.be')) {
      final fallback = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(trimmed);
      if (fallback != null) return fallback.group(1);
    }

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
      final stream = await ytmService.resolveStream(videoId).timeout(const Duration(seconds: 12));

      final track = YtmTrack(
        videoId: videoId,
        title: stream.title.isNotEmpty ? stream.title : 'YouTube Track',
        artist: stream.artist.isNotEmpty ? stream.artist : 'YouTube Music',
        duration: stream.duration,
        artworkUrl: stream.artworkUrl,
      );

      final song = track.toSongData();
      await _playerCubit.playSong(song);
      unawaited(rootNavigatorKey.currentContext?.push('/now-playing'));
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
    if (_isDuplicateUri(uriOrPath)) return;
    try {
      final videoId = extractYouTubeVideoId(uriOrPath);
      if (videoId != null && AppConfig.ytmEnabled) {
        await _handleYouTubeLink(videoId);
        return;
      }

      String cleanPath;
      try {
        cleanPath = Uri.decodeFull(uriOrPath);
      } catch (_) {
        cleanPath = uriOrPath;
      }
      if (cleanPath.startsWith('file://')) {
        try {
          final parsed = Uri.parse(cleanPath);
          if (parsed.scheme == 'file' && parsed.path.isNotEmpty) {
            cleanPath = parsed.path;
          } else {
            cleanPath = cleanPath.replaceFirst('file://', '');
          }
        } catch (_) {
          cleanPath = cleanPath.replaceFirst('file://', '');
        }
      }

      // 1. Check if it's a PLAYABLE audio file FIRST (fast-path).
      // content:// URIs skip the extension gate: file managers and media providers
      // frequently hand out extension-less URIs (content://media/.../<id>, msf:<id>)
      // that ARE audio (MainActivity.isAudioIntent already gated by intent mime type
      // audio/* before invoking Dart). The extension check would falsely reject them
      // with "Format not supported" and the song would never play.
      final isContentUri =
          cleanPath.startsWith('content:') || uriOrPath.startsWith('content:');
      if (isContentUri || AudioFormats.isSupportedExtension(cleanPath)) {
        // Proceed directly to audio handling below
      } else {
        // 2. Only check for proxy/text files if NOT audio
        final isTextExt = cleanPath.toLowerCase().endsWith('.txt') ||
            cleanPath.toLowerCase().endsWith('.list') ||
            cleanPath.toLowerCase().endsWith('.conf') ||
            cleanPath.toLowerCase().endsWith('.csv');

        if (isTextExt) {
          try {
            final file = File(cleanPath);
            if (await file.exists()) {
              final content = await file.readAsString();
              final proxies = ProxyEntry.parseList(content);
              if (proxies.isNotEmpty) {
                final navCtx = rootNavigatorKey.currentContext;
                if (navCtx != null && navCtx.mounted) {
                  unawaited(navCtx.push('/proxy-settings', extra: content));
                }
                return;
              }
            }
          } catch (_) {}
        } else {
          final parsedProxies = ProxyEntry.parseList(uriOrPath);
          if (parsedProxies.isNotEmpty) {
            final navCtx = rootNavigatorKey.currentContext;
            if (navCtx != null && navCtx.mounted) {
              unawaited(navCtx.push('/proxy-settings', extra: uriOrPath));
            }
            return;
          }
        }

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
        final navCtx = rootNavigatorKey.currentContext;
        if (navCtx != null && navCtx.mounted) {
          unawaited(navCtx.push('/now-playing'));
        }
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
          final decoded = Uri.decodeComponent(segment);
          // Media-provider URIs end in opaque ids ("1000000123", "msf:1000000123").
          // Prefer a readable display name from query params when present,
          // otherwise fall back to a generic title instead of the raw id.
          final qpTitle = parsedUri?.queryParameters['displayName'] ??
              parsedUri?.queryParameters['title'];
          if (qpTitle != null && qpTitle.trim().isNotEmpty) {
            title = p.withoutExtension(qpTitle.trim());
          } else if (decoded.contains('.') &&
              !decoded.endsWith('.') &&
              !decoded.contains(':')) {
            title = p.withoutExtension(decoded);
          } else {
            title = 'Audio Track';
          }
        }
      } else {
        final file = File(cleanPath);
        final filename = file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'Audio File';
        title = p.withoutExtension(filename);
        try {
          if (await file.exists()) {
            fileSize = await file.length();
          }
        } catch (_) {}
      }

      final tempSong = SongsTableData(
        id: _getNextTempId(),
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
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );

      await _playerCubit.playSong(tempSong);
      final navCtx = rootNavigatorKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        unawaited(navCtx.push('/now-playing'));
      }
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


