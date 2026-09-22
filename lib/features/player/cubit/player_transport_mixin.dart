part of 'player_cubit.dart';

mixin PlayerTransportControls on PulsrCubit<PlayerState> {
  PlayerTransportController get transportController;

  Future<void> play() => transportController.play();

  Future<void> pause() => transportController.pause();

  Future<void> togglePlayPause() => transportController.togglePlayPause();

  Future<void> seek(Duration position) => transportController.seek(position);

  Future<void> next() => transportController.next();

  Future<void> previous() => transportController.previous();

  Future<void> skipToQueueItem(int index) =>
      transportController.skipToQueueItem(index);

  Future<void> toggleShuffle() => transportController.toggleShuffle();

  Future<void> toggleRepeat() => transportController.toggleRepeat();

  Future<void> toggleFavorite(dynamic target) =>
      transportController.toggleFavorite(target);

  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) =>
      transportController.fastForward(step);

  Future<void> rewind([Duration step = const Duration(seconds: 10)]) =>
      transportController.rewind(step);
}
