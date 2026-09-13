import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/audio/ir_file_parser.dart';
import '../../../core/bloc/base_cubit.dart';
import '../../../core/constants/prefs_keys.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/lrclib_service.dart';
import '../../../core/services/radio_station_store.dart';
import '../../../core/services/scrobbler_service.dart';
import '../../../core/services/sponsorblock_service.dart';
import '../../../core/services/ytm_account_service.dart';
import '../../../core/telemetry/playback_latency_tracker.dart';
import '../../../core/utils/error_logger.dart';
import '../../../core/utils/lrc_parser.dart';
import '../../../core/utils/cue_parser.dart';
import '../../../core/constants/audio_feature_info.dart';
import '../../../data/audio/audio_handler.dart';
import '../../../data/audio/equalizer_manager.dart';
import '../../../data/audio/per_song_eq_store.dart';
import '../../../data/audio/per_song_volume_store.dart';
import '../../../data/audio/playback_bookmark_store.dart';
import '../../../data/audio/sleep_timer_manager.dart';
import '../../../data/audio/song_rating_store.dart';
import '../../../data/db/app_database.dart';
import '../../../data/scanner/media_scanner_service.dart';
import '../../../domain/models/audio_effects_config.dart';
import '../../../domain/models/eq_preset.dart';
import '../../../domain/models/headphone_profile.dart';
import '../../../domain/models/reverb_preset.dart';
import '../../../data/audio/headphone_profiles_repository.dart';
import '../../../domain/models/lyrics_line.dart';
import '../../../domain/models/radio_station.dart';
import '../../../domain/repositories/music_repository_interface.dart';
import '../../../domain/usecases/toggle_favorite_usecase.dart';
import '../../../core/services/device_profile_service.dart';
import '../../../core/services/earbud_optimization_service.dart';
import '../../../core/services/hires_audio_service.dart';
import '../../../core/services/quran_mode_service.dart';
import '../../../core/services/room_correction_service.dart';
import '../../../core/services/settings_profiles_service.dart';
import '../../../core/services/smart_audio_service.dart';
import '../../../domain/services/headphone_device_matcher.dart';
import '../../../domain/services/smart_audio_plan.dart';
import '../../../domain/models/audio_output_info.dart';
import '../../../domain/models/quran_mode_profile.dart';
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

/// Captures the DSP settings that Quran Mode overrides so they can be restored
/// verbatim when the mode is switched off.
class _QuranRestoreSnapshot {
  final EqPreset eqPreset;
  final bool isEqEnabled;
  final HeadphoneProfile? headphoneProfile;
  final bool isReverbEnabled;
  final int reverbPreset;
  final double reverbWetDry;
  final bool isDynamicsEnabled;
  final DynamicsPreset dynamicsPreset;
  final bool isSaturationEnabled;
  final double saturationDrive;
  final double saturationMix;
  final double saturationTilt;
  final double playbackSpeed;
  final bool isShuffle;
  final double preampDb;

  const _QuranRestoreSnapshot({
    required this.eqPreset,
    required this.isEqEnabled,
    required this.headphoneProfile,
    required this.isReverbEnabled,
    required this.reverbPreset,
    required this.reverbWetDry,
    required this.isDynamicsEnabled,
    required this.dynamicsPreset,
    required this.isSaturationEnabled,
    required this.saturationDrive,
    required this.saturationMix,
    required this.saturationTilt,
    required this.playbackSpeed,
    required this.isShuffle,
    required this.preampDb,
  });

  Map<String, dynamic> toJson() => {
        'eqPreset': eqPreset.toJson(),
        'isEqEnabled': isEqEnabled,
        'headphoneProfile': headphoneProfile?.toJson(),
        'isReverbEnabled': isReverbEnabled,
        'reverbPreset': reverbPreset,
        'reverbWetDry': reverbWetDry,
        'isDynamicsEnabled': isDynamicsEnabled,
        'dynamicsPreset': dynamicsPreset.name,
        'isSaturationEnabled': isSaturationEnabled,
        'saturationDrive': saturationDrive,
        'saturationMix': saturationMix,
        'saturationTilt': saturationTilt,
        'playbackSpeed': playbackSpeed,
        'isShuffle': isShuffle,
        'preampDb': preampDb,
      };

  factory _QuranRestoreSnapshot.fromJson(Map<String, dynamic> json) {
    final rawEq = json['eqPreset'];
    final rawProfile = json['headphoneProfile'];
    return _QuranRestoreSnapshot(
      eqPreset: EqPreset.fromJson(
          rawEq is Map ? Map<String, dynamic>.from(rawEq) : const {}),
      isEqEnabled: json['isEqEnabled'] as bool? ?? false,
      headphoneProfile: rawProfile is Map
          ? HeadphoneProfile.fromJson(Map<String, dynamic>.from(rawProfile))
          : null,
      isReverbEnabled: json['isReverbEnabled'] as bool? ?? false,
      reverbPreset: (json['reverbPreset'] as num?)?.toInt() ?? 0,
      reverbWetDry: (json['reverbWetDry'] as num?)?.toDouble() ?? 0.20,
      isDynamicsEnabled: json['isDynamicsEnabled'] as bool? ?? false,
      dynamicsPreset: DynamicsPreset.values.firstWhere(
          (e) => e.name == json['dynamicsPreset'],
          orElse: () => DynamicsPreset.off),
      isSaturationEnabled: json['isSaturationEnabled'] as bool? ?? false,
      saturationDrive: (json['saturationDrive'] as num?)?.toDouble() ?? 0.3,
      saturationMix: (json['saturationMix'] as num?)?.toDouble() ?? 0.5,
      saturationTilt: (json['saturationTilt'] as num?)?.toDouble() ?? 0.3,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      isShuffle: json['isShuffle'] as bool? ?? false,
      preampDb: (json['preampDb'] as num?)?.toDouble() ?? 0.0,
    );
  }
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
  final SmartAudioService? _smartAudioService;
  final PerSongEqStore _perSongEqStore;
  final PerSongVolumeStore _perSongVolumeStore;
  final SongRatingStore _songRatingStore;
  final SponsorBlockService _sponsorBlockService;
  final QuranModeService? _quranModeService;
  final EarbudOptimizationService? _earbudOptimizationService;
  final LrclibService? _lrclibService;
  final YtmAccountService? _ytmAccountService;
  final MediaScannerService? _mediaScannerService;
  _QuranRestoreSnapshot? _quranRestore;
  String? _lastAutoAppliedDeviceKey;
  /// True when Smart Auto itself enabled bit-perfect output, so it only ever
  /// turns off what it turned on (a manual bit-perfect choice is respected).
  bool _smartAutoBitPerfectApplied = false;

  // FIX(BUG-14): Expose unthrottled position stream for high-fps UI components like MiniPlayer
  Stream<Duration> get rawPositionStream => _audioHandler.positionStream;

  SponsorBlockService get _sponsorBlock => _sponsorBlockService;

  StreamSubscription<void>? _widgetClickSub;
  DateTime? _lastWidgetUpdateTime;
  DateTime? _lastSlotPersistAt;
  int _mediaItemResolutionGen = 0;
  int _localMatchSwapGen = 0;
  List<SponsorBlockSegment> _currentSponsorSegments = const [];
  String? _sponsorSegmentsVideoId;
  Duration? _lastSkippedSegmentEnd;
  DateTime? _lastSponsorSkipTime;

  Timer? _persistQueueDebounce;
  Timer? _scrobbleDebounce;
  Timer? _seekThrottleTimer;
  Duration? _pendingSeek;
  int? _lastScrobbleSongId;
  bool? _lastScrobbleIsPlaying;
  // FIX(BUG-15): Track position in milliseconds to avoid precision loss on sub-second seeks
  int? _lastScrobblePosMs;
  // Latest pending values for the debounced minor-tick flush. Read at fire
  // time so the flush reports the newest position, not the first tick's.
  SongsTableData? _pendingScrobbleSong;
  int _pendingScrobblePosMs = 0;
  bool _pendingScrobbleIsPlaying = false;
  List<String>? _cachedNextTitles;
  int? _cachedNextTitlesIndex;
  int? _cachedQueueLength;
  int? _cachedCurrentSongId;
  int? _cachedQueueVersion;

  /// T2: last sample rate successfully pushed for follow-track. Used to
  /// de-dupe so tracks sharing a rate do not trigger redundant native churn.
  int? _lastFollowedSampleRate;

  /// Per-song EQ override backup: the global preset active before a per-song
  /// override is applied. Restored when a track without an override starts,
  /// so a per-song curve never leaks into the rest of the queue.
  EqPreset? _globalEqBackup;
  HeadphoneProfile? _globalHeadphoneProfileBackup;
  bool _perSongOverrideActive = false;

  /// Idempotence key for per-track sync (AB loop, bookmark, rating, per-song
  /// EQ/volume). Both onTrackChanged and mediaItem can fire for one change
  /// and in either order — without this the second path would double-apply
  /// (or, worse, the first path wins the race and the second skips the reset
  /// entirely, leaving the previous song's AB/EQ on the new song).
  ///
  /// The guard is time-bounded rather than id-only: two listeners for the SAME
  /// change fire within milliseconds and are deduped, while a genuine replay of
  /// the same song id (repeat-one / duplicate queue entry) happens well after
  /// the window and re-runs the reset.
  int? _lastPerTrackSyncSongId;
  DateTime? _lastPerTrackSyncAt;

  /// Guards playbackState echoes against optimistic UI:
  /// - a transient loading/buffering `playing:false` must not regress an
  ///   optimistic `isPlaying:true` from playSong (flash paused);
  /// - a stale speed echo must not clobber a just-set speed.
  double? _lastSpeedPushed;
  DateTime? _lastSpeedPushAt;

