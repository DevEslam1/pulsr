import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/prefs_keys.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/lrclib_service.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/lrc_parser.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/equalizer_manager.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
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
  final double speed;

  const _QueueSlotData({
    required this.songs,
    required this.currentIndex,
    required this.position,
    this.speed = 1.0,
  });
}

@singleton
class PlayerCubit extends Cubit<PlayerState> {
  static const int _maxQueueSize = 500;
  static const Duration _scrobbleInterval = Duration(seconds: 5);

  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final SettingsCubit? _settingsCubit;
  final WidgetService? _widgetService;
  final ScrobblerService? _scrobblerService;

  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _queueSub;
  StreamSubscription? _settingsSub;
  StreamSubscription? _widgetClickSub;
  StreamSubscription? _sleepTimerSub;
  StreamSubscription? _audioSessionIdSub;
  StreamSubscription? _errorSub;
  DateTime? _lastWidgetUpdateTime;
  int _mediaItemResolutionGen = 0;

  Timer? _persistQueueDebounce;
  Timer? _scrobbleDebounce;
  int? _lastScrobbleSongId;
  bool? _lastScrobbleIsPlaying;
  int? _lastScrobblePosSec;
  List<String>? _cachedNextTitles;
  int? _cachedNextTitlesIndex;
  int? _cachedQueueLength;
  int? _cachedCurrentSongId;

