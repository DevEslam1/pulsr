part of 'player_cubit.dart';

mixin PlayerPlaybackOptions on PulsrCubit<PlayerState> {
  PlayerPlaybackOptionsController get playbackOptionsController;

  void startSleepTimer(int minutes) =>
      playbackOptionsController.startSleepTimer(minutes);

  void startAbsoluteSleepTimer(DateTime stopTime) =>
      playbackOptionsController.startAbsoluteSleepTimer(stopTime);

  void startEndOfTrackTimer() =>
      playbackOptionsController.startEndOfTrackTimer();

  void startAfterNTracksTimer(int trackCount) =>
      playbackOptionsController.startAfterNTracksTimer(trackCount);

  void startEndOfQueueTimer() =>
      playbackOptionsController.startEndOfQueueTimer();

  void cancelSleepTimer() => playbackOptionsController.cancelSleepTimer();

  int? get sleepTimerRemainingTracks =>
      playbackOptionsController.sleepTimerRemainingTracks;

  SleepTimerMode get sleepTimerMode => playbackOptionsController.sleepTimerMode;

  bool get isEndOfQueueSleepTimer =>
      playbackOptionsController.isEndOfQueueSleepTimer;

  Stream<int?> get sleepTimerRemainingTracksStream =>
      playbackOptionsController.sleepTimerRemainingTracksStream;

  double get minPlaybackSpeed => playbackOptionsController.minPlaybackSpeed;

  double get maxPlaybackSpeed => playbackOptionsController.maxPlaybackSpeed;

  Future<void> setPlaybackSpeed(double speed) =>
      playbackOptionsController.setPlaybackSpeed(speed);

  Future<void> setPlaybackPitch(double pitch) =>
      playbackOptionsController.setPlaybackPitch(pitch);

  Future<void> setRating(int rating) =>
      playbackOptionsController.setRating(rating);

  Future<void> setSongRating(int songId, int rating) =>
      playbackOptionsController.setSongRating(songId, rating);

  Future<void> setSongEqOverrideById(int songId, String? presetName) =>
      playbackOptionsController.setSongEqOverrideById(songId, presetName);

  Future<void> setCurrentSongEqOverride(String? presetName) =>
      playbackOptionsController.setCurrentSongEqOverride(presetName);

  Future<void> setSongEqOverride(dynamic songIdOrPreset,
          [String? presetName]) =>
      playbackOptionsController.setSongEqOverride(songIdOrPreset, presetName);

  Future<void> setSongVolumeOverride(int songId, double gainDb) =>
      playbackOptionsController.setSongVolumeOverride(songId, gainDb);

  Future<void> setSongVolumeOverrideDb(double offsetDb, {int? songId}) =>
      playbackOptionsController.setSongVolumeOverrideDb(offsetDb,
          songId: songId);

  Future<void> setVolume(double volume) =>
      playbackOptionsController.setVolume(volume);

  Future<void> adjustVolume(double delta) =>
      playbackOptionsController.adjustVolume(delta);

  /// A-06: Toggle output mute (restores pre-mute volume on unmute).
  Future<void> toggleMute() => playbackOptionsController.toggleMute();

  /// A-01: Restore a resumed track's per-song speed/pitch/volume/EQ memory.
  Future<void> applyPerSongPlaybackMemory(SongsTableData song) =>
      playbackOptionsController.applyPerSongPlaybackMemory(song);

  String exportCurrentEqPreset() =>
      playbackOptionsController.exportCurrentEqPreset();

  Future<bool> importEqPreset(String jsonString) =>
      playbackOptionsController.importEqPreset(jsonString);

  void toggleLyrics() => playbackOptionsController.toggleLyrics();

  void toggleLyricsVisibility() =>
      playbackOptionsController.toggleLyricsVisibility();

  void toggleQueue() => playbackOptionsController.toggleQueue();

  void toggleQueueVisibility() =>
      playbackOptionsController.toggleQueueVisibility();

  void resetOverlayViews() => playbackOptionsController.resetOverlayViews();

  void setExpanded(bool expanded) =>
      playbackOptionsController.setExpanded(expanded);

  void setAbPointA() => playbackOptionsController.setAbPointA();

  void setAbPointB() => playbackOptionsController.setAbPointB();

  void clearAbLoop() => playbackOptionsController.clearAbLoop();

  void setTrackDelayMs(int delayMs) =>
      playbackOptionsController.setTrackDelayMs(delayMs);

  void setSilenceSkipSensitivity(int sensitivity) =>
      playbackOptionsController.setSilenceSkipSensitivity(sensitivity);

  void setQuranModeEnabled(bool enabled) =>
      playbackOptionsController.setQuranModeEnabled(enabled);

  void setQuranReciterStyle(QuranReciterStyle style) =>
      playbackOptionsController.setQuranReciterStyle(style);

  void toggleAbLoop() => playbackOptionsController.toggleAbLoop();

  void seekToBookmark() => playbackOptionsController.seekToBookmark();

  void dismissBookmark() => playbackOptionsController.dismissBookmark();

  Future<void> setQuranAmbience(double v) =>
      playbackOptionsController.setQuranAmbience(v);

  Future<void> reapplyQuranProfile() =>
      playbackOptionsController.reapplyQuranProfile();

  Future<bool> updateLyrics(List<LyricsLine> lines) =>
      playbackOptionsController.updateLyrics(lines);

  Future<void> refreshLyrics() => playbackOptionsController.refreshLyrics();

  Future<EarbudCapabilities> detectEarbudCapabilities() =>
      playbackOptionsController.detectEarbudCapabilities();

  Future<bool> saveBookmark() => playbackOptionsController.saveBookmark();

  PlaybackBookmark? storedBookmarkFor(SongsTableData song) =>
      playbackOptionsController.storedBookmarkFor(song);

  Future<void> clearBookmark() => playbackOptionsController.clearBookmark();

  Future<void> setTrackBpm(SongsTableData song, double? bpm) =>
      playbackOptionsController.setTrackBpm(song, bpm);
}
