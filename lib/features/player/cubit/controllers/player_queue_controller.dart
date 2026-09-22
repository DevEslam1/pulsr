// lib/features/player/cubit/controllers/player_queue_controller.dart
// FIX-A1: Focused PlayerQueueController extracted from PlayerCubit
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:mutex/mutex.dart';
import '../../../../core/utils/error_logger.dart';
import '../../../../data/audio/audio_handler.dart';
import '../../../../data/db/app_database.dart';
import '../../../../domain/models/lyrics_line.dart';
import '../player_state.dart';

import 'queue_slot_data.dart';

/// Controls playback queue management, slot switching, and reordering.
class PlayerQueueController {
  static const int maxQueueSize = 500;

  final PulsrAudioHandler _audioHandler;
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

  bool _isSwitchingSlot = false;

  PlayerQueueController({
    required PulsrAudioHandler audioHandler,
    required PlayerState Function() getState,
    required void Function(PlayerState state) emit,
    required bool Function() isClosed,
    required Mutex queueMutex,
    required Map<int, SongsTableData> slotLookupCache,
    required Map<int, QueueSlotData> queueSlots,
    required void Function({bool force}) updateWidgetThrottled,
    required void Function(SongsTableData song) loadLyrics,
    required void Function() debouncedPersistQueueSlots,
    required void Function() bumpQueueVersion,
    required bool Function(SongsTableData? a, SongsTableData? b) isSameTrack,
  })  : _audioHandler = audioHandler,
        _getState = getState,
        _emit = emit,
        _isClosed = isClosed,
        _queueMutex = queueMutex,
        _slotLookupCache = slotLookupCache,
        _queueSlots = queueSlots,
        _updateWidgetThrottled = updateWidgetThrottled,
        _loadLyrics = loadLyrics,
        _debouncedPersistQueueSlots = debouncedPersistQueueSlots,
        _bumpQueueVersion = bumpQueueVersion,
        _isSameTrack = isSameTrack;

  void setQueueSlot(
    int slot, {
    required List<SongsTableData> songs,
    required int currentIndex,
    required Duration position,
    required double speed,
  }) {
    for (final s in songs) {
      _slotLookupCache[s.id] = s;
    }
    _queueSlots[slot] = QueueSlotData(
      songIds: songs.map((s) => s.id).toList(),
      currentIndex: currentIndex,
      position: position,
      speed: speed,
    );
  }

