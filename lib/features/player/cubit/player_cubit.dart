// lib/features/player/cubit/player_cubit.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:mutex/mutex.dart';
import 'package:rxdart/rxdart.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/services/sponsorblock_service.dart';
import '../../../core/utils/async_guard.dart';
import '../../../core/utils/error_logger.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/db/app_database.dart';
import '../../../domain/models/radio_station.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../data/services/settings_profiles_service.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../core/services/earbud_optimization_service.dart';
import '../../../data/audio/comparison_slot.dart';
import '../../../data/audio/playback_bookmark_store.dart';
import '../../../data/audio/sleep_timer_manager.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/models/quran_mode_profile.dart';
import '../../../data/services/room_correction_service.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../settings/cubit/settings_cubit.dart';
import 'controllers/player_controllers.dart';
import 'managers/player_managers.dart';
import 'player_constants.dart';
import 'player_dependencies.dart';

export 'player_dependencies.dart';
import 'player_state.dart';

part 'player_queue_mixin.dart';
part 'player_transport_mixin.dart';
part 'player_dsp_mixin.dart';
part 'player_playback_options_mixin.dart';

/// Thin coordinator owning player controllers, audio handler subscriptions, and state emission.
@lazySingleton
class PlayerCubit extends PulsrCubit<PlayerState>
    with
        PlayerQueueOps,
        PlayerTransportControls,
        PlayerDspControls,
        PlayerPlaybackOptions {
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

  /// Emits [state] directly so tests can install a pre-baked player state.
  @visibleForTesting
  void setStateForTesting(PlayerState state) => emit(state);

  bool _userPausedIntentionally = false;
  DateTime? _optimisticPlayingSince;
  Timer? _optimisticPlayingTimer;
  static const Duration _optimisticPlayingMaxWindow = Duration(seconds: 10);
  // Auto-skip-on-error bookkeeping: the id of the track that last failed and
  // how many consecutive failures it has produced. A different track (or a
  // successful track change) resets the count.
  int? _lastFailedSongId;
  int _consecutiveErrorCount = 0;
  final Set<int> _autoSkippedSongIds = <int>{};
  DateTime? _lastAutoSkipAt;
  // Monotonic counter bumped whenever the queue is mutated; used to invalidate
  // the home-widget "up next" title cache on reorder.
  int _queueVersion = 0;
  int? _lastScrobbledSongId;
  int _lastScrobbledPlayGen = -1;
  final AsyncGuard _mediaItemGuard = AsyncGuard();
  final AsyncGuard _queueSyncGuard = AsyncGuard();

  /// True once the engine has emitted a non-empty queue. Before that an empty
  /// queue is a cold-start artefact; afterwards it is an intentional clear and
  /// must be honoured.
  bool _hasSeenNonEmptyHandlerQueue = false;
  // BUG-2 FIX: replaced the boolean _isSponsorBlockSeeking with a generation
  // counter. The old boolean was reset prematurely because whenComplete() fired
  // on the Future.value() that PlayerSeekThrottle returns for throttled seeks,
  // before the actual debounced seek ever ran. A generation counter allows the
  // in-flight seek to self-cancel if a newer SponsorBlock seek is launched
  // concurrently, and is only decremented when the seek truly completes.
  int _sponsorBlockSeekGen = 0;
  bool get _isSponsorBlockSeeking => _sponsorBlockSeekGen > 0;

  Stream<Duration> get rawPositionStream => _audioHandler.positionStream;
  List<SponsorBlockSegment> get sponsorBlockSegments =>
      metadataController.sponsorBlockSegments;

  @override
  void invalidateMediaItemResolution() => _mediaItemGuard.next();

  /// Invalidates any in-flight restored-queue (`_audioHandler.queue`)
  /// resolution. Called after a programmatic queue mutation so a slow DB lookup
  /// for an older engine-queue snapshot cannot clobber the just-applied change.
  void invalidateQueueSyncResolution() => _queueSyncGuard.next();

  PlayerCubit({
    required PulsrAudioHandler audioHandler,
    required IMusicRepository repository,
    required ToggleFavoriteUseCase toggleFavoriteUseCase,
    PlayerDependencies? dependencies,
  })  : _audioHandler = audioHandler,
        _repository = repository,
        _settingsCubit = dependencies?.settingsCubit,
        super(const PlayerState()) {
    final deps = dependencies ?? const PlayerDependencies();
    metadataController = PlayerMetadataController(
      lyricsManager: PlayerLyricsManager(
        lrclibService: deps.lrclibService,
        ytmAccountService: deps.ytmAccountService,
      ),
      sponsorBlockManager: PlayerSponsorBlockManager(
        service: deps.sponsorBlockService ?? SponsorBlockService.instance,
      ),
      repository: _repository,
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      isSameTrack: _isSameTrack,
    );
    dspController = PlayerDspController(
      audioHandler: _audioHandler,
      settingsCubit: _settingsCubit,
      settingsProfilesService: deps.settingsProfilesService,
      deviceProfileService: deps.deviceProfileService,
      hiResAudioService: deps.hiResAudioService,
      smartAudioService: deps.smartAudioService,
      getState: () => state,
      emit: safeEmit,
      syncAudioEffects: _syncAudioEffects,
      isClosed: () => isClosed,
    );
    playbackOptionsController = PlayerPlaybackOptionsController(
      audioHandler: _audioHandler,
      earbudOptimizationService: deps.earbudOptimizationService,
      hiResAudioService: deps.hiResAudioService,
      perSongEqStore: deps.perSongEqStore,
      perSongVolumeStore: deps.perSongVolumeStore,
      songRatingStore: deps.songRatingStore,
      quranManager: PlayerQuranManager(
        service: deps.quranModeService,
      ),
      guardDsp: (feature, {showError = true}) =>
          dspController.guardDsp(feature, showError: showError),
      playbackRateBlockedReason: dspController.playbackRateBlockedReason,
      onPerSongEqOverride: (song, presetName) =>
          dspController.applyTrackDspState(song, perSongPresetName: presetName),
      getState: () => state,
      emit: safeEmit,
      isClosed: () => isClosed,
      onLoadLyrics: (song, {isOfflineOnly = false}) =>
          metadataController.loadLyrics(song, isOfflineOnly: isOfflineOnly),
    );
    widgetBridge = PlayerWidgetBridge(
      widgetService: deps.widgetService,
      scrobblerService: () => deps.scrobblerService,
      latencyTracker: deps.latencyTracker,
      isQuranMode: () => state.isQuranModeEnabled,
      isClosed: () => isClosed,
      playbackSpeed: () => state.playbackSpeed,
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
      latencyTracker: deps.latencyTracker,
      mediaScannerService: deps.mediaScannerService,
      ytmService: deps.ytmService,
      onResumePerSongMemory: (song) =>
          unawaited(playbackOptionsController.applyPerSongPlaybackMemory(song)),
      invalidateQueueSyncResolution: invalidateQueueSyncResolution,
      cancelPendingSeek: () => transportController.cancelPendingSeek(),
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
      // AUDIT-FIX: the only caller is the queue-history jump in previous();
      // preserve the play/pause state so "previous" while paused does not
      // start playback.
      onPlaySong: (song, {queue, initialPosition}) => playSong(
        song,
        queue: queue,
        initialPosition: initialPosition,
        preservePlaybackState: true,
      ),
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
    unawaited(playbackOptionsController.restoreQuranMode());
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
        preampDb: _audioHandler.preampDb,
        isCrossfeedEnabled: _audioHandler.crossfeedUserEnabled,
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
      _audioHandler.setAutomixEnabled(settingsCubit.state.automixEnabled);

      var prevCrossfadeSeconds = settingsCubit.state.crossfadeSeconds;
      var prevGapless = settingsCubit.state.gaplessPlayback;
      var prevAutomix = settingsCubit.state.automixEnabled;
      var prevReplayGainMode = settingsCubit.state.replayGainMode;
      var prevPreampWithRg = settingsCubit.state.replayGainPreampWithRg;
      var prevPreampWithoutRg = settingsCubit.state.replayGainPreampWithoutRg;
      var prevFollowSampleRate = settingsCubit.state.followTrackSampleRate;
      var prevBitPerfect = settingsCubit.state.bitPerfectOutput;

      autoSub(settingsCubit.stream, (settingsState) {
        final crossfadeChanged =
            settingsState.crossfadeSeconds != prevCrossfadeSeconds;
        final gaplessChanged = settingsState.gaplessPlayback != prevGapless;
        final automixChanged = settingsState.automixEnabled != prevAutomix;
        final volumeRelatedChanged =
            settingsState.replayGainMode != prevReplayGainMode ||
                settingsState.replayGainPreampWithRg != prevPreampWithRg ||
                settingsState.replayGainPreampWithoutRg != prevPreampWithoutRg;
        final sampleRateRelatedChanged =
            settingsState.followTrackSampleRate != prevFollowSampleRate ||
                settingsState.bitPerfectOutput != prevBitPerfect;

        prevCrossfadeSeconds = settingsState.crossfadeSeconds;
        prevGapless = settingsState.gaplessPlayback;
        prevAutomix = settingsState.automixEnabled;
        prevReplayGainMode = settingsState.replayGainMode;
        prevPreampWithRg = settingsState.replayGainPreampWithRg;
        prevPreampWithoutRg = settingsState.replayGainPreampWithoutRg;
        prevFollowSampleRate = settingsState.followTrackSampleRate;
        prevBitPerfect = settingsState.bitPerfectOutput;

        if (crossfadeChanged) {
          _audioHandler.setCrossfadeDuration(
            Duration(
                milliseconds: (settingsState.crossfadeSeconds * 1000).round()),
          );
        }
        if (gaplessChanged) {
          _audioHandler.setGaplessEnabled(settingsState.gaplessPlayback);
        }
        if (automixChanged) {
          _audioHandler.setAutomixEnabled(settingsState.automixEnabled);
        }
        if (volumeRelatedChanged) {
          // Re-apply composed gain (ReplayGain, loudness equalization, volume boost) for new settings
          unawaited(_audioHandler
              .setVolume(_audioHandler.volume)
              .catchError((Object e, StackTrace st) {
            ErrorLogger.log('Re-apply volume on settings change failed',
                error: e, stackTrace: st, category: 'PlayerCubit');
          }));
        }
        if (sampleRateRelatedChanged &&
            settingsState.followTrackSampleRate &&
            settingsState.bitPerfectOutput) {
          final song = state.currentSong;
          if (song != null) {
            unawaited(dspController.maybeFollowTrackSampleRate(song));
          }
        }
      });
    }
  }

  static const int _maxNegativeIdEntries = 1000;
  final Map<String, int> _remoteIdToNegativeId = {};
  // Reverse index of the values currently held by [_remoteIdToNegativeId], so
  // collision checks are O(1) instead of the O(n) `Map.containsValue` scan.
  final Set<int> _negativeIdValues = {};
  // Starts strictly below the hash-derived range (which spans
  // [-1000000001, -2]) so a fallback-assigned id can never collide with a
  // hash-derived one.
  int _nextAssignedNegativeId = -1000000002;

  int _resolveMediaItemId(String id) {
    final parsed = int.tryParse(id);
    if (parsed != null) return parsed;
    final cached = _remoteIdToNegativeId[id];
    if (cached != null) return cached;
    if (_remoteIdToNegativeId.length >= _maxNegativeIdEntries) {
      final evictedKey = _remoteIdToNegativeId.keys.first;
      final evictedValue = _remoteIdToNegativeId.remove(evictedKey);
      if (evictedValue != null) _negativeIdValues.remove(evictedValue);
    }
    // Map non-numeric IDs into collision-free negative integer space (never colliding on 0 or positive DB IDs)
    final h = -(id.hashCode.abs() % 1000000000 + 2);
    int assigned;
    if (!_negativeIdValues.contains(h)) {
      assigned = h;
    } else {
      // BUG-5 FIX: added a floor guard. Without it, _nextAssignedNegativeId
      // could reach dart:core's int.minValue in a very long session with many
      // hash collisions and wrap to a positive value, colliding with real DB IDs.
      // The fallback counter lives below the hash range [-1000000001, -2] so it
      // starts at -1000000002 and is floored at -9000000000000000000.
      do {
        if (_nextAssignedNegativeId <= -9000000000000000000) {
          // Safety reset: clear the cache and restart the counter. This is a
          // last-resort guard for pathological multi-day sessions.
          _negativeIdValues.removeWhere((v) => v < -1000000001);
          _remoteIdToNegativeId.removeWhere((_, v) => v < -1000000001);
          _nextAssignedNegativeId = -1000000002;
          ErrorLogger.log(
            'Negative ID counter reset after floor guard triggered',
            category: 'PlayerCubit',
          );
        }
        assigned = _nextAssignedNegativeId--;
      } while (_negativeIdValues.contains(assigned));
    }
    _remoteIdToNegativeId[id] = assigned;
    _negativeIdValues.add(assigned);
    return assigned;
  }

  Duration _resolveTrackDuration({
    Duration? engineDuration,
    int? songDurationMs,
    Duration? previousDuration,
    bool isSameSong = false,
  }) {
    if (engineDuration != null && engineDuration > Duration.zero) {
      return engineDuration;
    }
    if (songDurationMs != null && songDurationMs > 0) {
      return Duration(milliseconds: songDurationMs);
    }
    if (isSameSong && previousDuration != null) {
      return previousDuration;
    }
    return Duration.zero;
  }

  void _maybeScrobble(SongsTableData song, Duration position, bool isPlaying) {
    final currentGen = _audioHandler.playbackState.valueOrNull?.queueIndex ?? 0;
    if (_lastScrobbledSongId != song.id ||
        _lastScrobbledPlayGen != currentGen) {
      _lastScrobbledSongId = song.id;
      _lastScrobbledPlayGen = currentGen;
      widgetBridge.scrobble(song, position, isPlaying);
    }
  }

  /// The engine's authoritative current queue index when known and in range for
  /// a queue of [length]; otherwise null so callers fall back to a by-identity
  /// search. Preferring the engine index disambiguates duplicate songs, where
  /// `indexWhere` would always resolve to the first occurrence.
  int? _engineQueueIndexWithin(int length) {
    final idx = _audioHandler.playbackState.valueOrNull?.queueIndex;
    return (idx != null && idx >= 0 && idx < length) ? idx : null;
  }

  void _listenToAudioService() {
    autoSub(_audioHandler.onTrackChanged, (song) {
      if (isClosed) return;
      // Invalidate any in-flight mediaItem resolution for the previous track so
      // a slow DB lookup cannot re-emit the old song after this change.
      invalidateMediaItemResolution();
      final songIndex = _engineQueueIndexWithin(state.queue.length) ??
          state.queue.indexWhere((s) => _isSameTrack(s, song));
      final isSameSong = _isSameTrack(state.currentSong, song);
      final duration = _resolveTrackDuration(
        songDurationMs: song.durationMs,
        previousDuration: state.duration,
        isSameSong: isSameSong,
      );
      // Record history here too: this listener can win the race against the
      // mediaItem listener, which would then see isSameSong and skip it.
      final updatedHistory = List<SongsTableData>.from(state.queueHistory);
      final previousSong = state.currentSong;
      if (!isSameSong && previousSong != null) {
        updatedHistory.removeWhere((s) => s.id == previousSong.id);
        updatedHistory.insert(0, previousSong);
        if (updatedHistory.length > 25) {
          updatedHistory.removeRange(25, updatedHistory.length);
        }
      }
      safeEmit(state.copyWith(
        playback: state.playback.copyWith(
          currentSong: song,
          duration: duration,
          position: isSameSong ? state.position : Duration.zero,
          errorMessage: null,
        ),
        queueSlice: state.queueSlice.copyWith(
          currentIndex: songIndex != -1 ? songIndex : state.currentIndex,
          queueHistory: updatedHistory,
        ),
        lyricsSlice: state.lyricsSlice.copyWith(
          lyrics: isSameSong ? state.lyrics : const [],
          lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
          isLoadingLyrics: !isSameSong,
        ),
      ));
      if (!isSameSong) {
        _lastFailedSongId = null;
        _consecutiveErrorCount = 0;
        unawaited(metadataController.enrichTrackParallel(song));
        unawaited(dspController.maybeFollowTrackSampleRate(song));
        unawaited(playbackOptionsController.onCurrentSongChanged(song));
        unawaited(checkAndTriggerAutoplay());
        widgetBridge.updateWidgetThrottled(state, force: true);
      }
      _maybeScrobble(song, state.position, state.isPlaying);
    });

    autoSub(_audioHandler.mediaItem, (item) async {
      if (item == null || item.id.isEmpty) {
        if (_audioHandler.playbackState.valueOrNull?.processingState ==
                AudioProcessingState.idle ||
            _audioHandler.queue.valueOrNull?.isEmpty == true) {
          // Cold-start race guard: if the cubit already has a restored queue/currentSong
          // while the audio handler is still idle/uninitialised, do not wipe the restored track.
          final handlerQueue = _audioHandler.queue.valueOrNull;
          final isIdle =
              _audioHandler.playbackState.valueOrNull?.processingState ==
                  AudioProcessingState.idle;
          if (isIdle &&
              !_hasSeenNonEmptyHandlerQueue &&
              (handlerQueue == null || handlerQueue.isEmpty) &&
              state.queue.isNotEmpty) {
            return;
          }
          if (state.currentSong != null) {
            safeEmit(state.copyWith(
              playback: state.playback.copyWith(
                currentSong: null,
                isPlaying: false,
                isBuffering: false,
                position: Duration.zero,
                duration: Duration.zero,
              ),
              lyricsSlice: state.lyricsSlice.copyWith(
                lyrics: const [],
                lyricsSource: LyricsSource.none,
                isLoadingLyrics: false,
              ),
            ));
          }
        }
        return;
      }
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
          remoteArtworkUrl: (item.extras?['remoteArtworkUrl'] as String?) ??
              item.artUri?.toString(),
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
        final duration = _resolveTrackDuration(
          engineDuration: item.duration,
          songDurationMs: song.durationMs,
          previousDuration: state.duration,
          isSameSong: isSameSong,
        );
        final songQueueIndex = _engineQueueIndexWithin(state.queue.length) ??
            state.queue.indexWhere((s) => _isSameTrack(s, song));
        final effectiveIndex =
            songQueueIndex != -1 ? songQueueIndex : state.currentIndex;

        final songChanged = !isSameSong ||
            state.currentSong?.isFavorite != song.isFavorite ||
            state.currentSong?.artworkUri != song.artworkUri ||
            state.currentSong?.remoteArtworkUrl != song.remoteArtworkUrl ||
            state.currentSong?.album != song.album;

        final previousSong = state.currentSong;
        final updatedHistory = List<SongsTableData>.from(state.queueHistory);
        if (!isSameSong && previousSong != null) {
          updatedHistory.removeWhere((s) => s.id == previousSong.id);
          updatedHistory.insert(0, previousSong);
          if (updatedHistory.length > 25) {
            updatedHistory.removeRange(25, updatedHistory.length);
          }
        }

        safeEmit(state.copyWith(
          playback: state.playback.copyWith(
            currentSong: song,
            duration: duration,
            position: isSameSong ? state.position : Duration.zero,
            errorMessage: null,
          ),
          queueSlice: state.queueSlice.copyWith(
            currentIndex: effectiveIndex,
            queueHistory: updatedHistory,
          ),
          lyricsSlice: state.lyricsSlice.copyWith(
            lyrics: isSameSong ? state.lyrics : const [],
            lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
            isLoadingLyrics: !isSameSong,
          ),
        ));

        if (!isSameSong) {
          _lastFailedSongId = null;
          _consecutiveErrorCount = 0;
          unawaited(metadataController.enrichTrackParallel(song));
          unawaited(dspController.maybeFollowTrackSampleRate(song));
          unawaited(playbackOptionsController.onCurrentSongChanged(song));
          unawaited(checkAndTriggerAutoplay());
        }
        if (songChanged) {
          widgetBridge.updateWidgetThrottled(state, force: true);
        }
        _maybeScrobble(song, state.position, state.isPlaying);
      }
    });

    autoSub(_audioHandler.queue, (mediaItems) async {
      if (mediaItems.isNotEmpty) {
        _hasSeenNonEmptyHandlerQueue = true;
      }
      if (mediaItems.isEmpty) {
        final isIdle =
            _audioHandler.playbackState.valueOrNull?.processingState ==
                AudioProcessingState.idle;
        if (isIdle && !_hasSeenNonEmptyHandlerQueue && state.queue.isNotEmpty) {
          // Cold-start race guard: audioHandler.queue starts at [] before session restoration
          // or slot loading completes. Do not wipe a valid restored queue.
          return;
        }
        if (state.queue.isNotEmpty || state.currentSong != null) {
          safeEmit(state.copyWith(
            playback: state.playback.copyWith(
              currentSong: null,
              isPlaying: false,
              isBuffering: false,
              position: Duration.zero,
              duration: Duration.zero,
              errorMessage: null,
            ),
            queueSlice: state.queueSlice.copyWith(
              queue: const [],
              currentIndex: 0,
            ),
            lyricsSlice: state.lyricsSlice.copyWith(
              lyrics: const [],
              lyricsSource: LyricsSource.none,
              isLoadingLyrics: false,
            ),
          ));
        }
        return;
      }
      final gen = _queueSyncGuard.next();
      final ids = mediaItems.map((m) => _resolveMediaItemId(m.id)).toList();
      if (ids.isEmpty) return;
      final songsRes = await _repository.getSongsByIds(ids);
      if (isClosed || !_queueSyncGuard.isValid(gen)) return;
      final songsMap = {
        for (final s in songsRes.fold((_) => <SongsTableData>[], (r) => r))
          s.id: s
      };
      final restored = <SongsTableData>[];
      for (final m in mediaItems) {
        final parsedId = int.tryParse(m.id);
        if (parsedId == null) {
          ErrorLogger.log('Restoring non-numeric queue media item id=${m.id}',
              category: 'PlayerCubit');
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
            remoteId: (m.extras?['remoteId'] as String?) ??
                (parsedId == null ? m.id : null),
            remoteArtworkUrl: (m.extras?['remoteArtworkUrl'] as String?) ??
                m.artUri?.toString(),
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
        int resolvedIndex;
        if (current == null) {
          // No current track to anchor on: clamp the previous index into range.
          resolvedIndex = state.currentIndex.clamp(0, restored.length - 1);
        } else {
          // Keep currentIndex pointing at currentSong instead of an arbitrary
          // clamp: prefer an identity match, then a strict id match, then the
          // engine's own current queue index, and only clamp as a last resort.
          var idx = restored.indexWhere((s) => _isSameTrack(s, current));
          if (idx == -1) idx = restored.indexWhere((s) => s.id == current.id);
          if (idx == -1) {
            final engineIndex =
                _audioHandler.playbackState.valueOrNull?.queueIndex;
            if (engineIndex != null &&
                engineIndex >= 0 &&
                engineIndex < restored.length) {
              idx = engineIndex;
            }
          }
          resolvedIndex = idx != -1
              ? idx
              : state.currentIndex.clamp(0, restored.length - 1);
        }
        safeEmit(state.copyWith(
          queueSlice: state.queueSlice.copyWith(
            queue: restored,
            currentIndex: resolvedIndex,
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
        AudioServiceRepeatMode.all ||
        AudioServiceRepeatMode.group =>
          PlayerRepeatMode.all,
        _ => PlayerRepeatMode.off,
      };

      var resolvedPlaying = isPlaying;
      final transientNonReady =
          ps.processingState == AudioProcessingState.loading ||
              ps.processingState == AudioProcessingState.buffering;
      if (!isPlaying &&
          state.isPlaying &&
          !_userPausedIntentionally &&
          transientNonReady) {
        // Keep the optimistic "playing" through transient non-ready states
        // (loading/buffering) during a selection/load so the play button
        // doesn't flicker at track start. Bounded: an external pause (audio
        // focus loss, unplugged headphones) while buffering must not leave the
        // UI showing "playing" forever.
        final since = _optimisticPlayingSince ??= DateTime.now();
        if (DateTime.now().difference(since) < _optimisticPlayingMaxWindow) {
          resolvedPlaying = true;
          // Expire on our own: without a further engine event the UI would
          // otherwise keep claiming "playing" past the window.
          _optimisticPlayingTimer ??= Timer(_optimisticPlayingMaxWindow, () {
            _optimisticPlayingTimer = null;
            if (isClosed || _userPausedIntentionally) return;
            final eng = _audioHandler.playbackState.valueOrNull;
            if (eng != null && eng.playing) return;
            if (state.isPlaying) {
              safeEmit(state.copyWith(
                  playback: state.playback.copyWith(isPlaying: false)));
            }
          });
        }
      } else {
        _optimisticPlayingSince = null;
        _optimisticPlayingTimer?.cancel();
        _optimisticPlayingTimer = null;
      }

      final isBuffering = ps.processingState == AudioProcessingState.loading ||
          ps.processingState == AudioProcessingState.buffering;

      final resolvedIndex = ps.queueIndex != null &&
              ps.queueIndex! >= 0 &&
              ps.queueIndex! < state.queue.length
          ? ps.queueIndex!
          : state.currentIndex;

      final effectivePos = isCompleted ? Duration.zero : ps.position;
      final resolvedShuffle = ps.shuffleMode == AudioServiceShuffleMode.all;
      final nonPositionStateChanged = resolvedPlaying != state.isPlaying ||
          isBuffering != state.isBuffering ||
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
          isBuffering: isBuffering,
          position: isCompleted
              ? Duration.zero
              : (effectivePos > Duration.zero ? effectivePos : state.position),
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
    autoSub(
        positionUpdates.throttleTime(PlayerConstants.positionThrottleDuration,
            trailing: true), (pos) {
      if (state.playback.position == pos) return;
      // Repeat-one loop wrap: the engine restarts the same track without a
      // track change, so re-arm scrobbling for the new play.
      final wrapped = state.repeatMode == PlayerRepeatMode.one &&
          state.duration > Duration.zero &&
          state.position > state.duration * 0.5 &&
          pos < const Duration(seconds: 3);
      if (wrapped) _lastScrobbledSongId = null;
      safeEmit(
          state.copyWith(playback: state.playback.copyWith(position: pos)));
      if (wrapped) {
        final cur = state.currentSong;
        if (cur != null) _maybeScrobble(cur, pos, state.isPlaying);
      }
      if (state.isPlaying) {
        widgetBridge.updateWidgetProgressThrottled(state);
        // SponsorBlock auto-skip: jump past a skippable segment when one covers
        // the current position. Guarded so overlapping ticks never double-seek.
        // BUG-2 FIX: use a generation counter instead of a boolean so the guard
        // is cleared only after the engine seek completes, not when the
        // Future.value() from a throttled seek resolves immediately.
        if (!_isSponsorBlockSeeking) {
          final skipTarget =
              metadataController.sponsorBlockSkipTarget(pos, isPlaying: true);
          if (skipTarget != null) {
            final myGen = ++_sponsorBlockSeekGen;
            unawaited(seek(skipTarget).catchError((Object e, StackTrace st) {
              ErrorLogger.log('SponsorBlock auto-skip seek failed',
                  error: e, stackTrace: st, category: 'PlayerCubit');
            }).whenComplete(() {
              // Only decrement if this is still the active seek generation.
              if (_sponsorBlockSeekGen == myGen) _sponsorBlockSeekGen = 0;
            }));
          }
        }
      }
    });

    autoSub(_audioHandler.errorStream, (err) {
      widgetBridge.onPlaybackError(err);
      final failed = state.currentSong;
      if (failed == null) {
        safeEmit(state.copyWith(
            playback: state.playback
                .copyWith(errorMessage: err, isBuffering: false)));
        return;
      }
      if (failed.id == _lastFailedSongId) {
        _consecutiveErrorCount++;
      } else {
        _lastFailedSongId = failed.id;
        _consecutiveErrorCount = 1;
      }
      if (_consecutiveErrorCount >= 2 && _canAutoSkipUnplayable()) {
        final now = DateTime.now();
        if (_lastAutoSkipAt == null ||
            now.difference(_lastAutoSkipAt!) > const Duration(minutes: 2)) {
          _autoSkippedSongIds.clear();
        }
        _lastAutoSkipAt = now;
        // Never chase an entirely unplayable queue forever: cap the number of
        // distinct auto-skips at the queue length and stop with a clear error.
        final exhausted = !_autoSkippedSongIds.add(failed.id) ||
            _autoSkippedSongIds.length >= state.queue.length;
        _lastFailedSongId = null;
        _consecutiveErrorCount = 0;
        if (exhausted) {
          safeEmit(state.copyWith(
            playback: state.playback.copyWith(
              errorMessage: 'No playable tracks in the queue',
              isBuffering: false,
            ),
          ));
          return;
        }
        safeEmit(state.copyWith(
          playback: state.playback.copyWith(
            errorMessage: 'Skipped ${failed.title} (unplayable)',
            isBuffering: false,
          ),
        ));
        unawaited(next());
        return;
      }
      safeEmit(state.copyWith(
          playback:
              state.playback.copyWith(errorMessage: err, isBuffering: false)));
    });

    autoSub(_audioHandler.sleepTimerRemainingStream, (rem) {
      safeEmit(state.copyWith(
          playback: state.playback.copyWith(sleepTimerRemaining: rem)));
    });

    try {
      autoSub(_audioHandler.sleepTimerRemainingTracksStream, (tracks) {
        safeEmit(state.copyWith(
            playback:
                state.playback.copyWith(sleepTimerRemainingTracks: tracks)));
      });
    } catch (e, st) {
      ErrorLogger.log('Optional sleep timer stream attachment failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }

    autoSub(_audioHandler.audioSessionIdStream, (id) {
      safeEmit(state.copyWith(
          playback: state.playback.copyWith(audioSessionId: id)));
    });
  }

  /// Whether a twice-failed track can be abandoned for the next queue item.
  /// Repeat-one would replay the same broken track, a single-item queue has
  /// nowhere to go, and repeat-off at the last item must not wrap around.
  bool _canAutoSkipUnplayable() {
    if (state.repeatMode == PlayerRepeatMode.one) return false;
    if (state.queue.length <= 1) return false;
    return state.hasNextNeighbour;
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

  bool _isSameQueue(List<SongsTableData> a, List<SongsTableData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_isSameTrack(a[i], b[i])) return false;
    }
    return true;
  }

  void clearError() {
    safeEmit(
        state.copyWith(playback: state.playback.copyWith(errorMessage: null)));
  }

  Future<void> persistQueueSlotsNow() => queueController.persistQueueSlotsNow();
  Future<void> saveDspSnapshot() => _audioHandler.saveDspSnapshotForCurrent();

  @override
  Future<void> close() async {
    final cleanups = <({String name, FutureOr<void> Function() run})>[
      (name: 'transportController', run: transportController.dispose),
      (name: 'dspController', run: dspController.dispose),
      (
        name: 'playbackOptionsController',
        run: playbackOptionsController.dispose
      ),
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
    _optimisticPlayingTimer?.cancel();
    _remoteIdToNegativeId.clear();
    _negativeIdValues.clear();
    await super.close();
  }
}
