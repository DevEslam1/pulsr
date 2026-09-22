part of 'player_cubit.dart';

mixin PlayerQueueOps on PulsrCubit<PlayerState> {
  /// Plays an internet radio [station] by projecting it onto the normal queue
  /// as a synthetic pseudo-song whose `path` is the stream URL and whose id is
  /// a negative hash. The negative id keeps repository cleanup and
  /// play-history from ever treating it as a real local file; the absolute
  /// `http(s)` path is what routes it through the handler's URL source path.
  Future<void> playRadioStation(RadioStation station) async {
    if (!RadioStation.isHttpUrl(station.url)) {
      safeEmit(state.copyWith(errorMessage: 'Invalid stream URL'));
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
      source: SongSource.local,
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

  Future<void> playNext(SongsTableData song) async {
    if (state.queue.length >= PlayerCubit._maxQueueSize) {
      safeEmit(state.copyWith(
          errorMessage: 'Queue full (${PlayerCubit._maxQueueSize}) — cannot add more'));
      return;
    }
    try {
      await _audioHandler.insertNextInQueue(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to insert next in queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to add ${song.title}'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    // Same track identity as _isSameTrack (id, remoteId, or path): the raw-id
    // lookup missed the downloaded twin of an online row and let
    // cross-id duplicates through with mismatched indexes.
    final existingIdx = updatedQueue.indexWhere((s) => _isSameTrack(s, song));
    final targetSlot = (state.currentIndex + 1).clamp(0, updatedQueue.length);
    if (existingIdx != -1) {
      if (existingIdx != state.currentIndex && existingIdx != targetSlot) {
        final item = updatedQueue.removeAt(existingIdx);
        final adjustedTarget =
            targetSlot > existingIdx ? targetSlot - 1 : targetSlot;
        updatedQueue.insert(adjustedTarget.clamp(0, updatedQueue.length), item);
      }
    } else {
      updatedQueue.insert(targetSlot, song);
    }
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  /// Batch album/detail-level queue action (gap 07-03): appends [songs] to the
  /// end of the active queue, skipping tracks already queued. Bounded by
  /// [_maxQueueSize] with an error message instead of silent truncation.
  Future<void> addAllToQueue(List<SongsTableData> songs) async {
    if (songs.isEmpty || isClosed) return;
    final room = PlayerCubit._maxQueueSize - state.queue.length;
    if (room <= 0) {
      safeEmit(state.copyWith(
          errorMessage: 'Queue full (${PlayerCubit._maxQueueSize}) — cannot add more'));
      return;
    }
    final toAdd = songs
        .where((s) => !state.queue.any((q) => _isSameTrack(q, s)))
        .take(room)
        .toList();
    // Track only the rows the handler actually accepted: on a mid-loop failure
    // the cubit queue must mirror the engine, otherwise the UI lists tracks
    // that will never play.
    final added = <SongsTableData>[];
    for (final s in toAdd) {
      try {
        await _audioHandler.addToQueueEnd(s);
        added.add(s);
      } catch (e, st) {
        ErrorLogger.log('Failed to batch-add to queue',
            error: e, stackTrace: st, category: 'PlayerCubit');
        if (!isClosed) {
          safeEmit(state.copyWith(errorMessage: 'Failed to add ${s.title}'));
        }
        break;
      }
    }
    if (added.isEmpty) return;
    final updatedQueue = List<SongsTableData>.from(state.queue)..addAll(added);
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    if (state.queue.length >= PlayerCubit._maxQueueSize) {
      safeEmit(state.copyWith(
          errorMessage: 'Queue full (${PlayerCubit._maxQueueSize}) — cannot add more'));
      return;
    }
    try {
      await _audioHandler.addToQueueEnd(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to add to queue end',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to add ${song.title}'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final existingIdx = updatedQueue.indexWhere((s) => _isSameTrack(s, song));
    if (existingIdx != -1) {
      if (existingIdx != state.currentIndex &&
          existingIdx != updatedQueue.length - 1) {
        final item = updatedQueue.removeAt(existingIdx);
        updatedQueue.add(item);
      }
    } else {
      updatedQueue.add(song);
    }
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> clearQueue() async {
    try {
      await _audioHandler.clearQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed to clear queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to clear queue'));
      }
      return;
    }
    final current = state.currentSong;
    final updatedQueue = current != null ? [current] : <SongsTableData>[];
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: 0,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: 0));
  }

  /// Restores a previously cleared queue (Undo for destructive clear, gap 10-03).
  ///
  /// The handler is the actual playback queue, so restoring only the cubit's
  /// state/slots would leave the engine holding the single track `clearQueue`
  /// left behind — Next/Previous would then no-op. Re-load the full queue into
  /// the handler at the same index/position and resume only if it was playing.
  Future<void> restoreQueue(List<SongsTableData> songs, int index) async {
    if (songs.isEmpty || isClosed) return;
    final safeIndex = index.clamp(0, songs.length - 1);
    final wasPlaying = state.isPlaying;
    _setQueueSlot(
      state.activeQueueSlot,
      songs: List.of(songs),
      currentIndex: safeIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: List.of(songs), currentIndex: safeIndex));
    try {
      await _audioHandler.loadQueue(
        List.of(songs),
        initialIndex: safeIndex,
        initialPosition: state.position,
        autoPlay: wasPlaying,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to restore queue'));
      }
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex >= state.queue.length) {
      return;
    }
    if (oldIndex == newIndex) return;
    try {
      await _audioHandler.reorderQueue(oldIndex, newIndex);
    } catch (e, st) {
      ErrorLogger.log('Failed to reorder queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to reorder queue'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);
    var updatedIndex = state.currentIndex;
    if (updatedIndex == oldIndex) {
      updatedIndex = newIndex;
    } else if (oldIndex < updatedIndex && newIndex >= updatedIndex) {
      updatedIndex--;
    } else if (oldIndex > updatedIndex && newIndex <= updatedIndex) {
      updatedIndex++;
    }
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.removeQueueItemAt(index);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove queue item',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to remove track'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue)
      ..removeAt(index);
    var updatedIndex = state.currentIndex;
    if (updatedQueue.isEmpty) {
      updatedIndex = 0;
    } else if (index < updatedIndex) {
      updatedIndex--;
    } else if (index == updatedIndex) {
      updatedIndex = updatedIndex.clamp(0, updatedQueue.length - 1);
    }
    if (index == state.currentIndex) {
      // Removing the playing item: the handler rebuilds at the same clamped
      // index (removeQueueItemAt) and emits the new current via mediaItem,
      // but until that lands currentIndex pointed at the next song while
      // currentSong still held the removed one. Pre-empt with the same
      // arithmetic the handler uses, including the empty case.
      _queueVersion++;
      if (updatedQueue.isEmpty) {
        // The handler stops and emits a null mediaItem for this case.
        _setQueueSlot(
          state.activeQueueSlot,
          songs: const [],
          currentIndex: 0,
          position: Duration.zero,
          speed: state.playbackSpeed,
        );
        _debouncedPersistQueueSlots();
        safeEmit(state.copyWith(
          queue: const [],
          currentIndex: 0,
          currentSong: null,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
        ));
        _updateWidgetThrottled(force: true);
        return;
      }
      final newCurrent = updatedQueue[updatedIndex];
      final sameTrack = _isSameTrack(state.currentSong, newCurrent);
      _queueVersion++;
      _setQueueSlot(
        state.activeQueueSlot,
        songs: updatedQueue,
        currentIndex: updatedIndex,
        position: Duration.zero,
        speed: state.playbackSpeed,
      );
      _debouncedPersistQueueSlots();
      safeEmit(state.copyWith(
        queue: updatedQueue,
        currentIndex: updatedIndex,
        currentSong: newCurrent,
        position: Duration.zero,
        duration: Duration(milliseconds: newCurrent.durationMs),
        lyrics: sameTrack ? state.lyrics : [],
        lyricsSource: sameTrack ? state.lyricsSource : LyricsSource.none,
        isLoadingLyrics: !sameTrack,
      ));
      // The upcoming mediaItem emission sees isSameSong == true and skips
      // the lyrics load, so start it here.
      unawaited(_loadLyricsForSong(newCurrent));
      _updateWidgetThrottled(force: true);
      return;
    }
    _setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  Future<void> switchQueueSlot(int slot) async {
    if (_isSwitchingSlot ||
        slot == state.activeQueueSlot ||
        slot < 0 ||
        slot > 2) {
      return;
    }
    _isSwitchingSlot = true;
    try {
      // A naturally completed track reports isPlaying == false (the cubit
      // derives it from `playing && !completed`), but the user was listening.
      // Treat a finished-but-uninterrupted session as playing so switching
      // slots auto-plays instead of loading the target paused — mirrors the
      // handler's skipToNext/skipToQueueItem guard. A deliberate pause leaves
      // processingState == ready, so it still restores paused.
      final wasPlaying = state.isPlaying ||
          _audioHandler.playbackState.value.processingState ==
              AudioProcessingState.completed;
      _setQueueSlot(
        state.activeQueueSlot,
        songs: List.from(state.queue),
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      final targetSlot = _queueSlots[slot] ??
          const _QueueSlotData(
              songIds: [], currentIndex: 0, position: Duration.zero, speed: 1.0);
      final targetSongs = targetSlot.songsFrom(_slotLookupCache);
      final targetOriginalSong = (targetSlot.currentIndex >= 0 &&
              targetSlot.currentIndex < targetSongs.length)
          ? targetSongs[targetSlot.currentIndex]
          : null;
      final validSongs = targetSongs.where((s) => !s.isMissing).toList();

      _debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        safeEmit(state.copyWith(
          errorMessage: 'Queue slot is empty',
        ));
        return;
      }

      _queueVersion++;
      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx =
            validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
      }
      if (safeIdx == -1) {
        safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      }
      final song = validSongs[safeIdx];
      // Single atomic emit: a split emit exposed a transient state where the
      // new queue was paired with the old (possibly out-of-bounds) index.
      safeEmit(state.copyWith(
        activeQueueSlot: slot,
        queue: validSongs,
        currentIndex: safeIdx,
        currentSong: song,
        duration: Duration(milliseconds: song.durationMs),
        position: targetSlot.position,
        playbackSpeed: targetSlot.speed,
      ));
      try {
        await _audioHandler.setSpeed(targetSlot.speed);
        await _audioHandler.loadQueue(
          validSongs,
          initialIndex: safeIdx,
          initialPosition: targetSlot.position,
          autoPlay: wasPlaying,
        );
        unawaited(_loadLyricsForSong(song));
      } catch (e, st) {
        // The slot UI state is already switched; a failure here leaves the
        // handler on the previous queue until the next successful load.
        // Surface it instead of letting the throw escape into the widget tap
        // handler as an unhandled exception.
        ErrorLogger.log('Failed to switch queue slot $slot',
            error: e, stackTrace: st, category: 'PlayerCubit');
        if (!isClosed) {
          safeEmit(state.copyWith(errorMessage: 'Failed to switch queue slot'));
        }
      }
    } finally {
      _isSwitchingSlot = false;
    }
  }

  /// After a YouTube row is downloaded and folded into a positive-id local row,
  /// swap the stale negative-id row in the queues so favorite/tag/queue UI stay
  /// coherent. Pure state update: the handler keeps streaming the current track
  /// uninterrupted; the local file takes over on the next load.
  Future<void> swapReconciledSong(int oldId, int newId) async {
    if (oldId == newId) return;
    final result = await _repository.getSongById(newId);
    final newSong = result.fold((_) => null, (s) => s);
    if (newSong == null || isClosed) return;

    _slotLookupCache[newSong.id] = newSong;
    _slotLookupCache.remove(oldId);
    _queueMutex.protect(() async {
      _queueSlots.updateAll((slot, data) {
        if (!data.songIds.contains(oldId)) return data;
        return _QueueSlotData(
          songIds: data.songIds.map((id) => id == oldId ? newId : id).toList(),
          currentIndex: data.currentIndex,
          position: data.position,
          speed: data.speed,
        );
      });
    });
    _debouncedPersistQueueSlots();

    if (state.queue.any((s) => s.id == oldId)) {
      _queueVersion++;
      safeEmit(state.copyWith(
        queue: state.queue.map((s) => s.id == oldId ? newSong : s).toList(),
        currentSong:
            state.currentSong?.id == oldId ? newSong : state.currentSong,
      ));
      _updateWidgetThrottled(force: true);
    }

    try {
      _audioHandler.swapReconciledSong(oldId, newSong);
    } catch (_) {}
  }

  // Requires: provided by the composing class (same library).
  PulsrAudioHandler get _audioHandler;

  // Requires: provided by the composing class (same library).
  void _debouncedPersistQueueSlots();

  // Requires: provided by the composing class (same library).
  bool _isSameTrack(SongsTableData? a, SongsTableData? b);

  // Requires: provided by the composing class (same library).
  bool get _isSwitchingSlot;
  set _isSwitchingSlot(bool value);

  // Requires: provided by the composing class (same library).
  Future<void> _loadLyricsForSong(SongsTableData song);

  // Requires: provided by the composing class (same library).
  Map<int, _QueueSlotData> get _queueSlots;

  // Requires: provided by the composing class (same library).
  Mutex get _queueMutex;

  // Requires: provided by the composing class (same library).
  Map<int, SongsTableData> get _slotLookupCache;

  // Requires: provided by the composing class (same library).
  void _setQueueSlot(
    int slot, {
    required List<SongsTableData> songs,
    required int currentIndex,
    required Duration position,
    required double speed,
  });

  // Requires: provided by the composing class (same library).
  int get _queueVersion;
  set _queueVersion(int value);

  // Requires: provided by the composing class (same library).
  IMusicRepository get _repository;

  // Requires: provided by the composing class (same library).
  void _updateWidgetThrottled({bool force = false});

  // Requires: provided by the composing class (same library).
  Future<void> playSong(SongsTableData song, {List<SongsTableData>? queue, Duration? initialPosition, bool openPlayerIfPlaying = true});
}
