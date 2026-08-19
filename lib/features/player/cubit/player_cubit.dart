// lib/features/player/cubit/player_cubit.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/lrc_parser.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repositories/music_repository.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../widgets/widget_service.dart';
import 'player_state.dart';

@injectable
class PlayerCubit extends Cubit<PlayerState> {
  final PulsrAudioHandler _audioHandler;
  final MusicRepository _repository;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final SettingsCubit? _settingsCubit;
  final WidgetService? _widgetService;

  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;
  StreamSubscription? _settingsSub;
  StreamSubscription? _widgetClickSub;

  final Map<int, List<SongsTableData>> _queueSlots = {0: [], 1: [], 2: []};

  PlayerCubit({
    required PulsrAudioHandler audioHandler,
    required MusicRepository repository,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    SettingsCubit? settingsCubit,
    WidgetService? widgetService,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _settingsCubit = settingsCubit,
        _widgetService = widgetService,
        super(const PlayerState()) {
    _listenToAudioService();
    _loadPlaybackSpeed();
    _listenToSettings();
    _listenToWidgetClicks();
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
      if (uri != null && uri.scheme == 'pulsrWidget') {
        switch (uri.host) {
          case 'play_pause':
            togglePlayPause();
            break;
          case 'prev':
            previous();
            break;
          case 'next':
            next();
            break;
        }
      }
    });
  }

  void _updateWidget() {
    _widgetService?.updateNowPlaying(
      song: state.currentSong,
      isPlaying: state.isPlaying,
    );
  }

  void _listenToAudioService() {
    _mediaItemSub = _audioHandler.mediaItem.listen((item) async {
      if (item != null) {
        final id = int.tryParse(item.id);
        if (id != null) {
          final songsResult = await _repository.getAllSongs();
          songsResult.fold(
            (failure) => emit(state.copyWith(errorMessage: failure.message)),
            (songs) {
              final song = songs.where((s) => s.id == id).firstOrNull;
              if (song != null) {
                emit(
                  state.copyWith(
                    currentSong: song,
                    duration: Duration(milliseconds: song.durationMs),
                    errorMessage: null,
                  ),
                );
                _loadLyricsForSong(song);
                _updateWidget();
              }
            },
          );
        }
      }
    });

    _playbackStateSub = _audioHandler.playbackState.listen((playbackState) {
      final repeat = switch (playbackState.repeatMode) {
        AudioServiceRepeatMode.one => PlayerRepeatMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => PlayerRepeatMode.all,
        _ => PlayerRepeatMode.off,
      };

      emit(
        state.copyWith(
          isPlaying: playbackState.playing,
          position: playbackState.position,
          isShuffle: playbackState.shuffleMode == AudioServiceShuffleMode.all,
          repeatMode: repeat,
          currentIndex: playbackState.queueIndex ?? state.currentIndex,
          playbackSpeed: playbackState.speed,
        ),
      );
      _updateWidget();
    });
  }

  Future<void> _loadLyricsForSong(SongsTableData song) async {
    if (isClosed) return;
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

  Future<void> playSong(SongsTableData song, {List<SongsTableData>? queue}) async {
    final effectiveQueue = queue ?? [song];
    final index = effectiveQueue.indexWhere((s) => s.id == song.id);
    _queueSlots[state.activeQueueSlot] = List.from(effectiveQueue);
    emit(state.copyWith(
      queue: effectiveQueue,
      currentIndex: index != -1 ? index : 0,
      currentSong: song,
      duration: Duration(milliseconds: song.durationMs),
    ));
    await _audioHandler.loadQueue(
      effectiveQueue,
      initialIndex: index != -1 ? index : 0,
      initialPosition: Duration(milliseconds: song.lastPositionMs),
    );
    _loadLyricsForSong(song);
    _updateWidget();
  }

  Future<void> playNext(SongsTableData song) async {
    await _audioHandler.playNext(song);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final insertIdx = (state.currentIndex + 1).clamp(0, updatedQueue.length);
    updatedQueue.insert(insertIdx, song);
    _queueSlots[state.activeQueueSlot] = updatedQueue;
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    await _audioHandler.addToQueue(song);
    final updatedQueue = List<SongsTableData>.from(state.queue)..add(song);
    _queueSlots[state.activeQueueSlot] = updatedQueue;
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _audioHandler.reorderQueue(oldIndex, newIndex);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    if (oldIndex < newIndex) newIndex -= 1;
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);
    _queueSlots[state.activeQueueSlot] = updatedQueue;
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> removeQueueItem(int index) async {
    await _audioHandler.removeQueueItemAt(index);
    final updatedQueue = List<SongsTableData>.from(state.queue)..removeAt(index);
    _queueSlots[state.activeQueueSlot] = updatedQueue;
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> switchQueueSlot(int slot) async {
    if (slot == state.activeQueueSlot || slot < 0 || slot > 2) return;
    _queueSlots[state.activeQueueSlot] = List.from(state.queue);
    final nextQueue = _queueSlots[slot] ?? [];
    emit(state.copyWith(activeQueueSlot: slot, queue: nextQueue));
    if (nextQueue.isNotEmpty) {
      await playSong(nextQueue.first, queue: nextQueue);
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

  Future<void> adjustVolume(double delta) async {
    final current = _audioHandler.volume;
    final newVol = (current + delta).clamp(0.0, 1.0);
    await _audioHandler.setVolume(newVol);
  }

  Future<void> setVolume(double volume) async {
    await _audioHandler.setVolume(volume.clamp(0.0, 1.0));
  }

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
        }
      },
    );
  }

  // Equalizer & Audio Effects
  Future<void> setEqualizerEnabled(bool enabled) async {
    await _audioHandler.setEqualizerEnabled(enabled);
    emit(state.copyWith(isEqEnabled: enabled));
  }

  Future<void> applyPreset(EqPreset preset) async {
    await _audioHandler.applyPreset(preset);
    emit(state.copyWith(eqPreset: preset));
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    await _audioHandler.setBandGain(bandIndex, gain);
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      gains[bandIndex] = gain;
      emit(state.copyWith(eqPreset: EqPreset(name: 'Custom', gains: gains, bassBoost: state.eqPreset.bassBoost)));
    }
  }

  Future<void> setBassBoost(double amount) async {
    await _audioHandler.setBassBoost(amount);
    emit(state.copyWith(
      eqPreset: EqPreset(name: state.eqPreset.name, gains: state.eqPreset.gains, bassBoost: amount),
    ));
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
    } catch (_) {}
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _audioHandler.setSpeed(speed);
    emit(state.copyWith(playbackSpeed: speed));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', speed);
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
    _settingsSub?.cancel();
    _widgetClickSub?.cancel();
    return super.close();
  }
}
