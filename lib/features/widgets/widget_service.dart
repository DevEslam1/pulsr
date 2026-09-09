import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Map<int, String> _artworkCache = {};
  final Map<int, Uint8List> _roundedArtworkCache = {};
  static const int _maxCacheSize = 50;

  int? _lastSavedArtworkSongId;

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

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
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
        _lastSavedArtworkSongId = song.id;
        await HomeWidget.saveWidgetData<String>('artwork', artPath);
        await HomeWidget.updateWidget(
          name: androidWidgetName,
          androidName: androidWidgetName,
          qualifiedAndroidName: qualifiedAndroidName,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Widget artwork async resolve failed',
          error: e, stackTrace: st, category: 'WidgetService');
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
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);
      await HomeWidget.saveWidgetData<int>(
          'positionMs', position.inMilliseconds);
      await HomeWidget.saveWidgetData<int>(
          'durationMs', duration.inMilliseconds);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
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
              } catch (_) {}
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

  Future<Uint8List?> _roundCorners(
    Uint8List src, {
    required int size,
    required double radius,
  }) async {
    ui.Codec? codec;
    ui.FrameInfo? frame;
    ui.Picture? picture;
    ui.Image? out;
    try {
      codec = await ui.instantiateImageCodec(
        src,
        targetWidth: size,
        targetHeight: size,
      );
      frame = await codec.getNextFrame();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final rect =
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      canvas.clipRRect(
          ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius)));
      canvas.drawImageRect(
        frame.image,
        ui.Rect.fromLTWH(
            0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
        rect,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );

      picture = recorder.endRecording();
      out = await picture.toImage(size, size);
      final byteData = await out.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      picture?.dispose();
      out?.dispose();
      frame?.image.dispose();
      codec?.dispose();
    }
  }

  StreamSubscription<Uri?> listenToWidgetClicks(
      void Function(Uri? uri) onUriReceived) {
    return HomeWidget.widgetClicked.listen(onUriReceived);
  }

  Future<void> _pruneOldWidgetArtwork(Directory dir) async {
    try {
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('pulsr_widget_art_')) {
          try {
            final stat = await entity.stat();
            if (now.difference(stat.modified).inDays > 7) {
              await entity.delete();
            }
          } catch (e, st) {
            ErrorLogger.log('_pruneOldWidgetArtwork failed', error: e, stackTrace: st, category: 'WidgetService');
          }
        }
      }
      // Also enforce total count limit for widget art files
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('pulsr_widget_art_')) {
          files.add(entity);
        }
      }
      if (files.length > _maxCacheSize) {
        files.sort((a, b) => a.path.compareTo(b.path));
        for (int i = 0; i < files.length - _maxCacheSize; i++) {
          try {
            await files[i].delete();
          } catch (e, st) {
            ErrorLogger.log('_pruneOldWidgetArtwork failed', error: e, stackTrace: st, category: 'WidgetService');
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log('_pruneOldWidgetArtwork failed', error: e, stackTrace: st, category: 'WidgetService');
    }
  }
}
