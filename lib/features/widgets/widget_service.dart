import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/artwork_cache_manager.dart';
import '../../core/utils/error_logger.dart';
import '../../core/widgets/cached_artwork.dart';
import '../../data/db/app_database.dart';

@lazySingleton
class WidgetService {
  static const String androidWidgetName = 'NowPlayingWidget';
  static const String qualifiedAndroidName = 'com.pulsr.music.NowPlayingWidget';
  static const String iOSWidgetName = 'PulsrWidget';
  static const String appGroupId = 'group.com.pulsr.music';

  static const int _maxCacheSize = 50;
  static const int _maxPendingArtworkQueue = 3;
  static const Duration _networkTimeout = Duration(seconds: 8);
  static const String _contentVersionKey = 'widget_content_version';

  static const Set<String> _knownWidgetActions = {
    'play_pause',
    'prev',
    'next',
    'favorite',
    'shuffle',
    'repeat',
    'queue',
    'open',
    'main',
  };

  bool _appGroupConfigured = false;
  bool _androidInitialized = false;
  bool _versionInitialized = false;
  static bool _hasPrunedArtworkThisSession = false;

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // L-09: LinkedHashMap with manual access-order refresh on hit, so eviction
  // (`keys.first`) drops the least-recently-used entry.
  final LinkedHashMap<int, String> _artworkCache = LinkedHashMap();
  final LinkedHashMap<int, Uint8List> _roundedArtworkCache = LinkedHashMap();

  int? _lastSavedArtworkSongId;

  /// Cached progress snapshot to suppress redundant 1Hz IPC updates when
  /// playback is paused or position has not meaningfully advanced.
  bool? _lastProgressIsPlaying;
  int? _lastProgressPositionMs;
  int? _lastProgressDurationMs;

  /// Monotonic counter bumped whenever non-progress content changes (track,
  /// favourite/shuffle/repeat state, queue preview, artwork). Persisted as
  /// `contentVersion` in SharedPreferences and HomeWidget so it survives app restarts.
  int _contentVersion = 0;

  /// Whether an artwork resolve is currently in-flight (to avoid stacking).
  bool _artworkResolveInFlight = false;
  int _artworkGeneration = 0;
  final Queue<SongsTableData> _pendingArtworkQueue = Queue<SongsTableData>();

  Future<void> _ensureAppGroup() async {
    if (Platform.isIOS) {
      if (_appGroupConfigured) return;
      try {
        await HomeWidget.setAppGroupId(appGroupId);
        // Only mark configured once the call actually succeeded so a transient
        // failure is retried on the next update.
        _appGroupConfigured = true;
      } catch (e) {
        ErrorLogger.log(
          'Failed to set iOS app group ID',
          error: e,
          category: 'WidgetService',
        );
      }
    } else if (Platform.isAndroid) {
      if (_androidInitialized) return;
      _androidInitialized = true;
    }
  }

  Future<void> _ensureContentVersionLoaded() async {
    if (_versionInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _contentVersion = prefs.getInt(_contentVersionKey) ?? 0;
      _versionInitialized = true;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to load widget content version',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
      _versionInitialized = true;
    }
  }

