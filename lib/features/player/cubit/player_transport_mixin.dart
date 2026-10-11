part of 'player_cubit.dart';

mixin PlayerTransportControls on PulsrCubit<PlayerState> {
  PlayerTransportController get transportController;
  PlayerQueueController get queueController;

  /// Cancels any in-flight mediaItem resolution from a previous selection.
  void invalidateMediaItemResolution();

  Future<void> play() {
    if (queueController.isLiveRadio) return queueController.resumeLiveRadio();
    return transportController.play();
  }

  Future<void> pause() {
    if (queueController.isLiveRadio) return queueController.pauseLiveRadio();
    return transportController.pause();
  }

  Future<void> togglePlayPause() {
    if (queueController.isLiveRadio) {
      return state.isPlaying
          ? queueController.pauseLiveRadio()
          : queueController.resumeLiveRadio();
    }
    return transportController.togglePlayPause();
  }

  Future<void> seek(Duration position) => transportController.seek(position);

  Future<void> next() => transportController.next();

  Future<void> previous() => transportController.previous();

  Future<void> skipToQueueItem(int index) {
    invalidateMediaItemResolution();
    return transportController.skipToQueueItem(index);
  }

  Future<void> toggleShuffle() => transportController.toggleShuffle();

  Future<void> toggleRepeat() => transportController.toggleRepeat();

  Future<void> toggleFavoriteSong(SongsTableData song) =>
      transportController.toggleFavoriteSong(song);

  Future<void> toggleFavoriteById(int songId) =>
      transportController.toggleFavoriteById(songId);

  Future<void> toggleFavorite([Object? target]) =>
      transportController.toggleFavorite(target);

  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) =>
      transportController.fastForward(step);

  Future<void> rewind([Duration step = const Duration(seconds: 10)]) =>
      transportController.rewind(step);
}
