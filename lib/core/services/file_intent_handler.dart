import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../../core/utils/l10n_extensions.dart';
import '../../core/utils/l10n_holder.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../constants/audio_formats.dart';
import '../constants/prefs_keys.dart';
import '../di/injection.dart';
import '../errors/failures.dart';
import '../router/app_router.dart';
import '../utils/error_logger.dart';
import '../../data/audio/sacd/sacd_iso_library.dart';
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

  /// Upper bound for one voice-search resolution round trip.
  ///
  /// The assistant resolver runs through the platform method channel; without
  /// this bound a repository stream that never emits (or a wedged channel)
  /// kept the caller — and Android's voice interaction — waiting forever.
  static const Duration voiceSearchTimeout = Duration(seconds: 5);

  static const MethodChannel _channel = MethodChannel(PulsrChannels.fileOpener);
  static int _tempIdCounter = 0;
  static int _getNextTempId() {
    final rand = math.Random().nextInt(1 << 16);
    return (DateTime.now().millisecondsSinceEpoch * -1) -
        (++_tempIdCounter * 65536) -
        rand;
  }

  /// Test seam: replaces the SACD open path without touching path_provider.
  static SacdIsoLibrary? sacdIsoLibraryOverride;

  final IMusicRepository _repository;
  final PlayerCubit _playerCubit;

  FileIntentHandler(this._repository, this._playerCubit) {
    _initChannel();
    // Startup janitor for extracted DSF tracks: enforces the cache age/budget
    // and never throws. This handler is constructed during app warm-up, so it
    // is the earliest in-scope hook (main.dart is out of this change's scope).
    unawaited(_sacdLibrary.warmUp());
  }

  SacdIsoLibrary get _sacdLibrary =>
      sacdIsoLibraryOverride ?? SacdIsoLibrary.shared;

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
            if (getIt.isRegistered<MediaScannerService>()) {
              final scanner = getIt<MediaScannerService>();
              await scanner.scanDeviceLibrary(incremental: true);
            }
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
      final list =
          await _channel.invokeListMethod<String>('getInitialAudioUris');
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
      try {
        songs.addAll(await _songsForUri(raw));
      } catch (e, st) {
        ErrorLogger.log('Could not queue an external audio URI: $raw',
            error: e, stackTrace: st, category: 'FileIntentHandler');
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
    if (!AppConfig.ytmEnabled || !AppConfig.isCloudSyncAllowed) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(PrefsKeys.offlineOnlyMode) == true) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(context.l10n.homeOfflineNotice),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } catch (_) {
      // Fail closed if offline preference cannot be verified on external links.
      return;
    }
    if (!getIt.isRegistered<YtmService>()) return;

    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
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
      _openSearchFor(q);
    } on TimeoutException catch (e, st) {
      // A wedged resolver/repository must release the platform channel; the
      // Search screen (prefilled) is the honest fallback.
      ErrorLogger.log(
          'Voice search timed out after '
          '${voiceSearchTimeout.inSeconds}s: $q',
          error: e,
          stackTrace: st,
          category: 'FileIntentHandler');
      _openSearchFor(q);
    } catch (e, st) {
      ErrorLogger.log('Failed to handle voice search: $query',
          error: e, stackTrace: st, category: 'FileIntentHandler');
    }
  }

  void _openSearchFor(String query) {
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      navCtx.go('/search?q=${Uri.encodeComponent(query)}');
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
        if (albumId != null) {
          final albumSongs = (await _repository.getAlbumSongs(albumId))
              .fold<List<SongsTableData>>((_) => const [], (r) => r);
          if (albumSongs.isNotEmpty) {
            return albumSongs.map((song) => song.id).toList();
          }
        }
        return recent.map((song) => song.id).toList();
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
    final resolution =
        await resolver.resolveText(textIntent).timeout(voiceSearchTimeout);
    if (resolution is! AssistantPlayPlan || resolution.songIds.isEmpty) {
      return false;
    }
    final rawSongs = (await _repository
            .getSongsByIds(resolution.songIds)
            .timeout(voiceSearchTimeout))
        .fold<List<SongsTableData>>((_) => const [], (r) => r);
    if (rawSongs.isEmpty) return false;
    final songMap = {for (final s in rawSongs) s.id: s};
    final orderedSongs = <SongsTableData>[];
    for (final id in resolution.songIds) {
      final s = songMap[id];
      if (s != null) {
        orderedSongs.add(s);
      }
    }
    if (orderedSongs.isEmpty) return false;
    final queue = resolution.shuffle
        ? (List<SongsTableData>.from(orderedSongs)..shuffle())
        : orderedSongs;
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
      if (videoId != null) {
        if (AppConfig.ytmEnabled && AppConfig.isCloudSyncAllowed) {
          await _handleYouTubeLink(videoId);
        }
        return;
      }

      final songs = await _songsForUri(uriOrPath, showUnsupportedToast: true);
      if (songs.isEmpty) return;
      if (songs.length == 1) {
        await _playerCubit.playSong(songs.first);
      } else {
        // A SACD image expands into one stereo song per TOC track; start the
        // first and keep the rest queued.
        await _playerCubit.playSong(songs.first, queue: songs, queueIndex: 0);
      }
      _pushNowPlaying();
    } catch (e, st) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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

  void _pushNowPlaying() {
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      navCtx.push('/now-playing');
    }
  }

  /// Resolves one external URI/path into the songs it contributes to playback.
  ///
  /// Ordinary audio files contribute at most one synthetic song (or a library
  /// match); a SACD `.iso` contributes every stereo track it expands.
  Future<List<SongsTableData>> _songsForUri(
    String uriOrPath, {
    bool showUnsupportedToast = false,
  }) async {
    final cleanPath = _decodeLocalPath(uriOrPath);
    if (AudioFormats.kindFor(cleanPath) == AudioFormatKind.sacdContainer) {
      final sacdSongs = await _sacdSongsForIso(cleanPath);
      if (sacdSongs != null) return sacdSongs;
      // Not a SACD image: fall through so the unsupported-format handling runs
      // (an ordinary data ISO is still rejected, as before).
    }
    final song = await _resolveSongForUri(
      uriOrPath,
      showUnsupportedToast: showUnsupportedToast,
    );
    return song == null ? const <SongsTableData>[] : <SongsTableData>[song];
  }

  /// Probes, indexes and expands [path] into playable DSF-backed songs.
  ///
  /// Returns null when [path] is not a SACD image (the caller falls back to the
  /// existing unsupported-format path). Extraction failures are reported once
  /// and yield an empty list: a broken image must never crash the intent.
  Future<List<SongsTableData>?> _sacdSongsForIso(String path) async {
    final library = _sacdLibrary;
    if (!await library.isSacdImage(path)) return null;
    try {
      final opened = await library.openStereo(File(path));
      if (opened.isEmpty) return const <SongsTableData>[];
      final baseName = p.basenameWithoutExtension(path);
      final artist =
          L10nHolder.current?.fileIntentExternalAudio ?? 'External Audio';
      final album = L10nHolder.current?.fileIntentFilesAlbum ?? 'Files';
      final songs = <SongsTableData>[];
      for (final entry in opened) {
        int? fileSize;
        try {
          fileSize = await entry.file.length();
        } catch (e, st) {
          ErrorLogger.log(
            'Could not read the size of an extracted SACD track',
            error: e,
            stackTrace: st,
            category: 'FileIntentHandler',
          );
        }
        songs.add(
          SongsTableData(
            id: _getNextTempId(),
            title: '$baseName - Track ${entry.track.index}',
            artist: artist,
            album: album,
            durationMs: (entry.track.durationSeconds * 1000).round(),
            path: entry.file.path,
            uri: entry.file.path,
            source: SongSource.local,
            fileSize: fileSize,
            isFavorite: false,
            isMissing: false,
            isDownloaded: false,
            playCount: 0,
            lastPositionMs: 0,
          ),
        );
      }
      return songs;
    } catch (e, st) {
      ErrorLogger.log('Could not expand SACD image: $path',
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
      return const <SongsTableData>[];
    }
  }

  /// Decodes and normalises an incoming path/URI for local file access.
  static String _decodeLocalPath(String uriOrPath) {
    if (uriOrPath.startsWith('file://')) {
      try {
        final parsed = Uri.parse(uriOrPath);
        if (parsed.scheme == 'file' && parsed.path.isNotEmpty) {
          // Decode percent-escapes AFTER URI parsing so `%23` (#) and `%3F` (?)
          // in filenames are not truncated as fragment/query delimiters.
          return Uri.decodeComponent(parsed.path);
        }
      } catch (_) {
        // Fall through to literal fallback below.
      }
      final stripped = uriOrPath.replaceFirst('file://', '');
      try {
        return Uri.decodeFull(stripped);
      } catch (_) {
        return stripped;
      }
    }
    try {
      return Uri.decodeFull(uriOrPath);
    } catch (_) {
      return uriOrPath;
    }
  }

  Future<SongsTableData?> _resolveSongForUri(
    String uriOrPath, {
    bool showUnsupportedToast = false,
  }) async {
    final cleanPath = _decodeLocalPath(uriOrPath);

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
                if (!AppConfig.isPure) {
                  final navCtx = rootNavigatorKey.currentContext;
                  if (navCtx != null && navCtx.mounted) {
                    navCtx.push('/proxy-settings', extra: content);
                  }
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
            if (!AppConfig.isPure) {
              final navCtx = rootNavigatorKey.currentContext;
              if (navCtx != null && navCtx.mounted) {
                navCtx.push('/proxy-settings', extra: uriOrPath);
              }
            }
            return null;
          }
        }

        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      } catch (e, st) {
        ErrorLogger.log(
          'Could not read the size of an external audio file',
          error: e,
          stackTrace: st,
          category: 'FileIntentHandler',
        );
      }
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

  @disposeMethod
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
