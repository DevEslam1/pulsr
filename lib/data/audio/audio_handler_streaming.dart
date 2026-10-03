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

  AudioLoadConfiguration get currentAudioLoadConfiguration =>
      _currentAudioLoadConfiguration;

  void _onBufferBucketChanged(BufferBucket bucket) {
    if (bucket == _currentBucket) return;
    _currentBucket = bucket;
    _currentAudioLoadConfiguration =
        PulsrAudioHandler._loadConfigForBucket(bucket);
    debugPrint(
        '[AudioHandler] Buffer bucket transitioned to $bucket — applying load control');
    unawaited(_activePlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_inactivePlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_prefetchPlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
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

    // Only a failure on the track the user is actually on is worth surfacing.
    // Background pre-fetches (online carousels, lookahead, gapless preloads)
    // fail silently above; pushing them to `_errorSubject` spammed the app-level
    // toast with "No connection" even when nothing was playing.
    _errorSubject.add(errorMessage);

    if (!_activePlayer.playing) {
      debugPrint(
          '[AudioHandler] Resolution failed while paused — stopping loop.');
      return;
    }
    if (info.recoveryAction == YtmRecoveryAction.skipToNextTrack) {
      // Already 2 rapid gaps means 3rd song in your loop → pause instead of skip
      if (_consecutiveFailures >= 2) {
        _consecutiveFailures = 0;
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
      _activePlayer.pause().ignore();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      _consecutiveFailures++;
      if (PulsrAudioHandler.shouldHaltFailureCascade(
        consecutiveFailures: _consecutiveFailures,
        rapidGaplessChanges: 0,
        queueLength: _songs.length,
      )) {
        _consecutiveFailures = 0;
        _activePlayer.pause().ignore();
        _broadcastState(_activePlayer.playbackEvent);
      } else {
        unawaited(skipToNext());
      }
    }
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
      final cachedFile = await YtmCacheManager().getCachedAudioFile(
          song.remoteId!,
          quality: _currentStreamingQuality());
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

  void cancelPrefetches() {
    _prefetchGeneration++;
    _prefetching.clear();
  }

  /// Clears all IP-bound stream URL caches and DNS-era state.
  ///
  /// Call on VPN/network-path change: googlevideo URLs carry an IP-bound
  /// `expire`/`ip` signature and return 403 when the egress IP changes.
  void clearNetworkCaches() {
    _resolveEpoch++;
    _streamCache.clear();
    _inFlightResolves.clear();
    _prefetching.clear();
    cancelPrefetches();
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
      ErrorLogger.log('Failed to set skipSilence',
          error: e, stackTrace: st, category: 'AudioHandler');
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
      final bpm =
          bpmOverrideStore.getBpmForTrack(PulsrAudioHandler.trackKeyFor(song));
      final mgr = _crossfadeManager;
      if (bpm != null) {
        mgr.bpmOverrides[trackId] = bpm;
      } else {
        mgr.bpmOverrides.remove(trackId);
      }
      if (mgr.bpmOverrides.length > 500 && _songs.isNotEmpty) {
        final keep = _songs.map((s) => s.id.toString()).toSet();
        mgr.bpmOverrides.removeWhere((k, _) => !keep.contains(k));
      }
    } catch (_) {}
  }

  /// Sets (or clears with null) the manual BPM override for [song].
  /// Returns false when out of the 40–240 range.
  Future<bool> setTrackBpm(SongsTableData song, double? bpm) async {
    final ok = await bpmOverrideStore.setBpmForTrack(
        PulsrAudioHandler.trackKeyFor(song), bpm);
    if (ok) _seedBpmOverride(song);
    return ok;
  }

  /// Pushes the opt-in AAudio Direct output preference to every player
  /// (active, inactive and prefetch). Off by default; with `false` the sink
  /// stays the historical DefaultAudioSink path. Never throws.
  Future<bool> setAaudioOutputEnabled(bool enabled,
      {bool preferExclusive = true, int targetBufferMs = 150}) async {
    return pushAaudioOutputToPlayers(
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
      ErrorLogger.log('Failed to set normalization',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  bool get isAudioNormalizationEnabled {
    try {
      return _cachedPrefs?.getBool('audio_normalization_enabled') ?? false;
    } catch (_) {
      return false;
    }
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
    if (_songs.isEmpty || _currentIndex < 0 || _consecutiveFailures >= 3) {
      return;
    }
    if (_batteryAwarePlayback.currentLevel ==
        BatteryOptimizationLevel.critical) {
      return;
    }
    // Throttle: position ticks fire continuously in the last 30s of a track;
    // without this the same videoId is re-scheduled on every tick.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final song = _songs[_currentIndex];
    final stableId =
        (song.remoteId?.isNotEmpty ?? false) ? song.remoteId! : song.path;
    final key = '${_currentIndex}_$stableId';
    if (key == _lastSmartPrefetchKey && nowMs - _lastSmartPrefetchMs < 10000) {
      return;
    }
    _lastSmartPrefetchMs = nowMs;
    _lastSmartPrefetchKey = key;
    _preloadScheduler.schedulePreloads(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
      position: _activePlayer.position,
      duration: _activePlayer.duration ?? Duration.zero,
      // Thread the real gapless shuffle order so gapless shuffle preloads the
      // actual successor (item 7). Only in gapless mode: the crossfade engine
      // holds a single source on the active player.
      shuffleIndices: _gaplessMode ? _activePlayer.shuffleIndices : null,
      // Non-gapless shuffle: pin the pre-committed next pick so the scheduler
      // preloads exactly the track the next advance plays instead of its own
      // independent random guess.
      explicitNextSong: _nonGaplessShuffleNextSong(),
      preloadCount: _preloadCountForCurrentBucket,
    );
  }

  // Abstract contract supplied by the composing PulsrAudioHandler (same
  // library). Declaring these here keeps the mixin stateless and lets the
  // analyser type-check each mixin against the host's private members.
  AudioPlayer get _activePlayer;

  BatteryAwarePlayback get _batteryAwarePlayback;

  void _broadcastState(PlaybackEvent event);

  SharedPreferences? get _cachedPrefs;

  int get _consecutiveFailures;
  set _consecutiveFailures(int value);

  CrossfadeManager get _crossfadeManager;

  AudioLoadConfiguration get _currentAudioLoadConfiguration;
  set _currentAudioLoadConfiguration(AudioLoadConfiguration value);

  BufferBucket get _currentBucket;
  set _currentBucket(BufferBucket value);

  int get _currentIndex;

  String _currentStreamingQuality();

  bool get _gaplessMode;

  /// Supplied by [PulsrAudioQueueEngine]: the pre-committed non-gapless shuffle
  /// successor to warm, or null (gapless / not shuffling / no next).
  SongsTableData? _nonGaplessShuffleNextSong();

  EqualizerManager get _equalizerManager;

  StreamController<String> get _errorSubject;

  FormatAwareDecoder get _formatDecoder;

  dynamic get _inFlightResolves;

  AudioPlayer get _inactivePlayer;

  String? get _lastSmartPrefetchKey;
  set _lastSmartPrefetchKey(String? value);

  int get _lastSmartPrefetchMs;
  set _lastSmartPrefetchMs(int value);

  AudioPlayer get _playerA;

  AudioPlayer get _playerB;

  int get _prefetchGeneration;
  set _prefetchGeneration(int value);

  AudioPlayer get _prefetchPlayer;

  Set<String> get _prefetching;

  SmartPreloadScheduler get _preloadScheduler;

  IMusicRepository get _repository;

  int get _resolveEpoch;
  set _resolveEpoch(int value);

  Future<({String url, String? userAgent, String? cookies, String quality})>
      _resolveStreamUrl(SongsTableData song, {bool forceRefresh = false});

  List<SongsTableData> get _songs;

  dynamic get _streamCache;

  YtmService get _ytmService;

  AbLoopManager get abLoopManager;

  BpmOverrideStore get bpmOverrideStore;

  SongsTableData? get currentSong;

  dynamic get dspSnapshotStore;

  Future<bool> recallDspSnapshotFor(SongsTableData song);

  SilenceSkipController get silenceSkipController;

  PerSongPlaybackStore get perSongPlaybackStore;
  Future<void> setPitch(double pitch);
  Future<void> restorePersistedSpeed();
  Future<void> restorePersistedPitch();
}
