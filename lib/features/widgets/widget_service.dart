import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:home_widget/home_widget.dart';
import 'package:injectable/injectable.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';

@lazySingleton
class WidgetService {
  static const String androidWidgetName = 'NowPlayingWidget';
  static const String qualifiedAndroidName = 'com.example.pulsr.NowPlayingWidget';

  final OnAudioQuery _audioQuery = OnAudioQuery();

  int? _lastArtworkSongId;
  String? _lastArtworkPath;

  Future<void> updateNowPlaying({
    required SongsTableData? song,
    required bool isPlaying,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool isFavorite = false,
    bool isShuffle = false,
    String repeatMode = 'off',
  }) async {
    try {
      final hasSong = song != null;

      await HomeWidget.saveWidgetData<String>(
        'title',
        hasSong && song.title.trim().isNotEmpty ? song.title : 'Pulsr Music',
      );
      await HomeWidget.saveWidgetData<String>(
        'artist',
        hasSong && song.artist.trim().isNotEmpty ? song.artist : 'Nothing playing',
      );
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);
      await HomeWidget.saveWidgetData<int>('positionMs', position.inMilliseconds);
      await HomeWidget.saveWidgetData<int>('durationMs', duration.inMilliseconds);
      await HomeWidget.saveWidgetData<bool>('isFavorite', isFavorite);
      await HomeWidget.saveWidgetData<bool>('isShuffle', isShuffle);
      await HomeWidget.saveWidgetData<String>('repeatMode', repeatMode);

      if (hasSong) {
        final artPath = await _resolveArtworkPath(song.id);
        await HomeWidget.saveWidgetData<String>('artwork', artPath ?? '');
      } else {
        await HomeWidget.saveWidgetData<String>('artwork', '');
      }

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
      );
    } catch (_) {}
  }

  /// Exports a corner-rounded artwork PNG for the widget, cached per song.
  /// The widget refreshes ~1s during playback, so we only re-encode when
  /// the track actually changes.
  Future<String?> _resolveArtworkPath(int songId) async {
    if (_lastArtworkSongId == songId && _lastArtworkPath != null) {
      if (await File(_lastArtworkPath!).exists()) return _lastArtworkPath;
    }
    try {
      final dir = await getTemporaryDirectory();
      final cachedFile = File('${dir.path}/pulsr_widget_art_$songId.png');
      if (await cachedFile.exists()) {
        _lastArtworkSongId = songId;
        _lastArtworkPath = cachedFile.path;
        return cachedFile.path;
      }
      final bytes = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 256,
        quality: 90,
      );
      if (bytes == null || bytes.isEmpty) return null;

      final rounded = await _roundCorners(bytes, size: 256, radius: 56);
      if (rounded == null) return null;

      await cachedFile.writeAsBytes(rounded, flush: true);

      _lastArtworkSongId = songId;
      _lastArtworkPath = cachedFile.path;
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
    try {
      final codec = await ui.instantiateImageCodec(
        src,
        targetWidth: size,
        targetHeight: size,
      );
      final frame = await codec.getNextFrame();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final rect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      canvas.clipRRect(ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius)));
      canvas.drawImageRect(
        frame.image,
        ui.Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
        rect,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );

      final picture = recorder.endRecording();
      final out = await picture.toImage(size, size);
      final byteData = await out.toByteData(format: ui.ImageByteFormat.png);

      picture.dispose();
      out.dispose();
      frame.image.dispose();
      codec.dispose();

      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  StreamSubscription<Uri?> listenToWidgetClicks(void Function(Uri? uri) onUriReceived) {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(onUriReceived);
    return HomeWidget.widgetClicked.listen(onUriReceived);
  }
}
