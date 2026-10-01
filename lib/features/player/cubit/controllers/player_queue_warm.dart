// lib/features/player/cubit/controllers/player_queue_warm.dart
part of 'player_queue_controller.dart';

/// Gap between successive speculative warms in [PlayerQueueWarmExtension.warmStreams].
const Duration _warmStreamStagger = Duration(milliseconds: 400);

/// Speculative stream pre-resolution for the tracks a user is likely to play next.
/// Kept in a part so `player_queue_controller.dart` stays under the 400-line cap.
extension PlayerQueueWarmExtension on PlayerQueueController {
  /// Fire-and-forget stream pre-resolution for a track the user is likely to play next.
  void warmStream(SongsTableData song) {
    try {
      _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
    } catch (_) {}
  }

  /// Fire-and-forget pre-resolution of the first [count] streaming-eligible tracks.
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
      late final Timer timer;
      timer = Timer(delay, () {
        _warmTimers.remove(timer);
        if (_isClosed()) return;
        try {
          _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
        } catch (_) {}
      });
      _warmTimers.add(timer);
    }
  }
}
