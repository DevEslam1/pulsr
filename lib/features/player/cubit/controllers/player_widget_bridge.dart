import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../core/services/scrobbler_service.dart';
import '../../../../core/telemetry/playback_latency_tracker.dart';
import '../../../../data/db/app_database.dart';
import '../../../widgets/widget_service.dart';
import '../player_scrobble_coordinator.dart';
import '../player_state.dart';
import '../player_widget_coordinator.dart';

/// Bridges player playback state changes to OS widgets, scrobbling sinks, and telemetry.
class PlayerWidgetBridge {
  final WidgetService? _widgetService;
  final PlayerWidgetCoordinator _widgetCoordinator;
  final PlayerScrobbleCoordinator _scrobbleCoordinator;
  final PlaybackLatencyTracker? _latencyTracker;
  StreamSubscription<Uri?>? _widgetClickSub;

  PlayerWidgetBridge({
    WidgetService? widgetService,
    ScrobblerService? Function()? scrobblerService,
    PlaybackLatencyTracker? latencyTracker,
    required bool Function() isQuranMode,
    required bool Function() isClosed,
    Duration scrobbleInterval = const Duration(seconds: 5),
  })  : _widgetService = widgetService,
        _widgetCoordinator = PlayerWidgetCoordinator(widgetService),
        _scrobbleCoordinator = PlayerScrobbleCoordinator(
          service: scrobblerService ?? (() => null),
          isQuranMode: isQuranMode,
          isClosed: isClosed,
          interval: scrobbleInterval,
        ),
        _latencyTracker = latencyTracker;

  void listenToClicks({
    required VoidCallback onPlayPause,
    required VoidCallback onPrevious,
    required VoidCallback onNext,
    required void Function() onFavorite,
  }) {
    _widgetClickSub = _widgetService?.listenToWidgetClicks((uri) {
      if (uri != null && uri.scheme.toLowerCase() == 'pulsrwidget') {
        final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
        switch (action) {
          case 'play_pause':
            onPlayPause();
            break;
          case 'prev':
            onPrevious();
            break;
          case 'next':
            onNext();
            break;
          case 'favorite':
            onFavorite();
            break;
        }
      }
    });
  }

  void onAudiblePlaybackStarted() {
    try {
      if (_latencyTracker?.hasActiveSession == true) {
        _latencyTracker?.markStage(PlaybackStage.firstBytesReady);
        _latencyTracker?.markStage(PlaybackStage.playing);
      }
    } catch (_) {}
  }

  void onPlaybackError(String error) {
    try {
      _latencyTracker?.finishWithError(error, stage: PlaybackStage.playing);
    } catch (_) {}
  }

  void updateWidgetThrottled(PlayerState state, {int queueVersion = 0, bool force = false}) {
    _widgetCoordinator.updateThrottled(state, queueVersion, force: force);
  }

  void updateProgressThrottled(PlayerState state) {
    _widgetCoordinator.updateProgressThrottled(state);
  }

  void updateWidgetProgressThrottled(PlayerState state) => updateProgressThrottled(state);

  void debouncedScrobble(SongsTableData song, Duration position, bool isPlaying) {
    _scrobbleCoordinator.debouncedScrobble(song, position, isPlaying);
  }

  void scrobble(SongsTableData song, Duration position, bool isPlaying) =>
      debouncedScrobble(song, position, isPlaying);

  void trackStage(PlaybackStage stage) {
    try {
      _latencyTracker?.markStage(stage);
    } catch (_) {}
  }

  void dispose() {
    _widgetClickSub?.cancel();
    _scrobbleCoordinator.dispose();
  }
}

