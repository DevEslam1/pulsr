import 'dart:io';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/utils/l10n_holder.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import '../config/app_config.dart';
import '../constants/audio_formats.dart';
import '../di/injection.dart';
import '../errors/failures.dart';
import '../router/app_router.dart';
import '../utils/error_logger.dart';
import '../../data/db/app_database.dart';
import '../../data/scanner/media_scanner_service.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/assistant/assistant_query.dart';
import '../../features/assistant/assistant_resolver.dart';
import '../constants/channels.dart';
import '../network/proxy_config.dart';
import 'ytm_service.dart';

@singleton
class FileIntentHandler {
  static const int _maxProxyTextBytes = 10 * 1024 * 1024;
  static const MethodChannel _channel = MethodChannel(PulsrChannels.fileOpener);
  static int _tempIdCounter = 0;
  static int _getNextTempId() {
    final rand = math.Random().nextInt(1 << 16);
    return (DateTime.now().millisecondsSinceEpoch * -1) -
        (++_tempIdCounter * 65536) -
        rand;
  }

  final IMusicRepository _repository;
  final PlayerCubit _playerCubit;

  FileIntentHandler(this._repository, this._playerCubit) {
    _initChannel();
  }

  void _initChannel() {
    _channel.setMethodCallHandler((call) async {
      try {
        if (call.method == 'onAudioFileOpened') {
          final uri = call.arguments as String?;
          if (uri != null) {
            await handleAudioUri(uri);
            await _drainPendingAudioUris();
          }
        } else if (call.method == 'onVoiceSearch') {
          final query = call.arguments as String?;
          if (query != null) {
            await handleVoiceSearch(query);
          }
        } else if (call.method == 'onMediaStoreChanged') {
          try {
            final scanner = getIt<MediaScannerService>();
            await scanner.scanDeviceLibrary(incremental: true);
          } catch (e, st) {
            ErrorLogger.log('Media store rescan failed',
                error: e, stackTrace: st, category: 'FileIntentHandler');
          }
        }
      } catch (e, st) {
        ErrorLogger.log('Error handling method call: ${call.method}',
            error: e, stackTrace: st, category: 'FileIntentHandler');
      }
    });
  }

  Future<void> checkInitialUri() async {
    try {
      final List<String> initialUris = await _invokeInitialAudioUris();
      if (initialUris.isNotEmpty) {
        await handleAudioUri(initialUris.first);
        await _enqueueAdditionalUris(initialUris.skip(1));
        return;
      }
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

  Future<List<String>> _invokeInitialAudioUris() async {
    try {
      final list = await _channel.invokeListMethod<String>('getInitialAudioUris');
      if (list != null && list.isNotEmpty) {
        return list.where((u) => u.isNotEmpty).toList();
      }
    } on MissingPluginException {
      // Fall back to legacy single-URI channel method in tests/older hosts.
    } catch (_) {
      // Ignore mocked handlers that only implement getInitialAudioUri.
    }
    return const <String>[];
  }

  Future<void> _drainPendingAudioUris() async {
    final pending = await _invokeInitialAudioUris();
    if (pending.isNotEmpty) {
      await _enqueueAdditionalUris(pending);
    }
  }

  Future<void> _enqueueAdditionalUris(Iterable<String> uris) async {
    final songs = <SongsTableData>[];
    for (final raw in uris) {
      final song = await _resolveSongForUri(raw);
      if (song != null) {
        songs.add(song);
      }
    }
    if (songs.isNotEmpty) {
      await _playerCubit.addAllToQueue(songs);
    }
  }

  static final RegExp _rawIdRegex = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  static final RegExp _shortRegex =
      RegExp(r'(?:https?:\/\/)?(?:www\.)?youtu\.be\/([a-zA-Z0-9_-]{11})');
  static final RegExp _longRegex = RegExp(
      r'(?:https?:\/\/)?(?:(?:[a-zA-Z0-9-]+\.)*youtube\.com|youtube-nocookie\.com)\/(?:(?:watch\?.*?v=)|(?:v|embed|shorts)\/)([a-zA-Z0-9_-]{11})');
  static final RegExp _fallbackRegex = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})');

