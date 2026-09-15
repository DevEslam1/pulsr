// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/battery_optimization_service.dart';
import '../../core/services/hires_audio_service.dart';
import '../../core/services/smart_audio_service.dart';
import '../../core/services/ytm_service.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../core/telemetry/audio_session_log.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/audio_output_info.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/models/ytm_track.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';
import 'audio_effects_channel.dart';
import 'audio_session_id_router.dart';
import 'crossfade_manager.dart';
import 'interruption_state_machine.dart';
import 'equalizer_manager.dart';
import 'sleep_timer_manager.dart';
import 'ytm_resolving_source.dart';
import '../../core/services/ytm_cache_manager.dart';
import 'adaptive_buffer_engine.dart';
import 'audio_memory_manager.dart';
import 'battery_aware_playback.dart';
import 'format_aware_decoder.dart';
import 'optimized_dsp_pipeline.dart';
import 'output_format_negotiation.dart';
import 'playback_analytics.dart';
import 'replay_gain_math.dart';
import 'smart_preload_scheduler.dart';
import 'stream_pre_resolver.dart';
import 'triple_buffer_pipeline.dart';
import 'dsd_decoder_helper.dart';
import 'mqa_decoder_helper.dart';
import '../../core/services/ytm_url_cache.dart';
import 'collaborators/float_output_controller.dart';
import 'collaborators/aaudio_output_controller.dart';
import 'collaborators/playback_volume_controller.dart';
import 'collaborators/stream_resolution_pipeline.dart';
import 'ab_loop_manager.dart';
import 'adaptive_quality_manager.dart';
import 'bpm_override_store.dart';
import 'per_song_volume_store.dart';
import 'dsp_snapshot_store.dart';
import 'ducking_controller.dart';
import 'gapless_trim_handler.dart';
import 'hedged_stream_resolver.dart';
import 'multi_output_router.dart';
import 'playback_bookmark_store.dart';
import 'silence_skip_controller.dart';
import 'track_delay_manager.dart';
import 'audio_handler_lifecycle_observer.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  @factoryMethod
  static Future<PulsrAudioHandler> create(
      IMusicRepository repository, YtmService ytmService) async {
    // The instance is captured so that if AudioService.init times out we can
    // reuse the very instance its builder produced. A late completion of the
    // in-flight init then binds THIS handler instead of creating and binding a
    // second, state-less one (B-2).
    PulsrAudioHandler? built;
    // If the platform handshake times out before `builder` runs, this holds the
    // degraded-mode instance the app has already fallen back to. The builder
    // adopts it instead of constructing a second, unbound handler, so a late
    // init success binds the very instance the UI drives (B-2/B-6).
    PulsrAudioHandler? fallback;
    final initFuture = AudioService.init(
      builder: () {
        built = fallback ?? PulsrAudioHandler(repository, ytmService);
        return built!;
      },
      // The channel name stays English on purpose (C-6): the config is a const
      // evaluated while dependencies are still being constructed, before any
      // SettingsCubit / MaterialApp has resolved the *app-selected* locale — the
      // platform locale alone would mislabel the channel for users who picked a
      // different language than the system one, and Android only applies a
      // channel's name when the channel is first created, so a later re-resolve
      // could not fix it anyway.
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.pulsr.music.audio',
        androidNotificationChannelName: 'Pulsr Audio Playback',
        androidNotificationChannelDescription:
            'Playback controls and now-playing information for Pulsr Music.',
        androidNotificationOngoing: true,
        androidNotificationClickStartsActivity: true,
        androidStopForegroundOnPause: true,
        androidResumeOnClick: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
    try {
      return await initFuture.timeout(const Duration(seconds: 10));
    } catch (e, st) {
      ErrorLogger.log(
          'AudioService.init failed or timed out: running in degraded audio '
          'mode (playback works, but there is no media notification / '
          'foreground service)',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      // Fall back to the instance the builder created (if it got that far);
      // otherwise adopt this one so a late init success binds the same handler
      // the app is already using instead of orphaning it (B-2/B-6).
      fallback = built ?? PulsrAudioHandler(repository, ytmService);
      fallback.platformBridgeDegraded.value = true;
      return fallback;
    }
  }

  final AudioPlayer _playerA;
  final AudioPlayer _playerB;
  final AudioPlayer _prefetchPlayer;
  bool _isPlayerAActive = true;
  int _generationCounter = 0;
  int get generationCounter => _generationCounter;
  AudioPlayer get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  AudioPlayer get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;
  AudioPlayer get prefetchPlayer => _prefetchPlayer;

  /// Returns playback position compensated for native and DSP pipeline latency.
  Duration get compensatedPosition =>
      _dspPipeline.getCompensatedPosition(_activePlayer.position);

  final IMusicRepository _repository;
  final YtmService _ytmService;
  final CrossfadeManager _crossfadeManager = CrossfadeManager();
  final SleepTimerManager _sleepTimerManager = SleepTimerManager();
  late final EqualizerManager _equalizerManager;
  late final AudioSessionIdRouter _audioSessionIdRouter;
  int? _playerASessionId;
  int? _playerBSessionId;

  List<SongsTableData> _songs = [];
  int _currentIndex = 0;
  bool _queueDirty = false;
  double? _preDuckVolume;
  // ignore: unused_field
  double? _preDuckInactiveVolume;
  // ignore: unused_field, prefer_final_fields
  bool _duckActive = false;
  /// Pure, testable interruption bookkeeping (B-1). Replaces the previous pair
  /// of loose booleans whose begin/end bookkeeping was asymmetric.
  final InterruptionStateMachine _interruption = InterruptionStateMachine();
  // ignore: unused_field
  DateTime? _lastNoisyTime;
  int _consecutiveFailures = 0;
  DateTime? _lastGaplessChangeTime;
  int _rapidGaplessChangeCount = 0;
  // Last time a track-completion was reported to the sleep timer. Gapless
  // playback reports one boundary through two independent signals (the native
  // `ProcessingState.completed` event and the `currentIndexStream` advance), so
  // this debounce collapses the duplicate. See [_notifySleepTrackCompleted].
  DateTime? _lastSleepTrackCompletedAt;
  final List<int> _shuffleHistory = [];
  DateTime? _lastPreviousTapTime;
  bool _isManualSkip = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  int _playGeneration = 0;
  // Seek throttling: optimistic UI + debounced backend seeks.
  int _lastSeekMs = 0;
  Duration? _pendingSeekPosition;
  Timer? _seekDebounceTimer;
  int _lastSmartPrefetchMs = 0;
  String? _lastSmartPrefetchKey;
  Timer? _crossfadeSwitchDebounce;
  AudioHandlerLifecycleObserver? _lifecycleObserver;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  Duration? _pendingLazyPosition;
  // Memoized stream URLs, keyed by video id. Never persisted — they expire.
  final LinkedHashMap<String,
          ({String url, DateTime expires, String? userAgent, String? cookies})>
      _streamCache = LinkedHashMap();
  // Active stream URL resolutions, keyed by videoId-quality. Deduplicates concurrent
  // requests (e.g. background pre-warm and YtmResolvingSource.request()).
  final Map<
      String,
      Future<
          ({
            String url,
            String? userAgent,
            String? cookies,
            String quality
          })>> _inFlightResolves = {};
  // Video ids with an in-flight prefetch, so we resolve each at most once.
  final Set<String> _prefetching = {};

  String _currentStreamingQuality() =>
      _cachedPrefs?.getString('setting_streaming_quality') ?? 'high';

  final AdaptiveBufferEngine _adaptiveBufferEngine = AdaptiveBufferEngine();
  final OptimizedDspPipeline _dspPipeline = OptimizedDspPipeline();
  late final PlaybackAnalytics _playbackAnalytics;
  late final AudioMemoryManager _memoryManager;
  late final SmartPreloadScheduler _preloadScheduler;
  late final FormatAwareDecoder _formatDecoder;
  late final TripleBufferPipeline _tripleBufferPipeline;
  late final BatteryAwarePlayback _batteryAwarePlayback;
  late final StreamPreResolver _streamPreResolver;
  late final PlaybackVolumeController _volumeController;
  /// Set once [_volumeController] has been assigned in the (async) init. The
  /// settings cubit can emit — and call setVolume() — before that happens on a
  /// cold start, which used to throw a LateInitializationError on every launch.
  bool _volumeControllerReady = false;
  late final StreamResolutionPipeline _streamResolutionPipeline;
  // ── F1–F11 feature managers ──────────────────────────────────────────
  final AbLoopManager abLoopManager = AbLoopManager();
  final TrackDelayManager trackDelayManager = TrackDelayManager();
  final AdaptiveQualityManager adaptiveQualityManager =
      AdaptiveQualityManager();
  final DuckingController duckingController = DuckingController();
  final MultiOutputRouter multiOutputRouter = MultiOutputRouter();  final DspSnapshotStore dspSnapshotStore = DspSnapshotStore();
  final SilenceSkipController silenceSkipController = SilenceSkipController();
  final BpmOverrideStore bpmOverrideStore = BpmOverrideStore();
  final PlaybackBookmarkStore bookmarkStore = PlaybackBookmarkStore();
  bool hedgedResolutionEnabled = true;
  DateTime? _lastBookmarkSave;
  DateTime? _lastHealthyReport;

  // Gapless engine: when crossfade is off, AudioPlayer's built-in playlist on the
  // active player is the source of truth for track order/advance, and just_audio
  // joins consecutive items seamlessly. False while crossfade (duration > 0) is
  // active, which keeps the manual dual-player path below.
  bool _gaplessLoaded = false;
  // Last index reacted to from currentIndexStream, to drop duplicate emits.
  int _lastGaplessIndex = -1;

  // Guard against session restoration stomping over user-initiated playback on cold start
  bool _userPlaybackInitiated = false;
  // Target index for current gapless load; used to filter transient ExoPlayer index 0 emits
  int? _gaplessTargetIndex;
  DateTime? _gaplessLoadTime;
  bool _gaplessTargetReached = false;

  /// User-facing gapless toggle (persisted as `setting_gapless`). Gapless is
  /// the default engine but is mutually exclusive with crossfade.
  bool _gaplessEnabled = true;
  bool get isGaplessEnabled => _gaplessEnabled;

  /// Gapless is the default engine. Enabling crossfade (duration > 0) switches
  /// to the overlapping dual-player engine, which cannot also produce a seamless
  /// join, so the two are mutually exclusive by construction. An explicit
  /// gapless OFF also falls back to per-track playback when crossfade is 0.
  bool get _gaplessMode =>
      _gaplessEnabled && _crossfadeManager.duration <= Duration.zero;

  final StreamController<SongsTableData> _onTrackChangedSubject =
      StreamController<SongsTableData>.broadcast();
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedSubject.stream;
  SongsTableData? _lastPlayedSong;

  // T10: CUE sub-track boundaries. Both flags reset on track change so each
  // virtual track seeks once to its start and advances once at its end.
  bool _cueStartSeeked = false;
  bool _cueAdvanceTriggered = false;

  bool _positionDirty = false;
  Timer? _positionSaveTimer;
  Timer? _fadeInGuardTimer; // FIX-#12: tracked for disposal
  final StreamController<Duration> _positionSubject =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionSubject.stream;

  final StreamController<Duration> _highRatePositionSubject =
      StreamController<Duration>.broadcast();
  /// High-rate stream (~16ms granularity, 60fps) for fluid waveform seeks.
  Stream<Duration> get highRatePositionStream => _highRatePositionSubject.stream;
  int _lastHighRatePositionEmitMs = 0;

  /// Stream of playback positions compensated for DSP and native hardware latency.
  Stream<Duration> get compensatedPositionStream =>
      _positionSubject.stream.map((pos) => _dspPipeline.getCompensatedPosition(pos));

  final StreamController<String> _errorSubject =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorSubject.stream;
  int? _currentAudioSessionId;
  final StreamController<int?> _audioSessionIdSubject =
      StreamController<int?>.broadcast();

  /// The Android audio session id of the active player, or null when the
  /// platform has not yet assigned one (or on non-Android). Consumers such as
  /// the visualizer attach to this real session instead of the global mix.
  int? get currentAudioSessionId => _currentAudioSessionId;
  Stream<int?> get audioSessionIdStream => _audioSessionIdSubject.stream;
  SongsTableData? get currentSong =>
      (_songs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _songs.length)
          ? _songs[_currentIndex]
          : null;
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerManager.sleepTimerRemainingStream;
  Stream<int?> get sleepTimerRemainingTracksStream =>
      _sleepTimerManager.sleepTimerRemainingTracksStream;
  int? get sleepTimerRemainingTracks =>
      (_sleepTimerManager.isArmed &&
              (_sleepTimerManager.mode == SleepTimerMode.endOfTrack ||
                  _sleepTimerManager.mode == SleepTimerMode.afterNTracks))
          ? _sleepTimerManager.remainingTracks
          : null;
  SleepTimerMode get sleepTimerMode => _sleepTimerManager.mode;

  PlaybackLatencyTracker? get _latencyTracker =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;
  int _lastPositionEmitMs = 0;
  double? _preCrossfadeVolume;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PulsrAudioHandler._({
    required IMusicRepository repository,
    required YtmService ytmService,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AudioPlayer? prefetchPlayer,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
  })  : _repository = repository,
        _ytmService = ytmService,
        _playerA = playerA,
        _playerB = playerB,
        _prefetchPlayer = prefetchPlayer ?? AudioPlayer() {
    _equalizerManager = EqualizerManager(
      loudnessEnhancerA: loudnessEnhancerA,
      loudnessEnhancerB: loudnessEnhancerB,
    );
    _audioSessionIdRouter = AudioSessionIdRouter(
      onSessionChanged: (sessionId) {
        _equalizerManager.reapplyToSession(sessionId);
        _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        _currentAudioSessionId = sessionId;
        _audioSessionIdSubject.add(sessionId);
      },
      onRouteChanged: () {
        _syncBluetoothRouteFromCache();
        _equalizerManager.resyncActiveEffects();
        _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        unawaited(_refreshBluetoothRoute());
        unawaited(_recordSessionRouteChange());
      },
    );
    if (getIt.isRegistered<EqualizerManager>()) {
      getIt.unregister<EqualizerManager>();
    }
    getIt.registerSingleton<EqualizerManager>(_equalizerManager);
    if (getIt.isRegistered<AdaptiveBufferEngine>()) {
      getIt.unregister<AdaptiveBufferEngine>();
    }
    getIt.registerSingleton<AdaptiveBufferEngine>(_adaptiveBufferEngine);
    // Backstop: if _init() throws before reaching its restore block, the
    // effects-ready signal must still fire so listeners aren't left waiting.
    _init().whenComplete(() {
      if (!_effectsReadyCompleter.isCompleted) {
        _effectsReadyCompleter.complete();
      }
      // Restore a persisted sleep timer (process death / background kill).
      // Fire-and-forget: re-arms only duration timers still in the future.
      unawaited(_sleepTimerManager.restorePersistedState(
        onTimerExpired: () async => pause(),
        getActivePlayer: () => _activePlayer,
      ));
    });
  }

  EqualizerManager get equalizerManager => _equalizerManager;
  AudioSessionIdRouter get audioSessionIdRouter => _audioSessionIdRouter;
  AdaptiveBufferEngine get adaptiveBufferEngine => _adaptiveBufferEngine;
  OptimizedDspPipeline get dspPipeline => _dspPipeline;
  PlaybackAnalytics get playbackAnalytics => _playbackAnalytics;
  AudioMemoryManager get memoryManager => _memoryManager;
  SmartPreloadScheduler get preloadScheduler => _preloadScheduler;
  FormatAwareDecoder get formatDecoder => _formatDecoder;
  TripleBufferPipeline get tripleBufferPipeline => _tripleBufferPipeline;
  BatteryAwarePlayback get batteryAwarePlayback => _batteryAwarePlayback;
  StreamPreResolver get streamPreResolver => _streamPreResolver;
  PlaybackVolumeController get volumeController => _volumeController;
  StreamResolutionPipeline get streamResolutionPipeline => _streamResolutionPipeline;

  /// Observable degraded-mode flag (B-2): true when [AudioService.init] failed
  /// or timed out, so playback runs without a platform media bridge (no
  /// notification / mediaPlayback foreground service). The UI can read this to
  /// surface the condition; it is never set on a healthy start-up.
  final ValueNotifier<bool> platformBridgeDegraded = ValueNotifier<bool>(false);

  /// Mirrors the cached output route's Bluetooth flag into the effects layer.
  /// Synchronous (uses the HiResAudioService cache) so a route-change resync
  /// sees the new route immediately instead of hardcoding a wired route.
  void _syncBluetoothRouteFromCache() {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final info = getIt<HiResAudioService>().currentOutputInfo;
      if (info != null) _equalizerManager.isBluetoothRoute = info.isBluetooth;
    } catch (_) {}
  }

  /// Refreshes the cached output info from native, then mirrors the route.
  Future<void> _refreshBluetoothRoute() async {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final info = await getIt<HiResAudioService>().getAudioOutputInfo();
      _equalizerManager.isBluetoothRoute = info.isBluetooth;
    } catch (_) {}
  }

  // ── Per-session audio telemetry (pure Dart, best-effort) ───────────────
  // One record per playback session: route/codec/negotiated format plus any
  // route change, interruption and underrun/dropout count. Every call is
  // fire-and-forget; the service never throws and is a no-op when disabled.

  Future<AudioOutputInfo?> _currentOutputInfo() async {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return null;
      return await getIt<HiResAudioService>().getAudioOutputInfo();
    } catch (_) {
      return null;
    }
  }

  Future<void> _beginAudioSession(SongsTableData song) async {
    try {
      final log = AudioSessionLog.instance;
      // Restore/preload paths can re-notify the same track; keep one session.
      if (log.activeTrackId == song.id.toString()) return;
      final info = await _currentOutputInfo();
      await log.startSession(
        trackId: song.id.toString(),
        trackTitle: song.title,
        routeType: AudioSessionLog.routeTypeForInfo(info),
        bluetoothCodec: info?.btCodecName,
        sampleRate: info?.sampleRate ?? song.sampleRate,
        bitDepth: info?.bitDepth ?? song.bitDepth,
        bitrateKbps: song.bitrateKbps,
      );
    } catch (_) {}
  }

  Future<void> _recordSessionRouteChange() async {
    try {
      if (!AudioSessionLog.instance.hasActiveSession) return;
      final info = await _currentOutputInfo();
      if (info == null) return;
      await AudioSessionLog.instance.updateOutputInfo(
        routeType: AudioSessionLog.routeTypeForInfo(info),
        bluetoothCodec: info.btCodecName,
        sampleRate: info.sampleRate,
        bitDepth: info.bitDepth,
      );
    } catch (_) {}
  }

  factory PulsrAudioHandler(
      IMusicRepository repository, YtmService ytmService) {
    if (Platform.isAndroid) {
      final loadConfig = _loadConfigForBucket(BufferBucket.standard);

      final playerA = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      final playerB = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      final prefetchPlayer = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
      );
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: playerA,
        playerB: playerB,
        prefetchPlayer: prefetchPlayer,
      );
    } else {
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: AudioPlayer(useLazyPreparation: true),
        playerB: AudioPlayer(useLazyPreparation: true),
        prefetchPlayer: AudioPlayer(useLazyPreparation: true),
      );
    }
  }

  static MediaItem _songToMediaItem(SongsTableData song, [Uri? artUri]) {
    Uri? finalArtUri = (artUri != null &&
            artUri.hasScheme &&
            (artUri.host.isNotEmpty || artUri.path.isNotEmpty))
        ? artUri
        : null;

    if (finalArtUri == null) {
      final artString = (song.artworkUri != null && song.artworkUri!.isNotEmpty)
          ? song.artworkUri!
          : (song.remoteArtworkUrl != null && song.remoteArtworkUrl!.isNotEmpty)
              ? song.remoteArtworkUrl!
              : null;
      if (artString != null) {
        final parsed = Uri.tryParse(artString);
        if (parsed != null &&
            parsed.hasScheme &&
            (parsed.host.isNotEmpty ||
                parsed.scheme == 'file' ||
                parsed.scheme == 'content')) {
          finalArtUri = parsed;
        }
      }
    }

    return MediaItem(
      id: song.id.toString(),
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: Duration(milliseconds: song.durationMs),
      artUri: finalArtUri,
      extras: {
        'path': song.path,
        'uri': song.uri,
        'albumId': song.albumId,
        'artistId': song.artistId,
        'isFavorite': song.isFavorite,
        'trackNumber': song.trackNumber,
        'discNumber': song.discNumber,
        'year': song.year,
        'genre': song.genre,
        'playCount': song.playCount,
        'remoteId': song.remoteId,
        'source': song.source,
        'isDownloaded': song.isDownloaded,
        'remoteArtworkUrl': song.remoteArtworkUrl,
      },
    );
  }

  SharedPreferences? _cachedPrefs;

  Future<void> _initPrefs() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }

  double _volume = 1.0;
  double get volume => _volume;

  /// Direct Volume Control: when true the composed gain is applied in the
  /// native float DSP path and player volume stays at unity.
  bool _dvcEnabled = false;
  bool get isDvcEnabled => _dvcEnabled;

  /// Assumed Android mixer rate until the real output rate is known. The HAL
  /// only reports it after the first AudioTrack opens, so cold-start DSP
  /// coefficient init uses this; per-track [AudioEffectsChannel.resyncForTrack]
  /// in [_notifyTrackChanged] corrects it once real header rates arrive.
  static const double assumedOutputSampleRate = 48000.0;

  double _calculateReplayGainVolume(SongsTableData? song) {
    if (song == null) {
      if (_dvcEnabled) {
        unawaited(_pushDvcGain(_volume));
        return 1.0;
      }
      return _volume;
    }

    final prefs = _cachedPrefs;
    if (prefs == null) return _volume; // Null guard

    // Strict Bit-Perfect: bypass ReplayGain completely to preserve exact PCM samples
    final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
        (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
    if (bitPerfect) return _volume;

    final dvc = _dvcEnabled;
    var scaled = ReplayGainMath.apply(
      mode: prefs.getString(PrefsKeys.replayGainMode) ?? 'track',
      // Under DVC the user volume is applied by the native float stage, so the
      // player-side mixer carries only ReplayGain. This keeps crossfade and
      // ducking (which scale the player volume) fully functional.
      volume: dvc ? 1.0 : _volume,
      trackGainDb: song.replayGainTrack,
      trackPeak: song.replayGainTrackPeak,
      albumGainDb: song.replayGainAlbum,
      albumPeak: song.replayGainAlbumPeak,
      albumContext: _isConsecutiveAlbumPlayback(),
      preampWithRg: prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
      // Default 0dB: untagged tracks must not be attenuated without consent.
      preampWithoutRg:
          prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0,
    );
    // Per-song volume override (dB) applied in the single mixer stage.
    try {
      final perSongDb = _perSongVolumeDbFor(song);
      if (perSongDb != 0.0) {
        final factor = math.pow(10, perSongDb / 20).toDouble();
        scaled = (scaled * factor).clamp(0.0, 1.0);
      }
    } catch (_) {}
    if (dvc) {
      // Only the active track's user volume is authoritative for the single
      // native DVC stage; other (crossfade) calculations must not clobber it.
      if (song.id == currentSong?.id) {
        unawaited(_pushDvcGain(_volume));
      }
      return scaled;
    }
    return scaled;
  }

  /// Pushes the user-volume component to the native Direct Volume Control
  /// stage (applied in the float DSP path). ReplayGain/per-song/fades stay in
  /// the player mixer.
  Future<void> _pushDvcGain(double gain) async {
    try {
      await AudioEffectsChannel().setDvcGain(gain.clamp(0.0, 4.0));
    } catch (_) {}
  }

  /// Reads the per-song volume override without a hard DI dependency so unit
  /// test doubles of the handler keep working.
  double _perSongVolumeDbFor(SongsTableData song) {
    try {
      final store = getIt.isRegistered<PerSongVolumeStore>()
          ? getIt<PerSongVolumeStore>()
          : null;
      if (store == null) return 0.0;
      final key = song.id.toString();
      return store.getGainDbForTrack(key);
    } catch (_) {
      return 0.0;
    }
  }

  /// Pushes ReplayGain tags to the native DSP pre-gain stage.
  /// Single-stage mode: the mixer in [_calculateReplayGainVolume] is the
  /// source of truth, so the native stage is kept disabled to avoid applying
  /// the same gain twice. Non-Android / bit-perfect: same (disabled).
  Future<void> _pushNativeReplayGain(SongsTableData? song) async {
    try {
      await AudioEffectsChannel().setReplayGainEnabled(false);
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final song = currentSong;
    final target = _calculateReplayGainVolume(song);
    // Guard the startup race: the settings cubit's first emission can arrive
    // before the async init has constructed the volume controller.
    if (_volumeControllerReady) {
      _volumeController.updateSettings(userVolume: _volume);
    }
    await _equalizerManager.updateLoudnessVolume(_volume);
    await _activePlayer.setVolume(target);
    unawaited(_pushNativeReplayGain(song));
  }

  /// Toggles Direct Volume Control. Enabling pins Android's media stream to
  /// maximum and applies the composed gain in the native float DSP path;
  /// disabling restores the previous system volume. No-op when native DVC is
  /// unsupported (the preference push is then rolled back by the caller path).
  Future<void> setDvcEnabled(bool enabled) async {
    if (enabled == _dvcEnabled) {
      if (enabled) {
        await AudioEffectsChannel().setDvcEnabled(true);
      }
      return;
    }
    if (enabled) {
      final supported = await AudioEffectsChannel().isDvcSupported();
      if (!supported) {
        _dvcEnabled = false;
        await AudioEffectsChannel().setDvcEnabled(false);
        return;
      }
      _dvcEnabled = true;
      await AudioEffectsChannel().setDvcEnabled(true);
    } else {
      _dvcEnabled = false;
      await AudioEffectsChannel().setDvcEnabled(false);
    }
    // Re-apply the current volume so the new gain stage takes effect now.
    await setVolume(_volume);
  }

  bool get isEqualizerEnabled => _equalizerManager.isEnabled;
  EqPreset get currentPreset => _equalizerManager.currentPreset;
  bool get isVirtualizerEnabled => _equalizerManager.isVirtualizerEnabled;
  double get virtualizerStrength => _equalizerManager.virtualizerStrength;
  bool get isDynamicsEnabled => _equalizerManager.isDynamicsEnabled;
  bool get isDynamicsEffectivelyEnabled =>
      _equalizerManager.isDynamicsEffectivelyEnabled;
  bool get isDynamicsBypassed => _equalizerManager.isDynamicsBypassed;
  DynamicsPreset get dynamicsPreset => _equalizerManager.dynamicsPreset;
  HeadphoneProfile? get selectedHeadphoneProfile =>
      _equalizerManager.selectedHeadphoneProfile;
  Duration get crossfadeDuration => _crossfadeManager.duration;

  void setCrossfadeDuration(Duration duration) {
    final wasGapless = _gaplessMode;
    _crossfadeManager.duration = duration;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  /// Applies the persisted gapless toggle. Switching it (queue non-empty)
  /// re-selects the gapless playlist engine or the per-track player.
  void setGaplessEnabled(bool enabled) {
    if (_gaplessEnabled == enabled) return;
    final wasGapless = _gaplessMode;
    _gaplessEnabled = enabled;
    final isGapless = _gaplessMode;
    if (wasGapless != isGapless) {
      _scheduleEngineSwitch(toGapless: isGapless);
    }
  }

  void _scheduleEngineSwitch({required bool toGapless}) {
    if (_songs.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _songs.length) {
      return;
    }
    // Debounce slider drags: rapid toggles previously spawned concurrent
    // _switchPlaybackEngine calls that interleaved.
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_switchPlaybackEngine(toGapless: toGapless));
    });
  }

  int _engineSwitchGeneration = 0;

  Future<void> _switchPlaybackEngine({required bool toGapless}) async {
    final generation = ++_engineSwitchGeneration;
    final resumePos = _activePlayer.position;
    final wasPlaying = _activePlayer.playing;
    try {
      if (toGapless) {
        await _loadGaplessQueue(
            initialPosition: resumePos, preload: wasPlaying);
      } else {
        _gaplessLoaded = false;
        if (generation != _engineSwitchGeneration) return;
        if (wasPlaying) {
          await playSongAt(_currentIndex, initialPosition: resumePos);
        } else {
          if (_currentIndex >= 0 && _currentIndex < _songs.length) {
            final song = _songs[_currentIndex];
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            final item = _songToMediaItem(song, artUri);
            mediaItem.add(item);
            if (song.source != SongSource.youtube) {
              await _activePlayer.setAudioSource(
                _createAudioSource(song, item),
                initialPosition: resumePos,
                preload: false,
              );
            } else {
              _pendingLazyPosition = resumePos;
            }
            _broadcastState(_activePlayer.playbackEvent);
          }
        }
      }
      if (generation != _engineSwitchGeneration) return;
    } catch (e, st) {
      _pendingLazyPosition = null;
      ErrorLogger.log('Error switching playback engine on crossfade toggle',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _equalizerManager.setEqualizerEnabled(enabled);
  Future<void> setBandGain(int bandIndex, double gain) =>
      _equalizerManager.setBandGain(bandIndex, gain);
  Future<void> resetToFlat() => _equalizerManager.resetToFlat();
  Future<void> startAbComparison() => _equalizerManager.startAbComparison();
  Future<void> endAbComparison() => _equalizerManager.endAbComparison();
  bool get isAbComparisonActive => _equalizerManager.isAbComparisonActive;
  Future<void> setBassBoost(double value) =>
      _equalizerManager.setBassBoost(value);
  Future<void> applyPreset(EqPreset preset) =>
      _equalizerManager.applyPreset(preset);
  Future<void> applyHeadphoneProfile(HeadphoneProfile? profile) =>
      _equalizerManager.applyHeadphoneProfile(profile);
  Future<void> setVirtualizerEnabled(bool enabled) =>
      _equalizerManager.setVirtualizerEnabled(enabled);
  Future<void> setVirtualizerStrength(double strength) =>
      _equalizerManager.setVirtualizerStrength(strength);
  Future<void> setDynamicsPreset(DynamicsPreset preset, {bool? enabled}) =>
      _equalizerManager.setDynamicsPreset(preset, enabled: enabled);
  Future<void> toggleDynamicsBypass() =>
      _equalizerManager.toggleDynamicsBypass();
  bool get isSpatializerEnabled => _equalizerManager.isSpatializerEnabled;
  bool get isSpatializerSupported => _equalizerManager.isSpatializerSupported;
  bool get isVirtualizerSupported => _equalizerManager.isVirtualizerSupported;
  bool get isDynamicsSupported => _equalizerManager.isDynamicsSupported;
  bool get isBassBoostSupported => _equalizerManager.isBassBoostSupported;
  bool get isVolumeBoostSupported => _equalizerManager.isVolumeBoostSupported;
  bool get isHeadTrackerAvailable => _equalizerManager.isHeadTrackerAvailable;
  String get spatializerMode => _equalizerManager.spatializerMode;
  Future<void> setSpatializerMode(String mode) =>
      _equalizerManager.setSpatializerMode(mode);
  Future<void> setSpatializerEnabled(bool enabled) =>
      _equalizerManager.setSpatializerEnabled(enabled);
  double get volumeBoost => _equalizerManager.volumeBoost;
  Future<void> setVolumeBoost(double value) =>
      _equalizerManager.setVolumeBoost(value);
  Future<void> setCustomFrequencies(List<double> frequencies) =>
      _equalizerManager.setCustomFrequencies(frequencies);

  bool get is32BandMode => _equalizerManager.is32BandMode;
  Future<void> set32BandMode(bool enabled) =>
      _equalizerManager.set32BandMode(enabled);
  Future<void> switchComparisonSlot(ComparisonSlot slot) =>
      _equalizerManager.switchComparisonSlot(slot);
  String exportPresetToJson([EqPreset? preset]) =>
      _equalizerManager.exportPresetToJson(preset);
  Future<bool> importPresetFromJson(String jsonString) =>
      _equalizerManager.importPresetFromJson(jsonString);

  // Native DSP features
  bool get isCrossfeedEnabled => _equalizerManager.isCrossfeedEnabled;
  double get crossfeedDelayUs => _equalizerManager.crossfeedDelayUs;
  double get crossfeedFeedDb => _equalizerManager.crossfeedFeedDb;
  int get crossfeedMode => _equalizerManager.crossfeedMode;
  Future<void> setCrossfeed(bool enabled, {double? delayUs, double? feedDb, int? mode}) =>
      _equalizerManager.setCrossfeed(enabled, delayUs: delayUs, feedDb: feedDb, mode: mode);
  Future<void> setCrossfeedMode(int mode) =>
      _equalizerManager.setCrossfeedMode(mode);

  bool get isLimiterEnabled => _equalizerManager.isLimiterEnabled;
  double get limiterThresholdDb => _equalizerManager.limiterThresholdDb;
  double get limiterReleaseMs => _equalizerManager.limiterReleaseMs;
  Future<void> setLookaheadLimiter(bool enabled,
          {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      _equalizerManager.setLookaheadLimiter(enabled,
          thresholdDb: thresholdDb,
          releaseMs: releaseMs,
          lookaheadMs: lookaheadMs);

  bool get isReverbEnabled => _equalizerManager.isReverbEnabled;
  int get reverbPreset => _equalizerManager.reverbPreset;
  double get reverbWetDry => _equalizerManager.reverbWetDry;
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      _equalizerManager.setReverb(enabled, preset: preset, wetDry: wetDry);
  Future<bool> loadCustomImpulseResponse(List<double> irSamples) =>
      _equalizerManager.loadCustomImpulseResponse(irSamples);

  double get stereoBalance => _equalizerManager.stereoBalance;
  bool get monoMix => _equalizerManager.monoMix;
  Future<void> setStereoBalance(double balance) =>
      _equalizerManager.setStereoBalance(balance);
  Future<void> setMonoMix(bool mono) => _equalizerManager.setMonoMix(mono);

  bool get isSincResamplerEnabled => _equalizerManager.isSincResamplerEnabled;
  Future<void> setSincResampler(bool enabled) =>
      _equalizerManager.setSincResampler(enabled);

  bool get isDitherEnabled => _equalizerManager.isDitherEnabled;
  int get ditherTargetBitDepth => _equalizerManager.ditherTargetBitDepth;
  Future<void> setDither(bool enabled, {int? targetBitDepth}) =>
      _equalizerManager.setDither(enabled, targetBitDepth: targetBitDepth);

  Future<int> getPipelineLatencyFrames() =>
      _equalizerManager.getPipelineLatencyFrames();
  Future<void> setBandSolo(int index, bool solo) =>
      _equalizerManager.setBandSolo(index, solo);
  Future<void> setBandMute(int index, bool mute) =>
      _equalizerManager.setBandMute(index, mute);

  /// Whether a completion report at [now] is distinct from a previous one at
  /// [last]. Split out so the debounce window is unit-testable.
  @visibleForTesting
  static bool isDistinctSleepCompletion(DateTime? last, DateTime now) =>
      last == null ||
      now.difference(last) >= const Duration(milliseconds: 1500);

  /// Single funnel for "a track finished" so the sleep timer's after-N-tracks
  /// and end-of-track modes decrement exactly once per boundary. In gapless
  /// mode a boundary is reported twice — native `completed` plus the
  /// `currentIndexStream` advance — and feeding both straight into
  /// [SleepTimerManager.onTrackCompleted] halved an "after N songs" timer.
  void _notifySleepTrackCompleted() {
    final now = DateTime.now();
    if (!isDistinctSleepCompletion(_lastSleepTrackCompletedAt, now)) return;
    _lastSleepTrackCompletedAt = now;
    unawaited(_sleepTimerManager.onTrackCompleted());
  }

  // Sleep Timer controls
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    _sleepTimerManager.startSleepTimer(
      duration,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    final now = DateTime.now();
    final diff = stopTime.isAfter(now)
        ? stopTime.difference(now)
        : const Duration(minutes: 1);
    _sleepTimerManager.startSleepTimer(
      diff,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startEndOfTrackTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfTrackTimer(
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAfterNTracksTimer(int trackCount, {bool fadeOut = true}) {
    _sleepTimerManager.startAfterNTracksTimer(
      trackCount,
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void startEndOfQueueTimer({bool fadeOut = true}) {
    _sleepTimerManager.startEndOfQueueTimer(
      fadeOut: fadeOut,
      onTimerExpired: () async => pause(),
      getActivePlayer: () => _activePlayer,
    );
  }

  void cancelSleepTimer() {
    _sleepTimerManager.cancelSleepTimer();
  }

  bool get hasOemAudio => _equalizerManager.hasOemAudio;
  List<String> get detectedOemEngines => _equalizerManager.detectedOemEngines;

  Future<void> onAppPaused() async {
    await saveCurrentPositionImmediate();
    await _equalizerManager.onAppPaused();
  }

  Future<void> saveCurrentPositionImmediate() async {
    final hasPosition = _songs.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _songs.length;
    if (!hasPosition) {
      // Nothing to write; clear so the periodic timer does not spin.
      _positionDirty = false;
      return;
    }
    final currentSong = _songs[_currentIndex];
    final posMs = _activePlayer.position.inMilliseconds;
    try {
      await _repository.updateLastPosition(currentSong.id, posMs);
      if (_queueDirty) {
        await _repository.saveQueue(
            _songs.map((s) => s.id).toList(), _currentIndex, posMs);
        _queueDirty = false;
      }
      // Only clear AFTER a successful write: clearing first meant a failed
      // write was never retried and resume-after-kill could restore a stale
      // position (B-4).
      _positionDirty = false;
    } catch (e, st) {
      // Re-dirty so the periodic timer (and a later app pause) retries.
      _positionDirty = true;
      ErrorLogger.log('Failed to save current position',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  void _saveCurrentPosition() {
    _positionDirty = true;
  }

  void _initSaveTimer() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_positionDirty) {
        _positionDirty = false;
        saveCurrentPositionImmediate();
      }
    });
  }

  Future<void> _init() async {
    _initSaveTimer();
    AudioMemoryManager.adaptBudgetToSystemRam();
    await _initPrefs();
    // Restore the 24/32-bit float DSP path before any other player call so the
    // native sink is built with the persisted preference. Defaults ON so hi-res
    // sources are never truncated to 16-bit; 16-bit content is unaffected.
    await setFloatOutputEnabled(
      _cachedPrefs?.getBool(PrefsKeys.floatOutputEnabled) ?? true,
    );
    // Restore the opt-in AAudio Direct output before any other player call
    // so the sink is built with the persisted preference. Off by default.
    await setAaudioOutputEnabled(
      _cachedPrefs?.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
      preferExclusive:
          _cachedPrefs?.getBool(PrefsKeys.aaudioPreferExclusive) ?? true,
      targetBufferMs:
          _cachedPrefs?.getInt(PrefsKeys.aaudioTargetBufferMs) ?? 150,
    );
    // Restore the resampler quality and BPM-sync preference (defaults keep
    // the historical 64-tap polyphase and plain-duration crossfade).
    await AudioEffectsChannel().setSincResamplerQuality(
      _cachedPrefs?.getInt(PrefsKeys.sincResamplerQuality) ?? 3,
    );
    // Restore Direct Volume Control. Only the system-stream pinning needs to
    // happen here; per-track gain is applied by _calculateReplayGainVolume.
    _dvcEnabled = _cachedPrefs?.getBool(PrefsKeys.dvcEnabled) ?? false;
    if (_dvcEnabled) {
      unawaited(AudioEffectsChannel().setDvcEnabled(true));
    }
    _crossfadeManager.bpmSyncEnabled =
        _cachedPrefs?.getBool(PrefsKeys.bpmSyncCrossfadeEnabled) ?? false;

    _playbackAnalytics = PlaybackAnalytics(
      onIncreaseBufferSizeRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested buffer size increase');
        _adaptiveBufferEngine.forceBucket(BufferBucket.generous);
      },
      onReduceQualityRequested: () {
        debugPrint(
            '[AudioHandler] PlaybackAnalytics requested quality reduction');
        // F4: adaptive quality step-down mid-track.
        unawaited(_maybeAdaptiveStepDown());
      },
    );

    _memoryManager = AudioMemoryManager(
      onEvictOldestCacheRequested: () {
        AudioMemoryManager.trimStreamCache(_streamCache);
      },
      onBackgroundReleaseRequested: () {
        AudioMemoryManager.trimStreamCache(_streamCache);
      },
    );

    _preloadScheduler = SmartPreloadScheduler(
      onPreloadRequested: (song, {required priority}) async {
        if (song.source == SongSource.youtube && song.remoteId != null) {
          _prefetchStream(song);
        }
      },
      qualityProvider: _currentStreamingQuality,
    );

    _streamPreResolver = StreamPreResolver(
      resolveUrl: (videoId, {quality = 'high'}) =>
          _ytmService.resolveStream(videoId, quality: quality),
      urlCache: getIt.isRegistered<YtmUrlCache>()
          ? getIt<YtmUrlCache>()
          : YtmUrlCache(),
      qualityProvider: _currentStreamingQuality,
      isAlreadyPrefetching: (id) =>
          _prefetching.contains('$id:${_currentStreamingQuality().toLowerCase()}') ||
          _prefetching.contains(id),
    );

    _formatDecoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) => _resolveAudioSource(song, tag),
      decodeDsdToPcm: (song, tag) => DsdDecoderHelper.decodeDsdFile(song, tag),
    );

    _tripleBufferPipeline = TripleBufferPipeline(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
      prefetchPlayer: _prefetchPlayer,
      // Abort stale preloads: a resolve that outlives the track that
      // scheduled it must never setAudioSource on the now-active player.
      // Generation is the real guard (player objects are always distinct, so
      // `identical` alone can never detect a swap); crossfade state is the
      // secondary guard.
      isLoadStillValid: () => !_crossfadeManager.isCrossfading,
      getGeneration: () => _playGeneration,
      resolveAudioSource: (song, tag) => _resolveAudioSource(song, tag),
      songToMediaItem: (song, [fastArtUri]) =>
          _songToMediaItem(song, fastArtUri),
    );

    _batteryAwarePlayback = BatteryAwarePlayback(
      onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
        debugPrint('[AudioHandler] Battery low power mode triggered');
        if (reduceDsp) {
          unawaited(_equalizerManager.degradeToEssentials());
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
        debugPrint('[AudioHandler] Battery critical power mode triggered');
        if (disableCrossfade && _crossfadeManager.duration > Duration.zero) {
          setCrossfadeDuration(Duration.zero);
        }
        _adaptiveBufferEngine.forceBucket(BufferBucket.minimal);
      },
      onRestoreNormal: () {
        debugPrint('[AudioHandler] Battery restored to normal');
        unawaited(_equalizerManager.restoreFromDegrade());
        _adaptiveBufferEngine.releaseForce();
      },
    );

    _volumeController = PlaybackVolumeController(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
    );
    _volumeControllerReady = true;
    _streamResolutionPipeline = StreamResolutionPipeline(
      ytmService: _ytmService,
      getLatencyTracker: () => _latencyTracker,
    );

    _equalizerManager.attachDspPipeline(_dspPipeline);
    unawaited(_equalizerManager.syncNativeLatency(assumedOutputSampleRate));

    _subscriptions.add(
      _adaptiveBufferEngine.onBucketChanged.listen((bucket) {
        _onBufferBucketChanged(bucket);
      }),
    );

    _subscriptions.add(
      _adaptiveBufferEngine.onStepDownQualityRequested.listen((newQuality) {
        _onQualityStepDownRequested(newQuality);
      }),
    );

    _subscriptions.add(
      Stream.periodic(const Duration(seconds: 45)).listen((_) async {
        final level = await BatteryOptimizationService.getBatteryLevel();
        _batteryAwarePlayback.onBatteryLevelChanged(level);
      }),
    );
    BatteryOptimizationService.getBatteryLevel().then((level) {
      _batteryAwarePlayback.onBatteryLevelChanged(level);
    }).catchError((_) {});

    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      bool isTargetActive() =>
          isPlayerA == _isPlayerAActive && identical(player, _activePlayer);

      _subscriptions.add(
        player.playbackEventStream.listen(
          (event) {
            if (isTargetActive()) {
              if (event.processingState == ProcessingState.buffering &&
                  _activePlayer.playing) {
                _playbackAnalytics.recordBufferUnderrun();
                unawaited(AudioSessionLog.instance.recordUnderrun());
              }
              _broadcastState(event);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playbackEventStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.durationStream.listen(
          (dur) {
            if (isTargetActive() && dur != null && dur > Duration.zero) {
              final current = mediaItem.value;
              if (current != null && current.duration != dur) {
                mediaItem.add(current.copyWith(duration: dur));
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player durationStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.playerStateStream.listen(
          (state) async {
            if (isTargetActive()) {
              // Broadcast is driven solely by the playbackEventStream listener
              // above (C-5): playerStateStream is derived from the same event
              // stream, so broadcasting here serialised every transition to the
              // platform twice per state change.
              // Gapless loop-all support
              if (_gaplessMode &&
                  state.processingState == ProcessingState.completed &&
                  _activePlayer.loopMode == LoopMode.all) {
                await _activePlayer.seek(Duration.zero, index: 0);
                unawaited(_activePlayer.play());
                return;
              }
              // In gapless mode the ConcatenatingAudioSource advances itself, so a
              // `completed` event at the very end (repeat off) means the queue is
              // exhausted. The crossfade engine (one source per track) needs a
              // manual skip only while a next item exists; both paths report queue
              // completion so the sleep timer's endOfQueue mode can fire.
              if (state.processingState == ProcessingState.completed &&
                  !_crossfadeManager.isCrossfading) {
                if (_gaplessMode) {
                  if (_activePlayer.loopMode == LoopMode.off) {
                    // `completed` fires both mid-queue (while ExoPlayer swaps
                    // to the next item) and at the very end. Mid-queue the
                    // boundary is already reported by the `currentIndexStream`
                    // advance, so only the last item reports here — otherwise
                    // the after-N sleep timer decremented twice per song and
                    // end-of-queue fired at the first gap.
                    if (!_activePlayer.hasNext) {
                      _notifySleepTrackCompleted();
                      unawaited(_sleepTimerManager.onQueueCompleted());
                    }
                  }
                } else {
                  _notifySleepTrackCompleted();
                  if (_getNextIndex(peek: true) == null) {
                    unawaited(_sleepTimerManager.onQueueCompleted());
                  }
                  skipToNext();
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player playerStateStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.positionStream.listen(
          (pos) {
            if (isTargetActive()) {
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - _lastHighRatePositionEmitMs >= 16 || pos == Duration.zero) {
                _lastHighRatePositionEmitMs = now;
                if (!_highRatePositionSubject.isClosed) {
                  _highRatePositionSubject.add(pos);
                }
              }
              if (now - _lastPositionEmitMs >= 250 || pos == Duration.zero) {
                _lastPositionEmitMs = now;
                if (!_positionSubject.isClosed) {
                  _positionSubject.add(pos);
                }
              }
              // FIX-B03: Guard failure reset on position ticks: only reset when ready and pos > 2s
              if (player.processingState == ProcessingState.ready &&
                  pos > const Duration(seconds: 2) &&
                  _consecutiveFailures > 0) {
                _consecutiveFailures = 0;
              }
              // Only dirty the 2s DB writer while actually playing; otherwise
              // a paused track keeps rewriting the same position forever.
              if (player.playing) {
                _saveCurrentPosition();
                // F1: AB loop wrap.
                final wrap = abLoopManager.wrapTarget(pos,
                    songId: currentSong?.id);
                if (wrap != null) {
                  unawaited(_activePlayer.seek(wrap));
                }
                // T10: enter the CUE window once decodable, then advance at
                // its end. Guards prevent a seek/advance storm on position
                // ticks before the native transition lands.
                if (player.processingState == ProcessingState.ready) {
                  final cueSong = currentSong;
                  final cueStartMs = cueSong?.cueStartMs;
                  final cueEndMs = cueSong?.cueEndMs;
                  if (cueStartMs != null &&
                      !_cueStartSeeked &&
                      pos < Duration(milliseconds: cueStartMs)) {
                    _cueStartSeeked = true;
                    unawaited(
                        _activePlayer.seek(Duration(milliseconds: cueStartMs)));
                  }
                  if (cueEndMs != null) {
                    if (!_cueAdvanceTriggered &&
                        pos >= Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = true;
                      unawaited(skipToNext());
                    } else if (pos < Duration(milliseconds: cueEndMs)) {
                      _cueAdvanceTriggered = false;
                    }
                  }
                }
                // F11: autosave bookmark for long-form tracks (throttled 5s).
                final song = currentSong;
                if (song != null &&
                    PlaybackBookmarkStore.shouldBookmark(
                        durationMs: song.durationMs,
                        genre: song.genre,
                        album: song.album)) {
                  final nowDt = DateTime.now();
                  if (_lastBookmarkSave == null ||
                      nowDt.difference(_lastBookmarkSave!) >=
                          const Duration(seconds: 5)) {
                    _lastBookmarkSave = nowDt;
                    final key = PlaybackBookmarkStore.keyFor(
                        songId: song.id,
                        remoteId: song.remoteId,
                        path: song.path);
                    bookmarkStore.save(key, pos.inMilliseconds,
                        durationMs: song.durationMs);
                  }
                }
                // F4: report healthy playback windows for adaptive step-up.
                final nowH = DateTime.now();
                if (_lastHealthyReport == null ||
                    nowH.difference(_lastHealthyReport!) >=
                        const Duration(seconds: 30)) {
                  _lastHealthyReport = nowH;
                  unawaited(_maybeAdaptiveStepUp());
                }
              }
              final rawDuration = player.duration;
              final duration = (rawDuration != null && rawDuration > Duration.zero)
                  ? rawDuration
                  : ((currentSong?.durationMs != null && currentSong!.durationMs > 0)
                      ? Duration(milliseconds: currentSong!.durationMs)
                      : Duration.zero);
              // Warm the next YouTube stream URL before the crossfade window even
              // opens, so resolve latency does not truncate the fade. Cheap no-op
              // for local tracks and for an already-cached url.
              if (duration > const Duration(seconds: 15) &&
                  (pos >= duration - const Duration(seconds: 15) ||
                      pos.inMilliseconds >= duration.inMilliseconds * 0.7)) {
                _smartPrefetch();
              }
              final compensatedPos = _dspPipeline.getCompensatedPosition(pos);
              if (_crossfadeManager.duration > Duration.zero &&
                  duration > _crossfadeManager.duration &&
                  compensatedPos >= duration - _crossfadeManager.duration &&
                  !_crossfadeManager.isCrossfading) {
                final nextIdx = _getNextIndex();
                if (nextIdx != null && nextIdx != _currentIndex) {
                  _startCrossfade(nextIdx);
                }
              }
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player positionStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.androidAudioSessionIdStream.listen(
          (sessionId) {
            if (isPlayerA) {
              _playerASessionId = sessionId;
            } else {
              _playerBSessionId = sessionId;
            }
            if (isTargetActive()) {
              _audioSessionIdRouter.handleSessionId(sessionId);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player androidAudioSessionIdStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );

      _subscriptions.add(
        player.currentIndexStream.listen(
          (index) {
            // Native gapless advance: the concat moved to a new item on its own.
            // Reconcile our queue model, notification, history and position-save
            // off this single source of truth instead of a manual skip.
            if (_gaplessMode &&
                isTargetActive() &&
                index != null &&
                index != _lastGaplessIndex) {
              _onGaplessIndexChanged(index);
            }
          },
          onError: (e, st) {
            ErrorLogger.log('Player currentIndexStream error',
                error: e, stackTrace: st, category: 'AudioHandler');
          },
        ),
      );
    }

    setupPlayerListeners(_playerA, true);
    setupPlayerListeners(_playerB, false);

    // AudioSession configuration
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // Do NOT grab focus here: activating at construction steals audio focus
      // from other apps on cold start (pausing their playback) before the user
      // has played anything. just_audio activates on play()/resume and stop()
      // releases it.

      _subscriptions.add(
        session.interruptionEventStream.listen((event) async {
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.duck));
                // F7: ducking behavior is user-controllable (duck/pause/ignore).
                if (duckingController.shouldIgnore) break;
                if (duckingController.shouldPause) {
                  _interruption.begin(InterruptionKind.duck,
                      playing: _activePlayer.playing);
                  if (_crossfadeManager.isCrossfading) {
                    await _crossfadeManager.cancel(
                        _inactivePlayer, _activePlayer,
                        restoreVolume: _preCrossfadeVolume ?? _volume);
                  }
                  await _activePlayer.pause();
                  break;
                }
                // Stack-safe: a second duck begin while already ducked must not
                // clobber the saved pre-duck level. Duck both engines so a
                // navigation prompt during a crossfade doesn't blast the fade-in.
                if (!_duckActive && _activePlayer.playing) {
                  _duckActive = true;
                  _preDuckVolume = _activePlayer.volume;
                  _preDuckInactiveVolume = _inactivePlayer.volume;
                  final f = duckingController.duckFactor;
                  _volumeController.updateSettings(duckFactor: f);
                  await _activePlayer.setVolume(f * (_preDuckVolume ?? 1.0));
                  if (_crossfadeManager.isCrossfading) {
                    await _inactivePlayer
                        .setVolume(f * (_preDuckInactiveVolume ?? 0.0));
                  }
                }
                break;
              case AudioInterruptionType.pause:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.pause));
                // Stack-safe: keep the original pre-interruption state so an
                // overlapping duck + call doesn't lose the resume decision.
                _interruption.begin(InterruptionKind.pause,
                    playing: _activePlayer.playing);
                if (_interruption.wasPlayingBeforeInterruption) {
                  if (_crossfadeManager.isCrossfading) {
                    await _crossfadeManager.cancel(
                        _inactivePlayer, _activePlayer,
                        restoreVolume: _preCrossfadeVolume ?? _volume);
                  }
                  await _activePlayer.pause();
                }
                break;
              case AudioInterruptionType.unknown:
                unawaited(AudioSessionLog.instance
                    .recordInterruption(AudioInterruptionKind.unknown));
                // Permanent/unknown loss: pause, never auto-resume, free DSP.
                _interruption.begin(InterruptionKind.unknown,
                    playing: _activePlayer.playing);
                _interruption.neverResume();
                if (_crossfadeManager.isCrossfading) {
                  await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                      restoreVolume: _preCrossfadeVolume ?? _volume);
                }
                await _activePlayer.pause();
                break;
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                // A duck that began in pause-mode also holds the interruption
                // bookkeeping; end it here so a later call can snapshot afresh
                // instead of inheriting a stale half-open pause (B-1).
                final wasPlayingBeforeDuck =
                    _interruption.end(InterruptionKind.duck);
                if (_duckActive) {
                  _duckActive = false;
                  // Restore to the CURRENT ReplayGain-compensated target, not
                  // the stale pre-duck snapshot: gain settings or a track
                  // change during the duck would otherwise leave the level
                  // permanently ducked (tolerance check) or jumping.
                  final target = _calculateReplayGainVolume(currentSong);
                  try {
                    await _activePlayer.setVolume(target);
                  } catch (_) {}
                  if (_crossfadeManager.isCrossfading) {
                    try {
                      await _inactivePlayer.setVolume(
                          _calculateReplayGainVolume(
                              _currentIndex >= 0 &&
                                      _currentIndex < _songs.length
                                  ? _songs[_currentIndex]
                                  : null));
                    } catch (_) {}
                  }
                  _volumeController.updateSettings(
                      duckFactor: duckingController.duckFactor);
                  var perSongDb = 0.0;
                  try {
                    final cs = currentSong;
                    if (cs != null) perSongDb = _perSongVolumeDbFor(cs);
                  } catch (_) {}
                  unawaited(_volumeController.setDucked(false, currentSong,
                      perSongOffsetDb: perSongDb));
                  _preDuckVolume = null;
                  _preDuckInactiveVolume = null;
                } else if (shouldResumeAfterInterruption(
                  wasPlayingBeforeInterruption: wasPlayingBeforeDuck,
                  resumeAfterInterruption:
                      _cachedPrefs?.getBool(PrefsKeys.resumeAfterInterruption) ??
                          true,
                  currentlyPlaying: _activePlayer.playing,
                )) {
                  // Pause-mode duck: playback was running when the navigation
                  // prompt began, so resume it now that the prompt ended. It was
                  // previously left paused permanently.
                  unawaited(_activePlayer.play());
                }
                break;
              case AudioInterruptionType.pause:
                final wasPlayingBeforePause =
                    _interruption.end(InterruptionKind.pause);
                if (shouldResumeAfterInterruption(
                  wasPlayingBeforeInterruption: wasPlayingBeforePause,
                  // Cached prefs: this fires on every call-end; a disk read
                  // here delayed resume by ~10-20ms.
                  resumeAfterInterruption:
                      _cachedPrefs?.getBool(PrefsKeys.resumeAfterInterruption) ??
                          true,
                  currentlyPlaying: _activePlayer.playing,
                )) {
                  unawaited(_activePlayer.play());
                }
                _preDuckVolume = null;
                _preDuckInactiveVolume = null;
                _duckActive = false;
                break;
              case AudioInterruptionType.unknown:
                _interruption.reset();
                _preDuckVolume = null;
                _preDuckInactiveVolume = null;
                _duckActive = false;
                break;
            }
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) async {
          // Debounce: wired + BT stacks can emit noisy twice for one unplug.
          final now = DateTime.now();
          if (_lastNoisyTime != null &&
              now.difference(_lastNoisyTime!) <
                  const Duration(milliseconds: 800)) {
            return;
          }
          _lastNoisyTime = now;
          unawaited(AudioSessionLog.instance
              .recordInterruption(AudioInterruptionKind.becomingNoisy));
          if (!_activePlayer.playing && !_crossfadeManager.isCrossfading) {
            return;
          }
          if (_crossfadeManager.isCrossfading) {
            await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                restoreVolume: _preCrossfadeVolume ?? _volume);
          }
          await pause();
        }),
      );

      _subscriptions.add(
        session.devicesStream.listen((devices) {
          _syncBluetoothRouteFromCache();
          _audioSessionIdRouter.handleRouteChanged();
          unawaited(_refreshBluetoothRoute());
          unawaited(_recordSessionRouteChange());
        }),
      );
    } catch (e, st) {
      ErrorLogger.log('Error configuring AudioSession',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    _subscriptions.add(
      AudioEffectsChannel().onRouteChanged.listen((_) {
        _audioSessionIdRouter.handleRouteChanged();
        unawaited(_recordSessionRouteChange());
      }),
    );

    // Initialize audio effects & equalizer preferences
    try {
      // Seed the BT mirror before effects init so the cold-start dither push
      // sees the real route when the output info is already cached.
      _syncBluetoothRouteFromCache();
      await _equalizerManager.init();
      unawaited(_refreshBluetoothRoute());
      unawaited(_equalizerManager.updateLoudnessVolume(_volume));
      await _restoreSkipSilence();
      // F2/F7/F9–F11: restore persisted feature state (best-effort).
      try {
        await trackDelayManager.load();
        await duckingController.load();
        await silenceSkipController.load();
        await dspSnapshotStore.load();
        await bookmarkStore.load();
        final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
        hedgedResolutionEnabled =
            prefs.getBool('hedged_resolution_enabled') ?? true;
        adaptiveQualityManager.enabled =
            prefs.getBool('adaptive_quality_enabled') ?? true;
        final savedQ = prefs.getString('setting_streaming_quality');
        if (savedQ != null && savedQ.isNotEmpty) {
          adaptiveQualityManager.setQuality(savedQ);
        }
      } catch (_) {}
    } finally {
      // Signal effect-state listeners (e.g. PlayerCubit) even if restore
      // partially failed, so they re-sync whatever state is available.
      if (!_effectsReadyCompleter.isCompleted) {
        _effectsReadyCompleter.complete();
      }
    }

    // Register lifecycle observer to persist playback state and manage buffers on app background/resume
    _lifecycleObserver = AudioHandlerLifecycleObserver(
      onBackground: () {
        saveCurrentPositionImmediate();
        _equalizerManager.onAppPaused();
        _memoryManager.onAppBackgrounded(inactivePlayer: _inactivePlayer);
      },
      onResume: () {
        if (_activePlayer.playing) {
          _smartPrefetch();
        }
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    // Restore last played song & queue session from database with 10s timeout guard
    try {
      await restoreLastPlaybackSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          ErrorLogger.log('restoreLastPlaybackSession timed out after 10s',
              category: 'AudioHandler');
        },
      );
    } catch (e, st) {
      ErrorLogger.log('Failed to restore playback session on startup',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  BufferBucket _currentBucket = BufferBucket.standard;

  int get _preloadCountForCurrentBucket {
    switch (_currentBucket) {
      case BufferBucket.minimal:
        return 1;
      case BufferBucket.standard:
        return 2;
      case BufferBucket.generous:
        return 3;
    }
  }

  Future<void> _evaluateBufferBucket(SongsTableData song) async {
    try {
      final isLocal = song.source == SongSource.local || song.isDownloaded == true;
      final isWifi = isLocal ? false : await _ytmService.isWifiConnected();
      _adaptiveBufferEngine.evaluateBucket(isWifi: isWifi, isLocal: isLocal);
    } catch (_) {}
  }

  void _notifyTrackChanged(SongsTableData song) {
    // F1: AB loop is per-track; a new song invalidates the live region,
    // then the persisted loop for the new track (if any) is restored.
    abLoopManager.onSongChanged(song.id);
    unawaited(abLoopManager.restoreForSong(song.id));
    // T10: a new track re-arms its start seek. The advance guard is re-armed
    // by the position listener once it observes a position inside the window,
    // which prevents a stale post-advance tick from skipping the new track.
    _cueStartSeeked = false;
    // D2: seed the BPM-synced crossfade map from manual per-track overrides.
    _seedBpmOverride(song);
    // Correct DSP coefficients for the real header rate (replaces the 48kHz
    // cold-start assumption once known).
    final rate = song.sampleRate;
    if (rate != null && rate > 0) {
      unawaited(AudioEffectsChannel().resyncForTrack(rate.toDouble()));
      unawaited(_equalizerManager.syncNativeLatency(rate.toDouble()));
    }
    // F9: auto-restore per-album DSP snapshot (fire-and-forget).
    if (dspSnapshotStore.enabled) {
      unawaited(recallDspSnapshotFor(song));
    }
    final previousSong = _lastPlayedSong;
    if (previousSong != null && previousSong.id != song.id) {
      _memoryManager.onTrackCompleted(previousSong.id);
      if (previousSong.remoteId != null) {
        // Prefetch registers keys as `remoteId:quality`; evict every variant.
        _memoryManager.evictByPrefix(previousSong.remoteId!);
      }
    }
    _lastPlayedSong = song;
    _onTrackChangedSubject.add(song);
    // Signature-scan local lossless files so MQA material is labeled honestly
    // instead of silently reported as plain FLAC on the next quality rebuild.
    if (song.source == SongSource.local && !song.path.startsWith('content:')) {
      final lowerPath = song.path.toLowerCase();
      if (lowerPath.endsWith('.flac') || lowerPath.endsWith('.wav')) {
        unawaited(MqaDecoderHelper.isMqaFile(song.path).then((isMqa) {
          if (isMqa) MqaDecoderHelper.markMqaPath(song.path);
        }).catchError((_) {}));
      }
    }
    unawaited(_beginAudioSession(song));
    unawaited(_maybeNegotiateOutputFormat(song));
  }

  /// Per-track output-format negotiation. Hi-res-first by default: the pure
  /// [negotiateOutputFormat] decision picks the best format the device supports
  /// and pushes it through the existing target-format channel (bit-perfect
  /// keeps its own exclusive mixer attributes). Smart Audio also forces this on.
  Future<void> _maybeNegotiateOutputFormat(SongsTableData song) async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      var negotiate =
          prefs.getBool(PrefsKeys.outputFormatNegotiationEnabled) ?? true;
      // Smart Audio (Auto) opts into best-quality output negotiation without
      // changing the user's explicit manual setting.
      if (!negotiate && getIt.isRegistered<SmartAudioService>()) {
        negotiate = await getIt<SmartAudioService>().isEnabled();
      }
      if (!negotiate) {
        return;
      }
      if (!getIt.isRegistered<HiResAudioService>()) return;
      final service = getIt<HiResAudioService>();
      final info =
          service.currentOutputInfo ?? await service.getAudioOutputInfo();
      final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
          (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
      final decision = negotiateOutputFormat(
        request: OutputFormatRequest(
          trackSampleRate: song.sampleRate ?? 0,
          trackBitDepth: song.bitDepth ?? 0,
        ),
        deviceSampleRates: info.supportedSampleRates,
        deviceMaxBitDepth: info.bitDepth,
        route: OutputRoute.fromOutputInfo(info),
        bitPerfectActive: bitPerfect,
      );
      if (!decision.applied) return; // Exclusive path owns the mixer format.
      // setTargetOutputFormat only accepts the platform's known ladder; fall
      // back to "auto" for that dimension when the device reports a rate it
      // does not accept, rather than silently requesting nothing.
      const validRates = <int>{
        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 768000
      };
      final rate =
          validRates.contains(decision.sampleRate) ? decision.sampleRate : 0;
      await service.setTargetOutputFormat(
        sampleRate: rate,
        bitDepth: decision.bitDepth,
      );
    } catch (e, st) {
      ErrorLogger.log('Output format negotiation failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  static AudioLoadConfiguration _loadConfigForBucket(BufferBucket bucket) {
    return AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: bucket.minBufferDuration,
        maxBufferDuration: bucket.maxBufferDuration,
        bufferForPlaybackDuration: bucket.bufferForPlaybackDuration,
        bufferForPlaybackAfterRebufferDuration:
            bucket.bufferForPlaybackAfterRebufferDuration,
        prioritizeTimeOverSizeThresholds: false,
      ),
    );
  }

  AudioLoadConfiguration _currentAudioLoadConfiguration =
      _loadConfigForBucket(BufferBucket.standard);
  AudioLoadConfiguration get currentAudioLoadConfiguration =>
      _currentAudioLoadConfiguration;

  void _onBufferBucketChanged(BufferBucket bucket) {
    if (bucket == _currentBucket) return;
    _currentBucket = bucket;
    _currentAudioLoadConfiguration = _loadConfigForBucket(bucket);
    debugPrint(
        '[AudioHandler] Buffer bucket transitioned to $bucket — applying load control');
    unawaited(
        _activePlayer.setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_inactivePlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
    unawaited(_prefetchPlayer
        .setAudioLoadConfiguration(_currentAudioLoadConfiguration));
  }

  Future<void> _onQualityStepDownRequested(String newQuality) async {
    debugPrint(
        '[AudioHandler] Adaptive bitrate switching stepped down streaming quality to $newQuality');
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setString('setting_streaming_quality', newQuality);
    // Quality is part of EVERY downstream cache key: clear all of them so the
    // next resolve actually fetches the lower rendition instead of reusing a
    // stale higher-quality URL (previously only _streamCache was cleared).
    _streamCache.clear();
    _inFlightResolves.clear();
    _prefetching.clear();
    _preloadScheduler.clear();
    try {
      if (getIt.isRegistered<YtmUrlCache>()) {
        final urlCache = getIt<YtmUrlCache>();
        final song = currentSong;
        if (song?.remoteId != null) {
          urlCache.invalidate(song!.remoteId!);
        }
      }
    } catch (_) {}
  }

  /// True for absolute HTTP(S) stream URLs (internet radio / Icecast /
  /// Shoutcast / HLS). These bypass the file/format-aware path entirely.
  static bool _isStreamUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  UriAudioSource _createAudioSource(SongsTableData song, MediaItem tag) {
    if (_isStreamUrl(song.path)) {
      return AudioSource.uri(Uri.parse(song.path), tag: tag);
    }
    if (song.uri?.startsWith('content:') == true ||
        song.path.startsWith('content:')) {
      return AudioSource.uri(Uri.parse(song.uri ?? song.path), tag: tag);
    }
    return AudioSource.file(song.path, tag: tag);
  }

  void _handleStreamResolutionError(SongsTableData song, Object error) {
    final info = YtmErrorClassifier.classify(error);
    final String errorMessage;
    if (error is PlayerException &&
        error.message != null &&
        error.message!.isNotEmpty) {
      errorMessage = error.message!;
    } else {
      errorMessage = info.message;
    }
    ErrorLogger.log(
      'Gapless stream resolution error on "${song.title}": $errorMessage ($error)',
      category: 'AudioHandler',
    );
    _errorSubject.add(errorMessage);

    // Invalidate poToken only on a verdict that a fresh attestation can fix.
    // `contains('403')` matched the digits anywhere in the message — including
    // inside a video id, an itag or a byte count — and bare `bot` matched
    // "bottleneck", so ordinary failures kept throwing away a working token and
    // paying for a new BotGuard round on the next track.
    final signal = info.signal;
    if (signal == YtmBlockSignal.botChallenge ||
        signal == YtmBlockSignal.poTokenInvalid) {
      _ytmService.invalidatePoToken().catchError((e, st) {
        ErrorLogger.log('poToken invalidation failed',
            error: e, stackTrace: st, category: 'AudioHandler');
      });
    }
    // CRITICAL GUARD: If the error occurred on a pre-fetched background track or queued item
    // that is not currently playing, NEVER pause playback, skip, or increment failures!
    final activeSong = currentSong;
    final isCurrentTrack = activeSong != null &&
        (activeSong.id == song.id ||
            (song.remoteId != null &&
                song.remoteId!.isNotEmpty &&
                activeSong.remoteId == song.remoteId));

    if (!isCurrentTrack) {
      debugPrint(
          '[AudioHandler] Background pre-fetch failed for "${song.title}", keeping active playback alive.');
      return;
    }

    if (!_activePlayer.playing) {
      debugPrint('[AudioHandler] Resolution failed while paused — stopping loop.');
      return;
    }
    if (info.recoveryAction == YtmRecoveryAction.skipToNextTrack) {
      // Already 2 rapid gaps means 3rd song in your loop → pause instead of skip
      if (_consecutiveFailures >= 2 || _rapidGaplessChangeCount >= 1) {
        _consecutiveFailures = 0;
        _rapidGaplessChangeCount = 0;
        _activePlayer.pause().ignore();
        _broadcastState(_activePlayer.playbackEvent);
        return;
      }
      debugPrint('[AudioHandler] Track blocked/unavailable. Skipping to next.');
      unawaited(skipToNext());
      return;
    }

    final isFatal = error is YtmException
        ? error.isFatal
        : (info.recoveryAction != YtmRecoveryAction.retryWithBackoff);

    if (isFatal) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _activePlayer.pause().ignore();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
        _consecutiveFailures = 0;
        _rapidGaplessChangeCount = 0;
        _activePlayer.pause().ignore();
        _broadcastState(_activePlayer.playbackEvent);
      } else {
        unawaited(skipToNext());
      }
    }
  }

  /// Builds a gapless-queue child for [song] with no network I/O, so an entire
  /// queue can be assembled up front. Local tracks resolve to a file/content
  /// source; a YouTube row (not yet downloaded) becomes a [YtmResolvingSource]
  /// that resolves its URL and caches its bytes lazily on first playback. A
  /// downloaded YouTube row with a real file on disk plays straight off disk.
  final Map<String, bool> _pathExistsCache = {};
  static const _maxPathCacheSize = 2000;

  AudioSource _buildGaplessChild(SongsTableData song) {
    final tag = _songToMediaItem(song);
    // HTTP streams are not files: skip the disk/format/trim paths and hand
    // the URL to just_audio directly (HLS auto-detected).
    if (_isStreamUrl(song.path)) {
      return _createAudioSource(song, tag);
    }
    final isRemoteYtm = song.source == SongSource.youtube &&
        (song.path.startsWith('ytmusic://') || song.path.isEmpty) &&
        song.isDownloaded != true;
    final isLocalFile = !isRemoteYtm &&
        (!song.path.startsWith('ytmusic://') && song.path.isNotEmpty) &&
        (song.path.startsWith('content:') ||
            song.isDownloaded == true ||
            (_pathExistsCache[song.path] ??= File(song.path).existsSync()));
    // FIX-#8: Evict oldest 25% when the cache exceeds the bound to prevent
    // an unbounded memory leak over long listening sessions.
    if (_pathExistsCache.length > _maxPathCacheSize) {
      final keys = _pathExistsCache.keys.toList();
      for (var i = 0; i < keys.length ~/ 4; i++) {
        _pathExistsCache.remove(keys[i]);
      }
    }
    final isRemote = song.source == SongSource.youtube && !isLocalFile;
    if (isRemote) {
      late final YtmResolvingSource source;
      source = YtmResolvingSource.withRefresh(
        videoId: song.remoteId ?? '',
        quality: _currentStreamingQuality(),
        resolve: ({bool forceRefresh = false}) async {
          final resolved =
              await _resolveStreamUrl(song, forceRefresh: forceRefresh);
          source.userAgent = resolved.userAgent;
          source.cookies = resolved.cookies;
          source.quality = resolved.quality;
          return resolved.url;
        },
        onError: (error) => _handleStreamResolutionError(song, error),
        tag: tag,
      );
      return source;
    }
    final base = _createAudioSource(song, tag);
    // Apply codec encoder-delay/padding trims so Opus/MP3/AAC joins are
    // truly gapless instead of carrying ~6-48ms of silence.
    try {
      final trim = GaplessTrimHandler.trimFor(
        path: song.path,
        codec: song.codec,
      );
      if (!trim.isEmpty) {
        final trackLen = Duration(milliseconds: song.durationMs);
        final clamped = trim.clampedTo(trackLen);
        final start = GaplessTrimHandler.startOffset(clamped);
        final end = trackLen > Duration.zero
            ? GaplessTrimHandler.effectiveEnd(trackLen, clamped)
            : null;
        if (start > Duration.zero || (end != null && end < trackLen)) {
          return ClippingAudioSource(
            start: start == Duration.zero ? null : start,
            end: (end == null || end >= trackLen) ? null : end,
            child: base,
            tag: tag,
          );
        }
      }
    } catch (_) {}
    return base;
  }

  List<AudioSource> _buildAudioSources(List<SongsTableData> songs) {
    return songs.map(_buildGaplessChild).toList();
  }

  /// A local song plays straight off disk; a YouTube row needs a freshly
  /// resolved URL, because the last one expires within hours and is pinned to
  /// this device's IP. Used by the crossfade engine, which loads one track at a
  /// time. (The gapless engine instead uses [_buildGaplessChild], whose
  /// [YtmResolvingSource] both resolves lazily and caches fetched bytes so a
  /// backward seek does not re-hit an already-expired URL.)
  Future<AudioSource> _resolveAudioSource(
      SongsTableData song, MediaItem tag) async {
    // A pseudo-song whose path is a stream URL: no local match, no MQA/DSD
    // decode, no cache — just build a URI source.
    if (_isStreamUrl(song.path)) {
      return _createAudioSource(song, tag);
    }
    if (song.source != SongSource.youtube) {
      final cleanPath = song.path.split('?').first;
      final dot = cleanPath.lastIndexOf('.');
      final ext = dot >= 0 ? cleanPath.substring(dot + 1).toLowerCase() : '';
      if (ext == 'dsf' || ext == 'dff') {
        // T4: honor the user's DSD output mode, but only after the native probe
        // confirms a DoP-capable USB DAC. Default is PCM; DoP is never implied
        // by the file format or by an absent/failed probe.
        final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
        final wantDop =
            (prefs.getString(PrefsKeys.dsdOutputMode) ?? 'pcm') == 'dop';
        DsdDacCapabilities? caps;
        if (wantDop) {
          caps = await DsdDecoderHelper.probeDopCapabilities();
        }
        final forceDop = wantDop && (caps?.canUseDop ?? false);
        return DsdDecoderHelper.decodeDsdFile(
          song,
          tag,
          forceDop: forceDop,
          dopCapabilities: caps,
        );
      }
      // Route lossless containers through the format-aware decoder so MQA files
      // are detected (and unfolded when the helper is enabled) instead of
      // silently playing as plain FLAC. content:// URIs are excluded: the
      // decoder builds a file URI and cannot read through a content resolver.
      if ((ext == 'flac' || ext == 'wav') &&
          !song.path.startsWith('content:') &&
          song.uri?.startsWith('content:') != true) {
        return _formatDecoder.decodeForFormat(song, tag);
      }
      return _createAudioSource(song, tag);
    }

    // Direct fast path for downloaded songs with physical file on disk or content URI
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || await File(song.path).exists())) {
      return _createAudioSource(song, tag);
    }

    try {
      final localMatch = await _repository.findMatchingLocalSong(
        remoteId: song.remoteId,
        title: song.title,
        artist: song.artist,
      );
      final localSong = localMatch.fold((_) => null, (s) => s);
      if (localSong != null &&
          (localSong.path.startsWith('content:') ||
              (localSong.uri != null &&
                  localSong.uri!.startsWith('content:')) ||
              await File(localSong.path).exists())) {
        return _createAudioSource(localSong, tag);
      }
    } catch (_) {
      // If local check fails, fall through to stream resolution
    }

    // Fast-path: check if YouTube track is already cached in local disk stream cache
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      final cachedFile = await YtmCacheManager()
          .getCachedAudioFile(song.remoteId!, quality: _currentStreamingQuality());
      if (cachedFile != null) {
        return AudioSource.file(cachedFile.path, tag: tag);
      }
    }

    // Use lazy YtmResolvingSource: just_audio calls request() when it needs
    // bytes, which triggers the resolve chain. This lets the player accept
    // the source instantly (no blocking await on stream resolution) and start
    // buffering as soon as bytes arrive. If the background warm populated the
    // URL cache, the lazy resolve completes near-instantly.
    late final YtmResolvingSource source;
    source = YtmResolvingSource.withRefresh(
      videoId: song.remoteId ?? '',
      quality: _currentStreamingQuality(),
      resolve: ({bool forceRefresh = false}) async {
        final resolved =
            await _resolveStreamUrl(song, forceRefresh: forceRefresh);
        source.userAgent = resolved.userAgent;
        source.cookies = resolved.cookies;
        source.quality = resolved.quality;
        return resolved.url;
      },
      onError: (error) => _handleStreamResolutionError(song, error),
      tag: tag,
    );
    return source;
  }

  /// Returns a currently-valid stream URL for a YouTube row, reusing a memoized
  /// one until it nears expiry. Throws [YtmException] when nothing usable comes
  /// back, so the caller can tell "network down" from "skip this track".
  ///
  /// [quality] is reported back because it is part of every downstream cache key
  /// ([YtmUrlCache], the disk cache slot); the caller cannot assume `high`.
  Future<({String url, String? userAgent, String? cookies, String quality})>
      _resolveStreamUrl(SongsTableData song,
          {bool forceRefresh = false}) async {
    try {
      _latencyTracker?.markStage(PlaybackStage.resolutionRequested);
    } catch (_) {}
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }
    // Guard against placeholder local IDs (e.g. n_1f2cbFnkQ) that would waste
    // BotGuard + Innertube retries and then loop as VideoGone. Skip quietly.
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) || videoId.startsWith('n_')) {
      throw const YtmException('YTM_UNAVAILABLE', 'Invalid video id');
    }

    // Hot path: reuse the cached prefs (loaded once in _init) instead of an
    // async disk read per resolve — saves ~5-20ms on every tap/prefetch.
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      throw const YtmException(
          'OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY',
            'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final quality = prefs.getString('setting_streaming_quality') ?? 'high';
    final cacheKey = '$videoId:${quality.toLowerCase()}';

    if (!forceRefresh) {
      final cached = _streamCache[cacheKey];
      if (cached != null && cached.expires.isAfter(DateTime.now())) {
        try {
          _latencyTracker?.markStage(PlaybackStage.urlObtained);
        } catch (_) {}
        return (
          url: cached.url,
          userAgent: cached.userAgent,
          cookies: cached.cookies,
          quality: quality
        );
      }
      final inFlight = _inFlightResolves[cacheKey];
      if (inFlight != null) {
        return await inFlight;
      }
    }

    Future<YtmStream> doResolve() => _ytmService.resolveStream(videoId,
        quality: quality, forceRefresh: forceRefresh);
    final future = () async {
      try {
        _latencyTracker?.markStage(PlaybackStage.pluginEntered);
        _latencyTracker?.markStage(PlaybackStage.clientRequestSent);
      } catch (_) {}
      // F3: hedged resolution — race two client attempts, take first success.
      // Disabled while an egress block is active: both duplicates target the
      // same blocked IP, so hedging only doubles the native chain load (and the
      // CPU/GC churn) for a verdict that is already known.
      final coolingDown = _ytmService.isBotCoolingDown;
      final YtmStream stream = (hedgedResolutionEnabled && !coolingDown)
          ? await HedgedStreamResolver.raceDuplicate<YtmStream>(doResolve,
              hedgeDelay: const Duration(milliseconds: 300),
              timeout: const Duration(seconds: 25))
          : await doResolve();
      if (stream.url.trim().isEmpty) {
        throw const YtmException(
            'YTM_UNAVAILABLE', 'Resolved stream URL is empty');
      }
      final expireParam = Uri.tryParse(stream.url)?.queryParameters['expire'];
      DateTime expireAt;
      if (expireParam != null) {
        final rawExpire = int.tryParse(expireParam) ?? 0;
        if (rawExpire > 9999999999) {
          expireAt = DateTime.fromMillisecondsSinceEpoch(rawExpire);
        } else if (rawExpire > 0) {
          expireAt = DateTime.fromMillisecondsSinceEpoch(rawExpire * 1000);
        } else {
          expireAt = DateTime.now().add(const Duration(hours: 5));
        }
      } else {
        expireAt = DateTime.now().add(const Duration(hours: 5));
      }
      final safeExpiry = expireAt.subtract(const Duration(minutes: 5));
      if (safeExpiry.isAfter(DateTime.now())) {
        _addToStreamCache(cacheKey, (
          url: stream.url,
          expires: safeExpiry,
          userAgent: stream.userAgent,
          cookies: stream.cookies
        ));
      }
      AudioMemoryManager.trimStreamCache(_streamCache);
      try {
        _latencyTracker?.markStage(PlaybackStage.urlObtained);
      } catch (_) {}
      return (
        url: stream.url,
        userAgent: stream.userAgent,
        cookies: stream.cookies,
        quality: quality
      );
    }();

    _inFlightResolves[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightResolves.remove(cacheKey);
    }
  }

  /// Non-blocking background cache warm for [song]. Populates the stream URL
  /// cache so a subsequent lazy resolve completes near-instantly.
  Future<void> _warmStreamCache(SongsTableData song) async {
    if (_ytmService.isBotCoolingDown) return;
    try {
      await _resolveStreamUrl(song).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  static const int _maxStreamCacheEntries = 64;

  void _addToStreamCache(
      String key,
      ({
        String url,
        DateTime expires,
        String? userAgent,
        String? cookies
      }) entry) {
    if (_streamCache.length >= _maxStreamCacheEntries) {
      _streamCache.remove(_streamCache.keys.first);
    }
    _streamCache[key] = entry;
  }

  int _prefetchGeneration = 0;

  /// Quick soft-landing before a hard stop/swap: stopping mid-waveform without
  /// a fade cuts the signal at a non-zero crossing, which the ear hears as a
  /// click/pop on every manual track change. 70ms is inaudible as a delay.
  Future<void> _fadeOutForSwitch(AudioPlayer player) async {
    try {
      if (!player.playing) return;
      final from = player.volume;
      if (from <= 0.01) return;
      await _crossfadeManager
          .fadeVolume(player, from, 0.0, const Duration(milliseconds: 70),
              _crossfadeManager.nextFadeId())
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {}
  }

  /// Matching fade-in after a switch: starting at 0 and ramping to the
  /// ReplayGain target avoids the cold-start click. Skipped while ducked
  /// (navigation/call) so the ramp never fights the duck level.
  // ignore: unused_element
  void _fadeInAfterSwitch(AudioPlayer player, double targetVolume) {
    if (_duckActive) return;
    unawaited(_crossfadeManager.fadeVolume(
        player,
        0.0,
        targetVolume.clamp(0.0, 1.0),
        const Duration(milliseconds: 90),
        _crossfadeManager.nextFadeId()));
  }

  /// Safety net for the cold-start fade-in: the 90ms ramp is unawaited and can
  /// be orphaned by a racing fade-id bump, a cancelled crossfade, or a play()
  /// interrupted mid-load, leaving the player audibly running at volume 0
  /// until the user pauses and resumes. A short convergence check restores the
  /// ReplayGain target when the player is ready and playing but still muted.
  void _scheduleFadeInConvergenceGuard(AudioPlayer player, int generation) {
    if (_duckActive) return;
    var attempts = 0;
    // FIX-#12: Cancel any previous guard and store the new timer so it can
    // be disposed on onTaskRemoved / hot-restart.
    _fadeInGuardTimer?.cancel();
    _fadeInGuardTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      attempts++;
      try {
        if (attempts > 8 ||
            generation != _playGeneration ||
            !identical(player, _activePlayer) ||
            _duckActive ||
            _crossfadeManager.isCrossfading ||
            !player.playing) {
          timer.cancel();
          return;
        }
        if (player.volume > 0.01) {
          timer.cancel();
          return;
        }
        // Player is playing but volume is still muted
        final target = _calculateReplayGainVolume(currentSong).clamp(0.0, 1.0);
        if (target > 0.05) {
          ErrorLogger.log(
              'Cold-start fade-in did not converge (attempt $attempts); restoring target volume',
              category: 'AudioHandler');
          await player.setVolume(target);
          timer.cancel();
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  void cancelPrefetches() {
    _prefetchGeneration++;
    _prefetching.clear();
  }

  /// Clears all IP-bound stream URL caches and DNS-era state.
  ///
  /// Call on VPN/network-path change: googlevideo URLs carry an IP-bound
  /// `expire`/`ip` signature and return 403 when the egress IP changes.
  void clearNetworkCaches() {
    _streamCache.clear();
    _inFlightResolves.clear();
    _prefetching.clear();
    cancelPrefetches();
  }

  // --- SkipSilence + Normalization (InnerTune parity) ---
  bool get skipSilenceEnabled => _activePlayer.skipSilenceEnabled;

  Future<void> setSkipSilenceEnabled(bool enabled) async {
    try {
      silenceSkipController.setEnabled(enabled);
      await _playerA.setSkipSilenceEnabled(enabled);
      await _playerB.setSkipSilenceEnabled(enabled);
      await silenceSkipController.persist();
    } catch (e, st) {
      ErrorLogger.log('Failed to set skipSilence', error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Pushes the opt-in 24/32-bit float DSP-path preference to every player
  /// (active, inactive and prefetch). Off by default; with `false` the native
  /// sink is built exactly as before. Never throws.
  Future<void> setFloatOutputEnabled(bool enabled) async {
    await pushFloatOutputToPlayers(
      enabled,
      [_playerA, _playerB, _prefetchPlayer],
    );
  }

  /// Resampler quality (0=Fast/linear .. 3=Ultra/64-tap). Best-effort push.
  Future<void> setSincResamplerQuality(int quality) async {
    await AudioEffectsChannel().setSincResamplerQuality(quality);
  }

  /// BPM-synced crossfade toggle on the shared crossfade manager.
  Future<void> setBpmSyncCrossfadeEnabled(bool enabled) async {
    _crossfadeManager.bpmSyncEnabled = enabled;
  }

  /// Seeds the crossfade BPM map for [song] from manual overrides.
  /// Keeps the map bounded: entries for tracks outside the queue are dropped.
  void _seedBpmOverride(SongsTableData song) {
    try {
      final trackId = song.id.toString();
      final bpm = bpmOverrideStore.getBpmForTrack(trackKeyFor(song));
      final mgr = _crossfadeManager;
      if (bpm != null) {
        mgr.bpmOverrides[trackId] = bpm;
      } else {
        mgr.bpmOverrides.remove(trackId);
      }
      if (mgr.bpmOverrides.length > 500) {
        final keep = _songs.map((s) => s.id.toString()).toSet();
        mgr.bpmOverrides.removeWhere((k, _) => !keep.contains(k));
      }
    } catch (_) {}
  }

  /// Track key shared with the per-song stores (id-based).
  static String trackKeyFor(SongsTableData song) => song.id.toString();

  /// Sets (or clears with null) the manual BPM override for [song].
  /// Returns false when out of the 40–240 range.
  Future<bool> setTrackBpm(SongsTableData song, double? bpm) async {
    final ok =
        await bpmOverrideStore.setBpmForTrack(trackKeyFor(song), bpm);
    if (ok) _seedBpmOverride(song);
    return ok;
  }

  /// Pushes the opt-in AAudio Direct output preference to every player
  /// (active, inactive and prefetch). Off by default; with `false` the sink
  /// stays the historical DefaultAudioSink path. Never throws.
  Future<void> setAaudioOutputEnabled(bool enabled,
      {bool preferExclusive = true, int targetBufferMs = 150}) async {
    await pushAaudioOutputToPlayers(
      enabled,
      preferExclusive: preferExclusive,
      targetBufferMs: targetBufferMs,
      players: [_playerA, _playerB, _prefetchPlayer],
    );
  }

  Future<void> _restoreSkipSilence() async {
    try {
      await silenceSkipController.load();
      final enabled = silenceSkipController.enabled;
      if (enabled) {
        await _playerA.setSkipSilenceEnabled(true);
        await _playerB.setSkipSilenceEnabled(true);
      }
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      final normEnabled = prefs.getBool('audio_normalization_enabled') ?? false;
      final savedBoost = prefs.getDouble(PrefsKeys.eqVolumeBoost);
      if (normEnabled && (savedBoost == null || savedBoost == 0.0)) {
        // Apply mild loudness normalization for streams without ReplayGain tags only if user hasn't set custom boost
        await _equalizerManager.setVolumeBoost(0.35);
      }
    } catch (_) {}
  }

  Future<void> setAudioNormalizationEnabled(bool enabled) async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setBool('audio_normalization_enabled', enabled);
      if (enabled) {
        if (_equalizerManager.volumeBoost == 0.0) {
          await _equalizerManager.setVolumeBoost(0.35);
        }
      } else {
        if (_equalizerManager.volumeBoost == 0.35) {
          await _equalizerManager.setVolumeBoost(0.0);
        }
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to set normalization', error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  bool get isAudioNormalizationEnabled {
    try {
      return _cachedPrefs?.getBool('audio_normalization_enabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Warms [_streamCache] for an upcoming YouTube track so track switching is instant.
  void _prefetchStream(SongsTableData song) {
    final videoId = song.remoteId;
    if (song.source != SongSource.youtube ||
        videoId == null ||
        videoId.isEmpty) {
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) || videoId.startsWith('n_')) return;
    // Skip prefetch if downloaded/local file exists
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || song.isDownloaded == true)) {
      return;
    }
    // Avoid launching background prefetch storms if playback failures are occurring
    if (_consecutiveFailures >= 3) {
      return;
    }
    // While the IP is cooling down every resolve fails instantly with the same
    // BOT_CHALLENGE, so prefetching only burns log lines and thread-pool slots.
    // The foreground resolve retries once the window lapses.
    if (_ytmService.isBotCoolingDown) {
      return;
    }
    // Deduplicate against active stream pre-resolver (quality-aware: a
    // medium prefetch must not block a high foreground resolve).
    final prefetchKey = '$videoId:${_currentStreamingQuality().toLowerCase()}';
    if (_streamPreResolver.inFlightVideoId == videoId) {
      return;
    }
    final isBatteryConstrained =
        _batteryAwarePlayback.currentLevel != BatteryOptimizationLevel.normal;
    if (!_memoryManager.canPreload(isBatteryConstrained: isBatteryConstrained)) {
      return;
    }
    if (!_prefetching.add(prefetchKey)) {
      return;
    }
    _memoryManager.registerPreload(
      prefetchKey,
      AudioMemoryManager.calculateHeadSize(bitrateKbps: song.bitrateKbps ?? 256),
    );
    final currentGen = _prefetchGeneration;
    _resolveStreamUrl(song).whenComplete(() {
      if (_prefetchGeneration == currentGen) {
        _prefetching.remove(prefetchKey);
      }
    }).ignore();
  }

  bool _isConsecutiveAlbumPlayback() {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) {
      return false;
    }
    final currentAlbum = _songs[_currentIndex].album;
    if (currentAlbum == 'Unknown Album' || currentAlbum.isEmpty) return false;
    if (_currentIndex > 0 && _songs[_currentIndex - 1].album == currentAlbum) {
      return true;
    }
    if (_currentIndex + 1 < _songs.length &&
        _songs[_currentIndex + 1].album == currentAlbum) {
      return true;
    }
    return false;
  }

  void _smartPrefetch() {
    if (_songs.isEmpty || _currentIndex < 0 || _consecutiveFailures >= 3) return;
    if (_batteryAwarePlayback.currentLevel ==
        BatteryOptimizationLevel.critical) {
      return;
    }
    // Throttle: position ticks fire continuously in the last 30s of a track;
    // without this the same videoId is re-scheduled on every tick.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key =
        '${_currentIndex}_${_songs[_currentIndex].remoteId ?? _songs[_currentIndex].id}';
    if (key == _lastSmartPrefetchKey && nowMs - _lastSmartPrefetchMs < 10000) {
      return;
    }
    _lastSmartPrefetchMs = nowMs;
    _lastSmartPrefetchKey = key;
    _preloadScheduler.schedulePreloads(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
      position: _activePlayer.position,
      duration: _activePlayer.duration ?? Duration.zero,
      preloadCount: _preloadCountForCurrentBucket,
    );
  }

  void _prefetchNextTracks() {
    _smartPrefetch();
  }

  Future<void> restoreLastPlaybackSession() async {
    try {
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }
      final restoreGen = _playGeneration;

      // Restore shuffle and repeat preferences from storage (Issue #12)
      final prefs = await SharedPreferences.getInstance();
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final shufflePref = prefs.getBool(PrefsKeys.playbackShuffle) ?? false;
      final repeatModePref =
          prefs.getString(PrefsKeys.playbackRepeatMode) ?? 'off';
      final repeatMode = switch (repeatModePref) {
        'all' => AudioServiceRepeatMode.all,
        'one' => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
      await setShuffleMode(shufflePref
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      await setRepeatMode(repeatMode);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final queueRes = await _repository.getSavedQueue();
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final queueItems =
          queueRes.fold((l) => <QueueItemsTableData>[], (r) => r);
      if (queueItems.isEmpty) return;

      // Batch query songs instead of N+1 synchronous disk checks (Issue #18)
      final songIds = queueItems.map((q) => q.songId).toList();
      final songsRes = await _repository.getSongsByIds(songIds);
      if (_userPlaybackInitiated ||
          _songs.isNotEmpty ||
          _playGeneration != restoreGen ||
          _activePlayer.playing ||
          _activePlayer.audioSources.isNotEmpty) {
        return;
      }

      final songsMap = {
        for (final s in songsRes.fold((l) => <SongsTableData>[], (r) => r))
          s.id: s
      };

      final List<SongsTableData> songs = [];
      int targetIndex = 0;
      int savedPositionMs = 0;

      for (int i = 0; i < queueItems.length; i++) {
        final item = queueItems[i];
        final song = songsMap[item.songId];
        if (song != null) {
          songs.add(song);
          if (item.isCurrent) {
            targetIndex = songs.length - 1;
            savedPositionMs = item.positionMs;
          }
        }
      }

      if (songs.isNotEmpty) {
        if (_userPlaybackInitiated ||
            _songs.isNotEmpty ||
            _playGeneration != restoreGen ||
            _activePlayer.playing ||
            _activePlayer.audioSources.isNotEmpty) {
          return;
        }
        _songs = songs;
        _currentIndex = targetIndex.clamp(0, songs.length - 1);
        final currentSong = _songs[_currentIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(currentSong);
        if (_userPlaybackInitiated || _playGeneration != restoreGen) return;
        final item = _songToMediaItem(currentSong, artUri);
        mediaItem.add(item);
        queue.add(_songs.map(_songToMediaItem).toList());

        final pos = Duration(milliseconds: savedPositionMs);
        if (_gaplessMode) {
          // Build the concat but do not preload, so a restored YouTube track
          // resolves its (expiring) URL lazily on the first play() rather than
          // throwing here at cold start when offline and losing the session.
          await _loadGaplessQueue(initialPosition: pos, preload: false);
        } else {
          if (currentSong.source == SongSource.youtube) {
            // Resolving a stream URL here runs unawaited at cold start and, if
            // offline, would throw into the catch below and lose the whole
            // restored session. Stay idle; play() resolves it on first tap.
            _pendingLazyPosition = pos;
          } else {
            await _activePlayer.setAudioSource(
              _createAudioSource(currentSong, item),
              initialPosition: pos,
              preload: false,
            );
          }
        }
        if (_userPlaybackInitiated || _playGeneration != restoreGen) return;
        _broadcastState(_activePlayer.playbackEvent);
        _positionSubject.add(pos);
      }
    } catch (e, st) {
      ErrorLogger.log('Error restoring last playback session',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Readiness gate for crossfade: the incoming player must be decodable
  /// (ready/buffering) with enough buffered audio to cover the fade start.
  bool _canStartCrossfade(AudioPlayer incoming) {
    final ps = incoming.processingState;
    if (ps != ProcessingState.ready && ps != ProcessingState.buffering) {
      return false;
    }
    try {
      return incoming.bufferedPosition > const Duration(seconds: 2);
    } catch (_) {
      return true;
    }
  }

  Future<void> _startCrossfade(int nextIndex) async {
    if (_crossfadeManager.isCrossfading) return;
    if (!await _tripleBufferPipeline.claimInactive(PlayerClaim.crossfade)) return;
    try {
      return await _crossfadeManager.protect(() async {
        if (_crossfadeManager.isCrossfading) return;
        _crossfadeManager.beginCrossfade(nextIndex);
      final currentFadeId = _crossfadeManager.nextFadeId();

      final initialActiveVolume = _calculateReplayGainVolume(currentSong);
      _preCrossfadeVolume = initialActiveVolume;
      try {
        final nextSong = _songs[nextIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(nextSong);
        final item = _songToMediaItem(nextSong, artUri);

        final source = await _resolveAudioSource(nextSong, item);
        // Resolving a YouTube URL can take seconds. If a skip/stop cancelled this
        // fade meanwhile, loading the source now would push phantom audio into a
        // player that cancel() already stopped — bail on the stale fade.
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Synchronize speed on inactive player before loading & playback
        await _inactivePlayer.setSpeed(_activePlayer.speed);
        await _inactivePlayer.setPitch(_pitch);
        await _inactivePlayer.setAudioSource(source, preload: true);

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        await _inactivePlayer.setVolume(0.0);
        // Wait for the inactive player to be ACTUALLY playing at volume 0
        // before starting the gain ramp. play() resolves when the command is
        // sent, not when ExoPlayer has decoded its first frame — on slow
        // decoders or buffered streams the ramp can advance to ~0.3 before
        // any audio is emitted, causing a pop/click burst at the crossfade
        // start. We poll processingState until it leaves 'loading' (≤1000ms)
        // and then give the mixer one extra period to settle at zero gain.
        try {
          await _inactivePlayer.play().timeout(const Duration(milliseconds: 1000));
        } catch (_) {
          // FIX-#6: The fallback play() must also have a timeout — without one,
          // a hung native decoder deadlocks the crossfade engine indefinitely.
          try {
            await _inactivePlayer.play().timeout(const Duration(milliseconds: 3000));
          } on TimeoutException {
            ErrorLogger.log(
                'Inactive player hung on play(); aborting crossfade',
                category: 'AudioHandler');
            rethrow; // let crossfade error handler clean up
          } catch (_) {}
        }

        // FIX-B02: Abort if crossfade ID changed during play() await
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Poll until the decoder has produced its first audio frame
        // (processingState == ready/buffering with playing==true), or until
        // 1000ms have elapsed as a safety cap.
        const maxSettleMs = 1000;
        var settleWaited = 0;
        while (settleWaited < maxSettleMs) {
          final ps = _inactivePlayer.processingState;
          if (ps == ProcessingState.ready || ps == ProcessingState.buffering) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 20));
          settleWaited += 20;
        }

        // FIX-B02: Abort if crossfade ID changed during settle loop
        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        final ps = _inactivePlayer.processingState;
        if (ps != ProcessingState.ready && ps != ProcessingState.buffering) {
          ErrorLogger.log(
              'Inactive player not ready for crossfade (state: $ps); aborting crossfade',
              category: 'AudioHandler');
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        // Readiness gate: require enough buffered audio to cover the fade
        // start before opening the gain ramp; otherwise delay briefly or
        // fall back to a hard transition to avoid a truncated fade.
        if (!_canStartCrossfade(_inactivePlayer)) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (_crossfadeManager.currentFadeId != currentFadeId) {
            try {
              await _inactivePlayer.stop();
            } catch (_) {}
            try {
              await _activePlayer.setVolume(initialActiveVolume);
            } catch (_) {}
            return;
          }
          if (!_canStartCrossfade(_inactivePlayer)) {
            ErrorLogger.log(
                'Inactive player under-buffered for crossfade; falling back to direct transition',
                category: 'AudioHandler');
            try {
              await _inactivePlayer.stop();
            } catch (_) {}
            try {
              await _activePlayer.setVolume(initialActiveVolume);
            } catch (_) {}
            await playSongAt(nextIndex);
            return;
          }
        }

        // One extra mixer period so the audio sink has settled at zero before
        // the gain ramp opens — eliminates the brief full-volume transient.
        await Future.delayed(const Duration(milliseconds: 20));

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        final active = _activePlayer;
        final inactive = _inactivePlayer;

        // BPM-synced crossfade: when enabled and the incoming track has a
        // known BPM, align the fade to the nearest 2/4/8/16/32 beats.
        final fadeDuration = _crossfadeManager.effectiveFadeDuration(
          trackId: nextSong.id.toString(),
        );

        final targetNextVolume = _calculateReplayGainVolume(nextSong);
        final isRepeatOne = _activePlayer.loopMode == LoopMode.one;

        // Pre-buffer track N+2 into _prefetchPlayer during crossfade window
        // (gated on depth>=2 so minimal-bucket / critical-battery skips it).
        final nextNextIndex = _getNextIndex(offset: 2, peek: true);
        if (_preloadCountForCurrentBucket >= 2 &&
            nextNextIndex != null &&
            nextNextIndex >= 0 &&
            nextNextIndex < _songs.length) {
          unawaited(_tripleBufferPipeline.prefetchAhead(_songs[nextNextIndex]));
        }

        await _crossfadeManager.crossfadeVolumes(
          active: active,
          inactive: inactive,
          fromActiveVol: initialActiveVolume,
          toInactiveVol: targetNextVolume,
          duration: fadeDuration,
          fadeId: currentFadeId,
          isRepeatOne: isRepeatOne,
        );

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await active.setVolume(initialActiveVolume);
          } catch (_) {}
          return;
        }

        _isPlayerAActive = !_isPlayerAActive;
        _generationCounter++;
        _currentIndex = nextIndex;

        final currentSessionId =
            _isPlayerAActive ? _playerASessionId : _playerBSessionId;
        _audioSessionIdRouter.handleSessionId(
            currentSessionId ?? _activePlayer.androidAudioSessionId);

        mediaItem.add(_songToMediaItem(nextSong, artUri));
        _notifyTrackChanged(nextSong);
        _planNextStreamResolution();
        _repository.recordPlayHistory(nextSong.id);
        _broadcastState(_activePlayer.playbackEvent);

        // Clear the native gain curve BEFORE stop() while the player is still
        // active on the platform channel, then allow the pipeline to drain before stop.
        try {
          await active.dspClearGainCurve();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 80));
        try {
          await active.stop();
        } catch (_) {}
        await active.setVolume(_volume);
        // FIX-#5: During crossfade the outgoing player is manually stopped, so
        // ProcessingState.completed never fires.  Notify the sleep timer here
        // so track-count-based timers decrement correctly.
        _notifySleepTrackCompleted();
      } catch (e, st) {
        ErrorLogger.log('Error during crossfade playback',
            error: e, stackTrace: st, category: 'AudioHandler');
        try {
          await _inactivePlayer.stop();
        } catch (_) {}
        if (_crossfadeManager.currentFadeId == currentFadeId) {
          await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
              restoreVolume: _volume);
          try {
            await playSongAt(nextIndex);
          } catch (fallbackError, fallbackSt) {
            ErrorLogger.log('Crossfade fallback also failed',
                error: fallbackError,
                stackTrace: fallbackSt,
                category: 'AudioHandler');
            _errorSubject.add('Playback failed. Please try again.');
            await _failCurrentPlayback(fatal: true);
          }
        }
      } finally {
        if (_crossfadeManager.currentFadeId == currentFadeId) {
          _crossfadeManager.finishCrossfade();
        } else {
          // Stale fade (a skip/stop superseded it): drop any native gain
          // curves armed meanwhile so neither player keeps a fade multiplier
          // applied after the volumes are restored here. Clear both players:
          // depending on whether the post-fade swap ran, the outgoing player
          // may be either one.
          try {
            await _inactivePlayer.dspClearGainCurve();
          } catch (_) {}
          try {
            await _activePlayer.dspClearGainCurve();
          } catch (_) {}
          try {
            await _inactivePlayer.stop();
          } catch (_) {}
          try {
            await _activePlayer.setVolume(initialActiveVolume);
          } catch (_) {}
        }
      }
    });
    } finally {
      _tripleBufferPipeline.releaseInactive(PlayerClaim.crossfade);
    }
  }

  int? _getNextIndex({int offset = 1, bool peek = false}) {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) {
      if (offset == 1 && !peek) {
        _shuffleHistory.add(_currentIndex);
        if (_shuffleHistory.length > 50) {
          _shuffleHistory.removeAt(0);
        }
      }
      if (_songs.length == 2) {
        // In a 2-song queue with shuffle enabled, alternate to the other song
        return _currentIndex == 0 ? 1 : 0;
      }
      if (_songs.length == 1) {
        return 0;
      }
      final random = math.Random();
      final recentWindow = math.min(_songs.length - 1, 10);
      final recent = _shuffleHistory.length >= recentWindow
          ? _shuffleHistory.sublist(_shuffleHistory.length - recentWindow)
          : _shuffleHistory;

      int next = random.nextInt(_songs.length);
      int attempts = 0;
      final maxAttempts = _songs.length * 2;
      while ((next == _currentIndex || recent.contains(next)) &&
          attempts < maxAttempts &&
          _songs.length > 1) {
        next = random.nextInt(_songs.length);
        attempts++;
      }
      if (next == _currentIndex && _songs.length > 1) {
        final candidates = [
          for (int i = 0; i < _songs.length; i++)
            if (i != _currentIndex) i
        ];
        next = candidates[random.nextInt(candidates.length)];
      }
      return next;
    }
    if (_currentIndex + offset < _songs.length) {
      return _currentIndex + offset;
    } else if (_activePlayer.loopMode == LoopMode.all && _songs.isNotEmpty) {
      return (_currentIndex + offset) % _songs.length;
    }
    return null;
  }

  int? _getPreviousIndex({bool forcePrevious = false}) {
    if (_songs.isEmpty) return null;
    if (!forcePrevious && _activePlayer.position.inSeconds > 3) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _shuffleHistory.isNotEmpty) {
      // Drain any stale entries left over from a previous/shorter queue rather
      // than returning an out-of-range index.
      while (_shuffleHistory.isNotEmpty) {
        final previous = _shuffleHistory.removeLast();
        if (previous >= 0 && previous < _songs.length) return previous;
      }
    }
    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (_activePlayer.loopMode == LoopMode.all) {
      return _songs.length - 1;
    }
    return null;
  }

  void _broadcastState(PlaybackEvent event) {
    // Player events are already filtered to the active player by
    // setupPlayerListeners' isTargetActive(); the previous identical() guard
    // here compared _activePlayer against its own definition and was always
    // false (dead code).
    // If a gapless load is actively preparing a new track for user playback,
    // ignore transient idle/stop events emitted by stop() before setAudioSources.
    if (_gaplessMode &&
        !_gaplessLoaded &&
        _userPlaybackInitiated &&
        _gaplessTargetIndex != null) {
      return;
    }

    final isCompleted =
        _activePlayer.processingState == ProcessingState.completed;
    final isPlaying = _activePlayer.playing && !isCompleted;
    final activeSong = currentSong;
    final isStream =
        activeSong != null && _isStreamUrl(activeSong.path);
    // Skip controls follow the queue, not the URL scheme (C-1): a lone live
    // stream has nowhere to skip, and neither has a single-track local queue.
    // What matters is whether a neighbouring queue entry actually exists.
    final hasPrevious = _hasQueueNeighbour(forward: false);
    final hasNext = _hasQueueNeighbour(forward: true);
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_activePlayer.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        // Keep the advertised system actions consistent with the control set
        // above: a stream may never expose a duration, so seek is meaningless
        // for a live source, and shuffle/repeat mean nothing when the queue
        // holds no other entry to act on (C-1).
        systemActions: {
          if (!isStream) ...[
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          ],
          if (hasPrevious || hasNext) ...[
            MediaAction.setShuffleMode,
            MediaAction.setRepeatMode,
          ],
        },
        androidCompactActionIndices: [
          for (var i = 0; i < controls.length; i++) i,
        ],
        processingState: processingState,
        playing: isPlaying,
        // Report the latency-compensated position so the notification shade's
        // scrubber matches what the user actually hears (matches the in-app
        // UI/lyrics, which already use compensatedPosition).
        updatePosition: compensatedPosition,
        bufferedPosition: _activePlayer.bufferedPosition,
        speed: _activePlayer.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  /// Whether the queue holds another entry to skip to in [forward] direction.
  ///
  /// Non-destructive on purpose — it is called from [_broadcastState], which
  /// must not consume shuffle history or otherwise mutate navigation state the
  /// way [_getNextIndex] / [_getPreviousIndex] do when they are read for
  /// real. A single-entry queue (a lone live stream, a one-track album) has no
  /// neighbour; so does the last track of a non-looping queue going forward.
  bool _hasQueueNeighbour({required bool forward}) {
    if (_songs.length <= 1) return false;
    if (_activePlayer.shuffleModeEnabled) return true;
    if (_activePlayer.loopMode == LoopMode.all) return true;
    return forward ? _currentIndex + 1 < _songs.length : _currentIndex > 0;
  }

  /// Resume decision shared by every interruption-end path: resume only when
  /// playback was actually running when the interruption began, the user's
  /// preference allows it, and nothing else has already resumed playback.
  @visibleForTesting
  static bool shouldResumeAfterInterruption({
    required bool wasPlayingBeforeInterruption,
    required bool resumeAfterInterruption,
    required bool currentlyPlaying,
  }) =>
      wasPlayingBeforeInterruption &&
      resumeAfterInterruption &&
      !currentlyPlaying;

  bool _isSameSongList(List<SongsTableData> a, List<SongsTableData> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].path != b[i].path) return false;
    }
    return true;
  }

  Future<bool> _isGenerationCancelled(int generation) async {
    // Pure predicate: no side effects. Callers restore volume explicitly so a
    // stale poll can never mutate the live player.
    return generation != _playGeneration;
  }

  Future<void> _loadSongPaused(int index, {Duration? initialPosition}) async {
    _userPlaybackInitiated = true;
    if (index < 0 || index >= _songs.length) return;
    final generation = ++_playGeneration;
    final song = _songs[index];
    _currentIndex = index;
    _pendingLazyPosition = null;

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = _songToMediaItem(song, fastArtUri);
    mediaItem.add(item);
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));

    await _fadeOutForSwitch(_activePlayer);
    if (await _isGenerationCancelled(generation)) return;

    try {
      await _activePlayer.pause();
    } catch (_) {}

    final targetVolume = _calculateReplayGainVolume(song);
    try {
      await _activePlayer.dspClearGainCurve();
    } catch (_) {}
    await _activePlayer.setVolume(targetVolume);

    if (song.source == SongSource.youtube &&
        (song.remoteId?.isNotEmpty ?? false) &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true))) {
      _pendingLazyPosition = initialPosition ?? Duration.zero;
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }

    try {
      final source = await _resolveAudioSource(song, item);
      if (await _isGenerationCancelled(generation)) return;
      await _activePlayer.setAudioSource(
        source,
        initialPosition: initialPosition ?? Duration.zero,
        preload: false,
      );
      _broadcastState(_activePlayer.playbackEvent);
    } catch (e, st) {
      ErrorLogger.log('Failed to load song paused',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  // --- QUEUE & PLAYBACK COMMANDS ---
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition, bool autoPlay = true}) async {
    if (songs.isEmpty) {
      _songs = [];
      _currentIndex = 0;
      _queueDirty = true;
      _gaplessLoaded = false;
      _pendingLazyPosition = null;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    _userPlaybackInitiated = true;
    _isManualSkip = true;
    // Immediately warm the target song so network resolution overlaps
    // with crossfade cancellation, queue assembly, and player teardown.
    final targetIdx =
        initialIndex.clamp(0, songs.isEmpty ? 0 : songs.length - 1);
    final initialSong = songs[targetIdx];
    if (initialSong.source == SongSource.youtube &&
        (initialSong.remoteId?.isNotEmpty ?? false) &&
        (initialSong.path.startsWith('ytmusic://') ||
            initialSong.path.isEmpty ||
            (!initialSong.path.startsWith('content:') &&
                initialSong.isDownloaded != true))) {
      unawaited(_warmStreamCache(initialSong));
    }

    // Gapless Album Pre-buffering: pre-buffer opening 3 tracks (0, 1, 2) when queue is loaded
    for (int i = 1; i <= 2; i++) {
      final lookaheadIdx = targetIdx + i;
      if (lookaheadIdx < songs.length) {
        final lookaheadSong = songs[lookaheadIdx];
        if (lookaheadSong.source == SongSource.youtube &&
            (lookaheadSong.remoteId?.isNotEmpty ?? false)) {
          unawaited(_warmStreamCache(lookaheadSong));
        }
        unawaited(ArtworkUriResolver.resolveArtworkUri(lookaheadSong));
      }
    }

    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);

    // Fast-path: if gapless queue is already loaded with the exact same songs,
    // immediately seek to the requested track instead of tearing down
    // and recreating the entire ExoPlayer playlist.
    if (_gaplessMode &&
        _gaplessLoaded &&
        _activePlayer.audioSources.length == songs.length &&
        _isSameSongList(_songs, songs)) {
      final generation = ++_playGeneration;
      final targetIndex =
          initialIndex.clamp(0, _songs.isEmpty ? 0 : _songs.length - 1);
      _currentIndex = targetIndex;
      _lastGaplessIndex = targetIndex;
      _gaplessTargetIndex = targetIndex;
      _gaplessTargetReached = false;
      _gaplessLoadTime = DateTime.now();
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _lastGaplessChangeTime = null;
      final song = _songs[targetIndex];
      final fastArtUri =
          song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
      mediaItem.add(_songToMediaItem(song, fastArtUri));
      _notifyTrackChanged(song);
      unawaited(_evaluateBufferBucket(song));
      _planNextStreamResolution();

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            autoPlay ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          processingState: autoPlay
              ? AudioProcessingState.loading
              : AudioProcessingState.ready,
          playing: autoPlay,
          queueIndex: targetIndex,
        ),
      );

      if (song.source == SongSource.youtube &&
          (song.remoteId?.isNotEmpty ?? false) &&
          (song.path.startsWith('ytmusic://') ||
              song.path.isEmpty ||
              (!song.path.startsWith('content:') &&
                  song.isDownloaded != true))) {
        unawaited(_warmStreamCache(song).catchError((e) {
          if (generation != _playGeneration) return;
          debugPrint(
              '[AudioHandler] Background warm failed for ${song.title}: $e');
        }));
      }

      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;

      await _activePlayer.seek(initialPosition ?? Duration.zero,
          index: targetIndex);
      if (_activePlayer.currentIndex == targetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      }
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      await _activePlayer.setVolume(targetVolume);
      if (autoPlay) {
        unawaited(_activePlayer.play());
      } else {
        try {
          await _activePlayer.pause();
        } catch (_) {}
      }
      _broadcastState(_activePlayer.playbackEvent);
      if (autoPlay) {
        _repository.recordPlayHistory(song.id);
      }
      _saveCurrentPosition();

      ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
        if (artUri != null &&
            artUri != fastArtUri &&
            generation == _playGeneration &&
            currentSong?.id == song.id) {
          mediaItem.add(_songToMediaItem(song, artUri));
        }
      }).catchError((_) {});
      return;
    }

    _songs = List.from(songs);
    _currentIndex =
        initialIndex.clamp(0, _songs.isEmpty ? 0 : _songs.length - 1);
    // A new queue invalidates shuffle navigation history; stale indices would
    // otherwise point at unrelated tracks (or out of range) on Previous.
    _shuffleHistory.clear();
    _queueDirty = true;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;

    final mediaItems = _songs.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    if (_gaplessMode) {
      await _loadGaplessQueue(initialPosition: initialPosition, preload: autoPlay);
    } else {
      if (autoPlay) {
        await playSongAt(_currentIndex, initialPosition: initialPosition);
      } else {
        await _loadSongPaused(_currentIndex, initialPosition: initialPosition);
      }
    }
  }

  void swapReconciledSong(int oldId, SongsTableData newSong) {
    final idx = _songs.indexWhere((s) => s.id == oldId);
    if (idx != -1) {
      _songs[idx] = newSong;
      final mediaItems = _songs.map(_songToMediaItem).toList();
      queue.add(mediaItems);
      if (_currentIndex == idx) {
        final fastArtUri = newSong.artworkUri != null
            ? Uri.tryParse(newSong.artworkUri!)
            : null;
        mediaItem.add(_songToMediaItem(newSong, fastArtUri));
      }
    }
  }

  /// Loads the whole queue as a playlist on the active
  /// player so ExoPlayer joins consecutive tracks with no gap. With [preload]
  /// false the source is set but not prepared, so a restored YouTube track
  /// resolves lazily on the first play() instead of throwing at cold start when
  /// offline.
  Future<void> _loadGaplessQueue(
      {Duration? initialPosition, bool preload = true}) async {
    if (_songs.isEmpty) return;
    final generation = ++_playGeneration;
    // Quiesce native index events for the whole load: stop()/setAudioSources
    // emit transient indices (playlist attach resets to 0 before the initial
    // seek lands). With the stale _gaplessLoaded=true those transients used
    // to run _onGaplessIndexChanged mid-load, corrupting _currentIndex —
    // sometimes BEFORE it was consumed as initialIndex below, so tapping
    // song N loaded and played song 0 instead, with mediaItem/volume/history
    // churning (the "glitch + first song again" bug).
    _gaplessLoaded = false;
    _pendingLazyPosition = null;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;
    // Snapshot: no interleaved stream event may change the load target.
    final targetIndex = _currentIndex;
    _lastGaplessIndex = targetIndex;
    _gaplessTargetIndex = targetIndex;
    _gaplessTargetReached = false;
    _gaplessLoadTime = DateTime.now();

    final song = _songs[targetIndex];
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(_songToMediaItem(song, fastArtUri));
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));
    _planNextStreamResolution();

    if (preload) {
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            MediaControl.pause,
            MediaControl.skipToNext,
          ],
          androidCompactActionIndices: const [0, 1, 2],
          processingState: AudioProcessingState.loading,
          playing: true,
          queueIndex: targetIndex,
        ),
      );
    }

    final sources = _buildAudioSources(_songs);

    // Pre-resolve the target online URL BEFORE stopping current playback:
    // a YouTube resolve can take seconds, and stopping first turns that into
    // seconds of dead silence followed by a cold start. Resolving first keeps
    // the old track playing until the swap is near-instant (the URL lands in
    // _streamCache/YtmUrlCache, which the lazy child then reuses). On failure
    // the current track keeps playing and only an error toast is shown.
    // Fire-and-forget: if the warm completes before setAudioSources, the
    // YtmResolvingSource child hits a hot cache; if not, the child resolves
    // lazily on its own.
    if (song.source == SongSource.youtube &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true)) &&
        (song.remoteId?.isNotEmpty ?? false)) {
      unawaited(_warmStreamCache(song).catchError((e) {
        if (generation != _playGeneration) return;
        debugPrint(
            '[AudioHandler] Gapless pre-warm failed for ${song.title}: $e');
      }));
    }

    try {
      // Soft-landing fade so the stop doesn't click, then cleanly stop any
      // existing playing source to release hanging native sockets.
      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;
      try {
        await _activePlayer.stop();
      } catch (_) {}

      await _activePlayer.setAudioSources(
        sources,
        initialIndex: targetIndex,
        initialPosition: initialPosition,
        preload: preload,
      );
      try {
        _latencyTracker?.markStage(PlaybackStage.sourceSet);
      } catch (_) {}
      _gaplessLoaded = true;
      _lastGaplessIndex = targetIndex;
      _gaplessLoadTime = DateTime.now();
      if (_activePlayer.currentIndex == targetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      }
      if (await _isGenerationCancelled(generation)) return;
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      if (!preload) {
        // Restored queue, not playing yet: park the correct level so a later
        // play() doesn't inherit a faded-out 0 from a previous switch.
        await _activePlayer.setVolume(targetVolume);
      } else {
        await _activePlayer.setVolume(targetVolume);
        // FIX-#2b: Re-check generation after the async setVolume — same race
        // condition as playSongAt (see FIX-#2).
        if (_playGeneration != generation) return;
        unawaited(_activePlayer.play());
        _broadcastState(_activePlayer.playbackEvent);
      }
      if (preload) {
        try {
          _latencyTracker?.markStage(PlaybackStage.firstBytesReady);
          _latencyTracker?.markStage(PlaybackStage.playing);
        } catch (_) {}
        _consecutiveFailures = 0;
        _repository.recordPlayHistory(song.id);
      }
      _saveCurrentPosition();

      // Resolve high-res artwork off the hot path, like the crossfade engine.
      ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
        if (artUri != null &&
            artUri != fastArtUri &&
            generation == _playGeneration &&
            currentSong?.id == song.id) {
          mediaItem.add(_songToMediaItem(song, artUri));
        }
      }).catchError((_) {});
    } on YtmException catch (e, st) {
      if (generation != _playGeneration) return;
      final info = YtmErrorClassifier.classify(e);
      _errorSubject.add(info.message);
      ErrorLogger.log(
          'Error loading gapless YouTube source for ${song.title} (${e.code})',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      if (e.isFatal) {
        await _failCurrentPlayback(fatal: true);
        return;
      }
      // Non-fatal: skip this track and try the next
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
        await _failCurrentPlayback(fatal: false);
        return;
      }
      final nextIdx = _getNextIndex();
      if (nextIdx != null && nextIdx != targetIndex) {
        await playSongAt(nextIdx, initialPosition: initialPosition);
      } else {
        await _failCurrentPlayback(fatal: false);
      }
    } catch (e, st) {
      if (generation != _playGeneration) return;
      final errStr = e.toString().toLowerCase();
      // Ignore loading interrupted / abort errors resulting from newer play actions
      if (errStr.contains('interrupted') || errStr.contains('abort')) {
        return;
      }
      final info = YtmErrorClassifier.classify(e);
      final String errorMessage;
      if (e is PlayerException && e.message != null && e.message!.isNotEmpty) {
        errorMessage = e.message!;
      } else {
        errorMessage = info.message;
      }
      _errorSubject.add(errorMessage);
      ErrorLogger.log('Error loading gapless queue for ${song.title}',
          error: e, stackTrace: st, category: 'AudioHandler');

      // If the source at targetIndex has a permanent failure (BOT_CHALLENGE,
      // VIDEO_GONE, etc.) stored by YtmResolvingSource, the ExoPlayer "Source
      // error" is a known-permanent cause — skip to the next track rather than
      // calling _failCurrentPlayback(fatal: true) which just pauses and leaves
      // the user stuck with no audio and no way to continue.
      final targetSource = sources.length > targetIndex ? sources[targetIndex] : null;
      final sourcePermanentFailure = targetSource is YtmResolvingSource
          ? targetSource.permanentFailure
          : null;
      if (sourcePermanentFailure != null) {
        final failInfo = YtmErrorClassifier.classify(sourcePermanentFailure);
        _errorSubject.add(failInfo.message);
        _consecutiveFailures++;
        if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
          await _failCurrentPlayback(fatal: false);
        } else {
          final nextIdx = _getNextIndex();
          if (nextIdx != null && nextIdx != targetIndex) {
            await playSongAt(nextIdx, initialPosition: initialPosition);
          } else {
            await _failCurrentPlayback(fatal: false);
          }
        }
        return;
      }

      final isFatal = (e is YtmException && e.isFatal) ||
          info.recoveryAction != YtmRecoveryAction.skipToNextTrack;
      await _failCurrentPlayback(fatal: isFatal);
    }

  }

  /// Reacts to a native gapless advance (currentIndexStream): keeps the queue
  /// model, notification, play history, replay-gain volume and saved position in
  /// step with the item ExoPlayer moved to on its own.
  Future<void> _onGaplessIndexChanged(int index) async {
    if (!_gaplessMode) return;
    if (index < 0 || index >= _songs.length) return;
    if (!_gaplessLoaded) return;
    final childCount = _activePlayer.audioSources.length;
    if (index >= childCount) return;

    // Transient index 0 / spurious emit filter:
    // When loading a playlist, ExoPlayer may emit an initial index 0 before settling on the
    // requested target index. If target index hasn't been reached yet, ignore any unexpected index.
    if (_gaplessTargetIndex != null) {
      if (index == _gaplessTargetIndex) {
        _gaplessTargetReached = true;
        _gaplessTargetIndex = null;
      } else if (!_gaplessTargetReached) {
        final elapsed = _gaplessLoadTime != null
            ? DateTime.now().difference(_gaplessLoadTime!).inMilliseconds
            : 99999;
        if (elapsed < 3000) {
          debugPrint(
              '[AudioHandler] Ignoring spurious gapless index event: $index (target was $_gaplessTargetIndex)');
          return;
        }
      }
    }

    // Detect rapid successive transitions caused by ExoPlayer auto-advancing
    // past failing tracks in a loop. If user paused, kill the loop immediately.
    if (!_activePlayer.playing) {
      _rapidGaplessChangeCount = 0;
      _consecutiveFailures = 0;
      return;
    }
    if (_isManualSkip) {
      _isManualSkip = false;
      _rapidGaplessChangeCount = 0;
      _consecutiveFailures = 0;
    } else {
      final now = DateTime.now();
      if (_lastGaplessChangeTime != null &&
          now.difference(_lastGaplessChangeTime!).inMilliseconds < 1500) {
        _rapidGaplessChangeCount++;
        if (_rapidGaplessChangeCount >= 3) {
          // Circuit breaker tripped: halt runaway skip loop
          _rapidGaplessChangeCount = 0;
          _consecutiveFailures = 0;
          ErrorLogger.log(
            'Circuit breaker tripped: rapid gapless track changes detected. Halting playback.',
            category: 'AudioHandler',
          );
          _errorSubject.add('Playback stopped: multiple tracks failed to load.');
          await _activePlayer.pause();
          _broadcastState(_activePlayer.playbackEvent);
          return;
        }
      } else {
        _rapidGaplessChangeCount = 0;
        _consecutiveFailures = 0;
      }
      _lastGaplessChangeTime = now;
    }

    _lastGaplessIndex = index;
    _currentIndex = index;
    final song = _songs[index];
    final generation = _playGeneration;

    // Notify sleep timer of track completion for endOfTrack / afterNTracks
    // modes (fixes silent never-fire). Fired before the async work below so it
    // lands within the duplicate-collapse window of the native `completed`
    // event that reports the same boundary.
    _notifySleepTrackCompleted();

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(_songToMediaItem(song, fastArtUri));
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));
    _planNextStreamResolution();
    await _activePlayer.setVolume(_calculateReplayGainVolume(song));
    _repository.recordPlayHistory(song.id);
    _broadcastState(_activePlayer.playbackEvent);
    _saveCurrentPosition();

    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null &&
          artUri != fastArtUri &&
          _currentIndex == index &&
          generation == _playGeneration &&
          currentSong?.id == song.id) {
        mediaItem.add(_songToMediaItem(song, artUri));
      }
    }).catchError((_) {});
  }

  void _planNextStreamResolution() {
    if (_songs.isEmpty) return;
    _streamPreResolver.onTrackStarted(
      queue: _songs,
      currentIndex: _currentIndex,
      isShuffle: _activePlayer.shuffleModeEnabled,
    );
  }

  Future<void> playSongAt(int index, {Duration? initialPosition}) async {
    _userPlaybackInitiated = true;
    if (index < 0 || index >= _songs.length) return;
    cancelPrefetches();
    // A YouTube resolve below can await for seconds; a second skip during that
    // window must win. Capture a generation token FIRST so a pre-resolve
    // failure can bail without touching current playback at all.
    final generation = ++_playGeneration;
    final song = _songs[index];
    _streamPreResolver.onTrackEnqueuedOrTapped(song);

    // Fire-and-forget background warm: if the URL is already cached this
    // returns instantly; if not, it populates the cache in the background
    // so the lazy YtmResolvingSource hits a hot cache when just_audio
    // requests bytes. Never blocks the tap→play path.
    if (song.source == SongSource.youtube &&
        (song.remoteId?.isNotEmpty ?? false) &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && song.isDownloaded != true))) {
      unawaited(_warmStreamCache(song).catchError((e) {
        if (generation != _playGeneration) return;
        debugPrint(
            '[AudioHandler] Background warm failed for ${song.title}: $e');
      }));
    }

    // Soft-landing fade so pause/stop doesn't click, then ensure the previous
    // MediaCodec EventHandler is fully released before creating a new decoder
    // — prevents LegacyMessageQueue dead-thread crash on rapid Hi-Res FLAC switch (LOG-12)
    // Fast path: when the player is idle with no source, there is no decoder
    // to tear down — skip the ~1s pause/stop/grace serial entirely.
    final needsTeardown = _activePlayer.playing ||
        (_activePlayer.audioSource != null &&
            _activePlayer.processingState != ProcessingState.idle &&
            _activePlayer.processingState != ProcessingState.completed);
    if (needsTeardown) {
      await _fadeOutForSwitch(_activePlayer);
      if (await _isGenerationCancelled(generation)) return;
      try {
        await _activePlayer.pause().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      try {
        await _activePlayer.stop().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
      // Grace period only for decoder-backed switches (local/Hi-Res). YouTube
      // lazy sources create no MediaCodec until first bytes are requested.
      final isLocalDecode =
          song.source == SongSource.local || song.isDownloaded == true;
      if (isLocalDecode) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } else {
      if (await _isGenerationCancelled(generation)) return;
    }
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    if (await _isGenerationCancelled(generation)) return;
    _pendingLazyPosition = null;
    _currentIndex = index;
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = _songToMediaItem(song, fastArtUri);
    mediaItem.add(item);
    _notifyTrackChanged(song);
    unawaited(_evaluateBufferBucket(song));

    // Resolve high-res artwork in background without blocking audio source loading
    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null &&
          artUri != fastArtUri &&
          generation == _playGeneration &&
          currentSong?.id == song.id) {
        mediaItem.add(_songToMediaItem(song, artUri));
      }
    }).catchError((_) {});

    // Kick off background prefetch for next track immediately so next skip is instant
    if (index + 1 < _songs.length) {
      _prefetchStream(_songs[index + 1]);
    }

    // Keep notification controls alive during track transition
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.loading,
        playing: true,
        queueIndex: _currentIndex,
      ),
    );

    try {
      AudioSource source = await _resolveAudioSource(song, item);
      if (await _isGenerationCancelled(generation)) return;
      // For YouTube tracks using YtmResolvingSource (no warm cache hit),
      // use preload: false so setAudioSource returns instantly. just_audio
      // will call the resolve callback when it actually needs bytes,
      // keeping the UI responsive during the (potentially slow) resolution.
      final useLazyPreload = source is YtmResolvingSource;
      try {
        await _activePlayer.setAudioSource(source,
            initialPosition: initialPosition, preload: !useLazyPreload);
      } catch (playErr) {
        // If a YouTube stream fails (e.g. 403 / expired URL), clear cache & retry once
        if (song.source == SongSource.youtube && song.remoteId != null) {
          debugPrint(
              '[AudioHandler] Playback error on ${song.title}: $playErr. Retrying with fresh stream URL...');
          _streamCache.removeWhere((key, _) => key.startsWith('${song.remoteId}:'));
          source = await _resolveAudioSource(song, item);
          if (await _isGenerationCancelled(generation)) return;
          final retryLazy = source is YtmResolvingSource;
          await _activePlayer.setAudioSource(source,
              initialPosition: initialPosition, preload: !retryLazy);
        } else {
          rethrow;
        }
      }
      if (await _isGenerationCancelled(generation)) return;
      final targetVolume = _calculateReplayGainVolume(song);
      try {
        await _activePlayer.dspClearGainCurve();
      } catch (_) {}
      await _activePlayer.setVolume(targetVolume);
      // FIX-#2: Re-check generation after the async setVolume — a rapid skip
      // during the await can load a new source, and calling play() here would
      // inadvertently start the wrong track.
      if (_playGeneration != generation) return;
      unawaited(_activePlayer.play());
      _broadcastState(_activePlayer.playbackEvent);
      _consecutiveFailures = 0;
      _repository.recordPlayHistory(song.id);
      _saveCurrentPosition();

      // Early prefetch next streams for Gapless 2.0
      _prefetchNextTracks();
      // Unified preload depth: bucket drives ALL stages (scheduler via
      // _smartPrefetch above, triple-buffer here). minimal=1 holds only N+1,
      // standard=2 adds N+2, generous=3 keeps full lookahead.
      final depth = _preloadCountForCurrentBucket;
      // Only preload onto inactive player when crossfade is active
      if (!_gaplessMode && depth >= 1 && _songs.length > index + 1) {
        unawaited(_tripleBufferPipeline.preloadNext(_songs[index + 1]));
      }
      if (!_gaplessMode && depth >= 2 && _songs.length > index + 2) {
        unawaited(_tripleBufferPipeline.prefetchAhead(_songs[index + 2]));
      }
    } on YtmException catch (e, st) {
      if (generation != _playGeneration) return;
      final info = YtmErrorClassifier.classify(e);
      _errorSubject.add(info.message);
      ErrorLogger.log(
          'Error resolving YouTube stream for ${song.title} (${e.code})',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      // A dead network, bot challenge, or extractor-less build fails every remaining YouTube
      // row, so skipping through them is pointless — halt immediately.
      await _failCurrentPlayback(fatal: e.isFatal);
    } on DsdUnsupportedException catch (e, st) {
      if (generation != _playGeneration) return;
      // DSD (DSF/DFF) on a platform with no native decoder (e.g. iOS) must
      // fail visibly and skip, never crash or loop on the same row.
      _errorSubject.add(e.message);
      ErrorLogger.log('DSD playback unsupported for ${song.title}',
          error: e, stackTrace: st, category: 'AudioHandler');
      await _failCurrentPlayback(fatal: false);
    } catch (e, st) {
      if (generation != _playGeneration) return;
      if (e is PlatformException &&
          (e.code == 'abort' ||
              (e.message ?? '').toLowerCase().contains('abort') ||
              (e.message ?? '').toLowerCase().contains('interrupted'))) {
        return;
      }
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('interrupted') || errStr.contains('abort')) {
        return;
      }
      final info = YtmErrorClassifier.classify(e);
      final String errorMessage;
      if (e is PlayerException && e.message != null && e.message!.isNotEmpty) {
        errorMessage = e.message!;
      } else {
        errorMessage = info.message;
      }
      _errorSubject.add(errorMessage);
      ErrorLogger.log('Error playing song ${song.title} (${song.path})',
          error: e, stackTrace: st, category: 'AudioHandler');
      final isFatal = (e is YtmException && e.isFatal) ||
          info.recoveryAction != YtmRecoveryAction.skipToNextTrack;
      await _failCurrentPlayback(fatal: isFatal);
    }
  }

  /// Shared failure handling for [playSongAt]: a fatal error pauses outright,
  /// otherwise skip forward until [_consecutiveFailures] trips the circuit.
  /// Stops the loop if playback is already paused (user hit pause) or after
  /// 3 consecutive failures — prevents infinite skip loop on bot-blocked IP.
  Future<void> _failCurrentPlayback({required bool fatal}) async {
    // User paused during the failure chain → never auto-resume/skip.
    if (!_activePlayer.playing) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }
    if (fatal) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3 || _consecutiveFailures >= _songs.length) {
      _consecutiveFailures = 0;
      _rapidGaplessChangeCount = 0;
      _errorSubject.add('Playback failed for consecutive tracks. Stopping.');
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      await skipToNext();
    }
  }

  // --- PLAYBACK ACTIONS ---
  @override
  Future<void> play() {
    _userPlaybackInitiated = true;
    unawaited(() async {
      try {
        final s = await AudioSession.instance;
        await s.setActive(true);
      } catch (_) {}
    }());
    ErrorLogger.addBreadcrumb('Playback started', category: 'player');
    // A restored YouTube session in the crossfade engine is left with no source
    // loaded (see restoreLastPlaybackSession); resolve and start it on the first
    // play. The gapless engine instead sets a non-preloaded concat at restore,
    // so play() below prepares and starts it lazily with no special-casing.
    final pending = _pendingLazyPosition;
    if (pending != null && currentSong != null && !_gaplessMode) {
      _pendingLazyPosition = null;
      return playSongAt(_currentIndex, initialPosition: pending);
    }
    final generation = _playGeneration;
    final player = _activePlayer;
    try {
      player.dspClearGainCurve().catchError((_) => false);
    } catch (_) {}
    final playFuture = player.play();
    _scheduleFadeInConvergenceGuard(player, generation);
    _broadcastState(player.playbackEvent);
    return playFuture;
  }

  @override
  Future<void> pause() async {
    // A deliberate pause invalidates any pending interruption snapshot so a
    // later call can still pause us (B-1); the previous code only cleared the
    // "was playing" half, leaving the active flag set.
    _interruption.onUserPause();
    ErrorLogger.addBreadcrumb('Playback paused', category: 'player');
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _preCrossfadeVolume ?? _volume);
    _saveCurrentPosition();
    // If an online source is still being fetched/loaded (the track is not
    // playable yet), invalidate the in-flight load cycle so a late resolve — or
    // the play() at the end of playSongAt — cannot start playback after the
    // user paused. The position is remembered so a later play() re-runs the
    // cycle (re-fetches) instead of silently doing nothing.
    final playerState = _activePlayer.processingState;
    final stillLoading = playerState == ProcessingState.loading ||
        playerState == ProcessingState.buffering ||
        playerState == ProcessingState.idle;
    if (stillLoading) {
      _playGeneration++;
      cancelPrefetches();
      _pendingLazyPosition = _activePlayer.position;
    }
    await _activePlayer.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seek to ${position.inSeconds}s',
        category: 'player');
    // Optimistic UI: emit locally first so the slider feels instant,
    // then debounce the backend call to avoid jitter during scrubbing.
    // NOTE: PlayerCubit already throttles scrub floods (100ms). This layer
    // only coalesces sub-60ms bursts, so a discrete tap passes through a
    // single layer, not two stacked 100ms windows.
    _positionSubject.add(position);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSeekMs < 60) {
      _pendingSeekPosition = position;
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer =
          Timer(const Duration(milliseconds: 60), () {
        final pending = _pendingSeekPosition;
        _pendingSeekPosition = null;
        if (pending != null) {
          _performSeek(pending).catchError((Object e, StackTrace st) {
            ErrorLogger.log('Debounced seek failed',
                error: e, stackTrace: st, category: 'AudioHandler');
          });
        }
      });
      return;
    }
    _lastSeekMs = now;
    await _performSeek(position);
  }

  /// Direct seek without debounce, for discrete user intents (tap-to-seek,
  /// skip-to-previous-restart). The cubit already throttles scrub floods, so
  /// routing discrete seeks here avoids the double 100ms window stacking.
  Future<void> seekDirect(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seekDirect to ${position.inSeconds}s',
        category: 'player');
    _positionSubject.add(position);
    _lastSeekMs = DateTime.now().millisecondsSinceEpoch;
    _pendingSeekPosition = null;
    _seekDebounceTimer?.cancel();
    await _performSeek(position);
  }

  Future<void> _performSeek(Duration position) async {
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    try {
      await _activePlayer.seek(position);
    } catch (_) {
      // Roll back to the last known good position on failure.
      _positionSubject.add(_activePlayer.position);
      rethrow;
    }
    _positionSubject.add(position);
    _saveCurrentPosition();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    await loadQueue(_songs, initialIndex: index, autoPlay: _activePlayer.playing);
  }

  @override
  Future<void> skipToNext() async {
    ErrorLogger.addBreadcrumb('Playback skipToNext', category: 'player');
    // Invalidate stale prefetch completions; the manual playSongAt path below
    // captures its own _playGeneration token (no double-bump here).
    cancelPrefetches();
    _isManualSkip = true;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;
    final wasPlaying = _activePlayer.playing;

    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    }
    if (_gaplessMode && _gaplessLoaded) {
      // Native advance: invalidate any in-flight manual playSongAt resolve so
      // a slow YouTube URL fetch cannot clobber the new current item.
      _playGeneration++;
      if (_activePlayer.hasNext) {
        await _activePlayer.seekToNext();
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else if (_activePlayer.loopMode == LoopMode.all && _songs.isNotEmpty) {
        await _activePlayer.seek(Duration.zero, index: 0);
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else {
        await _activePlayer.pause();
        await _activePlayer.seek(Duration.zero);
        _broadcastState(_activePlayer.playbackEvent);
      }
      return;
    }

    final nextIdx = _getNextIndex();
    if (nextIdx != null) {
      if (wasPlaying) {
        await playSongAt(nextIdx);
      } else {
        await _loadSongPaused(nextIdx);
      }
    } else {
      await _activePlayer.pause();
      await _activePlayer.seek(Duration.zero);
      _broadcastState(_activePlayer.playbackEvent);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    ErrorLogger.addBreadcrumb('Playback skipToPrevious', category: 'player');
    cancelPrefetches();
    _isManualSkip = true;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;

    final now = DateTime.now();
    final isDoubleTap = _lastPreviousTapTime != null &&
        now.difference(_lastPreviousTapTime!).inMilliseconds < 2500;
    _lastPreviousTapTime = now;
    final wasPlaying = _activePlayer.playing;

    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    }
    if (_gaplessMode && _gaplessLoaded) {
      _playGeneration++;
      if (!isDoubleTap && _activePlayer.position.inSeconds > 3) {
        await _activePlayer.seek(Duration.zero);
        if (wasPlaying) {
          await _activePlayer.play();
        }
        _saveCurrentPosition();
        return;
      }
      if (_activePlayer.hasPrevious) {
        await _activePlayer.seekToPrevious();
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else if (_activePlayer.loopMode == LoopMode.all && _songs.isNotEmpty) {
        await _activePlayer.seek(Duration.zero, index: _songs.length - 1);
        if (wasPlaying) {
          await _activePlayer.play();
        }
      } else {
        await _activePlayer.seek(Duration.zero);
        if (wasPlaying) {
          await _activePlayer.play();
        }
        _saveCurrentPosition();
      }
      return;
    }
    if (!isDoubleTap && _activePlayer.position.inSeconds > 3) {
      await _activePlayer.seek(Duration.zero);
      if (wasPlaying) {
        await _activePlayer.play();
      }
      _saveCurrentPosition();
      return;
    }
    final prevIdx = _getPreviousIndex(forcePrevious: isDoubleTap);
    if (prevIdx != null) {
      if (wasPlaying) {
        await playSongAt(prevIdx);
      } else {
        await _loadSongPaused(prevIdx);
      }
    } else {
      await _activePlayer.seek(Duration.zero);
      if (wasPlaying) {
        await _activePlayer.play();
      }
      _saveCurrentPosition();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await Future.wait([
      _playerA.setShuffleModeEnabled(enable),
      _playerB.setShuffleModeEnabled(enable),
    ]);
    // In gapless mode the concat's shuffle order drives playback; reshuffle so
    // enabling shuffle actually reorders upcoming tracks (current stays put).
    if (enable && _gaplessMode && _gaplessLoaded) {
      await _activePlayer.shuffle();
    }
    // The crossfade engine draws its own random order from _getNextIndex, so no
    // native reshuffle is needed there.
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.playbackShuffle,
        shuffleMode == AudioServiceShuffleMode.all);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        LoopMode.all,
    };

    await Future.wait([
      _playerA.setLoopMode(loopMode),
      _playerB.setLoopMode(loopMode),
    ]);

    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    final persistMode = switch (repeatMode) {
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
      AudioServiceRepeatMode.one => 'one',
      _ => 'none',
    };
    await prefs.setString(PrefsKeys.playbackRepeatMode, persistMode);
  }

  // --- ANDROID AUTO & HEADSET BUTTON SUPPORT ---
  Timer? _headsetClickTimer;
  int _headsetClickCount = 0;

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    _headsetClickCount++;
    _headsetClickTimer?.cancel();

    if (_headsetClickCount >= 3) {
      _headsetClickCount = 0;
      await skipToPrevious();
      return;
    }

    _headsetClickTimer = Timer(const Duration(milliseconds: 350), () async {
      final count = _headsetClickCount;
      _headsetClickCount = 0;
      if (count == 1) {
        if (_activePlayer.playing) {
          await pause();
        } else {
          await play();
        }
      } else if (count == 2) {
        await skipToNext();
      }
    });
  }

  static const int maxQueueSize = 500;

  static const double _minPlaybackSpeed = 0.25;
  static const double _maxPlaybackSpeed = 4.0;
  static const double _minAdvancedPlaybackSpeed = 0.1;
  static const double _maxAdvancedPlaybackSpeed = 8.0;
  bool _advancedSpeedEnabled = false;

  double get minPlaybackSpeed =>
      _advancedSpeedEnabled ? _minAdvancedPlaybackSpeed : _minPlaybackSpeed;
  double get maxPlaybackSpeed =>
      _advancedSpeedEnabled ? _maxAdvancedPlaybackSpeed : _maxPlaybackSpeed;

  /// Enables the extended 0.1–8.0 speed range for power users.
  /// When disabled the stable 0.25–4.0 range is enforced.
  Future<void> setAdvancedSpeedEnabled(bool enabled) async {
    _advancedSpeedEnabled = enabled;
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(PrefsKeys.advancedPlaybackSpeed, enabled);
    // Re-clamp the current speed into the newly selected range so both
    // players stay in sync after the range changes.
    final current = playbackState.value.speed;
    final clamped = current.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    if (clamped != current) {
      await setSpeed(clamped);
    }
  }

  double _pitch = 1.0;
  double get pitch => _pitch;

  Future<void> restorePersistedSpeed() async {
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      _advancedSpeedEnabled =
          prefs.getBool(PrefsKeys.advancedPlaybackSpeed) ?? false;
      final saved = prefs.getDouble(PrefsKeys.playbackSpeed);
      if (saved != null) {
        final clamped = saved.clamp(minPlaybackSpeed, maxPlaybackSpeed);
        await Future.wait([
          _playerA.setSpeed(clamped),
          _playerB.setSpeed(clamped),
        ]);
        playbackState.add(playbackState.value.copyWith(speed: clamped));
      }
      final savedPitch = prefs.getDouble(PrefsKeys.playbackPitch);
      if (savedPitch != null) {
        final clampedPitch = savedPitch.clamp(0.5, 2.0);
        _pitch = clampedPitch;
        await Future.wait([
          _playerA.setPitch(clampedPitch),
          _playerB.setPitch(clampedPitch),
        ]);
      }
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(minPlaybackSpeed, maxPlaybackSpeed);
    await Future.wait([
      _playerA.setSpeed(clamped),
      _playerB.setSpeed(clamped),
    ]);
    playbackState.add(playbackState.value.copyWith(speed: clamped));
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackSpeed, clamped);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(0.5, 2.0);
    _pitch = clamped;
    await Future.wait([
      _playerA.setPitch(clamped),
      _playerB.setPitch(clamped),
    ]);
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      await prefs.setDouble(PrefsKeys.playbackPitch, clamped);
    } catch (_) {}
  }

  Future<void> validatePlayerState() async {
    final player = _activePlayer;
    if (player.processingState == ProcessingState.idle && _songs.isNotEmpty) {
      ErrorLogger.log('Player in idle state with non-empty queue, recovering',
          category: 'AudioHandler');
      await playSongAt(_currentIndex);
    }
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleFavorite':
        if (_songs.isNotEmpty && _currentIndex < _songs.length) {
          final currentSong = _songs[_currentIndex];
          final result = await _repository.toggleFavorite(currentSong.id);
          final newFav = result.fold((l) => currentSong.isFavorite, (r) => r);
          _songs[_currentIndex] = currentSong.copyWith(isFavorite: newFav);
          final artUri =
              await ArtworkUriResolver.resolveArtworkUri(_songs[_currentIndex]);
          mediaItem.add(_songToMediaItem(_songs[_currentIndex], artUri));
          return newFav;
        }
        return false;
      case 'toggleShuffle':
        final currentShuffle = _activePlayer.shuffleModeEnabled;
        await setShuffleMode(currentShuffle
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all);
        return !currentShuffle;
      case 'cycleRepeat':
      case 'toggleRepeat':
        final currentLoop = _activePlayer.loopMode;
        if (currentLoop == LoopMode.off) {
          await setRepeatMode(AudioServiceRepeatMode.all);
        } else if (currentLoop == LoopMode.all) {
          await setRepeatMode(AudioServiceRepeatMode.one);
        } else {
          await setRepeatMode(AudioServiceRepeatMode.none);
        }
        return true;
      default:
        return super.customAction(name, extras);
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (_songs.length >= maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($maxQueueSize)',
          category: 'AudioHandler');
      return;
    }
    final songId = int.tryParse(mediaItem.id);
    if (songId != null) {
      final songRes = await _repository.getSongById(songId);
      final song = songRes.fold((l) => null, (r) => r);
      if (song != null) {
        _songs.add(song);
        _queueDirty = true;
        if (_gaplessMode && _gaplessLoaded) {
          await _activePlayer.addAudioSource(_buildGaplessChild(song));
        }
        queue.add(_songs.map(_songToMediaItem).toList());
        _saveCurrentPosition();
      }
    }
  }

  Future<void> insertNextInQueue(SongsTableData song) async {
    final existingIdx = _songs.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1) {
      if (existingIdx == _currentIndex) {
        return;
      }
      final targetSlot = (_currentIndex + 1).clamp(0, _songs.length - 1);
      if (existingIdx == targetSlot) {
        return;
      }
      await reorderQueue(
          existingIdx, targetSlot > existingIdx ? targetSlot + 1 : targetSlot);
      return;
    }

    if (_songs.length >= maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($maxQueueSize)',
          category: 'AudioHandler');
      return;
    }
    final insertIdx =
        _songs.isEmpty ? 0 : (_currentIndex + 1).clamp(0, _songs.length);
    _songs.insert(insertIdx, song);
    _streamPreResolver.onTrackEnqueuedOrTapped(song);
    _queueDirty = true;
    // Insert sits after the current track, so the playing index never shifts.
    if (_gaplessMode && _gaplessLoaded) {
      await _activePlayer.insertAudioSource(
          insertIdx, _buildGaplessChild(song));
    }
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> addToQueueEnd(SongsTableData song) async {
    final existingIdx = _songs.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1) {
      if (existingIdx == _currentIndex) {
        return;
      }
      if (existingIdx == _songs.length - 1) {
        return;
      }
      await reorderQueue(existingIdx, _songs.length);
      return;
    }

    if (_songs.length >= maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($maxQueueSize)',
          category: 'AudioHandler');
      return;
    }
    _songs.add(song);
    _streamPreResolver.onTrackEnqueuedOrTapped(song);
    _queueDirty = true;
    if (_gaplessMode && _gaplessLoaded) {
      await _activePlayer.addAudioSource(_buildGaplessChild(song));
    }
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> clearQueue() async {
    if (_songs.isEmpty) return;
    final wasPlaying = _activePlayer.playing;
    if (_currentIndex >= 0 && _currentIndex < _songs.length) {
      final current = _songs[_currentIndex];
      _songs = [current];
      _currentIndex = 0;
      if (_gaplessMode && _gaplessLoaded) {
        await _loadGaplessQueue(preload: wasPlaying);
      }
    } else {
      _songs.clear();
      _currentIndex = 0;
      _gaplessLoaded = false;
      await stop();
    }
    _queueDirty = true;
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final wasPlayingCurrent = index == _currentIndex;
    final wasGaplessLoaded = _gaplessLoaded;
    final wasPlaying = _activePlayer.playing;

    _songs.removeAt(index);
    _queueDirty = true;

    if (_songs.isEmpty) {
      _currentIndex = 0;
      _gaplessLoaded = false;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    if (_gaplessMode) {
      if (wasPlayingCurrent) {
        // Removing the playing track changes the current song. Rebuild the
        // playlist at the clamped index so the new current starts cleanly,
        // rather than leaning on ExoPlayer's silent same-index auto-advance
        // (which would leave the notification and play history stale).
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        if (wasGaplessLoaded && _activePlayer.audioSources.isNotEmpty) {
          await _loadGaplessQueue(preload: wasPlaying);
        } else {
          final nextSong = _songs[_currentIndex];
          final fastArtUri = nextSong.artworkUri != null
              ? Uri.tryParse(nextSong.artworkUri!)
              : null;
          mediaItem.add(_songToMediaItem(nextSong, fastArtUri));
        }
      } else {
        if (index < _currentIndex) _currentIndex--;
        // Pre-set so the shift emit from currentIndexStream is a no-op.
        _lastGaplessIndex = _currentIndex;
        if (wasGaplessLoaded && index < _activePlayer.audioSources.length) {
          await _activePlayer.removeAudioSourceAt(index);
        }
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
      } else if (wasPlayingCurrent) {
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        if (wasPlaying) {
          await playSongAt(_currentIndex);
        } else {
          await _loadSongPaused(_currentIndex);
        }
      }
    }
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _songs.indexWhere((s) => s.id.toString() == mediaItem.id);
    if (index != -1) {
      await removeQueueItemAt(index);
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _songs.length ||
        newIndex < 0 ||
        newIndex > _songs.length) {
      return;
    }
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);
    _queueDirty = true;

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    // moveAudioSource() replays remove(oldIndex)+insert(newIndex) on the playlist's
    // layout, reaching the same order as _songs. Pre-set _lastGaplessIndex so a
    // shift emit for the (unchanged) current song is swallowed.
    if (_gaplessMode && _gaplessLoaded) {
      _lastGaplessIndex = _currentIndex;
      await _activePlayer.moveAudioSource(oldIndex, newIndex);
    }

    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  MediaItem _fastSongToMediaItem(SongsTableData song) {
    final artUri = song.artworkUri != null
        ? Uri.tryParse(song.artworkUri!)
        : (song.remoteArtworkUrl != null ? Uri.tryParse(song.remoteArtworkUrl!) : null);
    return _songToMediaItem(song, artUri);
  }

  Future<List<R>> _boundedParallelMap<T, R>(
    List<T> items,
    Future<R> Function(T) mapper, {
    int concurrency = 6,
  }) async {
    if (items.isEmpty) return <R>[];
    final results = List<R?>.filled(items.length, null);
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= items.length) break;
        results[i] = await mapper(items[i]);
      }
    }
    final workerCount = math.min(concurrency, items.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<R>();
  }

  // --- ANDROID AUTO / MEDIA BROWSER TREE ---
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.recentRootId:
      case 'root_recent':
        final recentRes = await _repository.getRecentlyPlayed();
        final list = recentRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      case 'root':
      case 'android_auto_root':
      case '/':
      case '':
        return [
          const MediaItem(
            id: 'songs',
            title: 'Songs',
            playable: false,
          ),
          const MediaItem(
            id: 'albums',
            title: 'Albums',
            playable: false,
          ),
          const MediaItem(
            id: 'artists',
            title: 'Artists',
            playable: false,
          ),
          const MediaItem(
            id: 'playlists',
            title: 'Playlists',
            playable: false,
          ),
          const MediaItem(
            id: 'genres',
            title: 'Genres',
            playable: false,
          ),
          const MediaItem(
            id: 'favorites',
            title: 'Favorites',
            playable: false,
          ),
          const MediaItem(
            id: 'recent',
            title: 'Recently Played',
            playable: false,
          ),
          if (AppConfig.ytmEnabled) ...[
            const MediaItem(
              id: 'ytm_trending',
              title: 'YouTube Music: Trending',
              playable: false,
            ),
            const MediaItem(
              id: 'ytm_favorites',
              title: 'YouTube Music: Liked',
              playable: false,
            ),
          ],
        ];

      case 'songs':
      case 'root_songs':
        final songsRes = await _repository.getAllSongs();
        final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      case 'albums':
      case 'root_albums':
        final albumsRes = await _repository.getAlbums();
        final list = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (album) async {
          final artUri = await ArtworkUriResolver.getAlbumArtUri(album.id);
          return MediaItem(
            id: 'album_${album.id}',
            title: album.title,
            artist: album.artist,
            playable: false,
            artUri: artUri,
          );
        });

      case 'artists':
      case 'root_artists':
        final artistsRes = await _repository.getArtists();
        final list = artistsRes.fold((l) => <ArtistsTableData>[], (r) => r);
        return await _boundedParallelMap(list, (artist) async {
          final artUri = await ArtworkUriResolver.getArtistArtUri(artist.id);
          return MediaItem(
            id: 'artist_${artist.id}',
            title: artist.name,
            artist: '${artist.songCount} songs',
            playable: false,
            artUri: artUri,
          );
        });

      case 'playlists':
      case 'root_playlists':
        final playlistsRes = await _repository.getPlaylists();
        final list = playlistsRes.fold((l) => <PlaylistsTableData>[], (r) => r);
        return list
            .map(
              (p) => MediaItem(
                id: 'playlist_${p.id}',
                title: p.name,
                playable: false,
              ),
            )
            .toList();

      case 'genres':
      case 'root_genres':
        final genresRes = await _repository.getGenres();
        final list = genresRes.fold((l) => <GenreItem>[], (r) => r);
        return list
            .map(
              (g) => MediaItem(
                id: 'genre_${g.name}',
                title: g.name,
                artist: '${g.songCount} songs',
                playable: false,
              ),
            )
            .toList();

      case 'favorites':
      case 'root_favorites':
        final favoritesRes = await _repository.getFavorites();
        final list = favoritesRes.fold((l) => <SongsTableData>[], (r) => r);
        return list.map(_fastSongToMediaItem).toList();

      default:
        if (parentMediaId.startsWith('album_')) {
          final albumId = int.tryParse(parentMediaId.substring(6));
          if (albumId == null) return [];
          final songsRes = await _repository.getAlbumSongs(albumId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('artist_')) {
          final artistId = int.tryParse(parentMediaId.substring(7));
          if (artistId == null) return [];
          final songsRes = await _repository.getArtistSongs(artistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('playlist_')) {
          final playlistId = int.tryParse(parentMediaId.substring(9));
          if (playlistId == null) return [];
          final songsRes = await _repository.getPlaylistSongs(playlistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId.startsWith('genre_')) {
          final genreName = parentMediaId.substring(6);
          if (genreName.isEmpty) return [];
          final songsRes = await _repository.getGenreSongs(genreName);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          return list.map(_fastSongToMediaItem).toList();
        }

        if (parentMediaId == 'ytm_trending') {
          if (!AppConfig.ytmEnabled) return [];
          try {
            final ytmTracks = await _ytmService.search('trending music');
            return ytmTracks.map((t) {
              final song = t.toSongData();
              return _songToMediaItem(song,
                  t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null);
            }).toList();
          } catch (_) {
            return [];
          }
        }

        if (parentMediaId == 'ytm_favorites') {
          if (!AppConfig.ytmEnabled) return [];
          try {
            final favRes = await _repository.getFavorites();
            final allFavs = favRes.fold((l) => <SongsTableData>[], (r) => r);
            final ytmFavs = allFavs
                .where((s) =>
                    s.source == SongSource.youtube ||
                    (s.remoteId != null && s.remoteId!.isNotEmpty))
                .toList();
            return ytmFavs.map(_fastSongToMediaItem).toList();
          } catch (_) {
            return [];
          }
        }

        return [];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final id = int.tryParse(mediaId);
    if (id == null) return null;
    final songRes = await _repository.getSongById(id);
    final match = songRes.fold((l) => null, (r) => r);
    if (match == null) return null;
    final artUri = await ArtworkUriResolver.resolveArtworkUri(match);
    return _songToMediaItem(match, artUri);
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    final queueIndex = _songs.indexWhere(
        (s) => s.id.toString() == mediaId || s.remoteId == mediaId);
    if (queueIndex != -1) {
      await loadQueue(_songs, initialIndex: queueIndex);
      return;
    }

    final songId = int.tryParse(mediaId);
    if (songId != null) {
      final songsRes = await _repository.getAllSongs();
      final loaded = songsRes.fold((l) => false, (songs) {
        final index = songs.indexWhere((s) => s.id == songId);
        if (index != -1) {
          loadQueue(songs, initialIndex: index);
          return true;
        }
        return false;
      });
      if (loaded) return;
    }

    if (extras != null &&
        (extras['remoteId'] != null ||
            extras['source'] == SongSource.youtube ||
            mediaId.length == 11)) {
      final remoteId = (extras['remoteId'] as String?) ?? mediaId;
      final uniqueNegativeId = -(remoteId.hashCode.abs() % 1000000000 + 1);
      final onlineSong = SongsTableData(
        id: songId ?? uniqueNegativeId,
        title: extras['title'] as String? ?? 'Unknown',
        artist: extras['artist'] as String? ?? 'Unknown Artist',
        album: extras['album'] as String? ?? '',
        durationMs: (extras['durationMs'] as int?) ?? 0,
        path: extras['path'] as String? ?? '',
        source: extras['source'] as String? ?? SongSource.youtube,
        remoteId: remoteId,
        remoteArtworkUrl: extras['remoteArtworkUrl'] as String?,
        isFavorite: false,
        isMissing: false,
        isDownloaded: false,
        playCount: 0,
        lastPositionMs: 0,
      );
      await loadQueue([onlineSong], initialIndex: 0);
      return;
    }

    if (mediaId.startsWith('album_')) {
      final albumId = int.tryParse(mediaId.substring(6));
      if (albumId != null) {
        final songsRes = await _repository.getAlbumSongs(albumId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('artist_')) {
      final artistId = int.tryParse(mediaId.substring(7));
      if (artistId != null) {
        final songsRes = await _repository.getArtistSongs(artistId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('playlist_')) {
      final playlistId = int.tryParse(mediaId.substring(9));
      if (playlistId != null) {
        final songsRes = await _repository.getPlaylistSongs(playlistId);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId.startsWith('genre_')) {
      final genreName = mediaId.substring(6);
      if (genreName.isNotEmpty) {
        final songsRes = await _repository.getGenreSongs(genreName);
        songsRes.fold((l) => null, (songs) {
          if (songs.isNotEmpty) loadQueue(songs);
        });
      }
      return;
    }

    if (mediaId == 'songs' || mediaId == 'root_songs') {
      final songsRes = await _repository.getAllSongs();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }

    if (mediaId == 'favorites' || mediaId == 'root_favorites') {
      final songsRes = await _repository.getFavorites();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }

    if (mediaId == 'recent' ||
        mediaId == 'root_recent' ||
        mediaId == AudioService.recentRootId) {
      // External controllers (media resumption chip, Assistant, Wear/Auto
      // reconnect) address the "recent" root to auto-play recently played
      // music. Honoring it while a user queue is actively playing silently
      // replaced the running queue — and the player-screen queue view — with
      // the 20 most recently played tracks. Only honor it when nothing is
      // playing.
      if (_songs.isNotEmpty && _activePlayer.playing) return;
      final songsRes = await _repository.getRecentlyPlayed();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }
  }

  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return [];
    // Use the indexed FTS search instead of materializing and linear-scanning
    // the entire library on every Android Auto query.
    final songsRes = await _repository
        .watchAllSongs(searchQuery: query.trim(), limit: 50)
        .first;
    final matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    final results = <MediaItem>[
      for (final song in matches) _fastSongToMediaItem(song),
    ];

    if (results.isEmpty && AppConfig.ytmEnabled) {
      try {
        final ytmTracks = await _ytmService.search(query.trim(), limit: 10);
        for (final t in ytmTracks) {
          final song = t.toSongData();
          final artUri =
              t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null;
          results.add(_songToMediaItem(song, artUri));
        }
      } catch (_) {}
    }

    return results;
  }

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return;
    final cleanQ = query.trim();
    // Indexed FTS search (title/artist/album) instead of a full-library scan.
    final songsRes = await _repository
        .watchAllSongs(searchQuery: cleanQ, limit: 50)
        .first;
    final matches = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    if (matches.isNotEmpty) {
      await loadQueue(matches);
      return;
    }

    // 5. Online YouTube Music Search fallback if enabled
    if (AppConfig.ytmEnabled) {
      try {
        final ytmTracks = await _ytmService.search(cleanQ, limit: 15);
        if (ytmTracks.isNotEmpty) {
          final songs = ytmTracks.map((t) => t.toSongData()).toList();
          await loadQueue(songs);
          return;
        }
      } catch (_) {}
    }
  }

  // ── F1–F11 public API ──────────────────────────────────────────────
  // F1: AB loop
  void setAbPointA(Duration pos) =>
      abLoopManager.setA(pos, songId: currentSong?.id);
  void setAbPointB(Duration pos) =>
      abLoopManager.setB(pos, songId: currentSong?.id);
  void toggleAbLoop() => abLoopManager.toggle();
  void clearAbLoop() => abLoopManager.clear();

  /// Re-restores the persisted AB loop for the current song. Used by the
  /// PlayerCubit to sync loop UI after a track change completes.
  Future<void> restoreAbLoopForCurrentSong() async {
    final song = currentSong;
    if (song == null) return;
    await abLoopManager.restoreForSong(song.id);
  }

  // F2: per-track delay
  String? get _currentTrackKey {
    final s = currentSong;
    if (s == null) return null;
    return TrackDelayManager.keyFor(
        songId: s.id, remoteId: s.remoteId, path: s.path);
  }

  int get currentTrackDelayMs =>
      _currentTrackKey == null ? 0 : trackDelayManager.getDelayMs(_currentTrackKey!);
  Duration get delayCompensatedPosition {
    final key = _currentTrackKey;
    return trackDelayManager.compensatedPosition(key, _activePlayer.position);
  }

  Future<void> setCurrentTrackDelay(int ms) async {
    final key = _currentTrackKey;
    if (key == null) return;
    trackDelayManager.setDelay(key, ms);
    await trackDelayManager.persist();
  }

  Future<void> setTrackDelayFor(String key, int ms) async {
    trackDelayManager.setDelay(key, ms);
    await trackDelayManager.persist();
  }

  // F3: hedged resolution toggle
  Future<void> setHedgedResolutionEnabled(bool v) async {
    hedgedResolutionEnabled = v;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('hedged_resolution_enabled', v);
  }

  // F4: adaptive quality
  Future<void> setAdaptiveQualityEnabled(bool v) async {
    adaptiveQualityManager.enabled = v;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setBool('adaptive_quality_enabled', v);
  }

  Future<void> _maybeAdaptiveStepDown() async {
    if (!adaptiveQualityManager.enabled) return;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    final current = prefs.getString('setting_streaming_quality') ?? 'high';
    adaptiveQualityManager.setQuality(current);
    final next = await adaptiveQualityManager.reportUnderrun();
    if (next != null) await _applyAdaptiveQuality(next);
  }

  Future<void> _maybeAdaptiveStepUp() async {
    if (!adaptiveQualityManager.enabled) return;
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    final current = prefs.getString('setting_streaming_quality') ?? 'high';
    // Only step up toward the user's chosen ceiling.
    if (qualityRank(current) >= qualityRank(adaptiveQualityManager.currentQuality)) {
      adaptiveQualityManager.setQuality(current);
    }
    final next = await adaptiveQualityManager.reportHealthy();
    if (next != null &&
        qualityRank(next) <= qualityRank(current)) {
      await _applyAdaptiveQuality(next);
    }
  }

  Future<void> _applyAdaptiveQuality(String newQuality) async {
    // A quality step-down landing mid-crossfade/gapless load would clobber the
    // player that is already transitioning; skip this cycle and let the next
    // health tick retry.
    if (_crossfadeManager.isCrossfading) return;
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString('setting_streaming_quality', newQuality);
      final song = currentSong;
      if (song != null &&
          song.source == SongSource.youtube &&
          (song.remoteId?.isNotEmpty ?? false)) {
        _streamCache.removeWhere((k, _) => k.startsWith(song.remoteId!));
        _streamResolutionPipeline.invalidateCache(song.remoteId!);
        // Hot-swap mid-track: re-resolve at new quality, keep position.
        final pos = _activePlayer.position;
        final wasPlaying = _activePlayer.playing;
        final generation = ++_playGeneration;
        try {
          final resolved = await _resolveStreamUrl(song, forceRefresh: true);
          // Bail if the track/queue changed while we re-resolved.
          if (generation != _playGeneration ||
              currentSong?.id != song.id ||
              _crossfadeManager.isCrossfading) {
            return;
          }
          final tag = _songToMediaItem(song);
          final src = AudioSource.uri(Uri.parse(resolved.url), tag: tag);
          await _activePlayer.setAudioSource(src, initialPosition: pos);
          if (wasPlaying) unawaited(_activePlayer.play());
        } catch (_) {}
      }
    } catch (_) {}
  }

  // F5: BT latency auto-calibration helper (codec table lives in service;
  // handler applies the result to prefs).
  Future<int> applyBtLatencyOffset(int ms) async {
    final clamped = ms.clamp(0, 500);
    final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
    await prefs.setInt(PrefsKeys.bluetoothLatencyOffsetMs, clamped);
    return clamped;
  }

  // F6: gapless trim lookup for a song.
  GaplessTrim gaplessTrimFor(SongsTableData song) =>
      GaplessTrimHandler.trimFor(path: song.path, codec: song.codec);

  // F7: ducking control
  Future<void> setDuckingMode(String modeName) async {
    duckingController.setMode(DuckingController.parseMode(modeName));
    await duckingController.persist();
  }

  Future<void> setDuckingLevel(double level) async {
    duckingController.setLevel(level);
    await duckingController.persist();
  }

  // F8: multi-output routing
  Future<bool> setMultiOutputMode(MultiOutputMode mode) =>
      multiOutputRouter.setMode(mode);

  // F9: DSP snapshots
  Future<void> saveDspSnapshotForCurrent() async {
    final s = currentSong;
    if (s == null) return;
    dspSnapshotStore.save(
      DspSnapshotStore.albumKey(s.album, s.artist),
      DspSnapshot(
        presetName: _equalizerManager.currentPreset.name,
        gains: List<double>.from(_equalizerManager.currentPreset.gains),
        volumeBoost: _equalizerManager.volumeBoost,
        savedAt: DateTime.now(),
      ),
    );
    await dspSnapshotStore.persist();
  }

  Future<bool> recallDspSnapshotFor(SongsTableData song) async {
    final snap = dspSnapshotStore.recallFor(
        album: song.album, artist: song.artist, genre: song.genre);
    if (snap == null) return false;
    try {
      await _equalizerManager.applyPreset(
          EqPreset(name: snap.presetName, gains: snap.gains));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setDspSnapshotEnabled(bool v) async {
    dspSnapshotStore.enabled = v;
    await dspSnapshotStore.persist();
  }

  // F10: silence-skip sensitivity. Native ExoPlayer stage is boolean-only,
  // so sensitivity is persisted and exposed via thresholdDb/minSilenceDuration
  // for UI truthfulness and future native thresholds; enabling still toggles
  // the native boolean stage.
  Future<void> setSilenceSkipSensitivity(int v) async {
    silenceSkipController.setSensitivity(v);
    try {
      await _playerA.setSkipSilenceEnabled(silenceSkipController.enabled);
      await _playerB.setSkipSilenceEnabled(silenceSkipController.enabled);
    } catch (_) {}
    await silenceSkipController.persist();
  }

  double get silenceSkipThresholdDb => silenceSkipController.thresholdDb;
  Duration get silenceSkipMinDuration => silenceSkipController.minSilenceDuration;

  // F11: bookmarks
  PlaybackBookmark? recallBookmarkFor(SongsTableData song) {
    final key = PlaybackBookmarkStore.keyFor(
        songId: song.id, remoteId: song.remoteId, path: song.path);
    return bookmarkStore.recall(key);
  }

  Future<void> clearBookmarkFor(SongsTableData song) async {
    final key = PlaybackBookmarkStore.keyFor(
        songId: song.id, remoteId: song.remoteId, path: song.path);
    bookmarkStore.remove(key);
    await bookmarkStore.persist();
  }

  Future<void> persistBookmarks() => bookmarkStore.persist();

  final Completer<void> _effectsReadyCompleter = Completer<void>();

  /// Completes when the handler's async init (effects/equalizer preference
  /// restore) has finished, so listeners can re-sync effect state that was
  /// read before the restore completed.
  Future<void> get effectsReady => _effectsReadyCompleter.future;

  bool get isSaturationEnabled => _equalizerManager.isSaturationEnabled;
  double get saturationDrive => _equalizerManager.saturationDrive;
  double get saturationMix => _equalizerManager.saturationMix;
  double get saturationTilt => _equalizerManager.saturationTilt;
  bool get saturationMultiband => _equalizerManager.saturationMultiband;
  Future<void> setSaturation(
    bool enabled, {
    double? drive,
    double? mix,
    double? tilt,
    int? mode,
    bool? multiband,
  }) =>
      _equalizerManager.setSaturation(
        enabled,
        drive: drive,
        mix: mix,
        tilt: tilt,
        mode: mode,
        multiband: multiband,
      );
  Future<void> setSaturationMultiband(bool multiband) =>
      _equalizerManager.setSaturationMultiband(multiband);
  bool get isStereoWidthEnabled => _equalizerManager.isStereoWidthEnabled;
  double get stereoWidth => _equalizerManager.stereoWidth;
  Future<void> setStereoWidth(
    bool enabled, {
    double? width,
    bool? multiband,
    double? lowWidth,
    double? midWidth,
    double? highWidth,
    double? lowCrossoverHz,
    double? highCrossoverHz,
  }) =>
      _equalizerManager.setStereoWidth(
        enabled,
        width: width,
        multiband: multiband,
        lowWidth: lowWidth,
        midWidth: midWidth,
        highWidth: highWidth,
        lowCrossoverHz: lowCrossoverHz,
        highCrossoverHz: highCrossoverHz,
      );
  bool get isLoudnessContourEnabled =>
      _equalizerManager.isLoudnessContourEnabled;
  double get loudnessContourIntensity =>
      _equalizerManager.loudnessContourIntensity;
  Future<void> setLoudnessContour(bool enabled, {double? intensity}) =>
      _equalizerManager.setLoudnessContour(enabled, intensity: intensity);
  bool get isSubCrossoverEnabled => _equalizerManager.isSubCrossoverEnabled;
  double get subCrossoverCornerHz => _equalizerManager.subCrossoverCornerHz;
  double get subCrossoverSlopeDbPerOct =>
      _equalizerManager.subCrossoverSlopeDbPerOct;
  double get subCrossoverGain => _equalizerManager.subCrossoverGain;
  Future<void> setSubCrossover(
    bool enabled, {
    double? cornerHz,
    double? slopeDbPerOct,
    double? gain,
    bool? bassMono,
    bool? antiPop,
  }) =>
      _equalizerManager.setSubCrossover(
        enabled,
        cornerHz: cornerHz,
        slopeDbPerOct: slopeDbPerOct,
        gain: gain,
        bassMono: bassMono,
        antiPop: antiPop,
      );
  bool get isDynamicEqEnabled => _equalizerManager.isDynamicEqEnabled;
  List<DynamicEqBandConfig> get dynamicEqBands =>
      _equalizerManager.dynamicEqBands;
  Future<void> setDynamicEq(bool enabled) =>
      _equalizerManager.setDynamicEq(enabled);
  Future<void> setDynamicEqBand(int index, DynamicEqBandConfig band) =>
      _equalizerManager.setDynamicEqBand(index, band);
      
  Future<void> addDynamicEqBand() => _equalizerManager.addDynamicEqBand();
  
  Future<void> removeDynamicEqBand(int index) => _equalizerManager.removeDynamicEqBand(index);

  bool get isViperDdcEnabled => _equalizerManager.isViperDdcEnabled;
  String get viperDdcProfileName => _equalizerManager.viperDdcProfileName;
  Future<void> setViperDdc(bool enabled,
          {String? profileName, List<double>? coeffs, String? ddcContent}) =>
      _equalizerManager.setViperDdc(enabled,
          profileName: profileName, coeffs: coeffs, ddcContent: ddcContent);

  bool get isArbitraryEqEnabled => _equalizerManager.isArbitraryEqEnabled;
  String get arbitraryEqString => _equalizerManager.arbitraryEqString;
  Future<void> setArbitraryEq(bool enabled, {String? eqString}) =>
      _equalizerManager.setArbitraryEq(enabled, eqString: eqString);

  bool get isLiveProgEnabled => _equalizerManager.isLiveProgEnabled;
  String get liveProgCode => _equalizerManager.liveProgCode;
  Future<void> setLiveProg(bool enabled, {String? code}) =>
      _equalizerManager.setLiveProg(enabled, code: code);
  Future<void> setLiveProgSlider(int sliderIndex, double value) =>
      _equalizerManager.setLiveProgSlider(sliderIndex, value);

  bool get isDynamicBassEnabled => _equalizerManager.isDynamicBassEnabled;
  double get dynamicBassStrength => _equalizerManager.dynamicBassStrength;
  int get dynamicBassPreset => _equalizerManager.dynamicBassPreset;
  Future<void> setDynamicBass({
    required bool enabled,
    double? strength,
    int? preset,
    int? xLow,
    int? xHigh,
    int? yLow,
    int? yHigh,
    double? sideGainLow,
    double? sideGainHigh,
  }) =>
      _equalizerManager.setDynamicBass(
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

  @override
  Future<void> stop() async {
    _sleepTimerManager.cancelSleepTimer();
    unawaited(AudioSessionLog.instance.endSession());
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    _saveCurrentPosition();
    await _playerA.stop();
    await _playerB.stop();
    await AudioEffectsChannel().releaseEffects();
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await saveCurrentPositionImmediate();
    // Route through the public pause path so it performs the same cleanup as a
    // user pause: reset the interruption bookkeeping, cancel any crossfade and
    // bump the play generation so a slow in-flight resolve cannot start
    // playback after the task is gone (B-3).
    try {
      await pause();
    } catch (_) {}
    await super.onTaskRemoved();
  }

  @disposeMethod
  Future<void> dispose() async {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _fadeInGuardTimer?.cancel(); // FIX-#12
    _fadeInGuardTimer = null;
    _crossfadeSwitchDebounce?.cancel();
    _crossfadeSwitchDebounce = null;
    for (final sub in List.of(_subscriptions)) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();
    // Dispose sleep timer before closing its subject to avoid add-after-close race
    _sleepTimerManager.dispose();
    try {
      abLoopManager.dispose();
    } catch (_) {}
    try {
      multiOutputRouter.dispose();
    } catch (_) {}
    try {
      await silenceSkipController.persist();
    } catch (_) {}
    // Guarded: dispose() can run before the async _init() assigned this late
    // field (hot restart / test teardown / early init failure).
    try {
      _streamPreResolver.dispose();
    } catch (_) {}
    try {
      _preloadScheduler.clear();
    } catch (_) {}
    try {
      _adaptiveBufferEngine.dispose();
    } catch (_) {}
    try {
      _memoryManager.clearAll();
    } catch (_) {}
    if (!_positionSubject.isClosed) _positionSubject.close();
    if (!_highRatePositionSubject.isClosed) _highRatePositionSubject.close();
    if (!_audioSessionIdSubject.isClosed) _audioSessionIdSubject.close();
    if (!_errorSubject.isClosed) _errorSubject.close();
    if (!_onTrackChangedSubject.isClosed) _onTrackChangedSubject.close();
    _equalizerManager.dispose();
    _crossfadeManager.dispose();
    try {
      await AudioEffectsChannel().releaseEffects();
    } catch (_) {}
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    await _playerA.dispose();
    await _playerB.dispose();
    await _prefetchPlayer.dispose();
    platformBridgeDegraded.dispose();
  }
}
