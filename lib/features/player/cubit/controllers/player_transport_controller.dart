// lib/features/player/cubit/controllers/player_transport_controller.dart
// FIX-A1: Focused PlayerTransportController extracted from PlayerCubit
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:mutex/mutex.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/toggle_favorite_usecase.dart';
import '../player_constants.dart';
import '../player_state.dart';

part 'player_transport_favorites.dart';

/// Owns audio transport controls: play, pause, seek, track skipping, shuffle, repeat, and favorite toggle.
class PlayerTransportController {
  final PulsrAudioHandler _audioHandler;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final void Function(bool intentional)? _onUserPausedIntentionally;
  final ToggleFavoriteUseCase? _toggleFavoriteUseCase;
  final Map<int, SongsTableData>? _slotLookupCache;
  final void Function()? _debouncedPersistQueueSlots;
  final void Function({bool force})? _updateWidgetThrottled;

  final Mutex _transportMutex = Mutex();

  // Monotonic stopwatch for seek throttling. H-05: instance-scoped so separate
  // controller instances (e.g. test + prod) never share throttle state.
  final Stopwatch _seekStopwatch = Stopwatch()..start();
  int _lastSeekMs = 0;
  int? _lastSeekRequestMs;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeek;

  /// True when a seek was requested within the last ~1.5s. Used to suppress
  /// automatic seeks (e.g. SponsorBlock) while the user is scrubbing.
  bool get isUserSeeking {
    final last = _lastSeekRequestMs;
    if (last == null) return false;
    return _seekStopwatch.elapsedMilliseconds - last < 1500;
  }

  /// The engine's own play flag. Used to reconcile the UI when a transport
  /// call throws, so a failed pause/play cannot leave state diverged from audio.
  bool get _enginePlaying {
    try {
      return _audioHandler.playbackState.value.playing;
    } catch (_) {
      return false;
    }
  }

