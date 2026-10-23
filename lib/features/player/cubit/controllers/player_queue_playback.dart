// lib/features/player/cubit/controllers/player_queue_playback.dart
part of 'player_queue_controller.dart';

/// Track selection and engine queue loading (including the load-failure
/// rollback). Split out of player_queue_controller.dart (pure code movement, no
/// behaviour change) to keep that file within the controller size budget.
extension PlayerQueuePlaybackExtension on PlayerQueueController {
  Future<void> playSong(
    SongsTableData song, {
    List<SongsTableData>? queue,
    Duration? initialPosition,
    bool openPlayerIfPlaying = true,
    bool preservePlaybackState = false,
  }) =>
      _queueMutex.protect(() => _playSongLocked(
            song,
            queue: queue,
            initialPosition: initialPosition,
            openPlayerIfPlaying: openPlayerIfPlaying,
            preservePlaybackState: preservePlaybackState,
          ));

  /// [preservePlaybackState] — when true (queue shuffle / history jump) the
  /// engine load keeps the current play/pause state instead of auto-playing.
  Future<void> _playSongLocked(
    SongsTableData song, {
    List<SongsTableData>? queue,
    Duration? initialPosition,
    bool openPlayerIfPlaying = true,
    bool preservePlaybackState = false,
  }) async {
    _cancelPendingSeek();
    final state = _getState();
    if (openPlayerIfPlaying &&
        initialPosition == null &&
        _isSameTrack(state.currentSong, song)) {
      // A supplied queue is a request to replace/reorder the current queue (e.g.
      // the Queue screen "Shuffle" action passes the current song with a freshly
      // shuffled queue). Only take the plain resume shortcut when the queue is
      // unchanged; otherwise fall through so the new order is actually applied.
      final queueUnchanged = queue == null ||
          listEquals(
            queue.map((s) => s.id).toList(growable: false),
            state.queue.map((s) => s.id).toList(growable: false),
          );
      if (queueUnchanged) {
        _emit(state.copyWith(
            playback: state.playback.copyWith(isExpanded: true)));
        if (!state.isPlaying && !preservePlaybackState) {
          try {
            await _audioHandler.play();
          } catch (e, st) {
            ErrorLogger.log('Resume of current song failed',
                error: e, stackTrace: st, category: 'PlayerQueueController');
            if (!_isClosed()) {
              final s = _getState();
              _emit(s.copyWith(
                  playback: s.playback
                      .copyWith(errorMessage: 'Failed to play ${song.title}')));
            }
          }
        }
        return;
      }
    }

    final videoIdForLatency = song.remoteId ?? song.id.toString();
    try {
      _latencyTracker?.start(videoId: videoIdForLatency);
      _latencyTracker?.markStage(PlaybackStage.tap);
    } catch (_) {}

    try {
      _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
    } catch (_) {}

    if ((song.sampleRate == null || song.sampleRate! <= 0) &&
        song.path.isNotEmpty &&
        !song.path.startsWith('http') &&
        !song.path.startsWith('ytmusic://')) {
      try {
        final scanner = _mediaScannerService ??
            (getIt.isRegistered<MediaScannerService>()
                ? getIt<MediaScannerService>()
                : null);
        if (scanner != null) {
          unawaited(scanner.enrichAudioQuality(song.id, song.path));
        }
      } catch (e, st) {
        ErrorLogger.log('enrichAudioQuality failed in playTrack',
            error: e, stackTrace: st, category: 'PlayerQueuePlayback');
      }
    }

    final capturedGen = _mediaItemResolutionGuard.next();
    final capturedSwapGen = _localMatchSwapGuard.next();
    _mediaItemGuard.next();

    final rawQueue = queue != null ? List<SongsTableData>.from(queue) : [song];
    var targetIndex = rawQueue.indexWhere((s) => _isSameTrack(s, song));
    if (targetIndex == -1) {
      targetIndex = 0;
      rawQueue.insert(0, song);
    }

    List<SongsTableData> effectiveQueue;
    int effectiveIndex;

    if (rawQueue.length > PlayerQueueController.maxQueueSize) {
      final halfWindow = PlayerQueueController.maxQueueSize ~/ 2;
      var start = targetIndex - halfWindow;
      if (start < 0) start = 0;
      if (start + PlayerQueueController.maxQueueSize > rawQueue.length) {
        start = (rawQueue.length - PlayerQueueController.maxQueueSize)
            .clamp(0, rawQueue.length);
      }
      effectiveQueue =
          rawQueue.sublist(start, start + PlayerQueueController.maxQueueSize);
      effectiveIndex = targetIndex - start;
      final headDropped = start > 0;
      final tailDropped =
          start + PlayerQueueController.maxQueueSize < rawQueue.length;
      final dropMsg = (headDropped && tailDropped)
          ? 'head and tail dropped'
          : (headDropped ? 'head dropped' : 'tail dropped');
      ErrorLogger.log(
        'Queue truncated to ${PlayerQueueController.maxQueueSize} '
        '(was ${rawQueue.length}) — $dropMsg',
        category: 'PlayerQueueController',
      );
    } else {
      effectiveQueue = rawQueue;
      effectiveIndex = targetIndex;
    }

    final isSameSong = _isSameTrack(state.currentSong, song);
    // When the same track keeps playing but its queue is being replaced (e.g.
    // Shuffle), preserve the current position instead of restarting from zero.
    final startPos = initialPosition ??
        ((queue != null && isSameSong) ? state.position : Duration.zero);
    final prevSlot = _queueSlots[state.activeQueueSlot];
    final prevQueue = state.queue;
    final prevIndex = state.currentIndex;
    final prevTrackTiers = state.trackTiers;
    final prevSong = state.currentSong;
    final prevPosition = state.position;
    final prevDuration = state.duration;
    final prevLyrics = state.lyrics;
    final prevLyricsSource = state.lyricsSource;

    final Map<int, QueueTier> nextTrackTiers;
    if (isSameSong && preservePlaybackState && queue != null) {
      final validIds = effectiveQueue.map((s) => s.id).toSet();
      nextTrackTiers = {
        for (final entry in state.trackTiers.entries)
          if (validIds.contains(entry.key)) entry.key: entry.value,
        for (final s in effectiveQueue)
          if (s.isAutoplay && !state.trackTiers.containsKey(s.id))
            s.id: QueueTier.autoplay,
      };
    } else {
      nextTrackTiers = <int, QueueTier>{};
      for (final s in effectiveQueue) {
        if (s.hasExplicitAutoplayFlag) {
          nextTrackTiers[s.id] = QueueTier.autoplay;
        } else {
          s.isAutoplay = false;
        }
      }
    }

    setQueueSlot(
      state.activeQueueSlot,
      songs: List.from(effectiveQueue),
      currentIndex: effectiveIndex,
      position: startPos,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();

    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: List<SongsTableData>.unmodifiable(effectiveQueue),
        currentIndex: effectiveIndex,
        trackTiers: nextTrackTiers,
      ),
      playback: state.playback.copyWith(
        currentSong: song,
        duration: (song.durationMs <= 0 && isSameSong)
            ? state.duration
            : Duration(milliseconds: song.durationMs),
        position: startPos,
        // BUG-3 FIX: do NOT optimistically set isPlaying=true before loadQueue
        // is called. There is an async gap between this emit and the loadQueue
        // call below; if the cubit closes or the load fails in that window the
        // state would permanently claim the track is playing. The playbackState
        // observer in PlayerCubit flips isPlaying=true once the engine confirms
        // playback. Keep the previous isPlaying value here so the UI does not
        // flicker to "playing" and immediately back to "paused" on a fast navigation.
        isPlaying: state.isPlaying,
        errorMessage: null,
      ),
      lyricsSlice: state.lyricsSlice.copyWith(
        lyrics: isSameSong ? state.lyrics : const [],
        lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
      ),
    ));

    _updateWidgetThrottled(force: true);
    _invalidateQueueSyncResolution();

    try {
      await _audioHandler.loadQueue(
        effectiveQueue,
        initialIndex: effectiveIndex,
        initialPosition: startPos,
        // AUDIT-FIX: shuffle / history-jump reloads must not start playback
        // while the player is paused.
        autoPlay: preservePlaybackState ? state.isPlaying : true,
      );
      if (_mediaItemResolutionGuard.isValid(capturedGen) && !_isClosed()) {
        _loadLyrics(song);
      }
    } catch (e, st) {
      ErrorLogger.log('Load queue failed for song ${song.id}',
          error: e, stackTrace: st, category: 'PlayerQueueController');

      // C3 FIX: Rollback and invalidate parallel guards so late resolution/match futures cannot re-apply failed queue
      _mediaItemResolutionGuard.invalidate();
      _localMatchSwapGuard.invalidate();
      _lyricsGuard.invalidate();

      assert(!_mediaItemResolutionGuard.isValid(capturedGen),
          'Resolution guard must be invalid after rollback');

      if (!_isClosed()) {
        // BUG-4 FIX, round 2: re-read the LIVE state and only roll back the
        // failed selection when it is still the active one. A skip/track change
        // that landed during the failed load must not be reverted to the
        // pre-call snapshot (which also restores an old currentSong/position).
        final current = _getState();
        final superseded = !_isSameTrack(current.currentSong, song);
        if (!superseded) {
          if (prevSlot != null) {
            _queueSlots[state.activeQueueSlot] = prevSlot;
          } else {
            _queueSlots.remove(state.activeQueueSlot);
          }
          _debouncedPersistQueueSlots();
          _bumpQueueVersion();
          // The rollback merges the pre-call queue/playback/lyrics snapshots
          // into the fresh state so concurrent ticks keep their latest values.
          _emit(current.copyWith(
            queueSlice: current.queueSlice.copyWith(
              queue: List<SongsTableData>.unmodifiable(prevQueue),
              currentIndex: prevIndex,
              trackTiers: prevTrackTiers,
            ),
            playback: current.playback.copyWith(
              currentSong: prevSong,
              duration: prevDuration,
              position: prevPosition,
              isPlaying: false,
              errorMessage: 'Failed to play ${song.title}',
            ),
            lyricsSlice: current.lyricsSlice.copyWith(
              lyrics: prevLyrics,
              lyricsSource: prevLyricsSource,
            ),
          ));
        } else {
          // A newer track change superseded the failed selection: keep the
          // fresh playback and only surface the failure.
          _emit(current.copyWith(
            playback: current.playback
                .copyWith(errorMessage: 'Failed to play ${song.title}'),
          ));
        }
        _invalidateQueueSyncResolution();
        try {
          if (!superseded && prevQueue.isNotEmpty) {
            await _audioHandler.loadQueue(
              prevQueue,
              initialIndex: prevIndex,
              initialPosition: prevPosition,
              autoPlay: false,
            );
          }
        } catch (rollbackError, rollbackSt) {
          // C-03: The rollback itself failed. Previously this was swallowed,
          // leaving state claiming `prevQueue` while the audio handler had
          // nothing loaded. Log it and clear the queue so the UI is truthful.
          ErrorLogger.log(
            'Queue rollback failed after load error',
            error: rollbackError,
            stackTrace: rollbackSt,
            category: 'PlayerQueueController',
          );
          try {
            await _audioHandler.pause();
          } catch (_) {}
          try {
            await _audioHandler.clearQueue();
          } catch (_) {}
          try {
            if (!_isClosed()) {
              final broken = _getState();
              _emit(broken.copyWith(
                queueSlice: broken.queueSlice
                    .copyWith(queue: const [], currentIndex: 0),
                playback: broken.playback.copyWith(
                  currentSong: null,
                  isPlaying: false,
                  errorMessage:
                      'Playback unavailable — please pick another track',
                ),
              ));
            }
          } catch (emitError, emitSt) {
            ErrorLogger.log(
                'Failed to emit terminal error state on queue failure',
                error: emitError,
                stackTrace: emitSt,
                category: 'PlayerQueueController');
          }
        }
      }
      return;
    }

    // A-01: On resume (bookmark / last position) restore this track's remembered
    // speed/pitch/volume/EQ. Fire-and-forget: it re-checks the current song
    // before applying so a fast skip cannot clobber the new track.
    if (initialPosition != null && !_isClosed()) {
      _onResumePerSongMemory?.call(song);
    }

    if (_mediaItemResolutionGuard.isValid(capturedGen) && !_isClosed()) {
      _findNextLocalMatch(
          song, effectiveQueue, effectiveIndex, capturedSwapGen, capturedGen);
    }
  }
}
