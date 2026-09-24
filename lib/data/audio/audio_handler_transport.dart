// ignore_for_file: unused_element, unused_element_parameter
part of 'audio_handler.dart';

mixin PulsrAudioTransport on BaseAudioHandler {
  @override
  Future<void> play() {
    _userPlaybackInitiated = true;
    unawaited(() async {
      try {
        final s = await AudioSession.instance;
        await s.setActive(true);
      } catch (_) {}
    }());
    ErrorLogger.addBreadcrumb('Playback started', category: 'player');
    // A restored YouTube session in the crossfade engine is left with no source
    // loaded (see restoreLastPlaybackSession); resolve and start it on the first
    // play. The gapless engine instead sets a non-preloaded concat at restore,
    // so play() below prepares and starts it lazily with no special-casing.
    final pending = _pendingLazyPosition;
    if (pending != null && currentSong != null) {
      _pendingLazyPosition = null;
      if (!_gaplessMode) {
        return playSongAt(_currentIndex, initialPosition: pending);
      } else if (!_gaplessLoaded) {
        return _loadGaplessQueue(initialPosition: pending, preload: true);
      }
    }
    final generation = _playGeneration;
    final player = _activePlayer;
    try {
      player.dspClearGainCurve().catchError((_) => false);
    } catch (_) {}
    // A finished track is parked in `completed` at its end; play() alone will
    // not restart it (which is why skipToNext/skipToPrevious seek to zero before
    // playing at end-of-queue). Seek to the head first so an explicit play — the
    // resume tap on the finished song, togglePlayPause, or the notification /
    // widget play button — replays it instead of no-opping in `completed`.
    // A merely paused (ready) track is untouched, so it still resumes in place.
    if (player.processingState == ProcessingState.completed) {
      return () async {
        try {
          await player.seek(Duration.zero);
        } catch (_) {}
        final f = player.play();
        _scheduleFadeInConvergenceGuard(player, generation);
        _broadcastState(player.playbackEvent);
        await f;
      }();
    }
    final playFuture = player.play();
    _scheduleFadeInConvergenceGuard(player, generation);
    _broadcastState(player.playbackEvent);
    return playFuture;
  }

  @override
  Future<void> pause() async {
    // A deliberate pause invalidates any pending interruption snapshot so a
    // later call can still pause us (B-1); the previous code only cleared the
    // "was playing" half, leaving the active flag set.
    _interruption.onUserPause();
    ErrorLogger.addBreadcrumb('Playback paused', category: 'player');
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _preCrossfadeVolume ?? _volume);
    _saveCurrentPosition();
    unawaited(saveCurrentPositionImmediate());
    // If an online source is still being fetched/loaded (the track is not
    // playable yet), invalidate the in-flight load cycle so a late resolve — or
    // the play() at the end of playSongAt — cannot start playback after the
    // user paused. The position is remembered so a later play() re-runs the
    // cycle (re-fetches) instead of silently doing nothing.
    final playerState = _activePlayer.processingState;
    final stillLoading = playerState == ProcessingState.loading ||
        playerState == ProcessingState.buffering ||
        playerState == ProcessingState.idle;
    if (stillLoading) {
      _playGeneration++;
      cancelPrefetches();
      _pendingLazyPosition = _activePlayer.position;
    }
    await _activePlayer.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seek to ${position.inSeconds}s',
        category: 'player');
    try {
      unawaited(HapticFeedback.selectionClick());
    } catch (_) {
      // Haptics are best-effort across platforms
    }
    // Optimistic UI: emit locally first so the slider feels instant,
    // then debounce the backend call to avoid jitter during scrubbing.
    // NOTE: PlayerCubit already throttles scrub floods (100ms). This layer
    // only coalesces sub-60ms bursts, so a discrete tap passes through a
    // single layer, not two stacked 100ms windows.
    _positionSubject.add(position);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSeekMs < 60) {
      _pendingSeekPosition = position;
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer =
          Timer(const Duration(milliseconds: 60), () {
        final pending = _pendingSeekPosition;
        _pendingSeekPosition = null;
        if (pending != null) {
          _performSeek(pending).catchError((Object e, StackTrace st) {
            ErrorLogger.log('Debounced seek failed',
                error: e, stackTrace: st, category: 'AudioHandler');
          });
        }
      });
      return;
    }
    _lastSeekMs = now;
    await _performSeek(position);
  }

  /// Direct seek without debounce, for discrete user intents (tap-to-seek,
  /// skip-to-previous-restart). The cubit already throttles scrub floods, so
  /// routing discrete seeks here avoids the double 100ms window stacking.
  Future<void> seekDirect(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seekDirect to ${position.inSeconds}s',
        category: 'player');
    _positionSubject.add(position);
    _lastSeekMs = DateTime.now().millisecondsSinceEpoch;
    _pendingSeekPosition = null;
    _seekDebounceTimer?.cancel();
    await _performSeek(position);
  }

  Future<void> _performSeek(Duration position) async {
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    try {
      await _activePlayer.seek(position);
    } catch (_) {
      // Roll back to the last known good position on failure.
      _positionSubject.add(_activePlayer.position);
      rethrow;
    }
    _positionSubject.add(position);
    _saveCurrentPosition();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    // A track that naturally reached its end reports playing == false with
    // processingState == completed. The user was listening to it, so selecting
    // or swiping to another queue item must auto-play rather than load paused.
    // Mirrors the same guard in skipToNext/skipToPrevious; without it the
    // mini-player carousel swipe after a track ends parks the new song paused.
    final wasPlaying = _activePlayer.playing ||
        _activePlayer.processingState == ProcessingState.completed;
    await loadQueue(_songs, initialIndex: index, autoPlay: wasPlaying);
  }

  @override
  Future<void> skipToNext() async {
    ErrorLogger.addBreadcrumb('Playback skipToNext', category: 'player');
    try {
      unawaited(HapticFeedback.lightImpact());
    } catch (_) {
      // Haptics are best-effort across platforms
    }
    // Invalidate stale prefetch completions; the manual playSongAt path below
    // captures its own _playGeneration token (no double-bump here).
    cancelPrefetches();
    _isManualSkip = true;
    // A headset/double-press storm must never queue overlapping skips: each
    // skip bumps the generation so a slow YouTube resolve from the previous
    // skip bails instead of clobbering the new track.
    // A track that naturally completed has playing == false and
    // processingState == completed. The user was listening to it, so the
    // next track must auto-play instead of loading paused.
    final wasPlaying = _activePlayer.playing ||
        _activePlayer.processingState == ProcessingState.completed;

    try {
      if (_crossfadeManager.isCrossfading) {
        await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
            restoreVolume: _volume);
      }
      if (_gaplessMode && _gaplessLoaded) {
        // Native advance: invalidate any in-flight manual playSongAt resolve so
        // a slow YouTube URL fetch cannot clobber the new current item.
        _playGeneration++;
        if (_activePlayer.hasNext) {
          await _activePlayer.seekToNext();
          if (wasPlaying) {
            await _activePlayer.play();
          }
        } else if (_activePlayer.loopMode == LoopMode.all &&
            _songs.isNotEmpty) {
          await _activePlayer.seek(Duration.zero, index: 0);
          if (wasPlaying) {
            await _activePlayer.play();
          }
        } else {
          // Native concat says "no next" — but it can desync from _songs
          // after queue edits. Fall back to the Dart queue before giving up,
          // otherwise Next on a valid queue pauses + dismisses the
          // notification ("no action").
          final fallbackIdx = _getNextIndex();
          if (fallbackIdx != null) {
            if (wasPlaying) {
              await playSongAt(fallbackIdx);
            } else {
              await _loadSongPaused(fallbackIdx);
            }
          } else {
            // True end-of-queue: restart the current track instead of
            // pausing. Pausing here drops the foreground service (and with
            // stopForegroundOnPause the notification) while the user
            // explicitly asked to keep listening.
            await _activePlayer.seek(Duration.zero);
            if (wasPlaying && _activePlayer.loopMode != LoopMode.off) {
              await _activePlayer.play();
            }
            _broadcastState(_activePlayer.playbackEvent);
          }
        }
        return;
      }

      final nextIdx = _getNextIndex();
      if (nextIdx != null) {
        if (wasPlaying) {
          await playSongAt(nextIdx);
        } else {
          await _loadSongPaused(nextIdx);
        }
      } else {
        // True end-of-queue: same no-dismiss policy as the gapless path.
        await _activePlayer.seek(Duration.zero);
        if (wasPlaying && _activePlayer.loopMode != LoopMode.off) {
          await _activePlayer.play();
        }
        _broadcastState(_activePlayer.playbackEvent);
      }
    } catch (e, st) {
      // Never let a skip kill the service silently: log, keep the queue
      // position, and re-broadcast so the notification stays alive.
      ErrorLogger.log('skipToNext failed',
          error: e, stackTrace: st, category: 'AudioHandler');
      try {
        _broadcastState(_activePlayer.playbackEvent);
      } catch (_) {}
    }
  }

  @override
  Future<void> skipToPrevious() async {
    ErrorLogger.addBreadcrumb('Playback skipToPrevious', category: 'player');
    try {
      unawaited(HapticFeedback.lightImpact());
    } catch (_) {
      // Haptics are best-effort across platforms
    }
    cancelPrefetches();
    _isManualSkip = true;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;

    final now = DateTime.now();
    final isDoubleTap = _lastPreviousTapTime != null &&
        now.difference(_lastPreviousTapTime!).inMilliseconds < 2500;
    _lastPreviousTapTime = now;
    // A track that reached the end sits in `completed` with `playing == false`
    // and its position pinned at the duration. Pressing previous on it should
    // replay it, not leave it parked as "finished & paused": the restart-current
    // branches below only call play() when this is true, and seek(0) alone does
    // not clear the `completed` state. Treating a finished track as "was playing"
    // makes previous resume it (and clear completed). This is intentionally
    // scoped to the user-driven skipToPrevious — the auto-advance skipToNext must
    // stay paused at end-of-queue so it doesn't loop the last track forever.
    final wasPlaying = _activePlayer.playing ||
        _activePlayer.processingState == ProcessingState.completed;

    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    }
    if (_gaplessMode && _gaplessLoaded) {
      _playGeneration++;
      if (!isDoubleTap && _activePlayer.position.inSeconds > 3) {
        await _activePlayer.seek(Duration.zero);
        if (wasPlaying) {
          await _activePlayer.play();
        }
        _saveCurrentPosition();
        return;
      }
      if (_activePlayer.hasPrevious) {
        await _activePlayer.seekToPrevious();
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else if (_activePlayer.loopMode == LoopMode.all && _songs.isNotEmpty) {
        await _activePlayer.seek(Duration.zero, index: _songs.length - 1);
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else {
        await _activePlayer.seek(Duration.zero);
        if (wasPlaying) {
          await _activePlayer.play();
        }
        _saveCurrentPosition();
      }
      return;
    }
    if (!isDoubleTap && _activePlayer.position.inSeconds > 3) {
      await _activePlayer.seek(Duration.zero);
      if (wasPlaying) {
        await _activePlayer.play();
      }
      _saveCurrentPosition();
      return;
    }
    final prevIdx = getPreviousIndex(forcePrevious: isDoubleTap);
    if (prevIdx != null) {
      if (wasPlaying) {
        await playSongAt(prevIdx);
      } else {
        await _loadSongPaused(prevIdx);
      }
    } else {
      await _activePlayer.seek(Duration.zero);
      if (wasPlaying) {
        await _activePlayer.play();
      }
      _saveCurrentPosition();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await Future.wait([
      _playerA.setShuffleModeEnabled(enable),
      _playerB.setShuffleModeEnabled(enable),
    ]);
    // In gapless mode the concat's shuffle order drives playback; reshuffle so
    // enabling shuffle actually reorders upcoming tracks (current stays put).
    if (enable && _gaplessMode && _gaplessLoaded) {
      await _activePlayer.shuffle();
    }
    // The crossfade engine draws its own random order from _getNextIndex, so no
    // native reshuffle is needed there.
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.playbackShuffle,
        shuffleMode == AudioServiceShuffleMode.all);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final LoopMode loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        LoopMode.all,
    };

    await Future.wait([
      _playerA.setLoopMode(loopMode),
      _playerB.setLoopMode(loopMode),
    ]);

    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    final persistMode = switch (repeatMode) {
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
      AudioServiceRepeatMode.one => 'one',
      _ => 'none',
    };
    await prefs.setString(PrefsKeys.playbackRepeatMode, persistMode);
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    _headsetClickCount++;
    _headsetClickTimer?.cancel();

    int windowMs = 350;
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      windowMs =
          (prefs.getInt(PrefsKeys.headsetClickWindowMs) ?? 350).clamp(150, 800);
    } catch (_) {}

    if (_headsetClickCount >= 3) {
      final count = _headsetClickCount;
      _headsetClickCount = 0;
      await _performHeadsetAction(count);
      return;
    }

    _headsetClickTimer = Timer(Duration(milliseconds: windowMs), () async {
      final count = _headsetClickCount;
      _headsetClickCount = 0;
      await _performHeadsetAction(count);
    });
  }

  Future<void> _performHeadsetAction(int count) async {
    final config = cachedHeadsetConfig ?? HeadsetControlConfig.defaults;
    final action = config.actionForCount(count);
    final seekSecs = config.seekSeconds;
    switch (action) {
      case HeadsetClickAction.playPause:
        if (_activePlayer.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case HeadsetClickAction.next:
        await skipToNext();
        break;
      case HeadsetClickAction.previous:
        await skipToPrevious();
        break;
      case HeadsetClickAction.stop:
        await pause();
        try {
          final session = await AudioSession.instance;
          await session.setActive(false);
        } catch (_) {}
        break;
      case HeadsetClickAction.seekForward:
        await seekRelative(Duration(seconds: seekSecs));
        break;
      case HeadsetClickAction.seekBackward:
        await seekRelative(Duration(seconds: -seekSecs));
        break;
      case HeadsetClickAction.none:
        break;
    }
  }

  /// Relative seek clamped to [0, duration]. Used by headset seek mapping
  /// and the `seekRelative` custom action (notification/widget long-press).
  Future<void> seekRelative(Duration offset) async {
    try {
      final pos = _activePlayer.position;
      final dur = _activePlayer.duration;
      var target = pos + offset;
      if (target < Duration.zero) target = Duration.zero;
      if (dur != null && target > dur) target = dur;
      await seek(target);
    } catch (_) {}
  }

  @override
  Future<void> rewind() async {
    await seekRelative(const Duration(seconds: -10));
  }

  @override
  Future<void> fastForward() async {
    await seekRelative(const Duration(seconds: 10));
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) await seekRelative(const Duration(seconds: -10));
  }

  @override
  Future<void> seekForward(bool begin) async {
    if (begin) await seekRelative(const Duration(seconds: 10));
  }

  double get minPlaybackSpeed =>
      _advancedSpeedEnabled ? PulsrAudioHandler._minAdvancedPlaybackSpeed : PulsrAudioHandler._minPlaybackSpeed;

  double get maxPlaybackSpeed =>
      _advancedSpeedEnabled ? PulsrAudioHandler._maxAdvancedPlaybackSpeed : PulsrAudioHandler._maxPlaybackSpeed;

  /// Enables the extended 0.1–8.0 speed range for power users.
  /// When disabled the stable 0.25–4.0 range is enforced.
  Future<void> setAdvancedSpeedEnabled(bool enabled) async {
    _advancedSpeedEnabled = enabled;
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.advancedPlaybackSpeed, enabled);
    // Re-clamp the current speed into the newly selected range so both
    // players stay in sync after the range changes.
    final current = playbackState.value.speed;
    final clamped = current.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    if (clamped != current) {
      await setSpeed(clamped);
    }
  }

  double get pitch => _pitch;

  Future<void> restorePersistedSpeed() async {
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      _advancedSpeedEnabled =
          prefs.getBool(PrefsKeys.advancedPlaybackSpeed) ?? false;
      final saved = prefs.getDouble(PrefsKeys.playbackSpeed);
      if (saved != null) {
        final clamped = saved.clamp(minPlaybackSpeed, maxPlaybackSpeed);
        await Future.wait([
          _playerA.setSpeed(clamped),
          _playerB.setSpeed(clamped),
        ]);
        playbackState.add(playbackState.value.copyWith(speed: clamped));
      }
      final savedPitch = prefs.getDouble(PrefsKeys.playbackPitch);
      if (savedPitch != null) {
        final clampedPitch = savedPitch.clamp(0.5, 2.0);
        _pitch = clampedPitch;
        await Future.wait([
          _playerA.setPitch(clampedPitch),
          _playerB.setPitch(clampedPitch),
        ]);
      }
    } catch (_) {}
  }

  Future<void> restorePersistedPitch() async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      final savedPitch = prefs.getDouble(PrefsKeys.playbackPitch) ?? 1.0;
      final clampedPitch = savedPitch.clamp(0.5, 2.0);
      _pitch = clampedPitch;
      await Future.wait([
        _playerA.setPitch(clampedPitch),
        _playerB.setPitch(clampedPitch),
      ]);
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    await Future.wait([
      _playerA.setSpeed(clamped),
      _playerB.setSpeed(clamped),
    ]);
    playbackState.add(playbackState.value.copyWith(speed: clamped));
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0);
    _pitch = clamped;
    await Future.wait([
      _playerA.setPitch(clamped),
      _playerB.setPitch(clamped),
    ]);
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackPitch, clamped);
    } catch (_) {}
  }

  Future<void> validatePlayerState() async {
    final player = _activePlayer;
    if (player.processingState == ProcessingState.idle && _songs.isNotEmpty) {
      ErrorLogger.log('Player in idle state with non-empty queue, recovering',
          category: 'AudioHandler');
      await playSongAt(_currentIndex);
    }
  }


  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (_songs.length >= PulsrAudioHandler.maxQueueSize) {
      ErrorLogger.log('Queue size limit reached (${PulsrAudioHandler.maxQueueSize})',
          category: 'AudioHandler');
      return;
    }
    final songId = int.tryParse(mediaItem.id);
    if (songId != null) {
      final existingIdx = _songs.indexWhere((s) => s.id == songId);
      if (existingIdx != -1) return;
      final songRes = await _repository.getSongById(songId);
      final song = songRes.fold((l) => null, (r) => r);
      if (song != null) {
        _songs.add(song);
        _queueDirty = true;
        if (_gaplessMode && _gaplessLoaded) {
          await _activePlayer.addAudioSource(_buildGaplessChild(song));
        }
        queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
        _saveCurrentPosition();
      }
    }
  }

  Future<void> insertNextInQueue(SongsTableData song) async {
    final existingIdx = _songs.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1) {
      if (existingIdx == _currentIndex) {
        return;
      }
      final targetSlot = (_currentIndex + 1).clamp(0, _songs.length - 1);
      if (existingIdx == targetSlot) {
        return;
      }
      await reorderQueue(
          existingIdx, targetSlot > existingIdx ? targetSlot - 1 : targetSlot);
      return;
    }

    if (_songs.length >= PulsrAudioHandler.maxQueueSize) {
      ErrorLogger.log('Queue size limit reached (${PulsrAudioHandler.maxQueueSize})',
          category: 'AudioHandler');
      return;
    }
    final insertIdx =
        _songs.isEmpty ? 0 : (_currentIndex + 1).clamp(0, _songs.length);
    _songs.insert(insertIdx, song);
    _streamPreResolver.onTrackEnqueuedOrTapped(song);
    _queueDirty = true;
    // Insert sits after the current track, so the playing index never shifts.
    if (_gaplessMode && _gaplessLoaded) {
      await _activePlayer.insertAudioSource(
          insertIdx, _buildGaplessChild(song));
    }
    queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> addToQueueEnd(SongsTableData song) async {
    final existingIdx = _songs.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1) {
      if (existingIdx == _currentIndex) {
        return;
      }
      if (existingIdx == _songs.length - 1) {
        return;
      }
      await reorderQueue(existingIdx, _songs.length - 1);
      return;
    }

    if (_songs.length >= PulsrAudioHandler.maxQueueSize) {
      ErrorLogger.log('Queue size limit reached (${PulsrAudioHandler.maxQueueSize})',
          category: 'AudioHandler');
      return;
    }
    _songs.add(song);
    _streamPreResolver.onTrackEnqueuedOrTapped(song);
    _queueDirty = true;
    if (_gaplessMode && _gaplessLoaded) {
      await _activePlayer.addAudioSource(_buildGaplessChild(song));
    }
    queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> clearQueue() async {
    if (_songs.isEmpty) return;
    final wasPlaying = _activePlayer.playing;
    if (_currentIndex >= 0 && _currentIndex < _songs.length) {
      final current = _songs[_currentIndex];
      _songs = [current];
      _currentIndex = 0;
      if (_gaplessMode && _gaplessLoaded) {
        await _loadGaplessQueue(preload: wasPlaying);
      }
    } else {
      _songs.clear();
      _currentIndex = 0;
      _gaplessLoaded = false;
      await stop();
    }
    _queueDirty = true;
    queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final wasPlayingCurrent = index == _currentIndex;
    final wasGaplessLoaded = _gaplessLoaded;
    final wasPlaying = _activePlayer.playing;

    _songs.removeAt(index);
    _queueDirty = true;

    if (_songs.isEmpty) {
      _currentIndex = 0;
      _gaplessLoaded = false;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    if (_gaplessMode) {
      if (wasPlayingCurrent) {
        // Removing the playing track changes the current song. Rebuild the
        // playlist at the clamped index so the new current starts cleanly,
        // rather than leaning on ExoPlayer's silent same-index auto-advance
        // (which would leave the notification and play history stale).
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        if (wasGaplessLoaded && _activePlayer.audioSources.isNotEmpty) {
          await _loadGaplessQueue(preload: wasPlaying);
        } else {
          final nextSong = _songs[_currentIndex];
          final fastArtUri = nextSong.artworkUri != null
              ? Uri.tryParse(nextSong.artworkUri!)
              : null;
          mediaItem.add(PulsrAudioHandler._songToMediaItem(nextSong, fastArtUri));
        }
      } else {
        if (index < _currentIndex) _currentIndex--;
        // Pre-set so the shift emit from currentIndexStream is a no-op.
        _lastGaplessIndex = _currentIndex;
        if (wasGaplessLoaded && index < _activePlayer.audioSources.length) {
          try {
            await _activePlayer.removeAudioSourceAt(index);
          } catch (e, st) {
            ErrorLogger.log(
                'Failed to remove audio source at index $index; resyncing gapless queue',
                error: e,
                stackTrace: st,
                category: 'AudioHandler');
            if (wasGaplessLoaded && _activePlayer.audioSources.isNotEmpty) {
              await _loadGaplessQueue(preload: wasPlaying);
            }
          }
        }
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
      } else if (wasPlayingCurrent) {
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        if (wasPlaying) {
          await playSongAt(_currentIndex);
        } else {
          await _loadSongPaused(_currentIndex);
        }
      }
    }
    queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _songs.indexWhere((s) => s.id.toString() == mediaItem.id);
    if (index != -1) {
      await removeQueueItemAt(index);
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _songs.length ||
        newIndex < 0 ||
        newIndex >= _songs.length) {
      return;
    }
    if (oldIndex == newIndex) return;

    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);
    _queueDirty = true;

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    // moveAudioSource() replays remove(oldIndex)+insert(newIndex) on the playlist's
    // layout, reaching the same order as _songs. Pre-set _lastGaplessIndex so a
    // shift emit for the (unchanged) current song is swallowed.
    if (_gaplessMode && _gaplessLoaded) {
      _lastGaplessIndex = _currentIndex;
      await _activePlayer.moveAudioSource(oldIndex, newIndex);
    }

    queue.add(_songs.map(PulsrAudioHandler._songToMediaItem).toList());
    _saveCurrentPosition();
  }











































































































































































































































































  // Requires: provided by the composing class (same library).
  AudioPlayer get _activePlayer;

  // Requires: provided by the composing class (same library).
  bool get _advancedSpeedEnabled;
  set _advancedSpeedEnabled(bool value);

  // Requires: provided by the composing class (same library).
  void _broadcastState(PlaybackEvent event);

  // Requires: provided by the composing class (same library).
  AudioSource _buildGaplessChild(SongsTableData song);

  // Requires: provided by the composing class (same library).
  SharedPreferences? get _cachedPrefs;
  set _cachedPrefs(SharedPreferences? value);

  // Requires: provided by the composing class (same library).
  CrossfadeManager get _crossfadeManager;

  // Requires: provided by the composing class (same library).
  int get _currentIndex;
  set _currentIndex(int value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessLoaded;
  set _gaplessLoaded(bool value);

  // Requires: provided by the composing class (same library).
  bool get _gaplessMode;

  // Requires: provided by the composing class (same library).
  int? _getNextIndex({int offset = 1, bool peek = false});

  // Requires: provided by the composing class (same library).
  int? getPreviousIndex({bool forcePrevious = false});

  // Requires: provided by the composing class (same library).
  int get _headsetClickCount;
  set _headsetClickCount(int value);

  // Requires: provided by the composing class (same library).
  Timer? get _headsetClickTimer;
  set _headsetClickTimer(Timer? value);

  // Requires: provided by the composing class (same library).
  AudioPlayer get _inactivePlayer;

  // Requires: provided by the composing class (same library).
  InterruptionStateMachine get _interruption;

  // Requires: provided by the composing class (same library).
  set _isManualSkip(bool value);

  // Requires: provided by the composing class (same library).
  DateTime? get _lastPreviousTapTime;
  set _lastPreviousTapTime(DateTime? value);

  // Requires: provided by the composing class (same library).
  int get _lastSeekMs;
  set _lastSeekMs(int value);

  // Requires: provided by the composing class (same library).
  Future<void> _loadGaplessQueue({Duration? initialPosition, bool preload = true});

  // Requires: provided by the composing class (same library).
  Future<void> _loadSongPaused(int index, {Duration? initialPosition});

  // Requires: provided by the composing class (same library).
  Duration? get _pendingLazyPosition;
  set _pendingLazyPosition(Duration? value);

  // Requires: provided by the composing class (same library).
  Duration? get _pendingSeekPosition;
  set _pendingSeekPosition(Duration? value);

  // Requires: provided by the composing class (same library).
  double get _pitch;
  set _pitch(double value);

  // Requires: provided by the composing class (same library).
  int get _playGeneration;
  set _playGeneration(int value);

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerA;

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerB;

  // Requires: provided by the composing class (same library).
  StreamController<Duration> get _positionSubject;

  // Requires: provided by the composing class (same library).
  double? get _preCrossfadeVolume;

  // Requires: provided by the composing class (same library).
  IMusicRepository get _repository;

  // Requires: provided by the composing class (same library).
  void _saveCurrentPosition();

  // Requires: provided by the composing class (same library).
  Future<void> saveCurrentPositionImmediate();

  // Requires: provided by the composing class (same library).
  void _scheduleFadeInConvergenceGuard(AudioPlayer player, int generation);

  // Requires: provided by the composing class (same library).
  Timer? get _seekDebounceTimer;
  set _seekDebounceTimer(Timer? value);

  // Requires: provided by the composing class (same library).
  List<SongsTableData> get _songs;
  set _songs(List<SongsTableData> value);

  // Requires: provided by the composing class (same library).
  StreamPreResolver get _streamPreResolver;



  // Requires: provided by the composing class (same library).
  double get _volume;

  // Requires: provided by the composing class (same library).
  void cancelPrefetches();

  // Requires: provided by the composing class (same library).
  SongsTableData? get currentSong;

  // Requires: provided by the composing class (same library).
  Future<void> loadQueue(List<SongsTableData> songs, {int initialIndex = 0, Duration? initialPosition, bool autoPlay = true});

  // Requires: provided by the composing class (same library).
  Future<void> playSongAt(int index, {Duration? initialPosition});

  // Requires: provided by the composing class (same library).
  bool get _userPlaybackInitiated;
  set _userPlaybackInitiated(bool value);

  // Requires: provided by the composing class (same library).
  int get _rapidGaplessChangeCount;
  set _rapidGaplessChangeCount(int value);

  // Requires: provided by the composing class (same library).
  DateTime? get _lastGaplessChangeTime;
  set _lastGaplessChangeTime(DateTime? value);

  // Requires: provided by the composing class (same library).
  bool get _queueDirty;
  set _queueDirty(bool value);

  // Requires: provided by the composing class (same library).
  int get _lastGaplessIndex;
  set _lastGaplessIndex(int value);

  // Requires: provided by the composing class (same library).
  HeadsetControlConfig? get cachedHeadsetConfig;
  set cachedHeadsetConfig(HeadsetControlConfig? value);
}
