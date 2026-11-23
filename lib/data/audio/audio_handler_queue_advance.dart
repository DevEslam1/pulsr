part of 'audio_handler.dart';

/// Track-boundary advance and preload handover, extracted from the queue
/// engine so the ratcheted core file can only shrink. The mixin sees the
/// queue engine's private state because it is the same Dart library.
mixin PulsrQueueAdvance on PulsrAudioQueueEngine, PulsrAudioNativeDsd {
  @override
  AudioSessionIdRouter get _audioSessionIdRouter;
  @override
  int? get _playerASessionId;
  @override
  int? get _playerBSessionId;
  @override
  double get _volume;
  @override
  TripleBufferPipeline get _tripleBufferPipeline;
  @override
  CrossfadeManager get _crossfadeManager;
  @override
  IMusicRepository get _repository;

  /// Automatic advance at a natural track boundary.
  ///
  /// Gapless mode advances natively, so this only special-cases the per-track
  /// engine: when the successor is already prepared on the inactive player,
  /// play it there instead of tearing the active player down. Anything else
  /// (a missing/failed preload, repeat-one, end of queue) falls through to
  /// [skipToNext]'s historical path.
  @override
  Future<void> _advanceAtTrackBoundary() async {
    if (_gaplessMode && _gaplessLoaded) {
      await skipToNext();
      return;
    }
    cancelPrefetches();
    // peek:true does not consume a pre-committed shuffle pick, so a fallback
    // skipToNext() resolves the very same successor.
    final nextIdx = _getNextIndex(peek: true);
    if (nextIdx != null && nextIdx != _currentIndex) {
      if (await _handoverToPreloaded(nextIdx)) return;
    }
    await skipToNext();
  }

  /// Plays [nextIndex] on the player that [TripleBufferPipeline.preloadNext]
  /// already prepared, instead of tearing the active player down.
  Future<bool> _handoverToPreloaded(int nextIndex) async {
    if (_gaplessMode || nativeDsdActive) return false;
    if (_crossfadeManager.isCrossfading ||
        _crossfadeManager.duration > Duration.zero) {
      return false;
    }
    if (nextIndex < 0 || nextIndex >= _songs.length) return false;
    final song = _songs[nextIndex];
    if (isNativeDsdCandidate(song)) return false;
    if (_tripleBufferPipeline.preloadedSongId != song.id) return false;
    if (!await _tripleBufferPipeline.claimInactive(PlayerClaim.handover)) {
      return false;
    }
    var handoverDone = false;
    try {
      // Re-check under the claim: a queue edit or a newer preload may have
      // landed while the claim awaited.
      if (_songs.length <= nextIndex || _songs[nextIndex].id != song.id) {
        return false;
      }
      if (_tripleBufferPipeline.preloadedSongId != song.id) return false;

      final outgoing = _activePlayer;
      final incoming = _inactivePlayer;
      if (incoming.processingState == ProcessingState.idle ||
          incoming.processingState == ProcessingState.completed) {
        return false;
      }
      await _applyPlayerOutputVolume(
        incoming,
        _calculateReplayGainVolume(song),
        song: song,
      );
      unawaited(incoming.play().catchError((e, st) {
        ErrorLogger.log('Failed to start incoming player on handover',
            error: e, stackTrace: st, category: 'AudioHandler');
      }));

      _playGeneration++;
      _isPlayerAActive = !_isPlayerAActive;
      _queueStateMachine.commitTransitionTo(
        nextIndex,
        shuffleModeEnabled: _activePlayer.shuffleModeEnabled,
      );
      _savedQueueIndex = nextIndex;
      final currentSessionId =
          _isPlayerAActive ? _playerASessionId : _playerBSessionId;
      _audioSessionIdRouter.handleSessionId(
          currentSessionId ?? _activePlayer.androidAudioSessionId);
      final fastArtUri = song.artworkUri != null
          ? Uri.tryParse(song.artworkUri!)
          : (song.remoteArtworkUrl != null &&
                  !song.remoteArtworkUrl!.startsWith('assets/')
              ? Uri.tryParse(song.remoteArtworkUrl!)
              : ArtworkUriResolver.getCachedArtworkUri(song.id));
      mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
      _notifyTrackChanged(song);
      _planNextStreamResolution();
      _repository.recordPlayHistory(song.id).catchError((e, st) {
        ErrorLogger.log('Failed to record play history on handover',
            error: e, stackTrace: st, category: 'AudioHandler');
        return Left<AppFailure, void>(DatabaseFailure(e.toString()));
      });
      _broadcastState(_activePlayer.playbackEvent);
      _saveCurrentPosition();

      ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
        if (artUri != null &&
            artUri != fastArtUri &&
            _currentIndex == nextIndex &&
            currentSong?.id == song.id) {
          mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
        }
      }).catchError((_) {});

      await _bestEffort(outgoing.stop, 'stop the finished track');
      await _bestEffort(
          () => outgoing.setVolume(_volume), 'reset the finished track volume');
      _tripleBufferPipeline.clearPreload();
      handoverDone = true;
      return true;
    } catch (e, st) {
      ErrorLogger.log('Preloaded handover failed; falling back to a full load',
          error: e, stackTrace: st, category: 'AudioHandler');
      return false;
    } finally {
      _tripleBufferPipeline.releaseInactive(PlayerClaim.handover);
      // Schedule only after the claim is released: preloadNext() takes the
      // same claim and would be refused while this handover still owns it.
      if (handoverDone) _scheduleLookaheadPreload(nextIndex);
    }
  }

  Future<void> _bestEffort(Future<void> Function() action, String what) async {
    try {
      await action();
    } catch (e, st) {
      ErrorLogger.log('Could not $what',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Warms the successor (and N+2 when the buffer bucket allows) on the
  /// inactive/prefetch players. Native DSD tracks are never preloaded: they
  /// are not played by either player.
  @override
  void _scheduleLookaheadPreload(int index) {
    if (_gaplessMode) return;
    final depth = _preloadCountForCurrentBucket;
    if (depth < 1) return;
    final warmIdx = _activePlayer.shuffleModeEnabled
        ? _getNextIndex(peek: true)
        : (index + 1 < _songs.length ? index + 1 : null);
    if (warmIdx != null &&
        warmIdx != index &&
        warmIdx >= 0 &&
        warmIdx < _songs.length &&
        !isNativeDsdCandidate(_songs[warmIdx])) {
      unawaited(_tripleBufferPipeline.preloadNext(_songs[warmIdx]));
    }
    if (depth >= 2) {
      int? prefetchIdx;
      if (_activePlayer.shuffleModeEnabled) {
        final shuffleOrder = _activePlayer.shuffleIndices;
        final posInShuffle = shuffleOrder.indexOf(index);
        if (posInShuffle >= 0 && shuffleOrder.length == _songs.length) {
          final targetPos = posInShuffle + 2;
          if (targetPos < shuffleOrder.length) {
            prefetchIdx = shuffleOrder[targetPos];
          } else if (_activePlayer.loopMode == LoopMode.all &&
              shuffleOrder.isNotEmpty) {
            prefetchIdx = shuffleOrder[targetPos % shuffleOrder.length];
          }
        } else {
          prefetchIdx = _queueStateMachine.peekNextIndex(
            offset: 2,
            shuffleModeEnabled: true,
            loopMode: _activePlayer.loopMode,
          );
        }
      } else if (index + 2 < _songs.length) {
        prefetchIdx = index + 2;
      }
      if (prefetchIdx != null &&
          prefetchIdx != index &&
          prefetchIdx != warmIdx &&
          prefetchIdx >= 0 &&
          prefetchIdx < _songs.length &&
          !isNativeDsdCandidate(_songs[prefetchIdx])) {
        unawaited(_tripleBufferPipeline.prefetchAhead(_songs[prefetchIdx]));
      }
    }
  }
}