  /// Bumped on every queue mutation. [_getNextTitles]'s cache is keyed by
  /// index/length/current song, none of which changes when songs AFTER the
  /// current one are reordered - the version counter is what actually
  /// invalidates it.
  int _queueVersion = 0;

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
    SmartAudioService? smartAudioService,
    PlaybackLatencyTracker? latencyTracker,
    PerSongEqStore? perSongEqStore,
    PerSongVolumeStore? perSongVolumeStore,
    SongRatingStore? songRatingStore,
    SponsorBlockService? sponsorBlockService,
    QuranModeService? quranModeService,
    EarbudOptimizationService? earbudOptimizationService,
    LrclibService? lrclibService,
    YtmAccountService? ytmAccountService,
    MediaScannerService? mediaScannerService,
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
        _smartAudioService = smartAudioService ??
            (getIt.isRegistered<SmartAudioService>()
                ? getIt<SmartAudioService>()
                : SmartAudioService()),
        _latencyTracker = latencyTracker ??
            (getIt.isRegistered<PlaybackLatencyTracker>()
                ? getIt<PlaybackLatencyTracker>()
                : null),
        _perSongEqStore = perSongEqStore ??
            (getIt.isRegistered<PerSongEqStore>()
                ? getIt<PerSongEqStore>()
                : PerSongEqStore()),
        _perSongVolumeStore = perSongVolumeStore ??
            (getIt.isRegistered<PerSongVolumeStore>()
                ? getIt<PerSongVolumeStore>()
                : PerSongVolumeStore()),
        _songRatingStore = songRatingStore ??
            (getIt.isRegistered<SongRatingStore>()
                ? getIt<SongRatingStore>()
                : SongRatingStore()),
        _sponsorBlockService = sponsorBlockService ??
            (getIt.isRegistered<SponsorBlockService>()
                ? getIt<SponsorBlockService>()
                : SponsorBlockService.instance),
        _quranModeService = quranModeService ??
            (getIt.isRegistered<QuranModeService>()
                ? getIt<QuranModeService>()
                : null),
        _earbudOptimizationService = earbudOptimizationService ??
            (getIt.isRegistered<EarbudOptimizationService>()
                ? getIt<EarbudOptimizationService>()
                : null),
        _lrclibService = lrclibService ??
            (getIt.isRegistered<LrclibService>()
                ? getIt<LrclibService>()
                : null),
        _ytmAccountService = ytmAccountService ??
            (getIt.isRegistered<YtmAccountService>()
                ? getIt<YtmAccountService>()
                : null),
        _mediaScannerService = mediaScannerService ??
            (getIt.isRegistered<MediaScannerService>()
                ? getIt<MediaScannerService>()
                : null),
        super(const PlayerState()) {
    // Share fallback instances process-wide so the handler (which resolves
    // the same types via getIt) never operates on a divergent throwaway
    // copy when DI isn't set up (tests / manual construction).
    if (!getIt.isRegistered<PerSongEqStore>()) {
      try {
        getIt.registerSingleton<PerSongEqStore>(_perSongEqStore);
      } catch (_) {}
    }
    if (!getIt.isRegistered<PerSongVolumeStore>()) {
      try {
        getIt.registerSingleton<PerSongVolumeStore>(_perSongVolumeStore);
      } catch (_) {}
    }
    if (!getIt.isRegistered<SongRatingStore>()) {
      try {
        getIt.registerSingleton<SongRatingStore>(_songRatingStore);
      } catch (_) {}
    }
    if (!getIt.isRegistered<SponsorBlockService>()) {
      try {
        getIt.registerSingleton<SponsorBlockService>(_sponsorBlockService);
      } catch (_) {}
    }
    _listenToAudioService();
    _loadPlaybackSpeed();
    _loadPlaybackPitch();
    _listenToSettings();
    _listenToWidgetClicks();
    _syncAudioEffects();
    // Re-sync effect state once the handler finishes its async init: the
    // sync above can race the preference restore and read pre-restore
    // defaults, leaving toggles showing OFF for saved-ON stages.
    _audioHandler.effectsReady.then((_) async {
      if (isClosed) return;
      _syncAudioEffects();
      await _restoreQuranMode();
      // ReplayGain re-apply: with the fully restored session (song tags +
      // cached prefs) a restored 'on' gain mode must be actually audible,
      // not just displayed as enabled.
      await _audioHandler.setVolume(_audioHandler.volume);
    }).catchError((Object e, StackTrace st) {
      ErrorLogger.log('Post-init effects re-sync failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    });
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
      isVirtualizerSupported: _audioHandler.isVirtualizerSupported,
      // Effective dynamics: enabled AND not bypassed, so the toggle can never
      // show ON while the native stage is muted by the bypass.
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
      _audioHandler.setGaplessEnabled(settingsCubit.state.gaplessPlayback);
      autoSub(settingsCubit.stream, (settingsState) {
        _audioHandler.setCrossfadeDuration(
          Duration(
              milliseconds: (settingsState.crossfadeSeconds * 1000).round()),
        );
        // Persisted gapless toggle actually selects the gapless engine.
        _audioHandler.setGaplessEnabled(settingsState.gaplessPlayback);
        // Re-apply gain when ReplayGain settings change
        _audioHandler.setVolume(_audioHandler.volume);
        // T2: when follow-track is toggled on mid-track, (re)apply it now. The
        // de-dupe inside the helper keeps repeated settings emissions cheap.
        if (settingsState.followTrackSampleRate) {
          final song = state.currentSong;
          if (song != null) unawaited(_maybeFollowTrackSampleRate(song));
        }
      });
    }
  }

  /// T2: request the current track's native sample rate when the preference is
  /// on. Pure decision (de-dupe + Bluetooth skip) lives in
  /// [HiResAudioService.followTrackRateToApply]; this method owns the side
  /// effect and the last-requested bookkeeping.
  Future<void> _maybeFollowTrackSampleRate(SongsTableData song) async {
    final service = _hiResAudioService;
    final settings = _settingsCubit?.state;
    if (service == null || settings == null) return;
    final rate = HiResAudioService.followTrackRateToApply(
      trackSampleRate: song.sampleRate,
      lastRequestedSampleRate: _lastFollowedSampleRate,
      isBluetooth: settings.currentOutputDevice?.isBluetooth == true,
      followTrackEnabled:
          settings.followTrackSampleRate || settings.strictBitPerfect,
    );
    if (rate == null) return;
    _lastFollowedSampleRate = rate;
    try {
      final depth = song.bitDepth ?? 0;
      await service.setTargetOutputFormat(sampleRate: rate, bitDepth: depth);
      if (isClosed) return;
      await _settingsCubit?.refreshOutputDevice();
    } catch (e, st) {
      ErrorLogger.log('Follow-track sample rate failed ($rate)',
          error: e, stackTrace: st, category: 'PlayerCubit');
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
          'onlineSongs': entry.value.songs
              .where((s) => s.source == SongSource.youtube || s.id < 0)
              .map((s) => {
                    'id': s.id,
                    'title': s.title,
                    'artist': s.artist,
                    'album': s.album,
                    'durationMs': s.durationMs,
                    'path': s.path,
                    'source': s.source,
                    'remoteId': s.remoteId,
                    'remoteArtworkUrl': s.remoteArtworkUrl,
                  })
              .toList(),
          'currentIndex': entry.value.currentIndex,
          'positionMs': entry.value.position.inMilliseconds,
          'speed': entry.value.speed,
        };
      }
      // Which slot is active is part of the session: without it a restart
      // labels the restored queue as slot 0, and the next queue edit writes
      // over slot 0's saved contents.
      data['activeSlot'] = state.activeQueueSlot;
      final encoded = await compute(jsonEncode, data);
      await prefs.setString(PrefsKeys.queueSlots, encoded);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist queue slots',
          error: e, stackTrace: st, category: 'PlayerCubit');
      // Don't clobber a more important error (e.g. 'Failed to play X').
      if (!isClosed && state.errorMessage == null) {
        safeEmit(state.copyWith(errorMessage: 'Failed to save queue'));
      }
    }
  }

  Future<void> _restoreQueueSlots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queueRestorationDone) return;
      final raw = prefs.getString(PrefsKeys.queueSlots);
      if (raw == null) return;
      final decoded = await compute(jsonDecode, raw);
      if (decoded is! Map<String, dynamic>) return;
      final data = decoded;
      // Validate: reject oversized slots (DoS). Three slots + activeSlot key.
      if (data.length > 4) return;
      for (final key in data.keys) {
        if (_queueRestorationDone) return;
        final slotIndex = int.tryParse(key);
        if (slotIndex == null || slotIndex < 0 || slotIndex > 2) continue;
        // One corrupt slot must not abort the others.
        final rawSlot = data[key];
        if (rawSlot is! Map) continue;
        final slotData = Map<String, dynamic>.from(rawSlot);
        final rawIds = (slotData['songIds'] as List<dynamic>?) ?? [];
        if (rawIds.length > _maxQueueSize) continue;
        final songIds = rawIds.whereType<int>().toList();
        if (songIds.isEmpty) continue;
        final songsResult = await _repository.getSongsByIds(songIds);
        if (_queueRestorationDone) return;
        // getSongsByIds returns rows in unspecified (rowid) order; re-map to
        // the persisted songIds order so the restored slot keeps the real
        // playback order (previous / current / next) instead of id order.
        final songsMap = {
          for (final s in songsResult.fold((_) => <SongsTableData>[], (r) => r))
            s.id: s
        };
        final onlineSongsList =
            (slotData['onlineSongs'] as List<dynamic>?) ?? [];
        final onlineSongsMap = <int, SongsTableData>{};
        for (final item in onlineSongsList) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final id = m['id'] as int?;
            if (id != null) {
              onlineSongsMap[id] = SongsTableData(
                id: id,
                title: m['title'] as String? ?? 'Unknown',
                artist: m['artist'] as String? ?? 'Unknown Artist',
                album: m['album'] as String? ?? '',
                durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
                path: m['path'] as String? ?? '',
                source: m['source'] as String? ?? SongSource.youtube,
                remoteId: m['remoteId'] as String?,
                remoteArtworkUrl: m['remoteArtworkUrl'] as String?,
                isFavorite: false,
                isMissing: false,
                isDownloaded: false,
                playCount: 0,
                lastPositionMs: 0,
              );
            }
          }
        }
        final songs = [
          for (final id in songIds)
            if (songsMap[id] != null)
              songsMap[id]!
            else if (onlineSongsMap[id] != null)
              onlineSongsMap[id]!,
        ];
        if (songs.isEmpty) continue;
        final restoredPosMs = (slotData['positionMs'] as num?)?.toInt() ?? 0;
        final restoredSpeed = (slotData['speed'] as num?)?.toDouble() ?? 1.0;
        _queueSlots[slotIndex] = _QueueSlotData(
          songs: songs,
          currentIndex: ((slotData['currentIndex'] as int?) ?? 0)
              .clamp(0, songs.length - 1),
          position:
              Duration(milliseconds: restoredPosMs.clamp(0, 24 * 3600 * 1000)),
          speed: restoredSpeed.isFinite ? restoredSpeed.clamp(0.1, 8.0) : 1.0,
        );
      }
      if (!_queueRestorationDone && !isClosed) {
        final activeRaw = data['activeSlot'];
        if (activeRaw is int && activeRaw >= 0 && activeRaw <= 2) {
          safeEmit(state.copyWith(activeQueueSlot: activeRaw));
        }
      }
      _queueRestorationDone = true;
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
      _pendingScrobbleSong = null;
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

    // Minor progress tick: schedule debounced flush with the LATEST position.
    // The timer callback reads the pending snapshot at fire time instead of
    // the first tick's captured values, so the flush is never up to 5s stale.
    _pendingScrobbleSong = song;
    _pendingScrobblePosMs = posMs;
    _pendingScrobbleIsPlaying = isPlaying;
    _scrobbleDebounce ??= autoTimer(Timer(_scrobbleInterval, () {
      if (isClosed) return;
      final pendingSong = _pendingScrobbleSong;
      if (pendingSong != null) {
        _scrobblerService?.notifyPlaybackState(
          id: pendingSong.id,
          artist: pendingSong.artist,
          track: pendingSong.title,
          album: pendingSong.album,
          durationMs: pendingSong.durationMs,
          positionMs: _pendingScrobblePosMs,
          isPlaying: _pendingScrobbleIsPlaying,
        );
      }
      _pendingScrobbleSong = null;
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
    if (_cachedQueueVersion == _queueVersion &&
        _cachedNextTitlesIndex == s.currentIndex &&
        _cachedQueueLength == s.queue.length &&
        _cachedCurrentSongId == s.currentSong?.id) {
      return _cachedNextTitles;
    }
    _cachedQueueVersion = _queueVersion;
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

  /// Monotonic per-event counter for handler-queue syncs: only the most
  /// recent queue event may apply its resolved songs. Guarding this with
  /// [_mediaItemResolutionGen] used to abort the sync whenever a concurrent
  /// mediaItem/track resolution bumped that generation, leaving the queue
  /// view stale (or empty after a cold-start session restore).
  int _queueSyncGen = 0;
  bool _handlerQueueHasEverEmittedNonEmpty = false;

  bool _isSameQueue(List<SongsTableData> a, List<SongsTableData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_isSameTrack(a[i], b[i])) return false;
    }
    return true;
  }

  /// Resolves the now-playing index from a playbackState snapshot. The
  /// handler's queueIndex is only trustworthy when the handler queue and the
  /// state queue agree: during playSong's optimistic window an old queueIndex
  /// clamped into the new queue pointed the highlight at a plausible-looking
  /// wrong row. When they disagree, keep the state's own index - the
  /// onTrackChanged/mediaItem listeners re-derive it from the actual song.
  int _resolvePlaybackStateIndex(PlaybackState playbackState) {
    final handlerIndex = playbackState.queueIndex;
    if (state.queue.isEmpty) {
      return 0;
    }
    if (handlerIndex != null &&
        handlerIndex >= 0 &&
        handlerIndex < state.queue.length) {
      final current = state.currentSong;
      if (current == null || _isSameTrack(state.queue[handlerIndex], current)) {
        return handlerIndex;
      }
    }
    return state.currentIndex.clamp(0, state.queue.length - 1);
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
          : (isSameSong ? state.duration : Duration.zero);

      safeEmit(
        state.copyWith(
          currentSong: song,
          currentIndex: effectiveIndex,
          duration: duration,
          position: isSameSong ? state.position : Duration.zero,
          errorMessage: null,
          lyrics: isSameSong ? state.lyrics : [],
          lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
          isLoadingLyrics: !isSameSong,
        ),
      );

      if (!isSameSong) {
        unawaited(_loadLyricsForSong(song));
        unawaited(_enrichAudioQuality(song, gen));
        // Gapless advances fire onTrackChanged without a fresh mediaItem;
        // without this the previous track's SponsorBlock segments stay armed.
        unawaited(_loadSponsorBlockSegments(song, gen));
        unawaited(_loadCueChapters(song));
        unawaited(_maybeFollowTrackSampleRate(song));
      }
      _updateWidgetThrottled(force: true);
      _debouncedScrobble(song, state.position, state.isPlaying);
      if (!isSameSong) {
        unawaited(_syncPerTrackState(song));
      }
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
            if (gen != _mediaItemResolutionGen || isClosed) return;
            final isSameSong = _isSameTrack(state.currentSong, resolvedSong);
            final duration =
                (item.duration != null && item.duration! > Duration.zero)
                    ? item.duration!
                    : (resolvedSong!.durationMs > 0
                        ? Duration(milliseconds: resolvedSong!.durationMs)
                        : (isSameSong ? state.duration : Duration.zero));
            final songQueueIndex =
                state.queue.indexWhere((s) => _isSameTrack(s, resolvedSong));
            final effectiveIndex =
                songQueueIndex != -1 ? songQueueIndex : state.currentIndex;

            safeEmit(
              state.copyWith(
                currentSong: resolvedSong,
                currentIndex: effectiveIndex,
                duration: duration,
                position: isSameSong ? state.position : Duration.zero,
                errorMessage: null,
                lyrics: isSameSong ? state.lyrics : [],
                lyricsSource:
                    isSameSong ? state.lyricsSource : LyricsSource.none,
                isLoadingLyrics: !isSameSong,
              ),
            );

            if (gen != _mediaItemResolutionGen || isClosed) return;

            if (!isSameSong) {
              unawaited(_loadLyricsForSong(resolvedSong!));
              unawaited(_enrichAudioQuality(resolvedSong!, gen));
              unawaited(_loadSponsorBlockSegments(resolvedSong!, gen));
              unawaited(_loadCueChapters(resolvedSong!));
              unawaited(_maybeFollowTrackSampleRate(resolvedSong!));
              unawaited(_syncPerTrackState(resolvedSong!));
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
      if (mediaItems.isEmpty) {
        if (_handlerQueueHasEverEmittedNonEmpty) {
          safeEmit(state.copyWith(
            queue: [],
            currentIndex: 0,
            currentSong: null,
            duration: Duration.zero,
            position: Duration.zero,
            lyrics: [],
            isLoadingLyrics: false,
            cueChapters: const [],
            currentCueIndex: 0,
          ));
        }
        return;
      }
      _handlerQueueHasEverEmittedNonEmpty = true;
      final gen = ++_queueSyncGen;
      final ids =
          mediaItems.map((m) => int.tryParse(m.id)).whereType<int>().toList();
      if (ids.isEmpty) return;

      final songsRes = await _repository.getSongsByIds(ids);
      if (isClosed || gen != _queueSyncGen) return;

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
            source: (m.extras?['source'] as String?) ?? SongSource.youtube,
            remoteId: m.extras?['remoteId'] as String?,
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
      if (isClosed || gen != _queueSyncGen) return;
      if (restoredSongs.isNotEmpty &&
          !_isSameQueue(state.queue, restoredSongs)) {
        // Re-anchor the highlight to the running song: at cold start the
        // queue sync can land after the mediaItem resolution, and the stale
        // index would mark the wrong row as "now playing".
        final current = state.currentSong;
        final anchoredIndex = current == null
            ? -1
            : restoredSongs.indexWhere((s) => _isSameTrack(s, current));
        final safeIndex =
            (anchoredIndex != -1 ? anchoredIndex : state.currentIndex)
                .clamp(0, restoredSongs.length - 1);
        safeEmit(state.copyWith(
          queue: restoredSongs,
          currentIndex: safeIndex,
        ));
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
      final wasRepeat = state.repeatMode;

      // Transient loading/buffering echoes report playing:false while the
      // engine is actually spinning up after an optimistic playSong(true).
      // Regressing here flashes the UI to paused for one frame.
      var resolvedPlaying = isPlaying;
      if (!isPlaying &&
          state.isPlaying &&
          (playbackState.processingState == AudioProcessingState.loading ||
              playbackState.processingState ==
                  AudioProcessingState.buffering)) {
        resolvedPlaying = true;
      }
      // Stale speed echo guard: within 500ms of a local setPlaybackSpeed,
      // only accept the echo if it matches what was pushed.
      var resolvedSpeed = playbackState.speed;
      if (_lastSpeedPushAt != null &&
          _lastSpeedPushed != null &&
          DateTime.now().difference(_lastSpeedPushAt!) <
              const Duration(milliseconds: 500) &&
          (resolvedSpeed - _lastSpeedPushed!).abs() > 1e-9) {
        resolvedSpeed = state.playbackSpeed;
      }
      final resolvedShuffle =
          playbackState.shuffleMode == AudioServiceShuffleMode.all;
      final resolvedIndex = _resolvePlaybackStateIndex(playbackState);
      if (resolvedPlaying == state.isPlaying &&
          effectivePos == state.position &&
          resolvedShuffle == state.isShuffle &&
          repeat == state.repeatMode &&
          resolvedIndex == state.currentIndex &&
          (resolvedSpeed - state.playbackSpeed).abs() < 1e-9) {
        return;
      }
      safeEmit(
        state.copyWith(
          isPlaying: resolvedPlaying,
          position: effectivePos,
          isShuffle: resolvedShuffle,
          repeatMode: repeat,
          currentIndex: resolvedIndex,
          playbackSpeed: resolvedSpeed,
        ),
      );
      if (resolvedPlaying != wasPlaying || repeat != wasRepeat) {
        _updateWidgetThrottled(force: true);
      } else {
        _updateWidgetProgressThrottled();
      }
      final currentSong = state.currentSong;
      if (currentSong != null) {
        _debouncedScrobble(currentSong, effectivePos, isPlaying);
      }
    });

    // Latency-compensated positions keep lyric highlights in sync with
    // audible DSP output. Older handler doubles (tests) may not implement
    // compensatedPositionStream — fall back to the raw position stream.
    Stream<Duration> positionUpdates;
    try {
      positionUpdates = _audioHandler.compensatedPositionStream;
    } catch (_) {
      positionUpdates = _audioHandler.positionStream;
    }
    autoSub(
      positionUpdates.throttleTime(const Duration(milliseconds: 200),
          trailing: true),
      (pos) {
        _checkSponsorBlockSkip(pos);
        safeEmit(state.copyWith(position: pos));
        if (state.isPlaying) {
          _updateWidgetProgressThrottled();
          // Keep the active slot's restore position near-live. It used to be
          // written only at queue-mutation time, so an app kill mid-song
          // resumed from the last mutation's position (often 0:00).
          _queueSlots[state.activeQueueSlot] = _QueueSlotData(
            songs: state.queue,
            currentIndex: state.currentIndex,
            position: pos,
            speed: state.playbackSpeed,
          );
          final slotNow = DateTime.now();
          if (_lastSlotPersistAt == null ||
              slotNow.difference(_lastSlotPersistAt!) >=
                  const Duration(seconds: 15)) {
            _lastSlotPersistAt = slotNow;
            _debouncedPersistQueueSlots();
          }
        }
      },
    );

    autoSub(_audioHandler.sleepTimerRemainingStream, (remaining) {
      safeEmit(state.copyWith(sleepTimerRemaining: remaining));
    });

    if (_audioHandler.currentAudioSessionId != null) {
      safeEmit(
          state.copyWith(audioSessionId: _audioHandler.currentAudioSessionId));
    }
    autoSub(_audioHandler.audioSessionIdStream, (id) {
      safeEmit(state.copyWith(audioSessionId: id));
    });
  }

  Future<void> _loadSponsorBlockSegments(SongsTableData song, int gen) async {
    // F-67: respect the persisted enable flag; the service loads it lazily.
    await _sponsorBlock.loadPreferences();
    if (!_sponsorBlock.isEnabled) {
      _currentSponsorSegments = const [];
      _sponsorSegmentsVideoId = null;
      _lastSkippedSegmentEnd = null;
      return;
    }
    // Offline-only mode disables all network lookups including SponsorBlock.
    if (_settingsCubit?.state.offlineOnlyMode == true) {
      _currentSponsorSegments = const [];
      _sponsorSegmentsVideoId = null;
      _lastSkippedSegmentEnd = null;
      return;
    }
    final videoId = (song.remoteId != null && song.remoteId!.isNotEmpty)
        ? song.remoteId!
        : (song.path.startsWith('ytmusic://')
            ? song.path.replaceFirst('ytmusic://', '').split('?').first
            : null);
    if (videoId == null || videoId.isEmpty) {
      _currentSponsorSegments = const [];
      _sponsorSegmentsVideoId = null;
      _lastSkippedSegmentEnd = null;
      return;
    }
    if (_sponsorSegmentsVideoId == videoId &&
        _currentSponsorSegments.isNotEmpty) {
      return;
    }
    // Clear synchronously BEFORE any await. The mediaItem and onTrackChanged
    // listeners share _mediaItemResolutionGen, so whichever fires last on a
    // track change invalidates this fetch; without this clear, the aborted
    // fetch left the previous song's segments armed and the skip checker
    // seeked the new song to positions meaningless for it.
    _currentSponsorSegments = const [];
    _sponsorSegmentsVideoId = null;
    _lastSkippedSegmentEnd = null;

    try {
      final service = _sponsorBlock;
      final segments = await service.getSegments(videoId);
      if (isClosed || gen != _mediaItemResolutionGen) return;
      _currentSponsorSegments = segments;
      _sponsorSegmentsVideoId = videoId;
      _lastSkippedSegmentEnd = null;
    } catch (_) {}
  }

  /// Loads the chapter list for a song expanded from a CUE sheet, so the
  /// advanced bar / song info can render and tap-to-seek the image's tracks.
  Future<void> _loadCueChapters(SongsTableData song) async {
    if (song.cueFile == null || song.cueStartMs == null) {
      if (state.cueChapters.isEmpty && state.currentCueIndex == 0) return;
      safeEmit(state.copyWith(cueChapters: const [], currentCueIndex: 0));
      return;
    }
    try {
      final chapters = await CueParser.findAndParseCue(song.path);
      if (isClosed || !_isSameTrack(state.currentSong, song)) return;
      final index = chapters.indexWhere((c) => c.index == song.trackNumber);
      safeEmit(state.copyWith(
        cueChapters: chapters,
        currentCueIndex: index < 0 ? 0 : index,
      ));
    } catch (e, st) {
      ErrorLogger.log('Failed to load cue chapters for ${song.path}',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  void _checkSponsorBlockSkip(Duration pos) {
    if (_currentSponsorSegments.isEmpty || !state.isPlaying) return;
    // F-67: gate auto-skip on the persisted enable flag and enabled categories.
    final service = _sponsorBlock;
    if (!service.isEnabled) return;
    final enabledCategories = service.enabledCategories;
    final now = DateTime.now();
    if (_lastSponsorSkipTime != null &&
        now.difference(_lastSponsorSkipTime!).inMilliseconds < 1500) {
      return;
    }
    for (final segment in _currentSponsorSegments) {
      if (!enabledCategories.contains(segment.category)) continue;
      if (segment.contains(pos)) {
        if (_lastSkippedSegmentEnd != null &&
            (_lastSkippedSegmentEnd == segment.end ||
                (pos - _lastSkippedSegmentEnd!).abs() <
                    const Duration(seconds: 2))) {
          continue;
        }
        // Chain adjacent/overlapping segments (contains is [start, end)):
        // skipping to this segment's end must not land inside the next one,
        // or the next tick would either re-skip or be suppressed by the
        // adjacent-segment guard above.
        var target = segment.end;
        var chained = true;
        while (chained) {
          chained = false;
          for (final other in _currentSponsorSegments) {
            if (other.end > target && other.contains(target)) {
              target = other.end;
              chained = true;
            }
          }
        }
        _lastSkippedSegmentEnd = target;
        _lastSponsorSkipTime = now;
        debugPrint(
            '[SPONSORBLOCK] Auto-skipping segment (${segment.category}): ${segment.start} -> $target');
        final seekTarget = target + const Duration(milliseconds: 50);
        _audioHandler.seek(seekTarget);
        // Optimistic position update: the throttled position stream would
        // otherwise keep reporting in-segment positions for up to 200ms.
        safeEmit(state.copyWith(position: seekTarget));
        break;
      }
    }
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
    final scanner = _mediaScannerService;
    if (scanner == null) return;
    try {
      await scanner.enrichAudioQuality(song.id, path);
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

    // Check central in-memory cache first, including a valid negative entry
    // (a recently-proven miss) so a local track with no lyrics does not re-run
    // embedded reads plus a 5s LRCLIB round-trip on every play. `refreshLyrics`
    // invalidates explicitly; the negative-cache TTL bounds the rest.
    if (LrcParser.hasCachedLyrics(songId: song.id, path: song.path)) {
      final cached =
          LrcParser.getCachedLyrics(songId: song.id, path: song.path);
      ++_lyricsLoadGen;
      if (_isSameTrack(state.currentSong, song)) {
        safeEmit(state.copyWith(
          isLoadingLyrics: false,
          lyrics: cached?.lines ?? const [],
          lyricsSource: cached?.source ?? LyricsSource.none,
        ));
      }
      return;
    }

    final gen = ++_lyricsLoadGen;
    safeEmit(state.copyWith(
      isLoadingLyrics: true,
      lyrics: [],
      lyricsSource: LyricsSource.none,
    ));

    // Offline-only mode disables every network lyrics lookup (LRCLIB, YTM).
    // It also means any miss below is non-authoritative, so it must not be
    // negative-cached — otherwise going back online would keep reporting
    // "no lyrics" for the TTL.
    final offlineOnly = _settingsCubit?.state.offlineOnlyMode == true;

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

      // 2. Query LRCLIB for synchronized karaoke lyrics (works for local and online tracks).
      // If local source only produced plain unsynced text, still attempt to fetch synced LRC.
      final hasSynced = lyricsResult != null &&
          lyricsResult.lines.isNotEmpty &&
          lyricsResult.isSynced;

      if (!hasSynced && !offlineOnly) {
        final plainFallback = lyricsResult;
        final lrclib = _lrclibService;
        if (lrclib != null) {
          try {
            final onlineResult = await lrclib
                .fetchLyrics(
                  trackName: song.title,
                  artistName: song.artist,
                  albumName: song.album,
                  durationSeconds:
                      song.durationMs > 0 ? song.durationMs ~/ 1000 : null,
                )
                .timeout(const Duration(seconds: 5), onTimeout: () => null);

            if (onlineResult != null && onlineResult.lines.isNotEmpty) {
              // Prefer synced online lyrics; if unsynced, only prefer if we had nothing
              if (onlineResult.isSynced ||
                  plainFallback == null ||
                  plainFallback.lines.isEmpty) {
                lyricsResult = onlineResult;
              }
            }
          } catch (e, st) {
            ErrorLogger.log('LRCLIB fetch error for ${song.title}',
                error: e, stackTrace: st, category: 'Lyrics');
          }
        }
      }

      if (isClosed ||
          gen != _lyricsLoadGen ||
          !_isSameTrack(state.currentSong, song)) {
        return;
      }

      // 3. For YouTube Music tracks without LRCLIB matches, fetch native YTM lyrics
      final videoId = song.remoteId;
      if (!offlineOnly &&
          (lyricsResult == null || lyricsResult.lines.isEmpty) &&
          videoId != null &&
          videoId.isNotEmpty) {
        final ytmAccount = _ytmAccountService;
        if (ytmAccount != null) {
          try {
            lyricsResult = await ytmAccount
                .fetchYtmLyrics(videoId)
                .timeout(const Duration(seconds: 5), onTimeout: () => null);
          } catch (e, st) {
            ErrorLogger.log('YTM lyrics fetch error for $videoId',
                error: e, stackTrace: st, category: 'Lyrics');
          }
        }
      }

      // Cache the resolved result, including null for negative caching, so a
      // miss on any source (local or online) is not re-resolved on every play.
      // Skip negative caching while offline: the miss reflects "could not
      // check", not "no lyrics exist".
      if (lyricsResult != null || !offlineOnly) {
        LrcParser.cacheLyricsResult(
          lyricsResult,
          songId: song.id,
          path: song.path,
        );
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
      LrcParser.invalidateSong(songId: song.id, path: song.path);
      await _loadLyricsForSong(song);
    }
  }

  /// Applies user-edited lyrics for the current song (F-31).
  ///
  /// Updates in-memory state and, for local files with a real path, writes a
  /// sidecar `.lrc` next to the audio file so the edit survives restarts.
  /// Returns true when the sidecar was persisted; false means the change is
  /// session-only (e.g. online tracks or a write failure).
  Future<bool> updateLyrics(List<LyricsLine> lines) async {
    // Discard any in-flight loader so its late result cannot overwrite this edit.
    ++_lyricsLoadGen;
    final source =
        lines.isNotEmpty ? LyricsSource.externalLrc : LyricsSource.none;
    safeEmit(state.copyWith(
      lyrics: lines,
      lyricsSource: source,
      isLoadingLyrics: false,
    ));

    final song = state.currentSong;
    if (song == null) return false;

    LrcParser.invalidateSong(songId: song.id, path: song.path);

    final path = song.path;
    final isLocal = song.source == SongSource.local &&
        path.isNotEmpty &&
        !path.startsWith('http') &&
        !path.startsWith('ytmusic://');
    if (!isLocal) {
      LrcParser.cacheLyricsResult(
        LyricsResult(lines: lines, source: source),
        songId: song.id,
        path: path,
      );
      return false;
    }

    try {
      final file = File(path);
      final dir = file.parent;
      final baseName = path.split(RegExp(r'[\\/]')).last;
      final dot = baseName.lastIndexOf('.');
      final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
      final sidecar = File('${dir.path}${Platform.pathSeparator}$stem.lrc');
      await sidecar.writeAsString(LrcParser.formatToLrc(lines), flush: true);
      LrcParser.cacheLyricsResult(
        LyricsResult(lines: lines, source: source),
        songId: song.id,
        path: path,
      );
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to persist sidecar .lrc for $path',
          error: e, stackTrace: st, category: 'Lyrics');
      return false;
    }
  }

  Future<void> playSong(SongsTableData song,
      {List<SongsTableData>? queue,
      Duration? initialPosition,
      bool openPlayerIfPlaying = true}) async {
    // If this song is already the active song, expand the player and resume if paused instead of restarting from 0:00
    if (openPlayerIfPlaying &&
        initialPosition == null &&
        _isSameTrack(state.currentSong, song)) {
      safeEmit(state.copyWith(isExpanded: true));
      if (!state.isPlaying) {
        try {
          await _audioHandler.play();
        } catch (e, st) {
          // Was unguarded: an expired online stream turned a resume tap into
          // an unhandled exception.
          ErrorLogger.log('Resume of current song failed',
              error: e, stackTrace: st, category: 'PlayerCubit');
          if (!isClosed) {
            safeEmit(
                state.copyWith(errorMessage: 'Failed to play ${song.title}'));
          }
        }
      }
      return;
    }
    // Task 0: start latency tracking from tap
    final videoIdForLatency = song.remoteId ?? song.id.toString();
    try {
      _latencyTracker?.start(videoId: videoIdForLatency);
      _latencyTracker?.markStage(PlaybackStage.tap);
    } catch (_) {}
    // P0-2: Speculative resolution on tap: begin resolving URL in background immediately
    try {
      _audioHandler.streamPreResolver.onTrackEnqueuedOrTapped(song);
    } catch (_) {}
    ++_mediaItemResolutionGen;
    final capturedGen = _mediaItemResolutionGen;
    // Dedicated token for the async downloaded-twin swap. It must NOT share
    // _mediaItemResolutionGen: the handler's own onTrackChanged bump for the
    // navigation that started this playSong would otherwise cancel every swap.
    ++_localMatchSwapGen;
    final capturedSwapGen = _localMatchSwapGen;
    // Mark restoration as done: any in-flight _restoreQueueSlots must abort
    _queueRestorationDone = true;
    var rawQueue = queue != null ? List<SongsTableData>.from(queue) : [song];

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
    // Failure-rollback snapshot: everything the optimistic path below
    // mutates before loadQueue can throw.
    final prevSlot = _queueSlots[state.activeQueueSlot];
    final prevQueue = state.queue;
    final prevIndex = state.currentIndex;
    final prevSong = state.currentSong;
    final prevPosition = state.position;
    final prevDuration = state.duration;
    final prevLyrics = state.lyrics;
    final prevLyricsSource = state.lyricsSource;
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: List.from(effectiveQueue),
      currentIndex: effectiveIndex,
      position: startPos,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;

    // Immediate emission so tap feels instant: song row highlights,
    // play/pause updates to playing, and miniplayer shows the track.
    final isSameSong = _isSameTrack(state.currentSong, song);
    safeEmit(state.copyWith(
      queue: effectiveQueue,
      currentIndex: effectiveIndex,
      currentSong: song,
      isPlaying: true,
      position: startPos,
      duration: Duration(milliseconds: song.durationMs),
      errorMessage: queueTruncationWarning,
      lyrics: isSameSong ? state.lyrics : [],
      lyricsSource: isSameSong ? state.lyricsSource : LyricsSource.none,
      isLoadingLyrics: !isSameSong,
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
          if (_localMatchSwapGen != capturedSwapGen ||
              isClosed ||
              !_isSameTrack(state.currentSong, song)) {
            return;
          }
          final local = match.fold((_) => null, (s) => s);
          if (local != null &&
              (local.path.startsWith('content:') ||
                  await File(local.path).exists())) {
            if (_localMatchSwapGen != capturedSwapGen ||
                isClosed ||
                !_isSameTrack(state.currentSong, song)) {
              return;
            }
            if (local.id != song.id) {
              _audioHandler.swapReconciledSong(song.id, local);
              final swappedQueue = effectiveQueue
                  .map((s) => _isSameTrack(s, song) ? local : s)
                  .toList();
              _queueVersion++;
              safeEmit(state.copyWith(
                queue: swappedQueue,
                currentSong: local,
                // The local twin carries the real audio-header duration; the
                // optimistic emit above kept the YouTube metadata value.
                duration: local.durationMs > 0
                    ? Duration(milliseconds: local.durationMs)
                    : state.duration,
              ));
              _queueSlots[state.activeQueueSlot] = _QueueSlotData(
                songs: List.from(swappedQueue),
                currentIndex: effectiveIndex,
                position: startPos,
                speed: state.playbackSpeed,
              );
              _debouncedPersistQueueSlots();
              unawaited(_loadLyricsForSong(local));
            }
          }
        } catch (e, st) {
          // Local-match swap failed: queue would claim a local file while
          // the handler still streams YouTube. Log + surface, don't swallow.
          ErrorLogger.log('Local-match swap failed for ${song.title}',
              error: e, stackTrace: st, category: 'PlayerCubit');
          if (!isClosed && _localMatchSwapGen == capturedSwapGen) {
            safeEmit(state.copyWith(
                errorMessage: 'Local match unavailable, streaming online'));
          }
        }
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
      if (_mediaItemResolutionGen == capturedGen && !isClosed) {
        safeEmit(state.copyWith(isPlaying: true));
      }
    } catch (e) {
      try {
        _latencyTracker?.finishWithError(e, stage: PlaybackStage.sourceSet);
      } catch (_) {}
      if (isClosed || _mediaItemResolutionGen != capturedGen) {
        // Stale failure: a newer playSong already took over (its success path
        // is gen-gated; this path was not). Emitting here would pause the
        // newer song and flag an error for an abandoned request, and
        // rethrowing would deliver a rejection nobody can act on.
        ErrorLogger.log('Stale playSong failure ignored for ${song.title}',
            error: e, category: 'PlayerCubit');
        return;
      }
      // Invalidate everything captured against this request: the parallel
      // local-match swap re-checks the gen and must not re-apply the failed
      // queue after the rollback below.
      _mediaItemResolutionGen++;
      // Roll back the optimistic mutations: the unplayable queue must not
      // present itself as active, and the pending 2s persist must not write
      // the broken slot over the previously saved session. Re-scheduling the
      // persist is deliberate - if loadQueue threw late, the broken slot may
      // already be persisted, and persisting the restored slot heals that.
      _queueSlots[state.activeQueueSlot] = prevSlot ??
          const _QueueSlotData(
              songs: [], currentIndex: 0, position: Duration.zero);
      _debouncedPersistQueueSlots();
      _queueVersion++;
      safeEmit(state.copyWith(
        queue: prevQueue,
        currentIndex: prevIndex,
        currentSong: prevSong,
        isPlaying: false,
        position: prevPosition,
        duration: prevDuration,
        lyrics: prevLyrics,
        lyricsSource: prevLyricsSource,
        isLoadingLyrics: false,
        errorMessage: 'Failed to play ${song.title}',
      ));
      rethrow;
    }
    if (isClosed || _mediaItemResolutionGen != capturedGen) return;
    unawaited(_loadLyricsForSong(song));
    unawaited(_loadSponsorBlockSegments(song, capturedGen));
    _updateWidgetThrottled(force: true);
  }

  /// Plays an internet radio [station] by projecting it onto the normal queue
  /// as a synthetic pseudo-song whose `path` is the stream URL and whose id is
  /// a negative hash. The negative id keeps repository cleanup and
  /// play-history from ever treating it as a real local file; the absolute
  /// `http(s)` path is what routes it through the handler's URL source path.
  Future<void> playRadioStation(RadioStation station) async {
    if (!RadioStation.isHttpUrl(station.url)) {
      safeEmit(state.copyWith(errorMessage: 'Invalid stream URL'));
      return;
    }
    final song = SongsTableData(
      id: station.songId,
      title: station.name,
      artist: (station.genre != null && station.genre!.isNotEmpty)
          ? station.genre!
          : station.name,
      album: '',
      durationMs: 0,
      path: station.url,
      source: SongSource.local,
      remoteArtworkUrl: station.artworkUrl,
      isFavorite: false,
      isMissing: false,
      isDownloaded: false,
      playCount: 0,
      lastPositionMs: 0,
    );
    unawaited(RadioStationStore().markPlayed(
      station.id,
      DateTime.now().millisecondsSinceEpoch,
    ));
    await playSong(song);
  }

  Future<void> playNext(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      safeEmit(state.copyWith(
          errorMessage: 'Queue full ($_maxQueueSize) — cannot add more'));
      return;
    }
    try {
      await _audioHandler.insertNextInQueue(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to insert next in queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to add ${song.title}'));
      }
      return;
    }
    final updatedQueue = List<SongsTableData>.from(state.queue);
    // Same track identity as _isSameTrack (id, remoteId, or path): the raw-id
    // lookup missed the downloaded twin of an online row and let
    // cross-id duplicates through with mismatched indexes.
    final existingIdx = updatedQueue.indexWhere((s) => _isSameTrack(s, song));
    final targetSlot = (state.currentIndex + 1).clamp(0, updatedQueue.length);
    if (existingIdx != -1) {
      if (existingIdx != state.currentIndex && existingIdx != targetSlot) {
        final item = updatedQueue.removeAt(existingIdx);
        final adjustedTarget =
            targetSlot > existingIdx ? targetSlot - 1 : targetSlot;
        updatedQueue.insert(adjustedTarget.clamp(0, updatedQueue.length), item);
      }
    } else {
      updatedQueue.insert(targetSlot, song);
    }
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> addToQueue(SongsTableData song) async {
    if (state.queue.length >= _maxQueueSize) {
      safeEmit(state.copyWith(
          errorMessage: 'Queue full ($_maxQueueSize) — cannot add more'));
      return;
    }
    try {
      await _audioHandler.addToQueueEnd(song);
    } catch (e, st) {
      ErrorLogger.log('Failed to add to queue end',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to add ${song.title}'));
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
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue));
  }

  Future<void> clearQueue() async {
    try {
      await _audioHandler.clearQueue();
    } catch (e, st) {
      ErrorLogger.log('Failed to clear queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to clear queue'));
      }
      return;
    }
    final current = state.currentSong;
    final updatedQueue = current != null ? [current] : <SongsTableData>[];
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: 0,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: 0));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex > state.queue.length) {
      return;
    }
    try {
      await _audioHandler.reorderQueue(oldIndex, newIndex);
    } catch (e, st) {
      ErrorLogger.log('Failed to reorder queue',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to reorder queue'));
      }
      return;
    }
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
    _queueVersion++;
    safeEmit(state.copyWith(queue: updatedQueue, currentIndex: updatedIndex));
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.removeQueueItemAt(index);
    } catch (e, st) {
      ErrorLogger.log('Failed to remove queue item',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Failed to remove track'));
      }
      return;
    }
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
    if (index == state.currentIndex) {
      // Removing the playing item: the handler rebuilds at the same clamped
      // index (removeQueueItemAt) and emits the new current via mediaItem,
      // but until that lands currentIndex pointed at the next song while
      // currentSong still held the removed one. Pre-empt with the same
      // arithmetic the handler uses, including the empty case.
      _queueVersion++;
      if (updatedQueue.isEmpty) {
        // The handler stops and emits a null mediaItem for this case.
        _queueSlots[state.activeQueueSlot] = _QueueSlotData(
            songs: const [],
            currentIndex: 0,
            position: Duration.zero,
            speed: state.playbackSpeed);
        _debouncedPersistQueueSlots();
        safeEmit(state.copyWith(
          queue: const [],
          currentIndex: 0,
          currentSong: null,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
        ));
        _updateWidgetThrottled(force: true);
        return;
      }
      final newCurrent = updatedQueue[updatedIndex];
      final sameTrack = _isSameTrack(state.currentSong, newCurrent);
      _queueVersion++;
      _queueSlots[state.activeQueueSlot] = _QueueSlotData(
        songs: updatedQueue,
        currentIndex: updatedIndex,
        position: Duration.zero,
        speed: state.playbackSpeed,
      );
      _debouncedPersistQueueSlots();
      safeEmit(state.copyWith(
        queue: updatedQueue,
        currentIndex: updatedIndex,
        currentSong: newCurrent,
        position: Duration.zero,
        duration: Duration(milliseconds: newCurrent.durationMs),
        lyrics: sameTrack ? state.lyrics : [],
        lyricsSource: sameTrack ? state.lyricsSource : LyricsSource.none,
        isLoadingLyrics: !sameTrack,
      ));
      // The upcoming mediaItem emission sees isSameSong == true and skips
      // the lyrics load, so start it here.
      unawaited(_loadLyricsForSong(newCurrent));
      _updateWidgetThrottled(force: true);
      return;
    }
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: updatedQueue,
      currentIndex: updatedIndex,
      position: state.position,
      speed: state.playbackSpeed,
    );
    _debouncedPersistQueueSlots();
    _queueVersion++;
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
          errorMessage: 'Queue slot is empty',
        ));
        return;
      }

      _queueVersion++;
      int safeIdx = -1;
      if (targetOriginalSong != null) {
        safeIdx =
            validSongs.indexWhere((s) => _isSameTrack(s, targetOriginalSong));
      }
      if (safeIdx == -1) {
        safeIdx = targetSlot.currentIndex.clamp(0, validSongs.length - 1);
      }
      final song = validSongs[safeIdx];
      // Single atomic emit: a split emit exposed a transient state where the
      // new queue was paired with the old (possibly out-of-bounds) index.
      safeEmit(state.copyWith(
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
        unawaited(_loadLyricsForSong(song));
      } catch (e, st) {
        // The slot UI state is already switched; a failure here leaves the
        // handler on the previous queue until the next successful load.
        // Surface it instead of letting the throw escape into the widget tap
        // handler as an unhandled exception.
        ErrorLogger.log('Failed to switch queue slot $slot',
            error: e, stackTrace: st, category: 'PlayerCubit');
        if (!isClosed) {
          safeEmit(state.copyWith(errorMessage: 'Failed to switch queue slot'));
        }
      }
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
      _queueVersion++;
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
    try {
      if (_audioHandler.playbackState.value.playing) {
        await _audioHandler.pause();
      } else {
        if (state.currentSong == null && state.queue.isEmpty) {
          return;
        }
        await _audioHandler.play();
      }
    } catch (e, st) {
      ErrorLogger.log('Toggle play/pause failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Playback action failed'));
      }
    }
  }

  int _lastSeekMs = 0;

  Future<void> seek(Duration position) {
    if (isClosed) return Future.value();
    // Clamp to a sane range; negative seeks crash some backends and
    // beyond-duration seeks leave UI/engine diverged.
    var target = position.isNegative ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    // Optimistic UI: don't wait up to 100ms / round-trip for the position
    // stream to reflect a discrete user intent.
    safeEmit(state.copyWith(position: target));
    // Throttle tap-spam: at most one native seek per 100ms. Drag-end seeks
    // are discrete user intents — the 100ms window is short enough that the
    // final position still lands promptly while floods are coalesced.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSeekMs < 100) {
      // Coalesce: schedule the latest position at the window edge.
      _pendingSeek = target;
      _seekThrottleTimer?.cancel();
      _seekThrottleTimer = autoTimer(Timer(
        Duration(milliseconds: 100 - (nowMs - _lastSeekMs)),
        () {
          if (isClosed) {
            _pendingSeek = null;
            return;
          }
          final pending = _pendingSeek;
          _pendingSeek = null;
          if (pending != null) {
            _lastSeekMs = DateTime.now().millisecondsSinceEpoch;
            _lastSkippedSegmentEnd = null;
            _lastSponsorSkipTime = null;
            _audioHandler.seek(pending).catchError((Object e, StackTrace st) {
              ErrorLogger.log('Coalesced seek failed',
                  error: e, stackTrace: st, category: 'PlayerCubit');
              if (!isClosed) {
                safeEmit(state.copyWith(
                    errorMessage: 'Seek failed, position restored'));
              }
            });
          }
        },
      ));
      return Future.value();
    }
    _lastSeekMs = nowMs;
    _lastSkippedSegmentEnd = null;
    _lastSponsorSkipTime = null;
    // Discrete intent: bypass the handler's scrub debounce (single layer).
    return _audioHandler.seekDirect(target);
  }

  Future<void> next() async {
    try {
      await _audioHandler.skipToNext();
    } catch (e, st) {
      ErrorLogger.log('Skip to next failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> previous() async {
    try {
      await _audioHandler.skipToPrevious();
    } catch (e, st) {
      ErrorLogger.log('Skip to previous failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    try {
      await _audioHandler.skipToQueueItem(index);
    } catch (e, st) {
      ErrorLogger.log('Skip to queue item failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) safeEmit(state.copyWith(errorMessage: 'Skip failed'));
    }
  }

  Future<void> toggleShuffle() async {
    final prev = state.isShuffle;
    final next = !prev;
    safeEmit(state.copyWith(isShuffle: next, errorMessage: null));
    try {
      await _audioHandler.setShuffleMode(
          next ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
    } catch (e, st) {
      ErrorLogger.log('Toggle shuffle failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(isShuffle: prev, errorMessage: 'Shuffle failed'));
      }
    }
  }

  Future<void> toggleRepeat() async {
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
    safeEmit(state.copyWith(repeatMode: next, errorMessage: null));
    try {
      await _audioHandler.setRepeatMode(nextMode);
    } catch (e, st) {
      ErrorLogger.log('Toggle repeat failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(repeatMode: prev, errorMessage: 'Repeat failed'));
      }
    }
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
              songs: v.songs
                  .map(
                      (s) => s.id == songId ? s.copyWith(isFavorite: isFav) : s)
                  .toList(),
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
        } else if (state.queue.any((s) => s.id == songId)) {
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
      if (showError) {
        safeEmit(state.copyWith(errorMessage: '$feature blocked: $reason'));
      }
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

  Future<void> applyPreset(EqPreset preset, {bool isPerSongRestore = false}) async {
    if (!_guardDsp('Preset')) return;
    // Manual edits during an active per-song override must not be lost when
    // the override restores: track the user's latest choice as the backup.
    if (_perSongOverrideActive && !isPerSongRestore) {
      _globalEqBackup = preset;
      _globalHeadphoneProfileBackup = null;
    }
    safeEmit(state.copyWith(
      isEqEnabled: true,
      eqPreset: preset,
      selectedHeadphoneProfile: null,
      errorMessage: null,
    ));
    await _audioHandler.setEqualizerEnabled(true);
    await _audioHandler.applyPreset(preset);
  }

  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile,
      {bool isPerSongRestore = false}) async {
    if (profile != null && !_guardDsp('AutoEQ')) return;
    if (profile != null) {
      if (_perSongOverrideActive && !isPerSongRestore) {
        _globalEqBackup = EqPreset(
          name: profile.name,
          gains: profile.gains,
          bassBoost: profile.bassBoost,
        );
        _globalHeadphoneProfileBackup = profile;
      }
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
    try {
      await _audioHandler.applyHeadphoneProfile(profile);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to apply headphone profile: $e'));
    }
  }

  List<EqPreset> _equalizerCustomPresets() {
    // Custom user curves live as HeadphoneProfile entries; plain EqPreset
    // customs are not stored separately, so only defaults apply here.
    return const [];
  }

  Future<HeadphoneProfile?> _headphoneProfileByName(String name) async {
    try {
      final lower = name.toLowerCase();
      final repo = HeadphoneProfilesRepository();
      // The repository's profiles are empty until load() runs; without this the
      // per-song override by headphone-profile name would never resolve on a
      // fresh process.
      await repo.loadProfiles();
      for (final p in repo.profiles) {
        if (p.name.toLowerCase() == lower) return p;
      }
    } catch (_) {}
    return null;
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
    try {
      await _audioHandler.setBandGain(bandIndex, clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set band gain: $e'));
    }
  }

  Future<void> resetToFlat() async {
    safeEmit(state.copyWith(
      eqPreset: EqPreset.defaultPresets.first,
      selectedHeadphoneProfile: null,
    ));
    try {
      await _audioHandler.resetToFlat();
    } catch (e) {
      _syncAudioEffects();
    }
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
    try {
      await _audioHandler.setBassBoost(clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set bass boost: $e'));
    }
  }

  /// Switches the active EQ band plan to [count] (10, 32 or 64). 10/32 keep the
  /// legacy handler passthrough; 64 goes straight to the manager (the handler's
  /// passthrough only speaks the legacy 10/32 split).
  Future<void> setBandMode(int count) async {
    if (count == 10 || count == 32) {
      await _audioHandler.set32BandMode(count == 32);
    } else if (count == 64) {
      await _audioHandler.equalizerManager.setBandMode(64);
    } else {
      return;
    }
    safeEmit(state.copyWith(
      eqPreset: _audioHandler.currentPreset,
    ));
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

  /// F-37: merge a fitted room-correction curve with the currently selected
  /// AutoEQ headphone profile (band-wise, clamped). Returns [roomGains]
  /// unchanged (clamped) when no profile is selected. Thin passthrough to
  /// [RoomCorrectionService.mergeWithHeadphoneCurve] for the room-correction
  /// wizard's "stack with headphone" option.
  List<double> mergeRoomCorrectionWithHeadphoneCurve(
    List<double> roomGains, {
    double maxGainDb = 15.0,
  }) {
    final profile = state.selectedHeadphoneProfile;
    return RoomCorrectionService.mergeWithHeadphoneCurve(
      roomGains,
      profile?.gains ?? const <double>[],
      maxGainDb: maxGainDb,
    );
  }

  /// F-37: design a linear-phase FIR impulse response from a correction curve
  /// for the native convolution stage. Thin passthrough to
  /// [RoomCorrectionService.exportCorrectionImpulseResponse].
  List<double> exportCorrectionImpulseResponse(
    List<double> gains, {
    List<double>? centers,
    int sampleRate = RoomCorrectionService.captureSampleRate,
    int taps = 127,
  }) {
    return RoomCorrectionService.exportCorrectionImpulseResponse(
      gains,
      centers: centers ?? EqPreset.centerFrequencies,
      sampleRate: sampleRate,
      taps: taps,
    );
  }

  Future<void> setVirtualizerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Virtualizer')) return;
    safeEmit(state.copyWith(isVirtualizerEnabled: enabled, errorMessage: null));
    try {
      await _audioHandler.setVirtualizerEnabled(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set virtualizer: $e'));
    }
  }

  Future<void> setVirtualizerStrength(double strength) async {
    if (!_guardDsp('Virtualizer', showError: false)) return;
    safeEmit(state.copyWith(virtualizerStrength: strength));
    try {
      await _audioHandler.setVirtualizerStrength(strength);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to set virtualizer strength: $e'));
    }
  }

  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) async {
    final isEnabled = enabled ?? (preset != DynamicsPreset.off);
    if (isEnabled && !_guardDsp('Dynamics')) return;
    safeEmit(state.copyWith(
      dynamicsPreset: preset,
      isDynamicsEnabled: isEnabled,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicsPreset(preset, enabled: enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set dynamics preset: $e'));
    }
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
    try {
      if (!enabled) {
        if (state.isDspEffectsActive) {
          _dspSnapshot = state;
        }
        // The Equalizer master switch is intentionally NOT touched here: the
        // DSP-effects switch owns only the spatial/dynamics/reverb stages, so
        // the two switches stay independent.
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
          isDynamicBassEnabled: false,
          volumeBoost: 0.0,
        ));
        await _audioHandler.setSpatializerEnabled(false);
        await _audioHandler.setVirtualizerEnabled(false);
        await _audioHandler.setDynamicsPreset(DynamicsPreset.off,
            enabled: false);
        await _audioHandler.setCrossfeed(false);
        await _audioHandler.setLookaheadLimiter(false);
        await _audioHandler.setReverb(false);
        await _audioHandler.setSaturation(false);
        await _audioHandler.setStereoWidth(false);
        await _audioHandler.setLoudnessContour(false);
        await _audioHandler.setSubCrossover(false);
        await _audioHandler.setDynamicEq(false);
        await _audioHandler.setDynamicBass(enabled: false);
        await _audioHandler.setVolumeBoost(0.0);
      } else {
        final snap = _dspSnapshot;
        if (snap != null && snap.isDspEffectsActive) {
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
            isDynamicBassEnabled: snap.isDynamicBassEnabled,
            dynamicBassStrength: snap.dynamicBassStrength,
            dynamicBassPreset: snap.dynamicBassPreset,
            volumeBoost: snap.volumeBoost,
          ));
          if (snap.isSpatializerEnabled) {
            await _audioHandler.setSpatializerEnabled(true);
          }
          if (snap.isVirtualizerEnabled) {
            await _audioHandler.setVirtualizerEnabled(true);
            await _audioHandler
                .setVirtualizerStrength(snap.virtualizerStrength);
          }
          if (snap.isDynamicsEnabled &&
              snap.dynamicsPreset != DynamicsPreset.off) {
            await _audioHandler.setDynamicsPreset(snap.dynamicsPreset,
                enabled: true);
          }
          if (snap.isCrossfeedEnabled) {
            await _audioHandler.setCrossfeed(true,
                delayUs: snap.crossfeedDelayUs, feedDb: snap.crossfeedFeedDb);
          }
          if (snap.isLimiterEnabled) {
            await _audioHandler.setLookaheadLimiter(true,
                thresholdDb: snap.limiterThresholdDb,
                releaseMs: snap.limiterReleaseMs);
          }
          if (snap.isReverbEnabled) {
            await _audioHandler.setReverb(true,
                preset: snap.reverbPreset, wetDry: snap.reverbWetDry);
          }
          if (snap.isSaturationEnabled) {
            await _audioHandler.setSaturation(true,
                drive: snap.saturationDrive,
                mix: snap.saturationMix,
                tilt: snap.saturationTilt);
          }
          if (snap.isStereoWidthEnabled) {
            await _audioHandler.setStereoWidth(true, width: snap.stereoWidth);
          }
          if (snap.isLoudnessContourEnabled) {
            await _audioHandler.setLoudnessContour(true,
                intensity: snap.loudnessContourIntensity);
          }
          if (snap.isSubCrossoverEnabled) {
            await _audioHandler.setSubCrossover(true,
                cornerHz: snap.subCrossoverCornerHz,
                slopeDbPerOct: snap.subCrossoverSlopeDbPerOct,
                gain: snap.subCrossoverGain);
          }
          if (snap.isDynamicEqEnabled) {
            await _audioHandler.setDynamicEq(true);
          }
          if (snap.isDynamicBassEnabled) {
            await _audioHandler.setDynamicBass(
              enabled: true,
              strength: snap.dynamicBassStrength,
              preset: snap.dynamicBassPreset,
            );
          }
          if (snap.volumeBoost > 0.0) {
            await _audioHandler.setVolumeBoost(snap.volumeBoost);
          }
        } else {
          // No snapshot to restore: do not fabricate limiter/dynamics as ON.
          // Re-sync the UI from the handler (the source of truth) and leave
          // every stage exactly as the current/stored preference has it.
          _syncAudioEffects();
        }
      }
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to update DSP effects: $e'));
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
    try {
      await _audioHandler.setVolumeBoost(safeValue);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set volume boost: $e'));
    }
  }

  Future<void> setSpatializerEnabled(bool enabled) async {
    if (enabled && !_guardDsp('Spatializer')) return;
    safeEmit(state.copyWith(isSpatializerEnabled: enabled, errorMessage: null));
    try {
      await _audioHandler.setSpatializerEnabled(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set spatializer: $e'));
    }
  }

  // --- NATIVE DSP METHODS ---

  Future<void> setCrossfeed(bool enabled,
      {double? delayUs, double? feedDb, int? mode}) async {
    if (enabled && !_guardDsp('Crossfeed')) return;
    safeEmit(state.copyWith(
      isCrossfeedEnabled: enabled,
      crossfeedDelayUs: delayUs ?? state.crossfeedDelayUs,
      crossfeedFeedDb: feedDb ?? state.crossfeedFeedDb,
      crossfeedMode: mode ?? state.crossfeedMode,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setCrossfeed(enabled,
          delayUs: delayUs, feedDb: feedDb, mode: mode);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set crossfeed: $e'));
    }
  }

  Future<void> setCrossfeedMode(int mode) async {
    safeEmit(state.copyWith(crossfeedMode: mode));
    try {
      await _audioHandler.setCrossfeedMode(mode);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set crossfeed mode: $e'));
    }
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
    try {
      await _audioHandler.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set limiter: $e'));
    }
  }

  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) async {
    if (enabled && !_guardDsp('Reverb')) return;
    safeEmit(state.copyWith(
      isReverbEnabled: enabled,
      reverbPreset: preset ?? state.reverbPreset,
      reverbWetDry: wetDry ?? state.reverbWetDry,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setReverb(enabled, preset: preset, wetDry: wetDry);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set reverb: $e'));
    }
  }

  /// Loads a custom reverb impulse response. Returns true only when the native
  /// side accepted it; on failure the UI is NOT flipped to "Custom (Loaded)".
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) async {
    if (!_guardDsp('Reverb IR')) return false;
    try {
      final loaded = await _audioHandler.loadCustomImpulseResponse(irSamples);
      if (!loaded) {
        _syncAudioEffects();
        safeEmit(state.copyWith(
            errorMessage: 'Impulse response rejected by the audio engine'));
        return false;
      }
      if (!isClosed) {
        safeEmit(state.copyWith(
          isReverbEnabled: true,
          reverbPreset: ReverbPreset.custom.wireValue,
          errorMessage: null,
        ));
      }
      return true;
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to load impulse response: $e'));
      return false;
    }
  }

  Future<void> pickAndLoadCustomIrFile() async {
    if (!_guardDsp('Reverb IR')) return;
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (result != null && result.path != null) {
        final path = result.path!;
        final samples = await IrFileParser.parseWavFile(File(path));
        // Persist the path only after the engine actually accepted the IR,
        // otherwise a failed load would be restored as "custom" with no IR.
        if (await loadCustomImpulseResponse(samples)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(PrefsKeys.customReverbIrPath, path);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to pick/load custom IR file',
          error: e, stackTrace: st, category: 'Reverb');
      safeEmit(state.copyWith(errorMessage: 'Failed to load IR WAV file: $e'));
    }
  }

  Future<void> setStereoBalance(double balance) async {
    if (balance.abs() > 0.01 &&
        !_guardDsp('Stereo Balance', showError: false)) {
      return;
    }
    final clamped = balance.clamp(-1.0, 1.0);
    safeEmit(state.copyWith(stereoBalance: clamped));
    try {
      await _audioHandler.setStereoBalance(clamped);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set stereo balance: $e'));
    }
  }

  Future<void> setMonoMix(bool mono) async {
    if (mono && !_guardDsp('Mono Mix')) return;
    safeEmit(state.copyWith(monoMix: mono, errorMessage: null));
    try {
      await _audioHandler.setMonoMix(mono);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set mono mix: $e'));
    }
  }

  Future<void> setSincResampler(bool enabled) async {
    if (enabled && !_guardDsp('Resampler', showError: false)) return;
    safeEmit(state.copyWith(isSincResamplerEnabled: enabled));
    try {
      await _audioHandler.setSincResampler(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set resampler: $e'));
    }
  }

  Future<void> setDither(bool enabled, {int? targetBitDepth}) async {
    if (enabled && !_guardDsp('Dither', showError: false)) return;
    if (targetBitDepth != null &&
        targetBitDepth != 16 &&
        targetBitDepth != 24 &&
        targetBitDepth != 32) {
      return;
    }
    safeEmit(state.copyWith(
      isDitherEnabled: enabled,
      ditherTargetBitDepth: targetBitDepth ?? state.ditherTargetBitDepth,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDither(enabled, targetBitDepth: targetBitDepth);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set dither: $e'));
    }
  }

  // --- PHASE 1 DSP EXPANSION METHODS ---

  Future<void> setSaturation(bool enabled,
      {double? drive,
      double? mix,
      double? tilt,
      int? mode,
      bool? multiband}) async {
    if (enabled && !_guardDsp('Harmonic Saturation')) return;
    safeEmit(state.copyWith(
      isSaturationEnabled: enabled,
      saturationDrive: drive ?? state.saturationDrive,
      saturationMix: mix ?? state.saturationMix,
      saturationTilt: tilt ?? state.saturationTilt,
      saturationMultiband: multiband ?? state.saturationMultiband,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setSaturation(enabled,
          drive: drive, mix: mix, tilt: tilt, mode: mode, multiband: multiband);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set saturation: $e'));
    }
  }

  Future<void> setSaturationMultiband(bool multiband) async {
    safeEmit(state.copyWith(saturationMultiband: multiband));
    try {
      await _audioHandler.setSaturationMultiband(multiband);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(
          errorMessage: 'Failed to set saturation multiband: $e'));
    }
  }

  Future<void> setStereoWidth(bool enabled,
      {double? width,
      bool? multiband,
      double? lowWidth,
      double? midWidth,
      double? highWidth,
      double? lowCrossoverHz,
      double? highCrossoverHz}) async {
    if (enabled && !_guardDsp('Stereo Width')) return;
    safeEmit(state.copyWith(
      isStereoWidthEnabled: enabled,
      stereoWidth: width ?? state.stereoWidth,
      stereoWidthMultiband: multiband ?? state.stereoWidthMultiband,
      stereoWidthLow: lowWidth ?? state.stereoWidthLow,
      stereoWidthMid: midWidth ?? state.stereoWidthMid,
      stereoWidthHigh: highWidth ?? state.stereoWidthHigh,
      stereoWidthLowCrossoverHz:
          lowCrossoverHz ?? state.stereoWidthLowCrossoverHz,
      stereoWidthHighCrossoverHz:
          highCrossoverHz ?? state.stereoWidthHighCrossoverHz,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setStereoWidth(enabled,
          width: width,
          multiband: multiband,
          lowWidth: lowWidth,
          midWidth: midWidth,
          highWidth: highWidth,
          lowCrossoverHz: lowCrossoverHz,
          highCrossoverHz: highCrossoverHz);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set stereo width: $e'));
    }
  }

  Future<void> setLoudnessContour(bool enabled, {double? intensity}) async {
    if (enabled && !_guardDsp('Loudness Contour')) return;
    safeEmit(state.copyWith(
      isLoudnessContourEnabled: enabled,
      loudnessContourIntensity: intensity ?? state.loudnessContourIntensity,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setLoudnessContour(enabled, intensity: intensity);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set loudness contour: $e'));
    }
  }

  Future<void> setSubCrossover(bool enabled,
      {double? cornerHz,
      double? slopeDbPerOct,
      double? gain,
      bool? bassMono,
      bool? antiPop}) async {
    if (enabled && !_guardDsp('Sub Crossover')) return;
    safeEmit(state.copyWith(
      isSubCrossoverEnabled: enabled,
      subCrossoverCornerHz: cornerHz ?? state.subCrossoverCornerHz,
      subCrossoverSlopeDbPerOct:
          slopeDbPerOct ?? state.subCrossoverSlopeDbPerOct,
      subCrossoverGain: gain ?? state.subCrossoverGain,
      subCrossoverBassMono: bassMono ?? state.subCrossoverBassMono,
      subCrossoverAntiPop: antiPop ?? state.subCrossoverAntiPop,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setSubCrossover(enabled,
          cornerHz: cornerHz,
          slopeDbPerOct: slopeDbPerOct,
          gain: gain,
          bassMono: bassMono,
          antiPop: antiPop);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set sub crossover: $e'));
    }
  }

  Future<void> setDynamicEq(bool enabled) async {
    if (enabled && !_guardDsp('Dynamic EQ')) return;
    safeEmit(state.copyWith(
      isDynamicEqEnabled: enabled,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicEq(enabled);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set dynamic EQ: $e'));
    }
  }

  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) async {
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    // Seed with neutral defaults if the state list has not been synced yet
    while (bands.length <= index) {
      bands.add(const DynamicEqBandConfig());
    }
    bands[index] = band;
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.setDynamicEqBand(index, band);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set dynamic EQ band: $e'));
    }
  }

  Future<void> addDynamicEqBand() async {
    if (state.dynamicEqBands.length >= 8) return;
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    bands.add(const DynamicEqBandConfig());
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.addDynamicEqBand();
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to add dynamic EQ band: $e'));
    }
  }

  Future<void> removeDynamicEqBand(int index) async {
    if (index < 0 || index >= state.dynamicEqBands.length) return;
    var bands = List<DynamicEqBandConfig>.from(state.dynamicEqBands);
    bands.removeAt(index);
    safeEmit(state.copyWith(dynamicEqBands: bands));
    try {
      await _audioHandler.removeDynamicEqBand(index);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(
          state.copyWith(errorMessage: 'Failed to remove dynamic EQ band: $e'));
    }
  }

  // --- JAMESDSP FEATURE PARITY METHODS ---

  Future<void> setViperDdcEnabled(bool enabled,
      {String? profileName, List<double>? coeffs}) async {
    if (enabled && !_guardDsp('ViPER-DDC')) return;
    safeEmit(state.copyWith(
      isViperDdcEnabled: enabled,
      viperDdcProfileName: profileName ?? state.viperDdcProfileName,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setViperDdc(enabled,
          profileName: profileName, coeffs: coeffs);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set ViPER-DDC: $e'));
    }
  }

  Future<void> setArbitraryEqEnabled(bool enabled, {String? eqString}) async {
    if (enabled && !_guardDsp('Arbitrary Response EQ')) return;
    safeEmit(state.copyWith(
      isArbitraryEqEnabled: enabled,
      arbitraryEqString: eqString ?? state.arbitraryEqString,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setArbitraryEq(enabled, eqString: eqString);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set Arbitrary EQ: $e'));
    }
  }

  Future<void> setLiveProgEnabled(bool enabled, {String? code}) async {
    if (enabled && !_guardDsp('Live Programmable DSP')) return;
    safeEmit(state.copyWith(
      isLiveProgEnabled: enabled,
      liveProgCode: code ?? state.liveProgCode,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setLiveProg(enabled, code: code);
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set LiveProg DSP: $e'));
    }
  }

  Future<void> setLiveProgSlider(int sliderIndex, double value) async {
    try {
      await _audioHandler.setLiveProgSlider(sliderIndex, value);
    } catch (e) {
      safeEmit(
          state.copyWith(errorMessage: 'Failed to set LiveProg slider: $e'));
    }
  }

  Future<void> setDynamicBass(
    bool enabled, {
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) async {
    if (enabled && !_guardDsp('Dynamic Bass')) return;
    safeEmit(state.copyWith(
      isDynamicBassEnabled: enabled,
      dynamicBassStrength: strength ?? state.dynamicBassStrength,
      dynamicBassPreset: preset ?? state.dynamicBassPreset,
      errorMessage: null,
    ));
    try {
      await _audioHandler.setDynamicBass(
        enabled: enabled,
        strength: strength,
        preset: preset,
        xLow: xLow,
        xHigh: xHigh,
        yLow: yLow,
        yHigh: yHigh,
        sideGainLow: sideGainLow,
        sideGainHigh: sideGainHigh,
      );
    } catch (e) {
      _syncAudioEffects();
      safeEmit(state.copyWith(errorMessage: 'Failed to set Dynamic Bass: $e'));
    }
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

      final smart = _smartAudioService;
      final smartEnabled = smart != null && await smart.isEnabled();

      // 1) An explicit user device->profile link always wins over auto-match.
      if (await service.isAutoSwitchEnabled()) {
        final link = await service.linkForDeviceKey(key);
        if (link != null) {
          final profiles = await profilesService.getProfiles();
          SettingsProfile? profile;
          for (final p in profiles) {
            if (p.id == link.profileId) {
              profile = p;
              break;
            }
          }
          if (profile != null) {
            // Claim the key before applying: applyProfile awaits a long chain,
            // and a second stream event for the same device would otherwise
            // pass this gate and run a concurrent apply.
            _lastAutoAppliedDeviceKey = key;
            final applied = await applyProfile(profile);
            if (!applied && !isClosed) {
              // applyProfile reports failure instead of throwing, so release
              // the claim here or a later event for this device never retries.
              _lastAutoAppliedDeviceKey = null;
            }
            return;
          }
        }
      }

      // 2) Smart Auto: match the connected headphone to an AutoEQ profile and
      // arbitrate the best output quality for this route.
      if (smartEnabled) {
        final matched = await _applySmartAutoEq(smart, key, device);
        await _applySmartQuality(device, matched?.id);
      }
    } catch (e, st) {
      ErrorLogger.log('Device profile auto-switch failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Smart Auto path: apply the remembered (or freshly detected) AutoEQ profile
  /// for [device]. A per-device saved match wins so the same headset is always
  /// corrected identically; otherwise a fuzzy match is computed and persisted.
  /// Returns the applied profile (or null when nothing matched).
  Future<HeadphoneProfile?> _applySmartAutoEq(
    SmartAudioService smart,
    String key,
    AudioOutputInfo device,
  ) async {
    try {
      final repo = HeadphoneProfilesRepository();
      await repo.loadProfiles();
      if (isClosed || repo.profiles.isEmpty) return null;

      HeadphoneProfile? profile;
      final saved = await smart.linkForDeviceKey(key);
      if (saved != null) {
        profile = repo.getProfileById(saved.profileId);
      }
      if (profile == null) {
        final match = HeadphoneDeviceMatcher.match(
          deviceName: device.deviceName,
          profiles: repo.profiles,
        );
        profile = match?.profile;
        if (profile == null) return null;
        // Persist the freshly detected association so reconnects skip matching.
        await smart.rememberAutoEqLink(
          deviceKey: key,
          deviceLabel: device.deviceName,
          profileId: profile.id,
          score: match!.score,
        );
      }

      if (isClosed) return null;
      _lastAutoAppliedDeviceKey = key;
      await applyHeadphoneProfile(profile);
      return profile;
    } catch (e, st) {
      ErrorLogger.log('Smart Auto AutoEQ match failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      return null;
    }
  }

  /// Smart Auto quality arbitration: hand the route to the bit-perfect/hi-res
  /// path when it is the best available and no correction is requested, else
  /// keep the DSP path. Only toggles bit-perfect that Smart Auto itself turned
  /// on, so an explicit user choice is never overridden.
  Future<void> _applySmartQuality(
    AudioOutputInfo device,
    String? matchedProfileId,
  ) async {
    final settings = _settingsCubit;
    if (settings == null || isClosed) return;
    final song = state.currentSong;
    final plan = resolveSmartAudioPlan(
      mode: SmartAudioMode.auto,
      device: device,
      matchedHeadphoneProfileId: matchedProfileId,
      trackIsHiRes: smartAudioTrackIsHiRes(
        sampleRate: song?.sampleRate ?? 0,
        bitDepth: song?.bitDepth ?? 0,
      ),
      deviceSupportsBitPerfect: device.isBitPerfectSupported,
    );
    try {
      if (plan.preferBitPerfect) {
        if (!settings.state.bitPerfectOutput) {
          _smartAutoBitPerfectApplied = true;
          await settings.setBitPerfectOutput(true);
        }
      } else if (_smartAutoBitPerfectApplied) {
        _smartAutoBitPerfectApplied = false;
        if (settings.state.bitPerfectOutput) {
          await settings.setBitPerfectOutput(false);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Smart Audio quality arbitration failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Applies a settings profile through the cubit's guarded setters so
  /// handler, persisted prefs and UI state stay consistent. Order matters:
  /// DSP stages are applied BEFORE bit-perfect so its bypass conflict rules
  /// evaluate against the pre-switch state, and bit-perfect is re-asserted
  /// last (its bypass then zeroes stages per the saved policy).
  Future<bool> applyProfile(SettingsProfile profile,
      {bool manual = false}) async {
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
      return true;
    } catch (e, st) {
      ErrorLogger.log('Failed to apply settings profile',
          error: e, stackTrace: st, category: 'PlayerCubit');
      return false;
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
    final remaining = state.duration > state.position
        ? state.duration - state.position
        : const Duration(minutes: 1);
    safeEmit(state.copyWith(sleepTimerRemaining: remaining));
  }

  void startAfterNTracksTimer(int trackCount) {
    _audioHandler.startAfterNTracksTimer(trackCount);
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  void startEndOfQueueTimer() {
    _audioHandler.startEndOfQueueTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  void cancelSleepTimer() {
    _audioHandler.cancelSleepTimer();
    safeEmit(state.copyWith(sleepTimerRemaining: null));
  }

  int? get sleepTimerRemainingTracks => _audioHandler.sleepTimerRemainingTracks;
  SleepTimerMode get sleepTimerMode => _audioHandler.sleepTimerMode;
  bool get isEndOfQueueSleepTimer =>
      sleepTimerMode == SleepTimerMode.endOfQueue;
  Stream<int?> get sleepTimerRemainingTracksStream =>
      _audioHandler.sleepTimerRemainingTracksStream;

  // Playback Speed
  double get minPlaybackSpeed => _audioHandler.minPlaybackSpeed;
  double get maxPlaybackSpeed => _audioHandler.maxPlaybackSpeed;

  Future<void> _loadPlaybackSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;
      // Clamp to the engine's *current* range so a persisted extended speed
      // (0.1–8.0) is not silently rewritten to the 0.5–3.0 default band.
      final speed = raw.isFinite
          ? raw.clamp(
              _audioHandler.minPlaybackSpeed, _audioHandler.maxPlaybackSpeed)
          : 1.0;
      await _audioHandler.setSpeed(speed);
      safeEmit(state.copyWith(playbackSpeed: speed));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback speed from SharedPreferences',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!speed.isFinite) return;
    // Honour the engine's active range (0.25–4.0, or 0.1–8.0 when the
    // advanced-speed setting is on) instead of a hardcoded band.
    final clamped = speed
        .clamp(_audioHandler.minPlaybackSpeed, _audioHandler.maxPlaybackSpeed);
    _lastSpeedPushed = clamped;
    _lastSpeedPushAt = DateTime.now();
    try {
      await _audioHandler.setSpeed(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set playback speed failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Speed change failed'));
      }
      return;
    }
    safeEmit(state.copyWith(playbackSpeed: clamped));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
    _queueSlots[state.activeQueueSlot] = _QueueSlotData(
      songs: state.queue,
      currentIndex: state.currentIndex,
      position: state.position,
      speed: clamped,
    );
    _debouncedPersistQueueSlots();
  }

  // Playback Pitch / Tone Control (PowerAmp parity)
  Future<void> _loadPlaybackPitch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getDouble(PrefsKeys.playbackPitch) ?? 1.0;
      final pitch = raw.isFinite ? raw.clamp(0.5, 2.0) : 1.0;
      await _audioHandler.setPitch(pitch);
      safeEmit(state.copyWith(playbackPitch: pitch));
    } catch (e, st) {
      ErrorLogger.log('Failed to load playback pitch from SharedPreferences',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<void> setPlaybackPitch(double pitch) async {
    if (!pitch.isFinite) return;
    final clamped = pitch.clamp(0.5, 2.0);
    try {
      await _audioHandler.setPitch(clamped);
    } catch (e, st) {
      ErrorLogger.log('Set playback pitch failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Pitch change failed'));
      }
      return;
    }
    safeEmit(state.copyWith(playbackPitch: clamped));
  }

  // Per-Song Star Rating (1 to 5 stars, 0 = unrated)
  Future<void> setSongRating(int songId, int rating) async {
    await _songRatingStore.setRating(songId.toString(), rating);
    if (state.currentSong?.id == songId) {
      safeEmit(state.copyWith(currentSongRating: rating));
    }
  }

  // Per-Song EQ Preset Override
  Future<void> setSongEqOverride(int songId, String? presetName) async {
    await _perSongEqStore.setPresetForTrack(songId.toString(), presetName);
    if (state.currentSong?.id != songId) return;
    safeEmit(state.copyWith(currentSongEqOverride: presetName));

    if (presetName != null) {
      final match = EqPreset.defaultPresets
          .where((p) => p.name.toLowerCase() == presetName.toLowerCase())
          .firstOrNull;
      if (match == null) return;
      // Assigning an override mid-song must mark it active and snapshot the
      // pre-override preset, otherwise clearing it (or the next song without an
      // override) has nothing to restore and the per-song curve leaks into the
      // rest of the queue.
      if (!_perSongOverrideActive) {
        _globalEqBackup = state.eqPreset;
        _globalHeadphoneProfileBackup = state.selectedHeadphoneProfile;
        _perSongOverrideActive = true;
      }
      await applyPreset(match, isPerSongRestore: true);
    } else if (_perSongOverrideActive && _globalEqBackup != null) {
      final restore = _globalEqBackup!;
      final profileRestore = _globalHeadphoneProfileBackup;
      _globalEqBackup = null;
      _globalHeadphoneProfileBackup = null;
      _perSongOverrideActive = false;
      // Re-apply the AutoEQ profile as a profile (not a plain preset), so the
      // global headphone selection is not silently deselected in the UI.
      if (profileRestore != null) {
        await applyHeadphoneProfile(profileRestore, isPerSongRestore: true);
      } else {
        await applyPreset(restore, isPerSongRestore: true);
      }
    }
  }

  // Per-Song Volume Override (-12.0 to +6.0 dB)
  Future<void> setSongVolumeOverride(int songId, double gainDb) async {
    await _perSongVolumeStore.setGainDbForTrack(songId.toString(), gainDb);
    if (state.currentSong?.id == songId) {
      safeEmit(state.copyWith(currentSongVolumeOverrideDb: gainDb));
      await _audioHandler.setVolume(_audioHandler.volume);
    }
  }

  // EQ Preset JSON Import & Export
  String exportCurrentEqPreset() {
    return _audioHandler.exportPresetToJson(state.eqPreset);
  }

  Future<bool> importEqPreset(String jsonString) async {
    final success = await _audioHandler.importPresetFromJson(jsonString);
    if (success) {
      _syncAudioEffects();
    }
    return success;
  }

  // Volume Control (handler-owned; no PlayerState.volume by design)
  Future<void> setVolume(double volume) async {
    try {
      await _audioHandler.setVolume(volume);
    } catch (e, st) {
      ErrorLogger.log('Set volume failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Volume change failed'));
      }
    }
  }

  Future<void> adjustVolume(double delta) async {
    try {
      final current = _audioHandler.volume;
      final target = (current + delta).clamp(0.0, 1.0);
      await _audioHandler.setVolume(target);
    } catch (e, st) {
      ErrorLogger.log('Adjust volume failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
      if (!isClosed) {
        safeEmit(state.copyWith(errorMessage: 'Volume change failed'));
      }
    }
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

  void resetOverlayViews() {
    if (state.isLyricsVisible || state.isQueueVisible) {
      safeEmit(state.copyWith(
        isLyricsVisible: false,
        isQueueVisible: false,
      ));
    }
  }

  // ── F1: AB loop ────────────────────────────────────────────────────
  void setAbPointA() {
    final pos = state.position;
    _audioHandler.setAbPointA(pos);
    // Emit manager truth, not the requested pos: the manager rejects
    // B<=A / pos<=A, and emitting pos would diverge UI from engine.
    final mgr = _audioHandler.abLoopManager;
    safeEmit(state.copyWith(
      abPointA: mgr.pointA,
      abLoopEnabled: mgr.isEnabled,
      abPointB: mgr.pointB,
    ));
  }

  void setAbPointB() {
    final pos = state.position;
    _audioHandler.setAbPointB(pos);
    final mgr = _audioHandler.abLoopManager;
    safeEmit(state.copyWith(
      abPointB: mgr.pointB,
      abPointA: mgr.pointA,
      abLoopEnabled: mgr.isEnabled,
    ));
  }

  void toggleAbLoop() {
    _audioHandler.toggleAbLoop();
    safeEmit(
        state.copyWith(abLoopEnabled: _audioHandler.abLoopManager.isEnabled));
  }

  void clearAbLoop() {
    _audioHandler.clearAbLoop();
    safeEmit(
        state.copyWith(abLoopEnabled: false, abPointA: null, abPointB: null));
  }

  /// Shared per-track reset used by BOTH track-change paths (onTrackChanged
  /// and mediaItem, which can fire in either order). Deduped within a short
  /// window so two listeners for one change apply once, while a genuine replay
  /// of the same song id (repeat-one / duplicate queue entry) still re-runs.
  Future<void> _syncPerTrackState(SongsTableData song) async {
    final now = DateTime.now();
    final sameId = _lastPerTrackSyncSongId == song.id;
    final withinDedupeWindow = _lastPerTrackSyncAt != null &&
        now.difference(_lastPerTrackSyncAt!) <
            const Duration(milliseconds: 400);
    if (sameId && withinDedupeWindow) return;
    _lastPerTrackSyncSongId = song.id;
    _lastPerTrackSyncAt = now;

    // The stores load their SharedPreferences map asynchronously; reading
    // before `ready` completes returns defaults (0/null) and silently drops
    // the saved per-song overrides.
    await Future.wait<void>([
      _songRatingStore.ready,
      _perSongEqStore.ready,
      _perSongVolumeStore.ready,
    ]);
    if (isClosed) return;

    final trackKey = song.id.toString();
    final songRating = _songRatingStore.getRating(trackKey);
    final songEq = _perSongEqStore.getPresetForTrack(trackKey);
    final songVol = _perSongVolumeStore.getGainDbForTrack(trackKey);

    var delayMs = state.trackDelayMs;
    try {
      delayMs = _audioHandler.currentTrackDelayMs;
    } catch (_) {}
    safeEmit(state.copyWith(
      abPointA: null,
      abPointB: null,
      abLoopEnabled: false,
      trackDelayMs: delayMs,
      bookmarkPosition: null,
      currentSongRating: songRating,
      currentSongEqOverride: songEq,
      currentSongVolumeOverrideDb: songVol,
    ));
    unawaited(_syncAbLoopUi(song));
    try {
      checkBookmarkOffer();
    } catch (e, st) {
      ErrorLogger.log('Bookmark offer check failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }

    if (songEq != null) {
      if (!_perSongOverrideActive) {
        _globalEqBackup = state.eqPreset;
        _globalHeadphoneProfileBackup = state.selectedHeadphoneProfile;
        _perSongOverrideActive = true;
      }
      final lower = songEq.toLowerCase();
      final match = EqPreset.defaultPresets
          .where((p) => p.name.toLowerCase() == lower)
          .firstOrNull;
      if (match != null) {
        unawaited(applyPreset(match, isPerSongRestore: true));
      } else {
        try {
          final custom = _equalizerCustomPresets()
              .where((p) => p.name.toLowerCase() == lower)
              .firstOrNull;
          if (custom != null) {
            unawaited(applyPreset(custom, isPerSongRestore: true));
          } else {
            unawaited(() async {
              final hp = await _headphoneProfileByName(songEq);
              if (hp != null && !isClosed) {
                await applyHeadphoneProfile(hp, isPerSongRestore: true);
              }
            }());
          }
        } catch (_) {}
      }
    } else if (_perSongOverrideActive && _globalEqBackup != null) {
      final restore = _globalEqBackup!;
      final profileRestore = _globalHeadphoneProfileBackup;
      _globalEqBackup = null;
      _globalHeadphoneProfileBackup = null;
      _perSongOverrideActive = false;
      unawaited(profileRestore != null
          ? applyHeadphoneProfile(profileRestore, isPerSongRestore: true)
          : applyPreset(restore, isPerSongRestore: true));
    }
    // Push per-song volume so the emitted override is actually audible.
    // setVolume combines master + ReplayGain + per-song gain in the handler.
    try {
      unawaited(_audioHandler.setVolume(_audioHandler.volume));
    } catch (e, st) {
      ErrorLogger.log('Per-song volume push failed',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Syncs AB-loop UI with the (possibly restored) handler state after a
  /// track change. Guarded for handler test doubles without F1 members.
  Future<void> _syncAbLoopUi(SongsTableData song) async {
    try {
      await _audioHandler.restoreAbLoopForCurrentSong();
    } catch (_) {}
    if (isClosed || state.currentSong?.id != song.id) return;
    try {
      final mgr = _audioHandler.abLoopManager;
      if (mgr.pointA == null && mgr.pointB == null) return;
      safeEmit(state.copyWith(
        abPointA: mgr.pointA,
        abPointB: mgr.pointB,
        abLoopEnabled: mgr.isEnabled,
      ));
    } catch (_) {}
  }

  // ── F2: per-track delay ──────────────────────────────────────────────
  Future<void> setTrackDelayMs(int ms) async {
    final clamped = ms.clamp(-2000, 2000);
    await _audioHandler.setCurrentTrackDelay(clamped);
    safeEmit(state.copyWith(trackDelayMs: clamped));
  }

  void syncTrackDelay() {
    safeEmit(state.copyWith(trackDelayMs: _audioHandler.currentTrackDelayMs));
  }

  // ── BPM override (feeds BPM-synced crossfade) ──────────────────────
  /// Sets (or clears with null) the manual BPM override for [song].
  /// Returns false when out of range or the handler lacks the API.
  Future<bool> setTrackBpm(SongsTableData song, double? bpm) async {
    try {
      return await _audioHandler.setTrackBpm(song, bpm);
    } catch (_) {
      return false;
    }
  }

  // ── F10: silence-skip sensitivity ────────────────────────────────────
  Future<void> setSilenceSkipSensitivity(int v) async {
    await _audioHandler.setSilenceSkipSensitivity(v);
    safeEmit(state.copyWith(silenceSkipSensitivity: v.clamp(0, 100)));
  }

  // ── F11: bookmarks ───────────────────────────────────────────────────
  void dismissBookmark() {
    safeEmit(state.copyWith(bookmarkPosition: null));
  }

  Future<void> seekToBookmark() async {
    final b = state.bookmarkPosition;
    if (b != null) {
      await _audioHandler.seek(b);
      safeEmit(state.copyWith(bookmarkPosition: null, position: b));
    }
  }

  Future<void> clearBookmark() async {
    final song = state.currentSong;
    if (song != null) await _audioHandler.clearBookmarkFor(song);
    safeEmit(state.copyWith(bookmarkPosition: null));
  }

  /// Saves the current playback position as a bookmark. Returns false when
  /// there is no current song or the position is too close to the head for the
  /// store to accept it.
  Future<bool> saveBookmark() async {
    final song = state.currentSong;
    if (song == null) return false;
    final posMs = state.position.inMilliseconds;
    if (posMs < 5000) return false;
    try {
      final key = PlaybackBookmarkStore.keyFor(
          songId: song.id, remoteId: song.remoteId, path: song.path);
      _audioHandler.bookmarkStore
          .save(key, posMs, durationMs: state.duration.inMilliseconds);
      await _audioHandler.persistBookmarks();
      safeEmit(state.copyWith(bookmarkPosition: Duration(milliseconds: posMs)));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads the stored bookmark for [song] without mutating playback state.
  PlaybackBookmark? storedBookmarkFor(SongsTableData song) {
    try {
      return _audioHandler.recallBookmarkFor(song);
    } catch (_) {
      return null;
    }
  }

  void checkBookmarkOffer() {
    final song = state.currentSong;
    if (song == null) return;
    PlaybackBookmark? b;
    try {
      b = _audioHandler.recallBookmarkFor(song);
    } catch (_) {
      return;
    }
    if (b != null && b.positionMs > 5000) {
      // Only offer when starting near the head.
      if (state.position.inMilliseconds < 8000) {
        safeEmit(state.copyWith(
            bookmarkPosition: Duration(milliseconds: b.positionMs)));
      }
    }
  }

  // ── Quran Mode ───────────────────────────────────────────────────────

  /// Restores Quran Mode from preferences on launch. No snapshot is captured:
  /// the restored prefs already reflect whatever the previous session left.
  Future<void> _restoreQuranMode() async {
    final service = _quranModeService;
    if (service == null) return;
    try {
      final profile = await service.loadActiveProfile();
      if (profile == null || isClosed) return;
      // Reload the snapshot captured when the mode was last enabled: the
      // in-memory one did not survive the process, and without it disabling
      // Quran Mode would leave its vocal EQ/reverb/dynamics applied.
      _quranRestore ??= await _loadQuranSnapshot();
      safeEmit(state.copyWith(
        quranReciterStyle: profile.style,
        isQuranModeEnabled: true,
      ));
      await _applyQuranProfile(profile.style);
    } catch (e, st) {
      ErrorLogger.log('Failed to restore Quran Mode',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  /// Enables or disables Quran Mode. Enabling snapshots the current DSP state,
  /// then applies the vocal-optimized profile. Disabling restores the snapshot.
  Future<void> setQuranModeEnabled(bool enabled) async {
    if (enabled == state.isQuranModeEnabled) return;
    if (enabled) {
      _quranRestore = _captureQuranRestoreSnapshot();
      await _persistQuranSnapshot(_quranRestore!);
      await _applyQuranProfile(state.quranReciterStyle);
      await _quranModeService?.setEnabled(true);
      if (!isClosed) {
        safeEmit(state.copyWith(isQuranModeEnabled: true, errorMessage: null));
      }
    } else {
      await _quranModeService?.setEnabled(false);
      // Fall back to the persisted snapshot when the in-memory one is gone
      // (mode restored on launch, then disabled in this session).
      _quranRestore ??= await _loadQuranSnapshot();
      await _restoreQuranSnapshot();
      _quranRestore = null;
      await _clearQuranSnapshot();
      if (!isClosed) {
        safeEmit(state.copyWith(isQuranModeEnabled: false, errorMessage: null));
      }
    }
  }

  Future<void> toggleQuranMode() =>
      setQuranModeEnabled(!state.isQuranModeEnabled);

  /// Switches the active reciter style, re-applying the profile when the mode
  /// is already on.
  Future<void> setQuranReciterStyle(QuranReciterStyle style) async {
    await _quranModeService?.setStyle(style);
    if (isClosed) return;
    safeEmit(state.copyWith(quranReciterStyle: style));
    if (state.isQuranModeEnabled) {
      await _applyQuranProfile(style);
    }
  }

  /// Re-applies the current style's profile (e.g. after a "reset" tap).
  Future<void> reapplyQuranProfile() =>
      _applyQuranProfile(state.quranReciterStyle);

  /// Applies a single reverb tweak on top of the active Quran profile (used by
  /// the ambience slider).
  Future<void> setQuranAmbience(double wetDry) async {
    final profile = QuranModeProfile.forStyle(state.quranReciterStyle);
    final caps = _earbudOptimizationService
        ?.detect(_hiResAudioService?.currentOutputInfo);
    await setReverb(
      wetDry > 0.001,
      preset: profile.reverbPreset.wireValue,
      wetDry: (wetDry * (caps?.reverbScale ?? 1.0)).clamp(0.0, 1.0),
    );
  }

  /// Detects the current output route's real capabilities for display.
  Future<EarbudCapabilities> detectEarbudCapabilities() async {
    final service = _earbudOptimizationService;
    if (service == null) {
      return const EarbudCapabilities(
        deviceName: 'Default output',
        codec: EarbudCodec.unknown,
        isBluetooth: false,
        isLeAudio: false,
        isUsbDac: false,
        sampleRateHz: 44100,
        bitDepth: 16,
        latencyMs: 0,
      );
    }
    var info = _hiResAudioService?.currentOutputInfo;
    try {
      info ??= await _hiResAudioService?.getAudioOutputInfo();
    } catch (_) {
      info = null;
    }
    return service.detect(info);
  }

  Future<void> _applyQuranProfile(QuranReciterStyle style) async {
    final profile = QuranModeProfile.forStyle(style);
    final caps = _earbudOptimizationService
        ?.detect(_hiResAudioService?.currentOutputInfo);
    final gains = caps == null
        ? profile.eqGains
        : _earbudOptimizationService!.mergeCompensation(profile.eqGains, caps);

    // 1. Vocal-optimized EQ (bulk apply, single native push).
    await applyPreset(profile.toEqPreset(gains));
    try {
      await _audioHandler.equalizerManager.setPreamp(profile.preampDb);
    } catch (_) {}

    // 2. Room / mosque-style convolution reverb, scaled for lossy Bluetooth.
    await setReverb(
      profile.reverbEnabled,
      preset: profile.reverbPreset.wireValue,
      wetDry:
          (profile.reverbWetDry * (caps?.reverbScale ?? 1.0)).clamp(0.0, 1.0),
    );

    // 3. Gentle harmonic warmth.
    await setSaturation(
      profile.saturationEnabled,
      drive: profile.saturationDrive,
      mix: profile.saturationMix,
      tilt: profile.saturationTilt,
    );

    // 4. Vocal dynamics.
    await setDynamicsPreset(
      profile.dynamicsPreset,
      enabled: profile.dynamicsEnabled,
    );

    // 5. Learning speed (memorization style only; others are 1.0x).
    if ((state.playbackSpeed - profile.playbackSpeed).abs() > 0.001) {
      await setPlaybackSpeed(profile.playbackSpeed);
    }

    // 6. Continuous order: recitation is never shuffled.
    if (state.isShuffle) {
      await toggleShuffle();
    }
  }

  _QuranRestoreSnapshot _captureQuranRestoreSnapshot() {
    return _QuranRestoreSnapshot(
      eqPreset: state.eqPreset,
      isEqEnabled: state.isEqEnabled,
      headphoneProfile: state.selectedHeadphoneProfile,
      isReverbEnabled: state.isReverbEnabled,
      reverbPreset: state.reverbPreset,
      reverbWetDry: state.reverbWetDry,
      isDynamicsEnabled: state.isDynamicsEnabled,
      dynamicsPreset: state.dynamicsPreset,
      isSaturationEnabled: state.isSaturationEnabled,
      saturationDrive: state.saturationDrive,
      saturationMix: state.saturationMix,
      saturationTilt: state.saturationTilt,
      playbackSpeed: state.playbackSpeed,
      isShuffle: state.isShuffle,
      preampDb: _audioHandler.equalizerManager.preampDb,
    );
  }

  Future<void> _restoreQuranSnapshot() async {
    final s = _quranRestore;
    if (s == null) return;
    if (s.headphoneProfile != null) {
      await applyHeadphoneProfile(s.headphoneProfile);
    } else {
      await applyPreset(s.eqPreset);
    }
    await setEqualizerEnabled(s.isEqEnabled);
    try {
      await _audioHandler.equalizerManager.setPreamp(s.preampDb);
    } catch (_) {}
    await setReverb(s.isReverbEnabled,
        preset: s.reverbPreset, wetDry: s.reverbWetDry);
    await setDynamicsPreset(s.dynamicsPreset, enabled: s.isDynamicsEnabled);
    await setSaturation(s.isSaturationEnabled,
        drive: s.saturationDrive, mix: s.saturationMix, tilt: s.saturationTilt);
    await setPlaybackSpeed(s.playbackSpeed);
    if (state.isShuffle != s.isShuffle) {
      await toggleShuffle();
    }
  }

  Future<void> _persistQuranSnapshot(_QuranRestoreSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          PrefsKeys.quranRestoreSnapshot, jsonEncode(snapshot.toJson()));
    } catch (e, st) {
      ErrorLogger.log('Failed to persist Quran Mode restore snapshot',
          error: e, stackTrace: st, category: 'PlayerCubit');
    }
  }

  Future<_QuranRestoreSnapshot?> _loadQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefsKeys.quranRestoreSnapshot);
      if (raw == null || raw.isEmpty) return null;
      return _QuranRestoreSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      ErrorLogger.log('Failed to load Quran Mode restore snapshot',
          error: e, stackTrace: st, category: 'PlayerCubit');
      return null;
    }
  }

  Future<void> _clearQuranSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefsKeys.quranRestoreSnapshot);
    } catch (_) {}
  }

  // ── F9: DSP snapshot ─────────────────────────────────────────────────
  Future<void> saveDspSnapshot() => _audioHandler.saveDspSnapshotForCurrent();

  @override
  Future<void> close() async {
    _persistQueueDebounce?.cancel();
    _scrobbleDebounce?.cancel();
    _seekThrottleTimer?.cancel();
    _seekThrottleTimer = null;
    _pendingSeek = null;
    try {
      await _widgetClickSub?.cancel();
    } catch (_) {}
    _widgetClickSub = null;
    // Final persist: the cancelled debounce would otherwise lose the most
    // recent slot state (e.g. the near-live position written by the position
    // listener). Awaited so the write lands before the cubit is gone.
    try {
      await _persistQueueSlots();
    } catch (_) {}
    return super.close();
  }
}
