// lib/features/player/cubit/controllers/player_queue_slots.dart
part of 'player_queue_controller.dart';

/// Upper bound on the slot lookup cache. Three slots of
/// [PlayerQueueController.maxQueueSize] plus reconciled replacements fit
/// comfortably; the cap only guards against unbounded growth from long
/// sessions, evicting the least-recently-written songs first.
const int _maxSlotLookupCacheEntries = 4096;

/// Caches [songs] for slot hydration, marking each as the most recently written
/// entry (LRU-ish) and evicting the oldest beyond [_maxSlotLookupCacheEntries].
void _cacheSlotSongs(
  Map<int, SongsTableData> cache,
  List<SongsTableData> songs,
) {
  for (final s in songs) {
    cache.remove(s.id);
    cache[s.id] = s;
  }
  final excess = cache.length - _maxSlotLookupCacheEntries;
  if (excess > 0) {
    final oldest = cache.keys.take(excess).toList(growable: false);
    for (final key in oldest) {
      cache.remove(key);
    }
  }
}

extension PlayerQueueSlotsExtension on PlayerQueueController {
  void debouncedPersistQueueSlots() {
    _persistQueueDebounce?.cancel();
    _persistQueueDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(persistQueueSlotsNow());
    });
  }

  Future<void> persistQueueSlotsNow() async {
    _persistQueueDebounce?.cancel();
    _persistQueueDebounce = null;
    if (_isClosed()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = QueueSlotCodec.encodeDocument(
        {
          for (final entry in _queueSlots.entries)
            entry.key: (
              songs: entry.value.songsFrom(_slotLookupCache),
              currentIndex: entry.value.currentIndex,
              position: entry.value.position,
              speed: entry.value.speed,
            ),
        },
        _getState().activeQueueSlot,
      );
      final encoded = await compute(jsonEncode, data);
      await prefs.setString(PrefsKeys.queueSlots, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist queue slots',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed() && _getState().errorMessage == null) {
        final s = _getState();
        _emit(s.copyWith(
          playback: s.playback.copyWith(errorMessage: 'Failed to save queue'),
        ));
      }
    }
  }

  Future<void> restoreQueueSlots() =>
      _queueMutex.protect(_restoreQueueSlotsLocked);

  Future<void> _restoreQueueSlotsLocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.queueSlots);
      if (raw == null) return;
      final data =
          QueueSlotCodec.decodeDocument(await compute(jsonDecode, raw));
      if (data == null) return;
      for (final key in data.keys) {
        final slotIndex = QueueSlotCodec.slotIndexForKey(key);
        if (slotIndex == null) continue;
        final rawSlot = data[key];
        if (rawSlot is! Map) continue;
        final decoded = QueueSlotCodec.decodeSlot(
            Map<String, dynamic>.from(rawSlot),
            PlayerQueueController.maxQueueSize);
        if (decoded == null) continue;
        try {
          final songsResult = await _repository.getSongsByIds(decoded.songIds);
          final songsMap = {
            for (final s
                in songsResult.fold((_) => <SongsTableData>[], (r) => r))
              s.id: s
          };
          final songs = QueueSlotCodec.mergeInPersistedOrder(
              decoded.songIds, songsMap, decoded.onlineSongsById);
          if (songs.isEmpty) continue;
          // Cold-start race guard: if playback already began during this async
          // restore window, do not overwrite the live active slot (the other,
          // inactive slots are still restored).
          final current = _getState();
          if (slotIndex == current.activeQueueSlot &&
              current.queue.isNotEmpty) {
            continue;
          }
          // Re-anchor currentIndex by identity: mergeInPersistedOrder drops ids
          // that no longer resolve, shifting positions, so a raw clamp of the
          // persisted index would point at the wrong track.
          final decodedIndex = decoded.currentIndex;
          final anchorId =
              (decodedIndex >= 0 && decodedIndex < decoded.songIds.length)
                  ? decoded.songIds[decodedIndex]
                  : null;
          var restoredIndex =
              anchorId != null ? songs.indexWhere((s) => s.id == anchorId) : -1;
          if (restoredIndex == -1) {
            restoredIndex = QueueSlotCodec.clampCurrentIndex(
                decoded.currentIndex, songs.length);
          }
          setQueueSlot(
            slotIndex,
            songs: songs,
            currentIndex: restoredIndex,
            position: QueueSlotCodec.clampPosition(decoded.positionMs),
            speed: QueueSlotCodec.clampSpeed(decoded.speed),
          );
        } catch (e, st) {
          ErrorLogger.log('Failed to restore queue slot $slotIndex',
              error: e, stackTrace: st, category: 'PlayerQueueController');
        }
      }
      if (!_isClosed()) {
        final restoredSlot = QueueSlotCodec.activeSlotFrom(data['activeSlot']);
        // Don't flip the active slot if a session already started during the
        // restore window (cold-start race): that would swap the live queue out
        // for stale restored data.
        if (restoredSlot != null && _getState().queue.isEmpty) {
          final s = _getState();
          _emit(s.copyWith(
            queueSlice: s.queueSlice.copyWith(activeQueueSlot: restoredSlot),
          ));
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore queue slots',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    }
  }

  Future<void> clearQueue() => _queueMutex.protect(_clearQueueLocked);

  Future<void> _clearQueueLocked() async {
    final state = _getState();
    final current = state.currentSong;
    final retained = current != null ? [current] : <SongsTableData>[];
    setQueueSlot(
      state.activeQueueSlot,
      songs: List.from(retained),
      currentIndex: 0,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(queue: retained, currentIndex: 0),
    ));
    try {
      await _audioHandler.clearQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed to clear queue in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    }
  }

  Future<void> restoreQueue(
          List<SongsTableData> previousQueue, int previousIndex) =>
      _queueMutex.protect(
          () async => _restoreQueueLocked(previousQueue, previousIndex));

  void _restoreQueueLocked(
      List<SongsTableData> previousQueue, int previousIndex) {
    // Empty queue is a safe no-op: `clamp(0, previousQueue.length - 1)` would
    // be clamp(0, -1) and throw ArgumentError.
    if (previousQueue.isEmpty) return;
    final state = _getState();
    final validIndex = previousIndex.clamp(0, previousQueue.length - 1);
    setQueueSlot(
      state.activeQueueSlot,
      songs: List.from(previousQueue),
      currentIndex: validIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: previousQueue,
        currentIndex: validIndex,
      ),
    ));
    _invalidateQueueSyncResolution();
    _audioHandler
        .loadQueue(
      previousQueue,
      initialIndex: validIndex,
      initialPosition: state.position,
      autoPlay: state.isPlaying,
    )
        .catchError((Object e, StackTrace st) {
      ErrorLogger.log('Failed to restore queue in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    });
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _queueMutex.protect(() => _reorderQueueLocked(oldIndex, newIndex));

  Future<void> _reorderQueueLocked(int oldIndex, int newIndex) async {
    final state = _getState();
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex >= state.queue.length) {
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);

    int newCurrentIndex = state.currentIndex;
    if (state.currentIndex == oldIndex) {
      newCurrentIndex = newIndex;
    } else if (oldIndex < state.currentIndex &&
        newIndex >= state.currentIndex) {
      newCurrentIndex = state.currentIndex - 1;
    } else if (oldIndex > state.currentIndex &&
        newIndex <= state.currentIndex) {
      newCurrentIndex = state.currentIndex + 1;
    }

    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: newCurrentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: updatedQueue,
        currentIndex: newCurrentIndex,
      ),
    ));
    _invalidateQueueSyncResolution();

    try {
      await _audioHandler.reorderQueue(oldIndex, newIndex);
    } catch (e, st) {
      // H-08: Roll back queue and slot state if audio handler reorder throws
      ErrorLogger.log('Failed to reorder queue in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      final current = _getState();
      setQueueSlot(
        state.activeQueueSlot,
        songs: state.queue,
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      debouncedPersistQueueSlots();
      _bumpQueueVersion();
      _emit(current.copyWith(
        queueSlice: current.queueSlice.copyWith(
          queue: state.queue,
          currentIndex: state.currentIndex,
        ),
        playback: current.playback.copyWith(
          errorMessage: 'Failed to reorder queue',
        ),
      ));
    }
  }

  Future<void> removeQueueItem(int index) =>
      _queueMutex.protect(() => _removeQueueItemLocked(index));

  Future<void> _removeQueueItemLocked(int index) async {
    final state = _getState();
    if (index < 0 || index >= state.queue.length) return;
    if (state.queue.length <= 1) {
      setQueueSlot(
        state.activeQueueSlot,
        songs: const [],
        currentIndex: 0,
        position: Duration.zero,
        speed: state.playbackSpeed,
      );
      debouncedPersistQueueSlots();
      _bumpQueueVersion();
      _emit(state.copyWith(
        queueSlice: state.queueSlice.copyWith(queue: const [], currentIndex: 0),
        playback: state.playback.copyWith(
          currentSong: null,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
        ),
      ));
      _invalidateQueueSyncResolution();
      try {
        await _audioHandler.clearQueue();
      } catch (e, st) {
        ErrorLogger.log('Failed to clear queue in audio handler',
            error: e, stackTrace: st, category: 'PlayerQueueController');
      }
      return;
    }

    final removingCurrent = index == state.currentIndex;
    final updatedQueue = List<SongsTableData>.from(state.queue)
      ..removeAt(index);
    int newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex = state.currentIndex - 1;
    } else if (removingCurrent) {
      newIndex = index.clamp(0, updatedQueue.length - 1);
    }

    final nextSong = (removingCurrent && updatedQueue.isNotEmpty)
        ? updatedQueue[newIndex]
        : state.currentSong;

    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: newIndex,
      position: removingCurrent ? Duration.zero : state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    final playback = removingCurrent
        ? state.playback.copyWith(
            currentSong: nextSong,
            position: Duration.zero,
            duration: nextSong != null
                ? Duration(milliseconds: nextSong.durationMs)
                : Duration.zero,
          )
        : state.playback;
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: updatedQueue,
        currentIndex: newIndex,
      ),
      playback: playback,
    ));
    _invalidateQueueSyncResolution();

    try {
      await _audioHandler.removeQueueItemAt(index);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove queue item in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          queueSlice: s.queueSlice.copyWith(
            queue: state.queue,
            currentIndex: state.currentIndex,
          ),
          playback: state.playback,
        ));
      }
    }
  }

  Future<void> switchQueueSlot(int slot) =>
      _queueMutex.protect(() => _switchQueueSlotLocked(slot));

  Future<void> _switchQueueSlotLocked(int slot) async {
    if (_isSwitchingSlot || _isClosed()) return;
    _isSwitchingSlot = true;
    try {
      final state = _getState();
      if (slot == state.activeQueueSlot) return;
      final wasPlaying = state.isPlaying;

      setQueueSlot(
        state.activeQueueSlot,
        songs: List.from(state.queue),
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      final targetSlot = _queueSlots[slot] ??
          const QueueSlotData(
              songIds: [],
              currentIndex: 0,
              position: Duration.zero,
              speed: 1.0);
      final targetSongs = targetSlot.songsFrom(_slotLookupCache);
      final targetOriginalSong = (targetSlot.currentIndex >= 0 &&
              targetSlot.currentIndex < targetSongs.length)
          ? targetSongs[targetSlot.currentIndex]
          : null;
      final validSongs = targetSongs.where((s) => !s.isMissing).toList();

      debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        _emit(state.copyWith(
          playback:
              state.playback.copyWith(errorMessage: 'Queue slot is empty'),
        ));
        return;
      }

      _bumpQueueVersion();
      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx =
            validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
      }
      if (safeIdx == -1) {
        safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      }
      final song = validSongs[safeIdx];
      _emit(state.copyWith(
        queueSlice: state.queueSlice.copyWith(
          activeQueueSlot: slot,
          queue: validSongs,
          currentIndex: safeIdx,
        ),
        playback: state.playback.copyWith(
          currentSong: song,
          duration: Duration(milliseconds: song.durationMs),
          position: targetSlot.position,
          playbackSpeed: targetSlot.speed,
        ),
      ));
      _invalidateQueueSyncResolution();
      try {
        await _audioHandler.setSpeed(targetSlot.speed);
        await _audioHandler.loadQueue(
          validSongs,
          initialIndex: safeIdx,
          initialPosition: targetSlot.position,
          autoPlay: wasPlaying,
        );
        _loadLyrics(song);
        _updateWidgetThrottled(force: true);
      } catch (e, st) {
        ErrorLogger.log('Failed to switch queue slot $slot',
            error: e, stackTrace: st, category: 'PlayerQueueController');
        if (!_isClosed()) {
          _bumpQueueVersion();
          _emit(state.copyWith(
            playback: state.playback
                .copyWith(errorMessage: 'Failed to switch queue slot'),
          ));
          _invalidateQueueSyncResolution();
          try {
            await _audioHandler.setSpeed(state.playbackSpeed);
          } catch (_) {}
        }
      }
    } finally {
      _isSwitchingSlot = false;
    }
  }

  Future<void> swapReconciledSong(
      Object? oldSongOrId, Object? newSongOrId) async {
    final int? oldId = oldSongOrId is SongsTableData
        ? oldSongOrId.id
        : (oldSongOrId is int ? oldSongOrId : null);
    if (oldId == null) return;
    SongsTableData? newSong;
    if (newSongOrId is SongsTableData) {
      newSong = newSongOrId;
    } else if (newSongOrId is int) {
      final res = await _repository.getSongById(newSongOrId);
      newSong = res.fold((_) => null, (s) => s);
    }
    final safeNewSong = newSong;
    if (safeNewSong == null || oldId == safeNewSong.id) return;

    final state = _getState();
    if (state.queue.any((s) => s.id == safeNewSong.id)) return;

    _slotLookupCache[safeNewSong.id] = safeNewSong;
    _slotLookupCache.remove(oldId);
    await _queueMutex.protect(() async {
      _queueSlots.updateAll((slot, data) {
        if (!data.songIds.contains(oldId)) return data;
        return QueueSlotData(
          songIds: data.songIds
              .map((id) => id == oldId ? safeNewSong.id : id)
              .toList(),
          currentIndex: data.currentIndex,
          position: data.position,
          speed: data.speed,
        );
      });
    });
    debouncedPersistQueueSlots();

    if (state.queue.any((s) => s.id == oldId)) {
      _bumpQueueVersion();
      _emit(state.copyWith(
        queueSlice: state.queueSlice.copyWith(
          queue:
              state.queue.map((s) => s.id == oldId ? safeNewSong : s).toList(),
        ),
        playback: state.playback.copyWith(
          currentSong:
              state.currentSong?.id == oldId ? safeNewSong : state.currentSong,
        ),
      ));
      _updateWidgetThrottled(force: true);
    }

    try {
      _audioHandler.swapReconciledSong(oldId, safeNewSong);
    } catch (e, st) {
      ErrorLogger.log('Failed to swap reconciled song in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    }
  }

  Future<void> addToQueue(SongsTableData song) =>
      _queueMutex.protect(() => _addToQueueLocked(song));

  Future<void> _addToQueueLocked(SongsTableData song) async {
    final state = _getState();
    final existingIdx = state.queue.indexWhere((s) => _isSameTrack(s, song));
    if (existingIdx != -1) {
      // Reordering an already-present song doesn't grow the queue, so handle it
      // before the capacity check — which would otherwise wrongly block it at
      // exactly-full.
      if (existingIdx == state.currentIndex ||
          existingIdx == state.queue.length - 1) {
        return;
      }
      // Reorder existing song to end instead of enqueuing duplicate into audio handler
      await _reorderQueueLocked(existingIdx, state.queue.length - 1);
      return;
    }
    if (state.queue.length >= PlayerQueueController.maxQueueSize) {
      _emit(state.copyWith(
        playback: state.playback.copyWith(
            errorMessage:
                'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
      ));
      return;
    }

    try {
      await _audioHandler.addToQueueEnd(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to add to queue',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          playback:
              s.playback.copyWith(errorMessage: 'Failed to add ${song.title}'),
        ));
      }
      return;
    }
    // Re-fetch state after the await: a concurrent mutation is impossible under
    // the mutex, but playback may have advanced, so never append to the stale
    // queue snapshot captured before `addToQueueEnd`.
    final s = _getState();
    final updatedQueue = [...s.queue, song];
    setQueueSlot(
      s.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: s.currentIndex,
      position: s.position,
      speed: s.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(s.copyWith(
      queueSlice: s.queueSlice.copyWith(queue: updatedQueue),
    ));
    _invalidateQueueSyncResolution();
    _updateWidgetThrottled();
  }

  Future<void> playNext(SongsTableData song) =>
      _queueMutex.protect(() => _playNextLocked(song));

  Future<void> _playNextLocked(SongsTableData song) async {
    final state = _getState();
    if (state.queue.isEmpty) {
      await _addToQueueLocked(song);
      return;
    }
    final existingIdx = state.queue.indexWhere((s) => _isSameTrack(s, song));
    final targetSlot = (state.currentIndex + 1).clamp(0, state.queue.length);
    if (existingIdx != -1) {
      // Reordering an already-present song doesn't grow the queue, so handle it
      // before the capacity check — which would otherwise wrongly block it at
      // exactly-full.
      if (existingIdx == state.currentIndex || existingIdx == targetSlot) {
        return;
      }
      final adjustedTarget =
          targetSlot > existingIdx ? targetSlot - 1 : targetSlot;
      await _reorderQueueLocked(existingIdx, adjustedTarget);
      return;
    }
    if (state.queue.length >= PlayerQueueController.maxQueueSize) {
      _emit(state.copyWith(
        playback: state.playback.copyWith(
            errorMessage:
                'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
      ));
      return;
    }

    try {
      await _audioHandler.insertNextInQueue(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to insert next in queue',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          playback:
              s.playback.copyWith(errorMessage: 'Failed to add ${song.title}'),
        ));
      }
      return;
    }
    // Re-fetch state after the await so the insert lands on the fresh playback
    // snapshot (and after the current track) instead of the stale queue.
    final s = _getState();
    final insertAt = (s.currentIndex + 1).clamp(0, s.queue.length);
    final updatedQueue = List<SongsTableData>.from(s.queue);
    updatedQueue.insert(insertAt, song);
    setQueueSlot(
      s.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: s.currentIndex,
      position: s.position,
      speed: s.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(s.copyWith(
      queueSlice: s.queueSlice.copyWith(queue: updatedQueue),
    ));
    _invalidateQueueSyncResolution();
  }

  Future<void> addAllToQueue(List<SongsTableData> songs) =>
      _queueMutex.protect(() => _addAllToQueueLocked(songs));

  Future<void> _addAllToQueueLocked(List<SongsTableData> songs) async {
    final state = _getState();
    if (songs.isEmpty || _isClosed()) return;
    final room = PlayerQueueController.maxQueueSize - state.queue.length;
    if (room <= 0) {
      _emit(state.copyWith(
        playback: state.playback.copyWith(
            errorMessage:
                'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
      ));
      return;
    }
    final seen = <int>{...state.queue.map((q) => q.id)};
    final toAdd = <SongsTableData>[];
    for (final s in songs) {
      if (!seen.contains(s.id)) {
        seen.add(s.id);
        toAdd.add(s);
        if (toAdd.length == room) break;
      }
    }
    if (toAdd.isEmpty) {
      if (state.queue.length >= PlayerQueueController.maxQueueSize) {
        _emit(state.copyWith(
          playback: state.playback.copyWith(
              errorMessage:
                  'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
        ));
      }
      return;
    }
    final added = <SongsTableData>[];
    for (final song in toAdd) {
      try {
        await _audioHandler.addToQueueEnd(song);
        added.add(song);
      } catch (e, st) {
        ErrorLogger.log('Failed to add batch song ${song.title}',
            error: e, stackTrace: st, category: 'PlayerQueueController');
        break;
      }
    }
    if (added.isEmpty || _isClosed()) {
      if (toAdd.isNotEmpty && !_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
          playback:
              s.playback.copyWith(errorMessage: 'Failed to add songs to queue'),
        ));
      }
      return;
    }
    // Re-fetch state after the awaits so the batch lands on the fresh queue.
    final s = _getState();
    final updatedQueue = [...s.queue, ...added];
    setQueueSlot(
      s.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: s.currentIndex,
      position: s.position,
      speed: s.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(s.copyWith(
      queueSlice: s.queueSlice.copyWith(queue: updatedQueue),
      playback: s.playback.copyWith(
        errorMessage: added.length < toAdd.length
            ? 'Added ${added.length} of ${toAdd.length} songs'
            : null,
      ),
    ));
    _invalidateQueueSyncResolution();
  }

  void _findNextLocalMatch(
    SongsTableData currentSong,
    List<SongsTableData> queue,
    int currentIndex,
    int capturedSwapGen,
    int capturedResolutionGen,
  ) {
    if (currentIndex + 1 >= queue.length) return;
    final nextTrack = queue[currentIndex + 1];
    if (nextTrack.source != SongSource.youtube) return;

    _repository
        .findMatchingLocalSong(
      remoteId: nextTrack.remoteId,
      title: nextTrack.title,
      artist: nextTrack.artist,
    )
        .then((res) async {
      final match = res.fold((_) => null, (s) => s);
      if (match != null &&
          _localMatchSwapGuard.isValid(capturedSwapGen) &&
          _mediaItemResolutionGuard.isValid(capturedResolutionGen) &&
          !_isClosed()) {
        await swapReconciledSong(nextTrack.id, match);
      }
    }).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Find next local match failed',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    });
  }
}
