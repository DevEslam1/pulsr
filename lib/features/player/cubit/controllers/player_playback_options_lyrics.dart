// lib/features/player/cubit/controllers/player_playback_options_lyrics.dart
part of 'player_playback_options_controller.dart';

extension PlayerPlaybackOptionsLyricsExtension on PlayerPlaybackOptionsController {
  // ──────────────────────────────────────────────
  // AB Loop
  // ──────────────────────────────────────────────
  void setAbPointA() {
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        abPointA: s.position,
        abLoopEnabled: s.abPointB != null && s.position < s.abPointB!,
      ),
    ));
  }

  void setAbPointB() {
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        abPointB: s.position,
        abLoopEnabled: s.abPointA != null && s.abPointA! < s.position,
      ),
    ));
  }

  void clearAbLoop() {
    final s = _getState();
    _emit(s.copyWith(
      playback: s.playback.copyWith(
        abLoopEnabled: false,
        abPointA: null,
        abPointB: null,
      ),
    ));
  }

  void toggleAbLoop() {
    final s = _getState();
    _emit(s.copyWith(playback: s.playback.copyWith(abLoopEnabled: !s.abLoopEnabled)));
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
      _audioHandler.bookmarkStore.save(key, posMs,
          durationMs: s.duration.inMilliseconds);
      await _audioHandler.persistBookmarks();
      _emit(s.copyWith(
          playback: s.playback.copyWith(bookmarkPosition: Duration(milliseconds: posMs))));
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
      _emit(s.copyWith(playback: s.playback.copyWith(bookmarkPosition: null)));
    } catch (_) {}
  }

  Future<bool> updateLyrics(List<LyricsLine> lines) async {
    final s = _getState();
    final source =
        lines.isNotEmpty ? LyricsSource.externalLrc : LyricsSource.none;
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        lyrics: lines,
        lyricsSource: source,
        isLoadingLyrics: false,
      ),
    ));

    final song = s.currentSong;
    if (song == null) return false;

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
      final sidecar =
          File('${dir.path}${Platform.pathSeparator}$stem.lrc');
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

    LrcParser.invalidateSong(songId: song.id, path: song.path);
    _emit(s.copyWith(
      lyricsSlice: s.lyricsSlice.copyWith(
        isLoadingLyrics: true,
        lyrics: const [],
        lyricsSource: LyricsSource.none,
      ),
    ));

    if (_onLoadLyrics != null) {
      await _onLoadLyrics!(song, isOfflineOnly: false);
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
}
