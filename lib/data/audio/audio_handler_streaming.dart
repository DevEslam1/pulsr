// ignore_for_file: unused_element
part of 'audio_handler.dart';

mixin PulsrAudioStreaming on BaseAudioHandler {
  int get _preloadCountForCurrentBucket {
    switch (_currentBucket) {
      case BufferBucket.minimal:
        return 1;
      case BufferBucket.standard:
        return 2;
      case BufferBucket.generous:
        return 3;
    }
  }

  Future<void> _evaluateBufferBucket(SongsTableData song) async {
    try {
      final isLocal = song.source == SongSource.local || song.isDownloaded == true;
      final isWifi = isLocal ? false : await _ytmService.isWifiConnected();
      _adaptiveBufferEngine.evaluateBucket(isWifi: isWifi, isLocal: isLocal);
    } catch (_) {}
  }

  void _notifyTrackChanged(SongsTableData song) {
    // F1: AB loop is per-track; a new song invalidates the live region,
    // then the persisted loop for the new track (if any) is restored.
    abLoopManager.onSongChanged(song.id);
    unawaited(abLoopManager.restoreForSong(song.id));
    // T10: a new track re-arms its start seek. The advance guard is re-armed
    // by the position listener once it observes a position inside the window,
    // which prevents a stale post-advance tick from skipping the new track.
    _cueStartSeeked = false;
    // D2: seed the BPM-synced crossfade map from manual per-track overrides.
    _seedBpmOverride(song);
    // Correct DSP coefficients for the real header rate (replaces the 48kHz
    // cold-start assumption once known). A missing rate keeps the previous
    // track's coefficients, so log it loudly instead of failing silently —
    // the scanner should populate sampleRate for local files.
    final rate = song.sampleRate;
    if (rate != null && rate > 0) {
      unawaited(AudioEffectsChannel().resyncForTrack(rate.toDouble()));
      unawaited(_syncDspLatencyForTrack(rate.toDouble()));
    } else {
      ErrorLogger.log(
        'No sample rate for "${song.title}"; DSP keeps previous track coefficients',
        category: 'PulsrAudioHandler',
      );
    }
    // F9: auto-restore per-album DSP snapshot (fire-and-forget).
    if (dspSnapshotStore.enabled) {
      unawaited(recallDspSnapshotFor(song));
    }
    final previousSong = _lastPlayedSong;
    if (previousSong != null && previousSong.id != song.id) {
      _memoryManager.onTrackCompleted(previousSong.id);
      if (previousSong.remoteId != null) {
        // Prefetch registers keys as `remoteId:quality`; evict every variant.
        _memoryManager.evictByPrefix(previousSong.remoteId!);
      }
    }
    _lastPlayedSong = song;
    _onTrackChangedSubject.add(song);
    // Signature-scan local lossless files so MQA material is labeled honestly
    // instead of silently reported as plain FLAC on the next quality rebuild.
    if (song.source == SongSource.local && !song.path.startsWith('content:')) {
      final lowerPath = song.path.toLowerCase();
      if (lowerPath.endsWith('.flac') || lowerPath.endsWith('.wav')) {
        unawaited(MqaDecoderHelper.isMqaFile(song.path).then((isMqa) {
          if (isMqa) MqaDecoderHelper.markMqaPath(song.path);
        }).catchError((e, st) {
          // File vanished or unreadable mid-play: the track simply plays
          // without the MQA badge rather than failing silently (14-03).
          ErrorLogger.log('MQA signature scan failed for ${song.path}',
              error: e, stackTrace: st, category: 'AudioHandler');
        }));
      }
    }
    unawaited(_beginAudioSession(song));
    unawaited(_maybeNegotiateOutputFormat(song));
    // Native ReplayGain follows the track: push tags so the DSP pre-gain
    // tracks the new song, then re-apply the mixer volume (unity for RG
    // component when native owns it, full Dart math otherwise).
    unawaited(_pushNativeReplayGain(song));
  }

  /// Syncs native latency reporting and programs the sinc resampler with the
  /// real track-rate -> device-rate pair so 44.1k <-> 48k switches convert
  /// instead of running bypassed on stale rates.
  Future<void> _syncDspLatencyForTrack(double trackRate) async {
    double? outputRate;
    try {
      outputRate = (await _currentOutputInfo())?.sampleRate.toDouble();
    } catch (_) {}
    await _equalizerManager.syncNativeLatency(
      trackRate,
      outputRate: outputRate,
    );
  }

  /// Per-track output-format negotiation. Hi-res-first by default: the pure
  /// [negotiateOutputFormat] decision picks the best format the device supports
  /// and pushes it through the existing target-format channel (bit-perfect
  /// keeps its own exclusive mixer attributes). Smart Audio also forces this on.
  Future<void> _maybeNegotiateOutputFormat(SongsTableData song) async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      var negotiate =
          prefs.getBool(PrefsKeys.outputFormatNegotiationEnabled) ?? true;
      // Smart Audio (Auto) opts into best-quality output negotiation without
      // changing the user's explicit manual setting.
      if (!negotiate && getIt.isRegistered<SmartAudioService>()) {
        negotiate = await getIt<SmartAudioService>().isEnabled();
      }
      if (!negotiate) {
        return;
      }
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final service = getIt<HiResAudioService>();
      final info =
          service.currentOutputInfo ?? await service.getAudioOutputInfo();
      final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
          (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
      final decision = negotiateOutputFormat(
        request: OutputFormatRequest(
          trackSampleRate: song.sampleRate ?? 0,
          trackBitDepth: song.bitDepth ?? 0,
        ),
        deviceSampleRates: info.supportedSampleRates,
        deviceMaxBitDepth: info.bitDepth,
        route: OutputRoute.fromOutputInfo(info),
        bitPerfectActive: bitPerfect,
      );
      if (!decision.applied) return; // Exclusive path owns the mixer format.
      // setTargetOutputFormat only accepts the platform's known ladder; fall
      // back to "auto" for that dimension when the device reports a rate it
      // does not accept, rather than silently requesting nothing.
      const validRates = <int>{
        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 768000
      };
      final rate =
          validRates.contains(decision.sampleRate) ? decision.sampleRate : 0;
      await service.setTargetOutputFormat(
        sampleRate: rate,
        bitDepth: decision.bitDepth,
      );
    } catch (e, st) {
      ErrorLogger.log('Output format negotiation failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  AudioLoadConfiguration get currentAudioLoadConfiguration =>
      _currentAudioLoadConfiguration;

  void _onBufferBucketChanged(BufferBucket bucket) {
    if (bucket == _currentBucket) return;
    _currentBucket = bucket;
    _currentAudioLoadConfiguration = PulsrAudioHandler._loadConfigForBucket(bucket);
    debugPrint(
        '[AudioHandler] Buffer bucket transitioned to $bucket — applying load control');
    unawaited(
        _activePlayer.setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_inactivePlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_prefetchPlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
  }

  Future<void> _onQualityStepDownRequested(String newQuality) async {
    debugPrint(
        '[AudioHandler] Adaptive bitrate switching stepped down streaming quality to $newQuality');
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setString('setting_streaming_quality', newQuality);
    // Quality is part of EVERY downstream cache key: clear all of them so the
    // next resolve actually fetches the lower rendition instead of reusing a
    // stale higher-quality URL (previously only _streamCache was cleared).
    _streamCache.clear();
    _inFlightResolves.clear();
    _preloadScheduler.clear();
    // Cancel in-flight prefetches (bumps the prefetch generation) and fence any
    // in-flight foreground resolve at the old quality so it can't write a
    // stale-rendition URL back into the freshly-cleared cache.
    cancelPrefetches();
    _resolveEpoch++;
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        final urlCache = getIt<YtmUrlCache>();
        final song = currentSong;
        if (song?.remoteId != null) {
          urlCache.invalidate(song!.remoteId!);
        }
      }
    } catch (_) {}
  }

  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag) {
    if (PulsrAudioHandler._isStreamUrl(song.path)) {
      return AudioSource.uri(Uri.parse(song.path), tag: tag);
    }
    if (song.uri?.startsWith('content:') == true ||
        song.path.startsWith('content:')) {
      return AudioSource.uri(Uri.parse(song.uri ?? song.path), tag: tag);
    }
    return AudioSource.file(song.path, tag: tag);
  }

  void _handleStreamResolutionError(SongsTableData song, Object error) {
    final info = YtmErrorClassifier.classify(error);
    final String errorMessage;
    if (error is PlayerException &&
        error.message != null &&
        error.message!.isNotEmpty) {
      errorMessage = error.message!;
    } else {
      errorMessage = info.message;
    }
    ErrorLogger.log(
      'Gapless stream resolution error on "${song.title}": $errorMessage ($error)',
      category: 'AudioHandler',
    );
    _errorSubject.add(errorMessage);

    // Invalidate poToken only on a verdict that a fresh attestation can fix.
    // `contains('403')` matched the digits anywhere in the message — including
    // inside a video id, an itag or a byte count — and bare `bot` matched
    // "bottleneck", so ordinary failures kept throwing away a working token and
    // paying for a new BotGuard round on the next track.
    final signal = info.signal;
    if (signal == YtmBlockSignal.botChallenge ||
        signal == YtmBlockSignal.poTokenInvalid) {
      _ytmService.invalidatePoToken().catchError((e, st) {
        ErrorLogger.log('poToken invalidation failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      });
    }
    // CRITICAL GUARD: If the error occurred on a pre-fetched background track or queued item
    // that is not currently playing, NEVER pause playback, skip, or increment failures!
    final activeSong = currentSong;
    final isCurrentTrack = activeSong != null &&
        (activeSong.id == song.id ||
            (song.remoteId != null &&
                song.remoteId!.isNotEmpty &&
                activeSong.remoteId == song.remoteId));

    if (!isCurrentTrack) {
      debugPrint(
          '[AudioHandler] Background pre-fetch failed for "${song.title}", keeping active playback alive.');
      return;
    }

    if (!_activePlayer.playing) {
      debugPrint('[AudioHandler] Resolution failed while paused — stopping loop.');
      return;
    }
    if (info.recoveryAction == YtmRecoveryAction.skipToNextTrack) {
      // Count this failure before deciding. The previous code only read the
      // counter, which the following gapless advance reset, so a queue full of
      // blocked/unavailable tracks skipped forever without ever tripping.
      _consecutiveFailures++;
      if (PulsrAudioHandler.shouldHaltFailureCascade(
        consecutiveFailures: _consecutiveFailures,
        rapidGaplessChanges: _rapidGaplessChangeCount,
        queueLength: _songs.length,
      )) {
        _consecutiveFailures = 0;
        _rapidGaplessChangeCount = 0;
        _errorSubject.add('Playback stopped: multiple tracks could not be played.');
        _activePlayer.pause().ignore();
        _broadcastState(_activePlayer.playbackEvent);
        return;
      }
      debugPrint('[AudioHandler] Track blocked/unavailable. Skipping to next.');
      unawaited(skipToNext());
      return;
    }

    final isFatal = error is YtmException
        ? error.isFatal
        : (info.recoveryAction != YtmRecoveryAction.retryWithBackoff);

    if (isFatal) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _activePlayer.pause().ignore();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
        _consecutiveFailures = 0;
        _rapidGaplessChangeCount = 0;
        _activePlayer.pause().ignore();
        _broadcastState(_activePlayer.playbackEvent);
      } else {
        unawaited(skipToNext());
      }
    }
  }

  AudioSource _buildGaplessChild(SongsTableData song) {
    final tag = PulsrAudioHandler._songToMediaItem(song);
    // HTTP streams are not files: skip the disk/format/trim paths and hand
    // the URL to just_audio directly (HLS auto-detected).
    if (PulsrAudioHandler._isStreamUrl(song.path)) {
      return _createAudioSource(song, tag);
    }
    final isRemoteYtm = song.source == SongSource.youtube &&
        (song.path.startsWith('ytmusic://') || song.path.isEmpty) &&
        song.isDownloaded != true;
    final isLocalFile = !isRemoteYtm &&
        (!song.path.startsWith('ytmusic://') && song.path.isNotEmpty) &&
        (song.path.startsWith('content:') ||
            song.isDownloaded == true ||
            (_pathExistsCache[song.path] ??= File(song.path).existsSync()));
    // FIX-#8: Evict oldest 25% when the cache exceeds the bound to prevent
    // an unbounded memory leak over long listening sessions.
    if (_pathExistsCache.length > PulsrAudioHandler._maxPathCacheSize) {
      final keys = _pathExistsCache.keys.toList();
      for (var i = 0; i < keys.length ~/ 4; i++) {
        _pathExistsCache.remove(keys[i]);
      }
    }
    final isRemote = song.source == SongSource.youtube && !isLocalFile;
    if (isRemote) {
      late final YtmResolvingSource source;
      source = YtmResolvingSource.withRefresh(
        videoId: song.remoteId ?? '',
        quality: _currentStreamingQuality(),
        resolve: ({bool forceRefresh = false}) async {
          final resolved =
              await _resolveStreamUrl(song, forceRefresh: forceRefresh);
          source.userAgent = resolved.userAgent;
          source.cookies = resolved.cookies;
          source.quality = resolved.quality;
          return resolved.url;
        },
        onError: (error) => _handleStreamResolutionError(song, error),
        tag: tag,
      );
      return source;
    }
    final base = _createAudioSource(song, tag);
    // Apply codec encoder-delay/padding trims so Opus/MP3/AAC joins are
    // truly gapless instead of carrying ~6-48ms of silence.
    try {
      final trim = GaplessTrimHandler.trimFor(
        path: song.path,
        codec: song.codec,
      );
      if (!trim.isEmpty) {
        final trackLen = Duration(milliseconds: song.durationMs);
        final clamped = trim.clampedTo(trackLen);
        final start = GaplessTrimHandler.startOffset(clamped);
        final end = trackLen > Duration.zero
            ? GaplessTrimHandler.effectiveEnd(trackLen, clamped)
            : null;
        if (start > Duration.zero || (end != null && end < trackLen)) {
          return ClippingAudioSource(
            start: start == Duration.zero ? null : start,
            end: (end == null || end >= trackLen) ? null : end,
            child: base,
            tag: tag,
          );
        }
      }
    } catch (_) {}
    return base;
  }

  List<AudioSource> _buildAudioSources(List<SongsTableData> songs) {
    return songs.map(_buildGaplessChild).toList();
  }

  /// A local song plays straight off disk; a YouTube row needs a freshly
  /// resolved URL, because the last one expires within hours and is pinned to
  /// this device's IP. Used by the crossfade engine, which loads one track at a
  /// time. (The gapless engine instead uses [_buildGaplessChild], whose
  /// [YtmResolvingSource] both resolves lazily and caches fetched bytes so a
  /// backward seek does not re-hit an already-expired URL.)
  Future<AudioSource> _resolveAudioSource(
      SongsTableData song, MediaItem tag) async {
    // A pseudo-song whose path is a stream URL: no local match, no MQA/DSD
    // decode, no cache — just build a URI source.
    if (PulsrAudioHandler._isStreamUrl(song.path)) {
      return _createAudioSource(song, tag);
    }
    if (song.source != SongSource.youtube) {
      final cleanPath = song.path.split('?').first;
      final dot = cleanPath.lastIndexOf('.');
      final ext = dot >= 0 ? cleanPath.substring(dot + 1).toLowerCase() : '';
      if (ext == 'dsf' || ext == 'dff') {
        // T4: honor the user's DSD output mode, but only after the native probe
        // confirms a DoP-capable USB DAC. Default is PCM; DoP is never implied
        // by the file format or by an absent/failed probe.
        final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
        final wantDop =
            (prefs.getString(PrefsKeys.dsdOutputMode) ?? 'pcm') == 'dop';
        DsdDacCapabilities? caps;
        if (wantDop) {
          caps = await DsdDecoderHelper.probeDopCapabilities();
        }
        final forceDop = wantDop && (caps?.canUseDop ?? false);
        final containerBits = prefs.getInt(PrefsKeys.dopContainerBits) ?? 24;
        return DsdDecoderHelper.decodeDsdFile(
          song,
          tag,
          forceDop: forceDop,
          dopCapabilities: caps,
          dopContainerBits: containerBits == 32 ? 32 : 24,
        );
      }
      // Route lossless containers through the format-aware decoder so MQA files
      // are detected (and unfolded when the helper is enabled) instead of
      // silently playing as plain FLAC. content:// URIs are excluded: the
      // decoder builds a file URI and cannot read through a content resolver.
      if ((ext == 'flac' || ext == 'wav') &&
          !song.path.startsWith('content:') &&
          song.uri?.startsWith('content:') != true) {
        return _formatDecoder.decodeForFormat(song, tag);
      }
      return _createAudioSource(song, tag);
    }

    // Direct fast path for downloaded songs with physical file on disk or content URI
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || await File(song.path).exists())) {
      return _createAudioSource(song, tag);
    }

    try {
      final localMatch = await _repository.findMatchingLocalSong(
        remoteId: song.remoteId,
        title: song.title,
        artist: song.artist,
      );
      final localSong = localMatch.fold((_) => null, (s) => s);
      if (localSong != null &&
          (localSong.path.startsWith('content:') ||
              (localSong.uri != null &&
                  localSong.uri!.startsWith('content:')) ||
              await File(localSong.path).exists())) {
        return _createAudioSource(localSong, tag);
      }
    } catch (_) {
      // If local check fails, fall through to stream resolution
    }

    // Fast-path: check if YouTube track is already cached in local disk stream cache
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      final cachedFile = await YtmCacheManager()
          .getCachedAudioFile(song.remoteId!, quality: _currentStreamingQuality());
      if (cachedFile != null) {
        return AudioSource.file(cachedFile.path, tag: tag);
      }
    }

    // Use lazy YtmResolvingSource: just_audio calls request() when it needs
    // bytes, which triggers the resolve chain. This lets the player accept
    // the source instantly (no blocking await on stream resolution) and start
    // buffering as soon as bytes arrive. If the background warm populated the
    // URL cache, the lazy resolve completes near-instantly.
    late final YtmResolvingSource source;
    source = YtmResolvingSource.withRefresh(
      videoId: song.remoteId ?? '',
      quality: _currentStreamingQuality(),
      resolve: ({bool forceRefresh = false}) async {
        final resolved =
            await _resolveStreamUrl(song, forceRefresh: forceRefresh);
        source.userAgent = resolved.userAgent;
        source.cookies = resolved.cookies;
        source.quality = resolved.quality;
        return resolved.url;
      },
      onError: (error) => _handleStreamResolutionError(song, error),
      tag: tag,
    );
    return source;
  }

  /// Non-blocking background cache warm for [song]. Populates the stream URL
  /// cache so a subsequent lazy resolve completes near-instantly.
  Future<void> _warmStreamCache(SongsTableData song) async {
    if (_ytmService.isBotCoolingDown) return;
    try {
      await _resolveStreamUrl(song).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  void _addToStreamCache(
      String key,
      ({
        String url,
        DateTime expires,
        String? userAgent,
        String? cookies
      }) entry) {
    if (_streamCache.length >= PulsrAudioHandler._maxStreamCacheEntries) {
      _streamCache.remove(_streamCache.keys.first);
    }
    _streamCache[key] = entry;
  }

  /// Quick soft-landing before a hard stop/swap: stopping mid-waveform without
  /// a fade cuts the signal at a non-zero crossing, which the ear hears as a
  /// click/pop on every manual track change. 70ms is inaudible as a delay.
  Future<void> _fadeOutForSwitch(AudioPlayer player) async {
    try {
      if (!player.playing) return;
      final from = player.volume;
      if (from <= 0.01) return;
      await _crossfadeManager
          .fadeVolume(player, from, 0.0, const Duration(milliseconds: 70),
              _crossfadeManager.nextFadeId())
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  /// Matching fade-in after a switch: starting at 0 and ramping to the
  /// ReplayGain target avoids the cold-start click. Skipped while ducked
  /// (navigation/call) so the ramp never fights the duck level.
  void _fadeInAfterSwitch(AudioPlayer player, double targetVolume) {
    if (_duckActive) return;
    unawaited(_crossfadeManager.fadeVolume(
        player,
        0.0,
        targetVolume.clamp(0.0, 1.0),
        const Duration(milliseconds: 90),
        _crossfadeManager.nextFadeId()));
  }

  /// Safety net for the cold-start fade-in: the 90ms ramp is unawaited and can
  /// be orphaned by a racing fade-id bump, a cancelled crossfade, or a play()
  /// interrupted mid-load, leaving the player audibly running at volume 0
  /// until the user pauses and resumes. A short convergence check restores the
  /// ReplayGain target when the player is ready and playing but still muted.
  void _scheduleFadeInConvergenceGuard(AudioPlayer player, int generation) {
    if (_duckActive) return;
    var attempts = 0;
    // FIX-#12: Cancel any previous guard and store the new timer so it can
    // be disposed on onTaskRemoved / hot-restart.
    _fadeInGuardTimer?.cancel();
    _fadeInGuardTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      attempts++;
      try {
        if (attempts > 8 ||
            generation != _playGeneration ||
            !identical(player, _activePlayer) ||
            _duckActive ||
            _crossfadeManager.isCrossfading ||
            !player.playing) {
          timer.cancel();
          return;
        }
        if (player.volume > 0.01) {
          timer.cancel();
          return;
        }
        // Player is playing but volume is still muted
        final target = _calculateReplayGainVolume(currentSong).clamp(0.0, 1.0);
        if (target > 0.05) {
          ErrorLogger.log(
              'Cold-start fade-in did not converge (attempt $attempts); restoring target volume',
              category: 'AudioHandler');
          await player.setVolume(target);
          timer.cancel();
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  void cancelPrefetches() {
    _prefetchGeneration++;
    _prefetching.clear();
  }

  /// Clears all IP-bound stream URL caches and DNS-era state.
  ///
  /// Call on VPN/network-path change: googlevideo URLs carry an IP-bound
  /// `expire`/`ip` signature and return 403 when the egress IP changes.
  void clearNetworkCaches() {
    _streamCache.clear();
    _inFlightResolves.clear();
    _prefetching.clear();
    cancelPrefetches();
    // Fence any in-flight resolve started before the path change so its result
    // (bound to the old egress IP) can't repopulate the cache with a URL that
    // will 403 on the new path.
    _resolveEpoch++;
  }

  // --- SkipSilence + Normalization (InnerTune parity) ---
  bool get skipSilenceEnabled => _activePlayer.skipSilenceEnabled;

  Future<void> setSkipSilenceEnabled(bool enabled) async {
    try {
      silenceSkipController.setEnabled(enabled);
      await _playerA.setSkipSilenceEnabled(enabled);
      await _playerB.setSkipSilenceEnabled(enabled);
      await silenceSkipController.persist();
    } catch (e, st) {
      ErrorLogger.log('Failed to set skipSilence', error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Pushes the opt-in 24/32-bit float DSP-path preference to every player
  /// (active, inactive and prefetch). Off by default; with `false` the native
  /// sink is built exactly as before. Never throws.
  Future<void> setFloatOutputEnabled(bool enabled) async {
    await pushFloatOutputToPlayers(
      enabled,
      [_playerA, _playerB, _prefetchPlayer],
    );
  }

  /// Resampler quality (0=Fast/linear .. 3=Ultra/64-tap). Best-effort push.
  Future<void> setSincResamplerQuality(int quality) async {
    await AudioEffectsChannel().setSincResamplerQuality(quality);
  }

  /// BPM-synced crossfade toggle on the shared crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    _crossfadeManager.bpmSyncEnabled = enabled;
  }

  /// Seeds the crossfade BPM map for [song] from manual overrides.
  /// Keeps the map bounded: entries for tracks outside the queue are dropped.
  void _seedBpmOverride(SongsTableData song) {
    try {
      final trackId = song.id.toString();
      final bpm = bpmOverrideStore.getBpmForTrack(PulsrAudioHandler.trackKeyFor(song));
      final mgr = _crossfadeManager;
      if (bpm != null) {
        mgr.bpmOverrides[trackId] = bpm;
      } else {
        mgr.bpmOverrides.remove(trackId);
      }
      if (mgr.bpmOverrides.length > 500) {
        final keep = _songs.map((s) => s.id.toString()).toSet();
        mgr.bpmOverrides.removeWhere((k, _) => !keep.contains(k));
      }
    } catch (_) {}
  }

  /// Sets (or clears with null) the manual BPM override for [song].
  /// Returns false when out of the 40–240 range.
  Future<bool> setTrackBpm(SongsTableData song, double? bpm) async {
    final ok =
        await bpmOverrideStore.setBpmForTrack(PulsrAudioHandler.trackKeyFor(song), bpm);
    if (ok) _seedBpmOverride(song);
    return ok;
  }

  /// Pushes the opt-in AAudio Direct output preference to every player
  /// (active, inactive and prefetch). Off by default; with `false` the sink
  /// stays the historical DefaultAudioSink path. Never throws.
  Future<void> setAaudioOutputEnabled(bool enabled,
      {bool preferExclusive = true, int targetBufferMs = 150}) async {
    await pushAaudioOutputToPlayers(
      enabled,
      preferExclusive: preferExclusive,
      targetBufferMs: targetBufferMs,
      players: [_playerA, _playerB, _prefetchPlayer],
    );
  }

  Future<void> _restoreSkipSilence() async {
    try {
      await silenceSkipController.load();
      final enabled = silenceSkipController.enabled;
      if (enabled) {
        await _playerA.setSkipSilenceEnabled(true);
        await _playerB.setSkipSilenceEnabled(true);
      }
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      final normEnabled = prefs.getBool('audio_normalization_enabled') ?? false;
      final savedBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost);
      if (normEnabled && (savedBoost == null || savedBoost == 0.0)) {
        // Apply mild loudness normalization for streams without ReplayGain tags only if user hasn't set custom boost
        await _equalizerManager.setVolumeBoost(0.35);
      }
    } catch (_) {}
  }

  Future<void> setAudioNormalizationEnabled(bool enabled) async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setBool('audio_normalization_enabled', enabled);
      if (enabled) {
        if (_equalizerManager.volumeBoost == 0.0) {
          await _equalizerManager.setVolumeBoost(0.35);
        }
      } else {
        if (_equalizerManager.volumeBoost == 0.35) {
          await _equalizerManager.setVolumeBoost(0.0);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set normalization', error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  bool get isAudioNormalizationEnabled {
    try {
      return _cachedPrefs?.getBool('audio_normalization_enabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Warms [_streamCache] for an upcoming YouTube track so track switching is instant.
  void _prefetchStream(SongsTableData song) {
    final videoId = song.remoteId;
    if (song.source != SongSource.youtube ||
        videoId == null ||
        videoId.isEmpty) {
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) || videoId.startsWith('n_')) return;
    // Skip prefetch if downloaded/local file exists
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || song.isDownloaded == true)) {
      return;
    }
    // Avoid launching background prefetch storms if playback failures are occurring
    if (_consecutiveFailures >= 3) {
      return;
    }
    // While the IP is cooling down every resolve fails instantly with the same
    // BOT_CHALLENGE, so prefetching only burns log lines and thread-pool slots.
    // The foreground resolve retries once the window lapses.
    if (_ytmService.isBotCoolingDown) {
      return;
    }
    // Deduplicate against active stream pre-resolver (quality-aware: a
    // medium prefetch must not block a high foreground resolve).
    final prefetchKey = '$videoId:${_currentStreamingQuality().toLowerCase()}';
    if (_streamPreResolver.inFlightVideoId == videoId) {
      return;
    }
    final isBatteryConstrained =
        _batteryAwarePlayback.currentLevel != BatteryOptimizationLevel.normal;
    if (!_memoryManager.canPreload(isBatteryConstrained: isBatteryConstrained)) {
      return;
    }
    if (!_prefetching.add(prefetchKey)) {
      return;
    }
    _memoryManager.registerPreload(
      prefetchKey,
      AudioMemoryManager.calculateHeadSize(bitrateKbps: song.bitrateKbps ?? 256),
    );
    final currentGen = _prefetchGeneration;
    _resolveStreamUrl(song).whenComplete(() {
      if (_prefetchGeneration == currentGen) {
        _prefetching.remove(prefetchKey);
      }
    }).ignore();
  }

  bool _isConsecutiveAlbumPlayback() {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return false;
    }
    final currentAlbum = _songs[_currentIndex].album;
    if (currentAlbum == 'Unknown Album' || currentAlbum.isEmpty) return false;
    if (_currentIndex > 0 && _songs[_currentIndex - 1].album == currentAlbum) {
      return true;
    }
    if (_currentIndex + 1 < _songs.length &&
        _songs[_currentIndex + 1].album == currentAlbum) {
      return true;
    }
    return false;
  }

  void _smartPrefetch() {
    if (_songs.isEmpty || _currentIndex < 0 || _consecutiveFailures >= 3) return;
    if (_batteryAwarePlayback.currentLevel ==
        BatteryOptimizationLevel.critical) {
      return;
    }
    // Throttle: position ticks fire continuously in the last 30s of a track;
    // without this the same videoId is re-scheduled on every tick.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key =
        '${_currentIndex}_${_songs[_currentIndex].remoteId ?? _songs[_currentIndex].id}';
    if (key == _lastSmartPrefetchKey && nowMs - _lastSmartPrefetchMs < 10000) {
      return;
    }
    _lastSmartPrefetchMs = nowMs;
    _lastSmartPrefetchKey = key;
    // Forward the player's shuffle order so the scheduler warms the tracks that
    // actually play next in shuffle, instead of uniformly-random picks. Only
    // pass it when it lines up with our queue; otherwise the scheduler falls
    // back to random on its own.
    final shuffleOrder = _activePlayer.shuffleIndices;
    final shuffleIndices =
        shuffleOrder.length == _songs.length ? shuffleOrder : null;
    _preloadScheduler.schedulePreloads(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
      shuffleIndices: shuffleIndices,
      position: _activePlayer.position,
      duration: _activePlayer.duration ?? Duration.zero,
      preloadCount: _preloadCountForCurrentBucket,
    );
  }

  void _prefetchNextTracks() {
    _smartPrefetch();
  }


























































































































































































































































































  // Requires: provided by the composing class (same library).
  AudioPlayer get _activePlayer;

  // Requires: provided by the composing class (same library).
  AdaptiveBufferEngine get _adaptiveBufferEngine;

  // Requires: provided by the composing class (same library).
  BatteryAwarePlayback get _batteryAwarePlayback;

  // Requires: provided by the composing class (same library).
  Future<void> _beginAudioSession(SongsTableData song);

  // Requires: provided by the composing class (same library).
  void _broadcastState(PlaybackEvent event);

  // Requires: provided by the composing class (same library).
  SharedPreferences? get _cachedPrefs;
  set _cachedPrefs(SharedPreferences? value);

  // Requires: provided by the composing class (same library).
  double _calculateReplayGainVolume(SongsTableData? song);

  // Requires: provided by the composing class (same library).
  int get _consecutiveFailures;
  set _consecutiveFailures(int value);

  // Requires: provided by the composing class (same library).
  CrossfadeManager get _crossfadeManager;

  // Requires: provided by the composing class (same library).
  bool get _cueStartSeeked;
  set _cueStartSeeked(bool value);

  // Requires: provided by the composing class (same library).
  AudioLoadConfiguration get _currentAudioLoadConfiguration;
  set _currentAudioLoadConfiguration(AudioLoadConfiguration value);

  // Requires: provided by the composing class (same library).
  BufferBucket get _currentBucket;
  set _currentBucket(BufferBucket value);

  // Requires: provided by the composing class (same library).
  int get _currentIndex;

  // Requires: provided by the composing class (same library).
  Future<AudioOutputInfo?> _currentOutputInfo();

  // Requires: provided by the composing class (same library).
  String _currentStreamingQuality();

  // Requires: provided by the composing class (same library).
  bool get _duckActive;

  // Requires: provided by the composing class (same library).
  EqualizerManager get _equalizerManager;

  // Requires: provided by the composing class (same library).
  StreamController<String> get _errorSubject;

  // Requires: provided by the composing class (same library).
  Timer? get _fadeInGuardTimer;
  set _fadeInGuardTimer(Timer? value);

  // Requires: provided by the composing class (same library).
  FormatAwareDecoder get _formatDecoder;

  // Requires: provided by the composing class (same library).
  dynamic get _inFlightResolves;

  // Requires: provided by the composing class (same library).
  AudioPlayer get _inactivePlayer;

  // Requires: provided by the composing class (same library).
  SongsTableData? get _lastPlayedSong;
  set _lastPlayedSong(SongsTableData? value);

  // Requires: provided by the composing class (same library).
  String? get _lastSmartPrefetchKey;
  set _lastSmartPrefetchKey(String? value);

  // Requires: provided by the composing class (same library).
  int get _lastSmartPrefetchMs;
  set _lastSmartPrefetchMs(int value);

  // Requires: provided by the composing class (same library).
  AudioMemoryManager get _memoryManager;

  // Requires: provided by the composing class (same library).
  StreamController<SongsTableData> get _onTrackChangedSubject;

  // Requires: provided by the composing class (same library).
  Map<String, bool> get _pathExistsCache;

  // Requires: provided by the composing class (same library).
  int get _playGeneration;

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerA;

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerB;

  // Requires: provided by the composing class (same library).
  int get _prefetchGeneration;
  set _prefetchGeneration(int value);

  // Requires: provided by the composing class (same library).
  // Bumped on network-path/quality changes to fence stale in-flight resolves.
  int get _resolveEpoch;
  set _resolveEpoch(int value);

  // Requires: provided by the composing class (same library).
  AudioPlayer get _prefetchPlayer;

  // Requires: provided by the composing class (same library).
  Set<String> get _prefetching;

  // Requires: provided by the composing class (same library).
  SmartPreloadScheduler get _preloadScheduler;

  // Requires: provided by the composing class (same library).
  Future<void> _pushNativeReplayGain(SongsTableData? song);

  // Requires: provided by the composing class (same library).
  int get _rapidGaplessChangeCount;
  set _rapidGaplessChangeCount(int value);

  // Requires: provided by the composing class (same library).
  IMusicRepository get _repository;

  // Requires: provided by the composing class (same library).
  Future<({String url, String? userAgent, String? cookies, String quality})> _resolveStreamUrl(SongsTableData song, {bool forceRefresh = false});

  // Requires: provided by the composing class (same library).
  List<SongsTableData> get _songs;

  // Requires: provided by the composing class (same library).
  dynamic get _streamCache;

  // Requires: provided by the composing class (same library).
  StreamPreResolver get _streamPreResolver;

  // Requires: provided by the composing class (same library).
  YtmService get _ytmService;

  // Requires: provided by the composing class (same library).
  AbLoopManager get abLoopManager;

  // Requires: provided by the composing class (same library).
  BpmOverrideStore get bpmOverrideStore;

  // Requires: provided by the composing class (same library).
  SongsTableData? get currentSong;

  // Requires: provided by the composing class (same library).
  dynamic get dspSnapshotStore;

  // Requires: provided by the composing class (same library).
  Future<bool> recallDspSnapshotFor(SongsTableData song);

  // Requires: provided by the composing class (same library).
  SilenceSkipController get silenceSkipController;
}
