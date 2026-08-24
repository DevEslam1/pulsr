import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/lrc_parser.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../widgets/widget_service.dart';
import 'player_state.dart';

class _QueueSlotData {
  final List<SongsTableData> songs;
  final int currentIndex;
  final Duration position;

  const _QueueSlotData({
    required this.songs,
    required this.currentIndex,
    required this.position,
  });
}

@lazySingleton
class PlayerCubit extends Cubit<PlayerState> {
  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final SettingsCubit? _settingsCubit;
  final WidgetService? _widgetService;
  final ScrobblerService? _scrobblerService;

  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _settingsSub;
  StreamSubscription? _widgetClickSub;
  StreamSubscription? _sleepTimerSub;
  DateTime? _lastWidgetUpdateTime;

  final Map<int, _QueueSlotData> _queueSlots = {
    0: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero),
    1: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero),
    2: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero),
  };

  PlayerCubit({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    SettingsCubit? settingsCubit,
    WidgetService? widgetService,
    ScrobblerService? scrobblerService,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _settingsCubit = settingsCubit,
        _widgetService = widgetService,
        _scrobblerService = scrobblerService,
        super(const PlayerState()) {
    _listenToAudioService();
    _loadPlaybackSpeed();
    _listenToSettings();
    _listenToWidgetClicks();
    _syncAudioEffects();
    _updateWidgetThrottled(force: true);
  }

  void _syncAudioEffects() {
    emit(state.copyWith(
      isEqEnabled: _audioHandler.isEqualizerEnabled,
      eqPreset: _audioHandler.currentPreset,
      isVirtualizerEnabled: _audioHandler.isVirtualizerEnabled,
      virtualizerStrength: _audioHandler.virtualizerStrength,
      isDynamicsEnabled: _audioHandler.isDynamicsEnabled,
      dynamicsPreset: _audioHandler.dynamicsPreset,
      selectedHeadphoneProfile: _audioHandler.selectedHeadphoneProfile,
      isSpatializerEnabled: _audioHandler.isSpatializerEnabled,
      isSpatializerSupported: _audioHandler.isSpatializerSupported,
      volumeBoost: _audioHandler.volumeBoost,
    ));
  }

  void clearError() {
    emit(state.copyWith(errorMessage: null));
  }

  void _listenToSettings() {
    final settingsCubit = _settingsCubit;
    if (settingsCubit != null) {
      _audioHandler.setCrossfadeDuration(
        Duration(milliseconds: (settingsCubit.state.crossfadeSeconds * 1000).round()),
      );
      _settingsSub = settingsCubit.stream
          .map((s) => s.crossfadeSeconds)
          .distinct()
          .listen((seconds) {
        _audioHandler.setCrossfadeDuration(
          Duration(milliseconds: (seconds * 1000).round()),
        );
      });
    }
  }

  void _listenToWidgetClicks() {
    _widgetClickSub = _widgetService?.listenToWidgetClicks((uri) {
      if (uri != null && uri.scheme.toLowerCase() == 'pulsrwidget') {
        final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
        switch (action) {
          case 'play_pause':
            togglePlayPause();
            break;
          case 'prev':
            previous();
            break;
          case 'next':
            next();
            break;
          case 'favorite':
            final song = state.currentSong;
            if (song != null) toggleFavorite(song.id);
            break;
          case 'open':
          case 'main':
            final ctx = rootNavigatorKey.currentContext;
            if (ctx != null) GoRouter.of(ctx).go('/now-playing');
            break;
        }
      }
    });
  }

  void _updateWidgetThrottled({bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastWidgetUpdateTime != null && now.difference(_lastWidgetUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastWidgetUpdateTime = now;
    _widgetService?.updateNowPlaying(
      song: state.currentSong,
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
      isFavorite: state.currentSong?.isFavorite ?? false,
      isShuffle: state.isShuffle,
      repeatMode: switch (state.repeatMode) {
        PlayerRepeatMode.one => 'one',
        PlayerRepeatMode.all => 'all',
        PlayerRepeatMode.off => 'off',
      },
    );
  }

  void _listenToAudioService() {
    _mediaItemSub = _audioHandler.mediaItem.listen((item) async {
      if (item != null) {
        final id = int.tryParse(item.id);
        if (id != null) {
          final songResult = await _repository.getSongById(id);
          songResult.fold(
            (failure) => emit(state.copyWith(errorMessage: failure.message)),
            (song) {
              if (song != null) {
                emit(
                  state.copyWith(
                    currentSong: song,
                    duration: Duration(milliseconds: song.durationMs),
                    errorMessage: null,
                  ),
                );
                _loadLyricsForSong(song);
                _updateWidgetThrottled(force: true);
                _scrobblerService?.notifyPlaybackState(
                  id: song.id,
                  artist: song.artist,
                  track: song.title,
                  album: song.album,
                  durationMs: song.durationMs,
                  positionMs: state.position.inMilliseconds,
                  isPlaying: state.isPlaying,
                );
              }
            },
          );
        }
      }
    });

    _playbackStateSub = _audioHandler.playbackState.listen((playbackState) {
      final isCompleted = playbackState.processingState == AudioProcessingState.completed;
      final repeat = switch (playbackState.repeatMode) {
        AudioServiceRepeatMode.one => PlayerRepeatMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => PlayerRepeatMode.all,
        _ => PlayerRepeatMode.off,
      };

      final isPlaying = playbackState.playing && !isCompleted;
      emit(
        state.copyWith(
          isPlaying: isPlaying,
          position: isCompleted ? Duration.zero : playbackState.position,
          isShuffle: playbackState.shuffleMode == AudioServiceShuffleMode.all,
          repeatMode: repeat,
          currentIndex: playbackState.queueIndex ?? state.currentIndex,
          playbackSpeed: playbackState.speed,
        ),
      );
      _updateWidgetThrottled(force: false);
      final currentSong = state.currentSong;
      if (currentSong != null) {
        _scrobblerService?.notifyPlaybackState(
          id: currentSong.id,
          artist: currentSong.artist,
          track: currentSong.title,
          album: currentSong.album,
          durationMs: currentSong.durationMs,
          positionMs: playbackState.position.inMilliseconds,
          isPlaying: isPlaying,
        );
      }
    });

    _positionSub = _audioHandler.positionStream.listen((pos) {
      if ((pos - state.position).abs() > const Duration(milliseconds: 250)) {
        emit(state.copyWith(position: pos));
        if (state.isPlaying) {
          _updateWidgetThrottled(force: false);
        }
      }
    });

    _sleepTimerSub = _audioHandler.sleepTimerRemainingStream.listen((remaining) {
      emit(state.copyWith(sleepTimerRemaining: remaining));
    });
  }

  Future<void> _loadLyricsForSong(SongsTableData song) async {
    if (isClosed) return;
    // A YouTube row's path is a ytmusic:// sentinel, not a file on disk, so
    // LrcParser (which reads sidecar/embedded lyrics off the path) has nothing
    // to resolve. Clear lyrics and skip the lookup.
    if (song.source != SongSource.local) {
      emit(state.copyWith(
        isLoadingLyrics: false,
        lyrics: [],
        lyricsSource: LyricsSource.none,
      ));
      return;
    }
    emit(state.copyWith(
      isLoadingLyrics: true,
      lyrics: [],
      lyricsSource: LyricsSource.none,
    ));
    final lyricsResult = await LrcParser.resolveLyrics(song.path);
    if (isClosed) return;
    emit(state.copyWith(
      isLoadingLyrics: false,
      lyrics: lyricsResult?.lines ?? [],
      lyricsSource: lyricsResult?.source ?? LyricsSource.none,
    ));
  }

  Future<void> playSong(SongsTableData song, {List<SongsTableData>? queue, Duration? initialPosition}) async {
    // If playing an online song that has already been downloaded to the device, swap to local song
    SongsTableData targetSong = song;
    if (song.source == SongSource.youtube) {
      try {
        final match = await _repository.findMatchingLocalSong(
          remoteId: song.remoteId,
          title: song.title,
          artist: song.artist,
        );
        final local = match.fold((_) => null, (s) => s);
        if (local != null && (File(local.path).existsSync() || local.path.startsWith('content:'))) {
          targetSong = local;
        }
      } catch (_) {}
    }

    var effectiveQueue = queue ?? [targetSong];
    if (targetSong.id != song.id) {
      effectiveQueue = effectiveQueue.map((s) => s.id == song.id ? targetSong : s).toList();
    }

    final index = effectiveQueue.indexWhere((s) => s.id == targetSong.id);
    final startPos = initialPosition ?? Duration.zero;
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: List.from(effectiveQueue),
      currentIndex: index != -1 ? index : 0,
      position: startPos,
    );
    emit(state.copyWith(
      queue: effectiveQueue,
      currentIndex: index != -1 ? index : 0,
      currentSong: targetSong,
      position: startPos,
      duration: Duration(milliseconds: targetSong.durationMs),
    ));
    await _audioHandler.loadQueue(
      effectiveQueue,
      initialIndex: index != -1 ? index : 0,
      initialPosition: startPos,
    );
    _loadLyricsForSong(targetSong);
    _updateWidgetThrottled(force: true);
  }

  Future<void> playNext(SongsTableData song) async {
    await _audioHandler.insertNextInQueue(song);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final insertIdx = (state.currentIndex + 1).clamp(0, updatedQueue.length);
    updatedQueue.insert(insertIdx, song);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
    );
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    await _audioHandler.addToQueueEnd(song);
    final updatedQueue = List<SongsTableData>.from(state.queue)..add(song);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
    );
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _audioHandler.reorderQueue(oldIndex, newIndex);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    if (oldIndex < newIndex) newIndex -= 1;
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
    );
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> removeQueueItem(int index) async {
    await _audioHandler.removeQueueItemAt(index);
    final updatedQueue = List<SongsTableData>.from(state.queue)..removeAt(index);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
    );
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> switchQueueSlot(int slot) async {
    if (slot == state.activeQueueSlot || slot < 0 || slot > 2) return;
    final wasPlaying = state.isPlaying;
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: List.from(state.queue),
      currentIndex: state.currentIndex,
      position: state.position,
    );
    final targetSlot = _queueSlots[slot] ?? const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero);
    emit(state.copyWith(activeQueueSlot: slot, queue: targetSlot.songs));
    if (targetSlot.songs.isNotEmpty) {
      final safeIdx = targetSlot.currentIndex.clamp(0, targetSlot.songs.length - 1);
      final song = targetSlot.songs[safeIdx];
      emit(state.copyWith(
        currentIndex: safeIdx,
        currentSong: song,
        duration: Duration(milliseconds: song.durationMs),
        position: targetSlot.position,
      ));
      await _audioHandler.loadQueue(
        targetSlot.songs,
        initialIndex: safeIdx,
        initialPosition: targetSlot.position,
      );
      if (!wasPlaying) {
        await _audioHandler.pause();
      }
      _loadLyricsForSong(song);
    }
  }

  /// After a YouTube row is downloaded and folded into a positive-id local row,
  /// swap the stale negative-id row in the queues so favorite/tag/queue UI stay
  /// coherent. Pure state update: the handler keeps streaming the current track
  /// uninterrupted; the local file takes over on the next load.
  Future<void> swapReconciledSong(int oldId, int newId) async {
    if (oldId == newId) return;
    final result = await _repository.getSongById(newId);
    final newSong = result.fold((_) => null, (s) => s);
    if (newSong == null || isClosed) return;

    _queueSlots.updateAll((slot, data) {
      if (!data.songs.any((s) => s.id == oldId)) return data;
      return _QueueSlotData(
        songs: data.songs.map((s) => s.id == oldId ? newSong : s).toList(),
        currentIndex: data.currentIndex,
        position: data.position,
      );
    });

    if (state.queue.any((s) => s.id == oldId)) {
      emit(state.copyWith(
        queue: state.queue.map((s) => s.id == oldId ? newSong : s).toList(),
        currentSong: state.currentSong?.id == oldId ? newSong : state.currentSong,
      ));
      _updateWidgetThrottled(force: true);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  Future<void> seek(Duration position) => _audioHandler.seek(position);

  Future<void> next() => _audioHandler.skipToNext();

  Future<void> previous() => _audioHandler.skipToPrevious();

  Future<void> toggleShuffle() async {
    final next = !state.isShuffle;
    await _audioHandler.setShuffleMode(next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
  }

  Future<void> toggleRepeat() async {
    final nextMode = switch (state.repeatMode) {
      PlayerRepeatMode.off => AudioServiceRepeatMode.all,
      PlayerRepeatMode.all => AudioServiceRepeatMode.one,
      PlayerRepeatMode.one => AudioServiceRepeatMode.none,
    };
    await _audioHandler.setRepeatMode(nextMode);
  }

  Future<void> toggleFavorite(int songId) async {
    final result = await _toggleFavoriteUseCase(songId);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
      (isFav) {
        if (state.currentSong != null && state.currentSong!.id == songId) {
          emit(
            state.copyWith(
              currentSong: state.currentSong!.copyWith(
                isFavorite: isFav,
              ),
              errorMessage: null,
            ),
          );
          _updateWidgetThrottled(force: true);
        }
      },
    );
  }

  // Equalizer & Audio Effects
  Future<void> setEqualizerEnabled(bool enabled) async {
    emit(state.copyWith(isEqEnabled: enabled));
    await _audioHandler.setEqualizerEnabled(enabled);
  }

  Future<void> applyPreset(EqPreset preset) async {
    emit(state.copyWith(
      isEqEnabled: true,
      eqPreset: preset,
      selectedHeadphoneProfile: null,
    ));
    await _audioHandler.setEqualizerEnabled(true);
    await _audioHandler.applyPreset(preset);
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {
    if (profile != null) {
      emit(state.copyWith(
        isEqEnabled: true,
        eqPreset: EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        ),
        selectedHeadphoneProfile: profile,
      ));
      await _audioHandler.setEqualizerEnabled(true);
    } else {
      emit(state.copyWith(selectedHeadphoneProfile: null));
    }
    await _audioHandler.applyHeadphoneProfile(profile);
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      gains[bandIndex] = gain;
      emit(state.copyWith(
        eqPreset: EqPreset(name: 'Custom', gains: gains, bassBoost: state.eqPreset.bassBoost),
        selectedHeadphoneProfile: null,
      ));
    }
    await _audioHandler.setBandGain(bandIndex, gain);
  }

  Future<void> setBassBoost(double amount) async {
    emit(state.copyWith(
      eqPreset: EqPreset(name: state.eqPreset.name, gains: state.eqPreset.gains, bassBoost: amount),
    ));
    await _audioHandler.setBassBoost(amount);
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    emit(state.copyWith(isVirtualizerEnabled: enabled));
    await _audioHandler.setVirtualizerEnabled(enabled);
  }

  Future<void> setVirtualizerStrength(double strength) async {
    emit(state.copyWith(virtualizerStrength: strength));
    await _audioHandler.setVirtualizerStrength(strength);
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    final isEnabled = enabled ?? (preset != DynamicsPreset.off);
    emit(state.copyWith(
      dynamicsPreset: preset,
      isDynamicsEnabled: isEnabled,
    ));
    await _audioHandler.setDynamicsPreset(preset, enabled: enabled);
  }

  Future<void> setVolumeBoost(double value) async {
    emit(state.copyWith(volumeBoost: value));
    await _audioHandler.setVolumeBoost(value);
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    await _audioHandler.setSpatializerEnabled(enabled);
    emit(state.copyWith(isSpatializerEnabled: enabled));
  }

  // Sleep Timer
  void startSleepTimer(int minutes) {
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    emit(state.copyWith(sleepTimerRemaining: duration));
  }

  void startAbsoluteSleepTimer(DateTime stopTime) {
    _audioHandler.startAbsoluteSleepTimer(stopTime);
    final diff = stopTime.difference(DateTime.now());
    emit(state.copyWith(sleepTimerRemaining: diff.isNegative ? diff + const Duration(days: 1) : diff));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    emit(state.copyWith(sleepTimerRemaining: null));
  }

  // Playback Speed
  Future<void> _loadPlaybackSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speed = prefs.getDouble('playback_speed') ?? 1.0;
      await _audioHandler.setSpeed(speed);
      emit(state.copyWith(playbackSpeed: speed));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback speed from SharedPreferences', error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _audioHandler.setSpeed(speed);
    emit(state.copyWith(playbackSpeed: speed));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', speed);
  }

  // Volume Control
  Future<void> setVolume(double volume) async {
    await _audioHandler.setVolume(volume);
  }

  Future<void> adjustVolume(double delta) async {
    final current = _audioHandler.volume;
    final target = (current + delta).clamp(0.0, 1.0);
    await _audioHandler.setVolume(target);
  }

  // Overlay toggles (Lyrics / Queue)
  void toggleLyricsVisibility() {
    emit(state.copyWith(
      isLyricsVisible: !state.isLyricsVisible,
      isQueueVisible: false,
    ));
  }

  void toggleQueueVisibility() {
    emit(state.copyWith(
      isQueueVisible: !state.isQueueVisible,
      isLyricsVisible: false,
    ));
  }

  @override
  Future<void> close() {
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();
    _positionSub?.cancel();
    _settingsSub?.cancel();
    _widgetClickSub?.cancel();
    _sleepTimerSub?.cancel();
    return super.close();
  }
}
