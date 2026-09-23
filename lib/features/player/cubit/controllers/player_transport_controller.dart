// lib/features/player/cubit/controllers/player_transport_controller.dart
// FIX-A1: Focused PlayerTransportController extracted from PlayerCubit
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/usecases/toggle_favorite_usecase.dart';
import '../player_constants.dart';
import '../player_state.dart';

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

  // Monotonic stopwatch for seek throttling. H-05: instance-scoped so separate
  // controller instances (e.g. test + prod) never share throttle state.
  final Stopwatch _seekStopwatch = Stopwatch()..start();
  int _lastSeekMs = 0;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeek;

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
    try {
      _onUserPausedIntentionally?.call(false);
      await _audioHandler.play();
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(isPlaying: true, errorMessage: null)));
      }
    } catch (e, st) {
      ErrorLogger.log('Play failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Failed to start playback')));
      }
    }
  }

  Future<void> pause() async {
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
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Failed to pause playback')));
      }
    }
  }

  Future<void> togglePlayPause() async {
    HapticFeedback.lightImpact();
    try {
      final state = _getState();
      final enginePlaying = _audioHandler.playbackState.value.playing;
      final shouldPause = state.isPlaying || enginePlaying;

      if (shouldPause) {
        _onUserPausedIntentionally?.call(true);
        _emit(state.copyWith(playback: state.playback.copyWith(isPlaying: false)));
        await _audioHandler.pause();
      } else {
        if (state.currentSong == null && state.queue.isEmpty) return;
        _onUserPausedIntentionally?.call(false);
        // Optimistically reflect play; the engine observer confirms it.
        if (!state.isPlaying) {
          _emit(state.copyWith(playback: state.playback.copyWith(isPlaying: true)));
        }
        await _audioHandler.play();
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle play/pause failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Playback action failed')));
      }
    }
  }

  Future<void> seek(Duration position) {
    if (_isClosed()) return Future.value();
    final state = _getState();
    var target = position.isNegative ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }

    _emit(state.copyWith(playback: state.playback.copyWith(position: target)));

    final nowMs = _seekStopwatch.elapsedMilliseconds;
    if (nowMs - _lastSeekMs < PlayerConstants.seekThrottleMs) {
      _pendingSeek = target;
      _seekThrottleTimer?.cancel();
      _seekThrottleTimer = Timer(
        Duration(
            milliseconds: (PlayerConstants.seekThrottleMs - (nowMs - _lastSeekMs))
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
                  error: e, stackTrace: st, category: 'PlayerTransportController');
              if (!_isClosed()) {
                final s = _getState();
                _emit(s.copyWith(
                    playback: s.playback.copyWith(errorMessage: 'Seek failed, position restored')));
              }
            });
          }
        },
      );
      return Future.value();
    }
    _lastSeekMs = nowMs;

    return _audioHandler.seekDirect(target).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Discrete seek failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Seek failed, position restored')));
      }
    });
  }

  Future<void> next() async {
    try {
      await _audioHandler.skipToNext();
    } catch (e, st) {
      ErrorLogger.log('Skip to next failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Skip failed')));
      }
    }
  }

  Future<void> previous() async {
    try {
      await _audioHandler.skipToPrevious();
    } catch (e, st) {
      ErrorLogger.log('Skip to previous failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Skip failed')));
      }
    }
  }

  Future<void> skipToQueueItem(int index) async {
    final state = _getState();
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.skipToQueueItem(index);
    } catch (e, st) {
      ErrorLogger.log('Skip to queue item failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: 'Skip failed')));
      }
    }
  }

  Future<void> toggleShuffle() async {
    final state = _getState();
    final prev = state.isShuffle;
    final next = !prev;
    _emit(state.copyWith(playback: state.playback.copyWith(isShuffle: next, errorMessage: null)));
    try {
      await _audioHandler.setShuffleMode(
          next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
    } catch (e, st) {
      ErrorLogger.log('Toggle shuffle failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(isShuffle: prev, errorMessage: 'Shuffle failed')));
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
    _emit(state.copyWith(playback: state.playback.copyWith(repeatMode: next, errorMessage: null)));
    try {
      await _audioHandler.setRepeatMode(nextMode);
    } catch (e, st) {
      ErrorLogger.log('Toggle repeat failed',
          error: e, stackTrace: st, category: 'PlayerTransportController');
      if (!_isClosed()) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(repeatMode: prev, errorMessage: 'Repeat failed')));
      }
    }
  }

  Future<void> toggleFavoriteSong(SongsTableData song) =>
      _executeToggleFavorite(song);

  Future<void> toggleFavoriteById(int songId) async {
    final state = _getState();
    final song = (state.currentSong?.id == songId)
        ? state.currentSong
        : (state.queue.where((s) => s.id == songId).firstOrNull ??
            _slotLookupCache?[songId]);
    if (song != null) {
      await _executeToggleFavorite(song);
    }
  }

  Future<void> toggleFavorite([dynamic target]) async {
    if (target is SongsTableData) {
      return toggleFavoriteSong(target);
    } else if (target is int) {
      return toggleFavoriteById(target);
    } else if (target == null) {
      final current = _getState().currentSong;
      if (current != null) return toggleFavoriteSong(current);
    }
  }

  Future<void> _executeToggleFavorite(SongsTableData song) async {
    if (_toggleFavoriteUseCase == null) return;
    final songId = song.id;
    final result = await _toggleFavoriteUseCase!(song.id);
    if (_isClosed()) return;
    result.fold(
      (failure) {
        final s = _getState();
        _emit(s.copyWith(playback: s.playback.copyWith(errorMessage: failure.message)));
      },
      (isFav) {
        final state = _getState();
        final updatedQueue = state.queue
            .map((s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s)
            .toList();
        if (_slotLookupCache != null) {
          final cached = _slotLookupCache![songId];
          if (cached != null) {
            _slotLookupCache![songId] = cached.copyWith(isFavorite: isFav);
          }
        }
        _debouncedPersistQueueSlots?.call();
        if (state.currentSong != null && state.currentSong!.id == songId) {
          _emit(
            state.copyWith(
              playback: state.playback.copyWith(
                currentSong: state.currentSong!.copyWith(isFavorite: isFav),
                errorMessage: null,
              ),
              queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
            ),
          );
          _updateWidgetThrottled?.call(force: true);
        } else if (state.queue.any((s) => s.id == songId)) {
          _emit(state.copyWith(
            queueSlice: state.queueSlice.copyWith(queue: updatedQueue),
            playback: state.playback.copyWith(errorMessage: null),
          ));
        }
      },
    );
  }

  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) async {
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
