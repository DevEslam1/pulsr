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

  int? _lastSavedArtworkSongId;

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
      await HomeWidget.saveWidgetData<int>(
          'positionMs', position.inMilliseconds);
      await HomeWidget.saveWidgetData<int>(
          'durationMs', duration.inMilliseconds);
      await HomeWidget.saveWidgetData<bool>('isFavorite', isFavorite);
      await HomeWidget.saveWidgetData<bool>('isShuffle', isShuffle);
      await HomeWidget.saveWidgetData<String>('repeatMode', repeatMode);
      for (int i = 0; i < 3; i++) {
        final title = (nextQueueTitles != null && i < nextQueueTitles.length)
            ? nextQueueTitles[i]
            : '';
        await HomeWidget.saveWidgetData<String>('nextTrack$i', title);
      }

      if (hasSong) {
        if (_lastSavedArtworkSongId != song.id) {
          final artPath = await _resolveArtworkPath(song);
          await HomeWidget.saveWidgetData<String>('artwork', artPath ?? '');
          _lastSavedArtworkSongId = song.id;
        }
      } else {
        if (_lastSavedArtworkSongId != null) {
          await HomeWidget.saveWidgetData<String>('artwork', '');
          _lastSavedArtworkSongId = null;
        }
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
    } catch (_) {}
  }

  /// Exports a corner-rounded artwork PNG for the widget, cached per song.
  Future<String?> _resolveArtworkPath(SongsTableData song) async {
    final songId = song.id;
    final cachedPath = _artworkCache[songId];
    if (cachedPath != null) {
      if (await File(cachedPath).exists()) return cachedPath;
      _artworkCache.remove(songId);
    }

    try {
      final dir = await getTemporaryDirectory();
      final cleanId = songId < 0 ? 'neg_${songId.abs()}' : '$songId';
      final cachedFile = File('${dir.path}/pulsr_widget_art_$cleanId.png');
      if (await cachedFile.exists()) {
        _artworkCache[songId] = cachedFile.path;
        return cachedFile.path;
      }

      Uint8List? rawBytes = _roundedArtworkCache[songId];
      if (rawBytes == null) {
        // 1. Check if song has remote/online artwork URL (e.g. YouTube Music / stream)
        final remoteUrl = song.remoteArtworkUrl ??
            (song.artworkUri?.startsWith('http') == true
                ? song.artworkUri
                : null);
        if (remoteUrl != null && remoteUrl.isNotEmpty) {
          final targetUrl = CachedArtwork.upgradeToHighResArtwork(remoteUrl);
          // Check ArtworkCacheManager cache
          var cachedBytes = await ArtworkCacheManager().get(targetUrl);
          if (cachedBytes == null || cachedBytes.isEmpty) {
            cachedBytes = await ArtworkCacheManager().get(remoteUrl);
          }

          if (cachedBytes != null && cachedBytes.isNotEmpty) {
            rawBytes = cachedBytes;
          } else {
            // Fetch remote artwork via HTTP
            try {
              final uri = Uri.tryParse(targetUrl) ?? Uri.tryParse(remoteUrl);
              if (uri != null) {
                final client = HttpClient()
                  ..connectionTimeout = const Duration(seconds: 5);
                final req = await client
                    .getUrl(uri)
                    .timeout(const Duration(seconds: 5));
                final res =
                    await req.close().timeout(const Duration(seconds: 5));
                if (res.statusCode == 200) {
                  final fetched =
                      await consolidateHttpClientResponseBytes(res)
                          .timeout(const Duration(seconds: 5));
                  if (fetched.isNotEmpty) {
                    rawBytes = fetched;
                    unawaited(ArtworkCacheManager().put(targetUrl, fetched));
                  }
                }
              }
            } catch (_) {}
          }
        }

        // 2. Check local file URI (e.g. file:///...)
        if ((rawBytes == null || rawBytes.isEmpty) &&
            song.artworkUri != null &&
            song.artworkUri!.isNotEmpty) {
          final parsed = Uri.tryParse(song.artworkUri!);
          if (parsed != null && parsed.scheme == 'file') {
            final f = File(parsed.toFilePath());
            if (await f.exists()) {
              rawBytes = await f.readAsBytes();
            }
          }
        }

        // 3. Fallback to OnAudioQuery for local MediaStore tracks
        if ((rawBytes == null || rawBytes.isEmpty) && songId > 0) {
          rawBytes = await _audioQuery.queryArtwork(
            songId,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: 256,
            quality: 90,
          );
        }

        if (rawBytes == null || rawBytes.isEmpty) return null;

        final rounded = await _roundCorners(rawBytes, size: 256, radius: 56);
        if (rounded == null) return null;
        _roundedArtworkCache[songId] = rounded;
        rawBytes = rounded;
      }

      await cachedFile.writeAsBytes(rawBytes, flush: true);
      _artworkCache[songId] = cachedFile.path;
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
      final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
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
    } catch (e, st) {
      ErrorLogger.log('Failed to round corners for widget artwork',
          error: e, stackTrace: st, category: 'WidgetService');
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
}
