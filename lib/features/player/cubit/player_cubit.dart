import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/constants/prefs_keys.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/lrclib_service.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/telemetry/playback_latency_tracker.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/lrc_parser.dart';
import '../../../core/constants/audio_feature_info.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/equalizer_manager.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../domain/models/reverb_preset.dart';
import '../../../data/audio/headphone_profiles_repository.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../core/services/device_profile_service.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/settings_profiles_service.dart';
import '../../../domain/models/audio_output_info.dart';
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
class PlayerCubit extends PulsrCubit<PlayerState> {
  static const int _maxQueueSize = 500;
  static const Duration _scrobbleInterval = Duration(seconds: 5);

  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final ToggleFavoriteUseCase _toggleFavoriteUseCase;
  final SettingsCubit? _settingsCubit;
  final WidgetService? _widgetService;
  final ScrobblerService? _scrobblerService;
  final PlaybackLatencyTracker? _latencyTracker;
  final SettingsProfilesService? _settingsProfilesService;
  final DeviceProfileService? _deviceProfileService;
  final HiResAudioService? _hiResAudioService;
  String? _lastAutoAppliedDeviceKey;

  // FIX(BUG-14): Expose unthrottled position stream for high-fps UI components like MiniPlayer
  Stream<Duration> get rawPositionStream => _audioHandler.positionStream;

  StreamSubscription<void>? _widgetClickSub;
  DateTime? _lastWidgetUpdateTime;
  int _mediaItemResolutionGen = 0;

  Timer? _persistQueueDebounce;
  Timer? _scrobbleDebounce;
  int? _lastScrobbleSongId;
  bool? _lastScrobbleIsPlaying;
  // FIX(BUG-15): Track position in milliseconds to avoid precision loss on sub-second seeks
  int? _lastScrobblePosMs;
  List<String>? _cachedNextTitles;
  int? _cachedNextTitlesIndex;
  int? _cachedQueueLength;
  int? _cachedCurrentSongId;

