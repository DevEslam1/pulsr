// lib/features/widgets/widget_service.dart
import 'dart:async';
import 'package:home_widget/home_widget.dart';
import 'package:injectable/injectable.dart';
import '../../data/db/app_database.dart';

@singleton
class WidgetService {
  static const String androidWidgetName = 'NowPlayingWidget';
  static const String qualifiedAndroidName = 'com.example.pulsr.NowPlayingWidget';

  /// Updates the Now Playing home screen widget with current song and playback status.
  Future<void> updateNowPlaying({
    required SongsTableData? song,
    required bool isPlaying,
  }) async {
    try {
      final title = song?.title.isNotEmpty == true ? song!.title : 'No song playing';
      final artist = song?.artist.isNotEmpty == true ? song!.artist : 'Pulsr Music';
      final artworkPath = song?.path ?? '';

      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('artist', artist);
      await HomeWidget.saveWidgetData<String>('artwork', artworkPath);
      await HomeWidget.saveWidgetData<bool>('isPlaying', isPlaying);

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        qualifiedAndroidName: qualifiedAndroidName,
      );
    } catch (_) {
      // Ignore widget update errors silently to avoid disrupting playback
    }
  }

  /// Listens to widget interactive click callbacks (Uri schemes).
  StreamSubscription<Uri?> listenToWidgetClicks(void Function(Uri? uri) onUriReceived) {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(onUriReceived);
    return HomeWidget.widgetClicked.listen(onUriReceived);
  }
}