  static String? extractYouTubeVideoId(String input) {
    final trimmed = input.trim();
    // Security / ReDoS guard: valid YouTube URLs and video IDs never exceed 2048 characters.
    // Early-rejecting unbounded inputs eliminates catastrophic backtracking vectors.
    if (trimmed.isEmpty || trimmed.length > 2048) {
      return null;
    }

    // Reject anything that looks like a file path when checking raw 11-char ID
    if (!trimmed.contains('/') &&
        !trimmed.contains('\\') &&
        !trimmed.contains('.') &&
        _rawIdRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    final youTubeShort = _shortRegex.firstMatch(trimmed);
    if (youTubeShort != null) return youTubeShort.group(1);

    final youTubeLong = _longRegex.firstMatch(trimmed);
    if (youTubeLong != null) return youTubeLong.group(1);

    // Fallback: only if it contains youtube.com or youtu.be
    if (trimmed.contains('youtube.com') || trimmed.contains('youtu.be')) {
      final fallback = _fallbackRegex.firstMatch(trimmed);
      if (fallback != null) return fallback.group(1);
    }

    return null;
  }

  Future<void> _handleYouTubeLink(String videoId) async {
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.openingYtmTrack),
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
        title: stream.title.isNotEmpty
            ? stream.title
            : (L10nHolder.current?.ytmFallbackTrackTitle ?? 'YouTube Track'),
        artist: stream.artist.isNotEmpty
            ? stream.artist
            : (L10nHolder.current?.browseYouTubeMusic ?? 'YouTube Music'),
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
            content: Text(ctx.l10n.fileIntentLoadTrackFailed(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Assistant / Android voice-search entry point.
  ///
  /// The spoken query is resolved through [AssistantResolver], so "play road
  /// trip", "resume the last album", "shuffle favourites" and an artist-radio
  /// all map to a real play plan instead of the first fuzzy song match. When
  /// nothing resolves, the Search screen opens with the query prefilled so the
  /// user can refine it.
  Future<void> handleVoiceSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final played = await _playAssistantQuery(q);
      if (played) return;
      final navCtx = rootNavigatorKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        navCtx.go('/search?q=${Uri.encodeComponent(q)}');
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to handle voice search: $query',
          error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }

  /// Resolves [rawQuery] into a play plan and starts it. Returns false when the
  /// query resolves to nothing playable (the caller then opens Search).
  Future<bool> _playAssistantQuery(String rawQuery) async {
    final resolver = AssistantResolver(
      searchSongIds: (term) async => _songIdsOf(
        await _repository.watchAllSongs(searchQuery: term, limit: 50).first,
      ),
      playlistSongIds: (name) async {
        final lists = (await _repository.getPlaylists())
            .fold<List<PlaylistsTableData>>((_) => const [], (r) => r);
        final lower = name.trim().toLowerCase();
        if (lower.isEmpty) return const <int>[];
        PlaylistsTableData? match;
        for (final playlist in lists) {
          if (playlist.name.trim().toLowerCase() == lower) {
            match = playlist;
            break;
          }
        }
        if (match == null) {
          for (final playlist in lists) {
            if (playlist.name.toLowerCase().contains(lower)) {
              match = playlist;
              break;
            }
          }
        }
        if (match == null) return const <int>[];
        return _songIdsOf(await _repository.getPlaylistSongs(match.id));
      },
      favoritesSongIds: () async =>
          _songIdsOf(await _repository.getFavorites()),
      lastAlbumSongIds: () async {
        final recent = (await _repository.getRecentlyPlayed(limit: 50))
            .fold<List<SongsTableData>>((_) => const [], (r) => r);
        if (recent.isEmpty) return const <int>[];
        final albumId = recent.first.albumId;
        if (albumId == null) {
          return recent.map((song) => song.id).toList();
        }
        return recent
            .where((song) => song.albumId == albumId)
            .map((song) => song.id)
            .toList();
      },
    );

    final AssistantTextIntent textIntent;
    try {
      textIntent = parseAssistantText(rawQuery);
    } on AssistantQueryError catch (e) {
      ErrorLogger.log('Assistant query rejected: ${e.reason}',
          category: 'FileIntentHandler');
      return false;
    }
    final resolution = await resolver.resolveText(textIntent);
    if (resolution is! AssistantPlayPlan || resolution.songIds.isEmpty) {
      return false;
    }
    final songs = (await _repository.getSongsByIds(resolution.songIds))
        .fold<List<SongsTableData>>((_) => const [], (r) => r);
    if (songs.isEmpty) return false;
    final queue = resolution.shuffle
        ? (List<SongsTableData>.from(songs)..shuffle())
        : songs;
    final index = resolution.startIndex.clamp(0, queue.length - 1);
    await _playerCubit.playSong(
      queue[index],
      queue: queue,
      queueIndex: index,
    );
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      navCtx.push('/now-playing');
    }
    return true;
  }

  List<int> _songIdsOf(Result<List<SongsTableData>> result) => result.fold(
        (_) => const <int>[],
        (songs) => songs.map((song) => song.id).toList(),
      );

  Future<void> handleAudioUri(String uriOrPath) async {
    try {
      // Handle pulsr:// deep links and launcher shortcuts
      final voiceUri = Uri.tryParse(uriOrPath);
      if (voiceUri != null && voiceUri.scheme == 'pulsr') {
        if (voiceUri.host == 'voice-search') {
          await handleVoiceSearch(voiceUri.queryParameters['query'] ?? '');
          return;
        }
        if (voiceUri.host == 'play') {
          await _playerCubit.play();
          final navCtx = rootNavigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            navCtx.push('/now-playing');
          }
          return;
        }
        if (voiceUri.host == 'shuffle') {
          final res = await _repository.watchAllSongs(limit: 200).first;
          final songs = res.fold((_) => <SongsTableData>[], (s) => s);
          if (songs.isNotEmpty) {
            final shuffled = List<SongsTableData>.from(songs)..shuffle();
            await _playerCubit.playSong(shuffled.first, queue: shuffled);
            final navCtx = rootNavigatorKey.currentContext;
            if (navCtx != null && navCtx.mounted) {
              navCtx.push('/now-playing');
            }
          }
          return;
        }
        if (voiceUri.host == 'favorites') {
          final navCtx = rootNavigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            navCtx.go('/favorites');
          }
          return;
        }
        if (voiceUri.host == 'search') {
          final navCtx = rootNavigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            navCtx.go('/search');
          }
          return;
        }
      }

