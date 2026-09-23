// lib/features/player/cubit/player_cubit.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:rxdart/rxdart.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/services/lrclib_service.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/sponsorblock_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/telemetry/playback_latency_tracker.dart';
import '../../../core/utils/async_guard.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/per_song_eq_store.dart';
import '../../../data/audio/per_song_volume_store.dart';
import '../../../data/audio/song_rating_store.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/radio_station.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../core/services/device_profile_service.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/settings_profiles_service.dart';
import '../../../core/services/smart_audio_service.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../core/services/earbud_optimization_service.dart';
import '../../../core/services/quran_mode_service.dart';
import '../../../data/audio/comparison_slot.dart';
import '../../../data/audio/playback_bookmark_store.dart';
import '../../../data/audio/sleep_timer_manager.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/models/quran_mode_profile.dart';
import '../../../core/services/room_correction_service.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../widgets/widget_service.dart';
import 'controllers/player_controllers.dart';
import 'managers/player_managers.dart';
import 'player_constants.dart';
import 'player_dependencies.dart';
import 'player_state.dart';

part 'player_queue_mixin.dart';
part 'player_transport_mixin.dart';
part 'player_dsp_mixin.dart';
part 'player_playback_options_mixin.dart';

/// Thin coordinator owning player controllers, audio handler subscriptions, and state emission.
@lazySingleton
class PlayerCubit extends PulsrCubit<PlayerState>
    with PlayerQueueOps, PlayerTransportControls, PlayerDspControls, PlayerPlaybackOptions {
  final PulsrAudioHandler _audioHandler;
  final IMusicRepository _repository;
  final SettingsCubit? _settingsCubit;

  @override
  @visibleForTesting
  late final PlayerTransportController transportController;
  @override
  @visibleForTesting
  late final PlayerQueueController queueController;
  @override
  @visibleForTesting
  late final PlayerDspController dspController;
  @override
  @visibleForTesting
  late final PlayerPlaybackOptionsController playbackOptionsController;
  @visibleForTesting
  late final PlayerMetadataController metadataController;
  @visibleForTesting
  late final PlayerWidgetBridge widgetBridge;

  bool _userPausedIntentionally = false;
  // Monotonic counter bumped whenever the queue is mutated; used to invalidate
  // the home-widget "up next" title cache on reorder.
  int _queueVersion = 0;
  final AsyncGuard _trackChangedGuard = AsyncGuard();
  final AsyncGuard _mediaItemGuard = AsyncGuard();
  final AsyncGuard _queueSyncGuard = AsyncGuard();

  Stream<Duration> get rawPositionStream => _audioHandler.positionStream;

  @override
  void invalidateMediaItemResolution() => _mediaItemGuard.next();

  PlayerCubit({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    PlayerDependencies? dependencies,
    SettingsCubit? settingsCubit,
    WidgetService? widgetService,
    ScrobblerService? scrobblerService,
    SettingsProfilesService? settingsProfilesService,
    DeviceProfileService? deviceProfileService,
    HiResAudioService? hiResAudioService,
    SmartAudioService? smartAudioService,
    PlaybackLatencyTracker? latencyTracker,
    PerSongEqStore? perSongEqStore,
    PerSongVolumeStore? perSongVolumeStore,
    SongRatingStore? songRatingStore,
    SponsorBlockService? sponsorBlockService,
    LrclibService? lrclibService,
    YtmAccountService? ytmAccountService,
    EarbudOptimizationService? earbudOptimizationService,
    QuranModeService? quranModeService,
    MediaScannerService? mediaScannerService,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _settingsCubit = dependencies?.settingsCubit ?? settingsCubit,
        super(const PlayerState()) {
    metadataController = PlayerMetadataController(
      lyricsManager: PlayerLyricsManager(
        lrclibService: dependencies?.lrclibService ?? lrclibService,
        ytmAccountService: dependencies?.ytmAccountService ?? ytmAccountService,
      ),
      sponsorBlockManager: PlayerSponsorBlockManager(
        service: dependencies?.sponsorBlockService ?? sponsorBlockService ?? SponsorBlockService.instance,
      ),
      repository: _repository,
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      isSameTrack: _isSameTrack,
    );
    playbackOptionsController = PlayerPlaybackOptionsController(
      audioHandler: _audioHandler,
      earbudOptimizationService: dependencies?.earbudOptimizationService ?? earbudOptimizationService,
      hiResAudioService: dependencies?.hiResAudioService ?? hiResAudioService,
      perSongEqStore: dependencies?.perSongEqStore ?? perSongEqStore,
      perSongVolumeStore: dependencies?.perSongVolumeStore ?? perSongVolumeStore,
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      onLoadLyrics: (song, {isOfflineOnly = false}) =>
          metadataController.loadLyrics(song, isOfflineOnly: isOfflineOnly),
    );
    dspController = PlayerDspController(
      audioHandler: _audioHandler,
      settingsCubit: _settingsCubit,
      settingsProfilesService: dependencies?.settingsProfilesService ?? settingsProfilesService,
      deviceProfileService: dependencies?.deviceProfileService ?? deviceProfileService,
      hiResAudioService: dependencies?.hiResAudioService ?? hiResAudioService,
      smartAudioService: dependencies?.smartAudioService ?? smartAudioService,
      getState: () => state,
      emit: safeEmit,
      syncAudioEffects: _syncAudioEffects,
      isClosed: () => isClosed,
    );
    widgetBridge = PlayerWidgetBridge(
      widgetService: dependencies?.widgetService ?? widgetService,
      scrobblerService: () => dependencies?.scrobblerService ?? scrobblerService,
      latencyTracker: dependencies?.latencyTracker ?? latencyTracker,
      isQuranMode: () => state.isQuranModeEnabled,
      isClosed: () => isClosed,
    );
    final queueMutex = Mutex();
    final slotLookupCache = <int, SongsTableData>{};
    final queueSlots = <int, QueueSlotData>{};
    queueController = PlayerQueueController(
      audioHandler: _audioHandler,
      repository: _repository,
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      queueMutex: queueMutex,
      slotLookupCache: slotLookupCache,
      queueSlots: queueSlots,
      updateWidgetThrottled: ({bool force = false}) =>
          widgetBridge.updateWidgetThrottled(state,
              queueVersion: _queueVersion, force: force),
      loadLyrics: (song) => unawaited(metadataController.loadLyrics(song)),
      debouncedPersistQueueSlots: () =>
          queueController.debouncedPersistQueueSlots(),
      bumpQueueVersion: () => _queueVersion++,
      isSameTrack: _isSameTrack,
      latencyTracker: dependencies?.latencyTracker ?? latencyTracker,
      onResumePerSongMemory: (song) => unawaited(
          playbackOptionsController.applyPerSongPlaybackMemory(song)),
    );
    transportController = PlayerTransportController(
      audioHandler: _audioHandler,
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      onUserPausedIntentionally: (val) => _userPausedIntentionally = val,
      toggleFavoriteUseCase: toggleFavoriteUseCase,
      slotLookupCache: slotLookupCache,
      debouncedPersistQueueSlots: () =>
          queueController.debouncedPersistQueueSlots(),
      updateWidgetThrottled: ({bool force = false}) =>
          widgetBridge.updateWidgetThrottled(state,
              queueVersion: _queueVersion, force: force),
    );
    widgetBridge.listenToClicks(
      onPlayPause: togglePlayPause,
      onPrevious: previous,
      onNext: next,
      onFavorite: () {
        final s = state.currentSong;
        if (s != null) toggleFavorite(s.id);
      },
    );
    unawaited(queueController.restoreQueueSlots());
    _listenToSettings();
    _listenToAudioService();
    _syncAudioEffects(force: true);
    unawaited(_audioHandler.effectsReady.then((_) async {
      if (isClosed) return;
      _syncAudioEffects(force: true);
      await _audioHandler.setVolume(_audioHandler.volume);
    }).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Post-init effects re-sync failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }));
  }

  void _syncAudioEffects({bool force = false}) {
    if (!force && dspController.isUserInteracting) return;
    safeEmit(state.copyWith(
      dsp: state.dsp.copyWith(
        isEqEnabled: _audioHandler.isEqualizerEnabled,
        eqPreset: _audioHandler.currentPreset,
        isVirtualizerEnabled: _audioHandler.isVirtualizerEnabled,
        virtualizerStrength: _audioHandler.virtualizerStrength,
        isVirtualizerSupported: _audioHandler.isVirtualizerSupported,
        isDynamicsEnabled: _audioHandler.isDynamicsEffectivelyEnabled,
        isDynamicsSupported: _audioHandler.isDynamicsSupported,
        dynamicsPreset: _audioHandler.dynamicsPreset,
        selectedHeadphoneProfile: _audioHandler.selectedHeadphoneProfile,
        isSpatializerEnabled: _audioHandler.isSpatializerEnabled,
        isSpatializerSupported: _audioHandler.isSpatializerSupported,
        isBassBoostSupported: _audioHandler.isBassBoostSupported,
        isVolumeBoostSupported: _audioHandler.isVolumeBoostSupported,
        volumeBoost: _audioHandler.volumeBoost,
        isCrossfeedEnabled: _audioHandler.isCrossfeedEnabled,
        crossfeedDelayUs: _audioHandler.crossfeedDelayUs,
        crossfeedFeedDb: _audioHandler.crossfeedFeedDb,
        crossfeedMode: _audioHandler.crossfeedMode,
        isLimiterEnabled: _audioHandler.isLimiterEnabled,
        limiterThresholdDb: _audioHandler.limiterThresholdDb,
        limiterReleaseMs: _audioHandler.limiterReleaseMs,
        isReverbEnabled: _audioHandler.isReverbEnabled,
        reverbPreset: _audioHandler.reverbPreset,
        reverbWetDry: _audioHandler.reverbWetDry,
        stereoBalance: _audioHandler.stereoBalance,
        monoMix: _audioHandler.monoMix,
        isSincResamplerEnabled: _audioHandler.isSincResamplerEnabled,
        isDitherEnabled: _audioHandler.isDitherEnabled,
        ditherTargetBitDepth: _audioHandler.ditherTargetBitDepth,
        isSaturationEnabled: _audioHandler.isSaturationEnabled,
        saturationDrive: _audioHandler.saturationDrive,
        saturationMix: _audioHandler.saturationMix,
        saturationTilt: _audioHandler.saturationTilt,
        saturationMultiband: _audioHandler.saturationMultiband,
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
        isViperDdcEnabled: _audioHandler.isViperDdcEnabled,
        viperDdcProfileName: _audioHandler.viperDdcProfileName,
        isArbitraryEqEnabled: _audioHandler.isArbitraryEqEnabled,
        arbitraryEqString: _audioHandler.arbitraryEqString,
        isLiveProgEnabled: _audioHandler.isLiveProgEnabled,
        liveProgCode: _audioHandler.liveProgCode,
        isDynamicBassEnabled: _audioHandler.isDynamicBassEnabled,
        dynamicBassStrength: _audioHandler.dynamicBassStrength,
        dynamicBassPreset: _audioHandler.dynamicBassPreset,
        hasOemAudio: _audioHandler.hasOemAudio,
        detectedOemEngines: _audioHandler.detectedOemEngines,
      ),
    ));
  }

  void _listenToSettings() {
    final settingsCubit = _settingsCubit;
    if (settingsCubit != null) {
      _audioHandler.setCrossfadeDuration(
        Duration(
            milliseconds:
                (settingsCubit.state.crossfadeSeconds * 1000).round()),
      );
      _audioHandler.setGaplessEnabled(settingsCubit.state.gaplessPlayback);
      autoSub(settingsCubit.stream, (settingsState) {
        _audioHandler.setCrossfadeDuration(
          Duration(
              milliseconds: (settingsState.crossfadeSeconds * 1000).round()),
        );
        _audioHandler.setGaplessEnabled(settingsState.gaplessPlayback);
        // Re-apply composed gain (ReplayGain, loudness equalization, volume boost) for new settings
        _audioHandler.setVolume(_audioHandler.volume);
        if (settingsState.followTrackSampleRate) {
          final song = state.currentSong;
          if (song != null) {
            unawaited(dspController.maybeFollowTrackSampleRate(song));
          }
        }
      });
    }
  }

  final Map<String, int> _remoteIdToNegativeId = {};
  int _nextAssignedNegativeId = -2;

  int _resolveMediaItemId(String id) {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed;
    // Map non-numeric IDs into collision-free negative integer space (never colliding on 0 or positive DB IDs)
    return _remoteIdToNegativeId.putIfAbsent(id, () {
      final h = -(id.hashCode.abs() % 1000000000 + 2);
      if (!_remoteIdToNegativeId.containsValue(h)) {
        return h;
      }
      return _nextAssignedNegativeId--;
    });
  }

  void _listenToAudioService() {
    autoSub(_audioHandler.onTrackChanged, (song) {
      if (isClosed) return;
      _trackChangedGuard.next();
      final songIndex = state.queue.indexWhere((s) => _isSameTrack(s, song));
      final isSameSong = _isSameTrack(state.currentSong, song);
      safeEmit(state.copyWith(
        playback: state.playback.copyWith(
          currentSong: song,
          duration: song.durationMs > 0
              ? Duration(milliseconds: song.durationMs)
              : (isSameSong ? state.duration : Duration.zero),
          position: isSameSong ? state.position : Duration.zero,
          errorMessage: null,
        ),
        queueSlice: state.queueSlice.copyWith(
          currentIndex: songIndex != -1 ? songIndex : state.currentIndex,
        ),
        lyricsSlice: state.lyricsSlice.copyWith(
          lyrics: isSameSong ? state.lyrics : const [],
          lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
          isLoadingLyrics: !isSameSong,
        ),
      ));
      if (!isSameSong) {
        unawaited(metadataController.enrichTrackParallel(song));
        unawaited(dspController.maybeFollowTrackSampleRate(song));
      }
      widgetBridge.updateWidgetThrottled(state, force: true);
      widgetBridge.scrobble(song, state.position, state.isPlaying);
    });

    autoSub(_audioHandler.mediaItem, (item) async {
      if (item == null || item.id.isEmpty) return;
      final mediaGen = _mediaItemGuard.next();
      final id = _resolveMediaItemId(item.id);

      SongsTableData? resolvedSong = _audioHandler.currentSong?.id == id
          ? _audioHandler.currentSong
          : state.queue.where((s) => s.id == id).firstOrNull;

      if (resolvedSong == null) {
        final songResult = await _repository.getSongById(id);
        if (!_mediaItemGuard.isValid(mediaGen) || isClosed) return;
        songResult.fold((_) => null, (song) => resolvedSong = song);
      }
      if (!_mediaItemGuard.isValid(mediaGen) || isClosed) return;

      if (resolvedSong == null && item.id.isNotEmpty) {
        resolvedSong = SongsTableData(
          id: id,
          title: item.title,
          artist: item.artist ?? 'Unknown',
          album: item.album ?? '',
          durationMs: item.duration?.inMilliseconds ?? 0,
          path: (item.extras?['path'] as String?) ?? '',
          source: (item.extras?['source'] as String?) ?? SongSource.youtube,
          remoteId: item.extras?['remoteId'] as String?,
          remoteArtworkUrl: (item.extras?['remoteArtworkUrl'] as String?) ?? item.artUri?.toString(),
          isFavorite: (item.extras?['isFavorite'] as bool?) ?? false,
          isMissing: false,
          isDownloaded: (item.extras?['isDownloaded'] as bool?) ?? false,
          playCount: (item.extras?['playCount'] as int?) ?? 0,
          lastPositionMs: 0,
        );
      }

      if (resolvedSong != null) {
        final song = resolvedSong!;
        if (!_mediaItemGuard.isValid(mediaGen) || isClosed) return;
        final isSameSong = _isSameTrack(state.currentSong, song);
        final duration = (item.duration != null && item.duration! > Duration.zero)
            ? item.duration!
            : (song.durationMs > 0
                ? Duration(milliseconds: song.durationMs)
                : (isSameSong ? state.duration : Duration.zero));
        final songQueueIndex = state.queue.indexWhere((s) => _isSameTrack(s, song));
        final effectiveIndex = songQueueIndex != -1 ? songQueueIndex : state.currentIndex;

        safeEmit(state.copyWith(
          playback: state.playback.copyWith(
            currentSong: song,
            duration: duration,
            position: isSameSong ? state.position : Duration.zero,
            errorMessage: null,
          ),
          queueSlice: state.queueSlice.copyWith(
            currentIndex: effectiveIndex,
          ),
          lyricsSlice: state.lyricsSlice.copyWith(
            lyrics: isSameSong ? state.lyrics : const [],
            lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
            isLoadingLyrics: !isSameSong,
          ),
        ));

        if (!isSameSong) {
          unawaited(metadataController.enrichTrackParallel(song));
          unawaited(dspController.maybeFollowTrackSampleRate(song));
        }
        widgetBridge.updateWidgetThrottled(state, force: true);
        widgetBridge.scrobble(song, state.position, state.isPlaying);
      }
    });

    autoSub(_audioHandler.queue, (mediaItems) async {
      if (mediaItems.isEmpty) return;
      final gen = _queueSyncGuard.next();
      final ids = mediaItems.map((m) => _resolveMediaItemId(m.id)).toList();
      if (ids.isEmpty) return;
      final songsRes = await _repository.getSongsByIds(ids);
      if (isClosed || !_queueSyncGuard.isValid(gen)) return;
      final songsMap = {for (final s in songsRes.fold((_) => <SongsTableData>[], (r) => r)) s.id: s};
      final restored = <SongsTableData>[];
      for (final m in mediaItems) {
        final parsedId = int.tryParse(m.id);
        if (parsedId == null) {
          ErrorLogger.log('Restoring non-numeric queue media item id=${m.id}', category: 'PlayerCubit');
        }
        final mid = _resolveMediaItemId(m.id);
        if (songsMap.containsKey(mid)) {
          restored.add(songsMap[mid]!);
        } else {
          restored.add(SongsTableData(
            id: mid,
            title: m.title,
            artist: m.artist ?? 'Unknown',
            album: m.album ?? '',
            durationMs: m.duration?.inMilliseconds ?? 0,
            path: (m.extras?['path'] as String?) ?? '',
            source: (m.extras?['source'] as String?) ?? SongSource.youtube,
            remoteId: (m.extras?['remoteId'] as String?) ?? (parsedId == null ? m.id : null),
            remoteArtworkUrl: (m.extras?['remoteArtworkUrl'] as String?) ?? m.artUri?.toString(),
            isFavorite: (m.extras?['isFavorite'] as bool?) ?? false,
            isMissing: false,
            isDownloaded: (m.extras?['isDownloaded'] as bool?) ?? false,
            playCount: (m.extras?['playCount'] as int?) ?? 0,
            lastPositionMs: 0,
          ));
        }
      }
      if (restored.isNotEmpty && !_isSameQueue(state.queue, restored)) {
        final current = state.currentSong;
        final anchored = current == null ? -1 : restored.indexWhere((s) => _isSameTrack(s, current));
        safeEmit(state.copyWith(
          queueSlice: state.queueSlice.copyWith(
            queue: restored,
            currentIndex: (anchored != -1 ? anchored : state.currentIndex).clamp(0, restored.length - 1),
          ),
        ));
      }
    });

    autoSub(_audioHandler.playbackState, (ps) {
      final isCompleted = ps.processingState == AudioProcessingState.completed;
      final isPlaying = ps.playing && !isCompleted;
      if (isPlaying) {
        _userPausedIntentionally = false;
      }
      if (isPlaying && ps.processingState == AudioProcessingState.ready) {
        widgetBridge.onAudiblePlaybackStarted();
      }
      final repeat = switch (ps.repeatMode) {
        AudioServiceRepeatMode.one => PlayerRepeatMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => PlayerRepeatMode.all,
        _ => PlayerRepeatMode.off,
      };

      var resolvedPlaying = isPlaying;
      if (!isPlaying &&
          state.isPlaying &&
          !_userPausedIntentionally &&
          ps.processingState != AudioProcessingState.ready &&
          ps.processingState != AudioProcessingState.completed) {
        resolvedPlaying = true;
      }

      final resolvedIndex = ps.queueIndex != null && ps.queueIndex! >= 0 && ps.queueIndex! < state.queue.length
          ? ps.queueIndex!
          : state.currentIndex;

      final effectivePos = isCompleted ? Duration.zero : ps.position;
      final resolvedShuffle = ps.shuffleMode == AudioServiceShuffleMode.all;
      final nonPositionStateChanged = resolvedPlaying != state.isPlaying ||
          resolvedShuffle != state.isShuffle ||
          repeat != state.repeatMode ||
          resolvedIndex != state.currentIndex ||
          (ps.speed - state.playbackSpeed).abs() >= 1e-9;

      if (!nonPositionStateChanged && !isCompleted) {
        // Pure position update: ignore here, positionUpdates stream is the canonical source
        return;
      }

      safeEmit(state.copyWith(
        playback: state.playback.copyWith(
          isPlaying: resolvedPlaying,
          position: isCompleted ? Duration.zero : (effectivePos > Duration.zero ? effectivePos : state.position),
          isShuffle: resolvedShuffle,
          repeatMode: repeat,
          playbackSpeed: ps.speed,
        ),
        queueSlice: state.queueSlice.copyWith(
          currentIndex: resolvedIndex,
        ),
      ));
      widgetBridge.updateWidgetProgressThrottled(state);
    });

    Stream<Duration> positionUpdates;
    try {
      positionUpdates = _audioHandler.compensatedPositionStream;
    } catch (_) {
      positionUpdates = _audioHandler.positionStream;
    }
    autoSub(positionUpdates.throttleTime(PlayerConstants.positionThrottleDuration, trailing: true), (pos) {
      safeEmit(state.copyWith(playback: state.playback.copyWith(position: pos)));
      if (state.isPlaying) widgetBridge.updateWidgetProgressThrottled(state);
    });

    autoSub(_audioHandler.errorStream, (err) {
      widgetBridge.onPlaybackError(err);
      safeEmit(state.copyWith(playback: state.playback.copyWith(errorMessage: err)));
    });

    autoSub(_audioHandler.sleepTimerRemainingStream, (rem) {
      safeEmit(state.copyWith(playback: state.playback.copyWith(sleepTimerRemaining: rem)));
    });

    try {
      autoSub(_audioHandler.sleepTimerRemainingTracksStream, (tracks) {
        safeEmit(state.copyWith(playback: state.playback.copyWith(sleepTimerRemainingTracks: tracks)));
      });
    } catch (_) {}

    autoSub(_audioHandler.audioSessionIdStream, (id) {
      safeEmit(state.copyWith(playback: state.playback.copyWith(audioSessionId: id)));
    });
  }

  bool _isSameTrack(SongsTableData? a, SongsTableData? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.id == b.id) return true;
    if (a.remoteId != null && b.remoteId != null && a.remoteId!.isNotEmpty && a.remoteId == b.remoteId) return true;
    if (a.path.isNotEmpty && a.path == b.path) return true;
    return false;
  }

  bool _isSameQueue(List<SongsTableData> a, List<SongsTableData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_isSameTrack(a[i], b[i])) return false;
    }
    return true;
  }

  void clearError() {
    safeEmit(state.copyWith(playback: state.playback.copyWith(errorMessage: null)));
  }

  Future<void> persistQueueSlotsNow() => queueController.persistQueueSlotsNow();
  Future<void> saveDspSnapshot() => _audioHandler.saveDspSnapshotForCurrent();

  @override
  Future<void> close() async {
    final cleanups = <({String name, FutureOr<void> Function() run})>[
      (name: 'transportController', run: transportController.dispose),
      (name: 'dspController', run: dspController.dispose),
      (name: 'playbackOptionsController', run: playbackOptionsController.dispose),
      (name: 'metadataController', run: metadataController.dispose),
      (name: 'widgetBridge', run: widgetBridge.dispose),
      (name: 'persistQueueSlots', run: queueController.persistQueueSlotsNow),
    ];
    for (final cleanup in cleanups) {
      try {
        await cleanup.run();
      } catch (e, st) {
        ErrorLogger.log('PlayerCubit close ${cleanup.name} failed',
            error: e, stackTrace: st, category: 'PlayerCubit');
      }
    }
    try {
      queueController.dispose();
    } catch (e, st) {
      ErrorLogger.log('PlayerCubit close queueController failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
    _remoteIdToNegativeId.clear();
    await super.close();
  }
}
