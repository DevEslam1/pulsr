// lib/core/services/yt_download_pause_registry.dart
import 'dart:async';

/// Tracks downloads the user paused, so the foreground notification stays up
/// with its Resume action.
///
/// Markers are bounded in time: nothing else ever drops one, so a paused-then-
/// abandoned download would otherwise hold the service (and the process) up
/// indefinitely on API < 35, where there is no dataSync foreground-time cap.
class YtDownloadPauseRegistry {
  YtDownloadPauseRegistry({this.onIdle});

  /// Called when the last marker ages out.
  final void Function()? onIdle;

  static const Duration idleWindow = Duration(minutes: 30);

  final Set<String> _ids = <String>{};
  final Map<String, DateTime> _since = {};
  Timer? _idleTimer;

  bool get isNotEmpty => _ids.isNotEmpty;
  bool contains(String videoId) => _ids.contains(videoId);

  void mark(String videoId) {
    _ids.add(videoId);
    _since[videoId] = DateTime.now();
    _refreshIdleTimer();
  }

  void clear(String videoId) {
    _ids.remove(videoId);
    _since.remove(videoId);
    _refreshIdleTimer();
  }

  /// Drops markers older than [idleWindow].
  void prune() {
    if (_since.isEmpty) return;
    final cutoff = DateTime.now().subtract(idleWindow);
    _since.removeWhere((id, since) {
      if (since.isBefore(cutoff)) {
        _ids.remove(id);
        return true;
      }
      return false;
    });
  }

  void _refreshIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    // clear() explicitly asks the owner to re-check the service; only the
    // timer path needs the callback to release a genuinely idle service.
    if (_ids.isEmpty) return;
    _idleTimer = Timer(idleWindow, () {
      _idleTimer = null;
      prune();
      if (_ids.isNotEmpty) {
        _refreshIdleTimer();
      } else {
        onIdle?.call();
      }
    });
  }
}