  Future<void> _bumpContentVersion() async {
    await _ensureContentVersionLoaded();
    _contentVersion += 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_contentVersionKey, _contentVersion);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist widget content version to prefs',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
    }
    try {
      await HomeWidget.saveWidgetData<int>('contentVersion', _contentVersion);
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to persist widget content version to HomeWidget',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
    }
  }

  Future<void> _triggerWidgetReload() {
    return HomeWidget.updateWidget(
      name: androidWidgetName,
      androidName: androidWidgetName,
      qualifiedAndroidName: qualifiedAndroidName,
      iOSName: iOSWidgetName,
    );
  }

  static int _computePermille(int positionMs, int durationMs) {
    if (durationMs <= 0 || positionMs <= 0) return 0;
    return ((positionMs * 1000) ~/ durationMs).clamp(0, 1000);
  }

  static String _formatTimestamp(Duration d) {
    if (d <= Duration.zero) return '0:00';
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      final paddedMin = minutes.toString().padLeft(2, '0');
      return '$hours:$paddedMin:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _touchArtworkPathLru(int songId, String path) {
    _artworkCache.remove(songId);
    _artworkCache[songId] = path;
  }

  void _touchArtworkBytesLru(int songId, Uint8List bytes) {
    _roundedArtworkCache.remove(songId);
    _roundedArtworkCache[songId] = bytes;
  }

  Future<void> _evictOverflowCachesIfNeeded() async {
    while (_artworkCache.length > _maxCacheSize) {
      final oldestKey = _artworkCache.keys.first;
      final evictedPath = _artworkCache.remove(oldestKey);
      if (evictedPath != null) {
        unawaited(_deleteFileSilently(File(evictedPath)));
      }
    }
    while (_roundedArtworkCache.length > _maxCacheSize) {
      final oldestKey = _roundedArtworkCache.keys.first;
      _roundedArtworkCache.remove(oldestKey);
    }
  }

  Future<void> _deleteFileSilently(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _drainPendingArtwork() {
    if (_artworkResolveInFlight) return;
    if (_pendingArtworkQueue.isEmpty) return;
    final next = _pendingArtworkQueue.removeFirst();
    if (next.id == _lastSavedArtworkSongId &&
        _artworkCache.containsKey(next.id)) {
      _drainPendingArtwork();
      return;
    }
    _artworkResolveInFlight = true;
    final generation = _artworkGeneration;
    unawaited(_resolveArtworkAsync(next, generation).whenComplete(() {
      _artworkResolveInFlight = false;
      _drainPendingArtwork();
    }));
  }

  /// Fires-and-forgets artwork resolution so the widget text updates
  /// immediately while the (potentially slow) artwork arrives async.
  Future<void> updateNowPlaying({
    required SongsTableData? song,
    required bool isPlaying,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool isFavorite = false,
    bool isShuffle = false,
    String repeatMode = 'off',
    List<String>? nextQueueTitles,
    String? queueCover,
  }) async {
    try {
      await _ensureAppGroup();
      final hasSong = song != null;

      final posMs = hasSong ? position.inMilliseconds : 0;
      final durMs = hasSong ? duration.inMilliseconds : 0;
      final permille = _computePermille(posMs, durMs);

      _lastProgressIsPlaying = isPlaying;
      _lastProgressPositionMs = posMs;
      _lastProgressDurationMs = durMs;

      final resolvedTitle =
          hasSong && song.title.trim().isNotEmpty ? song.title : 'Pulsr Music';
      final resolvedArtist = hasSong && song.artist.trim().isNotEmpty
          ? song.artist
          : 'Nothing playing';
      final resolvedAlbum = hasSong &&
              song.album.trim().isNotEmpty &&
              song.album != 'Unknown Album'
          ? song.album
          : '';

      final saves = <Future<bool?>>[
        HomeWidget.saveWidgetData<String>('title', resolvedTitle),
        HomeWidget.saveWidgetData<String>('artist', resolvedArtist),
        HomeWidget.saveWidgetData<String>('album', resolvedAlbum),
        HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying),
        HomeWidget.saveWidgetData<bool>('isFavorite', isFavorite),
        HomeWidget.saveWidgetData<bool>('isShuffle', isShuffle),
        HomeWidget.saveWidgetData<String>('repeatMode', repeatMode),
        HomeWidget.saveWidgetData<int>('positionMs', posMs),
        HomeWidget.saveWidgetData<int>('durationMs', durMs),
        HomeWidget.saveWidgetData<int>('progressPermille', permille),
        HomeWidget.saveWidgetData<String>(
          'formattedPosition',
          _formatTimestamp(hasSong ? position : Duration.zero),
        ),
        HomeWidget.saveWidgetData<String>(
          'formattedDuration',
          _formatTimestamp(hasSong ? duration : Duration.zero),
        ),
      ];

      if (hasSong) {
        for (int i = 0; i < 3; i++) {
          final nextTitle =
              (nextQueueTitles != null && i < nextQueueTitles.length)
                  ? nextQueueTitles[i]
                  : '';
          saves
              .add(HomeWidget.saveWidgetData<String>('nextTrack$i', nextTitle));
        }
        final upNext = (nextQueueTitles != null && nextQueueTitles.isNotEmpty)
            ? nextQueueTitles.first
            : '';
        saves.add(HomeWidget.saveWidgetData<String>('upNext', upNext));
        saves.add(
          HomeWidget.saveWidgetData<String>('queueCover', queueCover ?? ''),
        );

        await Future.wait(saves);

        // Check if artwork is already cached and valid on disk without blocking the UI thread.
        final cachedArt = _artworkCache[song.id];
        final isCachedValid =
            cachedArt != null && await File(cachedArt).exists();
        if (isCachedValid) {
          _touchArtworkPathLru(song.id, cachedArt);
          _lastSavedArtworkSongId = song.id;
          await HomeWidget.saveWidgetData<String>('artwork', cachedArt);
          await HomeWidget.saveWidgetData<bool>('artworkFailed', false);
        } else {
          if (cachedArt != null) {
            _artworkCache.remove(song.id);
            _roundedArtworkCache.remove(song.id);
          }
          _pendingArtworkQueue.removeWhere((s) => s.id == song.id);
          // C-04: Cap queue at 3 entries, drop oldest on rapid track changes
          while (_pendingArtworkQueue.length >= _maxPendingArtworkQueue) {
            _pendingArtworkQueue.removeFirst();
          }
          _pendingArtworkQueue.add(song);
          _drainPendingArtwork();
        }
      } else {
        for (int i = 0; i < 3; i++) {
          saves.add(HomeWidget.saveWidgetData<String>('nextTrack$i', ''));
        }
        saves.addAll([
          HomeWidget.saveWidgetData<String>('upNext', ''),
          HomeWidget.saveWidgetData<String>('queueCover', ''),
          HomeWidget.saveWidgetData<String>('artwork', ''),
          HomeWidget.saveWidgetData<bool>('artworkFailed', false),
        ]);
        await Future.wait(saves);

        _artworkGeneration++;
        _pendingArtworkQueue.clear();
        _lastSavedArtworkSongId = null;
      }

      await _bumpContentVersion();
      await _triggerWidgetReload();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to update home screen widget state',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
    }
  }

  /// Non-blocking artwork resolve: fires in background, updates widget
  /// once complete.
  Future<void> _resolveArtworkAsync(SongsTableData song, int generation) async {
    try {
      final artPath = await _resolveArtworkPath(song).timeout(
        _networkTimeout,
        onTimeout: () {
          ErrorLogger.log(
            'Widget artwork resolve timed out after 8s',
            category: 'WidgetService',
          );
          return null;
        },
      );
      if (generation != _artworkGeneration) return;

      // Generation check: skip updating UI if newer songs are queued.
      if (_pendingArtworkQueue.isNotEmpty &&
          _pendingArtworkQueue.any((s) => s.id != song.id)) {
        return;
      }

      _lastSavedArtworkSongId = song.id;
      final hasArt = artPath != null && artPath.isNotEmpty;
      await Future.wait([
        HomeWidget.saveWidgetData<String>('artwork', hasArt ? artPath : ''),
        HomeWidget.saveWidgetData<bool>('artworkFailed', !hasArt),
      ]);
      await _bumpContentVersion();
      await _triggerWidgetReload();
    } catch (e, st) {
      ErrorLogger.log(
        'Widget artwork async resolve failed',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
      // FIX-G03 / I12: Reset artwork and flag error on error
      try {
        await Future.wait([
          HomeWidget.saveWidgetData<String>('artwork', ''),
          HomeWidget.saveWidgetData<bool>('artworkFailed', true),
        ]);
        await _bumpContentVersion();
        await _triggerWidgetReload();
      } catch (e, st) {
        ErrorLogger.log(
          'Reset artwork on error failed',
          error: e,
          stackTrace: st,
          category: 'WidgetService',
        );
      }
    }
  }

  /// Lightweight progress-only update (throttled): updates position, duration & play state
  /// without re-resolving artwork or touching bitmap cache.
  Future<void> updateProgress({
    required bool isPlaying,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    final posMs = position.inMilliseconds;
    final durMs = duration.inMilliseconds;

    // Suppress redundant platform channel traffic if play state & duration are
    // identical and position has moved by less than 500ms.
    if (_lastProgressIsPlaying == isPlaying &&
        _lastProgressDurationMs == durMs &&
        _lastProgressPositionMs != null &&
        (posMs - _lastProgressPositionMs!).abs() < 500) {
      return;
    }

    _lastProgressIsPlaying = isPlaying;
    _lastProgressPositionMs = posMs;
    _lastProgressDurationMs = durMs;

    try {
      await _ensureAppGroup();
      final permille = _computePermille(posMs, durMs);

      await Future.wait([
        HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying),
        HomeWidget.saveWidgetData<int>('positionMs', posMs),
        HomeWidget.saveWidgetData<int>('durationMs', durMs),
        HomeWidget.saveWidgetData<int>('progressPermille', permille),
        HomeWidget.saveWidgetData<String>(
          'formattedPosition',
          _formatTimestamp(position),
        ),
        HomeWidget.saveWidgetData<String>(
          'formattedDuration',
          _formatTimestamp(duration),
        ),
      ]);

      await _triggerWidgetReload();
    } catch (e, st) {
      ErrorLogger.log(
        'updateProgress failed',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
    }
  }

  /// Exports an artwork image for the widget, cached per song.
  Future<String?> _resolveArtworkPath(SongsTableData song) async {
    final songId = song.id;
    final cachedPath = _artworkCache[songId];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (await f.exists() && await f.length() > 0) {
        // L-09 / M-03: refresh LRU position on hit and update mtime to align with disk pruner
        _touchArtworkPathLru(songId, cachedPath);
        try {
          await f.setLastModified(DateTime.now());
        } catch (_) {}
        return cachedPath;
      }
      _artworkCache.remove(songId);
      _roundedArtworkCache.remove(songId);
    }

    try {
      final baseDir = await getTemporaryDirectory();
      final artDir = Directory('${baseDir.path}/pulsr_widget_art');
      if (!await artDir.exists()) {
        await artDir.create(recursive: true);
      }
      final cleanId = songId < 0 ? 'neg_${songId.abs()}' : '$songId';
      final cachedFile = File('${artDir.path}/pulsr_widget_art_$cleanId.png');
      if (await cachedFile.exists() && await cachedFile.length() > 0) {
        _touchArtworkPathLru(songId, cachedFile.path);
        return cachedFile.path;
      }

      Uint8List? rawBytes = _roundedArtworkCache[songId];
      if (rawBytes != null) {
        // L-09: refresh LRU position on hit.
        _touchArtworkBytesLru(songId, rawBytes);
      } else {
        rawBytes = await _fetchArtworkBytes(song);
        if (rawBytes == null || rawBytes.isEmpty) return null;
        _touchArtworkBytesLru(songId, rawBytes);
      }

      // Atomic write via staging file so native widget host never reads a partial file.
      final tempFile =
          File('${artDir.path}/pulsr_widget_art_${cleanId}_tmp.png');
      await tempFile.writeAsBytes(rawBytes, flush: true);
      await tempFile.rename(cachedFile.path);

      _touchArtworkPathLru(songId, cachedFile.path);
      await _evictOverflowCachesIfNeeded();

      // Opportunistically prune old widget temp files at most once per session (L-6)
      if (!_hasPrunedArtworkThisSession) {
        _hasPrunedArtworkThisSession = true;
        unawaited(_pruneOldWidgetArtwork(baseDir));
      }
      return cachedFile.path;
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to resolve artwork path for widget',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
      return null;
    }
  }

  /// Resolves raw artwork bytes across memory cache, disk cache, remote HTTPS,
  /// local file URI, and MediaStore fallbacks.
  Future<Uint8List?> _fetchArtworkBytes(SongsTableData song) async {
    final songId = song.id;
    final remoteUrl = song.remoteArtworkUrl ??
        (song.artworkUri?.startsWith('http') == true ? song.artworkUri : null);

    // 1. Fast path: Check in-memory ArtworkLruCache
    Uint8List? rawBytes;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      rawBytes = ArtworkLruCache().get('${remoteUrl}_hq') ??
          ArtworkLruCache().get(remoteUrl);
    } else {
      rawBytes = ArtworkLruCache().get('AUDIO_${songId}_hq') ??
          ArtworkLruCache().get('AUDIO_$songId');
    }
    if (rawBytes != null && rawBytes.isNotEmpty) return rawBytes;

    // 2. Check persistent ArtworkCacheManager disk cache & remote HTTPS fallback
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final targetUrl = CachedArtwork.upgradeToHighResArtwork(remoteUrl);
      rawBytes = await ArtworkCacheManager().get(targetUrl) ??
          await ArtworkCacheManager().get(remoteUrl);

      if (rawBytes == null || rawBytes.isEmpty) {
        HttpClient? client;
        try {
          final uri = Uri.tryParse(targetUrl) ?? Uri.tryParse(remoteUrl);
          if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
            client = HttpClient()
              ..connectionTimeout = _networkTimeout
              ..idleTimeout = const Duration(seconds: 5);
            final req = await client.getUrl(uri).timeout(_networkTimeout);
            final res = await req.close().timeout(_networkTimeout);
            if (res.statusCode == 200) {
              final fetched = await consolidateHttpClientResponseBytes(res)
                  .timeout(_networkTimeout);
              if (fetched.isNotEmpty) {
                rawBytes = fetched;
                unawaited(ArtworkCacheManager().put(targetUrl, fetched));
              }
            }
          }
        } catch (e, st) {
          ErrorLogger.log(
            '_resolveArtworkPath HTTP fetch failed',
            error: e,
            stackTrace: st,
            category: 'WidgetService',
          );
        } finally {
          try {
            client?.close(force: true);
          } catch (e, st) {
            ErrorLogger.log(
              'Failed to close widget HTTP client',
              error: e,
              stackTrace: st,
              category: 'WidgetService',
            );
          }
        }
      }
    }
    if (rawBytes != null && rawBytes.isNotEmpty) return rawBytes;

    // 3. Check local file URI (e.g. file:///...)
    if (song.artworkUri != null && song.artworkUri!.isNotEmpty) {
      final parsed = Uri.tryParse(song.artworkUri!);
      if (parsed != null && parsed.scheme == 'file') {
        final f = File(parsed.toFilePath());
        if (await f.exists() && await f.length() > 0) {
          rawBytes = await f.readAsBytes();
        }
      }
    }
    if (rawBytes != null && rawBytes.isNotEmpty) return rawBytes;

    // 4. Fallback to OnAudioQuery for local MediaStore tracks (Audio ID, then Album ID)
    if (songId > 0) {
      rawBytes = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 256,
        quality: 90,
      );

      if ((rawBytes == null || rawBytes.isEmpty) && song.albumId != null) {
        rawBytes = await _audioQuery.queryArtwork(
          song.albumId!,
          ArtworkType.ALBUM,
          format: ArtworkFormat.JPEG,
          size: 256,
          quality: 90,
        );
      }
    }

    return (rawBytes != null && rawBytes.isNotEmpty) ? rawBytes : null;
  }

  StreamSubscription<Uri?> listenToWidgetClicks(
    void Function(Uri? uri) onUriReceived,
  ) {
    return HomeWidget.widgetClicked.listen((uri) {
      if (uri == null) return;
      if (uri.scheme.toLowerCase() != 'pulsrwidget') return;
      final action =
          uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
      if (!_knownWidgetActions.contains(action)) return;
      onUriReceived(uri);
    });
  }

  @visibleForTesting
  Future<void> pruneOldWidgetArtwork(Directory dir) =>
      _pruneOldWidgetArtwork(dir);

  Future<void> _pruneOldWidgetArtwork(Directory dir) async {
    try {
      // Use dedicated subdirectory if present, otherwise scan the provided directory (e.g. in tests)
      final subDir = Directory('${dir.path}/pulsr_widget_art');
      final scanDir = await subDir.exists() ? subDir : dir;

      final files = <File>[];
      await for (final entity in scanDir.list(followLinks: false)) {
        if (entity is File && entity.path.contains('pulsr_widget_art_')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return;

      final now = DateTime.now();
      final stats = <({File file, DateTime? modified})>[];
      const batchSize = 20; // limit concurrency
      for (var i = 0; i < files.length; i += batchSize) {
        final end =
            (i + batchSize < files.length) ? i + batchSize : files.length;
        final batchStats = await Future.wait(
          files.sublist(i, end).map((f) async {
            try {
              final stat = await f.stat();
              return (file: f, modified: stat.modified);
            } catch (e, st) {
              ErrorLogger.log(
                'Failed to stat widget artwork file',
                error: e,
                stackTrace: st,
                category: 'WidgetService',
              );
              return (file: f, modified: null);
            }
          }),
        );
        stats.addAll(batchStats);
      }

      final stale = <File>[];
      final survivors = <({File file, DateTime modified})>[];
      for (final s in stats) {
        final modified = s.modified;
        if (modified == null || now.difference(modified).inDays > 7) {
          stale.add(s.file);
        } else {
          survivors.add((file: s.file, modified: modified));
        }
      }

      // Enforce the total-count limit oldest-first.
      if (survivors.length > _maxCacheSize) {
        survivors.sort((a, b) => a.modified.compareTo(b.modified));
        stale.addAll(
          survivors.take(survivors.length - _maxCacheSize).map((s) => s.file),
        );
      }

      for (var i = 0; i < stale.length; i += batchSize) {
        final end =
            (i + batchSize < stale.length) ? i + batchSize : stale.length;
        await Future.wait(
          stale.sublist(i, end).map((f) async {
            try {
              await f.delete();
            } catch (e, st) {
              ErrorLogger.log(
                '_pruneOldWidgetArtwork failed',
                error: e,
                stackTrace: st,
                category: 'WidgetService',
              );
            }
          }),
        );
      }
    } catch (e, st) {
      ErrorLogger.log(
        '_pruneOldWidgetArtwork failed',
        error: e,
        stackTrace: st,
        category: 'WidgetService',
      );
    }
  }
}