  PlayerTransportController({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    void Function(bool intentional)? onUserPausedIntentionally,
    ToggleFavoriteUseCase? toggleFavoriteUseCase,
    Map<int, SongsTableData>? slotLookupCache,
    void Function()? debouncedPersistQueueSlots,
    void Function({bool force})? updateWidgetThrottled,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _onUserPausedIntentionally = onUserPausedIntentionally,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _slotLookupCache = slotLookupCache,
        _debouncedPersistQueueSlots = debouncedPersistQueueSlots,
        _updateWidgetThrottled = updateWidgetThrottled;

  Future<void> play() async {
    await _transportMutex.protect(() async {
      try {
        _onUserPausedIntentionally?.call(false);
        await _audioHandler.play();
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback:
                  s.playback.copyWith(isPlaying: true, errorMessage: null)));
        }
      } catch (e, st) {
        ErrorLogger.log('Play failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(
                  isPlaying: _enginePlaying,
                  errorMessage: 'Failed to start playback')));
        }
      }
    });
  }

  Future<void> pause() async {
    await _transportMutex.protect(() async {
      try {
        _onUserPausedIntentionally?.call(true);
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(isPlaying: false)));
        await _audioHandler.pause();
      } catch (e, st) {
        ErrorLogger.log('Pause failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          // Reconcile with the engine: if pause() threw, audio may still be
          // running, so never leave the UI stuck showing the optimistic pause.
          _emit(s.copyWith(
              playback: s.playback.copyWith(
                  isPlaying: _enginePlaying,
                  errorMessage: 'Failed to pause playback')));
        }
      }
    });
  }

  Future<void> togglePlayPause() async {
    HapticFeedback.lightImpact();
    await _transportMutex.protect(() async {
      try {
        final state = _getState();
        final enginePlaying = _audioHandler.playbackState.value.playing;
        final shouldPause = state.isPlaying || enginePlaying;

        if (shouldPause) {
          _onUserPausedIntentionally?.call(true);
          _emit(state.copyWith(
              playback: state.playback.copyWith(isPlaying: false)));
          await _audioHandler.pause();
        } else {
          if (state.currentSong == null && state.queue.isEmpty) return;
          _onUserPausedIntentionally?.call(false);
          // Optimistically reflect play; the engine observer confirms it.
          if (!state.isPlaying) {
            _emit(state.copyWith(
                playback: state.playback.copyWith(isPlaying: true)));
          }
          await _audioHandler.play();
        }
      } catch (e, st) {
        ErrorLogger.log('Toggle play/pause failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(
                  isPlaying: _enginePlaying,
                  errorMessage: 'Playback action failed')));
        }
      }
    });
  }

  Future<void> seek(Duration position) {
    if (_isClosed()) return Future.value();
    return _transportMutex.protect(() async {
      if (_isClosed()) return;
      final state = _getState();
      var target = position.isNegative ? Duration.zero : position;
      if (state.duration > Duration.zero && target > state.duration) {
        target = state.duration;
      }

      _emit(
          state.copyWith(playback: state.playback.copyWith(position: target)));

      final nowMs = _seekStopwatch.elapsedMilliseconds;
      _lastSeekRequestMs = nowMs;
      if (nowMs - _lastSeekMs < PlayerConstants.seekThrottleMs) {
        _pendingSeek = target;
        _seekThrottleTimer?.cancel();
        _seekThrottleTimer = Timer(
          Duration(
              milliseconds:
                  (PlayerConstants.seekThrottleMs - (nowMs - _lastSeekMs))
                      .clamp(16, PlayerConstants.seekThrottleMs)),
          () {
            if (_isClosed()) {
              _pendingSeek = null;
              return;
            }
            final pending = _pendingSeek;
            _pendingSeek = null;
            if (pending != null && !_isClosed()) {
              _lastSeekMs = _seekStopwatch.elapsedMilliseconds;
              _audioHandler.seek(pending).catchError((Object e, StackTrace st) {
                ErrorLogger.log('Coalesced seek failed',
                    error: e,
                    stackTrace: st,
                    category: 'PlayerTransportController');
                if (!_isClosed()) {
                  final s = _getState();
                  _emit(s.copyWith(
                      playback: s.playback.copyWith(
                          errorMessage: 'Seek failed, position restored')));
                }
              });
            }
          },
        );
        return;
      }
      _lastSeekMs = nowMs;

      try {
        await _audioHandler.seekDirect(target);
      } catch (e, st) {
        ErrorLogger.log('Discrete seek failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback
                  .copyWith(errorMessage: 'Seek failed, position restored')));
        }
      }
    });
  }

  Future<void> next() async {
    await _transportMutex.protect(() async {
      try {
        await _audioHandler.skipToNext();
      } catch (e, st) {
        ErrorLogger.log('Skip to next failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(errorMessage: 'Skip failed')));
        }
      }
    });
  }

  Future<void> previous() async {
    await _transportMutex.protect(() async {
      try {
        await _audioHandler.skipToPrevious();
      } catch (e, st) {
        ErrorLogger.log('Skip to previous failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(errorMessage: 'Skip failed')));
        }
      }
    });
  }

  Future<void> skipToQueueItem(int index) async {
    await _transportMutex.protect(() async {
      final state = _getState();
      if (index < 0 || index >= state.queue.length) return;
      try {
        await _audioHandler.skipToQueueItem(index);
      } catch (e, st) {
        ErrorLogger.log('Skip to queue item failed',
            error: e, stackTrace: st, category: 'PlayerTransportController');
        if (!_isClosed()) {
          final s = _getState();
          _emit(s.copyWith(
              playback: s.playback.copyWith(errorMessage: 'Skip failed')));
        }
      }
    });
  }

  Future<void> toggleShuffle() async {
    final state = _getState();
    final prev = state.isShuffle;
    final next = !prev;
    _emit(state.copyWith(
        playback:
            state.playback.copyWith(isShuffle: next, errorMessage: null)));
    try {
      await _audioHandler.setShuffleMode(
          next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
      // Progress-only widget ticks never carry shuffle/repeat, so without a
      // forced full push the home-screen widget's shuffle icon lags behind an
      // in-app toggle until the next track change (matches the favorite path).
      _updateWidgetThrottled?.call(force: true);
    } catch (e, st) {
      ErrorLogger.log('Toggle shuffle failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
            playback: s.playback
                .copyWith(isShuffle: prev, errorMessage: 'Shuffle failed')));
      }
    }
  }

  Future<void> toggleRepeat() async {
    final state = _getState();
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
    _emit(state.copyWith(
        playback:
            state.playback.copyWith(repeatMode: next, errorMessage: null)));
    try {
      await _audioHandler.setRepeatMode(nextMode);
      // See toggleShuffle: force a full widget push so the repeat icon reflects
      // the change immediately rather than on the next full render.
      _updateWidgetThrottled?.call(force: true);
    } catch (e, st) {
      ErrorLogger.log('Toggle repeat failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(
            playback: s.playback
                .copyWith(repeatMode: prev, errorMessage: 'Repeat failed')));
      }
    }
  }

  Future<void> fastForward(
      [Duration step = const Duration(seconds: 10)]) async {
    final state = _getState();
    await seek(state.position + step);
  }

  Future<void> rewind([Duration step = const Duration(seconds: 10)]) async {
    final state = _getState();
    await seek(state.position - step);
  }

  void dispose() {
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
    _pendingSeek = null;
  }
}
