part of 'player_queue_controller.dart';

extension PlayerQueueRadio on PlayerQueueController {
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