  Future<void> addToQueue(SongsTableData song) async {
    final state = _getState();
    if (state.queue.length >= maxQueueSize) {
      _emit(state.copyWith(
          errorMessage: 'Queue full ($maxQueueSize) — cannot add more'));
      return;
    }
    try {
      await _audioHandler.addToQueueEnd(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to add to queue end',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        _emit(state.copyWith(errorMessage: 'Failed to add ${song.title}'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final existingIdx = updatedQueue.indexWhere((s) => _isSameTrack(s, song));
    if (existingIdx != -1) {
      if (existingIdx != state.currentIndex &&
          existingIdx != updatedQueue.length - 1) {
        final item = updatedQueue.removeAt(existingIdx);
        updatedQueue.add(item);
      }
    } else {
      updatedQueue.add(song);
    }
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addAllToQueue(List<SongsTableData> songs) async {
    final state = _getState();
    if (songs.isEmpty || _isClosed()) return;
    final room = maxQueueSize - state.queue.length;
    if (room <= 0) {
      _emit(state.copyWith(
          errorMessage: 'Queue full ($maxQueueSize) — cannot add more'));
      return;
    }
    final toAdd = songs
        .where((s) => !state.queue.any((q) => _isSameTrack(q, s)))
        .take(room)
        .toList();

    final added = <SongsTableData>[];
    for (final s in toAdd) {
      try {
        await _audioHandler.addToQueueEnd(s);
        added.add(s);
      } catch (e, st) {
        ErrorLogger.log('Failed to batch-add to queue',
            error: e, stackTrace: st, category: 'PlayerQueueController');
        if (!_isClosed()) {
          _emit(state.copyWith(errorMessage: 'Failed to add ${s.title}'));
        }
        break;
      }
    }
    if (added.isEmpty) return;
    final updatedQueue = List<SongsTableData>.from(state.queue)..addAll(added);
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> clearQueue() async {
    final state = _getState();
    try {
      await _audioHandler.clearQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed to clear queue',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        _emit(state.copyWith(errorMessage: 'Failed to clear queue'));
      }
      return;
    }
    final current = state.currentSong;
    final updatedQueue = current != null ? [current] : <SongsTableData>[];
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: 0,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(queue: updatedQueue, currentIndex: 0));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final state = _getState();
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex >= state.queue.length) {
      return;
    }
    if (oldIndex == newIndex) return;
    try {
      await _audioHandler.reorderQueue(oldIndex, newIndex);
    } catch (e, st) {
      ErrorLogger.log('Failed to reorder queue',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        _emit(state.copyWith(errorMessage: 'Failed to reorder queue'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);
    final updatedIndex = calculateReorderedIndex(oldIndex, newIndex, state.currentIndex);
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  Future<void> removeQueueItem(int index) async {
    final state = _getState();
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.removeQueueItemAt(index);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove queue item',
          error: e, stackTrace: st, category: 'PlayerQueueController');
      if (!_isClosed()) {
        _emit(state.copyWith(errorMessage: 'Failed to remove track'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue)..removeAt(index);
    final updatedIndex = calculateRemovedIndex(index, state.currentIndex, updatedQueue.length);
    if (index == state.currentIndex) {
      _bumpQueueVersion();
      if (updatedQueue.isEmpty) {
        setQueueSlot(state.activeQueueSlot, songs: const [], currentIndex: 0, position: Duration.zero, speed: state.playbackSpeed);
        _debouncedPersistQueueSlots();
        _emit(state.copyWith(queue: const [], currentIndex: 0, currentSong: null, isPlaying: false, position: Duration.zero, duration: Duration.zero));
        _updateWidgetThrottled(force: true);
        return;
      }
      final newCurrent = updatedQueue[updatedIndex];
      _setQueueSlotAndEmit(state, updatedQueue, updatedIndex, newCurrent);
      return;
    }
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _bumpQueueVersion();
    _emit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  void _setQueueSlotAndEmit(PlayerState state, List<SongsTableData> updatedQueue,
      int updatedIndex, SongsTableData newCurrent) {
    final sameTrack = _isSameTrack(state.currentSong, newCurrent);
    _bumpQueueVersion();
    setQueueSlot(
      state.activeQueueSlot,
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: Duration.zero,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _emit(state.copyWith(
      queue: updatedQueue,
      currentIndex: updatedIndex,
      currentSong: newCurrent,
      position: Duration.zero,
      duration: Duration(milliseconds: newCurrent.durationMs),
      lyrics: sameTrack ? state.lyrics : [],
      lyricsSource: sameTrack ? state.lyricsSource : LyricsSource.none,
      isLoadingLyrics: !sameTrack,
    ));
    _loadLyrics(newCurrent);
    _updateWidgetThrottled(force: true);
  }

  Future<void> switchQueueSlot(int slot) async {
    final state = _getState();
    if (_isSwitchingSlot ||
        slot == state.activeQueueSlot ||
        slot < 0 ||
        slot > 2) {
      return;
    }
    _isSwitchingSlot = true;
    try {
      final wasPlaying = state.isPlaying ||
          _audioHandler.playbackState.value.processingState ==
              AudioProcessingState.completed;
      setQueueSlot(
        state.activeQueueSlot,
        songs: List.from(state.queue),
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      final targetSlot = _queueSlots[slot] ??
          const QueueSlotData(
              songIds: [], currentIndex: 0, position: Duration.zero, speed: 1.0);
      final targetSongs = targetSlot.songsFrom(_slotLookupCache);
      final targetOriginalSong = (targetSlot.currentIndex >= 0 &&
              targetSlot.currentIndex < targetSongs.length)
          ? targetSongs[targetSlot.currentIndex]
          : null;
      final validSongs = targetSongs.where((s) => !s.isMissing).toList();

      _debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        _emit(state.copyWith(errorMessage: 'Queue slot is empty'));
        return;
      }

      _bumpQueueVersion();
      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx = validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
      }
      if (safeIdx == -1) {
        safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      }
      final song = validSongs[safeIdx];
      _emit(state.copyWith(
        activeQueueSlot: slot,
        queue: validSongs,
        currentIndex: safeIdx,
        currentSong: song,
        duration: Duration(milliseconds: song.durationMs),
        position: targetSlot.position,
        playbackSpeed: targetSlot.speed,
      ));
      try {
        await _audioHandler.setSpeed(targetSlot.speed);
        await _audioHandler.loadQueue(
          validSongs,
          initialIndex: safeIdx,
          initialPosition: targetSlot.position,
          autoPlay: wasPlaying,
        );
        _loadLyrics(song);
      } catch (e, st) {
        ErrorLogger.log('Failed to switch queue slot $slot',
            error: e, stackTrace: st, category: 'PlayerQueueController');
        if (!_isClosed()) {
          _emit(_getState().copyWith(errorMessage: 'Failed to switch queue slot'));
        }
      }
    } finally {
      _isSwitchingSlot = false;
    }
  }

  void swapReconciledSong(int oldId, SongsTableData newSong) {
    _slotLookupCache[newSong.id] = newSong;
    _slotLookupCache.remove(oldId);
    _queueMutex.protect(() async {
      _queueSlots.updateAll((slot, data) {
        if (!data.songIds.contains(oldId)) return data;
        return QueueSlotData(
          songIds: data.songIds.map((id) => id == oldId ? newSong.id : id).toList(),
          currentIndex: data.currentIndex,
          position: data.position,
          speed: data.speed,
        );
      });
    });
    _debouncedPersistQueueSlots();

    final state = _getState();
    if (state.queue.any((s) => s.id == oldId)) {
      _bumpQueueVersion();
      _emit(state.copyWith(
        queue: state.queue.map((s) => s.id == oldId ? newSong : s).toList(),
        currentSong:
            state.currentSong?.id == oldId ? newSong : state.currentSong,
      ));
      _updateWidgetThrottled(force: true);
    }

    try {
      _audioHandler.swapReconciledSong(oldId, newSong);
    } catch (_) {}
  }
}