  final Map<int, _QueueSlotData> _queueSlots = {
    0: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
    1: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
    2: const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
  };
  bool _queueRestorationDone = false;

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
    _restoreQueueSlots();
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
      isCrossfeedEnabled: _audioHandler.isCrossfeedEnabled,
      crossfeedDelayUs: _audioHandler.crossfeedDelayUs,
      crossfeedFeedDb: _audioHandler.crossfeedFeedDb,
      isLimiterEnabled: _audioHandler.isLimiterEnabled,
      limiterThresholdDb: _audioHandler.limiterThresholdDb,
      limiterReleaseMs: _audioHandler.limiterReleaseMs,
      isReverbEnabled: _audioHandler.isReverbEnabled,
      reverbPreset: _audioHandler.reverbPreset,
      reverbWetDry: _audioHandler.reverbWetDry,
      stereoBalance: _audioHandler.stereoBalance,
      monoMix: _audioHandler.monoMix,
      isSincResamplerEnabled: _audioHandler.isSincResamplerEnabled,
      hasOemAudio: _audioHandler.hasOemAudio,
      detectedOemEngines: _audioHandler.detectedOemEngines,
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
      _settingsSub = settingsCubit.stream.listen((settingsState) {
        _audioHandler.setCrossfadeDuration(
          Duration(milliseconds: (settingsState.crossfadeSeconds * 1000).round()),
        );
        // Re-apply gain when ReplayGain settings change
        _audioHandler.setVolume(_audioHandler.volume);
      });
    }
  }

  void _debouncedPersistQueueSlots() {
    _persistQueueDebounce?.cancel();
    _persistQueueDebounce = Timer(const Duration(seconds: 2), () {
      _persistQueueSlots();
    });
  }

  Future<void> _persistQueueSlots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};
      for (final entry in _queueSlots.entries) {
        data['${entry.key}'] = {
          'songIds': entry.value.songs.map((s) => s.id).toList(),
          'currentIndex': entry.value.currentIndex,
          'positionMs': entry.value.position.inMilliseconds,
          'speed': entry.value.speed,
        };
      }
      await prefs.setString(PrefsKeys.queueSlots, jsonEncode(data));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist queue slots',
          error: e, stackTrace: st, category: 'PlayerCubit');
      emit(state.copyWith(errorMessage: 'Failed to save queue'));
    }
  }

  Future<void> _restoreQueueSlots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queueRestorationDone) return;
      final raw = prefs.getString(PrefsKeys.queueSlots);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded;
      for (final key in data.keys) {
        if (_queueRestorationDone) return;
        final slotIndex = int.tryParse(key);
        if (slotIndex == null || slotIndex < 0 || slotIndex > 2) continue;
        final slotData = data[key] as Map<String, dynamic>;
        final songIds =
            (slotData['songIds'] as List<dynamic>?)?.cast<int>() ?? [];
        if (songIds.isEmpty) continue;
        final songsResult = await _repository.getSongsByIds(songIds);
        if (_queueRestorationDone) return;
        final songs = songsResult.fold((_) => <SongsTableData>[], (r) => r);
        if (songs.isEmpty) continue;
        _queueSlots[slotIndex] = _QueueSlotData(
          songs: songs,
          currentIndex: ((slotData['currentIndex'] as int?) ?? 0)
              .clamp(0, songs.length - 1),
          position:
              Duration(milliseconds: (slotData['positionMs'] as int?) ?? 0),
          speed: (slotData['speed'] as num?)?.toDouble() ?? 1.0,
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore queue slots',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  void _debouncedScrobble(
      SongsTableData song, Duration position, bool isPlaying) {
    if (isClosed) return;
    final posSec = position.inSeconds;
    final isSongChange = _lastScrobbleSongId != song.id;
    final isPlayStateChange = _lastScrobbleIsPlaying != isPlaying;
    final isMajorSeek = _lastScrobblePosSec != null &&
        (posSec - _lastScrobblePosSec!).abs() >= 5;

    // Always update tracking state
    _lastScrobbleSongId = song.id;
    _lastScrobbleIsPlaying = isPlaying;
    _lastScrobblePosSec = posSec;

    if (isSongChange || isPlayStateChange || isMajorSeek) {
      // Major update: immediate flush + reset timer
      _scrobbleDebounce?.cancel();
      _scrobbleDebounce = null;
      _scrobblerService?.notifyPlaybackState(
        id: song.id,
        artist: song.artist,
        track: song.title,
        album: song.album,
        durationMs: song.durationMs,
        positionMs: position.inMilliseconds,
        isPlaying: isPlaying,
      );
      return;
    }

    // Minor progress tick: schedule debounced flush
    _scrobbleDebounce ??= Timer(_scrobbleInterval, () {
      if (isClosed) return;
      _scrobblerService?.notifyPlaybackState(
        id: song.id,
        artist: song.artist,
        track: song.title,
        album: song.album,
        durationMs: song.durationMs,
        positionMs: position.inMilliseconds,
        isPlaying: isPlaying,
      );
      _scrobbleDebounce = null;
    });
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

  List<String>? _getNextTitles(PlayerState s) {
    if (s.queue.isEmpty || s.currentIndex + 1 >= s.queue.length) {
      _cachedNextTitles = null;
      _cachedNextTitlesIndex = null;
      _cachedQueueLength = 0;
      _cachedCurrentSongId = null;
      return null;
    }
    if (_cachedNextTitlesIndex == s.currentIndex &&
        _cachedQueueLength == s.queue.length &&
        _cachedCurrentSongId == s.currentSong?.id) {
      return _cachedNextTitles;
    }
    _cachedNextTitlesIndex = s.currentIndex;
    _cachedQueueLength = s.queue.length;
    _cachedCurrentSongId = s.currentSong?.id;
    _cachedNextTitles = s.queue
        .skip(s.currentIndex + 1)
        .take(3)
        .map((item) => item.artist.isNotEmpty && item.artist != 'Unknown Artist'
            ? '${item.title} • ${item.artist}'
            : item.title)
        .toList();
    return _cachedNextTitles;
  }

  void _updateWidgetThrottled({bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastWidgetUpdateTime != null && now.difference(_lastWidgetUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastWidgetUpdateTime = now;
    final nextTitles = _getNextTitles(state);
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
      nextQueueTitles: nextTitles,
    );
  }

  void _listenToAudioService() {
    _mediaItemSub = _audioHandler.mediaItem.listen((item) async {
      if (item != null) {
        final gen = ++_mediaItemResolutionGen;
        final id = int.tryParse(item.id);
        if (id != null) {
          SongsTableData? resolvedSong;
          final songResult = await _repository.getSongById(id);
          if (gen != _mediaItemResolutionGen || isClosed) return;
          songResult.fold((_) => null, (song) => resolvedSong = song);

          // Crucial fallback for in-memory online tracks (negative IDs) or newly queued songs
          resolvedSong ??= _audioHandler.currentSong?.id == id
              ? _audioHandler.currentSong
              : state.queue.where((s) => s.id == id).firstOrNull;

          // Check all queue slots if not found in active queue
          if (resolvedSong == null) {
            for (final slot in _queueSlots.values) {
              resolvedSong = slot.songs.where((s) => s.id == id).firstOrNull;
              if (resolvedSong != null) break;
            }
          }

          // Final fallback — construct from MediaItem extras
          if (resolvedSong == null && item.id.isNotEmpty) {
            resolvedSong = SongsTableData(
              id: id,
              title: item.title,
              artist: item.artist ?? 'Unknown',
              album: item.album ?? '',
              durationMs: item.duration?.inMilliseconds ?? 0,
              path: (item.extras?['path'] as String?) ?? '',
              source: SongSource.youtube,
              remoteId: item.extras?['remoteId'] as String?,
              remoteArtworkUrl: item.artUri?.toString(),
              isFavorite: false,
              isMissing: false,
              isDownloaded: false,
              playCount: 0,
              lastPositionMs: 0,
            );
          }

          if (resolvedSong != null) {
            if (gen != _mediaItemResolutionGen || isClosed) return;
            final duration = (item.duration != null && item.duration! > Duration.zero)
                ? item.duration!
                : (resolvedSong!.durationMs > 0
                    ? Duration(milliseconds: resolvedSong!.durationMs)
                    : state.duration);
            final isSameSong = state.currentSong?.id == resolvedSong!.id;

            emit(
              state.copyWith(
                currentSong: resolvedSong,
                duration: duration,
                errorMessage: null,
              ),
            );

            if (gen != _mediaItemResolutionGen || isClosed) return;

            if (!isSameSong) {
              _loadLyricsForSong(resolvedSong!);
              _enrichAudioQuality(resolvedSong!, gen);
            }
            if (gen != _mediaItemResolutionGen || isClosed) return;
            _updateWidgetThrottled(force: true);
            _debouncedScrobble(resolvedSong!, state.position, state.isPlaying);
          }
        }
      }
    });

    _errorSub = _audioHandler.errorStream.listen((err) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: err));
      }
    });

    _queueSub = _audioHandler.queue.listen((mediaItems) async {
      if (mediaItems.isNotEmpty && (state.queue.isEmpty || state.queue.length != mediaItems.length)) {
        final ids = mediaItems.map((m) => int.tryParse(m.id)).whereType<int>().toList();
        final songsRes = await _repository.getSongsByIds(ids);
        final songsMap = {
          for (final s in songsRes.fold((_) => <SongsTableData>[], (r) => r)) s.id: s
        };
        final restoredSongs = <SongsTableData>[];
        for (final m in mediaItems) {
          final mid = int.tryParse(m.id);
          if (mid != null && songsMap.containsKey(mid)) {
            restoredSongs.add(songsMap[mid]!);
          } else if (mid != null) {
            restoredSongs.add(SongsTableData(
              id: mid,
              title: m.title,
              artist: m.artist ?? 'Unknown',
              album: m.album ?? '',
              durationMs: m.duration?.inMilliseconds ?? 0,
              path: (m.extras?['path'] as String?) ?? '',
              source: SongSource.youtube,
              remoteId: m.extras?['remoteId'] as String?,
              remoteArtworkUrl: m.artUri?.toString(),
              isFavorite: false,
              isMissing: false,
              isDownloaded: false,
              playCount: 0,
              lastPositionMs: 0,
            ));
          }
        }
        if (restoredSongs.isNotEmpty && !isClosed) {
          emit(state.copyWith(queue: restoredSongs));
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
      final effectivePos = isCompleted
          ? Duration.zero
          : (playbackState.position > Duration.zero
              ? playbackState.position
              : (state.position > Duration.zero ? state.position : playbackState.position));

      emit(
        state.copyWith(
          isPlaying: isPlaying,
          position: effectivePos,
          isShuffle: playbackState.shuffleMode == AudioServiceShuffleMode.all,
          repeatMode: repeat,
          currentIndex: playbackState.queueIndex ?? state.currentIndex,
          playbackSpeed: playbackState.speed,
        ),
      );
      _updateWidgetThrottled(force: false);
      final currentSong = state.currentSong;
      if (currentSong != null) {
        _debouncedScrobble(currentSong, effectivePos, isPlaying);
      }
    });

    _positionSub = _audioHandler.positionStream.listen((pos) {
      emit(state.copyWith(position: pos));
      if (state.isPlaying) {
        _updateWidgetThrottled(force: false);
      }
    });

    _sleepTimerSub = _audioHandler.sleepTimerRemainingStream.listen((remaining) {
      emit(state.copyWith(sleepTimerRemaining: remaining));
    });

    if (_audioHandler.currentAudioSessionId != null) {
      emit(state.copyWith(audioSessionId: _audioHandler.currentAudioSessionId));
    }
    _audioSessionIdSub = _audioHandler.audioSessionIdStream.listen((id) {
      emit(state.copyWith(audioSessionId: id));
    });
  }

  /// Reads real audio-header fields for a local song the first time it plays
  /// and caches them, so the quality badge shows actual metadata. Cheap: runs
  /// once per file (skips songs already enriched) and only for local files.
  Future<void> _enrichAudioQuality(SongsTableData song, int gen) async {
    if (song.source != SongSource.local) return;
    if (song.codec != null) return;
    final path = song.path;
    if (path.isEmpty || path.startsWith('http') || path.startsWith('ytmusic://')) {
      return;
    }
    try {
      await getIt<MediaScannerService>().enrichAudioQuality(song.id, path);
      if (isClosed || gen != _mediaItemResolutionGen) return;
      final refreshed = await _repository.getSongById(song.id);
      final updated = refreshed.fold((_) => null, (s) => s);
      if (updated != null && !isClosed && gen == _mediaItemResolutionGen && state.currentSong?.id == updated.id) {
        emit(state.copyWith(currentSong: updated));
      }
    } catch (_) {}
  }

  Future<void> _loadLyricsForSong(SongsTableData song) async {
    if (isClosed) return;
    emit(state.copyWith(
      isLoadingLyrics: true,
      lyrics: [],
      lyricsSource: LyricsSource.none,
    ));

    LyricsResult? lyricsResult;

    // 1. For local files, check embedded metadata and sidecar .lrc files
    if (song.source == SongSource.local && !song.path.startsWith('http') && !song.path.startsWith('ytmusic://')) {
      lyricsResult = await LrcParser.resolveLyrics(song.path, songId: song.id);
    }

    if (isClosed || state.currentSong?.id != song.id) return;

    // 2. Query LRCLIB for synchronized karaoke lyrics (works for local and online tracks)
    if (lyricsResult == null || lyricsResult.lines.isEmpty) {
      try {
        final lrclib = getIt<LrclibService>();
        lyricsResult = await lrclib.fetchLyrics(
          trackName: song.title,
          artistName: song.artist,
          albumName: song.album,
          durationSeconds: song.durationMs > 0 ? song.durationMs ~/ 1000 : null,
        );
      } catch (_) {}
    }

    if (isClosed || state.currentSong?.id != song.id) return;

    // 3. For YouTube Music tracks without LRCLIB matches, fetch native YTM lyrics
    final videoId = song.remoteId;
    if ((lyricsResult == null || lyricsResult.lines.isEmpty) && videoId != null && videoId.isNotEmpty) {
      try {
        final ytmAccount = getIt<YtmAccountService>();
        lyricsResult = await ytmAccount.fetchYtmLyrics(videoId);
      } catch (_) {}
    }

    if (isClosed || state.currentSong?.id != song.id) return;
    emit(state.copyWith(
      isLoadingLyrics: false,
      lyrics: lyricsResult?.lines ?? [],
      lyricsSource: lyricsResult?.source ?? LyricsSource.none,
    ));
  }

  Future<void> playSong(SongsTableData song, {List<SongsTableData>? queue, Duration? initialPosition}) async {
    ++_mediaItemResolutionGen;
    final capturedGen = _mediaItemResolutionGen;
    // Mark restoration as done: any in-flight _restoreQueueSlots must abort
    _queueRestorationDone = true;
    // If playing an online song that has already been downloaded to the device, swap to local song
    SongsTableData targetSong = song;
    if (song.source == SongSource.youtube) {
      try {
        final match = await _repository.findMatchingLocalSong(
          remoteId: song.remoteId,
          title: song.title,
          artist: song.artist,
        );
        // Abort if a newer playSong call arrived while we were awaiting
        if (_mediaItemResolutionGen != capturedGen) return;
        final local = match.fold((_) => null, (s) => s);
        if (local != null && (local.path.startsWith('content:') || await File(local.path).exists())) {
          targetSong = local;
        }
      } catch (_) {}
    }

    var rawQueue = queue != null ? List<SongsTableData>.from(queue) : [targetSong];
    if (targetSong.id != song.id) {
      rawQueue = rawQueue.map((s) => s.id == song.id ? targetSong : s).toList();
    }

    var targetIndex = rawQueue.indexWhere((s) => s.id == targetSong.id);
    if (targetIndex == -1) {
      targetIndex = 0;
      rawQueue.insert(0, targetSong);
    }

    List<SongsTableData> effectiveQueue;
    int effectiveIndex;

    if (rawQueue.length > _maxQueueSize) {
      // Center the 500-song window around the target song
      final halfWindow = _maxQueueSize ~/ 2;
      var start = targetIndex - halfWindow;
      if (start < 0) start = 0;
      if (start + _maxQueueSize > rawQueue.length) {
        start = (rawQueue.length - _maxQueueSize).clamp(0, rawQueue.length);
      }
      effectiveQueue = rawQueue.sublist(start, start + _maxQueueSize);
      effectiveIndex = targetIndex - start;
    } else {
      effectiveQueue = rawQueue;
      effectiveIndex = targetIndex;
    }

    final startPos = initialPosition ?? Duration.zero;
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: List.from(effectiveQueue),
      currentIndex: effectiveIndex,
      position: startPos,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();

    emit(state.copyWith(
      queue: effectiveQueue,
      currentIndex: effectiveIndex,
      currentSong: targetSong,
      position: startPos,
      duration: Duration(milliseconds: targetSong.durationMs),
      errorMessage: null,
    ));
    await _audioHandler.loadQueue(
      effectiveQueue,
      initialIndex: effectiveIndex,
      initialPosition: startPos,
    );
    _loadLyricsForSong(targetSong);
    _updateWidgetThrottled(force: true);
  }

  Future<void> playNext(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($_maxQueueSize)', category: 'PlayerCubit');
      return;
    }
    await _audioHandler.insertNextInQueue(song);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    final insertIdx = (state.currentIndex + 1).clamp(0, updatedQueue.length);
    updatedQueue.insert(insertIdx, song);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($_maxQueueSize)', category: 'PlayerCubit');
      return;
    }
    await _audioHandler.addToQueueEnd(song);
    final updatedQueue = List<SongsTableData>.from(state.queue)..add(song);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
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
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    emit(state.copyWith(queue: updatedQueue));
  }

  Future<void> removeQueueItem(int index) async {
    await _audioHandler.removeQueueItemAt(index);
    final updatedQueue = List<SongsTableData>.from(state.queue)..removeAt(index);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    emit(state.copyWith(queue: updatedQueue));
  }

  bool _isSwitchingSlot = false;

  Future<void> switchQueueSlot(int slot) async {
    if (_isSwitchingSlot || slot == state.activeQueueSlot || slot < 0 || slot > 2) return;
    _isSwitchingSlot = true;
    try {
      final wasPlaying = state.isPlaying;
      _queueSlots[state.activeQueueSlot] = _QueueSlotData(
        songs: List.from(state.queue),
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      final targetSlot = _queueSlots[slot] ?? const _QueueSlotData(songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0);
      final validSongs = targetSlot.songs.where((s) => !s.isMissing).toList();

      _debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        emit(state.copyWith(
          activeQueueSlot: slot,
          queue: [],
          errorMessage: 'Queue slot is empty',
        ));
        return;
      }

      emit(state.copyWith(activeQueueSlot: slot, queue: validSongs));

      final safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      final song = validSongs[safeIdx];
      emit(state.copyWith(
        currentIndex: safeIdx,
        currentSong: song,
        duration: Duration(milliseconds: song.durationMs),
        position: targetSlot.position,
        playbackSpeed: targetSlot.speed,
      ));
      await _audioHandler.setSpeed(targetSlot.speed);
      await _audioHandler.loadQueue(
        validSongs,
        initialIndex: safeIdx,
        initialPosition: targetSlot.position,
      );
      if (!wasPlaying) {
        await _audioHandler.pause();
        emit(state.copyWith(isPlaying: false));
      }
      _loadLyricsForSong(song);
    } finally {
      _isSwitchingSlot = false;
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
        speed: data.speed,
      );
    });
    _debouncedPersistQueueSlots();

    if (state.queue.any((s) => s.id == oldId)) {
      emit(state.copyWith(
        queue: state.queue.map((s) => s.id == oldId ? newSong : s).toList(),
        currentSong: state.currentSong?.id == oldId ? newSong : state.currentSong,
      ));
      _updateWidgetThrottled(force: true);
    }

    try {
      _audioHandler.swapReconciledSong(oldId, newSong);
    } catch (_) {}
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
      emit(state.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ));
    }
    await _audioHandler.applyHeadphoneProfile(profile);
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    final clamped = gain.clamp(-15.0, 15.0);
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      final hadProfile = state.selectedHeadphoneProfile != null;
      gains[bandIndex] = clamped;
      emit(state.copyWith(
        eqPreset: EqPreset(
          name: 'Custom',
          gains: gains,
          bassBoost: hadProfile ? 0.0 : state.eqPreset.bassBoost,
        ),
        selectedHeadphoneProfile: null,
      ));
    }
    await _audioHandler.setBandGain(bandIndex, clamped);
  }

  Future<void> resetToFlat() async {
    emit(state.copyWith(
      eqPreset: EqPreset.defaultPresets.first,
      selectedHeadphoneProfile: null,
    ));
    await _audioHandler.resetToFlat();
  }

  Future<void> startAbComparison() async {
    await _audioHandler.startAbComparison();
  }

  Future<void> endAbComparison() async {
    await _audioHandler.endAbComparison();
  }

  Future<void> setBassBoost(double amount) async {
    final clamped = amount.clamp(0.0, 1.0);
    emit(state.copyWith(
      eqPreset: EqPreset(name: state.eqPreset.name, gains: state.eqPreset.gains, bassBoost: clamped),
    ));
    await _audioHandler.setBassBoost(clamped);
  }

  Future<void> set32BandMode(bool enabled) async {
    await _audioHandler.set32BandMode(enabled);
    emit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    await _audioHandler.switchComparisonSlot(slot);
    emit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  String exportPresetToJson() => _audioHandler.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) async {
    final ok = await _audioHandler.importPresetFromJson(jsonStr);
    if (ok) {
      emit(state.copyWith(
        eqPreset: _audioHandler.currentPreset,
      ));
    }
    return ok;
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

  Future<void> toggleDynamicsBypass() async {
    await _audioHandler.toggleDynamicsBypass();
    emit(state.copyWith(
      isDynamicsEnabled: !_audioHandler.isDynamicsBypassed && state.dynamicsPreset != DynamicsPreset.off,
    ));
  }

  Future<void> setVolumeBoost(double value) async {
    // Gain staging: cap if combined with preamp > 6 dB
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    }
    emit(state.copyWith(volumeBoost: safeValue));
    await _audioHandler.setVolumeBoost(safeValue);
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    await _audioHandler.setSpatializerEnabled(enabled);
    emit(state.copyWith(isSpatializerEnabled: enabled));
  }

  // --- NATIVE DSP METHODS ---

  Future<void> setCrossfeed(bool enabled, {double? delayUs, double? feedDb}) async {
    emit(state.copyWith(
      isCrossfeedEnabled: enabled,
      crossfeedDelayUs: delayUs ?? state.crossfeedDelayUs,
      crossfeedFeedDb: feedDb ?? state.crossfeedFeedDb,
    ));
    await _audioHandler.setCrossfeed(enabled, delayUs: delayUs, feedDb: feedDb);
  }

  Future<void> setLookaheadLimiter(bool enabled, {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    emit(state.copyWith(
      isLimiterEnabled: enabled,
      limiterThresholdDb: thresholdDb ?? state.limiterThresholdDb,
      limiterReleaseMs: releaseMs ?? state.limiterReleaseMs,
    ));
    await _audioHandler.setLookaheadLimiter(enabled, thresholdDb: thresholdDb, releaseMs: releaseMs, lookaheadMs: lookaheadMs);
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    emit(state.copyWith(
      isReverbEnabled: enabled,
      reverbPreset: preset ?? state.reverbPreset,
      reverbWetDry: wetDry ?? state.reverbWetDry,
    ));
    await _audioHandler.setReverb(enabled, preset: preset, wetDry: wetDry);
  }

  Future<void> loadCustomImpulseResponse(List<double> irSamples) async {
    emit(state.copyWith(
      isReverbEnabled: true,
      reverbPreset: 4, // Custom
    ));
    await _audioHandler.loadCustomImpulseResponse(irSamples);
  }

  Future<void> setStereoBalance(double balance) async {
    final clamped = balance.clamp(-1.0, 1.0);
    emit(state.copyWith(stereoBalance: clamped));
    await _audioHandler.setStereoBalance(clamped);
  }

  Future<void> setMonoMix(bool mono) async {
    emit(state.copyWith(monoMix: mono));
    await _audioHandler.setMonoMix(mono);
  }

  Future<void> setSincResampler(bool enabled) async {
    emit(state.copyWith(isSincResamplerEnabled: enabled));
    await _audioHandler.setSincResampler(enabled);
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
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: state.queue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: speed,
    );
    _debouncedPersistQueueSlots();
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
    _persistQueueDebounce?.cancel();
    _scrobbleDebounce?.cancel();
    _mediaItemSub?.cancel();
    _queueSub?.cancel();
    _errorSub?.cancel();
    _playbackStateSub?.cancel();
    _positionSub?.cancel();
    _settingsSub?.cancel();
    _widgetClickSub?.cancel();
    _sleepTimerSub?.cancel();
    _audioSessionIdSub?.cancel();
    return super.close();
  }
}
