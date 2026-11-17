// lib/data/audio/audio_handler_session_wiring.dart
//
// Audio-session stream wiring, split out of PulsrAudioHandler to keep the class
// under its decomposition ratchet (test/architecture/fat_file_ratchet_test.dart).
// A `part` extension keeps private-member access, so the listeners still drive
// the handler's interruption bookkeeping directly instead of through a bridge.
part of 'audio_handler.dart';

extension AudioHandlerSessionWiring on PulsrAudioHandler {
  /// Subscribes to interruptions, becoming-noisy and device changes.
  ///
  /// Called once from the audio-session setup; the caller keeps the session
  /// configuration and the error handling around it.
  void wireSessionStreams(AudioSession session) {
    _subscriptions.add(
      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              unawaited(AudioSessionLog.instance
                  .recordInterruption(AudioInterruptionKind.duck));
              // F7: ducking behavior is user-controllable (duck/pause/ignore).
              if (duckingController.shouldIgnore) break;
              if (duckingController.shouldPause) {
                _interruption.begin(InterruptionKind.duck,
                    playing: _activePlayer.playing);
                if (_crossfadeManager.isCrossfading) {
                  await _crossfadeManager.cancel(
                      _inactivePlayer, _activePlayer,
                      restoreVolume: _preCrossfadeVolume ?? _volume);
                }
                // The system-behaviour policy may already deliver this pause
                // (with its own fade/USB handling). Only pause here when it
                // declined, so a duck never pauses twice.
                final SystemBehaviorHooks? duckHooks = _systemBehaviorHooks;
                final bool duckDelivered =
                    duckHooks != null && await duckHooks.onNotificationSound();
                if (!duckDelivered) await _activePlayer.pause();
                break;
              }
              // Stack-safe: a second duck begin while already ducked must not
              // clobber the saved pre-duck level. Duck both engines so a
              // navigation prompt during a crossfade doesn't blast the fade-in.
              // Count depth only for ducks that are really engaged. Counting a
              // begin that arrived while paused left the counter one too high,
              // so the matching end never reached 0 and the volume stayed
              // ducked after playback resumed.
              if (_duckActive) {
                _duckDepthCounter++;
              } else if (_activePlayer.playing) {
                _duckDepthCounter = 1;
                // Capture the clean (un-ducked) RG target and song identity
                // first so a later duck-end can restore the EXACT pre-duck
                // level when nothing changed during the duck.
                _preDuckRgTarget = _calculateReplayGainVolume(currentSong);
                _preDuckSongId = currentSong?.id;
                _duckActive = true;
                _duckSafetyTimer?.cancel();
                // Safety net ONLY: if a duck-end event is never delivered this
                // must NOT restore full volume (that would blast music over a
                // still-active navigation prompt). It merely re-asserts the
                // ducked level so a stuck state stays quiet; the real duck-end
                // event remains the sole path that restores volume.
                _duckSafetyTimer =
                    Timer(const Duration(seconds: 30), () async {
                  if (_duckActive) {
                    final rf = duckingController.duckFactor;
                    try {
                      await _activePlayer
                          .setVolume(rf * (_preDuckVolume ?? 1.0));
                      if (_crossfadeManager.isCrossfading) {
                        await _inactivePlayer
                            .setVolume(rf * (_preDuckInactiveVolume ?? 0.0));
                      }
                    } catch (_) {}
                  }
                });
                _preDuckVolume = _activePlayer.volume;
                _preDuckInactiveVolume = _inactivePlayer.volume;
                final f = duckingController.duckFactor;
                _volumeController?.updateSettings(
                    duckFactor: f, isDucked: true);
                await _activePlayer.setVolume(f * (_preDuckVolume ?? 1.0));
                if (_crossfadeManager.isCrossfading) {
                  await _inactivePlayer
                      .setVolume(f * (_preDuckInactiveVolume ?? 0.0));
                }
              }
              break;
            case AudioInterruptionType.pause:
              unawaited(AudioSessionLog.instance
                  .recordInterruption(AudioInterruptionKind.pause));
              // Cancel any active transient UI sound ducking timer so it cannot
              // restore volume mid-call or hold _duckDepthCounter elevated.
              if (_systemSoundTimer != null) {
                _systemSoundTimer?.cancel();
                _systemSoundTimer = null;
                if (_duckDepthCounter > 0) _duckDepthCounter--;
              }
              // Stack-safe: keep the original pre-interruption state so an
              // overlapping duck + call doesn't lose the resume decision.
              _interruption.begin(InterruptionKind.pause,
                  playing: _activePlayer.playing);
              if (_interruption.wasPlayingBeforeInterruption) {
                if (_crossfadeManager.isCrossfading) {
                  await _crossfadeManager.cancel(
                      _inactivePlayer, _activePlayer,
                      restoreVolume: _preCrossfadeVolume ?? _volume);
                }
                // One pause per event: when the system-behaviour runtime is
                // attached it owns the delivery (fade ramp / USB release /
                // plain pause) and this branch must not pause again.
                final SystemBehaviorHooks? hooks = _systemBehaviorHooks;
                final bool delivered = hooks != null &&
                    await hooks.onAudioFocusLoss(permanent: false);
                if (!delivered) await _activePlayer.pause();
              }
              break;
            case AudioInterruptionType.unknown:
              unawaited(AudioSessionLog.instance
                  .recordInterruption(AudioInterruptionKind.unknown));
              // Permanent/unknown loss: pause, never auto-resume, free DSP.
              _interruption.begin(InterruptionKind.unknown,
                  playing: _activePlayer.playing);
              _interruption.neverResume();
              if (_crossfadeManager.isCrossfading) {
                await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                    restoreVolume: _preCrossfadeVolume ?? _volume);
              }
              final SystemBehaviorHooks? permanentHooks =
                  _systemBehaviorHooks;
              final bool permanentDelivered = permanentHooks != null &&
                  await permanentHooks.onAudioFocusLoss(permanent: true);
              if (!permanentDelivered) await _activePlayer.pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _duckSafetyTimer?.cancel();
              _duckSafetyTimer = null;
              // A duck that began in pause-mode also holds the interruption
              // bookkeeping; end it here so a later call can snapshot afresh
              // instead of inheriting a stale half-open pause (B-1).
              final wasPlayingBeforeDuck =
                  _interruption.end(InterruptionKind.duck);
              if (_duckDepthCounter > 0) _duckDepthCounter--;
              if (_duckActive && _duckDepthCounter == 0) {
                _duckActive = false;
                _volumeController?.updateSettings(isDucked: false);
                // If neither the track nor the effective ReplayGain target
                // changed during the duck, restore the EXACT captured pre-duck
                // volume (preserving e.g. a mid-fade-in). Otherwise fall back
                // to the current RG target (gain/track changed, or nothing was
                // captured). This avoids both leaving the level permanently
                // ducked and discarding an in-progress fade.
                final currentTarget = _calculateReplayGainVolume(currentSong);
                final sameTrack = _preDuckSongId == currentSong?.id;
                final gainUnchanged = _preDuckRgTarget != null &&
                    (currentTarget - _preDuckRgTarget!).abs() < 0.001;
                // When a sleep fade is in flight the captured pre-duck level
                // is a stale faded value; restore from the clean target scaled
                // by the LIVE fade factor so the duck-end composes with the
                // fade instead of wiping it for a tick (Fight: duck-end vs
                // sleep fade). With no fade (_sleepFadeFactor == 1.0) this is
                // identical to the previous behaviour.
                final sleepFading = _sleepFadeFactor < 0.999;
                final restoreActive = (!sleepFading &&
                        _preDuckVolume != null &&
                        sameTrack &&
                        gainUnchanged)
                    ? _preDuckVolume!
                    : (currentTarget * _sleepFadeFactor).clamp(0.0, 1.0);
                try {
                  await _activePlayer
                      .setVolume(restoreActive.clamp(0.0, 1.0));
                } catch (e, st) {
                  ErrorLogger.log(
                      'Failed to restore active player volume after duck',
                      error: e,
                      stackTrace: st,
                      category: 'AudioHandler');
                }
                // During a crossfade the CrossfadeManager owns the inactive
                // player's live volume ramp; forcing a value here (previously
                // the OUTGOING track's RG applied to the INCOMING player) used
                // the wrong gain AND overwrote the ramp. Only restore the
                // inactive player when NOT crossfading, and then only to its
                // captured pre-duck level.
                if (!_crossfadeManager.isCrossfading &&
                    _preDuckInactiveVolume != null) {
                  try {
                    await _inactivePlayer.setVolume(_preDuckInactiveVolume!);
                  } catch (e, st) {
                    ErrorLogger.log(
                        'Failed to restore inactive volume after duck',
                        error: e,
                        stackTrace: st,
                        category: 'AudioHandler');
                  }
                }
                _preDuckVolume = null;
                _preDuckInactiveVolume = null;
                _preDuckSongId = null;
                _preDuckRgTarget = null;
              } else if (PulsrAudioHandler.shouldResumeAfterInterruption(
                wasPlayingBeforeInterruption: wasPlayingBeforeDuck,
                resumeAfterInterruption: _cachedPrefs
                        ?.getBool(PrefsKeys.resumeAfterInterruption) ??
                    true,
                currentlyPlaying: _activePlayer.playing,
              )) {
                // The system-behaviour service may own this resume (and the
                // volume restore that precedes it); it reports whether it
                // actually resumed so this branch never plays twice.
                final SystemBehaviorHooks? duckEndHooks =
                    _systemBehaviorHooks;
                final bool duckResumed = duckEndHooks != null &&
                    await duckEndHooks.onNotificationSoundEnd();
                if (!duckResumed) {
                  // Pause-mode duck: playback was running when the navigation
                  // prompt began, so resume it now that the prompt ended. It
                  // was previously left paused permanently. Route through the
                  // public play() so the resume also runs
                  // AudioSession.setActive(true), the completed-replay guard,
                  // the DVC gain-curve clear and the fade-in convergence guard
                  // (a bare _activePlayer.play() skips all of them).
                  unawaited(play());
                }
              }
              break;
            case AudioInterruptionType.pause:
              final wasPlayingBeforePause =
                  _interruption.end(InterruptionKind.pause);
              // The gain hook also restores the volume a fade-out ramp lowered
              // and reports whether it resumed. One owner per event: this
              // branch resumes only when the service did not.
              final SystemBehaviorHooks? gainHooks = _systemBehaviorHooks;
              final bool gainResumed =
                  gainHooks != null && await gainHooks.onAudioFocusGain();
              if (!gainResumed &&
                  PulsrAudioHandler.shouldResumeAfterInterruption(
                    wasPlayingBeforeInterruption: wasPlayingBeforePause,
                    // Cached prefs: this fires on every call-end; a disk read
                    // here delayed resume by ~10-20ms.
                    resumeAfterInterruption: _cachedPrefs
                            ?.getBool(PrefsKeys.resumeAfterInterruption) ??
                        true,
                    currentlyPlaying: _activePlayer.playing,
                  )) {
                // Route through the public play() (not a bare
                // _activePlayer.play()) so the resume runs setActive(true),
                // the completed-replay guard, the DVC clear and the fade-in
                // guard.
                unawaited(play());
              }
              // A call can arrive in the middle of a navigation-prompt duck.
              // The duck-end event may never come after that, so clear the duck
              // here AND put the volume back; before, the flags were reset but
              // the player stayed at the ducked level.
              final hadDuck = _duckActive;
              _clearDuckState();
              if (hadDuck) unawaited(_reapplyActiveVolume());
              break;
            case AudioInterruptionType.unknown:
              _interruption.reset();
              final hadUnknownDuck = _duckActive;
              _clearDuckState();
              if (hadUnknownDuck) unawaited(_reapplyActiveVolume());
              break;
          }
        }
      }),
    );

    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) async {
        // Debounce: wired + BT stacks can emit noisy twice for one unplug.
        final now = DateTime.now();
        if (_lastNoisyTime != null &&
            now.difference(_lastNoisyTime!) <
                const Duration(milliseconds: 800)) {
          return;
        }
        _lastNoisyTime = now;
        unawaited(AudioSessionLog.instance
            .recordInterruption(AudioInterruptionKind.becomingNoisy));
        if (!_activePlayer.playing && !_crossfadeManager.isCrossfading) {
          return;
        }
        if (_crossfadeManager.isCrossfading) {
          await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
              restoreVolume: _preCrossfadeVolume ?? _volume);
        }
        // Pause first (pause() clears _pausedForNoisy, like a user pause),
        // THEN arm the auto-resume window so ONLY a becoming-noisy pause keeps
        // it armed for a quick reconnect. The system-behaviour service owns
        // the delivery when attached (it may keep the USB claim), so it is
        // asked first and this path only pauses when it declined.
        final SystemBehaviorHooks? noisyHooks = _systemBehaviorHooks;
        final bool noisyDelivered =
            noisyHooks != null && await noisyHooks.onHeadsetUnplug();
        if (!noisyDelivered) await pause();
        _noisyPauseTime = now;
        _pausedForNoisy = true;
        await _captureOutputDeviceBaseline();
      }),
    );

    _subscriptions.add(
      session.devicesStream.listen((devices) {
        _syncBluetoothRouteFromCache();
        _audioSessionIdRouter.handleRouteChanged();
        unawaited(_refreshBluetoothRoute());
        unawaited(_recordSessionRouteChange());
        unawaited(_maybeAutoResumeOnReconnect());
      }),
    );
  }
}

