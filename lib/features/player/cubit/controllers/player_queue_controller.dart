// lib/features/player/cubit/controllers/player_queue_controller.dart
// FIX-A1: Focused PlayerQueueController extracted from PlayerCubit
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/prefs_keys.dart';
import '../../../../core/services/radio_station_store.dart';
import '../../../../core/telemetry/playback_latency_tracker.dart';
import '../../../../core/utils/async_guard.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../../../../domain/models/radio_station.dart';
import '../../../../domain/repositories/music_repository_interface.dart';
import '../player_state.dart';
import '../queue_slot_codec.dart';
import 'queue_slot_data.dart';

part 'player_queue_slots.dart';
part 'player_queue_warming.dart';
part 'player_queue_radio.dart';

/// Controls playback queue management, slot switching, and reordering.
class PlayerQueueController {
  static const int maxQueueSize = 500;

  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final PlayerState Function() _getState;
  final void Function(PlayerState state) _emit;
  final bool Function() _isClosed;
  final Mutex _queueMutex;
  final Map<int, SongsTableData> _slotLookupCache;
  final Map<int, QueueSlotData> _queueSlots;
  final void Function({bool force}) _updateWidgetThrottled;
  final void Function(SongsTableData song) _loadLyrics;
  final void Function() _debouncedPersistQueueSlots;
  final void Function() _bumpQueueVersion;
  final bool Function(SongsTableData? a, SongsTableData? b) _isSameTrack;
  final PlaybackLatencyTracker? _latencyTracker;

  /// A-01: Invoked when a track is resumed (initialPosition provided) so the
  /// per-song speed/pitch/volume/EQ memory can be re-applied.
  final void Function(SongsTableData song)? _onResumePerSongMemory;

  /// Invalidates any in-flight restored-queue resolver on the owning cubit so a
  /// slow DB lookup for an older engine-queue snapshot cannot clobber a
  /// just-applied programmatic queue mutation. No-op when not wired.
  final void Function() _invalidateQueueSyncResolution;

  Timer? _persistQueueDebounce;

  // Async guards for coordination
  final AsyncGuard _mediaItemResolutionGuard = AsyncGuard();
  final AsyncGuard _localMatchSwapGuard = AsyncGuard();
  final AsyncGuard _mediaItemGuard = AsyncGuard();
  final AsyncGuard _lyricsGuard = AsyncGuard();

  AsyncGuard get mediaItemResolutionGuard => _mediaItemResolutionGuard;
  AsyncGuard get localMatchSwapGuard => _localMatchSwapGuard;
  AsyncGuard get mediaItemGuard => _mediaItemGuard;
  AsyncGuard get lyricsGuard => _lyricsGuard;

  bool _isSwitchingSlot = false;