      final videoId = extractYouTubeVideoId(uriOrPath);
      if (videoId != null && AppConfig.ytmEnabled) {
        await _handleYouTubeLink(videoId);
        return;
      }

      final song = await _resolveSongForUri(uriOrPath, showUnsupportedToast: true);
      if (song == null) return;

      await _playerCubit.playSong(song);
      final navCtx = rootNavigatorKey.currentContext;
      if (navCtx != null && navCtx.mounted) {
        navCtx.push('/now-playing');
      }
    } catch (e, st) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.formatNotSupported),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      ErrorLogger.log('Failed to handle external audio URI: $uriOrPath',
          error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }

  Future<SongsTableData?> _resolveSongForUri(
    String uriOrPath, {
    bool showUnsupportedToast = false,
  }) async {
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

    // Determine whether this is a proxy/text payload (only relevant when it
    // isn't a recognized audio file).
    final isTextExt = cleanPath.toLowerCase().endsWith('.txt') ||
        cleanPath.toLowerCase().endsWith('.list') ||
        cleanPath.toLowerCase().endsWith('.conf') ||
        cleanPath.toLowerCase().endsWith('.csv');
    final isContentUri = uriOrPath.startsWith('content://');

    if (!(AudioFormats.isSupportedExtension(cleanPath) ||
        (isContentUri && !isTextExt))) {
      if (showUnsupportedToast) {
        if (isTextExt) {
          try {
            final file = File(cleanPath);
            if (await file.exists() &&
                await file.length() <= _maxProxyTextBytes) {
              final content = await file.readAsString();
              final proxies = ProxyEntry.parseList(content);
              if (proxies.isNotEmpty) {
                final navCtx = rootNavigatorKey.currentContext;
                if (navCtx != null && navCtx.mounted) {
                  navCtx.push('/proxy-settings', extra: content);
                }
                return null;
              }
            }
          } catch (_) {
            // Fall through to unsupported format notice on unreadable files.
          }
        } else {
          final parsedProxies = ProxyEntry.parseList(uriOrPath);
          if (parsedProxies.isNotEmpty) {
            final navCtx = rootNavigatorKey.currentContext;
            if (navCtx != null && navCtx.mounted) {
              navCtx.push('/proxy-settings', extra: uriOrPath);
            }
            return null;
          }
        }

        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.formatNotSupported),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return null;
    }

    final pathMatchRes = await _repository.getSongByPath(cleanPath);
    var match = pathMatchRes.fold((l) => null, (r) => r);

    if (match == null && uriOrPath != cleanPath) {
      final uriMatchRes = await _repository.getSongByUri(uriOrPath);
      match = uriMatchRes.fold((l) => null, (r) => r);
    }

    if (match != null) return match;

    final isContentScheme = uriOrPath.startsWith('content://');
    String title = L10nHolder.current?.fileIntentAudioFile ?? 'Audio File';
    int? fileSize;

    if (isContentScheme) {
      final parsedUri = Uri.tryParse(uriOrPath);
      final segment = parsedUri?.pathSegments.isNotEmpty == true
          ? parsedUri!.pathSegments.last
          : null;
      if (segment != null && segment.isNotEmpty) {
        final decoded = Uri.decodeComponent(segment);
        title = p.withoutExtension(decoded);
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

    return SongsTableData(
      id: _getNextTempId(),
      title: title.isNotEmpty
          ? title
          : (L10nHolder.current?.fileIntentExternalAudio ?? 'External Audio'),
      artist: L10nHolder.current?.fileIntentExternalAudio ?? 'External Audio',
      album: L10nHolder.current?.fileIntentFilesAlbum ?? 'Files',
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
  }
}
