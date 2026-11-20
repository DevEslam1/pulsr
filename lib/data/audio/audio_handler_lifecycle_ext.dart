part of 'audio_handler.dart';

/// Lifecycle teardown, stop, rating, and transient system-sound ducking
/// helpers extracted from [PulsrAudioHandler] to keep the core file focused.
extension _PulsrAudioLifecycleExt on PulsrAudioHandler {
  Future<void> _stopImpl() async {
    _pendingPlaybackStart = false;
    // Invalidate any slow in-flight resolve so it cannot start playback after
    // the user stopped (pause() already does this; stop() did not).
    _playGeneration++;
    _headsetClickTimer?.cancel();
    _headsetClickTimer = null;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = null;
    _sleepTimerManager.cancelSleepTimer();
    unawaited(AudioSessionLog.instance.endSession());
    try {
      await _crossfadeManager.cancel(
        _inactivePlayer,
        _activePlayer,
        restoreVolume: _volume,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to cancel crossfade during stop',
        error: e,
        stackTrace: st,
        category: 'AudioHandler',
      );
    }
    // Reset transient volume/interruption state so the next session does not
    // start ducked, mid-fade or with a stale "resume after call" decision.
    _clearDuckState();
    _sleepFadeFactor = 1.0;
    _interruption.reset();
    _pausedForNoisy = false;
    // Pause periodic saving BEFORE persisting and stopping players so trailing
    // ticks cannot write zero over the saved position.
    _playbackStateCoordinator.pauseSaving();
    // Persist the REAL position before the players are stopped.
    try {
      await saveCurrentPositionImmediate();
    } catch (_) {}
    // Release the DSD alt setting only after the position is persisted; the
    // session is the position source while it owns the DAC.
    if (nativeDsdActive) {
      try {
        await stopNativeDsd(clearStatus: true);
      } catch (e, st) {
        ErrorLogger.log('Failed to stop native DSD during stop',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    }
    unawaited(PositionCrashGuard.recordCleanShutdown());
    _gaplessLoaded = false;
    _gaplessTargetIndex = null;
    mediaItem.add(null);
    queue.add([]);
    // Each platform call is isolated: one throwing must not skip the rest and
    // leave the notification / foreground service stuck in a playing state.
    for (final player in [_playerA, _playerB]) {
      try {
        await player.stop();
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to stop player',
          error: e,
          stackTrace: st,
          category: 'AudioHandler',
        );
      }
    }
    // The stopped players report position 0; make sure the timer cannot write
    // that over the position saved above.
    _playbackStateCoordinator.clearDirty();
    try {
      await AudioEffectsChannel().releaseEffects();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to release effects during stop',
        error: e,
        stackTrace: st,
        category: 'AudioHandler',
      );
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        systemActions: const {},
        androidCompactActionIndices: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );
  }

