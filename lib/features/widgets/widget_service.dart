import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

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

  bool _appGroupConfigured = false;
  Future<void> _ensureAppGroup() async {
    if (_appGroupConfigured) return;
    if (Platform.isIOS) {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (e) {
        ErrorLogger.log('Failed to set iOS app group ID',
            error: e, category: 'WidgetService');
      }
    }
    _appGroupConfigured = true;
  }

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Map<int, String> _artworkCache = {};
  final Map<int, Uint8List> _roundedArtworkCache = {};
  static const int _maxCacheSize = 50;

  int? _lastSavedArtworkSongId;

  /// Monotonic counter bumped whenever non-progress content changes (track,
  /// favourite/shuffle/repeat state, queue preview, artwork). Persisted as
  /// `contentVersion` and compared by the Kotlin provider against the value it
  /// last rendered in full, so the ~1/s progress tick can be recognised as such
  /// without an Intent extra that home_widget cannot carry (C-4).
  int _contentVersion = 0;

  Future<void> _bumpContentVersion() async {
    _contentVersion += 1;
    try {
      await HomeWidget.saveWidgetData<int>('contentVersion', _contentVersion);
    } catch (_) {}
  }

  /// Whether an artwork resolve is currently in-flight (to avoid stacking).
  bool _artworkResolveInFlight = false;
  SongsTableData? _pendingArtworkSong;

  void _drainPendingArtwork() {
    if (_artworkResolveInFlight) return;
    final next = _pendingArtworkSong;
    if (next == null) return;
    if (next.id == _lastSavedArtworkSongId && _artworkCache.containsKey(next.id)) {
      _pendingArtworkSong = null;
      return;
    }
    _pendingArtworkSong = null;
    _artworkResolveInFlight = true;
    unawaited(_resolveArtworkAsync(next).whenComplete(() {
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
  }) async {
    try {
      await _ensureAppGroup();
      final hasSong = song != null;

      await HomeWidget.saveWidgetData<String>(
        'title',
        hasSong && song.title.trim().isNotEmpty ? song.title : 'Pulsr Music',
      );
      await HomeWidget.saveWidgetData<String>(
        'artist',
        hasSong && song.artist.trim().isNotEmpty
            ? song.artist
            : 'Nothing playing',
      );
      await HomeWidget.saveWidgetData<String>(
        'album',
        hasSong && song.album.trim().isNotEmpty && song.album != 'Unknown Album'
            ? song.album
            : '',
      );
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);
      await HomeWidget.saveWidgetData<bool>('isFavorite', isFavorite);
      await HomeWidget.saveWidgetData<bool>('isShuffle', isShuffle);
      await HomeWidget.saveWidgetData<String>('repeatMode', repeatMode);
      if (hasSong) {
        await HomeWidget.saveWidgetData<int>(
            'positionMs', position.inMilliseconds);
        await HomeWidget.saveWidgetData<int>(
            'durationMs', duration.inMilliseconds);
        for (int i = 0; i < 3; i++) {
          final title = (nextQueueTitles != null && i < nextQueueTitles.length)
              ? nextQueueTitles[i]
              : '';
          await HomeWidget.saveWidgetData<String>('nextTrack$i', title);
        }

        // If artwork is already cached for this song, set it immediately
        final cachedArt = _artworkCache[song.id];
        if (cachedArt != null && File(cachedArt).existsSync()) {
          _lastSavedArtworkSongId = song.id;
          await HomeWidget.saveWidgetData<String>('artwork', cachedArt);
        } else if (_lastSavedArtworkSongId != song.id) {
          _pendingArtworkSong = song;
          _drainPendingArtwork();
        }
      } else {
        await HomeWidget.saveWidgetData<int>('positionMs', 0);
        await HomeWidget.saveWidgetData<int>('durationMs', 0);
        for (int i = 0; i < 3; i++) {
          await HomeWidget.saveWidgetData<String>('nextTrack$i', '');
        }
        await HomeWidget.saveWidgetData<String>('artwork', '');
        _pendingArtworkSong = null;
        _lastSavedArtworkSongId = null;
      }

      await _bumpContentVersion();
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
        iOSName: iOSWidgetName,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to update home screen widget state',
          error: e, stackTrace: st, category: 'WidgetService');
    }
  }

  /// Non-blocking artwork resolve: fires in background, updates widget
  /// once complete.
  Future<void> _resolveArtworkAsync(SongsTableData song) async {
    try {
      final artPath = await _resolveArtworkPath(song).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          ErrorLogger.log('Widget artwork resolve timed out after 8s',
              category: 'WidgetService');
          return null;
        },
      );
      if (artPath != null && artPath.isNotEmpty) {
        // Generation check: skip if another song took over while resolving.
        if (_pendingArtworkSong != null && _pendingArtworkSong!.id != song.id) {
          return;
        }
        _lastSavedArtworkSongId = song.id;
        await HomeWidget.saveWidgetData<String>('artwork', artPath);
        await _bumpContentVersion();
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          qualifiedAndroidName: qualifiedAndroidName,
          iOSName: iOSWidgetName,
        );
      } else {
        // FIX-G03: Push empty string on resolution failure so widget doesn't stay stuck on stale artwork
        if (_pendingArtworkSong != null && _pendingArtworkSong!.id != song.id) {
          return;
        }
        _lastSavedArtworkSongId = song.id;
        await HomeWidget.saveWidgetData<String>('artwork', '');
        await _bumpContentVersion();
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          qualifiedAndroidName: qualifiedAndroidName,
          iOSName: iOSWidgetName,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Widget artwork async resolve failed',
          error: e, stackTrace: st, category: 'WidgetService');
      // FIX-G03: Reset artwork on error
      try {
        await HomeWidget.saveWidgetData<String>('artwork', '');
        await _bumpContentVersion();
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          qualifiedAndroidName: qualifiedAndroidName,
          iOSName: iOSWidgetName,
        );
      } catch (e, st) {
        ErrorLogger.log('Reset artwork on error failed',
            error: e, stackTrace: st, category: 'WidgetService');
      }
    }
  }

  /// Lightweight progress-only update (throttled 1/sec): updates only position, duration & play state
  /// without re-resolving artwork or touching bitmap cache.
  Future<void> updateProgress({
    required bool isPlaying,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    try {
      await _ensureAppGroup();
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);
      await HomeWidget.saveWidgetData<int>(
          'positionMs', position.inMilliseconds);
      await HomeWidget.saveWidgetData<int>(
          'durationMs', duration.inMilliseconds);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
        iOSName: iOSWidgetName,
      );
    } catch (e, st) {
      ErrorLogger.log('updateProgress failed', error: e, stackTrace: st, category: 'WidgetService');
    }
  }

  /// Exports an artwork image for the widget, cached per song.
  Future<String?> _resolveArtworkPath(SongsTableData song) async {
    final songId = song.id;
    final cachedPath = _artworkCache[songId];
    if (cachedPath != null) {
      final f = File(cachedPath);
      if (await f.exists() && await f.length() > 0) return cachedPath;
      _artworkCache.remove(songId);
      _roundedArtworkCache.remove(songId);
    }

    try {
      final dir = await getTemporaryDirectory();
      final cleanId = songId < 0 ? 'neg_${songId.abs()}' : '$songId';
      final cachedFile = File('${dir.path}/pulsr_widget_art_$cleanId.png');
      if (await cachedFile.exists() && await cachedFile.length() > 0) {
        _artworkCache[songId] = cachedFile.path;
        return cachedFile.path;
      }

      Uint8List? rawBytes = _roundedArtworkCache[songId];
      if (rawBytes == null) {
        final remoteUrl = song.remoteArtworkUrl ??
            (song.artworkUri?.startsWith('http') == true
                ? song.artworkUri
                : null);

        // 1. Fast path: Check in-memory ArtworkLruCache
        if (remoteUrl != null && remoteUrl.isNotEmpty) {
          rawBytes = ArtworkLruCache().get('${remoteUrl}_hq') ??
              ArtworkLruCache().get(remoteUrl);
        } else {
          rawBytes = ArtworkLruCache().get('AUDIO_${songId}_hq') ??
              ArtworkLruCache().get('AUDIO_$songId');
        }

        // 2. Check persistent ArtworkCacheManager disk cache
        if (rawBytes == null && remoteUrl != null && remoteUrl.isNotEmpty) {
          final targetUrl = CachedArtwork.upgradeToHighResArtwork(remoteUrl);
          rawBytes = await ArtworkCacheManager().get(targetUrl) ??
              await ArtworkCacheManager().get(remoteUrl);

          if (rawBytes == null || rawBytes.isEmpty) {
            // Fetch remote artwork via HTTP
            HttpClient? client;
            try {
              final uri = Uri.tryParse(targetUrl) ?? Uri.tryParse(remoteUrl);
              if (uri != null) {
                client = HttpClient()
                  ..connectionTimeout = const Duration(seconds: 8)
                  ..idleTimeout = const Duration(seconds: 5);
                final req = await client
                    .getUrl(uri)
                    .timeout(const Duration(seconds: 8));
                final res =
                    await req.close().timeout(const Duration(seconds: 8));
                if (res.statusCode == 200) {
                  final fetched =
                      await consolidateHttpClientResponseBytes(res)
                          .timeout(const Duration(seconds: 8));
                  if (fetched.isNotEmpty) {
                    rawBytes = fetched;
                    unawaited(ArtworkCacheManager().put(targetUrl, fetched));
                  }
                }
              }
            } catch (e, st) {
              ErrorLogger.log('_resolveArtworkPath HTTP fetch failed',
                  error: e, stackTrace: st, category: 'WidgetService');
            } finally {
              try {
                client?.close(force: true);
              } catch (e, st) {
                ErrorLogger.log('Failed to close widget HTTP client',
                    error: e, stackTrace: st, category: 'WidgetService');
              }
            }
          }
        }

        // 3. Check local file URI (e.g. file:///...)
        if ((rawBytes == null || rawBytes.isEmpty) &&
            song.artworkUri != null &&
            song.artworkUri!.isNotEmpty) {
          final parsed = Uri.tryParse(song.artworkUri!);
          if (parsed != null && parsed.scheme == 'file') {
            final f = File(parsed.toFilePath());
            if (await f.exists() && await f.length() > 0) {
              rawBytes = await f.readAsBytes();
            }
          }
        }

        // 4. Fallback to OnAudioQuery for local MediaStore tracks (Audio ID, then Album ID)
        if ((rawBytes == null || rawBytes.isEmpty) && songId > 0) {
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

        if (rawBytes == null || rawBytes.isEmpty) return null;

        _roundedArtworkCache[songId] = rawBytes;
      }

      await cachedFile.writeAsBytes(rawBytes, flush: true);
      _artworkCache[songId] = cachedFile.path;
      // Enforce LRU bounds
      if (_artworkCache.length > _maxCacheSize) {
        final oldestKey = _artworkCache.keys.first;
        _artworkCache.remove(oldestKey);
      }
      if (_roundedArtworkCache.length > _maxCacheSize) {
        final oldestKey = _roundedArtworkCache.keys.first;
        _roundedArtworkCache.remove(oldestKey);
      }
      // Opportunistically prune old widget temp files (older than 7 days)
      unawaited(_pruneOldWidgetArtwork(dir));
      return cachedFile.path;
    } catch (e, st) {
      ErrorLogger.log('Failed to resolve artwork path for widget',
          error: e, stackTrace: st, category: 'WidgetService');
      return null;
    }
  }

  // FIX-G01: Deleted unused dead code _roundCorners (native rounding moved to RemoteViews)

  static const Set<String> _knownWidgetActions = {
    'play_pause',
    'prev',
    'next',
    'favorite',
    'open',
    'main',
  };

  StreamSubscription<Uri?> listenToWidgetClicks(
      void Function(Uri? uri) onUriReceived) {
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
  Future<void> pruneOldWidgetArtwork(Directory dir) => _pruneOldWidgetArtwork(dir);

  Future<void> _pruneOldWidgetArtwork(Directory dir) async {
    try {
      // List the directory once, then stat every file concurrently instead of
      // awaiting stat() sequentially per file (I24).
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('pulsr_widget_art_')) {
          files.add(entity);
        }
      }
      if (files.isEmpty) return;

      final now = DateTime.now();
      final stats = <({File file, DateTime? modified})>[];
      const batchSize = 20; // limit concurrency
      for (var i = 0; i < files.length; i += batchSize) {
        final end = (i + batchSize < files.length) ? i + batchSize : files.length;
        final batchStats = await Future.wait(
          files.sublist(i, end).map((f) async {
            try {
              final stat = await f.stat();
              return (file: f, modified: stat.modified);
            } catch (e, st) {
              ErrorLogger.log('Failed to stat widget artwork file',
                  error: e, stackTrace: st, category: 'WidgetService');
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
            survivors.take(survivors.length - _maxCacheSize).map((s) => s.file));
      }

      for (var i = 0; i < stale.length; i += batchSize) {
        final end = (i + batchSize < stale.length) ? i + batchSize : stale.length;
        await Future.wait(stale.sublist(i, end).map((f) async {
          try {
            await f.delete();
          } catch (e, st) {
            ErrorLogger.log('_pruneOldWidgetArtwork failed',
                error: e, stackTrace: st, category: 'WidgetService');
          }
        }));
      }
    } catch (e, st) {
      ErrorLogger.log('_pruneOldWidgetArtwork failed',
          error: e, stackTrace: st, category: 'WidgetService');
    }
  }
}
