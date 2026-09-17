// ignore_for_file: unused_field
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
import '../../domain/models/audio_quality_info.dart';
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
import 'headset_control_config.dart';
part 'audio_handler_dsp_bridge.dart';
part 'audio_handler_sleep_bridge.dart';
part 'audio_handler_streaming.dart';
part 'audio_handler_queue_engine.dart';
part 'audio_handler_transport.dart';
part 'audio_handler_media_browser.dart';
part 'audio_handler_playback_extras.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler, PulsrAudioDspBridge, PulsrAudioSleepBridge, PulsrAudioStreaming, PulsrAudioQueueEngine, PulsrAudioTransport, PulsrAudioMediaBrowser, PulsrAudioPlaybackExtras {
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
    // User preference: keep the media notification after pause so playback
    // can be resumed from the shade. AudioServiceConfig is init-time only,
    // so this takes effect on the next cold start after the toggle changes.
    // Default TRUE: a paused player must keep its notification (standard
    // music-player behavior). With stopForegroundOnPause=true the OS drops
    // the notification on every pause — including end-of-queue Next — which
    // users report as "notification disappearing with no action".
    bool keepOnPause = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      keepOnPause = prefs.getBool(PrefsKeys.keepNotificationOnPause) ?? true;
    } catch (_) {}
    try {
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
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.pulsr.music.audio',
          androidNotificationChannelName: 'Pulsr Audio Playback',
          androidNotificationChannelDescription:
              'Playback controls and now-playing information for Pulsr Music.',
          androidNotificationOngoing: false,
          androidNotificationClickStartsActivity: true,
          androidStopForegroundOnPause: !keepOnPause,
          androidResumeOnClick: true,
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
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

  @override
  final AudioPlayer _playerA;
  @override
  final AudioPlayer _playerB;
  @override
  final AudioPlayer _prefetchPlayer;
  @override
  bool _isPlayerAActive = true;
  @override
  int _generationCounter = 0;
  int get generationCounter => _generationCounter;
  @override
  AudioPlayer get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  @override
  AudioPlayer get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;
  AudioPlayer get prefetchPlayer => _prefetchPlayer;

  /// Returns playback position compensated for native and DSP pipeline latency.
  @override
  Duration get compensatedPosition =>
      _dspPipeline.getCompensatedPosition(_activePlayer.position);

  @override
  final IMusicRepository _repository;
  @override
  final YtmService _ytmService;
  @override
  final CrossfadeManager _crossfadeManager = CrossfadeManager();
  @override
  final SleepTimerManager _sleepTimerManager = SleepTimerManager();
  @override
  late final EqualizerManager _equalizerManager;
  @override
  late final AudioSessionIdRouter _audioSessionIdRouter;
  @override
  int? _playerASessionId;
  @override
  int? _playerBSessionId;

  @override
  List<SongsTableData> _songs = [];
  @override
  int _currentIndex = 0;
  @override
  bool _queueDirty = false;

  /// Index last written to the persisted queue. Compared against [_currentIndex]
  /// on the periodic flush so a skip refreshes the cold-resume row even though
  /// the queue structure did not change.
  int _savedQueueIndex = -1;
  double? _preDuckVolume;
  double? _preDuckInactiveVolume;
  @override
  bool _duckActive = false;
  int _duckDepthCounter = 0;
  /// Pure, testable interruption bookkeeping (B-1). Replaces the previous pair
  /// of loose booleans whose begin/end bookkeeping was asymmetric.
  @override
  final InterruptionStateMachine _interruption = InterruptionStateMachine();
  DateTime? _lastNoisyTime;
  // Auto-resume bookkeeping: a becoming-noisy pause arms a one-shot resume
  // window; a reconnect on a headset/BT/USB route within the timeout resumes.
  DateTime? _noisyPauseTime;
  bool _pausedForNoisy = false;
  @override
  int _consecutiveFailures = 0;
  @override
  DateTime? _lastGaplessChangeTime;
  @override
  int _rapidGaplessChangeCount = 0;
  // Last time a track-completion was reported to the sleep timer. Gapless
  // playback reports one boundary through two independent signals (the native
  // `ProcessingState.completed` event and the `currentIndexStream` advance), so
  // this debounce collapses the duplicate. See [_notifySleepTrackCompleted].
  @override
  DateTime? _lastSleepTrackCompletedAt;
  @override
  final List<int> _shuffleHistory = [];
  @override
  DateTime? _lastPreviousTapTime;
  @override
  bool _isManualSkip = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  @override
  int _playGeneration = 0;
  // Seek throttling: optimistic UI + debounced backend seeks.
  @override
  int _lastSeekMs = 0;
  @override
  Duration? _pendingSeekPosition;
  @override
  Timer? _seekDebounceTimer;
  @override
  int _lastSmartPrefetchMs = 0;
  @override
  String? _lastSmartPrefetchKey;
  @override
  Timer? _crossfadeSwitchDebounce;
  AudioHandlerLifecycleObserver? _lifecycleObserver;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  @override
  Duration? _pendingLazyPosition;
  // Memoized stream URLs, keyed by video id. Never persisted — they expire.
  @override
  final LinkedHashMap<String,
          ({String url, DateTime expires, String? userAgent, String? cookies})>
      _streamCache = LinkedHashMap();
  // Active stream URL resolutions, keyed by videoId-quality. Deduplicates concurrent
  // requests (e.g. background pre-warm and YtmResolvingSource.request()).
  @override
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
  @override
  final Set<String> _prefetching = {};

  @override
  String _currentStreamingQuality() =>
      _cachedPrefs?.getString('setting_streaming_quality') ?? 'high';

  @override
  final AdaptiveBufferEngine _adaptiveBufferEngine = AdaptiveBufferEngine();
  final OptimizedDspPipeline _dspPipeline = OptimizedDspPipeline();
  late final PlaybackAnalytics _playbackAnalytics;
  @override
  late final AudioMemoryManager _memoryManager;
  @override
  late final SmartPreloadScheduler _preloadScheduler;
  @override
  late final FormatAwareDecoder _formatDecoder;
  @override
  late final TripleBufferPipeline _tripleBufferPipeline;
  @override
  late final BatteryAwarePlayback _batteryAwarePlayback;
  @override
  late final StreamPreResolver _streamPreResolver;
  late final PlaybackVolumeController _volumeController;
  /// Set once [_volumeController] has been assigned in the (async) init. The
  /// settings cubit can emit — and call setVolume() — before that happens on a
  /// cold start, which used to throw a LateInitializationError on every launch.
  bool _volumeControllerReady = false;
  @override
  late final StreamResolutionPipeline _streamResolutionPipeline;
  // ── F1–F11 feature managers ──────────────────────────────────────────
  @override
  final AbLoopManager abLoopManager = AbLoopManager();
  @override
  final TrackDelayManager trackDelayManager = TrackDelayManager();
  @override
  final AdaptiveQualityManager adaptiveQualityManager =
      AdaptiveQualityManager();
  @override
  final DuckingController duckingController = DuckingController();
  @override
  final MultiOutputRouter multiOutputRouter = MultiOutputRouter();  @override
  final DspSnapshotStore dspSnapshotStore = DspSnapshotStore();
  @override
  final SilenceSkipController silenceSkipController = SilenceSkipController();
  @override
  final BpmOverrideStore bpmOverrideStore = BpmOverrideStore();
  @override
  final PlaybackBookmarkStore bookmarkStore = PlaybackBookmarkStore();
  @override
  bool hedgedResolutionEnabled = true;
  DateTime? _lastBookmarkSave;
  DateTime? _lastHealthyReport;

  // Gapless engine: when crossfade is off, AudioPlayer's built-in playlist on the
  // active player is the source of truth for track order/advance, and just_audio
  // joins consecutive items seamlessly. False while crossfade (duration > 0) is
  // active, which keeps the manual dual-player path below.
  @override
  bool _gaplessLoaded = false;
  // Last index reacted to from currentIndexStream, to drop duplicate emits.
  @override
  int _lastGaplessIndex = -1;

  // Guard against session restoration stomping over user-initiated playback on cold start
  @override
  bool _userPlaybackInitiated = false;
  // Target index for current gapless load; used to filter transient ExoPlayer index 0 emits
  @override
  int? _gaplessTargetIndex;
  @override
  DateTime? _gaplessLoadTime;
  @override
  bool _gaplessTargetReached = false;

  /// User-facing gapless toggle (persisted as `setting_gapless`). Gapless is
  /// the default engine but is mutually exclusive with crossfade.
  @override
  bool _gaplessEnabled = true;
  bool get isGaplessEnabled => _gaplessEnabled;

  /// Gapless is the default engine. Enabling crossfade (duration > 0) switches
  /// to the overlapping dual-player engine, which cannot also produce a seamless
  /// join, so the two are mutually exclusive by construction. An explicit
  /// gapless OFF also falls back to per-track playback when crossfade is 0.
  @override
  bool get _gaplessMode =>
      _gaplessEnabled && _crossfadeManager.duration <= Duration.zero;

  @override
  final StreamController<SongsTableData> _onTrackChangedSubject =
      StreamController<SongsTableData>.broadcast();
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedSubject.stream;
  @override
  SongsTableData? _lastPlayedSong;

  // T10: CUE sub-track boundaries. Both flags reset on track change so each
  // virtual track seeks once to its start and advances once at its end.
  @override
  bool _cueStartSeeked = false;
  bool _cueAdvanceTriggered = false;

  bool _positionDirty = false;
  Timer? _positionSaveTimer;
  @override
  Timer? _fadeInGuardTimer; // FIX-#12: tracked for disposal
  @override
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

  @override
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
  @override
  SongsTableData? get currentSong =>
      (_songs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _songs.length)
          ? _songs[_currentIndex]
          : null;

  @override
  PlaybackLatencyTracker? get _latencyTracker =>
      getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null;
  int _lastPositionEmitMs = 0;
  @override
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

  /// One-shot auto-resume after a becoming-noisy pause.
  /// Fires only when the user opted in, the pause was noisy-triggered, the
  /// timeout has not elapsed, the player is still paused, and the new route
  /// is a headset-like output (BT / wired / USB / HDMI).
  Future<void> _maybeAutoResumeOnReconnect() async {
    if (!_pausedForNoisy) return;
    try {
      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      if (!(prefs.getBool(PrefsKeys.autoResumeOnReconnect) ?? false)) {
        _pausedForNoisy = false;
        return;
      }
      final timeoutSec = prefs.getInt(PrefsKeys.autoResumeTimeoutSec) ?? 90;
      final pausedAt = _noisyPauseTime;
      if (pausedAt == null ||
          DateTime.now().difference(pausedAt).inSeconds > timeoutSec) {
        _pausedForNoisy = false;
        return;
      }
      if (_activePlayer.playing || _songs.isEmpty) {
        _pausedForNoisy = false;
        return;
      }
      final info = getIt.isRegistered<HiResAudioService>()
          ? getIt<HiResAudioService>().currentOutputInfo
          : null;
      if (info == null) return;
      final type = info.activeDeviceType.trim().toLowerCase();
      final isHeadsetLike = info.isBluetooth ||
          info.isUsbDac ||
          type == 'wired' ||
          type == 'wired_headset' ||
          type == 'headset' ||
          type == 'usb' ||
          type == 'aux' ||
          type == 'line_out' ||
          type == 'hdmi' ||
          type == 'hearing_aid' ||
          type == 'ble';
      if (!isHeadsetLike) return;
      _pausedForNoisy = false;
      await play();
    } catch (_) {
      _pausedForNoisy = false;
    }
  }

  // ── Per-session audio telemetry (pure Dart, best-effort) ───────────────
  // One record per playback session: route/codec/negotiated format plus any
  // route change, interruption and underrun/dropout count. Every call is
  // fire-and-forget; the service never throws and is a no-op when disabled.

  @override
  Future<AudioOutputInfo?> _currentOutputInfo() async {
    try {
      if (!getIt.isRegistered<HiResAudioService>()) return null;
      return await getIt<HiResAudioService>().getAudioOutputInfo();
    } catch (_) {
      return null;
    }
  }

  @override
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

  @override
  SharedPreferences? _cachedPrefs;

  Future<void> _initPrefs() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }

  @override
  double _volume = 1.0;
  double get volume => _volume;

  /// Direct Volume Control: when true the composed gain is applied in the
  /// native float DSP path and player volume stays at unity.
  bool _dvcEnabled = false;
  bool get isDvcEnabled => _dvcEnabled;

  /// True when the native DSP ReplayGain pre-gain stage is carrying the
  /// current track's gain (bit-transparent, 20ms-smoothed, clipping-safe).
  /// When true the Dart mixer carries only user volume + per-song offset so
  /// the same gain is never applied twice. Falls back to false on non-Android,
  /// bit-perfect bypass, DoP, or native-bridge failure (Dart math then owns RG).
  bool _nativeRgActive = false;
  bool get isNativeRgActive => _nativeRgActive;

  /// Assumed Android mixer rate until the real output rate is known. The HAL
  /// only reports it after the first AudioTrack opens, so cold-start DSP
  /// coefficient init uses this; per-track [AudioEffectsChannel.resyncForTrack]
  /// in [_notifyTrackChanged] corrects it once real header rates arrive.
  static const double assumedOutputSampleRate = 48000.0;

  @override
  double _calculateReplayGainVolume(SongsTableData? song) {
    // DoP carries raw DSD inside PCM markers: any software gain corrupts the
    // 0x05/0xFA framing into white noise, so the mixer stays at unity and the
    // user volume is hardware-only. This also covers the crossfade/duck paths.
    if (AudioQualityInfo.dsdDopActive) {
      // Guarded by readiness (no catch): the controller is late-initialized
      // and must never throw past this point.
      if (_volumeControllerReady) _volumeController.setDopActive(true);
      return 1.0;
    }
    if (_volumeControllerReady) _volumeController.setDopActive(false);
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

    // Native pre-gain owns RG: mixer carries only user volume + per-song
    // offset (bit-transparent, 20ms-smoothed natively, no double-apply).
    if (_nativeRgActive && Platform.isAndroid) {
      var base = _volume;
      // _perSongVolumeDbFor is total (returns 0.0 on any lookup failure),
      // so no catch is needed here.
      final perSongDb = _perSongVolumeDbFor(song);
      if (perSongDb != 0.0) {
        base = (base * math.pow(10, perSongDb / 20).toDouble()).clamp(0.0, 1.0);
      }
      if (_dvcEnabled) {
        if (song.id == currentSong?.id) {
          unawaited(_pushDvcGain(_volume));
        }
        return base == _volume ? 1.0 : base;
      }
      return base;
    }

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

  /// Pushes ReplayGain tags to the native DSP pre-gain stage (bit-transparent,
  /// 20ms-smoothed, clipping-safe). On success [_nativeRgActive] is set so
  /// [_calculateReplayGainVolume] skips the Dart RG math (no double-apply):
  /// native owns RG, Dart mixer owns user volume + per-song offset.
  /// Falls back to Dart math on non-Android, bit-perfect bypass, DoP, mode
  /// off, or bridge failure — the mixer then applies RG as before.
  void _syncNativeRgFlag() {
    // Early return keeps the late-initialized controller access throw-free,
    // so this stays catch-free by construction.
    if (!_volumeControllerReady) return;
    _volumeController.setNativeRgActive(_nativeRgActive);
  }

  @override
  Future<void> _pushNativeReplayGain(SongsTableData? song) async {
    Future<void> disableNative() async {
      _nativeRgActive = false;
      _syncNativeRgFlag();
      try {
        await AudioEffectsChannel().setReplayGainEnabled(false);
      } catch (e, st) {
        ErrorLogger.log(
          'Failed to disable native ReplayGain stage',
          error: e,
          stackTrace: st,
          category: 'PulsrAudioHandler',
        );
      }
    }

    if (!Platform.isAndroid) {
      _nativeRgActive = false;
      _syncNativeRgFlag();
      return;
    }
    if (AudioQualityInfo.dsdDopActive) {
      await disableNative();
      return;
    }
    final prefs = _cachedPrefs;
    if (prefs == null || song == null) {
      await disableNative();
      return;
    }
    final bitPerfect = (prefs.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
        (prefs.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true);
    if (bitPerfect) {
      await disableNative();
      return;
    }
    final mode = prefs.getString(PrefsKeys.replayGainMode) ?? 'track';
    if (mode == 'off') {
      await disableNative();
      return;
    }
    try {
      final albumContext = _isConsecutiveAlbumPlayback();
      final applied = await AudioEffectsChannel().setReplayGainParams(
        mode: ReplayGainMath.nativeModeFor(mode, albumContext: albumContext),
        trackGainDb: song.replayGainTrack ?? 0.0,
        albumGainDb: song.replayGainAlbum ?? 0.0,
        trackPeak: song.replayGainTrackPeak ?? 1.0,
        albumPeak: song.replayGainAlbumPeak ?? 1.0,
        preAmpDb: ReplayGainMath.nativePreAmpFor(
          mode: mode,
          trackGainDb: song.replayGainTrack,
          albumGainDb: song.replayGainAlbum,
          albumContext: albumContext,
          preampWithRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
          preampWithoutRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? 0.0,
        ),
        preventClipping: true,
        enabled: true,
      );
      _nativeRgActive = applied;
      _syncNativeRgFlag();
      if (!applied) {
        await AudioEffectsChannel().setReplayGainEnabled(false);
      }
    } catch (_) {
      _nativeRgActive = false;
      _syncNativeRgFlag();
    }
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


  @override
  int _engineSwitchGeneration = 0;


  /// Whether a completion report at [now] is distinct from a previous one at
  /// [last]. Split out so the debounce window is unit-testable.
  @visibleForTesting
  static bool isDistinctSleepCompletion(DateTime? last, DateTime now) =>
      last == null ||
      now.difference(last) >= const Duration(milliseconds: 1500);


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
      if (_queueDirty || _currentIndex != _savedQueueIndex) {
        await _repository.saveQueue(
            _songs.map((s) => s.id).toList(), _currentIndex, posMs);
        _queueDirty = false;
        _savedQueueIndex = _currentIndex;
      } else {
        // Same track, later position: refresh just the current row so a cold
        // resume restores where the user actually was, not the position from
        // the last structural queue edit (skipToNext never dirtied the queue).
        await _repository.updateQueuePosition(posMs);
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

  @override
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
    // Restore persisted playback speed/pitch and the extended speed range so a
    // saved out-of-range speed is not silently clamped to 0.25–4.0 on cold start.
    await restorePersistedSpeed();

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
                      notifySleepTrackCompleted();
                      unawaited(_sleepTimerManager.onQueueCompleted());
                    }
                  }
                } else {
                  notifySleepTrackCompleted();
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
                _duckDepthCounter++;
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
                if (_duckDepthCounter > 0) _duckDepthCounter--;
                if (_duckActive && _duckDepthCounter == 0) {
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
                  // The correct ReplayGain-compensated target was applied above.
                  // Do NOT recompute through _volumeController.setDucked(): that
                  // path uses the controller's own ReplayGain mode/preamps, which
                  // this handler never feeds, so it would overwrite the target
                  // with raw duck-only user volume on every duck end.
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
                _duckDepthCounter = 0;
                break;
              case AudioInterruptionType.unknown:
                _interruption.reset();
                _preDuckVolume = null;
                _preDuckInactiveVolume = null;
                _duckActive = false;
                _duckDepthCounter = 0;
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
          // Arm the auto-resume window before pausing so a quick reconnect
          // can pick up where the unplug interrupted.
          _noisyPauseTime = now;
          _pausedForNoisy = true;
          await pause();
        }),
      );

      _subscriptions.add(
        session.devicesStream.listen((devices) {
          _syncBluetoothRouteFromCache();
          _audioSessionIdRouter.handleRouteChanged();
          unawaited(_refreshBluetoothRoute());
          unawaited(_recordSessionRouteChange());
          unawaited(_maybeAutoResumeOnReconnect());
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

  @override
  BufferBucket _currentBucket = BufferBucket.standard;


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

  @override
  AudioLoadConfiguration _currentAudioLoadConfiguration =
      _loadConfigForBucket(BufferBucket.standard);


  /// True for absolute HTTP(S) stream URLs (internet radio / Icecast /
  /// Shoutcast / HLS). These bypass the file/format-aware path entirely.
  static bool _isStreamUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');


  /// Builds a gapless-queue child for [song] with no network I/O, so an entire
  /// queue can be assembled up front. Local tracks resolve to a file/content
  /// source; a YouTube row (not yet downloaded) becomes a [YtmResolvingSource]
  /// that resolves its URL and caches its bytes lazily on first playback. A
  /// downloaded YouTube row with a real file on disk plays straight off disk.
  @override
  final Map<String, bool> _pathExistsCache = {};
  static const _maxPathCacheSize = 2000;


  /// Returns a currently-valid stream URL for a YouTube row, reusing a memoized
  /// one until it nears expiry. Throws [YtmException] when nothing usable comes
  /// back, so the caller can tell "network down" from "skip this track".
  ///
  /// [quality] is reported back because it is part of every downstream cache key
  /// ([YtmUrlCache], the disk cache slot); the caller cannot assume `high`.
  @override
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


  static const int _maxStreamCacheEntries = 64;


  @override
  int _prefetchGeneration = 0;


  /// Track key shared with the per-song stores (id-based).
  static String trackKeyFor(SongsTableData song) => song.id.toString();


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


  // --- PLAYBACK ACTIONS ---
  @override

  @override

  @override


  @override

  @override

  @override

  @override

  @override

  // --- ANDROID AUTO & HEADSET BUTTON SUPPORT ---
  Timer? _headsetClickTimer;
  @override
  int _headsetClickCount = 0;

  /// Headset hook button with user-configurable mapping (see
  /// HeadsetControlConfig). 1x/2x/3x clicks resolve after [clickWindowMs];
  /// 3+ clicks collapse to the triple action so fast multi-presses never
  /// get swallowed.

  static const int maxQueueSize = 500;

  static const double _minPlaybackSpeed = 0.25;
  static const double _maxPlaybackSpeed = 4.0;
  static const double _minAdvancedPlaybackSpeed = 0.1;
  static const double _maxAdvancedPlaybackSpeed = 8.0;
  @override
  bool _advancedSpeedEnabled = false;


  @override
  double _pitch = 1.0;


  @override


  @override

  @override


  @override

  @override


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

  final Completer<void> _effectsReadyCompleter = Completer<void>();

  /// Completes when the handler's async init (effects/equalizer preference
  /// restore) has finished, so listeners can re-sync effect state that was
  /// read before the restore completed.
  Future<void> get effectsReady => _effectsReadyCompleter.future;

      
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
      case 'seekRelative':
        final secs = (extras?['seconds'] as num?)?.toInt() ?? 10;
        await seekRelative(Duration(seconds: secs.clamp(-60, 60)));
        return true;
      case 'headsetAction':
        final count = (extras?['count'] as num?)?.toInt() ?? 1;
        await _performHeadsetAction(count.clamp(1, 3));
        return true;
      default:
        return super.customAction(name, extras);
    }
  }

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
