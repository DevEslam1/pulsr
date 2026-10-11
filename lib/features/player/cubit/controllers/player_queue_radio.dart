part of 'player_queue_controller.dart';

extension PlayerQueueRadio on PlayerQueueController {
  /// Whether the active track is a live radio stream. Derived from the current
  /// song's source so it self-clears when a regular track starts.
  bool get isLiveRadio => _getState().currentSong?.source == SongSource.radio;

  /// Pause for a live stream acts as stop: the buffered stream is retained but
  /// playback is halted and the stale position is dropped so a later resume
  /// cannot continue behind the live edge.
  Future<void> pauseLiveRadio() async {
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        isPlaying: false,
        isBuffering: false,
        position: Duration.zero,
      ),
    ));
    try {
      await _audioHandler.pause();
    } catch (e, st) {
      ErrorLogger.log('Failed to pause live radio',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Failed to pause radio'),
        ));
      }
    }
  }

  /// Resume for a live stream re-seeks to the live edge (position zero on a
  /// live just_audio source) before playing, instead of resuming the stale
  /// buffer.
  Future<void> resumeLiveRadio() async {
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        isPlaying: true,
        isBuffering: false,
        position: Duration.zero,
      ),
    ));
    try {
      await _audioHandler.seek(Duration.zero);
      await _audioHandler.play();
    } catch (e, st) {
      ErrorLogger.log('Failed to resume live radio',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          playback: s.playback.copyWith(
            isPlaying: false,
            errorMessage: 'Failed to start radio',
          ),
        ));
      }
    }
  }

  void setQueueSlot(
    int slot, {
    required List<SongsTableData> songs,
    required int currentIndex,
    required Duration position,
    required double speed,
  }) {
    _cacheSlotSongs(_slotLookupCache, songs);
    _queueSlots[slot] = QueueSlotData(
      songIds: songs.map((s) => s.id).toList(),
      currentIndex: currentIndex,
      position: position,
      speed: speed,
    );
  }

  Future<void> playRadioStation(RadioStation station) async {
    final uri = Uri.tryParse(station.url);
    if (!RadioStation.isHttpUrl(station.url) ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      final s = _getState();
      _emit(s.copyWith(
          playback: s.playback.copyWith(
              errorMessage: 'Invalid stream URL (must be HTTP/HTTPS)')));
      return;
    }
    final song = SongsTableData(
      id: station.songId,
      title: station.name,
      artist: (station.genre != null && station.genre!.isNotEmpty)
          ? station.genre!
          : station.name,
      album: '',
      durationMs: 0,
      path: station.url,
      source: SongSource.radio,
      remoteArtworkUrl: station.artworkUrl,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );
    unawaited(RadioStationStore().markPlayed(
      station.id,
      DateTime.now().millisecondsSinceEpoch,
    ));
    await playSong(song);
  }
}
