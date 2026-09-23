// lib/features/player/cubit/controllers/player_queue_slots.dart
part of 'player_queue_controller.dart';

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

  Future<void> restoreQueueSlots() async {
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
            Map<String, dynamic>.from(rawSlot), PlayerQueueController.maxQueueSize);
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
          setQueueSlot(
            slotIndex,
            songs: songs,
            currentIndex: QueueSlotCodec.clampCurrentIndex(
                decoded.currentIndex, songs.length),
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
        if (restoredSlot != null) {
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

  Future<void> clearQueue() async {
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

  void restoreQueue(List<SongsTableData> previousQueue, int previousIndex) {
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

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
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
    } else if (oldIndex < state.currentIndex && newIndex >= state.currentIndex) {
      newCurrentIndex = state.currentIndex - 1;
    } else if (oldIndex > state.currentIndex && newIndex <= state.currentIndex) {
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

    try {
      await _audioHandler.reorderQueue(oldIndex, newIndex);
    } catch (e, st) {
      ErrorLogger.log('Failed to reorder queue in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    }
  }

  Future<void> removeQueueItem(int index) async {
    final state = _getState();
    if (index < 0 || index >= state.queue.length) return;
    if (state.queue.length <= 1) {
      await clearQueue();
      return;
    }

    final updatedQueue = List<SongsTableData>.from(state.queue)..removeAt(index);
    int newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex = state.currentIndex - 1;
    } else if (index == state.currentIndex) {
      newIndex = index.clamp(0, updatedQueue.length - 1);
    }

    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: newIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: updatedQueue,
        currentIndex: newIndex,
      ),
    ));

    try {
      await _audioHandler.removeQueueItemAt(index);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove queue item in audio handler',
          error: e, stackTrace: st, category: 'PlayerQueueController');
    }
  }

  Future<void> switchQueueSlot(int slot) async {
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
              songIds: [], currentIndex: 0, position: Duration.zero, speed: 1.0);
      final targetSongs = targetSlot.songsFrom(_slotLookupCache);
      final targetOriginalSong = (targetSlot.currentIndex >= 0 &&
              targetSlot.currentIndex < targetSongs.length)
          ? targetSongs[targetSlot.currentIndex]
          : null;
      final validSongs = targetSongs.where((s) => !s.isMissing).toList();

      debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        _emit(state.copyWith(
          playback: state.playback.copyWith(errorMessage: 'Queue slot is empty'),
        ));
        return;
      }

      _bumpQueueVersion();
      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx = validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
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
      try {
        await _audioHandler.setSpeed(targetSlot.speed);
        await _audioHandler.loadQueue(
          validSongs,
          initialIndex: safeIdx,
          initialPosition: targetSlot.position,
          autoPlay: wasPlaying,
        );
        _loadLyrics(song);
      } catch (e, st) {
        ErrorLogger.log('Failed to switch queue slot $slot',
            error: e, stackTrace: st, category: 'PlayerQueueController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
            playback: s.playback.copyWith(errorMessage: 'Failed to switch queue slot'),
          ));
        }
      }
    } finally {
      _isSwitchingSlot = false;
    }
  }

  Future<void> swapReconciledSong(dynamic oldSongOrId, dynamic newSongOrId) async {
    final int oldId = oldSongOrId is SongsTableData ? oldSongOrId.id : (oldSongOrId as int);
    SongsTableData? newSong;
    if (newSongOrId is SongsTableData) {
      newSong = newSongOrId;
    } else if (newSongOrId is int) {
      final res = await _repository.getSongById(newSongOrId);
      newSong = res.fold((_) => null, (s) => s);
    }
    if (newSong == null || oldId == newSong.id) return;

    _slotLookupCache[newSong.id] = newSong;
    _slotLookupCache.remove(oldId);
    await _queueMutex.protect(() async {
      _queueSlots.updateAll((slot, data) {
        if (!data.songIds.contains(oldId)) return data;
        return QueueSlotData(
          songIds: data.songIds.map((id) => id == oldId ? newSong!.id : id).toList(),
          currentIndex: data.currentIndex,
          position: data.position,
          speed: data.speed,
        );
      });
    });
    debouncedPersistQueueSlots();

    final state = _getState();
    if (state.queue.any((s) => s.id == oldId)) {
      _bumpQueueVersion();
      _emit(state.copyWith(
        queueSlice: state.queueSlice.copyWith(
          queue: state.queue.map((s) => s.id == oldId ? newSong! : s).toList(),
        ),
        playback: state.playback.copyWith(
          currentSong:
              state.currentSong?.id == oldId ? newSong : state.currentSong,
        ),
      ));
      _updateWidgetThrottled(force: true);
    }

    try {
      _audioHandler.swapReconciledSong(oldId, newSong);
    } catch (_) {}
  }

  Future<void> addToQueue(SongsTableData song) async {
    final state = _getState();
    if (state.queue.length >= PlayerQueueController.maxQueueSize) {
      _emit(state.copyWith(
        playback: state.playback.copyWith(
            errorMessage:
                'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
      ));
      return;
    }
    final existingIdx = state.queue.indexWhere((s) => _isSameTrack(s, song));
    if (existingIdx != -1) {
      if (existingIdx == state.currentIndex ||
          existingIdx == state.queue.length - 1) {
        return;
      }
      // Reorder existing song to end instead of enqueuing duplicate into audio handler
      await reorderQueue(existingIdx, state.queue.length - 1);
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
    final updatedQueue = [...state.queue, song];
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
    ));
    _updateWidgetThrottled();
  }

  Future<void> playNext(SongsTableData song) async {
    final state = _getState();
    if (state.queue.length >= PlayerQueueController.maxQueueSize) {
      _emit(state.copyWith(
        playback: state.playback.copyWith(
            errorMessage:
                'Queue full (${PlayerQueueController.maxQueueSize}) — cannot add more'),
      ));
      return;
    }
    final existingIdx = state.queue.indexWhere((s) => _isSameTrack(s, song));
    final targetSlot = (state.currentIndex + 1).clamp(0, state.queue.length);
    if (existingIdx != -1) {
      if (existingIdx == state.currentIndex || existingIdx == targetSlot) {
        return;
      }
      final adjustedTarget =
          targetSlot > existingIdx ? targetSlot - 1 : targetSlot;
      await reorderQueue(existingIdx, adjustedTarget);
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
    final updatedQueue = List<SongsTableData>.from(state.queue);
    updatedQueue.insert(targetSlot, song);
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
    ));
  }

  Future<void> addAllToQueue(List<SongsTableData> songs) async {
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
    final toAdd = songs
        .where((s) => !state.queue.any((q) => _isSameTrack(q, s)))
        .take(room)
        .toList();
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
    if (added.isEmpty || _isClosed()) return;
    final updatedQueue = [...state.queue, ...added];
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    debouncedPersistQueueSlots();
    _bumpQueueVersion();
    final s = _getState();
    _emit(s.copyWith(
      queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
      playback: s.playback.copyWith(
        errorMessage: added.length < toAdd.length
            ? 'Added ${added.length} of ${toAdd.length} songs'
            : null,
      ),
    ));
  }
}
