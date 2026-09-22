part of 'audio_handler.dart';

mixin PulsrAudioPlaybackExtras on BaseAudioHandler {
  // ── F1–F11 public API ──────────────────────────────────────────────
  // F1: AB loop
  void setAbPointA(Duration pos) =>
      abLoopManager.setA(pos, songId: currentSong?.id);

  void setAbPointB(Duration pos) =>
      abLoopManager.setB(pos, songId: currentSong?.id);

  void toggleAbLoop() => abLoopManager.toggle();

  void clearAbLoop() => abLoopManager.clear();

  /// Re-restores the persisted AB loop for the current song. Used by the
  /// PlayerCubit to sync loop UI after a track change completes.
  Future<void> restoreAbLoopForCurrentSong() async {
    final song = currentSong;
    if (song == null) return;
    await abLoopManager.restoreForSong(song.id);
  }

  // F2: per-track delay
  String? get _currentTrackKey {
    final s = currentSong;
    if (s == null) return null;
    return TrackDelayManager.keyFor(
        songId: s.id, remoteId: s.remoteId, path: s.path);
  }

  int get currentTrackDelayMs =>
      _currentTrackKey == null ? 0 : trackDelayManager.getDelayMs(_currentTrackKey!);

  Duration get delayCompensatedPosition {
    final key = _currentTrackKey;
    return trackDelayManager.compensatedPosition(key, _activePlayer.position);
  }

  Future<void> setCurrentTrackDelay(int ms) async {
    final key = _currentTrackKey;
    if (key == null) return;
    trackDelayManager.setDelay(key, ms);
    await trackDelayManager.persist();
  }

  Future<void> setTrackDelayFor(String key, int ms) async {
    trackDelayManager.setDelay(key, ms);
    await trackDelayManager.persist();
  }

  // F3: hedged resolution toggle
  Future<void> setHedgedResolutionEnabled(bool v) async {
    hedgedResolutionEnabled = v;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('hedged_resolution_enabled', v);
  }

  // F4: adaptive quality
  Future<void> setAdaptiveQualityEnabled(bool v) async {
    adaptiveQualityManager.enabled = v;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('adaptive_quality_enabled', v);
  }

  Future<void> _maybeAdaptiveStepDown() async {
    if (!adaptiveQualityManager.enabled) return;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    final current = prefs.getString('setting_streaming_quality') ?? 'high';
    // Only re-sync the policy when the persisted quality actually changed;
    // resetting on every tick cleared the underrun counter before it could ever
    // reach the threshold, so a step-down never fired.
    if (current != adaptiveQualityManager.currentQuality) {
      adaptiveQualityManager.setQuality(current);
    }
    final next = await adaptiveQualityManager.reportUnderrun();
    if (next != null) await _applyAdaptiveQuality(next);
  }

  Future<void> _maybeAdaptiveStepUp() async {
    if (!adaptiveQualityManager.enabled) return;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    final current = prefs.getString('setting_streaming_quality') ?? 'high';
    // `current` is the user's ceiling. Snap down only if the manager believes a
    // higher quality is playing than the ceiling allows; never reset it upward.
    if (qualityRank(adaptiveQualityManager.currentQuality) > qualityRank(current)) {
      adaptiveQualityManager.setQuality(current);
    }
    final next = await adaptiveQualityManager.reportHealthy();
    if (next != null && qualityRank(next) <= qualityRank(current)) {
      await _applyAdaptiveQuality(next);
    }
  }

  Future<void> _applyAdaptiveQuality(String newQuality) async {
    // A quality step-down landing mid-crossfade/gapless load would clobber the
    // player that is already transitioning; skip this cycle and let the next
    // health tick retry.
    if (_crossfadeManager.isCrossfading) return;
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString('setting_streaming_quality', newQuality);
      final song = currentSong;
      if (song != null &&
          song.source == SongSource.youtube &&
          (song.remoteId?.isNotEmpty ?? false)) {
        _streamCache.removeWhere((k, _) => k.startsWith(song.remoteId!));
        _streamResolutionPipeline.invalidateCache(song.remoteId!);
        // Hot-swap mid-track: re-resolve at new quality, keep position.
        final pos = _activePlayer.position;
        final wasPlaying = _activePlayer.playing;
        final generation = ++_playGeneration;
        try {
          final resolved = await _resolveStreamUrl(song, forceRefresh: true);
          // Bail if the track/queue changed while we re-resolved.
          if (generation != _playGeneration ||
              currentSong?.id != song.id ||
              _crossfadeManager.isCrossfading) {
            return;
          }
          final tag = PulsrAudioHandler._songToMediaItem(song);
          final src = AudioSource.uri(Uri.parse(resolved.url), tag: tag);
          await _activePlayer.setAudioSource(src, initialPosition: pos);
          if (wasPlaying) unawaited(_activePlayer.play());
        } catch (_) {}
      }
    } catch (_) {}
  }

  // F6: gapless trim lookup for a song.
  GaplessTrim gaplessTrimFor(SongsTableData song) =>
      GaplessTrimHandler.trimFor(path: song.path, codec: song.codec);

  // F7: ducking control
  Future<void> setDuckingMode(String modeName) async {
    duckingController.setMode(DuckingController.parseMode(modeName));
    await duckingController.persist();
  }

  Future<void> setDuckingLevel(double level) async {
    duckingController.setLevel(level);
    await duckingController.persist();
  }

  // F8: multi-output routing
  Future<bool> setMultiOutputMode(MultiOutputMode mode) =>
      multiOutputRouter.setMode(mode);

  // F9: DSP snapshots
  Future<void> saveDspSnapshotForCurrent() async {
    final s = currentSong;
    if (s == null) return;
    dspSnapshotStore.save(
      DspSnapshotStore.albumKey(s.album, s.artist),
      DspSnapshot(
        presetName: _equalizerManager.currentPreset.name,
        gains: List<double>.from(_equalizerManager.currentPreset.gains),
        volumeBoost: _equalizerManager.volumeBoost,
        bassBoost: _equalizerManager.currentPreset.bassBoost,
        // Full effect chain (all JamesDSP / Phase-1 stages), not just the EQ
        // curve, so recall restores saturation/width/reverb/dynamics/etc.
        effects: _equalizerManager.captureEffectsState(),
        savedAt: DateTime.now(),
      ),
    );
    await dspSnapshotStore.persist();
  }

  Future<bool> recallDspSnapshotFor(SongsTableData song) async {
    final snap = dspSnapshotStore.recallFor(
        album: song.album, artist: song.artist, genre: song.genre);
    if (snap == null) return false;
    try {
      final effects = snap.effects;
      if (effects != null) {
        // Full-snapshot path: restore every captured DSP stage.
        await _equalizerManager.applyEffectsState(effects);
      } else {
        // Legacy v1 snapshot — only the graphic-EQ curve was captured.
        await _equalizerManager.applyPreset(
            EqPreset(name: snap.presetName, gains: snap.gains));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    dspSnapshotStore.enabled = v;
    await dspSnapshotStore.persist();
  }

  // F10: silence-skip sensitivity. Native ExoPlayer stage is boolean-only,
  // so sensitivity is persisted and exposed via thresholdDb/minSilenceDuration
  // for UI truthfulness and future native thresholds; enabling still toggles
  // the native boolean stage.
  Future<void> setSilenceSkipSensitivity(int v) async {
    silenceSkipController.setSensitivity(v);
    try {
      await _playerA.setSkipSilenceEnabled(silenceSkipController.enabled);
      await _playerB.setSkipSilenceEnabled(silenceSkipController.enabled);
    } catch (_) {}
    await silenceSkipController.persist();
  }

  // F11: bookmarks
  PlaybackBookmark? recallBookmarkFor(SongsTableData song) {
    final key = PlaybackBookmarkStore.keyFor(
        songId: song.id, remoteId: song.remoteId, path: song.path);
    return bookmarkStore.recall(key);
  }

  Future<void> clearBookmarkFor(SongsTableData song) async {
    final key = PlaybackBookmarkStore.keyFor(
        songId: song.id, remoteId: song.remoteId, path: song.path);
    bookmarkStore.remove(key);
    await bookmarkStore.persist();
  }

  Future<void> persistBookmarks() => bookmarkStore.persist();




















































































































  // Requires: provided by the composing class (same library).
  AudioPlayer get _activePlayer;

  // Requires: provided by the composing class (same library).
  SharedPreferences? get _cachedPrefs;

  // Requires: provided by the composing class (same library).
  CrossfadeManager get _crossfadeManager;

  // Requires: provided by the composing class (same library).
  EqualizerManager get _equalizerManager;

  // Requires: provided by the composing class (same library).
  int get _playGeneration;
  set _playGeneration(int value);

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerA;

  // Requires: provided by the composing class (same library).
  AudioPlayer get _playerB;

  // Requires: provided by the composing class (same library).
  Future<({String url, String? userAgent, String? cookies, String quality})> _resolveStreamUrl(SongsTableData song, {bool forceRefresh = false});

  // Requires: provided by the composing class (same library).
  dynamic get _streamCache;

  // Requires: provided by the composing class (same library).
  StreamResolutionPipeline get _streamResolutionPipeline;

  // Requires: provided by the composing class (same library).
  AbLoopManager get abLoopManager;

  // Requires: provided by the composing class (same library).
  AdaptiveQualityManager get adaptiveQualityManager;

  // Requires: provided by the composing class (same library).
  PlaybackBookmarkStore get bookmarkStore;

  // Requires: provided by the composing class (same library).
  SongsTableData? get currentSong;

  // Requires: provided by the composing class (same library).
  dynamic get dspSnapshotStore;

  // Requires: provided by the composing class (same library).
  DuckingController get duckingController;

  // Requires: provided by the composing class (same library).
  bool get hedgedResolutionEnabled;
  set hedgedResolutionEnabled(bool value);

  // Requires: provided by the composing class (same library).
  MultiOutputRouter get multiOutputRouter;

  // Requires: provided by the composing class (same library).
  SilenceSkipController get silenceSkipController;

  // Requires: provided by the composing class (same library).
  TrackDelayManager get trackDelayManager;
}
