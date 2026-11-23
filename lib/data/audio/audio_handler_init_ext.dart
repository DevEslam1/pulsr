part of 'audio_handler.dart';

/// Startup initialization and per-player stream listener wiring extracted from
/// [PulsrAudioHandler] to keep the core file focused.
extension _PulsrAudioInitExt on PulsrAudioHandler {
  Future<void> _init() async {
    AudioMemoryManager.adaptBudgetToSystemRam();
    await _initPrefs();
    _installSafeModeController();
    _castPlaybackHandoff = CastPlaybackHandoff(
      isLocalPlaying: () =>
          _playerA.playing || _playerB.playing || _nativeDsdActive,
      pauseLocal: pause,
      resumeLocal: play,
    )..start();
    // Restore the 24/32-bit float DSP path before any other player call so the
    // native sink is built with the persisted preference. Defaults ON so hi-res
    // sources are never truncated to 16-bit; 16-bit content is unaffected.
    try {
      await setFloatOutputEnabled(
        _cachedPrefs?.getBool(PrefsKeys.floatOutputEnabled) ?? true,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore float output setting',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Restore the opt-in AAudio Direct output before any other player call
    // so the sink is built with the persisted preference. Off by default.
    try {
      await setAaudioOutputEnabled(
        _cachedPrefs?.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
        preferExclusive:
            _cachedPrefs?.getBool(PrefsKeys.aaudioPreferExclusive) ?? true,
        targetBufferMs:
            _cachedPrefs?.getInt(PrefsKeys.aaudioTargetBufferMs) ?? 120,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore AAudio output setting',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Restore the opt-in DAC voicing preference so a saved choice is not
    // silently dropped until the user opens the output sheet again. Off by
    // default; off is a bit-exact passthrough, so this cannot change the sound
    // for anyone who never enabled it.
    try {
      await DacVoicingService.instance.load();
    } catch (e, st) {
      ErrorLogger.log('Failed to restore DAC voicing preference',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Restore the tap-side SRC kernel. The in-chain sinc stage no longer
    // converts anything (a fixed-size block cannot change rate), so the tap is
    // the only converter and the stored 64/128/256/512-tap choice has to reach
    // native before the first track is prepared.
    try {
      await AudioEffectsChannel().setTapSrcQuality(
        _cachedPrefs?.getInt(PrefsKeys.tapSrcQuality) ?? 2,
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore tap SRC quality',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Restore Remaster suite settings (oversampling, reconstruction filter kernel, PCM->DSD).
    try {
      final oversampleMultiplier =
          _cachedPrefs?.getInt(PrefsKeys.remasterOversampleMultiplier) ?? 1;
      final filterKernel =
          _cachedPrefs?.getInt(PrefsKeys.remasterFilterKernel) ?? 0;
      final pcmToDsdEnabled =
          _cachedPrefs?.getBool(PrefsKeys.remasterPcmToDsdEnabled) ?? false;
      final pcmToDsdRate =
          _cachedPrefs?.getInt(PrefsKeys.remasterPcmToDsdRate) ?? 64;
      final pcmToDsdOrder =
          _cachedPrefs?.getInt(PrefsKeys.remasterPcmToDsdOrder) ?? 5;

      await AudioEffectsChannel().setOversampleMultiplier(oversampleMultiplier);
      await AudioEffectsChannel().setOversampleKernel(filterKernel);
      await AudioEffectsChannel().setPcmToDsdEnabled(pcmToDsdEnabled);
      await AudioEffectsChannel().setPcmToDsdRate(pcmToDsdRate);
      await AudioEffectsChannel().setPcmToDsdOrder(pcmToDsdOrder);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Remaster settings',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    // Restore Direct Volume Control. Only the system-stream pinning needs to
    // happen here; per-track gain is applied by _calculateReplayGainVolume.
    try {
      _dvcEnabled = _cachedPrefs?.getBool(PrefsKeys.dvcEnabled) ?? false;
      if (_dvcEnabled) {
        // The stream is at its real device level right now; capture it as the
        // app volume before DVC pins the stream to max.
        await _seedVolumeFromSystemForDvc();
        unawaited(AudioEffectsChannel().setDvcEnabled(true));
        unawaited(_pushDvcGain(_volume));
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore DVC setting',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    _crossfadeManager.bpmSyncEnabled =
        _cachedPrefs?.getBool(PrefsKeys.bpmSyncCrossfadeEnabled) ?? false;
    // Restore persisted playback speed/pitch and the extended speed range so a
    // saved out-of-range speed is not silently clamped to 0.25–4.0 on cold start.
    try {
      await restorePersistedSpeed();
    } catch (e, st) {
      ErrorLogger.log('Failed to restore persisted speed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    _playbackAnalytics = PlaybackAnalytics(
      onIncreaseBufferSizeRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested buffer size increase');
        _adaptiveBufferEngine.forceBucket(BufferBucket.generous);
        _scheduleBufferRelax();
      },
      onReduceQualityRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested quality reduction');
        // F4: adaptive quality step-down mid-track.
        unawaited(_maybeAdaptiveStepDown());
      },
    );

    _memoryManager = AudioMemoryManager(
      onPreloadRejected: (key, sizeBytes) {
        debugPrint(
            '[AudioHandler] Preload rejected for $key ($sizeBytes bytes)');
      },
      onBackgroundReleaseRequested: () =>
          _tripleBufferPipeline.clearPreload(),
    );

    _preloadScheduler = SmartPreloadScheduler(
      // Intentional no-op: URL warming is handled by _smartPrefetch() and
      // StreamPreResolver, so the scheduler only needs the cancel hook below.
      onPreloadRequested: (song, {required priority}) async {},
      onCancelRequested: () => cancelPrefetches(),
      qualityProvider: _currentStreamingQuality,
    );

    _streamPreResolver = StreamPreResolver(
      resolveUrl: (videoId, {quality = 'high', title, artist}) =>
          _ytmService.resolveStream(videoId,
              quality: quality, title: title, artist: artist),
      urlCache: getIt.isRegistered<YtmUrlCache>()
          ? getIt<YtmUrlCache>()
          : YtmUrlCache(),
      qualityProvider: _currentStreamingQuality,
      isAlreadyPrefetching: (id) =>
          _prefetching
              .contains('$id:${_currentStreamingQuality().toLowerCase()}') ||
          _prefetching.contains(id),
      repeatQueueProvider: () =>
          playbackState.value.repeatMode == AudioServiceRepeatMode.all,
      // Warm as deep as the live buffer bucket allows (minimal=1, standard=2,
      // generous=3), except on metered connections where the scheduler's
      // data-cost policy caps it at the single next track.
      windowSizeProvider: () =>
          _preloadScheduler.isMeteredCached ? 1 : _preloadCountForCurrentBucket,
    );

    _formatDecoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) => _resolveAudioSource(song, tag),
      decodeDsdToPcm: (song, tag) => DsdDecoderHelper.decodeDsdFile(song, tag),
    );

    _tripleBufferPipeline = TripleBufferPipeline(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
      prefetchPlayer: _prefetchPlayer,
      analytics: _playbackAnalytics,
      // Abort stale preloads: a resolve that outlives the track that
      // scheduled it must never setAudioSource on the now-active player.
      // Generation is the real guard (player objects are always distinct, so
      // `identical` alone can never detect a swap); crossfade state is the
      // secondary guard.
      isLoadStillValid: () => !_crossfadeManager.isCrossfading,
      getGeneration: () => _playGeneration,
      resolveAudioSource: (song, tag) => _resolveAudioSource(song, tag),
      songToMediaItem: (song, [fastArtUri]) =>
          PulsrAudioHandler._songToMediaItem(song, fastArtUri),
    );

    _batteryAwarePlayback = BatteryAwarePlayback(
      onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
        debugPrint('[AudioHandler] Battery low power mode triggered');
        if (reduceDsp) {
          unawaited(_equalizerManager.degradeToEssentials());
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
        debugPrint('[AudioHandler] Battery critical power mode triggered');
        if (disableCrossfade && _crossfadeManager.duration > Duration.zero) {
          _preBatteryCriticalCrossfadeDuration = _crossfadeManager.duration;
          setCrossfadeDuration(Duration.zero);
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onRestoreFromCritical: () {
        debugPrint(
            '[AudioHandler] Battery restored from critical to low power');
        if (_preBatteryCriticalCrossfadeDuration != null) {
          setCrossfadeDuration(_preBatteryCriticalCrossfadeDuration!);
          _preBatteryCriticalCrossfadeDuration = null;
        }
        _adaptiveBufferEngine.releaseForce();
      },
      onRestoreNormal: () {
        debugPrint('[AudioHandler] Battery restored to normal');
        if (_preBatteryCriticalCrossfadeDuration != null) {
          setCrossfadeDuration(_preBatteryCriticalCrossfadeDuration!);
          _preBatteryCriticalCrossfadeDuration = null;
        }
        // A forced battery saver outlives an automatic restore: the user asked
        // for the essential profile regardless of the charge level.
        if (!_batterySaverForced) {
          unawaited(_equalizerManager.restoreFromDegrade());
        }
        _adaptiveBufferEngine.releaseForce();
      },
    );

    _volumeController ??= PlaybackVolumeController(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
    );
    _syncVolumeControllerSettings();
    var wasDirectStreaming = UsbExclusiveService().lastStatus.streamingActive;
    _hardwareVolumeOwned = _hardwareVolumeOwnsOutput();
    _subscriptions.add(UsbExclusiveService().statusStream.listen((status) {
      if (_disposed) return;
      final startedStreaming = (!wasDirectStreaming && status.streamingActive) ||
          (status.streamingActive &&
              _isUsbHardwareVolumeEnabled() &&
              status.hasVolumeControl &&
              !status.hardwareVolumeApplied);
      wasDirectStreaming = status.streamingActive;
      if (!status.streamingActive) {
        _externalHardwareVolumeSet = false;
        final hadDirectGain = _lastDirectUsbVolume >= 0.0;
        _lastDirectUsbVolume = -1.0;
        if (hadDirectGain) {
          unawaited(_resetDirectUsbGainAfterStop());
        }
      }
      if (startedStreaming) {
        unawaited(_onDirectUsbStreamingStarted(status));
      }
      final owned = _hardwareVolumeOwnsOutput();
      final ownershipChanged = owned != _hardwareVolumeOwned;
      _hardwareVolumeOwned = owned;
      // The DAC can move its own attenuator (volume keys, front panel, the
      // Settings UAC2 slider). Mirror that level into the app slider without
      // echoing it back into another SET_CUR.
      final hwDb = status.hardwareVolumeDb;
      final minDb = status.minVolumeDb;
      final maxDb = status.maxVolumeDb;
      if (owned &&
          !_usbHwVolumeBusy &&
          hwDb != null &&
          minDb != null &&
          maxDb != null) {
        final linear = UsbHardwareVolumeCurve.linearFor(
          hwDb,
          minDb: minDb,
          maxDb: maxDb,
        );
        if (linear.isFinite && (_volume - linear).abs() > 0.002) {
          syncVolumeFromExternalHardwareDb(hwDb, minDb: minDb, maxDb: maxDb);
        }
      }
      if (ownershipChanged) {
        // Ownership flip: re-run the whole gain path so software attenuation
        // is restored the moment the DAC stops confirming the hardware level.
        unawaited(setVolume(_volume));
      }
    }));
    unawaited(HeadsetControlConfig.load(_cachedPrefs).then((cfg) {
      _cachedHeadsetConfig = cfg;
    }).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Failed to load headset control config',
          error: e, stackTrace: st, category: 'AudioHandler');
    }));

    _equalizerManager.attachDspPipeline(_dspPipeline);
    unawaited(_equalizerManager.syncNativeLatency(PulsrAudioHandler.assumedOutputSampleRate));

    _gaplessMonitor.attach(
      currentIndexStream: _activePlayer.currentIndexStream,
      positionStream: _activePlayer.positionStream,
    );

    _subscriptions.add(
      _adaptiveBufferEngine.onBucketChanged.listen((bucket) {
        _onBufferBucketChanged(bucket);
      }),
    );
    // Quality step-down decisions are consolidated under AdaptiveQualityManager
    // (via PlaybackAnalytics -> _maybeAdaptiveStepDown) to avoid duplicate drops or thrashing.

    // Event-driven battery state change listener (I2)
    _subscriptions.add(
      BatteryOptimizationService.onBatteryChanged.listen((level) {
        if (!_disposed) {
          _batteryAwarePlayback.onBatteryLevelChanged(level);
        }
      }),
    );

    _subscriptions.add(
      // Low-frequency fallback poll only while playing if platform events are delayed
      Stream.periodic(const Duration(seconds: 120)).listen((_) async {
        if (_disposed || !_activePlayer.playing) return;
        try {
          final level = await BatteryOptimizationService.getBatteryLevel();
          if (level != null) {
            _batteryAwarePlayback.onBatteryLevelChanged(level);
          }
        } catch (_) {
          // Best-effort telemetry; platform hiccups must not throw
        }
      }),
    );
    BatteryOptimizationService.getBatteryLevel().then((level) {
      if (level != null && !_disposed) {
        _batteryAwarePlayback.onBatteryLevelChanged(level);
      }
    }).catchError((_) {});

    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      bool isTargetActive() =>
          isPlayerA == _isPlayerAActive && identical(player, _activePlayer);
      // Underruns are edge-triggered: a single stall emits many playback events
      // (every bufferedPosition update) and must count as ONE underrun, or one
      // hiccup would trip the widen-buffer / quality step-down thresholds.
      var wasBuffering = false;

      _subscriptions.add(
        player.outputModeEffectStream.listen(
          (effect) {
            if (_disposed) return;
            if (effect.reason == null) {
              // A mode became effective again; allow a future failure on the
              // same output to surface once more.
              _lastSuspendedReason = null;
              if (effect.aaudioActive || effect.floatActive) {
                _lastOutputModeNotice = null;
              }
              return;
            }
            // A non-null reason is not automatically a failure: the sink
            // reports temporary suspensions (speed/pitch, skip-silence) the
            // same way. AAudio is parked on the AudioTrack path and restored
            // once the parameter returns to default, so those must not count
            // as rejections - three of them would make safe mode permanently
            // disable AAudio for the device.
            if (PulsrAudioHandler._suspensionReasons.contains(effect.reason)) {
              if (effect.aaudioActive) {
                // Resume after the suspension: direct output is back, so the
                // next episode may be logged again.
                _lastSuspendedReason = null;
                return;
              }
              if (effect.reason == _lastSuspendedReason) return;
              _lastSuspendedReason = effect.reason;
              // Informational: no safe-mode counter and no rejection notice -
              // the direct path comes back on its own. No localized string
              // exists for this line yet, so it stays in the log.
              ErrorLogger.log(
                'Direct output was suspended (${effect.reason}); '
                'playback continues.',
                category: 'AudioHandler',
              );
              return;
            }
            _lastSuspendedReason = null;
            final message = effect.reason == 'float_rejected'
                ? "High-resolution float output isn't available on this "
                    'output; using 16-bit output.'
                : "Direct (AAudio) output isn't available on this output; "
                    'using the standard audio output.';
            // Safe mode (P1-10): a rejected direct output is a real sink
            // failure, so feed the consecutive-failure counter on every event
            // (not only on the first notice) or the threshold could never be
            // reached. No-op without a controller.
            unawaited(
              _recordSafeModeFailure('output-mode:${effect.reason}'),
            );
            if (message == _lastOutputModeNotice) return;
            _lastOutputModeNotice = message;
            ErrorLogger.log(
              'Audio output mode fallback: ${effect.reason} '
              '(aaudioActive=${effect.aaudioActive}, '
              'floatActive=${effect.floatActive})',
              category: 'AudioHandler',
            );
            if (!_errorSubject.isClosed) {
              _errorSubject.add('${PulsrAudioHandler.outputModeNoticePrefix}$message');
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player outputModeEffectStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.playbackEventStream.listen(
          (event) {
            if (_disposed || _nativeDsdActive) return;
            if (isTargetActive()) {
              final isBuffering =
                  event.processingState == ProcessingState.buffering;
              // Ignore the initial fill at track start / seeks near the start:
              // only a stall after playback has really begun is an underrun.
              if (isBuffering &&
                  !wasBuffering &&
                  _activePlayer.playing &&
                  _activePlayer.position > const Duration(seconds: 2)) {
                _playbackAnalytics.recordBufferUnderrun();
                // Still stalling: keep the widened buffer for another quiet
                // period instead of letting the relax timer expire mid-trouble.
                if (_bufferRelaxTimer?.isActive == true) _scheduleBufferRelax();
                unawaited(AudioSessionLog.instance.recordUnderrun());
              }
              wasBuffering = isBuffering;
              _broadcastState(event);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playbackEventStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
            unawaited(_recordSafeModeFailure('playback-event:$e'));
          },
        ),
      );

      _subscriptions.add(
        player.durationStream.listen(
          (dur) {
            if (_disposed || _nativeDsdActive) return;
            if (isTargetActive() && dur != null && dur > Duration.zero) {
              final current = mediaItem.value;
              if (current != null && current.duration != dur) {
                mediaItem.add(current.copyWith(duration: dur));
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player durationStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.playerStateStream.listen(
          (state) async {
            if (_disposed || _nativeDsdActive) return;
            if (isTargetActive()) {
              // Broadcast is driven solely by the playbackEventStream listener
              // above (C-5): playerStateStream is derived from the same event
              // stream, so broadcasting here serialised every transition to the
              // platform twice per state change.
              // Gapless loop-all support
              if (_gaplessMode &&
                  state.processingState == ProcessingState.completed &&
                  _activePlayer.loopMode == LoopMode.all) {
                // `completed` can also fire mid-queue while the next item is
                // swapped in (see the comment below). Only wrap to the start
                // when the LAST item actually finished, otherwise this would
                // yank playback back to track 1 on every transition.
                final idx = _activePlayer.currentIndex;
                final len = _activePlayer.sequence.length;
                if (idx == null || idx >= len - 1) {
                  try {
                    await _activePlayer.seek(Duration.zero, index: 0);
                    unawaited(_activePlayer.play());
                  } catch (e, st) {
                    ErrorLogger.log('Failed to wrap queue for repeat-all',
                        error: e, stackTrace: st, category: 'AudioHandler');
                  }
                }
                return;
              }
              // A natural completion keeps `playing == true` in just_audio;
              // only the playback state turns `completed`. Pause/stop re-emit
              // the current event as `completed` with `playing == false`, and
              // those must NOT trigger auto-advance: playSongAt pauses as part
              // of its teardown, which would otherwise re-enter this branch,
              // spawn a second skipToNext and let the stale first invocation
              // stop() the player out from under the successor (track shown,
              // parked paused at 0:00).
              if (state.processingState == ProcessingState.completed &&
                  state.playing &&
                  !_crossfadeManager.isCrossfading) {
                if (_gaplessMode && _gaplessLoaded) {
                  // In gapless mode the ConcatenatingAudioSource advances
                  // itself, so a `completed` event can fire mid-queue while the
                  // native concat has already moved on to the next item. Only
                  // the LAST item reports the end of the queue: advancing here
                  // as well double-skipped the successor (the "next song never
                  // plays" bug). Mid-queue boundaries are already handled by
                  // the currentIndexStream listener.
                  if (!_activePlayer.hasNext &&
                      _activePlayer.loopMode == LoopMode.off) {
                    notifySleepTrackCompleted();
                    unawaited(_sleepTimerManager.onQueueCompleted());
                    if (_songs.isNotEmpty) {
                      unawaited(() async {
                        try {
                          await _activePlayer.seek(Duration.zero, index: 0);
                          _lastGaplessIndex = 0;
                          _currentIndex = 0;
                          _savedQueueIndex = 0;
                          final song = _songs[0];
                          final fastArtUri = song.artworkUri != null
                              ? Uri.tryParse(song.artworkUri!)
                              : null;
                          mediaItem.add(PulsrAudioHandler._songToMediaItem(
                              song, fastArtUri));
                          _notifyTrackChanged(song);
                          await _activePlayer.pause();
                          _broadcastState(_activePlayer.playbackEvent);
                        } catch (_) {}
                      }());
                    }
                  }
                } else {
                  // Non-gapless playback holds one source per track, so the
                  // completed event needs a manual advance (or end-of-queue
                  // reset to the first track, paused).
                  notifySleepTrackCompleted();
                  final nextIdx = _getNextIndex(peek: true);
                  if (nextIdx == null &&
                      !_activePlayer.hasNext &&
                      _activePlayer.loopMode == LoopMode.off) {
                    unawaited(_sleepTimerManager.onQueueCompleted());
                    if (_songs.isNotEmpty) {
                      unawaited(
                          _loadSongPaused(0, initialPosition: Duration.zero));
                    }
                  } else {
                    unawaited(_advanceAtTrackBoundary()
                        .catchError((Object e, StackTrace st) {
                      ErrorLogger.log('Auto-advance failed',
                          error: e, stackTrace: st, category: 'AudioHandler');
                    }));
                  }
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playerStateStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.positionStream.listen(
          (pos) {
            if (_disposed || _nativeDsdActive) return;
            if (isTargetActive()) {
              _playbackStateCoordinator.onPositionTick(
                pos,
                markDirty: player.playing,
              );
              // FIX-B03: Guard failure reset on position ticks: only reset when ready and pos > 2s
              if (player.processingState == ProcessingState.ready &&
                  pos > const Duration(seconds: 2) &&
                  _consecutiveFailures > 0) {
                _consecutiveFailures = 0;
              }
              // AB loop wrap, CUE end advance, bookmark autosave, and adaptive
              // healthy-window reporting only apply during active playback.
              if (player.playing) {
                // F1: AB loop wrap. Pass the live playback speed so the
                // look-ahead widens at 2–4x (a single ~150ms position tick
                // jumps far enough to overshoot the fixed 1x window otherwise).
                final wrap = abLoopManager.wrapTarget(pos,
                    songId: currentSong?.id, speed: _activePlayer.speed);
                if (wrap != null) {
                  unawaited(_activePlayer.seek(wrap));
                }
                // T10: enter the CUE window once decodable, then advance at
                // its end. Guards prevent a seek/advance storm on position
                // ticks before the native transition lands.
                if (player.processingState == ProcessingState.ready) {
                  final cueSong = currentSong;
                  final cueStartMs = cueSong?.cueStartMs;
                  final cueEndMs = cueSong?.cueEndMs;
                  if (cueStartMs != null &&
                      !_cueStartSeeked &&
                      pos < Duration(milliseconds: cueStartMs)) {
                    _cueStartSeeked = true;
                    unawaited(
                        _activePlayer.seek(Duration(milliseconds: cueStartMs)));
                  }
                  if (cueEndMs != null) {
                    if (!_cueAdvanceTriggered &&
                        pos >= Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = true;
                      unawaited(skipToNext());
                    } else if (pos < Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = false;
                    }
                  }
                }
                // F11: autosave bookmark for long-form tracks (throttled 5s).
                final song = currentSong;
                if (song != null &&
                    PlaybackBookmarkStore.shouldBookmark(
                        durationMs: song.durationMs,
                        genre: song.genre,
                        album: song.album)) {
                  final nowDt = DateTime.now();
                  if (_lastBookmarkSave == null ||
                      nowDt.difference(_lastBookmarkSave!) >=
                          const Duration(seconds: 5)) {
                    _lastBookmarkSave = nowDt;
                    final key = PlaybackBookmarkStore.keyFor(
                        songId: song.id,
                        remoteId: song.remoteId,
                        path: song.path);
                    bookmarkStore.save(key, pos.inMilliseconds,
                        durationMs: song.durationMs);
                  }
                }
                // F4: report healthy playback windows for adaptive step-up.
                final nowH = DateTime.now();
                if (_lastHealthyReport == null ||
                    nowH.difference(_lastHealthyReport!) >=
                        const Duration(seconds: 30)) {
                  _lastHealthyReport = nowH;
                  unawaited(_maybeAdaptiveStepUp());
                }
              }
              final rawDuration = player.duration;
              final songDurationMs = currentSong?.durationMs ?? 0;
              final duration =
                  (rawDuration != null && rawDuration > Duration.zero)
                      ? rawDuration
                      : (songDurationMs > 0
                          ? Duration(milliseconds: songDurationMs)
                          : Duration.zero);
              // Warm the next YouTube stream URL before the crossfade window even
              // opens, so resolve latency does not truncate the fade. Cheap no-op
              // for local tracks and for an already-cached url.
              if (duration > const Duration(seconds: 15) &&
                  (pos >= duration - const Duration(seconds: 15) ||
                      pos.inMilliseconds >= duration.inMilliseconds * 0.7)) {
                _smartPrefetch();
              }
              final compensatedPos = _dspPipeline.getCompensatedPosition(pos);
              if ((_crossfadeManager.duration > Duration.zero ||
                      _crossfadeManager.automixEnabled) &&
                  !_crossfadeManager.isCrossfading &&
                  !_gaplessMode) {
                // Peek the next index (item 10): the mutating _getNextIndex()
                // appends to shuffle history and draws a fresh random pick on
                // every qualifying tick before the crossfade latches.
                final nextIdx = _getNextIndex(peek: true);
                if (nextIdx != null &&
                    nextIdx != _currentIndex &&
                    nextIdx >= 0 &&
                    nextIdx < _songs.length) {
                  // Trigger early enough for the WHOLE fade to fit before the
                  // outgoing track ends (item 9): the effective fade can exceed
                  // the base duration (BPM alignment clamps up to 20s), and
                  // _startCrossfade needs a resolve + ~1.25s settle before the
                  // ramp opens. Firing at `duration - crossfadeDuration` (base)
                  // opened the fade too late, so the outgoing track could reach
                  // ProcessingState.completed mid-fade (one-sided fade).
                  // The margin is now measured: prepare time (EWMA) plus the
                  // arbiter's 500 ms tail guard. A fixed 1.5 s margin truncated
                  // every fade whose resolve ran long, because prepare ate the
                  // margin and the arbiter then clamped the fade itself.
                  final effFade = _crossfadeManager.effectiveTransitionDuration(
                      trackId: _songs[nextIdx].id.toString());
                  final settleMargin = _crossfadeManager.triggerMargin;
                  if (duration > effFade + settleMargin &&
                      compensatedPos >= duration - effFade - settleMargin) {
                    _startCrossfade(nextIdx);
                  }
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player positionStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.androidAudioSessionIdStream.listen(
          (sessionId) {
            if (_disposed) return;
            if (isPlayerA) {
              _playerASessionId = sessionId;
            } else {
              _playerBSessionId = sessionId;
            }
            if (isTargetActive()) {
              _audioSessionIdRouter.handleSessionId(sessionId);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player androidAudioSessionIdStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.currentIndexStream.listen(
          (index) {
            if (_disposed) return;
            // Native gapless advance: the concat moved to a new item on its own.
            // Reconcile our queue model, notification, history and position-save
            // off this single source of truth instead of a manual skip.
            if (_gaplessMode &&
                isTargetActive() &&
                index != null &&
                index != _lastGaplessIndex) {
              _onGaplessIndexChanged(index);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player currentIndexStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.icyMetadataStream.listen(
          (icy) {
            if (_disposed || !isTargetActive()) return;
            final song = currentSong;
            if (song == null || !SongSource.isLive(song.source)) return;
            final rawTitle = icy?.info?.title?.trim();
            if (rawTitle == null ||
                rawTitle.isEmpty ||
                rawTitle == song.album) {
              return;
            }
            final updatedSong = song.copyWith(album: rawTitle);
            if (_currentIndex >= 0 && _currentIndex < _songs.length) {
              _songs[_currentIndex] = updatedSong;
            }
            final currentItem = mediaItem.valueOrNull;
            if (currentItem != null) {
              mediaItem.add(
                currentItem.copyWith(
                  album: rawTitle,
                  extras: <String, dynamic>{
                    ...?currentItem.extras,
                    'icyTitle': rawTitle,
                  },
                ),
              );
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player icyMetadataStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );
    }

    setupPlayerListeners(_playerA, true);
    setupPlayerListeners(_playerB, false);

    // AudioSession configuration
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Do NOT grab focus here: activating at construction steals audio focus
      // from other apps on cold start (pausing their playback) before the user
      // has played anything. just_audio activates on play()/resume and stop()
      // releases it.

      wireSessionStreams(session);
    } catch (e, st) {
      ErrorLogger.log('Error configuring AudioSession',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    _subscriptions.add(
      AudioEffectsChannel().onRouteChanged.listen((_) {
        _audioSessionIdRouter.handleRouteChanged();
        unawaited(_recordSessionRouteChange());
      }),
    );

    // Drive the loudness contour live from the ANDROID hardware media volume.
    // While the contour is off we only cache the latest ratio; the
    // software-volume path (setVolume) still owns the value in that case.
    _subscriptions.add(
      AudioEffectsChannel().onSystemVolumeChanged.listen((reading) {
        if (_dvcEnabled) {
          // DVC pins STREAM_MUSIC to maximum and applies user gain natively;
          // ignore Android's pinned max stream callbacks so `_volume` is not
          // overwritten back to 1.0.
          return;
        }
        // Route-tagged: a speaker index of 0 during a USB sink rebuild must
        // not mute the live Direct USB stream.
        final belongsToThisRoute = PulsrAudioHandler.systemVolumeReadingBelongsToRoute(
          directUsbStreaming:
              UsbExclusiveService().lastStatus.streamingActive,
          routeKnown: reading.routeKnown,
          isUsb: reading.isUsb,
        );
        final clamped = reading.isKnown && belongsToThisRoute
            ? reading.ratio.clamp(0.0, 1.0)
            : null;
        if (clamped != null) {
          _lastSystemVolumeRatio = clamped;
        }
        final forwardToOutput = _shouldForwardSystemVolumeToOutput();
        if (forwardToOutput && clamped != null) {
          _externalHardwareVolumeSet = false;
          _volume = clamped;
          if (!_volumeSubject.isClosed) {
            _volumeSubject.add(_volume);
          }
          _volumeController?.updateSettings(userVolume: _volume);
          unawaited(_pushUsbHardwareVolume());
          unawaited(_reapplyActiveVolume());
        }
        if (_equalizerManager.isLoudnessContourEnabled) {
          unawaited(_feedLoudnessContourVolume());
        }
      }),
    );

    // Initialize audio effects & equalizer preferences
    try {
      // Seed the BT mirror before effects init so the cold-start dither push
      // sees the real route when the output info is already cached.
      _syncBluetoothRouteFromCache();
      try {
        await _equalizerManager.init();
      } catch (e, st) {
        ErrorLogger.log('EqualizerManager init failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
      await _restoreBatterySaverPreference();
      unawaited(_refreshBluetoothRoute());
      try {
        // Query the system STREAM_MUSIC volume once at cold start so a restored
        // (enabled) loudness contour engages against the hardware level.
        await _refreshLoudnessContourFromSystemVolume();
      } catch (e, st) {
        ErrorLogger.log('Update loudness volume failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
      try {
        await _restoreSkipSilence();
      } catch (e, st) {
        ErrorLogger.log('Restore skip silence failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
      // F2/F7/F9–F11: restore persisted feature state (best-effort).
      try {
        await Future.wait([
          trackDelayManager.load(),
          duckingController.load(),
          silenceSkipController.load(),
          dspSnapshotStore.load(),
          bookmarkStore.load(),
          perSongPlaybackStore.load(),
        ]);
      } catch (e, st) {
        ErrorLogger.log('Restore feature stores failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
      try {
        final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
        hedgedResolutionEnabled =
            prefs.getBool(PrefsKeys.hedgedResolutionEnabled) ?? true;
        adaptiveQualityManager.enabled =
            prefs.getBool(PrefsKeys.adaptiveQualityEnabled) ?? true;
        // Don't let stale adaptive_runtime_quality override setting_streaming_quality
        final userQ = prefs.getString(PrefsKeys.streamingQuality);
        final savedQ =
            userQ ?? prefs.getString(PrefsKeys.adaptiveRuntimeQuality);
        if (savedQ != null && savedQ.isNotEmpty) {
          adaptiveQualityManager.setQuality(savedQ);
        }
      } catch (e, st) {
        ErrorLogger.log('Restore adaptive quality config failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    } finally {
      // Signal effect-state listeners (e.g. PlayerCubit) even if restore
      // partially failed, so they re-sync whatever state is available.
      if (!_effectsReadyCompleter.isCompleted) {
        _effectsReadyCompleter.complete();
      }
    }

    // Register lifecycle observer to persist playback state and manage buffers on app background/resume
    _lifecycleObserver = AudioHandlerLifecycleObserver(
      onBackground: () {
        unawaited(saveCurrentPositionImmediate());
        _equalizerManager.onAppPaused();
        _memoryManager.onAppBackgrounded(inactivePlayer: _inactivePlayer);
      },
      onDetached: () {
        unawaited(saveCurrentPositionImmediate());
      },
      onResume: () {
        if (_activePlayer.playing) {
          _smartPrefetch();
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    // Restore last played song & queue session from database with 10s timeout guard
    try {
      await restoreLastPlaybackSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _playGeneration++;
          ErrorLogger.log('restoreLastPlaybackSession timed out after 10s',
              category: 'AudioHandler');
        },
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore playback session on startup',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }
}
