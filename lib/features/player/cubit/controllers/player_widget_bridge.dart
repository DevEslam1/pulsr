// lib/features/player/cubit/controllers/player_widget_bridge.dart
// FIX-A1: Focused PlayerWidgetBridge for home-widget push, scrobble dispatch, and telemetry
import '../../../../core/services/scrobbler_service.dart';
import '../../../../core/telemetry/playback_latency_tracker.dart';
import '../../../../data/db/app_database.dart';
import '../../../widgets/widget_service.dart';
import '../player_scrobble_coordinator.dart';
import '../player_state.dart';
import '../player_widget_coordinator.dart';

/// Bridges player playback state changes to OS widgets, scrobbling sinks, and telemetry.
class PlayerWidgetBridge {
  final PlayerWidgetCoordinator _widgetCoordinator;
  final PlayerScrobbleCoordinator _scrobbleCoordinator;
  final PlaybackLatencyTracker? _latencyTracker;

  PlayerWidgetBridge({
    WidgetService? widgetService,
    ScrobblerService? Function()? scrobblerService,
    PlaybackLatencyTracker? latencyTracker,
    required bool Function() isQuranMode,
    required bool Function() isClosed,
    Duration scrobbleInterval = const Duration(seconds: 5),
  })  : _widgetCoordinator = PlayerWidgetCoordinator(widgetService),
        _scrobbleCoordinator = PlayerScrobbleCoordinator(
          service: scrobblerService ?? (() => null),
          isQuranMode: isQuranMode,
          isClosed: isClosed,
          interval: scrobbleInterval,
        ),
        _latencyTracker = latencyTracker;

  void updateWidgetThrottled(PlayerState state, int queueVersion, {bool force = false}) {
    _widgetCoordinator.updateThrottled(state, queueVersion, force: force);
  }

  void updateProgressThrottled(PlayerState state) {
    _widgetCoordinator.updateProgressThrottled(state);
  }

  void debouncedScrobble(SongsTableData song, Duration position, bool isPlaying) {
    _scrobbleCoordinator.debouncedScrobble(song, position, isPlaying);
  }

  void trackStage(PlaybackStage stage) {
    try {
      _latencyTracker?.markStage(stage);
    } catch (_) {}
  }

  void dispose() {
    _scrobbleCoordinator.dispose();
  }
}
