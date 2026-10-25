// lib/features/player/cubit/controllers/player_playback_options_lyrics.dart
part of 'player_playback_options_controller.dart';

extension PlayerPlaybackOptionsLyricsExtension
    on PlayerPlaybackOptionsController {
  // ──────────────────────────────────────────────
  // AB Loop
  // ──────────────────────────────────────────────
  void setAbPointA() {
    final s = _getState();
    _audioHandler.setAbPointA(s.position);
    _syncAbLoopFromHandler();
  }

  void setAbPointB() {
    final s = _getState();
    _audioHandler.setAbPointB(s.position);
    _syncAbLoopFromHandler();
  }

  void clearAbLoop() {
    _audioHandler.clearAbLoop();
    _syncAbLoopFromHandler();
  }

  void setAbLoopRange(Duration start, Duration end) {
    final songId = _getState().currentSong?.id;
    _audioHandler.abLoopManager.setA(start, songId: songId);
    _audioHandler.abLoopManager.setB(end, songId: songId);
    _syncAbLoopFromHandler();
  }

  void toggleAbLoop() {
    final s = _getState();
    if (!s.abLoopEnabled && (s.abPointA == null || s.abPointB == null)) {
      return;
    }
    _audioHandler.toggleAbLoop();
    _syncAbLoopFromHandler();
  }

  void seekToBookmark() {
    final pos = _getState().bookmarkPosition;
    if (pos != null) _audioHandler.seek(pos);
  }

  void dismissBookmark() {
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(bookmarkPosition: null)));
  }

  Future<bool> saveBookmark() async {
    final s = _getState();
    final song = s.currentSong;
    if (song == null) return false;
    final posMs = s.position.inMilliseconds;
    if (posMs < 0) return false;
    try {
      final key = PlaybackBookmarkStore.keyFor(
          songId: song.id, remoteId: song.remoteId, path: song.path);
      _audioHandler.bookmarkStore
          .save(key, posMs, durationMs: s.duration.inMilliseconds);
      await _audioHandler.persistBookmarks();
      if (_isClosed()) return false;
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback
              .copyWith(bookmarkPosition: Duration(milliseconds: posMs))));
      return true;
    } catch (_) {
      return false;
    }
  }

  PlaybackBookmark? storedBookmarkFor(SongsTableData song) {
    try {
      return _audioHandler.recallBookmarkFor(song);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearBookmark() async {
    final s = _getState();
    final song = s.currentSong;
    if (song == null) return;
    try {
      await _audioHandler.clearBookmarkFor(song);
      if (_isClosed()) return;
      final cur = _getState();
      _emit(cur.copyWith(
          playback: cur.playback.copyWith(bookmarkPosition: null)));
    } catch (_) {}
  }

  Future<bool> updateLyrics(List<LyricsLine> lines,
      {int? expectedSongId}) async {
    if (lines.isEmpty) {
      // Do not overwrite an existing sidecar .lrc file with an empty list
      return false;
    }
    final s = _getState();
    const source = LyricsSource.externalLrc;
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        lyrics: lines,
        lyricsSource: source,
        isLoadingLyrics: false,
      ),
    ));

    final song = s.currentSong;
    if (song == null) return false;
    // The sheet may stay open while playback advances; never write the previous
    // track's edited lyrics into the new track's sidecar.
    if (expectedSongId != null && song.id != expectedSongId) return false;

    LrcParser.invalidateSong(songId: song.id, path: song.path);

    final path = song.path;
    final isLocal = song.source == SongSource.local &&
        path.isNotEmpty &&
        !path.startsWith('http') &&
        !path.startsWith('ytmusic://');
    if (!isLocal) {
      LrcParser.cacheLyricsResult(
        LyricsResult(lines: lines, source: source),
        songId: song.id,
        path: path,
      );
      return false;
    }

    try {
      final file = File(path);
      final dir = file.parent;
      final baseName = path.split(RegExp(r'[\\/]')).last;
      final dot = baseName.lastIndexOf('.');
      final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
      final sidecar = File('${dir.path}${Platform.pathSeparator}$stem.lrc');
      await sidecar.writeAsString(LrcParser.formatToLrc(lines), flush: true);
      LrcParser.cacheLyricsResult(
        LyricsResult(lines: lines, source: source),
        songId: song.id,
        path: path,
      );
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to persist sidecar .lrc for $path',
          error: e, stackTrace: st, category: 'Lyrics');
      return false;
    }
  }

  Future<void> refreshLyrics() async {
    final s = _getState();
    final song = s.currentSong;
    if (song == null) return;
    final songId = song.id;

    LrcParser.invalidateSong(songId: song.id, path: song.path);
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        isLoadingLyrics: true,
        lyrics: const [],
        lyricsSource: LyricsSource.none,
      ),
    ));

    if (_onLoadLyrics != null) {
      try {
        await _onLoadLyrics!(song, isOfflineOnly: false);
      } catch (e, st) {
        ErrorLogger.log('Refresh lyrics failed',
            error: e, stackTrace: st, category: 'Lyrics');
      } finally {
        if (!_isClosed()) {
          final cur = _getState();
          // Only clear the spinner if the refreshed track is still current: a
          // track switch during the fetch already started the new track's load.
          if (cur.isLoadingLyrics && cur.currentSong?.id == songId) {
            _emit(cur.copyWith(
              lyricsSlice: cur.lyricsSlice.copyWith(isLoadingLyrics: false),
            ));
          }
        }
      }
    } else {
      if (!_isClosed()) {
        final cur = _getState();
        _emit(cur.copyWith(
          lyricsSlice: cur.lyricsSlice.copyWith(isLoadingLyrics: false),
        ));
      }
    }
  }

  Future<EarbudCapabilities> detectEarbudCapabilities() async {
    final service = _earbudOptimizationService;
    if (service == null) {
      return const EarbudCapabilities(
        deviceName: 'Default output',
        codec: EarbudCodec.unknown,
        isBluetooth: false,
        isLeAudio: false,
        isUsbDac: false,
        sampleRateHz: 44100,
        bitDepth: 16,
        latencyMs: 0,
      );
    }
    var info = _hiResAudioService?.currentOutputInfo;
    try {
      info ??= await _hiResAudioService?.getAudioOutputInfo();
    } catch (_) {
      info = null;
    }
    return service.detect(info);
  }

  // ──────────────────────────────────────────────
  // Overlays
  // ──────────────────────────────────────────────
  void toggleLyrics() => toggleLyricsVisibility();

  void toggleLyricsVisibility() {
    HapticFeedback.lightImpact();
    final s = _getState();
    _emit(s.copyWith(
        lyricsSlice: s.lyricsSlice.copyWith(
            isLyricsVisible: !s.isLyricsVisible, isQueueVisible: false)));
  }

  void toggleQueue() => toggleQueueVisibility();

  void toggleQueueVisibility() {
    HapticFeedback.lightImpact();
    final s = _getState();
    _emit(s.copyWith(
        lyricsSlice: s.lyricsSlice.copyWith(
            isQueueVisible: !s.isQueueVisible, isLyricsVisible: false)));
  }

  void resetOverlayViews() {
    final s = _getState();
    if (s.isLyricsVisible || s.isQueueVisible) {
      _emit(s.copyWith(
          lyricsSlice: s.lyricsSlice
              .copyWith(isLyricsVisible: false, isQueueVisible: false)));
    }
  }

  void setExpanded(bool expanded) => _emit(_getState()
      .copyWith(playback: _getState().playback.copyWith(isExpanded: expanded)));
  void setSilenceSkipSensitivity(int sensitivity) => _emit(_getState().copyWith(
      playback:
          _getState().playback.copyWith(silenceSkipSensitivity: sensitivity)));
}
