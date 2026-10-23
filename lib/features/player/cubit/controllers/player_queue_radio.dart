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

  /// Sets whether endless autoplay is enabled.
  Future<void> setAutoplayEnabled(bool enabled) async {
    final s = _getState();
    _emit(s.copyWith(
      queueSlice: s.queueSlice.copyWith(isAutoplayEnabled: enabled),
    ));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.autoplayEnabled, enabled);
    } catch (_) {}
    if (enabled) {
      unawaited(checkAndTriggerAutoplay());
    }
  }

  /// Evaluates whether the queue is approaching its end and fetches recommendations if enabled.
  Future<void> checkAndTriggerAutoplay() async {
    final s = _getState();
    if (!s.isAutoplayEnabled || _isClosed()) return;
    if (s.queue.isEmpty) return;

    final remaining = s.queue.length - 1 - s.currentIndex;
    if (remaining > 2) return;

    // Use current song or last song in queue as seed
    final seedSong = s.currentSong ?? s.queue.last;
    final videoId = seedSong.remoteId;
    if (videoId == null || videoId.isEmpty) return;

    await fetchAndEnqueueAutoplay(videoId, seedArtist: seedSong.artist);
  }

  /// Normalized title for deduplication comparison (matching BitChord's QueueBuilder.normalizeTitle).
  static String normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(
            RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove parenthesized content
        .replaceAll(RegExp(r'[^a-z0-9]'), '') // keep only alphanumeric
        .trim();
  }

  /// Tests if two tracks represent the same recording using normalized title and artists.
  static bool isSameRecording(
      String titleA, String artistA, String titleB, String artistB) {
    final normA = normalizeTitle(titleA);
    final normB = normalizeTitle(titleB);
    if (normA.isNotEmpty && normA == normB) {
      final artSetA = artistA
          .toLowerCase()
          .split(RegExp(r'[,&/\\]'))
          .map((e) => e.trim())
          .toSet();
      final artSetB = artistB
          .toLowerCase()
          .split(RegExp(r'[,&/\\]'))
          .map((e) => e.trim())
          .toSet();
      if (artSetA.intersection(artSetB).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Fetches radio tracks via YtmService and appends them to the queue as QueueTier.autoplay.
  Future<void> fetchAndEnqueueAutoplay(String seedVideoId,
      {String? seedArtist}) async {
    final ytmService = _ytmService ??
        (getIt.isRegistered<YtmService>() ? getIt<YtmService>() : null);
    if (ytmService == null) return;

    try {
      final radioTracks =
          await ytmService.getRadioTracks(seedVideoId, limit: 15);
      if (radioTracks.isEmpty || _isClosed()) return;

      final s = _getState();
      final playedAndQueuedIds = <String>{};
      for (final song in s.queue) {
        if (song.remoteId != null) playedAndQueuedIds.add(song.remoteId!);
      }
      for (final song in s.queueHistory) {
        if (song.remoteId != null) playedAndQueuedIds.add(song.remoteId!);
      }

      final artistCounts = <String, int>{};
      final normalizedSeedArtist = (seedArtist ?? '').trim().toLowerCase();

      final eligible = <SongsTableData>[];
      for (final track in radioTracks) {
        if (playedAndQueuedIds.contains(track.videoId)) continue;

        // Duplicate recording check
        final hasDup = s.queue.any((q) => isSameRecording(
                q.title, q.artist, track.title, track.artist)) ||
            s.queueHistory.any((h) =>
                isSameRecording(h.title, h.artist, track.title, track.artist));
        if (hasDup) continue;

        // Artist limits: max 4 for seed artist, max 2 for other artists (matching BitChord)
        final trackArtist = track.artist.trim().toLowerCase();
        final limit = (normalizedSeedArtist.isNotEmpty &&
                trackArtist.contains(normalizedSeedArtist))
            ? 4
            : 2;
        final currentCount = artistCounts[trackArtist] ?? 0;
        if (currentCount >= limit) continue;

        artistCounts[trackArtist] = currentCount + 1;
        playedAndQueuedIds.add(track.videoId);

        final songData = track.toSongData();
        songData.isAutoplay = true;
        eligible.add(songData);
        if (eligible.length >= 10) break;
      }

      if (eligible.isEmpty || _isClosed()) return;

      final room = PlayerQueueController.maxQueueSize - s.queue.length;
      if (room <= 0) return;

      final toAppend = eligible.take(room).toList();
      // AUDIT-FIX: track only the songs the engine actually accepted — a
      // mid-loop failure must not append songs to the UI queue that were
      // never enqueued (mirrors the batch-add path in the queue controller).
      final added = <SongsTableData>[];
      for (final song in toAppend) {
        try {
          await _audioHandler.addToQueueEnd(song);
          added.add(song);
        } catch (e, st) {
          ErrorLogger.log('Failed to add autoplay song ${song.title}',
              error: e, stackTrace: st, category: 'PlayerQueueRadio');
          break;
        }
      }
      if (added.isEmpty || _isClosed()) return;

      final fresh = _getState();
      final updatedQueue = [...fresh.queue, ...added];
      final updatedTiers = Map<int, QueueTier>.from(fresh.trackTiers);
      for (final song in added) {
        updatedTiers[song.id] = QueueTier.autoplay;
      }

      setQueueSlot(
        fresh.activeQueueSlot,
        songs: updatedQueue,
        currentIndex: fresh.currentIndex,
        position: fresh.position,
        speed: fresh.playbackSpeed,
      );
      debouncedPersistQueueSlots();
      _bumpQueueVersion();
      _emit(fresh.copyWith(
        queueSlice: fresh.queueSlice.copyWith(
          queue: List<SongsTableData>.unmodifiable(updatedQueue),
          trackTiers: updatedTiers,
        ),
      ));
      _invalidateQueueSyncResolution();
    } catch (e, st) {
      ErrorLogger.log('fetchAndEnqueueAutoplay failed',
          error: e, stackTrace: st, category: 'PlayerQueueRadio');
    }
  }

  /// Rotates list by 1 if a random shuffle happened to produce identical order.
  static void _avoidIdentityShuffle<T>(List<T> original, List<T> shuffled) {
    if (original.length < 2) return;
    var identical = true;
    for (var i = 0; i < original.length; i++) {
      if (original[i] != shuffled[i]) {
        identical = false;
        break;
      }
    }
    if (identical) {
      final first = shuffled.removeAt(0);
      shuffled.add(first);
    }
  }

  /// Tiered shuffle:
  /// - User-queued tracks stay pinned in order at the front of upcoming
  /// - Context tracks and autoplay tracks are shuffled in their respective partitions
  Future<void> tieredShuffle() async {
    final state = _getState();
    if (state.queue.length <= 1) return;

    final currIdx = state.currentIndex;
    final currentSong = state.currentSong;
    if (currentSong == null) return;

    final past = state.queue.sublist(0, currIdx);
    final upcoming = state.queue.sublist(currIdx + 1);

    if (upcoming.isEmpty) return;

    final userQueued = <SongsTableData>[];
    final contextTracks = <SongsTableData>[];
    final autoplayTracks = <SongsTableData>[];

    for (final song in upcoming) {
      final tier = state.trackTiers[song.id] ??
          (song.isAutoplay ? QueueTier.autoplay : QueueTier.context);
      switch (tier) {
        case QueueTier.userQueue:
          userQueued.add(song);
          break;
        case QueueTier.autoplay:
          autoplayTracks.add(song);
          break;
        case QueueTier.context:
          contextTracks.add(song);
          break;
      }
    }

    final shuffledContext = List<SongsTableData>.from(contextTracks)..shuffle();
    _avoidIdentityShuffle(contextTracks, shuffledContext);

    final shuffledAutoplay = List<SongsTableData>.from(autoplayTracks)
      ..shuffle();
    _avoidIdentityShuffle(autoplayTracks, shuffledAutoplay);

    final newUpcoming = [
      ...userQueued,
      ...shuffledContext,
      ...shuffledAutoplay,
    ];

    final newQueue = [
      ...past,
      currentSong,
      ...newUpcoming,
    ];

    await playSong(currentSong, queue: newQueue, preservePlaybackState: true);
  }
}
