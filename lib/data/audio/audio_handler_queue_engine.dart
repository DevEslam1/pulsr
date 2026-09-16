// ignore_for_file: unused_element
part of 'audio_handler.dart';

mixin PulsrAudioQueueEngine on BaseAudioHandler {
  Future<void> restoreLastPlaybackSession() async {
    try {
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }
      final restoreGen = _playGeneration;

      // Restore shuffle and repeat preferences from storage (Issue #12)
      final prefs = await SharedPreferences.getInstance();
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final shufflePref = prefs.getBool(PrefsKeys.playbackShuffle) ?? false;
      final repeatModePref =
          prefs.getString(PrefsKeys.playbackRepeatMode) ?? 'off';
      final repeatMode = switch (repeatModePref) {
        'all' => AudioServiceRepeatMode.all,
        'one' => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
      await setShuffleMode(shufflePref
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      await setRepeatMode(repeatMode);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final queueRes = await _repository.getSavedQueue();
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final queueItems =
          queueRes.fold((l) => <QueueItemsTableData>[], (r) => r);
      if (queueItems.isEmpty) return;

      // Batch query songs instead of N+1 synchronous disk checks (Issue #18)
      final songIds = queueItems.map((q) => q.songId).toList();
      final songsRes = await _repository.getSongsByIds(songIds);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final songsMap = {
        for (final s in songsRes.fold((l) => <SongsTableData>[], (r) => r))
          s.id: s
      };

      final List<SongsTableData> songs = [];
      int targetIndex = 0;
      int savedPositionMs = 0;

      for (int i = 0; i < queueItems.length; i++) {
        final item = queueItems[i];
        final song = songsMap[item.songId];
        if (song != null) {
          songs.add(song);
          if (item.isCurrent) {
            targetIndex = songs.length - 1;
            savedPositionMs = item.positionMs;
          }
        }
      }

      if (songs.isNotEmpty) {
        if (_userPlaybackInitiated ||
            _songs.isNotEmpty ||
            _playGeneration != restoreGen ||
            _activePlayer.playing ||
            _activePlayer.audioSources.isNotEmpty) {
          return;
        }
        _songs = songs;
        _currentIndex = targetIndex.clamp(0, songs.length - 1);
        final currentSong = _songs[_currentIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(currentSong);
        if (_userPlaybackInitiated || _playGeneration != restoreGen) return;
        final item = PulsrAudioHandler._songToMediaItem(currentSong, artUri);
        mediaItem.add(item);
        queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());

        final pos = Duration(milliseconds: savedPositionMs);
        if (_gaplessMode) {
          // Build the concat but do not preload, so a restored YouTube track
          // resolves its (expiring) URL lazily on the first play() rather than
          // throwing here at cold start when offline and losing the session.
          await _loadGaplessQueue(initialPosition: pos, preload: false);
        } else {
          if (currentSong.source == SongSource.youtube) {
            // Resolving a stream URL here runs unawaited at cold start and, if
            // offline, would throw into the catch below and lose the whole
            // restored session. Stay idle; play() resolves it on first tap.
            _pendingLazyPosition = pos;
          } else {
            await _activePlayer.setAudioSource(
              _createAudioSource(currentSong, item),
              initialPosition: pos,
              preload: false,
            );
          }
        }
        if (_userPlaybackInitiated || _playGeneration != restoreGen) return;
        _broadcastState(_activePlayer.playbackEvent);
        _positionSubject.add(pos);
      }
    } catch (e, st) {
      ErrorLogger.log('Error restoring last playback session',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Readiness gate for crossfade: the incoming player must be decodable
  /// (ready/buffering) with enough buffered audio to cover the fade start.
  bool _canStartCrossfade(AudioPlayer incoming) {
    final ps = incoming.processingState;
    if (ps != ProcessingState.ready && ps != ProcessingState.buffering) {
      return false;
    }
    try {
      return incoming.bufferedPosition > const Duration(seconds: 2);
    } catch (_) {
      return true;
    }
  }

  Future<void> _startCrossfade(int nextIndex) async {
    if (_crossfadeManager.isCrossfading) return;
    if (!await _tripleBufferPipeline.claimInactive(PlayerClaim.crossfade)) return;
    try {
      return await _crossfadeManager.protect(() async {
        if (_crossfadeManager.isCrossfading) return;
        _crossfadeManager.beginCrossfade(nextIndex);
      final currentFadeId = _crossfadeManager.nextFadeId();

      final initialActiveVolume = _calculateReplayGainVolume(currentSong);
      _preCrossfadeVolume = initialActiveVolume;
      try {
        final nextSong = _songs[nextIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(nextSong);
        final item = PulsrAudioHandler._songToMediaItem(nextSong, artUri);

        final source = await _resolveAudioSource(nextSong, item);
        // Resolving a YouTube URL can take seconds. If a skip/stop cancelled this
        // fade meanwhile, loading the source now would push phantom audio into a
        // player that cancel() already stopped — bail on the stale fade.
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Synchronize speed on inactive player before loading & playback
        await _inactivePlayer.setSpeed(_activePlayer.speed);
        await _inactivePlayer.setPitch(_pitch);
        await _inactivePlayer.setAudioSource(source, preload: true);

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        await _inactivePlayer.setVolume(0.0);
        // Wait for the inactive player to be ACTUALLY playing at volume 0
        // before starting the gain ramp. play() resolves when the command is
        // sent, not when ExoPlayer has decoded its first frame — on slow
        // decoders or buffered streams the ramp can advance to ~0.3 before
        // any audio is emitted, causing a pop/click burst at the crossfade
        // start. We poll processingState until it leaves 'loading' (≤1000ms)
        // and then give the mixer one extra period to settle at zero gain.
        try {
          await _inactivePlayer.play().timeout(const Duration(milliseconds: 1000));
        } catch (_) {
          // FIX-#6: The fallback play() must also have a timeout — without one,
          // a hung native decoder deadlocks the crossfade engine indefinitely.
          try {
            await _inactivePlayer.play().timeout(const Duration(milliseconds: 3000));
          } on TimeoutException {
            ErrorLogger.log(
                'Inactive player hung on play(); aborting crossfade',
                category: 'AudioHandler');
            rethrow; // let crossfade error handler clean up
          } catch (_) {}
        }

        // FIX-B02: Abort if crossfade ID changed during play() await
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Poll until the decoder has produced its first audio frame
        // (processingState == ready/buffering with playing==true), or until
        // 1000ms have elapsed as a safety cap.
        const maxSettleMs = 1000;
        var settleWaited = 0;
        while (settleWaited < maxSettleMs) {
          final ps = _inactivePlayer.processingState;
          if (ps == ProcessingState.ready || ps == ProcessingState.buffering) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 20));
          settleWaited += 20;
        }

        // FIX-B02: Abort if crossfade ID changed during settle loop
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        final ps = _inactivePlayer.processingState;
        if (ps != ProcessingState.ready && ps != ProcessingState.buffering) {
          ErrorLogger.log(
              'Inactive player not ready for crossfade (state: $ps); aborting crossfade',
              category: 'AudioHandler');
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Readiness gate: require enough buffered audio to cover the fade
        // start before opening the gain ramp; otherwise delay briefly or
        // fall back to a hard transition to avoid a truncated fade.
        if (!_canStartCrossfade(_inactivePlayer)) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (_crossfadeManager.currentFadeId != currentFadeId) {
            try {
              await _inactivePlayer.stop();
            } catch (_) {}
            try {
              await _activePlayer.setVolume(initialActiveVolume);
            } catch (_) {}
            return;
          }
          if (!_canStartCrossfade(_inactivePlayer)) {
            ErrorLogger.log(
                'Inactive player under-buffered for crossfade; falling back to direct transition',
                category: 'AudioHandler');
            try {
              await _inactivePlayer.stop();
            } catch (_) {}
            try {
              await _activePlayer.setVolume(initialActiveVolume);
            } catch (_) {}
            await playSongAt(nextIndex);
            return;
          }
        }

        // One extra mixer period so the audio sink has settled at zero before
        // the gain ramp opens — eliminates the brief full-volume transient.
        await Future.delayed(const Duration(milliseconds: 20));

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        final active = _activePlayer;
        final inactive = _inactivePlayer;

        // BPM-synced crossfade: when enabled and the incoming track has a
        // known BPM, align the fade to the nearest 2/4/8/16/32 beats.
        final fadeDuration = _crossfadeManager.effectiveFadeDuration(
          trackId: nextSong.id.toString(),
        );

        final targetNextVolume = _calculateReplayGainVolume(nextSong);
        final isRepeatOne = _activePlayer.loopMode == LoopMode.one;

        // Pre-buffer track N+2 into _prefetchPlayer during crossfade window
        // (gated on depth>=2 so minimal-bucket / critical-battery skips it).
        final nextNextIndex = _getNextIndex(offset: 2, peek: true);
        if (_preloadCountForCurrentBucket >= 2 &&
            nextNextIndex != null &&
            nextNextIndex >= 0 &&
            nextNextIndex < _songs.length) {
          unawaited(_tripleBufferPipeline.prefetchAhead(_songs[nextNextIndex]));
        }

        await _crossfadeManager.crossfadeVolumes(
          active: active,
          inactive: inactive,
          fromActiveVol: initialActiveVolume,
          toInactiveVol: targetNextVolume,
          duration: fadeDuration,
          fadeId: currentFadeId,
          isRepeatOne: isRepeatOne,
        );

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await active.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        _isPlayerAActive = !_isPlayerAActive;
        _generationCounter++;
        _currentIndex = nextIndex;

        final currentSessionId =
            _isPlayerAActive ? _playerASessionId : _playerBSessionId;
        _audioSessionIdRouter.handleSessionId(
            currentSessionId ?? _activePlayer.androidAudioSessionId);

        mediaItem.add(PulsrAudioHandler._songToMediaItem(nextSong, artUri));
        _notifyTrackChanged(nextSong);
        _planNextStreamResolution();
        _repository.recordPlayHistory(nextSong.id);
        _broadcastState(_activePlayer.playbackEvent);

        // Clear the native gain curve BEFORE stop() while the player is still
        // active on the platform channel, then allow the pipeline to drain before stop.
        try {
          await active.dspClearGainCurve();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 80));
        try {
          await active.stop();
        } catch (_) {}
        await active.setVolume(_volume);
        // FIX-#5: During crossfade the outgoing player is manually stopped, so
        // ProcessingState.completed never fires.  Notify the sleep timer here
        // so track-count-based timers decrement correctly.
        notifySleepTrackCompleted();
      } catch (e, st) {
        ErrorLogger.log('Error during crossfade playback',
            error: e, stackTrace: st, category: 'AudioHandler');
        try {
          await _inactivePlayer.stop();
        } catch (_) {}
        if (_crossfadeManager.currentFadeId == currentFadeId) {
          await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
              restoreVolume: _volume);
          try {
            await playSongAt(nextIndex);
          } catch (fallbackError, fallbackSt) {
            ErrorLogger.log('Crossfade fallback also failed',
                error: fallbackError,
                stackTrace: fallbackSt,
                category: 'AudioHandler');
            _errorSubject.add('Playback failed. Please try again.');
            await _failCurrentPlayback(fatal: true);
          }
        }
      } finally {
        if (_crossfadeManager.currentFadeId == currentFadeId) {
          _crossfadeManager.finishCrossfade();
        } else {
          // Stale fade (a skip/stop superseded it): drop any native gain
          // curves armed meanwhile so neither player keeps a fade multiplier
          // applied after the volumes are restored here. Clear both players:
          // depending on whether the post-fade swap ran, the outgoing player
          // may be either one.
          try {
            await _inactivePlayer.dspClearGainCurve();
          } catch (_) {}
          try {
            await _activePlayer.dspClearGainCurve();
          } catch (_) {}
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
        }
      }
    });
    } finally {
      _tripleBufferPipeline.releaseInactive(PlayerClaim.crossfade);
    }
  }

  int? _getNextIndex({int offset = 1, bool peek = false}) {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) {
      if (offset == 1 && !peek) {
        _shuffleHistory.add(_currentIndex);
        if (_shuffleHistory.length > 50) {
          _shuffleHistory.removeAt(0);
        }
      }
      if (_songs.length == 2) {
        // In a 2-song queue with shuffle enabled, alternate to the other song
        return _currentIndex == 0 ? 1 : 0;
      }
      if (_songs.length == 1) {
        return 0;
      }
      final random = math.Random();
      final recentWindow = math.min(_songs.length - 1, 10);
      final recent = _shuffleHistory.length >= recentWindow
          ? _shuffleHistory.sublist(_shuffleHistory.length - recentWindow)
          : _shuffleHistory;

      int next = random.nextInt(_songs.length);
      int attempts = 0;
      final maxAttempts = _songs.length * 2;
      while ((next == _currentIndex || recent.contains(next)) &&
          attempts < maxAttempts &&
          _songs.length > 1) {
        next = random.nextInt(_songs.length);
        attempts++;
      }
      if (next == _currentIndex && _songs.length > 1) {
        final candidates = [
          for (int i = 0; i < _songs.length; i++)
            if (i != _currentIndex) i
        ];
        next = candidates[random.nextInt(candidates.length)];
      }
      return next;
    }
    if (_currentIndex + offset < _songs.length) {
      return _currentIndex + offset;
    } else if (_activePlayer.loopMode == LoopMode.all && _songs.isNotEmpty) {
      return (_currentIndex + offset) % _songs.length;
    }
    return null;
  }

  int? getPreviousIndex({bool forcePrevious = false}) {
    if (_songs.isEmpty) return null;
    if (!forcePrevious && _activePlayer.position.inSeconds > 3) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _shuffleHistory.isNotEmpty) {
      // Drain any stale entries left over from a previous/shorter queue rather
      // than returning an out-of-range index.
      while (_shuffleHistory.isNotEmpty) {
        final previous = _shuffleHistory.removeLast();
        if (previous >= 0 && previous < _songs.length) return previous;
      }
    }
    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (_activePlayer.loopMode == LoopMode.all) {
      return _songs.length - 1;
    }
    return null;
  }

  void _broadcastState(PlaybackEvent event) {
    // Player events are already filtered to the active player by
    // setupPlayerListeners' isTargetActive(); the previous identical() guard
    // here compared _activePlayer against its own definition and was always
    // false (dead code).
    // If a gapless load is actively preparing a new track for user playback,
    // ignore transient idle/stop events emitted by stop() before setAudioSources.
    if (_gaplessMode &&
        !_gaplessLoaded &&
        _userPlaybackInitiated &&
        _gaplessTargetIndex != null) {
      return;
    }

    final isCompleted =
        _activePlayer.processingState == ProcessingState.completed;
    final isPlaying = _activePlayer.playing && !isCompleted;
    final activeSong = currentSong;
    final isStream =
        activeSong != null && PulsrAudioHandler._isStreamUrl(activeSong.path);
    // Skip controls follow the queue, not the URL scheme (C-1): a lone live
    // stream has nowhere to skip, and neither has a single-track local queue.
    // What matters is whether a neighbouring queue entry actually exists.
    final hasPrevious = _hasQueueNeighbour(forward: false);
    final hasNext = _hasQueueNeighbour(forward: true);
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_activePlayer.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        // Keep the advertised system actions consistent with the control set
        // above: a stream may never expose a duration, so seek is meaningless
        // for a live source, and shuffle/repeat mean nothing when the queue
        // holds no other entry to act on (C-1).
        systemActions: {
          if (!isStream) ...[
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          ],
          if (hasPrevious || hasNext) ...[
            MediaAction.setShuffleMode,
            MediaAction.setRepeatMode,
          ],
        },
        androidCompactActionIndices: [
          for (var i = 0; i < controls.length; i++) i,
        ],
        processingState: processingState,
        playing: isPlaying,
        // Report the latency-compensated position so the notification shade's
        // scrubber matches what the user actually hears (matches the in-app
        // UI/lyrics, which already use compensatedPosition).
        updatePosition: compensatedPosition,
        bufferedPosition: _activePlayer.bufferedPosition,
        speed: _activePlayer.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  /// Whether the queue holds another entry to skip to in [forward] direction.
  ///
  /// Non-destructive on purpose — it is called from [_broadcastState], which
  /// must not consume shuffle history or otherwise mutate navigation state the
  /// way [_getNextIndex] / [_getPreviousIndex] do when they are read for
  /// real. A single-entry queue (a lone live stream, a one-track album) has no
  /// neighbour; so does the last track of a non-looping queue going forward.
  bool _hasQueueNeighbour({required bool forward}) {
    if (_songs.length <= 1) return false;
    if (_activePlayer.shuffleModeEnabled) return true;
    if (_activePlayer.loopMode == LoopMode.all) return true;
    return forward ? _currentIndex + 1 < _songs.length : _currentIndex > 0;
  }

  bool _isSameSongList(List<SongsTableData> a, List<SongsTableData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].path != b[i].path) return false;
    }
    return true;
  }

  Future<bool> _isGenerationCancelled(int generation) async {
    // Pure predicate: no side effects. Callers restore volume explicitly so a
    // stale poll can never mutate the live player.
    return generation != _playGeneration;
  }

  Future<void> _loadSongPaused(int index, {Duration? initialPosition}) async {
    _userPlaybackInitiated = true;
    if (index < 0 || index >= _songs.length) return;
    final generation = ++_playGeneration;
    final song = _songs[index];
    _currentIndex = index;
    _pendingLazyPosition = null;

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = PulsrAudioHandler._songToMediaItem(song, fastArtUri);
    mediaItem.add(item);
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));

    await _fadeOutForSwitch(_activePlayer);
    if (await _isGenerationCancelled(generation)) return;

    try {
      await _activePlayer.pause();
    } catch (_) {}

    final targetVolume = _calculateReplayGainVolume(song);
    try {
      await _activePlayer.dspClearGainCurve();
    } catch (_) {}
    await _activePlayer.setVolume(targetVolume);

    if (song.source == SongSource.youtube &&
        (song.remoteId?.isNotEmpty ?? false) &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true))) {
      _pendingLazyPosition = initialPosition ?? Duration.zero;
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }

    try {
      final source = await _resolveAudioSource(song, item);
      if (await _isGenerationCancelled(generation)) return;
      await _activePlayer.setAudioSource(
        source,
        initialPosition: initialPosition ?? Duration.zero,
        preload: false,
      );
      _broadcastState(_activePlayer.playbackEvent);
    } catch (e, st) {
      ErrorLogger.log('Failed to load song paused',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  // --- QUEUE & PLAYBACK COMMANDS ---
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition, bool autoPlay = true}) async {
    if (songs.isEmpty) {
      _songs = [];
      _currentIndex = 0;
      _queueDirty = true;
      _gaplessLoaded = false;
      _pendingLazyPosition = null;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    _userPlaybackInitiated = true;
    _isManualSkip = true;
    // Immediately warm the target song so network resolution overlaps
    // with crossfade cancellation, queue assembly, and player teardown.
    final targetIdx =
        initialIndex.clamp(0, songs.isEmpty ? 0 : songs.length - 1);
    final initialSong = songs[targetIdx];
    if (initialSong.source == SongSource.youtube &&
        (initialSong.remoteId?.isNotEmpty ?? false) &&
        (initialSong.path.startsWith('ytmusic://') ||
            initialSong.path.isEmpty ||
            (!initialSong.path.startsWith('content:') &&
                initialSong.isDownloaded != true))) {
      unawaited(_warmStreamCache(initialSong));
    }

    // Gapless Album Pre-buffering: pre-buffer opening 3 tracks (0, 1, 2) when queue is loaded
    for (int i = 1; i <= 2; i++) {
      final lookaheadIdx = targetIdx + i;
      if (lookaheadIdx < songs.length) {
        final lookaheadSong = songs[lookaheadIdx];
        if (lookaheadSong.source == SongSource.youtube &&
            (lookaheadSong.remoteId?.isNotEmpty ?? false)) {
          unawaited(_warmStreamCache(lookaheadSong));
        }
        unawaited(ArtworkUriResolver.resolveArtworkUri(lookaheadSong));
      }
    }

    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);

    // Fast-path: if gapless queue is already loaded with the exact same songs,
    // immediately seek to the requested track instead of tearing down
    // and recreating the entire ExoPlayer playlist.
    if (_gaplessMode &&
        _gaplessLoaded &&
        _activePlayer.audioSources.length == songs.length &&
        _isSameSongList(_songs, songs)) {
      final generation = ++_playGeneration;
      final targetIndex =
          initialIndex.clamp(0, _songs.isEmpty ? 0 : _songs.length - 1);
      _currentIndex = targetIndex;
      _lastGaplessIndex = targetIndex;
      _gaplessTargetIndex = targetIndex;
      _gaplessTargetReached = false;
      _gaplessLoadTime = DateTime.now();
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _lastGaplessChangeTime = null;
      final song = _songs[targetIndex];
      final fastArtUri =
          song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
      mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
      _notifyTrackChanged(song);
      unawaited(_evaluateBufferBucket(song));
      _planNextStreamResolution();

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            autoPlay ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          processingState: autoPlay
              ? AudioProcessingState.loading
              : AudioProcessingState.ready,
          playing: autoPlay,
          queueIndex: targetIndex,
        ),
      );

      if (song.source == SongSource.youtube &&
          (song.remoteId?.isNotEmpty ?? false) &&
          (song.path.startsWith('ytmusic://') ||
              song.path.isEmpty ||
              (!song.path.startsWith('content:') &&
                  song.isDownloaded != true))) {
        unawaited(_warmStreamCache(song).catchError((e) {
          if (generation != _playGeneration) return;
          debugPrint(
              '[AudioHandler] Background warm failed for ${song.title}: $e');
        }));
      }

      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;

      await _activePlayer.seek(initialPosition ?? Duration.zero,
          index: targetIndex);
      if (_activePlayer.currentIndex == targetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      }
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      await _activePlayer.setVolume(targetVolume);
      if (autoPlay) {
        unawaited(_activePlayer.play());
      } else {
        try {
          await _activePlayer.pause();
        } catch (_) {}
      }
      _broadcastState(_activePlayer.playbackEvent);
      if (autoPlay) {
        _repository.recordPlayHistory(song.id);
      }
      _saveCurrentPosition();

      ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
        if (artUri != null &&
            artUri != fastArtUri &&
            generation == _playGeneration &&
            currentSong?.id == song.id) {
          mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
        }
      }).catchError((_) {});
      return;
    }

    _songs = List.from(songs);
    _currentIndex =
        initialIndex.clamp(0, _songs.isEmpty ? 0 : _songs.length - 1);
    // A new queue invalidates shuffle navigation history; stale indices would
    // otherwise point at unrelated tracks (or out of range) on Previous.
    _shuffleHistory.clear();
    _queueDirty = true;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;

    final mediaItems = _songs.map(PulsrAudioHandler._songToMediaItem).toList();
    queue.add(mediaItems);

    if (_gaplessMode) {
      await _loadGaplessQueue(initialPosition: initialPosition, preload: autoPlay);
    } else {
      if (autoPlay) {
        await playSongAt(_currentIndex, initialPosition: initialPosition);
      } else {
        await _loadSongPaused(_currentIndex, initialPosition: initialPosition);
      }
    }
  }

  void swapReconciledSong(int oldId, SongsTableData newSong) {
    final idx = _songs.indexWhere((s) => s.id == oldId);
    if (idx != -1) {
      _songs[idx] = newSong;
      final mediaItems = _songs.map(PulsrAudioHandler._songToMediaItem).toList();
      queue.add(mediaItems);
      if (_currentIndex == idx) {
        final fastArtUri = newSong.artworkUri != null
            ? Uri.tryParse(newSong.artworkUri!)
            : null;
        mediaItem.add(PulsrAudioHandler._songToMediaItem(newSong, fastArtUri));
      }
    }
  }

  /// Loads the whole queue as a playlist on the active
  /// player so ExoPlayer joins consecutive tracks with no gap. With [preload]
  /// false the source is set but not prepared, so a restored YouTube track
  /// resolves lazily on the first play() instead of throwing at cold start when
  /// offline.
  Future<void> _loadGaplessQueue(
      {Duration? initialPosition, bool preload = true}) async {
    if (_songs.isEmpty) return;
    final generation = ++_playGeneration;
    // Quiesce native index events for the whole load: stop()/setAudioSources
    // emit transient indices (playlist attach resets to 0 before the initial
    // seek lands). With the stale _gaplessLoaded=true those transients used
    // to run _onGaplessIndexChanged mid-load, corrupting _currentIndex —
    // sometimes BEFORE it was consumed as initialIndex below, so tapping
    // song N loaded and played song 0 instead, with mediaItem/volume/history
    // churning (the "glitch + first song again" bug).
    _gaplessLoaded = false;
    _pendingLazyPosition = null;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;
    // Snapshot: no interleaved stream event may change the load target.
    final targetIndex = _currentIndex;
    _lastGaplessIndex = targetIndex;
    _gaplessTargetIndex = targetIndex;
    _gaplessTargetReached = false;
    _gaplessLoadTime = DateTime.now();

    final song = _songs[targetIndex];
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));
    _planNextStreamResolution();

    if (preload) {
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.skipToNext,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          processingState: AudioProcessingState.loading,
          playing: true,
          queueIndex: targetIndex,
        ),
      );
    }

    final sources = _buildAudioSources(_songs);

    // Pre-resolve the target online URL BEFORE stopping current playback:
    // a YouTube resolve can take seconds, and stopping first turns that into
    // seconds of dead silence followed by a cold start. Resolving first keeps
    // the old track playing until the swap is near-instant (the URL lands in
    // _streamCache/YtmUrlCache, which the lazy child then reuses). On failure
    // the current track keeps playing and only an error toast is shown.
    // Fire-and-forget: if the warm completes before setAudioSources, the
    // YtmResolvingSource child hits a hot cache; if not, the child resolves
    // lazily on its own.
    if (song.source == SongSource.youtube &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true)) &&
        (song.remoteId?.isNotEmpty ?? false)) {
      unawaited(_warmStreamCache(song).catchError((e) {
        if (generation != _playGeneration) return;
        debugPrint(
            '[AudioHandler] Gapless pre-warm failed for ${song.title}: $e');
      }));
    }

    try {
      // Soft-landing fade so the stop doesn't click, then cleanly stop any
      // existing playing source to release hanging native sockets.
      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;
      try {
        await _activePlayer.stop();
      } catch (_) {}

      await _activePlayer.setAudioSources(
        sources,
        initialIndex: targetIndex,
        initialPosition: initialPosition,
        preload: preload,
      );
      try {
        _latencyTracker?.markStage(PlaybackStage.sourceSet);
      } catch (_) {}
      _gaplessLoaded = true;
      _lastGaplessIndex = targetIndex;
      _gaplessLoadTime = DateTime.now();
      if (_activePlayer.currentIndex == targetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      }
      if (await _isGenerationCancelled(generation)) return;
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      if (!preload) {
        // Restored queue, not playing yet: park the correct level so a later
        // play() doesn't inherit a faded-out 0 from a previous switch.
        await _activePlayer.setVolume(targetVolume);
      } else {
        await _activePlayer.setVolume(targetVolume);
        // FIX-#2b: Re-check generation after the async setVolume — same race
        // condition as playSongAt (see FIX-#2).
        if (_playGeneration != generation) return;
        unawaited(_activePlayer.play());
        _broadcastState(_activePlayer.playbackEvent);
      }
      if (preload) {
        try {
          _latencyTracker?.markStage(PlaybackStage.firstBytesReady);
          _latencyTracker?.markStage(PlaybackStage.playing);
        } catch (_) {}
        _consecutiveFailures = 0;
        _repository.recordPlayHistory(song.id);
      }
      _saveCurrentPosition();

      // Resolve high-res artwork off the hot path, like the crossfade engine.
      ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
        if (artUri != null &&
            artUri != fastArtUri &&
            generation == _playGeneration &&
            currentSong?.id == song.id) {
          mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
        }
      }).catchError((_) {});
    } on YtmException catch (e, st) {
      if (generation != _playGeneration) return;
      final info = YtmErrorClassifier.classify(e);
      _errorSubject.add(info.message);
      ErrorLogger.log(
          'Error loading gapless YouTube source for ${song.title} (${e.code})',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      if (e.isFatal) {
        await _failCurrentPlayback(fatal: true);
        return;
      }
      // Non-fatal: skip this track and try the next
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
        await _failCurrentPlayback(fatal: false);
        return;
      }
      final nextIdx = _getNextIndex();
      if (nextIdx != null && nextIdx != targetIndex) {
        await playSongAt(nextIdx, initialPosition: initialPosition);
      } else {
        await _failCurrentPlayback(fatal: false);
      }
    } catch (e, st) {
      if (generation != _playGeneration) return;
      final errStr = e.toString().toLowerCase();
      // Ignore loading interrupted / abort errors resulting from newer play actions
      if (errStr.contains('interrupted') || errStr.contains('abort')) {
        return;
      }
      final info = YtmErrorClassifier.classify(e);
      final String errorMessage;
      if (e is PlayerException && e.message != null && e.message!.isNotEmpty) {
        errorMessage = e.message!;
      } else {
        errorMessage = info.message;
      }
      _errorSubject.add(errorMessage);
      ErrorLogger.log('Error loading gapless queue for ${song.title}',
          error: e, stackTrace: st, category: 'AudioHandler');

      // If the source at targetIndex has a permanent failure (BOT_CHALLENGE,
      // VIDEO_GONE, etc.) stored by YtmResolvingSource, the ExoPlayer "Source
      // error" is a known-permanent cause — skip to the next track rather than
      // calling _failCurrentPlayback(fatal: true) which just pauses and leaves
      // the user stuck with no audio and no way to continue.
      final targetSource = sources.length > targetIndex ? sources[targetIndex] : null;
      final sourcePermanentFailure = targetSource is YtmResolvingSource
          ? targetSource.permanentFailure
          : null;
      if (sourcePermanentFailure != null) {
        final failInfo = YtmErrorClassifier.classify(sourcePermanentFailure);
        _errorSubject.add(failInfo.message);
        _consecutiveFailures++;
        if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
          await _failCurrentPlayback(fatal: false);
        } else {
          final nextIdx = _getNextIndex();
          if (nextIdx != null && nextIdx != targetIndex) {
            await playSongAt(nextIdx, initialPosition: initialPosition);
          } else {
            await _failCurrentPlayback(fatal: false);
          }
        }
        return;
      }

      final isFatal = (e is YtmException && e.isFatal) ||
          info.recoveryAction != YtmRecoveryAction.skipToNextTrack;
      await _failCurrentPlayback(fatal: isFatal);
    }

  }

  /// Reacts to a native gapless advance (currentIndexStream): keeps the queue
  /// model, notification, play history, replay-gain volume and saved position in
  /// step with the item ExoPlayer moved to on its own.
  Future<void> _onGaplessIndexChanged(int index) async {
    if (!_gaplessMode) return;
    if (index < 0 || index >= _songs.length) return;
    if (!_gaplessLoaded) return;
    final childCount = _activePlayer.audioSources.length;
    if (index >= childCount) return;

    // Transient index 0 / spurious emit filter:
    // When loading a playlist, ExoPlayer may emit an initial index 0 before settling on the
    // requested target index. If target index hasn't been reached yet, ignore any unexpected index.
    if (_gaplessTargetIndex != null) {
      if (index == _gaplessTargetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      } else if (!_gaplessTargetReached) {
        final elapsed = _gaplessLoadTime != null
            ? DateTime.now().difference(_gaplessLoadTime!).inMilliseconds
            : 99999;
        if (elapsed < 3000) {
          debugPrint(
              '[AudioHandler] Ignoring spurious gapless index event: $index (target was $_gaplessTargetIndex)');
          return;
        }
      }
    }

    // Detect rapid successive transitions caused by ExoPlayer auto-advancing
    // past failing tracks in a loop. If user paused, kill the loop immediately.
    if (!_activePlayer.playing) {
      _rapidGaplessChangeCount = 0;
      _consecutiveFailures = 0;
      return;
    }
    if (_isManualSkip) {
      _isManualSkip = false;
      _rapidGaplessChangeCount = 0;
      _consecutiveFailures = 0;
    } else {
      final now = DateTime.now();
      if (_lastGaplessChangeTime != null &&
          now.difference(_lastGaplessChangeTime!).inMilliseconds < 1500) {
        _rapidGaplessChangeCount++;
        if (_rapidGaplessChangeCount >= 3) {
          // Circuit breaker tripped: halt runaway skip loop
          _rapidGaplessChangeCount = 0;
          _consecutiveFailures = 0;
          ErrorLogger.log(
            'Circuit breaker tripped: rapid gapless track changes detected. Halting playback.',
            category: 'AudioHandler',
          );
          _errorSubject.add('Playback stopped: multiple tracks failed to load.');
          await _activePlayer.pause();
          _broadcastState(_activePlayer.playbackEvent);
          return;
        }
      } else {
        _rapidGaplessChangeCount = 0;
        _consecutiveFailures = 0;
      }
      _lastGaplessChangeTime = now;
    }

    _lastGaplessIndex = index;
    _currentIndex = index;
    final song = _songs[index];
    final generation = _playGeneration;

    // Notify sleep timer of track completion for endOfTrack / afterNTracks
    // modes (fixes silent never-fire). Fired before the async work below so it
    // lands within the duplicate-collapse window of the native `completed`
    // event that reports the same boundary.
    notifySleepTrackCompleted();

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));
    _planNextStreamResolution();
    await _activePlayer.setVolume(_calculateReplayGainVolume(song));
    _repository.recordPlayHistory(song.id);
    _broadcastState(_activePlayer.playbackEvent);
    _saveCurrentPosition();

    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null &&
          artUri != fastArtUri &&
          _currentIndex == index &&
          generation == _playGeneration &&
          currentSong?.id == song.id) {
        mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
      }
    }).catchError((_) {});
  }

  void _planNextStreamResolution() {
    if (_songs.isEmpty) return;
    _streamPreResolver.onTrackStarted(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
    );
  }

  Future<void> playSongAt(int index, {Duration? initialPosition}) async {
    _userPlaybackInitiated = true;
    if (index < 0 || index >= _songs.length) return;
    cancelPrefetches();
    // A YouTube resolve below can await for seconds; a second skip during that
    // window must win. Capture a generation token FIRST so a pre-resolve
    // failure can bail without touching current playback at all.
    final generation = ++_playGeneration;
    final song = _songs[index];
    _streamPreResolver.onTrackEnqueuedOrTapped(song);

    // Fire-and-forget background warm: if the URL is already cached this
    // returns instantly; if not, it populates the cache in the background
    // so the lazy YtmResolvingSource hits a hot cache when just_audio
    // requests bytes. Never blocks the tap→play path.
    if (song.source == SongSource.youtube &&
        (song.remoteId?.isNotEmpty ?? false) &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true))) {
      unawaited(_warmStreamCache(song).catchError((e) {
        if (generation != _playGeneration) return;
        debugPrint(
            '[AudioHandler] Background warm failed for ${song.title}: $e');
      }));
    }

    // Soft-landing fade so pause/stop doesn't click, then ensure the previous
    // MediaCodec EventHandler is fully released before creating a new decoder
    // — prevents LegacyMessageQueue dead-thread crash on rapid Hi-Res FLAC switch (LOG-12)
    // Fast path: when the player is idle with no source, there is no decoder
    // to tear down — skip the ~1s pause/stop/grace serial entirely.
    final needsTeardown = _activePlayer.playing ||
        (_activePlayer.audioSource != null &&
            _activePlayer.processingState != ProcessingState.idle &&
            _activePlayer.processingState != ProcessingState.completed);
    if (needsTeardown) {
      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;
      try {
        await _activePlayer.pause().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      try {
        await _activePlayer.stop().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      // Grace period only for decoder-backed switches (local/Hi-Res). YouTube
      // lazy sources create no MediaCodec until first bytes are requested.
      final isLocalDecode =
          song.source == SongSource.local || song.isDownloaded == true;
      if (isLocalDecode) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } else {
      if (await _isGenerationCancelled(generation)) return;
    }
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    if (await _isGenerationCancelled(generation)) return;
    _pendingLazyPosition = null;
    _currentIndex = index;
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = PulsrAudioHandler._songToMediaItem(song, fastArtUri);
    mediaItem.add(item);
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));

    // Resolve high-res artwork in background without blocking audio source loading
    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null &&
          artUri != fastArtUri &&
          generation == _playGeneration &&
          currentSong?.id == song.id) {
        mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
      }
    }).catchError((_) {});

    // Kick off background prefetch for next track immediately so next skip is instant
    if (index + 1 < _songs.length) {
      _prefetchStream(_songs[index + 1]);
    }

    // Keep notification controls alive during track transition
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.loading,
        playing: true,
        queueIndex: _currentIndex,
      ),
    );

    try {
      AudioSource source = await _resolveAudioSource(song, item);
      if (await _isGenerationCancelled(generation)) return;
      // For YouTube tracks using YtmResolvingSource (no warm cache hit),
      // use preload: false so setAudioSource returns instantly. just_audio
      // will call the resolve callback when it actually needs bytes,
      // keeping the UI responsive during the (potentially slow) resolution.
      final useLazyPreload = source is YtmResolvingSource;
      try {
        await _activePlayer.setAudioSource(source,
            initialPosition: initialPosition, preload: !useLazyPreload);
      } catch (playErr) {
        // If a YouTube stream fails (e.g. 403 / expired URL), clear cache & retry once
        if (song.source == SongSource.youtube && song.remoteId != null) {
          debugPrint(
              '[AudioHandler] Playback error on ${song.title}: $playErr. Retrying with fresh stream URL...');
          _streamCache.removeWhere((key, _) => key.startsWith('${song.remoteId}:'));
          source = await _resolveAudioSource(song, item);
          if (await _isGenerationCancelled(generation)) return;
          final retryLazy = source is YtmResolvingSource;
          await _activePlayer.setAudioSource(source,
              initialPosition: initialPosition, preload: !retryLazy);
        } else {
          rethrow;
        }
      }
      if (await _isGenerationCancelled(generation)) return;
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      await _activePlayer.setVolume(targetVolume);
      // FIX-#2: Re-check generation after the async setVolume — a rapid skip
      // during the await can load a new source, and calling play() here would
      // inadvertently start the wrong track.
      if (_playGeneration != generation) return;
      unawaited(_activePlayer.play());
      _broadcastState(_activePlayer.playbackEvent);
      _consecutiveFailures = 0;
      _repository.recordPlayHistory(song.id);
      _saveCurrentPosition();

      // Early prefetch next streams for Gapless 2.0
      _prefetchNextTracks();
      // Unified preload depth: bucket drives ALL stages (scheduler via
      // _smartPrefetch above, triple-buffer here). minimal=1 holds only N+1,
      // standard=2 adds N+2, generous=3 keeps full lookahead.
      final depth = _preloadCountForCurrentBucket;
      // Only preload onto inactive player when crossfade is active
      if (!_gaplessMode && depth >= 1 && _songs.length > index + 1) {
        unawaited(_tripleBufferPipeline.preloadNext(_songs[index + 1]));
      }
      if (!_gaplessMode && depth >= 2 && _songs.length > index + 2) {
        unawaited(_tripleBufferPipeline.prefetchAhead(_songs[index + 2]));
      }
    } on YtmException catch (e, st) {
      if (generation != _playGeneration) return;
      final info = YtmErrorClassifier.classify(e);
      _errorSubject.add(info.message);
      ErrorLogger.log(
          'Error resolving YouTube stream for ${song.title} (${e.code})',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      // A dead network, bot challenge, or extractor-less build fails every remaining YouTube
      // row, so skipping through them is pointless — halt immediately.
      await _failCurrentPlayback(fatal: e.isFatal);
    } on DsdUnsupportedException catch (e, st) {
      if (generation != _playGeneration) return;
      // DSD (DSF/DFF) on a platform with no native decoder (e.g. iOS) must
      // fail visibly and skip, never crash or loop on the same row.
      _errorSubject.add(e.message);
      ErrorLogger.log('DSD playback unsupported for ${song.title}',
          error: e, stackTrace: st, category: 'AudioHandler');
      await _failCurrentPlayback(fatal: false);
    } catch (e, st) {
      if (generation != _playGeneration) return;
      if (e is PlatformException &&
          (e.code == 'abort' ||
              (e.message ?? '').toLowerCase().contains('abort') ||
              (e.message ?? '').toLowerCase().contains('interrupted'))) {
        return;
      }
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('interrupted') || errStr.contains('abort')) {
        return;
      }
      final info = YtmErrorClassifier.classify(e);
      final String errorMessage;
      if (e is PlayerException && e.message != null && e.message!.isNotEmpty) {
        errorMessage = e.message!;
      } else {
        errorMessage = info.message;
      }
      _errorSubject.add(errorMessage);
      ErrorLogger.log('Error playing song ${song.title} (${song.path})',
          error: e, stackTrace: st, category: 'AudioHandler');
      final isFatal = (e is YtmException && e.isFatal) ||
          info.recoveryAction != YtmRecoveryAction.skipToNextTrack;
      await _failCurrentPlayback(fatal: isFatal);
    }
  }

  /// Shared failure handling for [playSongAt]: a fatal error pauses outright,
  /// otherwise skip forward until [_consecutiveFailures] trips the circuit.
  /// Stops the loop if playback is already paused (user hit pause) or after
  /// 3 consecutive failures — prevents infinite skip loop on bot-blocked IP.
  Future<void> _failCurrentPlayback({required bool fatal}) async {
    // User paused during the failure chain → never auto-resume/skip.
    if (!_activePlayer.playing) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }
    if (fatal) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _errorSubject.add('Playback failed for consecutive tracks. Stopping.');
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      await skipToNext();
    }
  }


















































































































































































































































































































  // Requires: provided by the composing class (same library).
  AudioPlayer get _activePlayer;

  // Requires: provided by the composing class (same library).
  AudioSessionIdRouter get _audioSessionIdRouter;

  // Requires: provided by the composing class (same library).
  List<AudioSource> _buildAudioSources(List<SongsTableData> songs);

  // Requires: provided by the composing class (same library).
  double _calculateReplayGainVolume(SongsTableData? song);

  // Requires: provided by the composing class (same library).
  int get _consecutiveFailures;
  set _consecutiveFailures(int value);

  // Requires: provided by the composing class (same library).
  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag);

  // Requires: provided by the composing class (same library).
  CrossfadeManager get _crossfadeManager;

  // Requires: provided by the composing class (same library).
  int get _currentIndex;
  set _currentIndex(int value);

  // Requires: provided by the composing class (same library).
  StreamController<String> get _errorSubject;

  // Requires: provided by the composing class (same library).
  Future<void> _evaluateBufferBucket(SongsTableData song);

  // Requires: provided by the composing class (same library).
  Future<void> _fadeOutForSwitch(AudioPlayer player);

  // Requires: provided by the composing class (same library).
  DateTime? get _gaplessLoadTime;
  set _gaplessLoadTime(DateTime? value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessLoaded;
  set _gaplessLoaded(bool value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessMode;

  // Requires: provided by the composing class (same library).
  int? get _gaplessTargetIndex;
  set _gaplessTargetIndex(int? value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessTargetReached;
  set _gaplessTargetReached(bool value);

  // Requires: provided by the composing class (same library).
  int get _generationCounter;
  set _generationCounter(int value);

  // Requires: provided by the composing class (same library).
  AudioPlayer get _inactivePlayer;

  // Requires: provided by the composing class (same library).
  bool get _isManualSkip;
  set _isManualSkip(bool value);

  // Requires: provided by the composing class (same library).
  bool get _isPlayerAActive;
  set _isPlayerAActive(bool value);

  // Requires: provided by the composing class (same library).
  DateTime? get _lastGaplessChangeTime;
  set _lastGaplessChangeTime(DateTime? value);

  // Requires: provided by the composing class (same library).
  PlaybackLatencyTracker? get _latencyTracker;

  // Requires: provided by the composing class (same library).
  void notifySleepTrackCompleted();

  // Requires: provided by the composing class (same library).
  void _notifyTrackChanged(SongsTableData song);

  // Requires: provided by the composing class (same library).
  double get _pitch;

  // Requires: provided by the composing class (same library).
  int get _playGeneration;
  set _playGeneration(int value);

  // Requires: provided by the composing class (same library).
  int? get _playerASessionId;

  // Requires: provided by the composing class (same library).
  int? get _playerBSessionId;

  // Requires: provided by the composing class (same library).
  StreamController<Duration> get _positionSubject;

  // Requires: provided by the composing class (same library).
  void _prefetchNextTracks();

  // Requires: provided by the composing class (same library).
  void _prefetchStream(SongsTableData song);

  // Requires: provided by the composing class (same library).
  int get _preloadCountForCurrentBucket;

  // Requires: provided by the composing class (same library).
  int get _rapidGaplessChangeCount;
  set _rapidGaplessChangeCount(int value);

  // Requires: provided by the composing class (same library).
  IMusicRepository get _repository;

  // Requires: provided by the composing class (same library).
  Future<AudioSource> _resolveAudioSource( SongsTableData song, MediaItem tag);

  // Requires: provided by the composing class (same library).
  void _saveCurrentPosition();

  // Requires: provided by the composing class (same library).
  List<int> get _shuffleHistory;

  // Requires: provided by the composing class (same library).
  List<SongsTableData> get _songs;
  set _songs(List<SongsTableData> value);

  // Requires: provided by the composing class (same library).
  dynamic get _streamCache;

  // Requires: provided by the composing class (same library).
  StreamPreResolver get _streamPreResolver;

  // Requires: provided by the composing class (same library).
  TripleBufferPipeline get _tripleBufferPipeline;

  // Requires: provided by the composing class (same library).
  bool get _userPlaybackInitiated;
  set _userPlaybackInitiated(bool value);

  // Requires: provided by the composing class (same library).
  double get _volume;

  // Requires: provided by the composing class (same library).
  Future<void> _warmStreamCache(SongsTableData song);

  // Requires: provided by the composing class (same library).
  void cancelPrefetches();

  // Requires: provided by the composing class (same library).
  Duration get compensatedPosition;

  // Requires: provided by the composing class (same library).
  SongsTableData? get currentSong;

  // Requires: provided by the composing class (same library).
  Duration? get _pendingLazyPosition;
  set _pendingLazyPosition(Duration? value);

  // Requires: provided by the composing class (same library).
  double? get _preCrossfadeVolume;
  set _preCrossfadeVolume(double? value);

  // Requires: provided by the composing class (same library).
  bool get _queueDirty;
  set _queueDirty(bool value);

  // Requires: provided by the composing class (same library).
  int get _lastGaplessIndex;
  set _lastGaplessIndex(int value);
}
