part of 'audio_handler.dart';

mixin PulsrAudioQueueEngine on BaseAudioHandler, PulsrAudioStreaming {
  Future<Map<String, dynamic>?> _readCrashPositionRecovery();

  Future<void> restoreLastPlaybackSession() async {
    try {
      if (_songs.isNotEmpty ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }
      final restoreGen = _playGeneration;
      // True once anything else (a user tap, another restore) has taken the
      // player while this restore was awaiting.
      bool isStale() =>
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty;

      // Restore shuffle and repeat preferences from storage (Issue #12)
      final prefs = await SharedPreferences.getInstance();
      if (isStale()) return;

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
      if (isStale()) return;

      await setRepeatMode(repeatMode);
      if (isStale()) return;

      final queueRes = await _repository.getSavedQueue();
      if (isStale()) return;

      final queueItems =
          queueRes.fold((l) => <QueueItemsTableData>[], (r) => r);
      if (queueItems.isEmpty) return;

      // Batch query songs instead of N+1 synchronous disk checks (Issue #18)
      final songIds = queueItems.map((q) => q.songId).toList();
      final songsRes = await _repository.getSongsByIds(songIds);
      if (isStale()) return;

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
            // Fall back to the per-song position when the queue row carries
            // none (e.g. saved before the position refresh existed), so a cold
            // resume does not silently restart the track from 0.
            savedPositionMs =
                item.positionMs > 0 ? item.positionMs : song.lastPositionMs;
            try {
              final crashSnapshot = await PositionCrashGuard.readSnapshot();
              if (crashSnapshot != null &&
                  crashSnapshot.songId == item.songId) {
                final preferCrash =
                    await PositionCrashGuard.shouldPreferCrashGuard(
                        savedPositionMs);
                if (preferCrash || crashSnapshot.positionMs > savedPositionMs) {
                  savedPositionMs = crashSnapshot.positionMs;
                }
              } else {
                final recovery = await _readCrashPositionRecovery();
                if (recovery != null && recovery['songId'] == item.songId) {
                  final recPos = (recovery['positionMs'] as num?)?.toInt() ?? 0;
                  if (recPos > savedPositionMs) {
                    savedPositionMs = recPos;
                  }
                }
              }
            } catch (_) {}
          }
        }
      }

      if (songs.isNotEmpty) {
        if (isStale()) return;
        _songs = songs;
        _currentIndex = targetIndex.clamp(0, songs.length - 1);
        final currentSong = _songs[_currentIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(currentSong);
        if (_playGeneration != restoreGen) return;
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
        if (_playGeneration != restoreGen) return;
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

  int _failedCrossfadeClaims = 0;
  bool _crossfadeStartInFlight = false;

  Future<void> _startCrossfade(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= _songs.length) return;
    if (_crossfadeManager.isCrossfading || _crossfadeStartInFlight) return;
    _crossfadeStartInFlight = true;
    if (!await _tripleBufferPipeline.claimInactive(PlayerClaim.crossfade)) {
      _crossfadeStartInFlight = false;
      _failedCrossfadeClaims++;
      if (_failedCrossfadeClaims >= 3) {
        _failedCrossfadeClaims = 0;
        await playSongAt(nextIndex);
      }
      return;
    }
    _failedCrossfadeClaims = 0;
    try {
      return await _crossfadeManager.protect(() async {
        if (_crossfadeManager.isCrossfading) return;
        if (nextIndex < 0 || nextIndex >= _songs.length) return;
        _crossfadeManager.beginCrossfade(nextIndex);
        final currentFadeId = _crossfadeManager.nextFadeId();

        final initialActiveVolume = _calculateReplayGainVolume(currentSong);
        _preCrossfadeVolume = initialActiveVolume;
        try {
          final nextSong = _songs[nextIndex];
          final songId = nextSong.id;
          final fastArtUri = nextSong.artworkUri != null
              ? Uri.tryParse(nextSong.artworkUri!)
              : (nextSong.remoteArtworkUrl != null
                  ? Uri.tryParse(nextSong.remoteArtworkUrl!)
                  : ArtworkUriResolver.getCachedArtworkUri(songId));
          if (!_songs.any((s) => s.id == songId)) return;
          ArtworkUriResolver.resolveArtworkUri(nextSong).then((artUri) {
            if (artUri != null &&
                artUri != fastArtUri &&
                _crossfadeManager.currentFadeId == currentFadeId &&
                _currentIndex == nextIndex) {
              mediaItem
                  .add(PulsrAudioHandler._songToMediaItem(nextSong, artUri));
            }
          }).catchError((_) {});
          if (!_songs.any((s) => s.id == songId)) return;
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
          _tripleBufferPipeline.clearPreload();
          if (!_songs.any((s) => s.id == songId)) return;

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
            await _inactivePlayer
                .play()
                .timeout(const Duration(milliseconds: 1000));
          } catch (_) {
            // FIX-#6: The fallback play() must also have a timeout — without one,
            // a hung native decoder deadlocks the crossfade engine indefinitely.
            try {
              await _inactivePlayer
                  .play()
                  .timeout(const Duration(milliseconds: 3000));
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
            if (ps == ProcessingState.ready ||
                ps == ProcessingState.buffering) {
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

          // Arbitrate the transition now that the incoming player is ready
          // (item 9). The arbiter clamps the effective fade (BPM alignment can
          // make it longer than the base duration) to `remaining - 0.5s` so the
          // ramp can never outlast the outgoing track and leave it to hit
          // ProcessingState.completed mid-fade (one-sided fade); it also falls
          // back to a hard switch when < 1s of the track remains. The incoming-
          // buffer guard is intentionally bypassed (null): streaming players
          // buffer incrementally and never reach the 50%-ahead the arbiter's
          // fraction guard expects — readiness is already enforced above by
          // _canStartCrossfade.
          final outDuration = _activePlayer.duration;
          final remaining = (outDuration != null && outDuration > Duration.zero)
              ? outDuration - _activePlayer.position
              : Duration.zero;
          final decision = CrossfadeManager.arbitrateTransition(
            configuredCrossfade: _crossfadeManager.effectiveFadeDuration(
              trackId: nextSong.id.toString(),
            ),
            remainingTrackDuration: remaining,
            isSameDecoderConfig: true,
            isRepeatOne: _activePlayer.loopMode == LoopMode.one,
            nextTrackBufferedFraction: null,
          );
          if (decision.isGapless) {
            ErrorLogger.log(
                'Crossfade arbitration chose a hard transition: ${decision.reason}',
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
          final fadeDuration = decision.effectiveDuration;

          final targetNextVolume = _calculateReplayGainVolume(nextSong);
          final isRepeatOne = _activePlayer.loopMode == LoopMode.one;

          // Pre-buffer track N+2 into _prefetchPlayer during crossfade window
          // (gated on depth>=2 so minimal-bucket / critical-battery skips it).
          final nextNextIndex = _getNextIndex(peek: true);
          if (_preloadCountForCurrentBucket >= 2 &&
              nextNextIndex != null &&
              nextNextIndex >= 0 &&
              nextNextIndex < _songs.length) {
            unawaited(
                _tripleBufferPipeline.prefetchAhead(_songs[nextNextIndex]));
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

          final resolvedIndex = _songs.indexWhere((s) => s.id == songId);
          if (resolvedIndex == -1) {
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
          _currentIndex = resolvedIndex;
          _savedQueueIndex = resolvedIndex;

          final currentSessionId =
              _isPlayerAActive ? _playerASessionId : _playerBSessionId;
          _audioSessionIdRouter.handleSessionId(
              currentSessionId ?? _activePlayer.androidAudioSessionId);
          final initialArtUri =
              ArtworkUriResolver.getCachedArtworkUri(songId) ?? fastArtUri;
          mediaItem
              .add(PulsrAudioHandler._songToMediaItem(nextSong, initialArtUri));
          ArtworkUriResolver.resolveArtworkUri(nextSong).then((artUri) {
            if (artUri != null &&
                artUri != initialArtUri &&
                _crossfadeManager.currentFadeId == currentFadeId &&
                currentSong?.id == songId) {
              mediaItem
                  .add(PulsrAudioHandler._songToMediaItem(nextSong, artUri));
            }
          }).catchError((_) {});
          _planNextStreamResolution();
          _repository.recordPlayHistory(nextSong.id);
          _broadcastState(_activePlayer.playbackEvent);

          // Clear the native gain curve BEFORE stop() while the player is still
          // active on the platform channel, then allow the pipeline to drain before stop.
          // Re-read outgoing player reference in case of mid-delay skip or swap (M-05).
          final outgoing = _inactivePlayer;
          try {
            await outgoing.dspClearGainCurve();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 80));
          final outgoingAfterDelay = _inactivePlayer;
          try {
            await outgoingAfterDelay.stop();
          } catch (_) {}
          await outgoingAfterDelay.setVolume(_volume);
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
            if (nextIndex >= 0 && nextIndex < _songs.length) {
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
      _crossfadeStartInFlight = false;
      _tripleBufferPipeline.releaseInactive(PlayerClaim.crossfade);
    }
  }

  int? _getNextIndex({bool peek = false}) {
    return _queueStateMachine.getNextIndex(
      peek: peek,
      shuffleModeEnabled: _activePlayer.shuffleModeEnabled,
      loopMode: _activePlayer.loopMode,
    );
  }

  int? getPreviousIndex({bool forcePrevious = false}) {
    return _queueStateMachine.getPreviousIndex(
      forcePrevious: forcePrevious,
      position: _activePlayer.position,
      shuffleModeEnabled: _activePlayer.shuffleModeEnabled,
      loopMode: _activePlayer.loopMode,
    );
  }

  @override
  void _broadcastState(PlaybackEvent event) {
    if (event.processingState == ProcessingState.ready &&
        _activePlayer.playing) {
      _pendingPlaybackStart = false;
    }
    // Player events are already filtered to the active player by
    // setupPlayerListeners' isTargetActive(); the previous identical() guard
    // here compared _activePlayer against its own definition and was always
    // false (dead code).
    // If a gapless load is actively preparing a new track for user playback,
    // ignore transient idle/stop events emitted by stop() before setAudioSources.
    if (_gaplessMode && !_gaplessLoaded && _gaplessTargetIndex != null) {
      // A gapless load that stalls or fails before it sets _gaplessLoaded would
      // otherwise suppress EVERY broadcast indefinitely and freeze the
      // notification. Bound the suppression: once it has been active too long,
      // clear the stuck target and fall through so state flows again. The
      // load's own failure paths reset the target immediately (see
      // _loadGaplessQueue / playSongAt); this is the backstop for any they miss.
      final since = _gaplessSuppressionSince ??= DateTime.now();
      if (DateTime.now().difference(since) < const Duration(seconds: 8)) {
        final tEarly = DateTime.now().toIso8601String();
        ErrorLogger.addBreadcrumb(
          '[$tEarly] _broadcastState: early-return (gapless loading target=$_gaplessTargetIndex)',
          category: 'AudioHandler',
          data: {
            'ts': tEarly,
            'gaplessMode': _gaplessMode,
            'gaplessLoaded': _gaplessLoaded,
            'gaplessTargetIndex': _gaplessTargetIndex,
          },
        );
        return;
      }
      ErrorLogger.log(
        'Gapless load suppression exceeded 8s without completing; clearing '
        'stuck target=$_gaplessTargetIndex to unfreeze the notification',
        category: 'AudioHandler',
      );
      _gaplessTargetIndex = null;
      _gaplessSuppressionSince = null;
    } else {
      _gaplessSuppressionSince = null;
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
    final isPodcast = activeSong != null &&
        PlaybackBookmarkStore.shouldBookmark(
          durationMs: activeSong.durationMs,
          genre: activeSong.genre,
          album: activeSong.album,
        );
    final hasPrevious = _hasQueueNeighbour(forward: false);
    final hasNext = _hasQueueNeighbour(forward: true);

    final controls = <MediaControl>[
      if (isPodcast)
        MediaControl.rewind
      else if (hasPrevious)
        MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (isPodcast)
        MediaControl.fastForward
      else if (hasNext)
        MediaControl.skipToNext,
      if (activeSong != null)
        activeSong.isFavorite
            ? PulsrAudioHandler.controlFavorite
            : PulsrAudioHandler.controlUnfavorite,
      if (hasPrevious || hasNext) ...[
        _activePlayer.shuffleModeEnabled
            ? PulsrAudioHandler.controlShuffleOn
            : PulsrAudioHandler.controlShuffleOff,
        _activePlayer.loopMode == LoopMode.one
            ? PulsrAudioHandler.controlRepeatOne
            : (_activePlayer.loopMode == LoopMode.all
                ? PulsrAudioHandler.controlRepeatAll
                : PulsrAudioHandler.controlRepeatOff),
      ],
    ];
    final processingState = const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_activePlayer.processingState] ??
        AudioProcessingState.ready;

    final tEmit = DateTime.now().toIso8601String();
    ErrorLogger.addBreadcrumb(
      '[$tEmit] _broadcastState: emit playing=$isPlaying controls=${controls.map((c) => c.label).toList()}',
      category: 'AudioHandler',
      data: {
        'ts': tEmit,
        'playing': isPlaying,
        'controls': controls.map((c) => c.label).toList(),
        'processingState': processingState.name,
      },
    );

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
          for (var i = 0; i < math.min(3, controls.length); i++) i,
        ],
        processingState: processingState,
        playing: isPlaying,
        // Report the latency-compensated position so the notification shade's
        // scrubber matches what the user actually hears (matches the in-app
        // UI/lyrics, which already use compensatedPosition). Clamp to zero:
        // compensation can push it slightly negative near track start.
        updatePosition: compensatedPosition.isNegative
            ? Duration.zero
            : compensatedPosition,
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
    return _queueStateMachine.hasQueueNeighbour(
      forward: forward,
      shuffleModeEnabled: _activePlayer.shuffleModeEnabled,
      loopMode: _activePlayer.loopMode,
      gaplessMode: _gaplessMode,
      gaplessLoaded: _gaplessLoaded,
      playerHasNext: _activePlayer.hasNext,
      playerHasPrevious: _activePlayer.hasPrevious,
    );
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
    if (index < 0 || index >= _songs.length) return;
    _pendingPlaybackStart = false;
    final generation = ++_playGeneration;
    final song = _songs[index];
    _currentIndex = index;
    _pendingLazyPosition = null;

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = PulsrAudioHandler._songToMediaItem(song, fastArtUri);
    mediaItem.add(item);

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
    final source = await _resolveAudioSource(song, item);
    if (await _isGenerationCancelled(generation)) return;
    await _activePlayer.setAudioSource(source,
        initialPosition: initialPosition ?? Duration.zero, preload: false);
    if (await _isGenerationCancelled(generation)) return;
    _broadcastState(_activePlayer.playbackEvent);
  }

  // --- QUEUE & PLAYBACK COMMANDS ---
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0,
      Duration? initialPosition,
      bool autoPlay = true}) async {
    _pendingPlaybackStart = songs.isNotEmpty && autoPlay;
    if (songs.isEmpty) {
      _songs = [];
      _currentIndex = 0;
      _queueDirty = true;
      _gaplessLoaded = false;
      // A stale target keeps _broadcastState suppressed (up to 8s) after the
      // queue is cleared, and stale history points at tracks that are gone.
      _gaplessTargetIndex = null;
      _shuffleHistory.clear();
      _pendingLazyPosition = null;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    _isManualSkip = true;
    // Warm artwork for the next two tracks so the notification/queue UI is
    // ready. (The former YouTube "warm" blocks here were empty no-ops.)
    final targetIdx = initialIndex.clamp(0, songs.length - 1);
    for (int i = 1; i <= 2; i++) {
      final lookaheadIdx = targetIdx + i;
      if (lookaheadIdx < songs.length) {
        unawaited(ArtworkUriResolver.resolveArtworkUri(songs[lookaheadIdx]));
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
      _gaplessStopwatch
        ..reset()
        ..start();
      _consecutiveFailures = 0;
      final song = _songs[targetIndex];
      final fastArtUri =
          song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
      mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
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

    _publishQueueWithArtwork();

    if (_gaplessMode) {
      await _loadGaplessQueue(
          initialPosition: initialPosition, preload: autoPlay);
    } else {
      if (autoPlay) {
        await playSongAt(_currentIndex, initialPosition: initialPosition);
      } else {
        await _loadSongPaused(_currentIndex, initialPosition: initialPosition);
      }
    }
  }

  void _publishQueueWithArtwork({int windowSize = 5}) {
    final songsSnapshot = List<SongsTableData>.from(_songs);
    final currentIdx = _currentIndex;
    final mediaItems =
        songsSnapshot.map(PulsrAudioHandler._songToMediaItem).toList();
    queue.add(mediaItems);

    unawaited(() async {
      if (songsSnapshot.isEmpty) return;
      final start =
          (currentIdx - windowSize).clamp(0, songsSnapshot.length - 1);
      final end = (currentIdx + windowSize).clamp(0, songsSnapshot.length - 1);
      bool anyResolved = false;
      for (int i = start; i <= end; i++) {
        final song = songsSnapshot[i];
        if (ArtworkUriResolver.getCachedArtworkUri(song.id) == null) {
          final uri = await ArtworkUriResolver.resolveArtworkUri(song);
          if (uri != null) anyResolved = true;
        }
      }
      if (anyResolved && _songs.length == songsSnapshot.length) {
        queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
      }
    }());
  }

  void swapReconciledSong(int oldId, SongsTableData newSong) {
    final idx = _songs.indexWhere((s) => s.id == oldId);
    if (idx != -1) {
      _songs[idx] = newSong;
      _publishQueueWithArtwork();
      if (_currentIndex == idx) {
        final fastArtUri = newSong.artworkUri != null
            ? Uri.tryParse(newSong.artworkUri!)
            : null;
        mediaItem.add(PulsrAudioHandler._songToMediaItem(newSong, fastArtUri));
      }
    }
  }

  /// Mirrors an in-app favorite change into the handler's queue and pushes a
  /// fresh metadata/control update so the media notification's favorite icon
  /// and the in-app queue stay in lockstep (no DB/notification divergence).
  void updateFavorite(int songId, bool isFavorite) {
    final idx = _songs.indexWhere((s) => s.id == songId);
    if (idx == -1) return;
    final song = _songs[idx];
    if (song.isFavorite == isFavorite) return;
    _songs[idx] = song.copyWith(isFavorite: isFavorite);
    _publishQueueWithArtwork();
    if (_currentIndex == idx) {
      final fastArtUri =
          song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
      mediaItem
          .add(PulsrAudioHandler._songToMediaItem(_songs[idx], fastArtUri));
      // Rebuild controls so the notification heart reflects the new state now
      // instead of on the next unrelated playback-state broadcast.
      _broadcastState(_activePlayer.playbackEvent);
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
    _pendingPlaybackStart = preload;
    final songsSnapshot = List<SongsTableData>.from(_songs);
    final generation = ++_playGeneration;
    _gaplessLoadGeneration++;
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
    // Snapshot: no interleaved stream event may change the load target.
    final targetIndex = _currentIndex.clamp(0, songsSnapshot.length - 1);
    _lastGaplessIndex = targetIndex;
    _gaplessTargetIndex = targetIndex;
    _gaplessTargetReached = false;
    _gaplessStopwatch
      ..reset()
      ..start();

    final song = songsSnapshot[targetIndex];
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(PulsrAudioHandler._songToMediaItem(song, fastArtUri));
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

    try {
      // Soft-landing fade so the stop doesn't click, then cleanly stop any
      // existing playing source to release hanging native sockets.
      // Bounded, not Future.wait over the whole queue: resolving every row at
      // once (file-exists checks, DB lookups, DSD/MQA decode setup) stalled
      // big libraries, and one throwing row failed the entire load.
      final sources = await _boundedParallelMap<SongsTableData, AudioSource>(
        songsSnapshot,
        (queuedSong) async {
          final art = queuedSong.artworkUri != null
              ? Uri.tryParse(queuedSong.artworkUri!)
              : null;
          final tag = PulsrAudioHandler._songToMediaItem(queuedSong, art);
          try {
            return await _resolveAudioSource(queuedSong, tag);
          } catch (e, st) {
            // Online rows keep the original behaviour (the error classifier
            // below handles them). A broken local decoder path degrades to a
            // plain source so only that track can fail, not the whole queue.
            if (queuedSong.source == SongSource.youtube) rethrow;
            ErrorLogger.log(
                'Gapless child resolve failed for "${queuedSong.title}"; '
                'using plain source',
                error: e,
                stackTrace: st,
                category: 'AudioHandler');
            return _createAudioSource(queuedSong, tag);
          }
        },
        concurrency: 8,
      );
      if (await _isGenerationCancelled(generation)) return;
      try {
        await _activePlayer.stop();
      } catch (_) {}

      if (await _isGenerationCancelled(generation)) return;
      await _activePlayer.setAudioSources(sources,
          initialIndex: targetIndex,
          initialPosition: initialPosition ?? Duration.zero,
          preload: preload);
      if (await _isGenerationCancelled(generation)) return;

      try {
        _latencyTracker?.markStage(PlaybackStage.sourceSet);
      } catch (_) {}
      _gaplessLoaded = true;
      _lastGaplessIndex = targetIndex;
      _gaplessStopwatch
        ..reset()
        ..start();
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
      // This load failed before setting _gaplessLoaded; clear the target so the
      // _broadcastState suppression lifts immediately and the notification does
      // not freeze (item 13).
      _gaplessTargetIndex = null;
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
      if (PulsrAudioHandler.shouldHaltFailureCascade(
        consecutiveFailures: _consecutiveFailures,
        rapidGaplessChanges: 0,
        queueLength: _songs.length,
      )) {
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
      // This load failed before setting _gaplessLoaded; clear the target so the
      // _broadcastState suppression lifts immediately (item 13).
      _gaplessTargetIndex = null;
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
        if (_gaplessLoadGeneration > 0) {
          debugPrint(
              '[AudioHandler] Ignoring spurious gapless index event: $index (target was $_gaplessTargetIndex, gen: $_gaplessLoadGeneration)');
          return;
        }
      }
    }

    // If user paused, kill the loop immediately.
    if (!_activePlayer.playing) {
      _consecutiveFailures = 0;
      return;
    }
    if (_isManualSkip) {
      _isManualSkip = false;
      // Decay consecutive failure counter by 1 on manual skip (M-02) so user interaction
      // rewards the failure budget without totally erasing error-tracking.
      if (_consecutiveFailures > 0) {
        _consecutiveFailures--;
      }
    }

    _lastGaplessIndex = index;
    _currentIndex = index;
    _savedQueueIndex = index;
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

  /// The single track the NEXT advance will actually play in the non-gapless
  /// shuffle case — the state machine's pre-committed pick (see
  /// [PlaybackQueueStateMachine.peekNextIndex]). The pre-resolver and preload
  /// scheduler warm this instead of the linear neighbour (which shuffle skips)
  /// or an independent random guess (which the advance would not match).
  ///
  /// Null when gapless (the shuffleIndices concat order already drives warming),
  /// when not shuffling, or when no valid next exists. Peeking is idempotent and
  /// does not record shuffle history, so repeated calls return the SAME pick the
  /// real advance later consumes.
  @override
  SongsTableData? _nonGaplessShuffleNextSong() {
    if (_gaplessMode || !_activePlayer.shuffleModeEnabled) return null;
    final idx = _getNextIndex(peek: true);
    if (idx == null || idx < 0 || idx >= _songs.length) return null;
    return _songs[idx];
  }

  void _planNextStreamResolution() {
    if (_songs.isEmpty) return;
    _streamPreResolver.onTrackStarted(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
      // Thread the real gapless shuffle order so the shuffle successor is warmed
      // instead of the linear currentIndex+1 (item 7). Only meaningful in
      // gapless mode, where the concat carries the whole queue; the crossfade
      // engine holds a single source on the active player (shuffleIndices=[0]).
      shuffleIndices: (_activePlayer.shuffleModeEnabled && _gaplessMode)
          ? _activePlayer.shuffleIndices
          : null,
      // Non-gapless shuffle: pin the pre-committed next pick so the warmed track
      // is exactly the one the next advance plays (the state machine now hands
      // peek and advance the SAME index) instead of the linear fallback.
      explicitNextSong: _nonGaplessShuffleNextSong(),
    );
  }

  Future<void> playSongAt(int index, {Duration? initialPosition}) async {
    if (index < 0 || index >= _songs.length) return;
    _pendingPlaybackStart = true;
    cancelPrefetches();
    // playSongAt takes over the active player with a single source; clear any
    // in-flight gapless load target so a stalled one cannot keep
    // _broadcastState suppressed and freeze the notification (item 13).
    _gaplessTargetIndex = null;
    // A YouTube resolve below can await for seconds; a second skip during that
    // window must win. Capture a generation token FIRST so a pre-resolve
    // failure can bail without touching current playback at all.
    final generation = ++_playGeneration;
    final song = _songs[index];
    _streamPreResolver.onTrackEnqueuedOrTapped(song);

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

    // Resolve high-res artwork in background without blocking audio source loading
    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null &&
          artUri != fastArtUri &&
          generation == _playGeneration &&
          currentSong?.id == song.id) {
        mediaItem.add(PulsrAudioHandler._songToMediaItem(song, artUri));
      }
    }).catchError((_) {});

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
      final source = await _resolveAudioSource(song, item);
      if (await _isGenerationCancelled(generation)) return;
      await _activePlayer.setAudioSource(source,
          initialPosition: initialPosition ?? Duration.zero);
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
    Future<void> halt() async {
      _consecutiveFailures = 0;
      // Clear the autoplay intent too, or a later engine switch would think
      // playback was requested and start the player on its own.
      _pendingPlaybackStart = false;
      try {
        await _activePlayer.pause();
      } catch (_) {}
      _broadcastState(_activePlayer.playbackEvent);
    }

    // User paused during the failure chain -> never auto-resume/skip.
    // `playing` alone is not a reliable signal: playSongAt pauses the player
    // itself during teardown, so a failure while loading a tapped/skipped
    // track saw playing == false and never skipped. A pending start means
    // the user still wants playback.
    if (!_activePlayer.playing && !_pendingPlaybackStart) {
      await halt();
      return;
    }
    if (fatal) {
      await halt();
      return;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
      if (!_errorSubject.isClosed) {
        _errorSubject.add('Playback failed for consecutive tracks. Stopping.');
      }
      await halt();
    } else {
      await skipToNext();
    }
  }

  // Abstract contract supplied by the composing PulsrAudioHandler (same
  // library). Declaring these here keeps the mixin stateless and lets the
  // analyser type-check each mixin against the host's private members.
  @override
  AudioPlayer get _activePlayer;

  AudioSessionIdRouter get _audioSessionIdRouter;

  Future<List<R>> _boundedParallelMap<T, R>(
    List<T> items,
    Future<R> Function(T) mapper, {
    int concurrency = 6,
  });

  double _calculateReplayGainVolume(SongsTableData? song);

  @override
  int get _consecutiveFailures;
  @override
  set _consecutiveFailures(int value);

  @override
  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag);

  @override
  CrossfadeManager get _crossfadeManager;

  @override
  int get _currentIndex;
  set _currentIndex(int value);

  @override
  StreamController<String> get _errorSubject;

  Stopwatch get _gaplessStopwatch;

  bool get _gaplessLoaded;
  set _gaplessLoaded(bool value);

  @override
  bool get _gaplessMode;

  int? get _gaplessTargetIndex;
  set _gaplessTargetIndex(int? value);

  bool get _gaplessTargetReached;
  set _gaplessTargetReached(bool value);

  DateTime? get _gaplessSuppressionSince;
  set _gaplessSuppressionSince(DateTime? value);

  int get _generationCounter;
  set _generationCounter(int value);

  @override
  AudioPlayer get _inactivePlayer;

  bool get _isManualSkip;
  set _isManualSkip(bool value);

  bool get _isPlayerAActive;
  set _isPlayerAActive(bool value);

  PlaybackLatencyTracker? get _latencyTracker;

  void notifySleepTrackCompleted();

  double get _pitch;

  int get _playGeneration;
  bool get _pendingPlaybackStart;
  set _pendingPlaybackStart(bool value);
  set _playGeneration(int value);

  int? get _playerASessionId;

  int? get _playerBSessionId;

  StreamController<Duration> get _positionSubject;

  @override
  int get _preloadCountForCurrentBucket;

  @override
  IMusicRepository get _repository;

  void _saveCurrentPosition();

  PlaybackQueueStateMachine get _queueStateMachine;

  List<int> get _shuffleHistory;

  @override
  List<SongsTableData> get _songs;
  set _songs(List<SongsTableData> value);

  StreamPreResolver get _streamPreResolver;

  TripleBufferPipeline get _tripleBufferPipeline;

  double get _volume;

  @override
  void cancelPrefetches();

  Duration get compensatedPosition;

  @override
  SongsTableData? get currentSong;

  set _pendingLazyPosition(Duration? value);

  set _preCrossfadeVolume(double? value);

  set _queueDirty(bool value);

  set _lastGaplessIndex(int value);

  set _savedQueueIndex(int value);

  int get _gaplessLoadGeneration;
  set _gaplessLoadGeneration(int value);
}
