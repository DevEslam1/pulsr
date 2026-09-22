part of 'player_cubit.dart';

mixin PlayerTransportControls on PulsrCubit<PlayerState> {
  // FIX-A06: Monotonic Stopwatch for seek throttling
  static final Stopwatch _seekStopwatch = Stopwatch()..start();

  Future<void> togglePlayPause() async {
    HapticFeedback.lightImpact();
    try {
      // Decide from what the user actually sees (the transport mirrors
      // state.isPlaying), not the engine's playWhenReady alone: while an online
      // stream is still being fetched the engine can report playing while the
      // track has not been fetched, and branching on that turned a pause tap
      // into a redundant play() that let the fetch cycle start playback anyway.
      final enginePlaying = _audioHandler.playbackState.value.playing;
      final shouldPause = state.isPlaying || enginePlaying;
      // Reconcile the visible state with the decision before acting, so the
      // button can never perform the inverse of the icon it is showing (A-7).
      if (state.isPlaying != shouldPause) {
        safeEmit(state.copyWith(isPlaying: shouldPause));
      }
      if (shouldPause) {
        _userPausedIntentionally = true;
        // Reflect the pause immediately, then abort the in-flight load cycle in
        // the handler so a late resolve cannot auto-start playback.
        safeEmit(state.copyWith(isPlaying: false));
        await _audioHandler.pause();
      } else {
        if (state.currentSong == null && state.queue.isEmpty) {
          return;
        }
        _userPausedIntentionally = false;
        await _audioHandler.play();
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle play/pause failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Playback action failed'));
      }
    }
  }

  Future<void> seek(Duration position) {
    if (isClosed) return Future.value();
    // Clamp to a sane range; negative seeks crash some backends and
    // beyond-duration seeks leave UI/engine diverged.
    var target = position.isNegative ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    // Optimistic UI: don't wait up to 100ms / round-trip for the position
    // stream to reflect a discrete user intent.
    safeEmit(state.copyWith(position: target));
    // Throttle tap-spam: at most one native seek per 100ms. Drag-end seeks
    // are discrete user intents — the 100ms window is short enough that the
    // final position still lands promptly while floods are coalesced.
    // FIX-A06: Use monotonic clock to prevent time skew from breaking seek throttling
    final nowMs = _seekStopwatch.elapsedMilliseconds;
    if (nowMs - _lastSeekMs < 100) {
      // Coalesce: schedule the latest position at the window edge.
      _pendingSeek = target;
      _seekThrottleTimer?.cancel();
      _seekThrottleTimer = autoTimer(Timer(
        Duration(milliseconds: 100 - (nowMs - _lastSeekMs)),
        () {
          if (isClosed) {
            _pendingSeek = null;
            return;
          }
          final pending = _pendingSeek;
          _pendingSeek = null;
          if (pending != null) {
            _lastSeekMs = _seekStopwatch.elapsedMilliseconds;
            _lastSkippedSegmentEnd = null;
            _lastSponsorSkipTime = null;
            _audioHandler.seek(pending).catchError((Object e, StackTrace st) {
              ErrorLogger.log('Coalesced seek failed',
                  error: e, stackTrace: st, category: 'PlayerCubit');
              if (!isClosed) {
                safeEmit(state.copyWith(
                    errorMessage: 'Seek failed, position restored'));
              }
            });
          }
        },
      ));
      return Future.value();
    }
    _lastSeekMs = nowMs;
    _lastSkippedSegmentEnd = null;
    _lastSponsorSkipTime = null;
    // Discrete intent: bypass the handler's scrub debounce (single layer).
    // Callers discard the returned future, so a rethrow here would become an
    // unhandled async error with a silent rollback and no user feedback. Route
    // it through the same failure handling as the coalesced path (A-6).
    return _audioHandler.seekDirect(target).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Discrete seek failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(
            state.copyWith(errorMessage: 'Seek failed, position restored'));
      }
    });
  }

  Future<void> next() async {
    try {
      await _audioHandler.skipToNext();
    } catch (e, st) {
      ErrorLogger.log('Skip to next failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> previous() async {
    try {
      await _audioHandler.skipToPrevious();
    } catch (e, st) {
      ErrorLogger.log('Skip to previous failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.skipToQueueItem(index);
    } catch (e, st) {
      ErrorLogger.log('Skip to queue item failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> toggleShuffle() async {
    final prev = state.isShuffle;
    final next = !prev;
    safeEmit(state.copyWith(isShuffle: next, errorMessage: null));
    try {
      await _audioHandler.setShuffleMode(
          next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
    } catch (e, st) {
      ErrorLogger.log('Toggle shuffle failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(isShuffle: prev, errorMessage: 'Shuffle failed'));
      }
    }
  }

  Future<void> toggleRepeat() async {
    final prev = state.repeatMode;
    final next = switch (prev) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    final nextMode = switch (next) {
      PlayerRepeatMode.off => AudioServiceRepeatMode.none,
      PlayerRepeatMode.all => AudioServiceRepeatMode.all,
      PlayerRepeatMode.one => AudioServiceRepeatMode.one,
    };
    safeEmit(state.copyWith(repeatMode: next, errorMessage: null));
    try {
      await _audioHandler.setRepeatMode(nextMode);
    } catch (e, st) {
      ErrorLogger.log('Toggle repeat failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(repeatMode: prev, errorMessage: 'Repeat failed'));
      }
    }
  }

  Future<void> toggleFavorite(int songId) async {
    final result = await _toggleFavoriteUseCase(songId);
    result.fold(
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (isFav) {
        // Propagate to queue so SongTile favorite stars update immediately
        final updatedQueue = state.queue
            .map((s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s)
            .toList();
        // Also update lookup cache
        final cached = _slotLookupCache[songId];
        if (cached != null) {
          _slotLookupCache[songId] = cached.copyWith(isFavorite: isFav);
        }
        // FIX-M05: Debounced persistence for updated queue slots
        _debouncedPersistQueueSlots();
        if (state.currentSong != null && state.currentSong!.id == songId) {
          safeEmit(
            state.copyWith(
              currentSong: state.currentSong!.copyWith(isFavorite: isFav),
              queue: updatedQueue,
              errorMessage: null,
            ),
          );
          _updateWidgetThrottled(force: true);
        } else if (state.queue.any((s) => s.id == songId)) {
          safeEmit(state.copyWith(queue: updatedQueue, errorMessage: null));
        }
      },
    );
  }

  // Requires: provided by the composing class (same library).
  PulsrAudioHandler get _audioHandler;

  // Requires: provided by the composing class (same library).
  int get _lastSeekMs;
  set _lastSeekMs(int value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  Duration? get _lastSkippedSegmentEnd;
  set _lastSkippedSegmentEnd(Duration? value);

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  DateTime? get _lastSponsorSkipTime;
  set _lastSponsorSkipTime(DateTime? value);

  // Requires: provided by the composing class (same library).
  Duration? get _pendingSeek;
  set _pendingSeek(Duration? value);

  // Requires: provided by the composing class (same library).
  Map<int, SongsTableData> get _slotLookupCache;

  // Requires: provided by the composing class (same library).
  Timer? get _seekThrottleTimer;
  set _seekThrottleTimer(Timer? value);

  // Requires: provided by the composing class (same library).
  ToggleFavoriteUseCase get _toggleFavoriteUseCase;

  // Requires: provided by the composing class (same library).
  void _updateWidgetThrottled({bool force = false});

  // Requires: provided by the composing class (same library).
  // ignore: unused_element
  bool get _userPausedIntentionally;
  set _userPausedIntentionally(bool value);

  // Requires: provided by the composing class (same library).
  void _debouncedPersistQueueSlots();
}