  Future<void> _setRatingImpl(
    Rating rating, [
    Map<String, dynamic>? extras,
  ]) async {
    if (rating.getRatingStyle() != RatingStyle.heart) return;
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return;
    }
    final hasHeart = rating.isRated() && rating.hasHeart();
    final song = _songs[_currentIndex];
    if (song.isFavorite == hasHeart) return;
    final toggleUseCase = getIt.isRegistered<ToggleFavoriteUseCase>()
        ? getIt<ToggleFavoriteUseCase>()
        : ToggleFavoriteUseCase(_repository);
    final result = await toggleUseCase(song.id);
    final newFav = result.fold((l) => song.isFavorite, (r) => r);
    updateFavorite(song.id, newFav);
  }

  Future<void> _disposeImpl() async {
    // Idempotency check first: a second call used to re-run the observer and
    // timer teardown before bailing out.
    if (_disposed) return;
    try {
      await stopNativeDsd(clearStatus: true);
    } catch (e, st) {
      ErrorLogger.log('Failed to stop native DSD during dispose',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    _disposed = true;
    try {
      await _castPlaybackHandoff?.dispose();
    } catch (e, st) {
      ErrorLogger.log('Cast playback handoff dispose failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    _castPlaybackHandoff = null;
    _headsetClickTimer?.cancel();
    _headsetClickTimer = null;
    _bufferRelaxTimer?.cancel();
    _bufferRelaxTimer = null;
    final lifecycleObserver = _lifecycleObserver;
    if (lifecycleObserver != null) {
      try {
        WidgetsBinding.instance.removeObserver(lifecycleObserver);
      } catch (_) {}
      _lifecycleObserver = null;
    }
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _fadeInGuardTimer?.cancel(); // FIX-#12
    _fadeInGuardTimer = null;
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = null;
    _duckSafetyTimer?.cancel();
    _duckSafetyTimer = null;
    _systemSoundTimer?.cancel();
    _systemSoundTimer = null;
    for (final sub in List.of(_subscriptions)) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
    // Dispose sleep timer before closing its subject to avoid add-after-close race
    try {
      _sleepTimerManager.dispose();
    } catch (_) {}
    try {
      _gaplessMonitor.dispose();
    } catch (_) {}
    try {
      abLoopManager.dispose();
    } catch (_) {}
    try {
      multiOutputRouter.dispose();
    } catch (_) {}
    try {
      await silenceSkipController.persist();
    } catch (_) {}
    // Guarded: dispose() can run before the async _init() assigned this late
    // field (hot restart / test teardown / early init failure).
    try {
      _streamPreResolver.dispose();
    } catch (_) {}
    try {
      _preloadScheduler.clear();
    } catch (_) {}
    try {
      _adaptiveBufferEngine.dispose();
    } catch (_) {}
    try {
      _memoryManager.clearAll();
    } catch (_) {}
    try {
      adaptiveQualityManager.dispose();
    } catch (_) {}
    try {
      _volumeController?.dispose();
    } catch (_) {}
    _playbackStateCoordinator.dispose();
    if (!_audioSessionIdSubject.isClosed) _audioSessionIdSubject.close();
    if (!_errorSubject.isClosed) _errorSubject.close();
    if (!_onTrackChangedSubject.isClosed) _onTrackChangedSubject.close();
    if (!_volumeSubject.isClosed) _volumeSubject.close();
    try {
      _equalizerManager.dispose();
    } catch (_) {}
    try {
      _crossfadeManager.dispose();
    } catch (_) {}
    // Don't leave disposed objects registered in DI: a later consumer (or a
    // rebuilt handler) would otherwise resolve a dead EqualizerManager.
    try {
      if (getIt.isRegistered<EqualizerManager>() &&
          identical(getIt<EqualizerManager>(), _equalizerManager)) {
        getIt.unregister<EqualizerManager>();
      }
      if (getIt.isRegistered<AdaptiveBufferEngine>() &&
          identical(getIt<AdaptiveBufferEngine>(), _adaptiveBufferEngine)) {
        getIt.unregister<AdaptiveBufferEngine>();
      }
    } catch (_) {}
    try {
      await AudioEffectsChannel().releaseEffects();
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to release native audio effects',
        error: e,
        stackTrace: st,
        category: 'AudioHandler',
      );
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    try {
      await _playerA.dispose();
    } catch (_) {}
    try {
      await _playerB.dispose();
    } catch (_) {}
    try {
      await _prefetchPlayer.dispose();
    } catch (_) {}
    try {
      platformBridgeDegraded.dispose();
    } catch (_) {}
  }

  Future<void> _handleSystemUiSoundInterruptionImpl() async {
    if (!_activePlayer.playing) return;
    if (_duckActive) {
      // Participate in stack-safe duck depth so an overlapping navigation duck
      // or call cannot be prematurely un-ducked by a 500ms UI sound timer.
      if (_systemSoundTimer == null) {
        _duckDepthCounter++;
      }
      _interruption.begin(InterruptionKind.systemUiSound, playing: true);
    } else {
      _duckDepthCounter = 1;
      _preDuckRgTarget = _calculateReplayGainVolume(currentSong);
      _preDuckSongId = currentSong?.id;
      _preDuckVolume = _activePlayer.volume;
      _preDuckInactiveVolume = _inactivePlayer.volume;
      _duckActive = true;
      _interruption.begin(InterruptionKind.systemUiSound, playing: true);
    }

    // Schedule the restore timer BEFORE awaiting the duck. If setVolume throws
    // and we only created the timer afterwards, _duckActive would stay true
    // forever with no timer to clear it, permanently blocking later ducks.
    _systemSoundTimer?.cancel();
    _systemSoundTimer = Timer(const Duration(milliseconds: 500), () async {
      _systemSoundTimer = null;
      _interruption.end(InterruptionKind.systemUiSound);
      if (_duckDepthCounter > 0) _duckDepthCounter--;
      if (_duckActive && _duckDepthCounter == 0) {
        _duckActive = false;
        _volumeController?.updateSettings(isDucked: false);
        final currentTarget = _calculateReplayGainVolume(currentSong);
        final sameTrack = _preDuckSongId == currentSong?.id;
        final gainUnchanged = _preDuckRgTarget != null &&
            (currentTarget - _preDuckRgTarget!).abs() < 0.001;
        final sleepFading = _sleepFadeFactor < 0.999;
        final restoreActive = (!sleepFading &&
                _preDuckVolume != null &&
                sameTrack &&
                gainUnchanged)
            ? _preDuckVolume!
            : (currentTarget * _sleepFadeFactor).clamp(0.0, 1.0);
        try {
          await _activePlayer.setVolume(restoreActive.clamp(0.0, 1.0));
        } catch (_) {}
        _preDuckVolume = null;
        _preDuckInactiveVolume = null;
        _preDuckSongId = null;
        _preDuckRgTarget = null;
      }
    });
    try {
      final f = duckingController.duckFactor;
      _volumeController?.updateSettings(duckFactor: f, isDucked: true);
      await _activePlayer.setVolume(
        f * (_preDuckVolume ?? _activePlayer.volume),
      );
    } catch (_) {
      // Ducking failed: restore state immediately instead of leaving the
      // 500 ms timer to do it (or not, if it never fires).
      _systemSoundTimer?.cancel();
      _systemSoundTimer = null;
      _interruption.end(InterruptionKind.systemUiSound);
      if (_duckDepthCounter > 0) _duckDepthCounter--;
      if (_duckDepthCounter == 0) {
        _duckActive = false;
        _volumeController?.updateSettings(isDucked: false);
        _preDuckVolume = null;
        _preDuckInactiveVolume = null;
        _preDuckSongId = null;
        _preDuckRgTarget = null;
      }
    }
  }
}
