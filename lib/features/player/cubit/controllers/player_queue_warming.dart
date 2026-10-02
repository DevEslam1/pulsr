// lib/features/player/cubit/controllers/player_queue_warming.dart
part of 'player_queue_controller.dart';

/// Gap between successive speculative warms in [PlayerQueueWarmingExtension.
/// warmStreams], so opening a list never stacks several full multi-engine
/// resolves on the native thread pool — or bursts enough googlevideo requests
/// to trip bot detection — at once. Mirrors the search screen's own
/// speculative-warm stagger.
const Duration _warmStreamStagger = Duration(milliseconds: 400);

/// Speculative stream pre-resolution ("stream warming") for the queue
/// controller. Split out of player_queue_controller.dart (pure code movement,
/// no behaviour change) to keep that file within the controller size budget.
/// Lives in the same library (`part of`), so it reads the shared
/// `_audioHandler` / `_isClosed` members directly.
extension PlayerQueueWarmingExtension on PlayerQueueController {
  /// Fire-and-forget stream pre-resolution for a track the user is likely to
  /// play next — e.g. the first item of a freshly rendered list. Fills the
  /// shared YtmUrlCache so the eventual tap skips the network resolve entirely
  /// instead of paying it at tap-to-sound time. Idempotent and non-throwing.
  void warmStream(SongsTableData song) {
    try {
      _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
    } catch (_) {}
  }

  /// Fire-and-forget pre-resolution of the first [count] streaming-eligible
  /// tracks of a freshly rendered list — the taps a user is most likely to
  /// make near the top. Each warm is staggered by [_warmStreamStagger], skips
  /// tracks that aren't online-streamable (local, already downloaded, or
  /// missing a remote id), is a no-op when the URL is already cached fresh, and
  /// short-circuits cheaply while YTM is bot-cooling (the underlying
  /// [resolveStream] skips the native tiers). Idempotent and non-throwing;
  /// safe to call on every render.
  void warmStreams(List<SongsTableData> songs, {int count = 3}) {
    if (songs.isEmpty || count <= 0) return;
    var warmed = 0;
    for (final song in songs) {
      if (warmed >= count) break;
      if (song.source != SongSource.youtube ||
          song.isDownloaded == true ||
          (song.remoteId?.isEmpty ?? true)) {
        continue;
      }
      final delay = _warmStreamStagger * warmed;
      warmed++;
      unawaited(Future<void>.delayed(delay, () {
        if (_isClosed()) return;
        try {
          _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
        } catch (_) {}
      }));
    }
  }
}
