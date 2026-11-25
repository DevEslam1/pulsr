part of 'audio_handler.dart';

/// Native DSD playback owned by the handler instead of ExoPlayer.
///
/// just_audio cannot render DSD, and a silent WAV source would fake a timeline
/// without carrying the audio. This mixin runs a [NativeDsdSession] as the
/// active backend: transport calls delegate to it, just_audio state is
/// suppressed, the media session is driven from the DSD byte clock, and any
/// stream failure reloads the same track through DoP/PCM.
mixin PulsrAudioNativeDsd on BaseAudioHandler {
  NativeDsdSession? _nativeDsdSession;
  bool _nativeDsdActive = false;
  int _nativeDsdPrepareGeneration = 0;
  bool _nativeDsdPlaying = false;
  final Set<int> _nativeDsdFallbackAttempted = <int>{};
  StreamSubscription<PlaybackState>? _nativeDsdStateSub;
  StreamSubscription<Duration>? _nativeDsdPosSub;
  StreamSubscription<void>? _nativeDsdCompleteSub;
  DateTime _lastNativeDsdPositionEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _nativeDsdFixedVolumeNoticeShown = false;

  bool get nativeDsdActive => _nativeDsdActive;
  NativeDsdSession? get nativeDsdSession => _nativeDsdSession;

  Duration get compensatedPosition {
    if (_nativeDsdActive) {
      return _nativeDsdSession?.position ?? Duration.zero;
    }
    return _dspPipeline.getCompensatedPosition(_activePlayer.position);
  }

  /// Persister construction lives here so the native position source and the
  /// "not idle" override stay next to the session instead of growing the
  /// already-ratcheted handler core.
  PlaybackPositionPersister createPlaybackPositionPersister() {
    return PlaybackPositionPersister(
      repository: _repository,
      readSnapshot: () {
        if (_songs.isEmpty ||
            _currentIndex < 0 ||
            _currentIndex >= _songs.length) {
          return null;
        }
        final currentSong = _songs[_currentIndex];
        final isIdle = _nativeDsdActive
            ? false
            : _activePlayer.processingState == ProcessingState.idle;
        final posMs = _nativeDsdActive
            ? (_nativeDsdSession?.position.inMilliseconds ?? 0)
            : ((_pendingLazyPosition != null && isIdle)
                ? _pendingLazyPosition!.inMilliseconds
                : _activePlayer.position.inMilliseconds);
        return PlaybackPositionSnapshot(
          songId: currentSong.id,
          queueIndex: _currentIndex,
          positionMs: posMs,
          queueIds: _songs.map((s) => s.id).toList(),
          isIdle: isIdle,
          queueDirty: _queueDirty,
          savedQueueIndex: _savedQueueIndex,
        );
      },
      readCurrentPositionMs: () => _nativeDsdActive
          ? (_nativeDsdSession?.position.inMilliseconds ?? 0)
          : _activePlayer.position.inMilliseconds,
      isDisposed: () => _disposed,
      clearDirty: _playbackStateCoordinator.clearDirty,
      markDirty: _playbackStateCoordinator.markPositionDirty,
      onQueueSaved: (index) {
        _queueDirty = false;
        _savedQueueIndex = index;
      },
    );
  }

  int get _currentIndex;
  set _currentIndex(int value);
  set _pendingPlaybackStart(bool value);
  set _gaplessLoaded(bool value);
  set _gaplessTargetIndex(int? value);
  int get _playGeneration;
  bool get _disposed;
  SongsTableData? get currentSong;
  List<SongsTableData> get _songs;
  set _songs(List<SongsTableData> value);
  AudioPlayer get _activePlayer;
  OptimizedDspPipeline get _dspPipeline;
  IMusicRepository get _repository;
  Duration? get _pendingLazyPosition;
  bool get _queueDirty;
  set _queueDirty(bool value);
  int get _savedQueueIndex;
  set _savedQueueIndex(int value);
  PlaybackStateCoordinator get _playbackStateCoordinator;
  List<int> get _shuffleHistory;
  void _publishQueueWithArtwork();
  Future<void> _loadSongPaused(int index, {Duration? initialPosition});
  SharedPreferences? get _cachedPrefs;
  StreamController<SongsTableData> get _onTrackChangedSubject;
  StreamController<String> get _errorSubject;
  bool _isBitPerfectBypassEnabled();
  bool _isUsbHardwareVolumeEnabled();
  Future<void> playSongAt(int index, {Duration? initialPosition});
  void _recordResolvedDsdTransport(
    int songId, {
    required bool isDop,
    required bool isNativeDsd,
  });
  void _notifyTrackChanged(SongsTableData song);
  Future<void> _advanceAtTrackBoundary();
  void _emitPosition(Duration position);
  void _saveCurrentPosition();
  Future<void> saveCurrentPositionImmediate();
  void notifySleepTrackCompleted();
  int? _getNextIndex({bool peek = false});
  SleepTimerManager get _sleepTimerManager;

  /// A DSD track is eligible for the native session only when the user chose
  /// native output, the bit-perfect path is active, the file is local, and a
  /// previous native attempt for this song did not already fail.
  bool isNativeDsdCandidate(SongsTableData song) {
    if (!kNativeDsdProducerAvailable) return false;
    if (!PlatformCapabilities.isAndroid) return false;
    if (_nativeDsdFallbackAttempted.contains(song.id)) return false;
    final path = song.path.split('?').first;
    if (path.isEmpty ||
        path.startsWith('http') ||
        path.startsWith('content:') ||
        path.startsWith('ytmusic://')) {
      return false;
    }
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    if (ext != 'dsf' && ext != 'dff') return false;
    if (_cachedPrefs?.getString(PrefsKeys.dsdOutputMode) != 'native') {
      return false;
    }
    return _isBitPerfectBypassEnabled();
  }

  /// Starts the native session for [song].
  ///
  /// Returns true when this call owns playback now. A false result means the
  /// session could not open and the caller must fall through to DoP/PCM.
  Future<bool> tryStartNativeDsd(
    SongsTableData song, {
    Duration? initialPosition,
    required bool autoPlay,
    required int generation,
  }) async {
    final prepareGen = ++_nativeDsdPrepareGeneration;
    NativeDsdSession? session;
    try {
      await stopNativeDsd(clearStatus: false);
      if (prepareGen != _nativeDsdPrepareGeneration ||
          generation != _playGeneration) {
        return true;
      }
      unawaited(() async {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (e, st) {
          ErrorLogger.log('Native DSD audio-session activation failed',
              error: e, stackTrace: st, category: 'AudioHandler');
        }
      }());
      session = NativeDsdSession();
      final hardwareVolume = _isUsbHardwareVolumeEnabled();
      session.setHardwareVolumeEnabled(hardwareVolume);
      if (!hardwareVolume && !_nativeDsdFixedVolumeNoticeShown) {
        _nativeDsdFixedVolumeNoticeShown = true;
        if (!_errorSubject.isClosed) {
          _errorSubject.add(
            'Native DSD cannot be scaled in software. Enable USB hardware '
            'volume to change the level on the DAC.',
          );
        }
      }
      session.onNativeActive = () {
        _recordResolvedDsdTransport(song.id, isDop: false, isNativeDsd: true);
        DsdDecoderHelper.dsdNativeActive = true;
        DsdDecoderHelper.dsdDopActive = false;
        if (!_onTrackChangedSubject.isClosed) {
          _onTrackChangedSubject.add(song);
        }
      };
      session.onFallbackRequired = (position) {
        unawaited(_handleNativeDsdFallback(song, position));
      };

      // Suppress just_audio state before the first await so an idle player
      // cannot overwrite the loading state during file read / USB claim.
      _recordResolvedDsdTransport(song.id, isDop: false, isNativeDsd: false);
      _nativeDsdSession = session;
      _nativeDsdActive = true;
      _gaplessLoaded = false;
      _gaplessTargetIndex = null;

      await session.preparePath(
        song.path,
        title: song.title,
        initialPosition: initialPosition,
        autoPlay: autoPlay,
      );

      if (prepareGen != _nativeDsdPrepareGeneration ||
          generation != _playGeneration ||
          _nativeDsdSession != session) {
        if (identical(_nativeDsdSession, session)) {
          await stopNativeDsd(clearStatus: true);
        } else {
          await session.dispose();
        }
        return true;
      }

      _nativeDsdPlaying = autoPlay;
      _pendingPlaybackStart = false;
      final current = mediaItem.value;
      if (current != null) {
        mediaItem.add(current.copyWith(duration: session.duration));
      }
      _subscribeNativeDsdSession(session, song);
      _notifyTrackChanged(song);
      _emitNativeDsdState(
        AudioProcessingState.ready,
        playing: autoPlay,
        position: session.position,
        duration: session.duration,
      );
      _saveCurrentPosition();
      return true;
    } on DsdFallbackRequiredException catch (e) {
      if (prepareGen != _nativeDsdPrepareGeneration ||
          generation != _playGeneration) {
        if (!identical(_nativeDsdSession, session)) {
          await session?.dispose();
        }
        return true;
      }
      ErrorLogger.log(
          'Native DSD unavailable for "${song.title}": ${e.message}; '
          'falling back to DoP/PCM',
          category: 'AudioHandler');
      _nativeDsdFallbackAttempted.add(song.id);
      if (identical(_nativeDsdSession, session)) {
        await stopNativeDsd(clearStatus: true);
      } else {
        await session?.dispose();
      }
      return false;
    } catch (e, st) {
      if (prepareGen != _nativeDsdPrepareGeneration ||
          generation != _playGeneration) {
        if (!identical(_nativeDsdSession, session)) {
          await session?.dispose();
        }
        return true;
      }
      ErrorLogger.log('Native DSD session failed for "${song.title}"',
          error: e, stackTrace: st, category: 'AudioHandler');
      _nativeDsdFallbackAttempted.add(song.id);
      if (identical(_nativeDsdSession, session)) {
        await stopNativeDsd(clearStatus: true);
      } else {
        await session?.dispose();
      }
      return false;
    }
  }

  Future<void> stopNativeDsd({bool clearStatus = true}) async {
    final session = _nativeDsdSession;
    _nativeDsdActive = false;
    _nativeDsdPlaying = false;
    _nativeDsdSession = null;
    await _nativeDsdStateSub?.cancel();
    await _nativeDsdPosSub?.cancel();
    await _nativeDsdCompleteSub?.cancel();
    _nativeDsdStateSub = null;
    _nativeDsdPosSub = null;
    _nativeDsdCompleteSub = null;
    if (session != null) {
      try {
        await session.dispose();
      } catch (e, st) {
        ErrorLogger.log('Failed to dispose native DSD session',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    }
    if (clearStatus) {
      DsdDecoderHelper.dsdNativeActive = false;
    }
  }

  void _subscribeNativeDsdSession(
      NativeDsdSession session, SongsTableData song) {
    _nativeDsdStateSub = session.stateStream.listen((state) {
      if (!_nativeDsdActive || _nativeDsdSession != session) return;
      if (state.processingState != AudioProcessingState.completed) {
        _nativeDsdPlaying = state.playing;
      }
      _emitNativeDsdState(
        state.processingState,
        playing: state.playing,
        position: state.updatePosition,
        duration: session.duration,
      );
    });
    _nativeDsdPosSub = session.positionStream.listen((position) {
      if (!_nativeDsdActive || _nativeDsdSession != session) return;
      final now = DateTime.now();
      if (now.difference(_lastNativeDsdPositionEmit) <
          const Duration(milliseconds: 200)) {
        return;
      }
      _lastNativeDsdPositionEmit = now;
      _emitPosition(position);
      _updateNativeDsdPlaybackPosition(position);
      if (_nativeDsdPlaying) _saveCurrentPosition();
    });
    _nativeDsdCompleteSub = session.completedStream.listen((_) {
      if (!_nativeDsdActive || _nativeDsdSession != session) return;
      notifySleepTrackCompleted();
      final nextIdx = _getNextIndex(peek: true);
      if (nextIdx == null && _activePlayer.loopMode == LoopMode.off) {
        unawaited(_sleepTimerManager.onQueueCompleted());
      }
      unawaited(_advanceAtTrackBoundary().catchError((Object e, StackTrace st) {
        ErrorLogger.log('Native DSD auto-advance failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      }));
    });
  }

  void _emitNativeDsdState(
    AudioProcessingState processingState, {
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    if (_disposed) return;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
        queueIndex: _currentIndex,
      ),
    );
  }

  void _updateNativeDsdPlaybackPosition(Duration position) {
    if (_disposed) return;
    final state = playbackState.value;
    if (state.updatePosition == position) return;
    playbackState.add(state.copyWith(
      updatePosition: position,
      bufferedPosition: position,
    ));
  }

  Future<void> _handleNativeDsdFallback(
      SongsTableData song, Duration position) async {
    if (_nativeDsdFallbackAttempted.contains(song.id)) return;
    _nativeDsdFallbackAttempted.add(song.id);
    await stopNativeDsd(clearStatus: true);
    if (currentSong?.id != song.id) return;
    await playSongAt(_currentIndex, initialPosition: position);
  }

  bool playNativeDsdIfActive() {
    if (!_nativeDsdActive) return false;
    final session = _nativeDsdSession;
    if (session == null) return false;
    _pendingPlaybackStart = false;
    _nativeDsdPlaying = true;
    unawaited(session.play().catchError((e, st) {
      ErrorLogger.log('Native DSD play failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }));
    return true;
  }

  bool pauseNativeDsdIfActive() {
    if (!_nativeDsdActive) return false;
    final session = _nativeDsdSession;
    if (session == null) return false;
    _nativeDsdPlaying = false;
    unawaited(session.pause().catchError((e, st) {
      ErrorLogger.log('Native DSD pause failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }));
    _saveCurrentPosition();
    unawaited(saveCurrentPositionImmediate());
    return true;
  }

  bool seekNativeDsdIfActive(Duration position) {
    if (!_nativeDsdActive) return false;
    final session = _nativeDsdSession;
    if (session == null) return false;
    unawaited(session.seek(position).catchError((e, st) {
      ErrorLogger.log('Native DSD seek failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }));
    _emitPosition(position);
    _saveCurrentPosition();
    return true;
  }

  /// Stops the native session before an existing skip path runs, preserving
  /// whether the user expected the successor to play.
  Future<void> prepareNativeDsdSkip() async {
    if (!_nativeDsdActive) return;
    final wasPlaying = _nativeDsdPlaying;
    await stopNativeDsd(clearStatus: true);
    _pendingPlaybackStart = wasPlaying;
  }

  void clearNativeDsdFallbackGuard() {
    _nativeDsdFallbackAttempted.clear();
  }

  Future<bool> startNativeDsdPlayback(
    SongsTableData song,
    Duration? initialPosition,
    int generation,
  ) =>
      tryStartNativeDsd(
        song,
        initialPosition: initialPosition,
        autoPlay: true,
        generation: generation,
      );

  Future<bool> startNativeDsdPaused(
    SongsTableData song,
    Duration? initialPosition,
    int generation,
  ) =>
      tryStartNativeDsd(
        song,
        initialPosition: initialPosition,
        autoPlay: false,
        generation: generation,
      );

  /// Routes a queue load whose initial track is native DSD. The gapless
  /// concat and the dual-player handover cannot carry raw DSD, so the queue
  /// state is adopted here and the session starts (or loads paused).
  Future<bool> startNativeDsdQueue(
    List<SongsTableData> songs,
    int index, {
    Duration? initialPosition,
    required bool autoPlay,
  }) async {
    _songs = List.from(songs);
    _currentIndex = index;
    _queueDirty = true;
    _shuffleHistory.clear();
    _publishQueueWithArtwork();
    if (autoPlay) {
      await playSongAt(index, initialPosition: initialPosition);
    } else {
      await _loadSongPaused(index, initialPosition: initialPosition);
    }
    return true;
  }
}
