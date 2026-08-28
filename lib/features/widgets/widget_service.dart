import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:home_widget/home_widget.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/error_logger.dart';
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
          final artPath = await _resolveArtworkPath(song.id);
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
  Future<String?> _resolveArtworkPath(int songId) async {
    if (songId <= 0) return null;
    final cachedPath = _artworkCache[songId];
    if (cachedPath != null) {
      if (await File(cachedPath).exists()) return cachedPath;
      _artworkCache.remove(songId);
    }

    try {
      final dir = await getTemporaryDirectory();
      final cachedFile = File('${dir.path}/pulsr_widget_art_$songId.png');
      if (await cachedFile.exists()) {
        _artworkCache[songId] = cachedFile.path;
        return cachedFile.path;
      }

      Uint8List? rounded = _roundedArtworkCache[songId];
      if (rounded == null) {
        final bytes = await _audioQuery.queryArtwork(
          songId,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 256,
          quality: 90,
        );
        if (bytes == null || bytes.isEmpty) return null;

        rounded = await _roundCorners(bytes, size: 256, radius: 56);
        if (rounded == null) return null;
        _roundedArtworkCache[songId] = rounded;
      }

      await cachedFile.writeAsBytes(rounded, flush: true);
      _artworkCache[songId] = cachedFile.path;
      return cachedFile.path;
    } catch (_) {
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