  PlayerQueueController({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    required Mutex queueMutex,
    required Map<int, SongsTableData> slotLookupCache,
    required Map<int, QueueSlotData> queueSlots,
    required void Function({bool force}) updateWidgetThrottled,
    required void Function(SongsTableData song) loadLyrics,
    void Function()? debouncedPersistQueueSlots,
    required void Function() bumpQueueVersion,
    required bool Function(SongsTableData? a, SongsTableData? b) isSameTrack,
    PlaybackLatencyTracker? latencyTracker,
    void Function(SongsTableData song)? onResumePerSongMemory,
    void Function()? invalidateQueueSyncResolution,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _queueMutex = queueMutex,
        _slotLookupCache = slotLookupCache,
        _queueSlots = queueSlots,
        _updateWidgetThrottled = updateWidgetThrottled,
        _loadLyrics = loadLyrics,
        _debouncedPersistQueueSlots = debouncedPersistQueueSlots ?? (() {}),
        _bumpQueueVersion = bumpQueueVersion,
        _isSameTrack = isSameTrack,
        _latencyTracker = latencyTracker,
        _onResumePerSongMemory = onResumePerSongMemory,
        _invalidateQueueSyncResolution =
            invalidateQueueSyncResolution ?? (() {});

  Future<void> playSong(
    SongsTableData song, {
    List<SongsTableData>? queue,
    Duration? initialPosition,
    bool openPlayerIfPlaying = true,
  }) =>
      _queueMutex.protect(() => _playSongLocked(
            song,
            queue: queue,
            initialPosition: initialPosition,
            openPlayerIfPlaying: openPlayerIfPlaying,
          ));

  Future<void> _playSongLocked(
    SongsTableData song, {
    List<SongsTableData>? queue,
    Duration? initialPosition,
    bool openPlayerIfPlaying = true,
  }) async {
    final state = _getState();
    if (openPlayerIfPlaying &&
        initialPosition == null &&
        _isSameTrack(state.currentSong, song)) {
      // A supplied queue is a request to replace/reorder the current queue (e.g.
      // the Queue screen "Shuffle" action passes the current song with a freshly
      // shuffled queue). Only take the plain resume shortcut when the queue is
      // unchanged; otherwise fall through so the new order is actually applied.
      final queueUnchanged = queue == null ||
          listEquals(
            queue.map((s) => s.id).toList(growable: false),
            state.queue.map((s) => s.id).toList(growable: false),
          );
      if (queueUnchanged) {
        _emit(state.copyWith(
            playback: state.playback.copyWith(isExpanded: true)));
        if (!state.isPlaying) {
          try {
            await _audioHandler.play();
          } catch (e, st) {
            ErrorLogger.log('Resume of current song failed',
                error: e, stackTrace: st, category: 'PlayerQueueController');
            if (!_isClosed()) {
              final s = _getState();
              _emit(s.copyWith(
                  playback: s.playback
                      .copyWith(errorMessage: 'Failed to play ${song.title}')));
            }
          }
        }
        return;
      }
    }

    final videoIdForLatency = song.remoteId ?? song.id.toString();
    try {
      _latencyTracker?.start(videoId: videoIdForLatency);
      _latencyTracker?.markStage(PlaybackStage.tap);
    } catch (_) {}

    try {
      _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
    } catch (_) {}

    final capturedGen = _mediaItemResolutionGuard.next();
    final capturedSwapGen = _localMatchSwapGuard.next();
    _mediaItemGuard.next();

    final rawQueue = queue != null ? List<SongsTableData>.from(queue) : [song];
    var targetIndex = rawQueue.indexWhere((s) => _isSameTrack(s, song));
    if (targetIndex == -1) {
      targetIndex = 0;
      rawQueue.insert(0, song);
    }

    List<SongsTableData> effectiveQueue;
    int effectiveIndex;

    if (rawQueue.length > maxQueueSize) {
      final halfWindow = maxQueueSize ~/ 2;
      var start = targetIndex - halfWindow;
      if (start < 0) start = 0;
      if (start + maxQueueSize > rawQueue.length) {
        start = (rawQueue.length - maxQueueSize).clamp(0, rawQueue.length);
      }
      effectiveQueue = rawQueue.sublist(start, start + maxQueueSize);
      effectiveIndex = targetIndex - start;
      final headDropped = start > 0;
      final tailDropped = start + maxQueueSize < rawQueue.length;
      final dropMsg = (headDropped && tailDropped)
          ? 'head and tail dropped'
          : (headDropped ? 'head dropped' : 'tail dropped');
      ErrorLogger.log(
        'Queue truncated to $maxQueueSize (was ${rawQueue.length}) — $dropMsg',
        category: 'PlayerQueueController',
      );
    } else {
      effectiveQueue = rawQueue;
      effectiveIndex = targetIndex;
    }

    final isSameSong = _isSameTrack(state.currentSong, song);
    // When the same track keeps playing but its queue is being replaced (e.g.
    // Shuffle), preserve the current position instead of restarting from zero.
    final startPos = initialPosition ??
        ((queue != null && isSameSong) ? state.position : Duration.zero);
    final prevSlot = _queueSlots[state.activeQueueSlot];
    final prevQueue = state.queue;
    final prevIndex = state.currentIndex;
    final prevSong = state.currentSong;
    final prevPosition = state.position;
    final prevDuration = state.duration;
    final prevLyrics = state.lyrics;
    final prevLyricsSource = state.lyricsSource;

    setQueueSlot(
      state.activeQueueSlot,
      songs: List.from(effectiveQueue),
      currentIndex: effectiveIndex,
      position: startPos,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();

    _emit(state.copyWith(
      queueSlice: state.queueSlice.copyWith(
        queue: effectiveQueue,
        currentIndex: effectiveIndex,
      ),
      playback: state.playback.copyWith(
        currentSong: song,
        duration: Duration(milliseconds: song.durationMs),
        position: startPos,
        // BUG-3 FIX: do NOT optimistically set isPlaying=true before loadQueue
        // is called. There is an async gap between this emit and the loadQueue
        // call below; if the cubit closes or the load fails in that window the
        // state would permanently claim the track is playing. The playbackState
        // observer in PlayerCubit flips isPlaying=true once the engine confirms
        // playback. Keep the previous isPlaying value here so the UI does not
        // flicker to "playing" and immediately back to "paused" on a fast navigation.
        isPlaying: state.isPlaying,
        errorMessage: null,
      ),
      lyricsSlice: state.lyricsSlice.copyWith(
        lyrics: isSameSong ? state.lyrics : const [],
        lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
      ),
    ));

    _updateWidgetThrottled(force: true);
    _invalidateQueueSyncResolution();

    try {
      await _audioHandler.loadQueue(
        effectiveQueue,
        initialIndex: effectiveIndex,
        initialPosition: startPos,
        autoPlay: true,
      );
      if (_mediaItemResolutionGuard.isValid(capturedGen) && !_isClosed()) {
        _loadLyrics(song);
      }
    } catch (e, st) {
      ErrorLogger.log('Load queue failed for song ${song.id}',
          error: e, stackTrace: st, category: 'PlayerQueueController');

      // C3 FIX: Rollback and invalidate parallel guards so late resolution/match futures cannot re-apply failed queue
      _mediaItemResolutionGuard.invalidate();
      _localMatchSwapGuard.invalidate();
      _lyricsGuard.invalidate();

      assert(!_mediaItemResolutionGuard.isValid(capturedGen),
          'Resolution guard must be invalid after rollback');

      if (!_isClosed()) {
        if (prevSlot != null) {
          _queueSlots[state.activeQueueSlot] = prevSlot;
        } else {
          _queueSlots.remove(state.activeQueueSlot);
        }
        _debouncedPersistQueueSlots();
        _bumpQueueVersion();
        // BUG-4 FIX: build the rollback state entirely from the pre-call
        // snapshots (prev*). The old code fetched _getState() for the playback
        // sub-tree and mixed it with prev* values for the queue sub-tree. If a
        // position tick or any other async observer ran between the optimistic
        // emit and the error catch, those intermediate values leaked into the
        // rollback — leaving isPlaying/position/etc. inconsistent with the
        // reverted queue. Using a fully captured snapshot avoids the mismatch.
        _emit(state.copyWith(
          queueSlice: state.queueSlice.copyWith(
            queue: prevQueue,
            currentIndex: prevIndex,
          ),
          playback: state.playback.copyWith(
            currentSong: prevSong,
            duration: prevDuration,
            position: prevPosition,
            isPlaying: false,
            errorMessage: 'Failed to play ${song.title}',
          ),
          lyricsSlice: state.lyricsSlice.copyWith(
            lyrics: prevLyrics,
            lyricsSource: prevLyricsSource,
          ),
        ));
        _invalidateQueueSyncResolution();
        try {
          if (prevQueue.isNotEmpty) {
            await _audioHandler.loadQueue(
              prevQueue,
              initialIndex: prevIndex,
              initialPosition: prevPosition,
              autoPlay: false,
            );
          }
        } catch (rollbackError, rollbackSt) {
          // C-03: The rollback itself failed. Previously this was swallowed,
          // leaving state claiming `prevQueue` while the audio handler had
          // nothing loaded. Log it and clear the queue so the UI is truthful.
          ErrorLogger.log(
            'Queue rollback failed after load error',
            error: rollbackError,
            stackTrace: rollbackSt,
            category: 'PlayerQueueController',
          );
          try {
            await _audioHandler.pause();
          } catch (_) {}
          try {
            await _audioHandler.clearQueue();
          } catch (_) {}
          try {
            if (!_isClosed()) {
              final broken = _getState();
              _emit(broken.copyWith(
                queueSlice: broken.queueSlice
                    .copyWith(queue: const [], currentIndex: 0),
                playback: broken.playback.copyWith(
                  currentSong: null,
                  isPlaying: false,
                  errorMessage:
                      'Playback unavailable — please pick another track',
                ),
              ));
            }
          } catch (emitError, emitSt) {
            ErrorLogger.log(
                'Failed to emit terminal error state on queue failure',
                error: emitError,
                stackTrace: emitSt,
                category: 'PlayerQueueController');
          }
        }
      }
      return;
    }

    // A-01: On resume (bookmark / last position) restore this track's remembered
    // speed/pitch/volume/EQ. Fire-and-forget: it re-checks the current song
    // before applying so a fast skip cannot clobber the new track.
    if (initialPosition != null && !_isClosed()) {
      _onResumePerSongMemory?.call(song);
    }

    if (_mediaItemResolutionGuard.isValid(capturedGen) && !_isClosed()) {
      _findNextLocalMatch(
          song, effectiveQueue, effectiveIndex, capturedSwapGen, capturedGen);
    }
  }

  void dispose() {
    if (_persistQueueDebounce != null) {
      _persistQueueDebounce?.cancel();
      _persistQueueDebounce = null;
      persistQueueSlotsNow();
    }
    _mediaItemResolutionGuard.invalidate();
    _localMatchSwapGuard.invalidate();
    _mediaItemGuard.invalidate();
    _lyricsGuard.invalidate();
  }
}
