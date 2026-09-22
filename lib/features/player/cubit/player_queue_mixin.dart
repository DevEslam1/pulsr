part of 'player_cubit.dart';

mixin PlayerQueueOps on PulsrCubit<PlayerState> {
  PlayerQueueController get queueController;

  /// Invalidates any in-flight mediaItem resolution. Called when the user
  /// explicitly selects a track so a slow DB lookup for the previous selection
  /// cannot clobber the new one when it finally completes.
  void invalidateMediaItemResolution();

  Future<void> playRadioStation(RadioStation station) =>
      queueController.playRadioStation(station);

  Future<void> playSong(
    SongsTableData song, {
    List<SongsTableData>? queue,
    Duration? initialPosition,
    bool openPlayerIfPlaying = true,
  }) {
    invalidateMediaItemResolution();
    return queueController.playSong(
      song,
      queue: queue,
      initialPosition: initialPosition,
      openPlayerIfPlaying: openPlayerIfPlaying,
    );
  }

  Future<void> playNext(SongsTableData song) =>
      queueController.playNext(song);

  Future<void> addToQueue(SongsTableData song) =>
      queueController.addToQueue(song);

  Future<void> addAllToQueue(List<SongsTableData> songs) =>
      queueController.addAllToQueue(songs);

  Future<void> clearQueue() => queueController.clearQueue();

  void restoreQueue(List<SongsTableData> previousQueue, int previousIndex) =>
      queueController.restoreQueue(previousQueue, previousIndex);

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      queueController.reorderQueue(oldIndex, newIndex);

  Future<void> removeQueueItem(int index) =>
      queueController.removeQueueItem(index);

  Future<void> switchQueueSlot(int slot) =>
      queueController.switchQueueSlot(slot);

  Future<void> swapReconciledSong(dynamic oldSongOrId, dynamic newSongOrId) =>
      queueController.swapReconciledSong(oldSongOrId, newSongOrId);
}