  final Map<int, _QueueSlotData> _queueSlots = {
    0: const _QueueSlotData(
        songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
    1: const _QueueSlotData(
        songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
    2: const _QueueSlotData(
        songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0),
  };
  bool _queueRestorationDone = false;

  PlayerCubit({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    SettingsCubit? settingsCubit,
    WidgetService? widgetService,
    ScrobblerService? scrobblerService,
    SettingsProfilesService? settingsProfilesService,
    DeviceProfileService? deviceProfileService,
    HiResAudioService? hiResAudioService,
    PlaybackLatencyTracker? latencyTracker,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _toggleFavoriteUseCase = toggleFavoriteUseCase,
        _settingsCubit = settingsCubit,
        _widgetService = widgetService,
        _scrobblerService = scrobblerService,
        _settingsProfilesService = settingsProfilesService ??
            (getIt.isRegistered<SettingsProfilesService>()
                ? getIt<SettingsProfilesService>()
                : null),
        _deviceProfileService = deviceProfileService ??
            (getIt.isRegistered<DeviceProfileService>()
                ? getIt<DeviceProfileService>()
                : null),
        _hiResAudioService = hiResAudioService ??
            (getIt.isRegistered<HiResAudioService>()
                ? getIt<HiResAudioService>()
                : null),
        _latencyTracker = latencyTracker ??
            (getIt.isRegistered<PlaybackLatencyTracker>()
                ? getIt<PlaybackLatencyTracker>()
                : null),
        super(const PlayerState()) {
    _listenToAudioService();
    _loadPlaybackSpeed();
    _listenToSettings();
    _listenToWidgetClicks();
    _syncAudioEffects();
    // Re-sync effect state once the handler finishes its async init: the
    // sync above can race the preference restore and read pre-restore
    // defaults, leaving toggles showing OFF for saved-ON stages.
    _audioHandler.effectsReady.then((_) async {
      if (isClosed) return;
      _syncAudioEffects();
      // ReplayGain re-apply: with the fully restored session (song tags +
      // cached prefs) a restored 'on' gain mode must be actually audible,
      // not just displayed as enabled.
      await _audioHandler.setVolume(_audioHandler.volume);
    }).ignore();
    _restoreQueueSlots();
    _startDeviceProfileWatcher();
    _updateWidgetThrottled(force: true);
  }

  void _syncAudioEffects() {
    safeEmit(state.copyWith(
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
      isSaturationEnabled: _audioHandler.isSaturationEnabled,
      saturationDrive: _audioHandler.saturationDrive,
      saturationMix: _audioHandler.saturationMix,
      saturationTilt: _audioHandler.saturationTilt,
      isStereoWidthEnabled: _audioHandler.isStereoWidthEnabled,
      stereoWidth: _audioHandler.stereoWidth,
      isLoudnessContourEnabled: _audioHandler.isLoudnessContourEnabled,
      loudnessContourIntensity: _audioHandler.loudnessContourIntensity,
      isSubCrossoverEnabled: _audioHandler.isSubCrossoverEnabled,
      subCrossoverCornerHz: _audioHandler.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct: _audioHandler.subCrossoverSlopeDbPerOct,
      subCrossoverGain: _audioHandler.subCrossoverGain,
      isDynamicEqEnabled: _audioHandler.isDynamicEqEnabled,
      dynamicEqBands: _audioHandler.dynamicEqBands,
      hasOemAudio: _audioHandler.hasOemAudio,
      detectedOemEngines: _audioHandler.detectedOemEngines,
    ));
  }

  void clearError() {
    safeEmit(state.copyWith(errorMessage: null));
  }

  void _listenToSettings() {
    final settingsCubit = _settingsCubit;
    if (settingsCubit != null) {
      _audioHandler.setCrossfadeDuration(
        Duration(
            milliseconds:
                (settingsCubit.state.crossfadeSeconds * 1000).round()),
      );
      autoSub(settingsCubit.stream, (settingsState) {
        _audioHandler.setCrossfadeDuration(
          Duration(
              milliseconds: (settingsState.crossfadeSeconds * 1000).round()),
        );
        // Re-apply gain when ReplayGain settings change
        _audioHandler.setVolume(_audioHandler.volume);
      });
    }
  }

  void _debouncedPersistQueueSlots() {
    _persistQueueDebounce?.cancel();
    _persistQueueDebounce = autoTimer(Timer(const Duration(seconds: 2), () {
      _persistQueueSlots();
    }));
  }

  Future<void> _persistQueueSlots() async {
    if (isClosed) return;
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
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Failed to save queue'));
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
      // Validate: reject oversized slots (DoS)
      if (data.length > 3) return;
      for (final key in data.keys) {
        if (_queueRestorationDone) return;
        final slotIndex = int.tryParse(key);
        if (slotIndex == null || slotIndex < 0 || slotIndex > 2) continue;
        final slotData = data[key] as Map<String, dynamic>;
        final rawIds = (slotData['songIds'] as List<dynamic>?) ?? [];
        if (rawIds.length > _maxQueueSize) continue;
        final songIds = rawIds.whereType<int>().toList();
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
    final posMs = position.inMilliseconds;
    final isSongChange = _lastScrobbleSongId != song.id;
    final isPlayStateChange = _lastScrobbleIsPlaying != isPlaying;
    // FIX(BUG-15): Compare milliseconds (>= 5000 ms) instead of integer seconds
    final isMajorSeek = _lastScrobblePosMs != null &&
        (posMs - _lastScrobblePosMs!).abs() >= 5000;

    // Always update tracking state
    _lastScrobbleSongId = song.id;
    _lastScrobbleIsPlaying = isPlaying;
    _lastScrobblePosMs = posMs;

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
    _scrobbleDebounce ??= autoTimer(Timer(_scrobbleInterval, () {
      if (isClosed) return;
      _scrobblerService?.notifyPlaybackState(
        id: song.id,
        artist: song.artist,
        track: song.title,
        album: song.album,
        durationMs: song.durationMs,
        positionMs: state.position.inMilliseconds,
        isPlaying: state.isPlaying,
      );
      _scrobbleDebounce = null;
    }));
  }

  void _listenToWidgetClicks() {
    _widgetClickSub = _widgetService?.listenToWidgetClicks((uri) {
      if (uri != null && uri.scheme.toLowerCase() == 'pulsrwidget') {
        final action =
            uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
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
            safeEmit(state.copyWith(isExpanded: true));
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

  DateTime? _lastWidgetProgressUpdateTime;

  void _updateWidgetThrottled({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastWidgetUpdateTime != null &&
        now.difference(_lastWidgetUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastWidgetUpdateTime = now;
    _lastWidgetProgressUpdateTime = now;
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

  void _updateWidgetProgressThrottled() {
    final now = DateTime.now();
    if (_lastWidgetProgressUpdateTime != null &&
        now.difference(_lastWidgetProgressUpdateTime!).inMilliseconds < 1000) {
      return;
    }
    _lastWidgetProgressUpdateTime = now;
    _widgetService?.updateProgress(
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
    );
  }

  bool _isSameTrack(SongsTableData? a, SongsTableData? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.id == b.id) return true;
    if (a.remoteId != null &&
        b.remoteId != null &&
        a.remoteId!.isNotEmpty &&
        a.remoteId == b.remoteId) {
      return true;
    }
    if (a.path.isNotEmpty && a.path == b.path) return true;
    return false;
  }

  void _listenToAudioService() {
    autoSub(_audioHandler.onTrackChanged, (song) {
      if (isClosed) return;
      final gen = ++_mediaItemResolutionGen;
      final songQueueIndex =
          state.queue.indexWhere((s) => _isSameTrack(s, song));
      final effectiveIndex =
          songQueueIndex != -1 ? songQueueIndex : state.currentIndex;
      final isSameSong = _isSameTrack(state.currentSong, song);

      final duration = song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : state.duration;

      safeEmit(
        state.copyWith(
          currentSong: song,
          currentIndex: effectiveIndex,
          duration: duration,
          position: isSameSong ? state.position : Duration.zero,
          errorMessage: null,
        ),
      );

      if (!isSameSong) {
        unawaited(_loadLyricsForSong(song));
        unawaited(_enrichAudioQuality(song, gen));
      }
      _updateWidgetThrottled(force: true);
      _debouncedScrobble(song, state.position, state.isPlaying);
    });

    autoSub(_audioHandler.mediaItem, (item) async {
      if (item != null) {
        final gen = ++_mediaItemResolutionGen;
        final id = int.tryParse(item.id);
        if (id != null) {
          SongsTableData? resolvedSong;
          // Try in-memory sources first (no I/O) before hitting Drift — avoids stale overwrite
          resolvedSong = _audioHandler.currentSong?.id == id
              ? _audioHandler.currentSong
              : state.queue.where((s) => s.id == id).firstOrNull;
          if (resolvedSong == null) {
            final songResult = await _repository.getSongById(id);
            if (gen != _mediaItemResolutionGen || isClosed) return;
            songResult.fold((_) => null, (song) => resolvedSong = song);
          }
          if (gen != _mediaItemResolutionGen || isClosed) return;

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
            final duration =
                (item.duration != null && item.duration! > Duration.zero)
                    ? item.duration!
                    : (resolvedSong!.durationMs > 0
                        ? Duration(milliseconds: resolvedSong!.durationMs)
                        : state.duration);
            final isSameSong = _isSameTrack(state.currentSong, resolvedSong);
            final songQueueIndex = state.queue
                .indexWhere((s) => _isSameTrack(s, resolvedSong));
            final effectiveIndex =
                songQueueIndex != -1 ? songQueueIndex : state.currentIndex;

            safeEmit(
              state.copyWith(
                currentSong: resolvedSong,
                currentIndex: effectiveIndex,
                duration: duration,
                position: isSameSong ? state.position : Duration.zero,
                errorMessage: null,
              ),
            );

            if (gen != _mediaItemResolutionGen || isClosed) return;

            if (!isSameSong) {
              unawaited(_loadLyricsForSong(resolvedSong!));
              unawaited(_enrichAudioQuality(resolvedSong!, gen));
            }
            if (gen != _mediaItemResolutionGen || isClosed) return;
            _updateWidgetThrottled(force: true);
            _debouncedScrobble(resolvedSong!, state.position, state.isPlaying);
          }
        }
      }
    });

    autoSub(_audioHandler.errorStream, (err) {
      try {
        _latencyTracker?.finishWithError(err, stage: PlaybackStage.playing);
      } catch (_) {}
      safeEmit(state.copyWith(errorMessage: err));
    });

    autoSub(_audioHandler.queue, (mediaItems) async {
      if (mediaItems.isNotEmpty &&
          (state.queue.isEmpty || state.queue.length != mediaItems.length)) {
        final gen = _mediaItemResolutionGen;
        final ids =
            mediaItems.map((m) => int.tryParse(m.id)).whereType<int>().toList();
        final songsRes = await _repository.getSongsByIds(ids);
        final songsMap = {
          for (final s in songsRes.fold((_) => <SongsTableData>[], (r) => r))
            s.id: s
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
        if (isClosed || gen != _mediaItemResolutionGen) return;
        if (restoredSongs.isNotEmpty) {
          safeEmit(state.copyWith(queue: restoredSongs));
        }
      }
    });

    autoSub(_audioHandler.playbackState, (playbackState) {
      final isCompleted =
          playbackState.processingState == AudioProcessingState.completed;
      final repeat = switch (playbackState.repeatMode) {
        AudioServiceRepeatMode.one => PlayerRepeatMode.one,
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group =>
          PlayerRepeatMode.all,
        _ => PlayerRepeatMode.off,
      };

      final isPlaying = playbackState.playing && !isCompleted;
      // Task 0: mark first bytes / playing stages — TTFA telemetry must
      // reflect real audible start, so only mark when ExoPlayer is actually
      // ready (just_audio processingState == ready) AND playing, never while
      // still loading/buffering.
      if (isPlaying &&
          playbackState.processingState == AudioProcessingState.ready) {
        try {
          if (_latencyTracker?.hasActiveSession == true) {
            // firstBytesReady precedes playing by one frame if not yet marked
            _latencyTracker?.markStage(PlaybackStage.firstBytesReady);
            _latencyTracker?.markStage(PlaybackStage.playing);
          }
        } catch (_) {}
      }
      final effectivePos = isCompleted ? Duration.zero : playbackState.position;
      final wasPlaying = state.isPlaying;

      safeEmit(
        state.copyWith(
          isPlaying: isPlaying,
          position: effectivePos,
          isShuffle: playbackState.shuffleMode == AudioServiceShuffleMode.all,
          repeatMode: repeat,
          currentIndex: playbackState.queueIndex ?? state.currentIndex,
          playbackSpeed: playbackState.speed,
        ),
      );
      if (isPlaying != wasPlaying || repeat != state.repeatMode) {
        _updateWidgetThrottled(force: true);
      } else {
        _updateWidgetProgressThrottled();
      }
      final currentSong = state.currentSong;
      if (currentSong != null) {
        _debouncedScrobble(currentSong, effectivePos, isPlaying);
      }
    });

    autoSub(
      _audioHandler.positionStream
          .throttleTime(const Duration(milliseconds: 200), trailing: true),
      (pos) {
        safeEmit(state.copyWith(position: pos));
        if (state.isPlaying) {
          _updateWidgetProgressThrottled();
        }
      },
    );

    autoSub(_audioHandler.sleepTimerRemainingStream, (remaining) {
      safeEmit(state.copyWith(sleepTimerRemaining: remaining));
    });

    if (_audioHandler.currentAudioSessionId != null) {
      safeEmit(state.copyWith(audioSessionId: _audioHandler.currentAudioSessionId));
    }
    autoSub(_audioHandler.audioSessionIdStream, (id) {
      safeEmit(state.copyWith(audioSessionId: id));
    });
  }

  /// Reads real audio-header fields for a local song the first time it plays
  /// and caches them, so the quality badge shows actual metadata. Cheap: runs
  /// once per file (skips songs already enriched) and only for local files.
  Future<void> _enrichAudioQuality(SongsTableData song, int gen) async {
    if (song.source != SongSource.local) return;
    if (song.codec != null) return;
    final path = song.path;
    if (path.isEmpty ||
        path.startsWith('http') ||
        path.startsWith('ytmusic://')) {
      return;
    }
    try {
      await getIt<MediaScannerService>().enrichAudioQuality(song.id, path);
      if (isClosed || gen != _mediaItemResolutionGen) return;
      final refreshed = await _repository.getSongById(song.id);
      final updated = refreshed.fold((_) => null, (s) => s);
      if (updated != null &&
          !isClosed &&
          gen == _mediaItemResolutionGen &&
          _isSameTrack(state.currentSong, updated)) {
        safeEmit(state.copyWith(currentSong: updated));
      }
    } catch (_) {}
  }

  /// Monotonic loader generation: only the most recently started lyrics load
  /// may emit, so a slow fetch for a superseded song can never overwrite the
  /// current track's lyrics.
  int _lyricsLoadGen = 0;

  Future<void> _loadLyricsForSong(SongsTableData song) async {
    if (isClosed) return;
    final gen = ++_lyricsLoadGen;
    safeEmit(state.copyWith(
      isLoadingLyrics: true,
      lyrics: [],
      lyricsSource: LyricsSource.none,
    ));

    LyricsResult? lyricsResult;

    try {
      // 1. For local files, check embedded metadata and sidecar .lrc files
      if (song.source == SongSource.local &&
          !song.path.startsWith('http') &&
          !song.path.startsWith('ytmusic://')) {
        lyricsResult = await LrcParser.resolveLyrics(
          song.path,
          songId: song.id,
        );
      }

      if (isClosed ||
          gen != _lyricsLoadGen ||
          !_isSameTrack(state.currentSong, song)) {
        return;
      }

      // 2. Query LRCLIB for synchronized karaoke lyrics (works for local and online tracks)
      if (lyricsResult == null || lyricsResult.lines.isEmpty) {
        try {
          final lrclib = getIt<LrclibService>();
          lyricsResult = await lrclib
              .fetchLyrics(
                trackName: song.title,
                artistName: song.artist,
                albumName: song.album,
                durationSeconds:
                    song.durationMs > 0 ? song.durationMs ~/ 1000 : null,
              )
              .timeout(const Duration(seconds: 4), onTimeout: () => null);
        } catch (e, st) {
          ErrorLogger.log('LRCLIB fetch error for ${song.title}',
              error: e, stackTrace: st, category: 'Lyrics');
        }
      }

      if (isClosed ||
          gen != _lyricsLoadGen ||
          !_isSameTrack(state.currentSong, song)) {
        return;
      }

      // 3. For YouTube Music tracks without LRCLIB matches, fetch native YTM lyrics
      final videoId = song.remoteId;
      if ((lyricsResult == null || lyricsResult.lines.isEmpty) &&
          videoId != null &&
          videoId.isNotEmpty) {
        try {
          final ytmAccount = getIt<YtmAccountService>();
          lyricsResult = await ytmAccount
              .fetchYtmLyrics(videoId)
              .timeout(const Duration(seconds: 4), onTimeout: () => null);
        } catch (e, st) {
          ErrorLogger.log('YTM lyrics fetch error for $videoId',
              error: e, stackTrace: st, category: 'Lyrics');
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Lyrics load error for ${song.title}',
          error: e, stackTrace: st, category: 'Lyrics');
    } finally {
      if (!isClosed && gen == _lyricsLoadGen) {
        if (_isSameTrack(state.currentSong, song)) {
          safeEmit(state.copyWith(
            isLoadingLyrics: false,
            lyrics: lyricsResult?.lines ?? [],
            lyricsSource: lyricsResult?.source ?? LyricsSource.none,
          ));
        } else {
          safeEmit(state.copyWith(
            isLoadingLyrics: false,
          ));
        }
      }
    }
  }

  Future<void> refreshLyrics() async {
    final song = state.currentSong;
    if (song != null) {
      await _loadLyricsForSong(song);
    }
  }

  Future<void> playSong(SongsTableData song,
      {List<SongsTableData>? queue, Duration? initialPosition}) async {
    // Task 0: start latency tracking from tap
    final videoIdForLatency = song.remoteId ?? song.id.toString();
    try {
      _latencyTracker?.start(videoId: videoIdForLatency);
      _latencyTracker?.markStage(PlaybackStage.tap);
    } catch (_) {}
    ++_mediaItemResolutionGen;
    final capturedGen = _mediaItemResolutionGen;
    // Mark restoration as done: any in-flight _restoreQueueSlots must abort
    _queueRestorationDone = true;
    var rawQueue =
        queue != null ? List<SongsTableData>.from(queue) : [song];

    var targetIndex = rawQueue.indexWhere((s) => _isSameTrack(s, song));
    if (targetIndex == -1) {
      targetIndex = 0;
      rawQueue.insert(0, song);
    }

    List<SongsTableData> effectiveQueue;
    int effectiveIndex;

    String? queueTruncationWarning;
    if (rawQueue.length > _maxQueueSize) {
      final halfWindow = _maxQueueSize ~/ 2;
      var start = targetIndex - halfWindow;
      if (start < 0) start = 0;
      if (start + _maxQueueSize > rawQueue.length) {
        start = (rawQueue.length - _maxQueueSize).clamp(0, rawQueue.length);
      }
      effectiveQueue = rawQueue.sublist(start, start + _maxQueueSize);
      effectiveIndex = targetIndex - start;
      queueTruncationWarning =
          'Queue truncated to $_maxQueueSize (was ${rawQueue.length}) — tail dropped';
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

    // Immediate emission so tap feels instant: song row highlights,
    // play/pause updates to playing, and miniplayer shows the track.
    safeEmit(state.copyWith(
      queue: effectiveQueue,
      currentIndex: effectiveIndex,
      currentSong: song,
      isPlaying: true,
      position: startPos,
      duration: Duration(milliseconds: song.durationMs),
      errorMessage: queueTruncationWarning,
    ));

    // Start loadQueue immediately — don't block on local-match DB query.
    // The local-match check runs in parallel and swaps the source if found.
    try {
      _latencyTracker?.markStage(PlaybackStage.resolutionRequested);
    } catch (_) {}

    // Fire-and-forget: check if a downloaded local copy exists and swap it in
    if (song.source == SongSource.youtube) {
      unawaited(() async {
        try {
          final match = await _repository.findMatchingLocalSong(
            remoteId: song.remoteId,
            title: song.title,
            artist: song.artist,
          );
          if (_mediaItemResolutionGen != capturedGen) return;
          final local = match.fold((_) => null, (s) => s);
          if (local != null &&
              (local.path.startsWith('content:') ||
                  await File(local.path).exists())) {
            if (_mediaItemResolutionGen != capturedGen) return;
            if (local.id != song.id) {
              _audioHandler.swapReconciledSong(song.id, local);
              final swappedQueue = effectiveQueue
                  .map((s) => _isSameTrack(s, song) ? local : s)
                  .toList();
              safeEmit(state.copyWith(
                queue: swappedQueue,
                currentSong: local,
              ));
            }
          }
        } catch (_) {}
      }());
    }

    try {
      await _audioHandler.loadQueue(
        effectiveQueue,
        initialIndex: effectiveIndex,
        initialPosition: startPos,
      );
      try {
        _latencyTracker?.markStage(PlaybackStage.sourceSet);
      } catch (_) {}
    } catch (e) {
      try {
        _latencyTracker?.finishWithError(e, stage: PlaybackStage.sourceSet);
      } catch (_) {}
      safeEmit(state.copyWith(
        isPlaying: false,
        errorMessage: 'Failed to play ${song.title}',
      ));
      rethrow;
    }
    if (isClosed || _mediaItemResolutionGen != capturedGen) return;
    unawaited(_loadLyricsForSong(song));
    _updateWidgetThrottled(force: true);
  }

  Future<void> playNext(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      safeEmit(state.copyWith(errorMessage: 'Queue full ($_maxQueueSize) — cannot add more'));
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
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      safeEmit(state.copyWith(errorMessage: 'Queue full ($_maxQueueSize) — cannot add more'));
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
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex > state.queue.length) {
      return;
    }
    await _audioHandler.reorderQueue(oldIndex, newIndex);
    final updatedQueue = List<SongsTableData>.from(state.queue);
    if (oldIndex < newIndex) newIndex -= 1;
    final song = updatedQueue.removeAt(oldIndex);
    updatedQueue.insert(newIndex, song);
    var updatedIndex = state.currentIndex;
    if (updatedIndex == oldIndex) {
      updatedIndex = newIndex;
    } else if (oldIndex < updatedIndex && newIndex >= updatedIndex) {
      updatedIndex--;
    } else if (oldIndex > updatedIndex && newIndex <= updatedIndex) {
      updatedIndex++;
    }
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    await _audioHandler.removeQueueItemAt(index);
    final updatedQueue = List<SongsTableData>.from(state.queue)
      ..removeAt(index);
    var updatedIndex = state.currentIndex;
    if (updatedQueue.isEmpty) {
      updatedIndex = 0;
    } else if (index < updatedIndex) {
      updatedIndex--;
    } else if (index == updatedIndex) {
      updatedIndex = updatedIndex.clamp(0, updatedQueue.length - 1);
    }
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  bool _isSwitchingSlot = false;

  Future<void> switchQueueSlot(int slot) async {
    if (_isSwitchingSlot ||
        slot == state.activeQueueSlot ||
        slot < 0 ||
        slot > 2) {
      return;
    }
    _isSwitchingSlot = true;
    try {
      final wasPlaying = state.isPlaying;
      _queueSlots[state.activeQueueSlot] = _QueueSlotData(
        songs: List.from(state.queue),
        currentIndex: state.currentIndex,
        position: state.position,
        speed: state.playbackSpeed,
      );
      final targetSlot = _queueSlots[slot] ??
          const _QueueSlotData(
              songs: [], currentIndex: 0, position: Duration.zero, speed: 1.0);
      final targetOriginalSong = (targetSlot.currentIndex >= 0 &&
              targetSlot.currentIndex < targetSlot.songs.length)
          ? targetSlot.songs[targetSlot.currentIndex]
          : null;
      final validSongs = targetSlot.songs.where((s) => !s.isMissing).toList();

      _debouncedPersistQueueSlots();

      if (validSongs.isEmpty) {
        safeEmit(state.copyWith(
          activeQueueSlot: slot,
          queue: [],
          errorMessage: 'Queue slot is empty',
        ));
        return;
      }

      safeEmit(state.copyWith(activeQueueSlot: slot, queue: validSongs));

      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx =
            validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
      }
      if (safeIdx == -1) {
        safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      }
      final song = validSongs[safeIdx];
      safeEmit(state.copyWith(
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
        safeEmit(state.copyWith(isPlaying: false));
      }
      unawaited(_loadLyricsForSong(song));
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
      safeEmit(state.copyWith(
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

  Future<void> togglePlayPause() async {
    if (_audioHandler.playbackState.value.playing) {
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
    await _audioHandler.setShuffleMode(
        next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
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
      (failure) => safeEmit(state.copyWith(errorMessage: failure.message)),
      (isFav) {
        // Propagate to queue so SongTile favorite stars update immediately
        final updatedQueue = state.queue
            .map((s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s)
            .toList();
        // Also update slots
        _queueSlots.updateAll((k, v) => _QueueSlotData(
              songs: v.songs.map((s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s).toList(),
              currentIndex: v.currentIndex,
              position: v.position,
              speed: v.speed,
            ));
        if (state.currentSong != null && state.currentSong!.id == songId) {
          safeEmit(
            state.copyWith(
              currentSong: state.currentSong!.copyWith(isFavorite: isFav),
              queue: updatedQueue,
              errorMessage: null,
            ),
          );
          _updateWidgetThrottled(force: true);
        } else if (updatedQueue != state.queue) {
          safeEmit(state.copyWith(queue: updatedQueue, errorMessage: null));
        }
      },
    );
  }

  String? _dspBlockedReason() {
    final s = _settingsCubit?.state;
    if (s == null) return null;
    return AudioConflicts.dspBlockedByBitPerfect(
      bitPerfectOutput: s.bitPerfectOutput,
      bypassDspOnBitPerfect: s.bypassDspOnBitPerfect,
      device: s.currentOutputDevice,
    );
  }

  bool _guardDsp(String feature, {bool showError = true}) {
    final reason = _dspBlockedReason();
    if (reason != null) {
      if (showError) safeEmit(state.copyWith(errorMessage: '$feature blocked: $reason'));
      return false;
    }
    return true;
  }

  // Equalizer & Audio Effects
  Future<void> setEqualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('EQ')) return;
    safeEmit(state.copyWith(isEqEnabled: enabled, errorMessage: null));
    await _audioHandler.setEqualizerEnabled(enabled);
  }

  Future<void> applyPreset(EqPreset preset) async {
    if (!_guardDsp('Preset')) return;
    safeEmit(state.copyWith(
      isEqEnabled: true,
      eqPreset: preset,
      selectedHeadphoneProfile: null,
      errorMessage: null,
    ));
    await _audioHandler.setEqualizerEnabled(true);
    await _audioHandler.applyPreset(preset);
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) async {
    if (profile != null && !_guardDsp('AutoEQ')) return;
    if (profile != null) {
      safeEmit(state.copyWith(
        isEqEnabled: true,
        eqPreset: EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        ),
        selectedHeadphoneProfile: profile,
        errorMessage: null,
      ));
      await _audioHandler.setEqualizerEnabled(true);
    } else {
      safeEmit(state.copyWith(
        eqPreset: EqPreset.defaultPresets.first,
        selectedHeadphoneProfile: null,
      ));
    }
    await _audioHandler.applyHeadphoneProfile(profile);
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    if (gain.abs() > 0.1 && !_guardDsp('EQ Band')) return;
    final clamped = gain.clamp(-15.0, 15.0);
    final gains = List<double>.from(state.eqPreset.gains);
    if (bandIndex >= 0 && bandIndex < gains.length) {
      final hadProfile = state.selectedHeadphoneProfile != null;
      gains[bandIndex] = clamped;
      safeEmit(state.copyWith(
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
    safeEmit(state.copyWith(
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
    if (amount > 0.01 && !_guardDsp('Bass Boost')) return;
    final clamped = amount.clamp(0.0, 1.0);
    safeEmit(state.copyWith(
      eqPreset: EqPreset(
          name: state.eqPreset.name,
          gains: state.eqPreset.gains,
          bassBoost: clamped),
      errorMessage: null,
    ));
    await _audioHandler.setBassBoost(clamped);
  }

  Future<void> set32BandMode(bool enabled) async {
    await _audioHandler.set32BandMode(enabled);
    safeEmit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  Future<void> switchComparisonSlot(ComparisonSlot slot) async {
    await _audioHandler.switchComparisonSlot(slot);
    safeEmit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
  }

  String exportPresetToJson() => _audioHandler.exportPresetToJson();

  Future<bool> importPresetFromJson(String jsonStr) async {
    final ok = await _audioHandler.importPresetFromJson(jsonStr);
    if (ok) {
      safeEmit(state.copyWith(
        eqPreset: _audioHandler.currentPreset,
      ));
    }
    return ok;
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Virtualizer')) return;
    safeEmit(state.copyWith(isVirtualizerEnabled: enabled, errorMessage: null));
    await _audioHandler.setVirtualizerEnabled(enabled);
  }

  Future<void> setVirtualizerStrength(double strength) async {
    if (!_guardDsp('Virtualizer', showError: false)) return;
    safeEmit(state.copyWith(virtualizerStrength: strength));
    await _audioHandler.setVirtualizerStrength(strength);
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    final isEnabled = enabled ?? (preset != DynamicsPreset.off);
    if (isEnabled && !_guardDsp('Dynamics')) return;
    safeEmit(state.copyWith(
      dynamicsPreset: preset,
      isDynamicsEnabled: isEnabled,
      errorMessage: null,
    ));
    await _audioHandler.setDynamicsPreset(preset, enabled: enabled);
  }

  Future<void> toggleDynamicsBypass() async {
    await _audioHandler.toggleDynamicsBypass();
    safeEmit(state.copyWith(
      isDynamicsEnabled: !_audioHandler.isDynamicsBypassed &&
          state.dynamicsPreset != DynamicsPreset.off,
    ));
  }

  PlayerState? _dspSnapshot;

  Future<void> setDspEffectsEnabled(bool enabled) async {
    if (enabled && !_guardDsp('DSP Engine')) return;
    if (!enabled) {
      if (state.isDspActive) {
        _dspSnapshot = state;
      }
      safeEmit(state.copyWith(
        isSpatializerEnabled: false,
        isVirtualizerEnabled: false,
        isDynamicsEnabled: false,
        isCrossfeedEnabled: false,
        isLimiterEnabled: false,
        isReverbEnabled: false,
        isSaturationEnabled: false,
        isStereoWidthEnabled: false,
        isLoudnessContourEnabled: false,
        isSubCrossoverEnabled: false,
        isDynamicEqEnabled: false,
        volumeBoost: 0.0,
      ));
      await _audioHandler.setSpatializerEnabled(false);
      await _audioHandler.setVirtualizerEnabled(false);
      await _audioHandler.setDynamicsPreset(DynamicsPreset.off, enabled: false);
      await _audioHandler.setCrossfeed(false);
      await _audioHandler.setLookaheadLimiter(false);
      await _audioHandler.setReverb(false);
      await _audioHandler.setSaturation(false);
      await _audioHandler.setStereoWidth(false);
      await _audioHandler.setLoudnessContour(false);
      await _audioHandler.setSubCrossover(false);
      await _audioHandler.setDynamicEq(false);
      await _audioHandler.setVolumeBoost(0.0);
    } else {
      final snap = _dspSnapshot;
      if (snap != null && snap.isDspActive) {
        safeEmit(state.copyWith(
          isSpatializerEnabled: snap.isSpatializerEnabled,
          isVirtualizerEnabled: snap.isVirtualizerEnabled,
          virtualizerStrength: snap.virtualizerStrength,
          isDynamicsEnabled: snap.isDynamicsEnabled,
          dynamicsPreset: snap.dynamicsPreset,
          isCrossfeedEnabled: snap.isCrossfeedEnabled,
          crossfeedDelayUs: snap.crossfeedDelayUs,
          crossfeedFeedDb: snap.crossfeedFeedDb,
          isLimiterEnabled: snap.isLimiterEnabled,
          limiterThresholdDb: snap.limiterThresholdDb,
          limiterReleaseMs: snap.limiterReleaseMs,
          isReverbEnabled: snap.isReverbEnabled,
          reverbPreset: snap.reverbPreset,
          reverbWetDry: snap.reverbWetDry,
          isSaturationEnabled: snap.isSaturationEnabled,
          saturationDrive: snap.saturationDrive,
          saturationMix: snap.saturationMix,
          saturationTilt: snap.saturationTilt,
          isStereoWidthEnabled: snap.isStereoWidthEnabled,
          stereoWidth: snap.stereoWidth,
          isLoudnessContourEnabled: snap.isLoudnessContourEnabled,
          loudnessContourIntensity: snap.loudnessContourIntensity,
          isSubCrossoverEnabled: snap.isSubCrossoverEnabled,
          subCrossoverCornerHz: snap.subCrossoverCornerHz,
          subCrossoverSlopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
          subCrossoverGain: snap.subCrossoverGain,
          isDynamicEqEnabled: snap.isDynamicEqEnabled,
          dynamicEqBands: snap.dynamicEqBands,
          volumeBoost: snap.volumeBoost,
        ));
        if (snap.isSpatializerEnabled) await _audioHandler.setSpatializerEnabled(true);
        if (snap.isVirtualizerEnabled) {
          await _audioHandler.setVirtualizerEnabled(true);
          await _audioHandler.setVirtualizerStrength(snap.virtualizerStrength);
        }
        if (snap.isDynamicsEnabled && snap.dynamicsPreset != DynamicsPreset.off) {
          await _audioHandler.setDynamicsPreset(snap.dynamicsPreset, enabled: true);
        }
        if (snap.isCrossfeedEnabled) {
          await _audioHandler.setCrossfeed(true, delayUs: snap.crossfeedDelayUs, feedDb: snap.crossfeedFeedDb);
        }
        if (snap.isLimiterEnabled) {
          await _audioHandler.setLookaheadLimiter(true, thresholdDb: snap.limiterThresholdDb, releaseMs: snap.limiterReleaseMs);
        }
        if (snap.isReverbEnabled) {
          await _audioHandler.setReverb(true, preset: snap.reverbPreset, wetDry: snap.reverbWetDry);
        }
        if (snap.isSaturationEnabled) {
          await _audioHandler.setSaturation(true, drive: snap.saturationDrive, mix: snap.saturationMix, tilt: snap.saturationTilt);
        }
        if (snap.isStereoWidthEnabled) {
          await _audioHandler.setStereoWidth(true, width: snap.stereoWidth);
        }
        if (snap.isLoudnessContourEnabled) {
          await _audioHandler.setLoudnessContour(true, intensity: snap.loudnessContourIntensity);
        }
        if (snap.isSubCrossoverEnabled) {
          await _audioHandler.setSubCrossover(true, cornerHz: snap.subCrossoverCornerHz, slopeDbPerOct: snap.subCrossoverSlopeDbPerOct, gain: snap.subCrossoverGain);
        }
        if (snap.isDynamicEqEnabled) {
          await _audioHandler.setDynamicEq(true);
        }
        if (snap.volumeBoost > 0.0) {
          await _audioHandler.setVolumeBoost(snap.volumeBoost);
        }
      } else {
        safeEmit(state.copyWith(
          isLimiterEnabled: true,
          isDynamicsEnabled: true,
          dynamicsPreset: state.dynamicsPreset == DynamicsPreset.off
              ? DynamicsPreset.studioPunch
              : state.dynamicsPreset,
        ));
        await _audioHandler.setLookaheadLimiter(true);
        await _audioHandler.setDynamicsPreset(
          state.dynamicsPreset == DynamicsPreset.off
              ? DynamicsPreset.studioPunch
              : state.dynamicsPreset,
          enabled: true,
        );
      }
    }
  }

  Future<void> setVolumeBoost(double value) async {
    if (value > 0.01 && !_guardDsp('Volume Boost')) return;
    // Gain staging: cap if combined with preamp > 6 dB
    final preampDb = state.selectedHeadphoneProfile?.preampGain ?? 0.0;
    var safeValue = value.clamp(0.0, 1.0);
    if ((preampDb + safeValue * 10.0) > 6.0) {
      safeValue = ((6.0 - preampDb) / 10.0).clamp(0.0, 1.0);
    }
    safeEmit(state.copyWith(volumeBoost: safeValue, errorMessage: null));
    await _audioHandler.setVolumeBoost(safeValue);
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Spatializer')) return;
    await _audioHandler.setSpatializerEnabled(enabled);
    safeEmit(state.copyWith(isSpatializerEnabled: enabled, errorMessage: null));
  }

  // --- NATIVE DSP METHODS ---

  Future<void> setCrossfeed(bool enabled,
      {double? delayUs, double? feedDb}) async {
    if (enabled && !_guardDsp('Crossfeed')) return;
    safeEmit(state.copyWith(
      isCrossfeedEnabled: enabled,
      crossfeedDelayUs: delayUs ?? state.crossfeedDelayUs,
      crossfeedFeedDb: feedDb ?? state.crossfeedFeedDb,
      errorMessage: null,
    ));
    await _audioHandler.setCrossfeed(enabled, delayUs: delayUs, feedDb: feedDb);
  }

  Future<void> setLookaheadLimiter(bool enabled,
      {double? thresholdDb, double? releaseMs, double? lookaheadMs}) async {
    if (enabled && !_guardDsp('Limiter')) return;
    safeEmit(state.copyWith(
      isLimiterEnabled: enabled,
      limiterThresholdDb: thresholdDb ?? state.limiterThresholdDb,
      limiterReleaseMs: releaseMs ?? state.limiterReleaseMs,
      errorMessage: null,
    ));
    await _audioHandler.setLookaheadLimiter(enabled,
        thresholdDb: thresholdDb,
        releaseMs: releaseMs,
        lookaheadMs: lookaheadMs);
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    if (enabled && !_guardDsp('Reverb')) return;
    safeEmit(state.copyWith(
      isReverbEnabled: enabled,
      reverbPreset: preset ?? state.reverbPreset,
      reverbWetDry: wetDry ?? state.reverbWetDry,
      errorMessage: null,
    ));
    await _audioHandler.setReverb(enabled, preset: preset, wetDry: wetDry);
  }

  Future<void> loadCustomImpulseResponse(List<double> irSamples) async {
    safeEmit(state.copyWith(
      isReverbEnabled: true,
      reverbPreset: ReverbPreset.custom.wireValue,
    ));
    await _audioHandler.loadCustomImpulseResponse(irSamples);
  }

  Future<void> setStereoBalance(double balance) async {
    if (balance.abs() > 0.01 && !_guardDsp('Stereo Balance', showError: false)) return;
    final clamped = balance.clamp(-1.0, 1.0);
    safeEmit(state.copyWith(stereoBalance: clamped));
    await _audioHandler.setStereoBalance(clamped);
  }

  Future<void> setMonoMix(bool mono) async {
    if (mono && !_guardDsp('Mono Mix')) return;
    safeEmit(state.copyWith(monoMix: mono, errorMessage: null));
    await _audioHandler.setMonoMix(mono);
  }

  Future<void> setSincResampler(bool enabled) async {
    if (enabled && !_guardDsp('Resampler', showError: false)) return;
    safeEmit(state.copyWith(isSincResamplerEnabled: enabled));
    await _audioHandler.setSincResampler(enabled);
  }

  // --- PHASE 1 DSP EXPANSION METHODS ---

  Future<void> setSaturation(bool enabled,
      {double? drive, double? mix, double? tilt}) async {
    if (enabled && !_guardDsp('Harmonic Saturation')) return;
    safeEmit(state.copyWith(
      isSaturationEnabled: enabled,
      saturationDrive: drive ?? state.saturationDrive,
      saturationMix: mix ?? state.saturationMix,
      saturationTilt: tilt ?? state.saturationTilt,
      errorMessage: null,
    ));
    await _audioHandler.setSaturation(enabled,
        drive: drive, mix: mix, tilt: tilt);
  }

  Future<void> setStereoWidth(bool enabled, {double? width}) async {
    if (enabled && !_guardDsp('Stereo Width')) return;
    safeEmit(state.copyWith(
      isStereoWidthEnabled: enabled,
      stereoWidth: width ?? state.stereoWidth,
      errorMessage: null,
    ));
    await _audioHandler.setStereoWidth(enabled, width: width);
  }

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    if (enabled && !_guardDsp('Loudness Contour')) return;
    safeEmit(state.copyWith(
      isLoudnessContourEnabled: enabled,
      loudnessContourIntensity: intensity ?? state.loudnessContourIntensity,
      errorMessage: null,
    ));
    await _audioHandler.setLoudnessContour(enabled, intensity: intensity);
  }

  Future<void> setSubCrossover(bool enabled,
      {double? cornerHz, double? slopeDbPerOct, double? gain}) async {
    if (enabled && !_guardDsp('Sub Crossover')) return;
    safeEmit(state.copyWith(
      isSubCrossoverEnabled: enabled,
      subCrossoverCornerHz: cornerHz ?? state.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct: slopeDbPerOct ?? state.subCrossoverSlopeDbPerOct,
      subCrossoverGain: gain ?? state.subCrossoverGain,
      errorMessage: null,
    ));
    await _audioHandler.setSubCrossover(enabled,
        cornerHz: cornerHz, slopeDbPerOct: slopeDbPerOct, gain: gain);
  }

  Future<void> setDynamicEq(bool enabled) async {
    if (enabled && !_guardDsp('Dynamic EQ')) return;
    safeEmit(state.copyWith(
      isDynamicEqEnabled: enabled,
      errorMessage: null,
    ));
    await _audioHandler.setDynamicEq(enabled);
  }

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    // Seed with neutral defaults if the state list has not been synced yet
    while (bands.length <= index) {
      bands.add(const DynamicEqBandConfig());
    }
    bands[index] = band;
    safeEmit(state.copyWith(dynamicEqBands: bands));
    await _audioHandler.setDynamicEqBand(index, band);
  }

  // --- PHASE 3: PER-DEVICE PROFILE AUTOSWITCH ---

  void _startDeviceProfileWatcher() {
    final service = _deviceProfileService;
    final hiRes = _hiResAudioService;
    if (service == null || hiRes == null) return;
    autoSub(hiRes.outputDeviceStream, (device) {
      _onOutputDeviceChanged(device);
    });
  }

  Future<void> _onOutputDeviceChanged(AudioOutputInfo device) async {
    final service = _deviceProfileService;
    final profilesService = _settingsProfilesService;
    if (service == null || profilesService == null || isClosed) return;
    try {
      final key = DeviceProfileService.deviceKeyFromInfo(device);
      await service.rememberDevice(key, device.deviceName);
      // De-dup: the output stream also fires on format changes (sample rate,
      // bit depth) for the same device; only switch when the device changes.
      if (_lastAutoAppliedDeviceKey == key) return;
      if (!await service.isAutoSwitchEnabled()) return;
      final link = await service.linkForDeviceKey(key);
      if (link == null) return;
      final profiles = await profilesService.getProfiles();
      SettingsProfile? profile;
      for (final p in profiles) {
        if (p.id == link.profileId) {
          profile = p;
          break;
        }
      }
      if (profile == null) return;
      // Claim the key before applying: applyProfile awaits a long chain, and a
      // second stream event for the same device would otherwise pass this gate
      // and run a concurrent apply.
      _lastAutoAppliedDeviceKey = key;
      try {
        await applyProfile(profile);
      } catch (_) {
        _lastAutoAppliedDeviceKey = null;
        rethrow;
      }
    } catch (e, st) {
      ErrorLogger.log('Device profile auto-switch failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Applies a settings profile through the cubit's guarded setters so
  /// handler, persisted prefs and UI state stay consistent. Order matters:
  /// DSP stages are applied BEFORE bit-perfect so its bypass conflict rules
  /// evaluate against the pre-switch state, and bit-perfect is re-asserted
  /// last (its bypass then zeroes stages per the saved policy).
  Future<void> applyProfile(SettingsProfile profile, {bool manual = false}) async {
    try {
      EqPreset preset = EqPreset.defaultPresets.first;
      for (final p in EqPreset.defaultPresets) {
        if (p.name == profile.eqPresetName) {
          preset = p;
          break;
        }
      }
      await setEqualizerEnabled(true);
      await applyPreset(preset);
      await setVolumeBoost(profile.volumeBoost);
      if (profile.saturationEnabled != null) {
        await setSaturation(profile.saturationEnabled!);
      }
      if (profile.stereoWidthEnabled != null) {
        await setStereoWidth(profile.stereoWidthEnabled!);
      }
      if (profile.loudnessContourEnabled != null) {
        await setLoudnessContour(profile.loudnessContourEnabled!);
      }
      if (profile.subCrossoverEnabled != null) {
        await setSubCrossover(profile.subCrossoverEnabled!);
      }
      if (profile.dynamicEqEnabled != null) {
        await setDynamicEq(profile.dynamicEqEnabled!);
      }
      if (profile.crossfeedEnabled != null) {
        await setCrossfeed(
          profile.crossfeedEnabled!,
          delayUs: profile.crossfeedDelayUs,
          feedDb: profile.crossfeedFeedDb,
        );
      }
      if (profile.headphoneProfileId != null) {
        final repo = HeadphoneProfilesRepository();
        await repo.loadProfiles();
        final hpProfile = repo.getProfileById(profile.headphoneProfileId!);
        await applyHeadphoneProfile(hpProfile);
      }
      final settings = _settingsCubit;
      if (settings != null) {
        await settings.setCrossfade(
            profile.crossfadeEnabled ? profile.crossfadeSeconds : 0.0);
        await settings.setBitPerfectOutput(profile.bitPerfectEnabled);
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply settings profile',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  // Sleep Timer
  void startSleepTimer(int minutes) {
    final duration = Duration(minutes: minutes);
    _audioHandler.startSleepTimer(duration);
    safeEmit(state.copyWith(sleepTimerRemaining: duration));
  }

  void startAbsoluteSleepTimer(DateTime stopTime) {
    _audioHandler.startAbsoluteSleepTimer(stopTime);
    final diff = stopTime.difference(DateTime.now());
    safeEmit(state.copyWith(
        sleepTimerRemaining:
            diff.isNegative ? diff + const Duration(days: 1) : diff));
  }

  void startEndOfTrackTimer() {
    _audioHandler.startEndOfTrackTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: const Duration(minutes: 1)));
  }

  void startAfterNTracksTimer(int trackCount) {
    _audioHandler.startAfterNTracksTimer(trackCount);
    safeEmit(
        state.copyWith(sleepTimerRemaining: Duration(minutes: trackCount * 3)));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  // Playback Speed
  Future<void> _loadPlaybackSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speed = prefs.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;
      await _audioHandler.setSpeed(speed);
      safeEmit(state.copyWith(playbackSpeed: speed));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback speed from SharedPreferences',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _audioHandler.setSpeed(speed);
    safeEmit(state.copyWith(playbackSpeed: speed));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.playbackSpeed, speed);
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
    safeEmit(state.copyWith(
      isLyricsVisible: !state.isLyricsVisible,
      isQueueVisible: false,
    ));
  }

  void toggleQueueVisibility() {
    safeEmit(state.copyWith(
      isQueueVisible: !state.isQueueVisible,
      isLyricsVisible: false,
    ));
  }

  @override
  Future<void> close() {
    _persistQueueDebounce?.cancel();
    _scrobbleDebounce?.cancel();
    _widgetClickSub?.cancel();
    return super.close();
  }
}
