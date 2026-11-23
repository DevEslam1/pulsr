// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/errors/failures.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/battery_optimization_service.dart';
import '../services/hires_audio_service.dart';
import '../services/cast_playback_handoff.dart';
import '../services/usb_exclusive_service.dart';
import '../../core/services/ytm_service.dart';
import '../../core/telemetry/playback_latency_tracker.dart';
import '../../core/telemetry/audio_session_log.dart';
import '../../core/telemetry/dsp_reliability_tracker.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/audio_output_info.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../../domain/usecases/toggle_favorite_usecase.dart';
import 'package:drift/drift.dart' show Value;
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';
import 'audio_effects_channel.dart';
import 'audio_session_id_router.dart';
import 'crossfade_manager.dart';
import 'system_behavior_hooks.dart';
import 'automix/automix_transition_planner.dart';
import 'interruption_state_machine.dart';
import 'equalizer_manager.dart';
import 'sleep_timer_manager.dart';
import 'position_crash_guard.dart';
import 'ytm_resolving_source.dart';
import '../../core/services/ytm_cache_manager.dart';
import '../../core/utils/l10n_holder.dart';
import '../../core/utils/platform_capabilities.dart';
import 'adaptive_buffer_engine.dart';
import 'audio_memory_manager.dart';
import 'battery_aware_playback.dart';
import 'format_aware_decoder.dart';
import 'gapless_trim_handler.dart';
import 'optimized_dsp_pipeline.dart';
import 'playback_analytics.dart';
import 'replay_gain_math.dart';
import 'usb_hardware_volume_curve.dart';
import 'smart_preload_scheduler.dart';
import 'stream_pre_resolver.dart';
import 'triple_buffer_pipeline.dart';
import 'dsd_decoder_helper.dart';
import 'dsd_header_probe.dart';
import 'dsd_transport_resolver.dart';
import 'hires_dac_bridge.dart';
import 'native_dsd_session.dart';
import '../../core/services/ytm_url_cache.dart';
import '../../features/player/cubit/queue_slot_codec.dart';
import '../../features/diagnostics/safe_mode_controller.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import 'collaborators/float_output_controller.dart';
import 'collaborators/tap_src_controller.dart';
import 'dac_voicing_service.dart';
import 'collaborators/aaudio_output_controller.dart';
import 'collaborators/playback_volume_controller.dart';
import 'collaborators/playback_position_persister.dart';
import 'collaborators/playback_state_coordinator.dart';
import 'collaborators/stream_resolution_pipeline.dart';
import 'playback_queue_state_machine.dart';
import 'ab_loop_manager.dart';
import 'adaptive_quality_manager.dart';
import 'bpm_override_store.dart';
import 'per_song_volume_store.dart';
import 'per_song_playback_store.dart';
import 'dsp_snapshot_store.dart';
import 'ducking_controller.dart';
import 'multi_output_router.dart';
import 'playback_bookmark_store.dart';
import 'silence_skip_controller.dart';
import 'track_delay_manager.dart';
import 'audio_handler_lifecycle_observer.dart';
import 'headset_control_config.dart';
import '../../core/utils/pulsr_haptics.dart';
part 'audio_handler_dsp_bridge.dart';
part 'audio_handler_native_dsd.dart';
part 'audio_handler_sleep_bridge.dart';
part 'audio_handler_session_wiring.dart';
part 'audio_handler_streaming.dart';
part 'audio_handler_queue_engine.dart';
part 'audio_handler_queue_advance.dart';
part 'audio_handler_transport.dart';
part 'audio_handler_media_browser.dart';
part 'audio_handler_playback_extras.dart';
part 'audio_handler_lifecycle_ext.dart';
part 'audio_handler_init_ext.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler
    with
        WidgetsBindingObserver,
        QueueHandler,
        SeekHandler,
        PulsrAudioDspBridge,
        PulsrAudioNativeDsd,
        PulsrAudioSleepBridge,
        PulsrAudioStreaming,
        PulsrAudioQueueEngine,
        PulsrQueueAdvance,
        PulsrAudioTransport,
        PulsrAudioMediaBrowser,
        PulsrAudioPlaybackExtras {
  /// UI language used to localize the Android Auto browse tree. Set during
  /// [create] from the persisted language preference; defaults to English.
  static String _browseLanguage = 'en';

  @factoryMethod
  static Future<PulsrAudioHandler> create(
      IMusicRepository repository, YtmService ytmService) async {
    final handler = PulsrAudioHandler(repository, ytmService);
    // User preference: keep the media notification after pause so playback
    // can be resumed from the shade. AudioServiceConfig is init-time only,
    // so this takes effect on the next cold start after the toggle changes.
    // Default TRUE: a paused player must keep its notification (standard
    // music-player behavior). With stopForegroundOnPause=true the OS drops
    // the notification on every pause — including end-of-queue Next — which
    // users report as "notification disappearing with no action".
    bool keepOnPause = true;
    String channelName = 'Pulsr Audio Playback';
    String channelDesc =
        'Playback controls and now-playing information for Pulsr Music.';
    try {
      final prefs = await SharedPreferences.getInstance();
      keepOnPause = prefs.getBool(PrefsKeys.keepNotificationOnPause) ?? true;
      final langCode = prefs.getString(PrefsKeys.languageCode) ??
          prefs.getString('setting_language') ??
          Platform.localeName.split(RegExp(r'[_-]')).first.toLowerCase();
      _browseLanguage = langCode;
      if (langCode == 'ar') {
        channelName = 'تشغيل الصوت Pulsr';
        channelDesc =
            'عناصر التحكم في التشغيل ومعلومات التشغيل الحالي لتطبيق Pulsr.';
      } else if (langCode == 'es') {
        channelName = 'Reproducción de Audio Pulsr';
        channelDesc =
            'Controles de reproducción e información de reproducción actual para Pulsr.';
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to read notification channel preferences',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    try {
      final initFuture = AudioService.init(
        builder: () => handler,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.pulsr.music.audio',
          androidNotificationChannelName: channelName,
          androidNotificationChannelDescription: channelDesc,
          androidNotificationOngoing: false,
          androidNotificationClickStartsActivity: true,
          androidStopForegroundOnPause: !keepOnPause,
          androidResumeOnClick: true,
          androidNotificationIcon: 'drawable/ic_notification',
          // Declare Android Auto content-style support so the car can choose
          // list vs grid templates for the browse tree instead of a generic
          // list. Per-node hints are attached to each MediaItem's extras.
          androidBrowsableRootExtras: const <String, dynamic>{
            AndroidContentStyle.supportedKey: true,
            AndroidContentStyle.browsableHintKey:
                AndroidContentStyle.gridItemHintValue,
            AndroidContentStyle.playableHintKey:
                AndroidContentStyle.listItemHintValue,
          },
        ),
      );
      initFuture.then((_) {
        handler.platformBridgeDegraded.value = false;
      }).catchError((_) {});
      return await initFuture.timeout(const Duration(seconds: 10));
    } catch (e, st) {
      ErrorLogger.log(
          'AudioService.init failed or timed out: running in degraded audio '
          'mode (playback works, but there is no media notification / '
          'foreground service)',
          error: e,
          stackTrace: st,
          category: 'AudioHandler');
      handler.platformBridgeDegraded.value = true;
      return handler;
    }
  }

  // Getters, not finals: the notification is rebuilt on every state change, so
  // each one picks up the locale that is active at that moment.
  static String get _favoriteOffLabel =>
      L10nHolder.current?.mediaControlUnfavorite ?? 'Unfavorite';
  static String get _favoriteOnLabel =>
      L10nHolder.current?.favorite ?? 'Favorite';
  static String get _shuffleLabel => L10nHolder.current?.shuffle ?? 'Shuffle';
  static String get _repeatLabel => L10nHolder.current?.repeat ?? 'Repeat';

  static MediaControl get controlFavorite => MediaControl.custom(
        androidIcon: 'drawable/ic_favorite',
        label: _favoriteOffLabel,
        name: 'toggleFavorite',
      );
  static MediaControl get controlUnfavorite => MediaControl.custom(
        androidIcon: 'drawable/ic_favorite_border',
        label: _favoriteOnLabel,
        name: 'toggleFavorite',
      );
  static MediaControl get controlShuffleOn => MediaControl.custom(
        androidIcon: 'drawable/ic_shuffle_on',
        label: _shuffleLabel,
        name: 'toggleShuffle',
      );
  static MediaControl get controlShuffleOff => MediaControl.custom(
        androidIcon: 'drawable/ic_shuffle',
        label: _shuffleLabel,
        name: 'toggleShuffle',
      );
  static MediaControl get controlRepeatOne => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat_one',
        label: _repeatLabel,
        name: 'cycleRepeat',
      );
  static MediaControl get controlRepeatAll => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat_all',
        label: _repeatLabel,
        name: 'cycleRepeat',
      );
  static MediaControl get controlRepeatOff => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat',
        label: _repeatLabel,
        name: 'cycleRepeat',
      );

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
  @override
  bool get _isEffectivelyPlaying =>
      _activePlayer.playing || (nativeDsdActive && _nativeDsdPlaying);

  /// Returns playback position compensated for native and DSP pipeline latency.
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

  /// Pure, testable playback queue state machine (P2).
  @override
  final PlaybackQueueStateMachine _queueStateMachine =
      PlaybackQueueStateMachine();

  PlaybackQueueStateMachine get queueStateMachine => _queueStateMachine;

  @override
  List<SongsTableData> get _songs => _queueStateMachine.songs;
  @override
  set _songs(List<SongsTableData> value) => _queueStateMachine.setQueue(value);

  @override
  int get _currentIndex => _queueStateMachine.currentIndex;
  @override
  set _currentIndex(int value) => _queueStateMachine.setCurrentIndex(value);

  @override
  bool get _queueDirty => _queueStateMachine.isQueueDirty;
  @override
  set _queueDirty(bool value) {
    if (value) {
      _queueStateMachine.markQueueDirty();
    } else {
      _queueStateMachine.markQueueClean(_queueStateMachine.currentIndex);
    }
  }

  @override
  int get _savedQueueIndex => _queueStateMachine.savedQueueIndex;
  @override
  set _savedQueueIndex(int value) =>
      _queueStateMachine.setSavedQueueIndex(value);

  HeadsetControlConfig? _cachedHeadsetConfig;
  @override
  HeadsetControlConfig? get cachedHeadsetConfig => _cachedHeadsetConfig;
  @override
  set cachedHeadsetConfig(HeadsetControlConfig? value) =>
      _cachedHeadsetConfig = value;
  double? _preDuckVolume;
  double? _preDuckInactiveVolume;
  // Captured at duck-begin so duck-end can tell whether the track or its
  // ReplayGain target changed during the duck and, if not, restore the exact
  // pre-duck level instead of snapping to the RG target (preserves a mid-fade).
  int? _preDuckSongId;
  double? _preDuckRgTarget;
  bool _duckActive = false;
  int _duckDepthCounter = 0;
  Timer? _duckSafetyTimer;
  // Single sleep-fade multiplier (0..1; 1.0 = not fading) owned by the handler
  // so the three volume paths (ducking, sleep-fade, crossfade) stop clobbering
  // each other. The SleepTimerManager reports its stepped fade progress here
  // (via its onFadeFactor hook) instead of writing the player volume directly;
  // the handler then composes it with the duck-aware ReplayGain/user target in
  // [_reapplyActiveVolume] / [setVolume]. The native sample-accurate gain-curve
  // fade path leaves this at 1.0 (that curve multiplies the player's base
  // volume inside the sink, so it already composes).
  @override
  double _sleepFadeFactor = 1.0;
  // Transient system-sound duck restore timer; tracked so dispose() can cancel
  // it (previously it was an untracked Timer that could fire after dispose).
  Timer? _systemSoundTimer;
  // When a gapless load is suppressing broadcasts, the time it started, so the
  // suppression is bounded and a stalled/failed load cannot freeze the
  // notification forever (see _broadcastState).
  @override
  DateTime? _gaplessSuppressionSince;

  /// Optional delivery bridge owned by the system-behaviour runtime.
  ///
  /// The handler owns the audio_session streams and the interruption state
  /// machine; the runtime owns *how* a pause is delivered (fade ramp, USB
  /// release, plain pause) and which setting decides it. With a bridge
  /// attached, focus/duck/noisy events are handed to it and the handler skips
  /// its own pause/resume when the bridge reports it acted, so one event always
  /// produces exactly one pause. Null keeps the legacy path byte-for-byte.
  SystemBehaviorHooks? _systemBehaviorHooks;

  /// Attaches (or clears, with null) the system-behaviour delivery bridge.
  void attachSystemBehaviorHooks(SystemBehaviorHooks? hooks) {
    _systemBehaviorHooks = hooks;
  }

  /// Whether a system-behaviour bridge currently owns pause delivery.
  bool get hasSystemBehaviorHooks => _systemBehaviorHooks != null;

  /// Pure, testable interruption bookkeeping (B-1). Replaces the previous pair
  /// of loose booleans whose begin/end bookkeeping was asymmetric.
  @override
  final InterruptionStateMachine _interruption = InterruptionStateMachine();
  DateTime? _lastNoisyTime;
  // Auto-resume bookkeeping: a becoming-noisy pause arms a one-shot resume
  // window; a reconnect on a headset/BT/USB route within the timeout resumes.
  DateTime? _noisyPauseTime;
  @override
  bool _pausedForNoisy = false;
  @override
  int _consecutiveFailures = 0;
  // Last time a track-completion was reported to the sleep timer. Gapless
  // playback reports one boundary through two independent signals (the native
  // `ProcessingState.completed` event and the `currentIndexStream` advance), so
  // this debounce collapses the duplicate. See [_notifySleepTrackCompleted].
  @override
  DateTime? _lastSleepTrackCompletedAt;
  @override
  List<int> get _shuffleHistory => _queueStateMachine.shuffleHistory;
  @override
  DateTime? _lastPreviousTapTime;
  @override
  bool _isManualSkip = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  @override
  int _playGeneration = 0;
  // Seek throttling: optimistic UI only — the cubit-layer PlayerSeekThrottle
  // is the canonical debounce. _seekDebounceTimer is kept for teardown safety
  // in stop() and dispose() in case a timer was in flight before this handler
  // was re-created.
  Timer? _seekDebounceTimer;
  @override
  int _lastSmartPrefetchMs = 0;
  @override
  String? _lastSmartPrefetchKey;
  @override
  Timer? _crossfadeSwitchDebounce;
  AudioHandlerLifecycleObserver? _lifecycleObserver;
  CastPlaybackHandoff? _castPlaybackHandoff;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  @override
  Duration? _pendingLazyPosition;
  Duration? _preBatteryCriticalCrossfadeDuration;
  // Video ids with an in-flight prefetch, so we resolve each at most once.
  @override
  final Set<String> _prefetching = {};

  @override
  String _currentStreamingQuality() {
    if (adaptiveQualityManager.enabled) {
      return adaptiveQualityManager.currentQuality;
    }
    return _cachedPrefs?.getString(PrefsKeys.streamingQuality) ?? 'high';
  }

  final AdaptiveBufferEngine _adaptiveBufferEngine = AdaptiveBufferEngine();
  @override
  final OptimizedDspPipeline _dspPipeline = OptimizedDspPipeline();
  late final PlaybackAnalytics _playbackAnalytics;
  late final AudioMemoryManager _memoryManager;
  @override
  late final SmartPreloadScheduler _preloadScheduler;
  @override
  late final FormatAwareDecoder _formatDecoder;
  @override
  late final TripleBufferPipeline _tripleBufferPipeline;
  @override
  late final BatteryAwarePlayback _batteryAwarePlayback;

  /// User-forced battery saver. Distinct from the automatic level policy: it
  /// pins the essential DSP profile regardless of charge and survives restart.
  bool _batterySaverForced = false;
  @override
  late final StreamPreResolver _streamPreResolver;
  @override
  bool _disposed = false;
  bool get isDisposed => _disposed;
  Future<void> _dspTransitionTail = Future<void>.value();

  /// Change a complete DSP profile while the rendered signal is faded out.
  /// Poll the actual gain so buffered playback cannot outrun a timed delay.
  Future<T> withSmoothDspTransition<T>(Future<T> Function() action) async {
    final previous = _dspTransitionTail;
    final released = Completer<void>();
    _dspTransitionTail = released.future;
    await previous;
    final muted = <AudioPlayer>[];
    try {
      if (_disposed) throw StateError('Audio handler disposed');
      for (final player in [_playerA, _playerB]) {
        if (!player.playing) continue;
        if (await player.dspSetTransitionMuted(true)) muted.add(player);
      }
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      for (final player in muted) {
        while (player.playing &&
            player.processingState != ProcessingState.completed) {
          final gain = await player.dspGetTransitionGain();
          if (gain == null) {
            // The native side cannot report the gain, so polling can never
            // succeed. Give the fade a short fixed window instead of spinning
            // until the 3s deadline and then aborting the profile change.
            await Future<void>.delayed(const Duration(milliseconds: 60));
            break;
          }
          if (gain <= 0.0001) break;
          if (DateTime.now().isAfter(deadline)) {
            // A player can report `playing` while no frames are rendering (a
            // temporary stall, a gapless hand-off, or a route where the native
            // processor is not in the active sink). The fade then never
            // advances. Aborting here used to drop the entire profile change —
            // the toggle flipped on but no DSP applied. Prefer applying the
            // profile over a fully silent hand-off; the mute is released in
            // `finally` either way.
            ErrorLogger.log(
              'DSP transition fade did not reach silence before the deadline; '
              'applying without a completed fade',
              category: 'AudioHandler',
            );
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      final result = await action();
      if (muted.isNotEmpty) {
        // The DSP edits have already been dispatched by `action()`. A failed
        // preparation acknowledgement only means we cannot confirm the native
        // queue drained; it must not be reported as the profile failing to
        // apply. Log it and still give the settle window.
        if (!await AudioEffectsChannel().awaitControlUpdates()) {
          ErrorLogger.log(
            'DSP profile preparation did not acknowledge completion; '
            'releasing the transition anyway',
            category: 'AudioHandler',
          );
        }
        // Let reset filters and lookahead buffers settle before fading back in.
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      return result;
    } finally {
      for (final player in muted) {
        try {
          await player.dspSetTransitionMuted(false);
        } catch (_) {}
      }
      released.complete();
    }
  }

  // FIX B9 & C-01: Initialized immediately in constructor to prevent cold-start races.
  PlaybackVolumeController? _volumeController;
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
  final MultiOutputRouter multiOutputRouter = MultiOutputRouter();
  @override
  final DspSnapshotStore dspSnapshotStore = DspSnapshotStore();
  @override
  final SilenceSkipController silenceSkipController = SilenceSkipController();
  @override
  final BpmOverrideStore bpmOverrideStore = BpmOverrideStore();
  @override
  final PlaybackBookmarkStore bookmarkStore = PlaybackBookmarkStore();
  @override
  final PerSongPlaybackStore perSongPlaybackStore = PerSongPlaybackStore();
  @override
  bool hedgedResolutionEnabled = true;
  DateTime? _lastBookmarkSave;
  DateTime? _lastHealthyReport;
  final GaplessTransitionMonitor _gaplessMonitor = GaplessTransitionMonitor();
  int get gapEventCount => _gaplessMonitor.gapEventCount;
  int get crossfadeGlitchCount => _crossfadeManager.crossfadeGlitchCount;

  // Gapless engine: when crossfade is off, AudioPlayer's built-in playlist on the
  // active player is the source of truth for track order/advance, and just_audio
  // joins consecutive items seamlessly. False while crossfade (duration > 0) is
  // active, which keeps the manual dual-player path below.
  @override
  bool _gaplessLoaded = false;
  // Last index reacted to from currentIndexStream, to drop duplicate emits.
  @override
  int _lastGaplessIndex = -1;

  // Target index for current gapless load; used to filter transient ExoPlayer index 0 emits
  @override
  int? _gaplessTargetIndex;
  @override
  final Stopwatch _gaplessStopwatch = Stopwatch();
  @override
  bool _gaplessTargetReached = false;
  @override
  int _gaplessLoadGeneration = 0;
  @override
  int _loadQueueGeneration = 0;

  /// User-facing gapless toggle (persisted as `setting_gapless`). Gapless is
  /// disabled by default and is mutually exclusive with crossfade.
  @override
  bool _gaplessEnabled = false;
  bool get isGaplessEnabled => _gaplessEnabled;

  /// Gapless is mutually exclusive with crossfade and Automix. Enabling either
  /// crossfade (duration > 0) or Automix switches to the overlapping
  /// dual-player engine, which cannot share the single-player concat path.
  @override
  bool get _gaplessMode =>
      _gaplessEnabled &&
      !_nativeDsdActive &&
      _crossfadeManager.duration <= Duration.zero &&
      !_crossfadeManager.automixEnabled;

  @override
  final StreamController<SongsTableData> _onTrackChangedSubject =
      StreamController<SongsTableData>.broadcast();
  Stream<SongsTableData> get onTrackChanged => _onTrackChangedSubject.stream;

  final Map<int, bool> _resolvedDopBySongId = {};
  final Map<int, bool> _resolvedNativeDsdBySongId = {};
  bool _lastSyncedNativeDop = false;

  @override
  void _recordResolvedDsdTransport(
    int songId, {
    required bool isDop,
    required bool isNativeDsd,
  }) {
    if (_resolvedDopBySongId.length >= 512 &&
        !_resolvedDopBySongId.containsKey(songId)) {
      _resolvedDopBySongId.remove(_resolvedDopBySongId.keys.first);
      _resolvedNativeDsdBySongId.remove(_resolvedNativeDsdBySongId.keys.first);
    }
    _resolvedDopBySongId[songId] = isDop;
    _resolvedNativeDsdBySongId[songId] = isNativeDsd;
  }

  bool _isSongDopActive(SongsTableData? song) {
    if (song == null) return DsdDecoderHelper.dsdDopActive;
    final resolved = _resolvedDopBySongId[song.id];
    if (resolved != null) return resolved;
    return song.id == currentSong?.id && DsdDecoderHelper.dsdDopActive;
  }

  @override
  bool _isBitPerfectBypassEnabled() {
    final transport = _bitPerfectTransportBypass;
    if (transport != null) return transport;
    final prefs = _cachedPrefs;
    return (prefs?.getBool(PrefsKeys.strictBitPerfect) ?? false) ||
        ((prefs?.getBool(PrefsKeys.bitPerfectOutput) ?? false) &&
            (prefs?.getBool(PrefsKeys.bypassDspOnBitPerfect) ?? true));
  }

  Future<void> _syncDopToEffectsEngine(bool isDop) async {
    if (!Platform.isAndroid) return;
    if (isDop == _lastSyncedNativeDop) return;
    _lastSyncedNativeDop = isDop;
    try {
      await AudioEffectsChannel().setBypassDspForBitPerfect(
        _isBitPerfectBypassEnabled(),
        isDop: isDop,
      );
    } catch (e, st) {
      ErrorLogger.log(
        'Failed to sync DoP transport state ($isDop) to effects engine',
        error: e,
        stackTrace: st,
        category: 'AudioHandler',
      );
    }
  }

  @override
  void _notifyTrackChanged(SongsTableData song) {
    _cueStartSeeked = false;
    _cueAdvanceTriggered = false;
    _playbackStateCoordinator.resetSavedPosition();
    final previousDop = DsdDecoderHelper.dsdDopActive;
    final prevDop = _lastSyncedNativeDop;
    final isDop = _resolvedDopBySongId[song.id] ?? false;
    final isNativeDsd = _resolvedNativeDsdBySongId[song.id] ?? false;
    DsdDecoderHelper.dsdDopActive = isDop;
    DsdDecoderHelper.dsdNativeActive = isNativeDsd;
    if (isDop != _lastSyncedNativeDop) {
      unawaited(_syncDopToEffectsEngine(isDop));
    }
    unawaited(_pushNativeReplayGain(song));
    // Always re-sync output/Direct-USB/hardware volume on track change so a
    // newly opened or reconfigured Bit-Perfect/Direct-USB sink never starts at
    // full scale (1.0) waiting for a physical volume key press.
    _lastDirectUsbVolume = -1.0;
    if (_shouldForwardSystemVolumeToOutput()) {
      unawaited(_refreshLoudnessContourFromSystemVolume(
        forceUsbHardwareSeed: true,
      ));
    } else if (isDop != prevDop || isDop != previousDop) {
      unawaited(_reapplyActiveVolume());
    }
    if (!_onTrackChangedSubject.isClosed) {
      _onTrackChangedSubject.add(song);
    }
  }

  // T10: CUE sub-track boundaries. Both flags reset on track change so each
  // virtual track seeks once to its start and advances once at its end.
  bool _cueStartSeeked = false;
  bool _cueAdvanceTriggered = false;

  @override
  late final PlaybackStateCoordinator _playbackStateCoordinator;
  late final PlaybackPositionPersister _positionPersister;
  Timer? _fadeInGuardTimer; // FIX-#12: tracked for disposal

  // Transient stream-error retry bookkeeping (see _retryCurrentOrSkip).
  @override
  int? _streamRetrySongId;
  @override
  int _streamRetryCount = 0;

  /// Releases the underrun-forced "generous" buffer after a quiet period so a
  /// passing network dip does not pin a 50-90s buffer for the whole session.
  Timer? _bufferRelaxTimer;
  static const Duration _bufferRelaxAfter = Duration(minutes: 5);

  void _scheduleBufferRelax() {
    _bufferRelaxTimer?.cancel();
    _bufferRelaxTimer = Timer(_bufferRelaxAfter, () {
      _bufferRelaxTimer = null;
      if (_disposed) return;
      // A battery policy force must outlive this timer.
      if (_batteryAwarePlayback.currentLevel !=
          BatteryOptimizationLevel.normal) {
        return;
      }
      _adaptiveBufferEngine.releaseForce();
    });
  }

  Stream<Duration> get positionStream =>
      _playbackStateCoordinator.positionStream;

  /// High-rate stream (~16ms granularity, 60fps) for fluid waveform seeks.
  Stream<Duration> get highRatePositionStream =>
      _playbackStateCoordinator.highRatePositionStream;

  /// High-rate stream compensated for DSP and native hardware latency (B-11).
  Stream<Duration> get compensatedHighRatePositionStream =>
      highRatePositionStream
          .map((pos) => _dspPipeline.getCompensatedPosition(pos));

  /// Stream of playback positions compensated for DSP and native hardware latency.
  Stream<Duration> get compensatedPositionStream =>
      positionStream.map((pos) => _dspPipeline.getCompensatedPosition(pos));

  @override
  void _emitPosition(Duration position) =>
      _playbackStateCoordinator.emitImmediatePosition(position);

  @override
  void _resumePositionSaving() => _playbackStateCoordinator.resumeSaving();

  @override
  final StreamController<String> _errorSubject =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorSubject.stream;
  // Output-mode fallbacks and cascade halts are terminal/informational notices:
  // they ride the error stream prefixed so PlayerCubit displays them without
  // re-entering its unplayable-track auto-skip path.
  static const String outputModeNoticePrefix = '__pulsr_output_mode__:';
  static const String failureCascadeHaltPrefix = '__pulsr_cascade_halt__:';
  String? _lastOutputModeNotice;
  /// Last temporary-suspension reason logged. A suspension and its resume
  /// repeat the same reason, so this keeps the informational line to one per
  /// episode instead of two.
  String? _lastSuspendedReason;
  /// Sink reasons that mean "temporarily parked on the AudioTrack path", not
  /// "this output refuses the direct path". Both arrive with a non-null reason,
  /// but only a real rejection may feed safe mode or raise a notice.
  static const Set<String> _suspensionReasons = {
    'speed_requires_audiotrack',
    'skip_silence_requires_audiotrack',
    'aaudio_suspended',
    'aaudio_write_failed',
  };
  SafeModeController? _safeModeController;
  bool _safeModeApplyInFlight = false;
  int? _currentAudioSessionId;
  final StreamController<int?> _audioSessionIdSubject =
      StreamController<int?>.broadcast();

  /// The Android audio session id of the active player, or null when the
  /// platform has not yet assigned one (or on non-Android). Consumers such as
  /// the visualizer attach to this real session instead of the global mix.
  int? get currentAudioSessionId => _currentAudioSessionId;
  Stream<int?> get audioSessionIdStream => _audioSessionIdSubject.stream;

  final BehaviorSubject<double> _volumeSubject =
      BehaviorSubject<double>.seeded(1.0);

  /// Reactive master volume stream reflecting software volume and hardware key updates.
  Stream<double> get volumeStream => _volumeSubject.stream;
  @override
  SongsTableData? get currentSong => _queueStateMachine.currentSong;

  final PlaybackLatencyTracker? _injectedLatencyTracker;
  final HiResAudioService? _injectedHiResAudioService;

  @override
  PlaybackLatencyTracker? get _latencyTracker =>
      _injectedLatencyTracker ??
      (getIt.isRegistered<PlaybackLatencyTracker>()
          ? getIt<PlaybackLatencyTracker>()
          : null);

  HiResAudioService? get _hiResAudioService =>
      _injectedHiResAudioService ??
      (getIt.isRegistered<HiResAudioService>()
          ? getIt<HiResAudioService>()
          : null);

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
    PlaybackLatencyTracker? latencyTracker,
    HiResAudioService? hiResAudioService,
  })  : _repository = repository,
        _ytmService = ytmService,
        _playerA = playerA,
        _playerB = playerB,
        _prefetchPlayer = prefetchPlayer ?? AudioPlayer(),
        _injectedLatencyTracker = latencyTracker,
        _injectedHiResAudioService = hiResAudioService {
    _playbackStateCoordinator = PlaybackStateCoordinator(
      onSavePositionRequested: saveCurrentPositionImmediate,
      saveInterval: const Duration(seconds: 2),
      minDeltaMs: 0,
    );
    _positionPersister = createPlaybackPositionPersister();
    _equalizerManager = EqualizerManager(
      loudnessEnhancerA: loudnessEnhancerA,
      loudnessEnhancerB: loudnessEnhancerB,
    );
    _audioSessionIdRouter = AudioSessionIdRouter(
      onSessionChanged: (sessionId) async {
        _currentAudioSessionId = sessionId;
        _audioSessionIdSubject.add(sessionId);
        try {
          // Reattach before reading latency: the HAL chain must exist on the
          // new session before the native query can report its real latency.
          await _equalizerManager.reapplyToSession(sessionId);
          await _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        } catch (e, st) {
          ErrorLogger.log(
            'Session-change DSP reattach failed',
            error: e,
            stackTrace: st,
            category: 'PulsrAudioHandler',
          );
        }
        // Track start: re-seed the loudness contour and re-apply hardware /
        // Direct USB volume (reapplyToSession released and rebuilt native DSP).
        _lastDirectUsbVolume = -1.0;
        unawaited(_refreshLoudnessContourFromSystemVolume(
          forceUsbHardwareSeed: true,
        ));
      },
      onRouteChanged: () async {
        _syncBluetoothRouteFromCache();
        try {
          await _equalizerManager.resyncActiveEffects();
          await _equalizerManager.syncNativeLatency(assumedOutputSampleRate);
        } catch (e, st) {
          ErrorLogger.log(
            'Route-change DSP resync failed',
            error: e,
            stackTrace: st,
            category: 'PulsrAudioHandler',
          );
        }
        unawaited(_refreshBluetoothRoute());
        unawaited(_recordSessionRouteChange());
        // STREAM_MUSIC volume is per-route on Android; re-seed so a bypassed
        // (bit-perfect / AAudio / USB) output does not keep the old route's gain.
        _lastDirectUsbVolume = -1.0;
        unawaited(_refreshLoudnessContourFromSystemVolume(
          forceUsbHardwareSeed: true,
        ));
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
    _volumeController = PlaybackVolumeController(
      getActivePlayer: () => _activePlayer,
      getInactivePlayer: () => _inactivePlayer,
    );
    _streamResolutionPipeline = StreamResolutionPipeline(
      ytmService: _ytmService,
      getLatencyTracker: () => _latencyTracker,
      qualityProvider: _currentStreamingQuality,
      onStreamResolved: (song, bitrate, codec) {
        final songIndex = _songs.indexWhere((s) =>
            s.id == song.id ||
            (s.remoteId != null && s.remoteId == song.remoteId));
        if (songIndex != -1 && songIndex < _songs.length) {
          final target = _songs[songIndex];
          if (target.id == song.id ||
              (target.remoteId != null && target.remoteId == song.remoteId)) {
            final updated = target.copyWith(
              // Unknown stays unknown. A guessed 64/128/160 kbps badge is a
              // fabricated technical claim about a stream that never reported a
              // bitrate; the resolver now passes null instead of a default.
              bitrateKbps:
                  bitrate != null ? Value(bitrate) : const Value.absent(),
              codec: codec != null ? Value(codec) : const Value.absent(),
              // The stream metadata carries no sample rate. Asserting 44.1 kHz
              // for every AAC track (and 48 kHz for every Opus one) was a
              // second invention, so leave the column alone.
              sampleRate: const Value.absent(),
            );
            _songs[songIndex] = updated;
            if (mediaItem.value?.id == updated.id.toString()) {
              mediaItem.add(_songToMediaItem(updated));
            }
          }
        }
      },
    );
    // Volume coordination: the sleep fade reports its progress as a FACTOR
    // instead of writing the active player's volume itself, so it composes with
    // ducking (and defers to the crossfade manager) through the handler's
    // single [_reapplyActiveVolume] re-apply point. [baseVolumeProvider] gives
    // the manager the clean (un-faded) target for its fallback path so it never
    // snapshots a ducked level as its fade baseline.
    _sleepTimerManager.baseVolumeProvider =
        () => _calculateReplayGainVolume(currentSong);
    _sleepTimerManager.onFadeFactor = (factor) {
      _sleepFadeFactor = factor.isFinite ? factor.clamp(0.0, 1.0) : 1.0;
      return _reapplyActiveVolume();
    };
    // Backstop: if _init() throws before reaching its restore block, the
    // effects-ready signal must still fire so listeners aren't left waiting.
    _init().catchError((Object e, StackTrace st) {
      // Without this, the Future returned by whenComplete() below re-throws the
      // error with no listener and it surfaces as an unhandled async error.
      ErrorLogger.log('PulsrAudioHandler._init failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }).whenComplete(() {
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
  @override
  AdaptiveBufferEngine get adaptiveBufferEngine => _adaptiveBufferEngine;
  OptimizedDspPipeline get dspPipeline => _dspPipeline;
  PlaybackAnalytics get playbackAnalytics => _playbackAnalytics;
  AudioMemoryManager get memoryManager => _memoryManager;
  SmartPreloadScheduler get preloadScheduler => _preloadScheduler;
  FormatAwareDecoder get formatDecoder => _formatDecoder;
  TripleBufferPipeline get tripleBufferPipeline => _tripleBufferPipeline;
  BatteryAwarePlayback get batteryAwarePlayback => _batteryAwarePlayback;
  StreamPreResolver get streamPreResolver => _streamPreResolver;
  PlaybackVolumeController? get volumeController => _volumeController;
  StreamResolutionPipeline get streamResolutionPipeline =>
      _streamResolutionPipeline;

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
      final service = _hiResAudioService;
      if (service == null) return;
      final info = service.currentOutputInfo;
      if (info != null) _equalizerManager.isBluetoothRoute = info.isBluetooth;
    } catch (_) {}
  }

  /// Refreshes the cached output info from native, then mirrors the route.
  Future<void> _refreshBluetoothRoute() async {
    try {
      final service = _hiResAudioService;
      if (service == null) return;
      final wasBluetooth = _equalizerManager.isBluetoothRoute;
      // The native event channel already pushed the fresh snapshot that
      // triggered this refresh; re-probing during BT/startup jank only
      // produces timeouts.
      final info = await service.getAudioOutputInfo(allowCached: true);
      _equalizerManager.isBluetoothRoute = info.isBluetooth;
      if (wasBluetooth != info.isBluetooth) {
        await _equalizerManager.resyncActiveEffects();
      }
    } catch (e, st) {
      DspReliabilityTracker.instance.recordRouteResyncFailure(e);
      ErrorLogger.log('Failed to refresh Bluetooth route and sync effects',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  Set<String> _lastKnownOutputDeviceIds = <String>{};

  static bool _isHeadsetLikeDevice(AudioOutputInfo info) {
    final type = info.activeDeviceType.trim().toLowerCase();
    return info.isBluetooth ||
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
  }

  Future<AudioOutputInfo?> _getOutputInfo() async {
    final service = _hiResAudioService;
    if (service == null) return null;
    return service.getAudioOutputInfo(allowCached: true);
  }

  Set<String> _outputDeviceIds(AudioOutputInfo info) {
    return info.availableDevices.isNotEmpty
        ? info.availableDevices.map((d) => '${d.id}:${d.type}').toSet()
        : <String>{'${info.deviceName}:${info.activeDeviceType}'};
  }

  /// The "before reconnect" snapshot. Captured after the noisy pause so the
  /// unplugged headset is absent and only a real reconnect looks like a gain.
  Future<void> _captureOutputDeviceBaseline() async {
    final info = await _getOutputInfo();
    if (info == null) return;
    _lastKnownOutputDeviceIds = _outputDeviceIds(info);
  }

  /// One-shot auto-resume after a becoming-noisy pause.
  /// Fires only when the user opted in, the pause was noisy-triggered, the
  /// timeout has not elapsed, the player is still paused, and the new route
  /// gained a headset-like output (BT / wired / USB / HDMI).
  Future<void> _maybeAutoResumeOnReconnect() async {
    try {
      final info = await _getOutputInfo();
      if (info == null) return;
      final currentDeviceIds = _outputDeviceIds(info);

      if (!_pausedForNoisy) {
        _lastKnownOutputDeviceIds = currentDeviceIds;
        return;
      }

      final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
      if (!(prefs.getBool(PrefsKeys.autoResumeOnReconnect) ?? false)) {
        _pausedForNoisy = false;
        _lastKnownOutputDeviceIds = currentDeviceIds;
        return;
      }
      final timeoutSec = prefs.getInt(PrefsKeys.autoResumeTimeoutSec) ?? 90;
      final pausedAt = _noisyPauseTime;
      if (pausedAt == null ||
          DateTime.now().difference(pausedAt).inSeconds > timeoutSec) {
        _pausedForNoisy = false;
        _lastKnownOutputDeviceIds = currentDeviceIds;
        return;
      }
      if (_activePlayer.playing || _songs.isEmpty) {
        _pausedForNoisy = false;
        _lastKnownOutputDeviceIds = currentDeviceIds;
        return;
      }

      final gainedDevices =
          currentDeviceIds.difference(_lastKnownOutputDeviceIds);
      _lastKnownOutputDeviceIds = currentDeviceIds;

      if (!_isHeadsetLikeDevice(info) || gainedDevices.isEmpty) return;

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

  Future<AudioOutputInfo?> _currentOutputInfo() async {
    try {
      final service = _hiResAudioService;
      if (service == null) return null;
      return await service.getAudioOutputInfo();
    } catch (_) {
      return null;
    }
  }

  /// Publishes the app-scoped [SafeModeController] once preferences exist.
  ///
  /// The diagnostics screen can also build a private controller; the default
  /// reloader below is static, so both refresh SettingsCubit after a fallback
  /// or reset.
  void _installSafeModeController() {
    final prefs = _cachedPrefs;
    if (prefs == null) return;
    SafeModeController controller;
    if (getIt.isRegistered<SafeModeController>()) {
      controller = getIt<SafeModeController>();
    } else {
      controller = SafeModeController(prefs: prefs);
      getIt.registerSingleton<SafeModeController>(controller);
    }
    _safeModeController = controller;
    SafeModeController.defaultReloader = () async {
      if (!getIt.isRegistered<SettingsCubit>()) return;
      await getIt<SettingsCubit>().reloadSettings();
    };
  }

  /// Records one output failure for the active device and applies the fallback
  /// once the threshold is reached.
  ///
  /// Fire-and-forget from the player streams: a missing controller (tests,
  /// desktop) is a no-op and failures never escape into the audio path.
  Future<void> _recordSafeModeFailure(String reason) async {
    if (_disposed) return;
    final controller = _safeModeController ??
        (getIt.isRegistered<SafeModeController>()
            ? getIt<SafeModeController>()
            : null);
    if (controller == null) return;
    try {
      final info = await _currentOutputInfo();
      final deviceKey = info == null
          ? 'default'
          : '${info.isUsbDac ? 'usb' : info.isBluetooth ? 'bluetooth' : info.activeDeviceType}_${info.deviceName}';
      await controller.recordFailure(deviceKey, reason);
      if (!controller.shouldFallback(deviceKey) ||
          controller.isFallbackActive(deviceKey) ||
          _safeModeApplyInFlight) {
        return;
      }
      _safeModeApplyInFlight = true;
      final description = await controller.applyFallback(deviceKey);
      if (!_errorSubject.isClosed) {
        _errorSubject.add('$outputModeNoticePrefix$description');
      }
    } catch (e, st) {
      ErrorLogger.log(
        'Safe-mode output failure handling failed',
        error: e,
        stackTrace: st,
        category: 'AudioHandler',
      );
    } finally {
      _safeModeApplyInFlight = false;
    }
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
    IMusicRepository repository,
    YtmService ytmService, {
    PlaybackLatencyTracker? latencyTracker,
    HiResAudioService? hiResAudioService,
  }) {
    if (Platform.isAndroid) {
      final loadConfig = _loadConfigForBucket(BufferBucket.standard);

      final playerA = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
        handleInterruptions: false,
      );
      final playerB = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
        handleInterruptions: false,
      );
      final prefetchPlayer = AudioPlayer(
        audioLoadConfiguration: loadConfig,
        useLazyPreparation: true,
        handleInterruptions: false,
      );
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: playerA,
        playerB: playerB,
        prefetchPlayer: prefetchPlayer,
        latencyTracker: latencyTracker,
        hiResAudioService: hiResAudioService,
      );
    } else {
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: AudioPlayer(
          useLazyPreparation: true,
          handleInterruptions: false,
        ),
        playerB: AudioPlayer(
          useLazyPreparation: true,
          handleInterruptions: false,
        ),
        prefetchPlayer: AudioPlayer(
          useLazyPreparation: true,
          handleInterruptions: false,
        ),
        latencyTracker: latencyTracker,
        hiResAudioService: hiResAudioService,
      );
    }
  }

  @visibleForTesting
  PulsrAudioHandler.forTesting({
    required IMusicRepository repository,
    required YtmService ytmService,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AudioPlayer? prefetchPlayer,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
    PlaybackLatencyTracker? latencyTracker,
    HiResAudioService? hiResAudioService,
  }) : this._(
          repository: repository,
          ytmService: ytmService,
          playerA: playerA,
          playerB: playerB,
          prefetchPlayer: prefetchPlayer,
          loudnessEnhancerA: loudnessEnhancerA,
          loudnessEnhancerB: loudnessEnhancerB,
          latencyTracker: latencyTracker,
          hiResAudioService: hiResAudioService,
        );

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
        if (artString.startsWith('assets/')) {
          final cached = ArtworkUriResolver.getCachedArtworkUri(song.id);
          if (cached != null) {
            finalArtUri = cached;
          }
        } else {
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
      finalArtUri ??= ArtworkUriResolver.getCachedArtworkUri(song.id) ??
          (song.albumId != null
              ? ArtworkUriResolver.getCachedAlbumArtUri(song.albumId!)
              : null);
      if (finalArtUri == null && song.albumId != null && song.albumId! > 0) {
        finalArtUri = Uri.parse(
            'content://media/external/audio/albumart/${song.albumId}');
      } else if (finalArtUri == null && song.id > 0) {
        finalArtUri = Uri.parse(
            'content://media/external/audio/media/${song.id}/albumart');
      }
    }

    return MediaItem(
      id: song.id.toString(),
      album: song.album,
      title: song.title,
      artist: song.artist,
      // Android Auto surfaces this as a heart toggle; handled by [setRating].
      rating: Rating.newHeartRating(song.isFavorite),
      // 0 means "unknown" (streams); null lets the platform show an indeterminate
      // bar until the player's durationStream reports the real length.
      duration:
          song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null,
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
    try {
      _cachedPrefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      ErrorLogger.log('SharedPreferences init failed, retrying once...',
          error: e, stackTrace: st, category: 'AudioHandler');
      try {
        _cachedPrefs = await SharedPreferences.getInstance();
      } catch (e2, st2) {
        ErrorLogger.log('SharedPreferences init failed permanently',
            error: e2, stackTrace: st2, category: 'AudioHandler');
        _cachedPrefs = null;
      }
    }
  }

  @override
  double _volume = 1.0;
  double get volume => _volume;

  /// Actual player gain, including per-song offsets, ducking and sleep fades.
  double get effectiveSoftwareGain => _activePlayer.volume;
  bool get transportSamplesModified =>
      playbackState.value.speed != 1.0 ||
      pitch != 1.0 ||
      skipSilenceEnabled ||
      _crossfadeManager.isCrossfading ||
      _crossfadeManager.isNativeCurveArmedOnOutgoing ||
      _sleepFadeFactor != 1.0 ||
      _duckActive;

  @override
  bool? _bitPerfectTransportBypass;

  /// Rebuilds both players' inner sinks with the current output policies.
  ///
  /// The integer Bit-Perfect bypass is applied by the sink's configure(), so a
  /// bypass change made mid-track needs one rebuild to take effect. The
  /// Bit-Perfect transition pauses first, which is what makes the rebuild
  /// inaudible; callers must not use this while audio is actively rendering.
  Future<void> reconfigurePlaybackSink() async {
    try {
      await Future.wait([
        _playerA.dspReconfigureSink(),
        _playerB.dspReconfigureSink(),
      ]);
    } catch (e, st) {
      ErrorLogger.log('Sink reconfigure after a policy change failed',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Hint for the next volume seed: the live route is a USB DAC even if
  /// AudioManager still reports a transient speaker. Set by the settings
  /// transition, which knows the target route; kept out of the method signature
  /// so existing handler mocks and callers stay source-compatible.
  bool expectedUsbRouteForVolumeSeed = false;

  /// Set by the sink-transition envelope: the rebuilt sink needs a fresh
  /// system-volume seed (entry) or just a re-apply of the known level (exit).
  bool seedVolumeOnNextRebuild = false;

  /// Reconcile the live transport without changing saved speed/pitch/silence
  /// choices. Set the boundary guard before awaiting any player writes.
  Future<void> setBitPerfectTransportPolicy(bool enabled) async {
    final expectedUsbRoute = expectedUsbRouteForVolumeSeed;
    final previous = _bitPerfectTransportBypass;
    _bitPerfectTransportBypass = enabled;
    try {
      if (enabled) {
        await cancelActiveCrossfade();
        await _applyPlaybackSpeed(1.0);
        await _applyPlaybackPitch(1.0);
        await Future.wait([
          _playerA.setSkipSilenceEnabled(false),
          _playerB.setSkipSilenceEnabled(false),
        ]);
        // Entering bypass shifts output gain ownership from the Android
        // STREAM_MUSIC mixer to the app/DAC path; seed [_volume] from the
        // system level immediately so playback cannot start at unity (1.0).
        // `forceSeed` is required: the saved Bit-Perfect preference is written
        // after this call, so [_shouldForwardSystemVolumeToOutput] still reads
        // the previous (off) value here.
        await _refreshLoudnessContourFromSystemVolume(
          forceUsbHardwareSeed: true,
          forceSeed: true,
          expectedUsbRoute: expectedUsbRoute,
        );
      } else if (previous == true) {
        // Leaving bypass must always release the Direct USB software stage.
        // The status stream may already have cleared [_lastDirectUsbVolume]
        // before this runs, and gating the reset on that value left the native
        // gain at the old (possibly 0.0) attenuation — audible as silence after
        // Bit-Perfect is turned off.
        if (PlatformCapabilities.isAndroid) {
          _lastDirectUsbVolume = -1.0;
          try {
            await AudioEffectsChannel().setDirectUsbVolume(1.0);
          } catch (_) {}
        }
        await restorePersistedSpeed();
        final skip = silenceSkipController.enabled;
        await Future.wait([
          _playerA.setSkipSilenceEnabled(skip),
          _playerB.setSkipSilenceEnabled(skip),
        ]);
      }
    } catch (_) {
      // A refused player write must not leave the boundary guard claiming a
      // policy the transport never applied; the caller rolls the mode back and
      // this flag gates every later speed/pitch/silence write.
      _bitPerfectTransportBypass = previous;
      rethrow;
    }
  }

  /// Stop both software fades and native curves even if the saved duration is
  /// already zero. Preserve the actual held gain, not the slider/RG target.
  Future<void> cancelActiveCrossfade() async {
    final heldGain = _activePlayer.volume;
    // The pause below exists only so the unobservable native curve can be
    // cleared without a gain jump; it must not outlive the cancel, or enabling
    // Bit-Perfect during the last seconds of a track stops audio dead.
    final wasPlaying = _activePlayer.playing;
    if (_crossfadeManager.isNativeCurveArmedOnOutgoing) {
      // The native curve's gain is unobservable. Clearing it while playing
      // could jump to full gain, so park playback on a buffer boundary first.
      await _activePlayer.pause();
    }
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: heldGain);
    setCrossfadeDuration(Duration.zero);
    if (wasPlaying) await _activePlayer.play();
  }

  /// Most recent ANDROID system STREAM_MUSIC volume ratio (0..1), fed by the
  /// [AudioEffectsChannel.onSystemVolumeChanged] stream and the explicit
  /// queries below. Null until the first reading. Lets the hot [setVolume]
  /// path drive the loudness contour from the hardware level without a
  /// per-call platform round-trip.
  double? _lastSystemVolumeRatio;

  /// Feeds the equal-loudness contour its driving volume. When the contour is
  /// engaged on Android it tracks the hardware STREAM_MUSIC volume so the lift
  /// actually responds to the phone's volume keys instead of the in-app
  /// software slider (default 100%, which left the lift inert). Falls back to
  /// the software [_volume] when the contour is off, off-Android, or no valid
  /// system reading is available yet.
  Future<void> _feedLoudnessContourVolume() async {
    double ratio = _volume; // software fallback
    if (PlatformCapabilities.isAndroid &&
        _equalizerManager.isLoudnessContourEnabled) {
      final sys = _lastSystemVolumeRatio;
      if (sys != null && sys.isFinite && sys >= 0.0) {
        ratio = sys;
      }
    }
    try {
      await _equalizerManager.updateLoudnessVolume(ratio);
    } catch (e, st) {
      ErrorLogger.log('Failed to feed loudness contour volume',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Queries the ANDROID system STREAM_MUSIC volume once and feeds it to the
  /// loudness contour (used on cold start and track start). Only queries while
  /// the contour is engaged on Android; otherwise defers to the software
  /// fallback in [_feedLoudnessContourVolume].
  /// Awaited before a queue/track load so a bypassed output (bit-perfect,
  /// AAudio, direct USB) never starts a track on a stale in-app volume.
  /// Bounded so a slow platform channel cannot delay playback noticeably.
  /// Whether [PulsrAudioHandler] should seed [_volume] from Android's system
  /// STREAM_MUSIC level before starting or switching into a bypassed output.
  /// Whether a STREAM_MUSIC reading belongs to the route the app is actually
  /// driving. Direct USB owns the DAC while Android may still report the
  /// speaker index (often 0) for a moment; seeding from that would mute the
  /// live stream. An unknown route keeps the previous level instead.
  @visibleForTesting
  static bool systemVolumeReadingBelongsToRoute({
    required bool directUsbStreaming,
    required bool routeKnown,
    required bool isUsb,
  }) =>
      !directUsbStreaming || !routeKnown || isUsb;

  @visibleForTesting
  static bool shouldSeedSystemVolume({
    required bool isAndroid,
    required bool dvcEnabled,
    required bool hardwareVolumeOwnsOutput,
    required bool forwardSystemVolume,
    bool forceUsbHardwareSeed = false,
    bool externalHardwareVolumeSet = false,
    bool forceSeed = false,
  }) {
    if (!isAndroid || dvcEnabled) return false;
    // A mode transition (Bit-Perfect on/off, sink rebuild) has just moved gain
    // ownership between Android's mixer and the app/DAC path. The saved
    // preference is written later in the transition, so reading it here would
    // skip the seed and leave the new sink at the 1.0 default.
    if (forceSeed) return true;
    if (!forwardSystemVolume) return false;
    if (!hardwareVolumeOwnsOutput) return true;
    return forceUsbHardwareSeed && !externalHardwareVolumeSet;
  }

  @override
  Future<void>? _syncOutputVolumeBeforeLoad() {
    final shouldSeed = shouldSeedSystemVolume(
      isAndroid: PlatformCapabilities.isAndroid,
      dvcEnabled: _dvcEnabled,
      hardwareVolumeOwnsOutput: _hardwareVolumeOwnsOutput(),
      forwardSystemVolume: _shouldForwardSystemVolumeToOutput(),
      forceUsbHardwareSeed: true,
      externalHardwareVolumeSet: _externalHardwareVolumeSet,
    );
    if (!shouldSeed) {
      return null;
    }
    return _refreshLoudnessContourFromSystemVolume(
      forceUsbHardwareSeed: true,
    ).timeout(const Duration(milliseconds: 400)).catchError((Object _) {
      // Best effort: the track-start / volume-event paths still correct it.
    });
  }

  Future<void> _refreshLoudnessContourFromSystemVolume({
    bool forceUsbHardwareSeed = false,
    bool forceSeed = false,
    bool expectedUsbRoute = false,
  }) async {
    final shouldSeed = shouldSeedSystemVolume(
      isAndroid: PlatformCapabilities.isAndroid,
      dvcEnabled: _dvcEnabled,
      hardwareVolumeOwnsOutput: _hardwareVolumeOwnsOutput(),
      forwardSystemVolume: _shouldForwardSystemVolumeToOutput(),
      forceUsbHardwareSeed: forceUsbHardwareSeed,
      externalHardwareVolumeSet: _externalHardwareVolumeSet,
      forceSeed: forceSeed,
    );
    if (PlatformCapabilities.isAndroid &&
        (_equalizerManager.isLoudnessContourEnabled || shouldSeed)) {
      try {
        final reading =
            await AudioEffectsChannel().getSystemMusicVolumeDetailed();
        // A route transition can make getStreamVolume() report the speaker's
        // index while Direct USB already owns the output. Never seed 0 from a
        // different route: keep the last level that belonged to this sink.
        final belongsToThisRoute = systemVolumeReadingBelongsToRoute(
          directUsbStreaming:
              UsbExclusiveService().lastStatus.streamingActive ||
                  expectedUsbRoute,
          routeKnown: reading.routeKnown,
          isUsb: reading.isUsb,
        );
        if (reading.isKnown && belongsToThisRoute) {
          _lastSystemVolumeRatio = reading.ratio;
        }
      } catch (e, st) {
        ErrorLogger.log('Failed to query system music volume for loudness',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    }
    // Bit-perfect / AAudio / direct-USB bypass Android's mixer, so the output
    // gain IS the system volume. [_volume] defaults to 1.0 and was only ever
    // updated by volume-key events, so the first track after launch (or after
    // enabling bit-perfect) played at full scale. Seed it from the system level,
    // and always push to hardware / active output even when [_volume] already
    // matches [sys] because a new track or reopened USB/DSP sink may have reset
    // its native/hardware gain to unity (1.0).
    final sys = _lastSystemVolumeRatio;
    if (shouldSeed && sys != null) {
      _volume = sys;
      if (!_volumeSubject.isClosed) _volumeSubject.add(_volume);
      _volumeController?.updateSettings(userVolume: _volume);
      await Future.wait([
        _pushUsbHardwareVolume(),
        _reapplyActiveVolume(),
      ]);
    }
    await _feedLoudnessContourVolume();
  }

  /// Re-applies the user/system level after a sink rebuild.
  ///
  /// `reconfigurePlaybackSink()` opens a fresh AudioTrack whose gain starts at
  /// unity. The Bit-Perfect transition already seeded the intended level, but
  /// the rebuilt sink must be told about it again or the first track after the
  /// toggle plays at 100% while the device volume is lower.
  Future<void> reapplyVolumeAfterSinkRebuild({
    bool? seedFromSystem,
    bool? expectedUsbRoute,
  }) async {
    final seed = seedFromSystem ?? seedVolumeOnNextRebuild;
    final routeIsUsb = expectedUsbRoute ?? expectedUsbRouteForVolumeSeed;
    // Only an entry transition needs a fresh read: the saved preference is
    // still "off" while the sink is being rebuilt, and the old sink may have
    // left the player at unity. Leaving Bit-Perfect must NOT re-read, because
    // the route is mid-restore and getStreamVolume() can report the speaker's
    // 0 for one event — which would silence the app right after it is turned
    // off. On exit the level was already seeded on the way in.
    if (seed) {
      await _refreshLoudnessContourFromSystemVolume(
        forceUsbHardwareSeed: true,
        forceSeed: true,
        expectedUsbRoute: routeIsUsb,
      );
    }
    await _pushUsbHardwareVolume();
    await _reapplyActiveVolume();
  }

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

  bool _hardwareVolumeOwned = false;
  bool? _usbHardwareVolumeOverride;
  bool _externalHardwareVolumeSet = false;
  double _lastDirectUsbVolume = -1.0;

  @override
  bool _isUsbHardwareVolumeEnabled() =>
      _usbHardwareVolumeOverride ??
      (_cachedPrefs?.getBool(PrefsKeys.usbHardwareVolumeEnabled) ?? false);

  @visibleForTesting
  static bool shouldForwardSystemVolumeToOutput({
    required bool bitPerfectBypass,
    required bool aaudioOutputEnabled,
    required bool directUsbStreaming,
  }) {
    // Shared AudioTrack lets Android's STREAM_MUSIC mixer scale analog level;
    // Direct USB, AAudio Exclusive, and Android 14+ bit-perfect direct paths
    // bypass that mixer, so physical volume keys must forward into output gain.
    return bitPerfectBypass || aaudioOutputEnabled || directUsbStreaming;
  }

  @override
  bool _shouldForwardSystemVolumeToOutput() {
    final prefs = _cachedPrefs;
    final bitPerfectEnabled = _isBitPerfectBypassEnabled() ||
        (prefs?.getBool(PrefsKeys.bitPerfectOutput) ?? false) ||
        (prefs?.getBool(PrefsKeys.strictBitPerfect) ?? false);
    return shouldForwardSystemVolumeToOutput(
      bitPerfectBypass: bitPerfectEnabled,
      aaudioOutputEnabled:
          prefs?.getBool(PrefsKeys.aaudioOutputEnabled) ?? false,
      directUsbStreaming: UsbExclusiveService().lastStatus.streamingActive,
    );
  }

  Future<void> _syncDirectUsbVolume(
    double appliedPlayerVolume, {
    SongsTableData? song,
  }) async {
    if (!PlatformCapabilities.isAndroid) return;
    final streamingUsb = UsbExclusiveService().lastStatus.streamingActive;
    final bitPerfectArmed = _isBitPerfectBypassEnabled() ||
        (_cachedPrefs?.getBool(PrefsKeys.bitPerfectOutput) ?? false) ||
        (_cachedPrefs?.getBool(PrefsKeys.strictBitPerfect) ?? false);
    if (!streamingUsb && !bitPerfectArmed) {
      if (_lastDirectUsbVolume >= 0.0 &&
          (_lastDirectUsbVolume - 1.0).abs() >= 1e-6) {
        await AudioEffectsChannel().setDirectUsbVolume(1.0);
      }
      _lastDirectUsbVolume = -1.0;
      return;
    }
    final directGain =
        (!_hardwareVolumeOwnsOutput() && !_isSongDopActive(song ?? currentSong))
            ? appliedPlayerVolume.clamp(0.0, 1.0)
            : 1.0;
    if (_lastDirectUsbVolume >= 0.0 &&
        (_lastDirectUsbVolume - directGain).abs() < 1e-6) {
      return;
    }
    _lastDirectUsbVolume = directGain;
    await AudioEffectsChannel().setDirectUsbVolume(directGain);
  }

  /// Applies [targetVolume] (scaled by [_sleepFadeFactor]) to both [player]
  /// and the native Direct USB gain stage so track starts, gapless transitions,
  /// and live volume updates never diverge.
  ///
  /// [smooth] ramps the player gain instead of stepping it. A policy-only gain
  /// change (Bit-Perfect, the DSP bypass or a ReplayGain mode) must ramp: the
  /// new target can differ by several dB, and a step at an arbitrary sample is
  /// audible as a click. On that path the Direct USB stage is synced first and
  /// awaited, so the hardware gain and the software ramp never disagree.
  @override
  Future<void> _applyPlayerOutputVolume(
    AudioPlayer player,
    double targetVolume, {
    SongsTableData? song,
    bool smooth = false,
  }) async {
    final applied = (targetVolume * _sleepFadeFactor).clamp(0.0, 1.0);
    if (_isUsbHardwareVolumeEnabled()) {
      unawaited(_pushUsbHardwareVolume());
    }
    final controller = _volumeController;
    if (smooth && controller != null) {
      await _syncDirectUsbVolume(applied, song: song);
      await controller.applyVolume(player, applied, smoothTransition: true);
      return;
    }
    await Future.wait([
      _syncDirectUsbVolume(applied, song: song),
      player.setVolume(applied).catchError((Object e) {
        // A concurrent sink rebuild (reconfigurePlaybackSink) can momentarily
        // dispose the old just_audio platform channel; ignore MissingPluginException.
        if (e is! MissingPluginException) throw e;
      }),
    ]);
  }

  Future<void> _onDirectUsbStreamingStarted(UsbExclusiveStatus status) async {
    if (_disposed) return;
    // Seed [_volume] from Android STREAM_MUSIC before pushing hardware or
    // Direct USB software gain so a freshly opened stream (cold start,
    // follow-track rate change, or toggle) never starts at unity (1.0).
    if (!_dvcEnabled) {
      await _refreshLoudnessContourFromSystemVolume(
        forceUsbHardwareSeed: true,
      );
    }
    if (_disposed) return;
    if (_isUsbHardwareVolumeEnabled() && !status.hardwareVolumeApplied) {
      await _pushUsbHardwareVolume();
    }
    if (_disposed) return;
    // Always sync the freshly opened Direct USB stream (unless hardware volume
    // already owns output, in which case _syncDirectUsbVolume resets to 1.0)
    // so DACs without UAC2 volume control attenuate immediately.
    _lastDirectUsbVolume = -1.0;
    await _reapplyActiveVolume();
  }

  /// The native DSP applies [directUsbGain] on the ordinary path as well, not
  /// only during the direct-USB tee. If the sink stops (disabled, unplugged or
  /// a fault) while that software gain is still below unity, normal playback
  /// stays attenuated — and a gain of 0 leaves it silent after Bit-Perfect is
  /// turned off. Reset the native stage to unity and re-apply the app volume.
  Future<void> _resetDirectUsbGainAfterStop() async {
    // The old `bitPerfectArmed` guard read preferences that are written after
    // the stream has already stopped, so it skipped the reset on the exact
    // transition that needed it. The native stage is gated by
    // bitPerfect.directUsbActive, so resetting to unity unconditionally is
    // safe and keeps a stale 0.0 from silencing the ordinary path.
    if (!UsbExclusiveService().lastStatus.streamingActive) {
      try {
        await AudioEffectsChannel().setDirectUsbVolume(1.0);
      } catch (e, st) {
        ErrorLogger.log('Failed to reset direct USB software gain',
            error: e, stackTrace: st, category: 'AudioHandler');
      }
    }
    if (_disposed) return;
    try {
      await setVolume(_volume);
    } catch (e, st) {
      ErrorLogger.log('Failed to re-apply volume after direct USB stop',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Software gain may only be released when the DAC itself is holding the
  /// level: a saved preference plus a USB route proves neither permission,
  /// capability, nor a value that actually landed in the hardware register.
  bool _hardwareVolumeOwnsOutput() {
    if (!_isUsbHardwareVolumeEnabled()) {
      return false;
    }
    final usb = UsbExclusiveService().lastStatus;
    return usb.attached &&
        usb.permitted &&
        usb.streamingActive &&
        usb.hardwareVolumeApplied;
  }

  /// True while the DAC's own Feature Unit is the active attenuator. Used by
  /// the mute layer to choose CS_MUTE over a software volume of zero.
  bool get usbHardwareVolumeOwned => _hardwareVolumeOwnsOutput();

  /// Last DAC CS_MUTE state, when the device exposed one.
  bool? get usbHardwareMute => UsbExclusiveService().lastStatus.hardwareMute;

  /// Mutes/unmutes the DAC's Feature Unit (CS_MUTE) when it is the active
  /// attenuator. Returns false when the device has no mute control.
  Future<bool> setUsbHardwareMute(bool muted) async {
    if (!PlatformCapabilities.isAndroid) return false;
    return const HiresDacBridge().setUac2HardwareMute(muted);
  }

  void _syncVolumeControllerSettings() {
    final prefs = _cachedPrefs;
    final bitPerfect = _isBitPerfectBypassEnabled();
    final hardwareVolume = _hardwareVolumeOwnsOutput();
    _volumeController?.updateSettings(
      userVolume: _volume,
      replayGainMode: prefs?.getString(PrefsKeys.replayGainMode) ?? 'off',
      preampWithRg: prefs?.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
      preampWithoutRg:
          prefs?.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? -3.0,
      duckFactor: duckingController.duckFactor,
      isDucked: _duckActive,
      nativeRgActive: _nativeRgActive && Platform.isAndroid,
      dvcEnabled: _dvcEnabled,
      isDopActive: _isSongDopActive(currentSong),
      bitPerfectBypass: bitPerfect,
      hardwareVolumeActive: hardwareVolume,
    );
  }

  @override
  double _calculateReplayGainVolume(SongsTableData? song) {
    _syncVolumeControllerSettings();
    final controller = _volumeController;
    if (controller != null) {
      final perSongDb = song != null ? _perSongVolumeDbFor(song) : 0.0;
      final boostFoldedIntoDvc = _dvcEnabled && perSongDb > 0.0;
      final target = controller.calculateTargetVolume(
        song,
        albumContext: _isConsecutiveAlbumPlayback(),
        perSongOffsetDb: boostFoldedIntoDvc ? 0.0 : perSongDb,
      );
      if (_dvcEnabled && (song == null || song.id == currentSong?.id)) {
        final dvcGain = boostFoldedIntoDvc
            ? (_volume * math.pow(10.0, perSongDb / 20.0)).clamp(0.0, 4.0)
            : _volume;
        unawaited(_pushDvcGain(dvcGain));
      }
      return target;
    }

    if (_isSongDopActive(song)) return 1.0;
    if (song == null) {
      if (_dvcEnabled) {
        unawaited(_pushDvcGain(_volume));
        return 1.0;
      }
      return _volume;
    }
    final prefs = _cachedPrefs;
    if (prefs == null) return _volume;
    final bitPerfect = _isBitPerfectBypassEnabled();
    if (bitPerfect) {
      return _hardwareVolumeOwnsOutput() ? 1.0 : _volume;
    }
    if (_nativeRgActive && Platform.isAndroid) {
      final perSongDb = _perSongVolumeDbFor(song);
      if (_dvcEnabled) {
        if (song.id == currentSong?.id) {
          unawaited(_pushDvcGain(_volume));
        }
        if (perSongDb == 0.0) return 1.0;
        return math.pow(10, perSongDb / 20).toDouble().clamp(0.0, 1.0);
      }
      var base = _volume;
      if (perSongDb != 0.0) {
        base = (base * math.pow(10, perSongDb / 20).toDouble()).clamp(0.0, 1.0);
      }
      return base;
    }
    final dvc = _dvcEnabled;
    var scaled = ReplayGainMath.apply(
      mode: prefs.getString(PrefsKeys.replayGainMode) ?? 'off',
      volume: dvc ? 1.0 : _volume,
      trackGainDb: song.replayGainTrack,
      trackPeak: song.replayGainTrackPeak,
      albumGainDb: song.replayGainAlbum,
      albumPeak: song.replayGainAlbumPeak,
      albumContext: _isConsecutiveAlbumPlayback(),
      preampWithRg: prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
      preampWithoutRg:
          prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? -3.0,
    );
    try {
      final perSongDb = _perSongVolumeDbFor(song);
      if (perSongDb != 0.0) {
        final factor = math.pow(10, perSongDb / 20).toDouble();
        scaled = (scaled * factor).clamp(0.0, 1.0);
      }
    } catch (_) {}
    if (dvc && song.id == currentSong?.id) {
      unawaited(_pushDvcGain(_volume));
    }
    return scaled;
  }

  /// Pushes the user-volume component to the native Direct Volume Control
  /// stage (applied in the float DSP path). ReplayGain/per-song/fades stay in
  /// the player mixer.
  Future<void> _pushDvcGain(double gain) async {
    try {
      await AudioEffectsChannel().setDvcGain(gain.clamp(0.0, 4.0));
    } catch (e, st) {
      ErrorLogger.log('Failed to push DVC gain to native channel',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
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
    _volumeController?.setNativeRgActive(_nativeRgActive);
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
    if (_isSongDopActive(song)) {
      await disableNative();
      return;
    }
    final prefs = _cachedPrefs;
    if (prefs == null || song == null) {
      await disableNative();
      return;
    }
    final bitPerfect = _isBitPerfectBypassEnabled();
    if (bitPerfect) {
      await disableNative();
      return;
    }
    final mode = prefs.getString(PrefsKeys.replayGainMode) ?? 'off';
    if (mode == 'off') {
      await disableNative();
      return;
    }
    try {
      final albumContext = _isConsecutiveAlbumPlayback();
      var effectiveTrackGainDb = song.replayGainTrack;
      if (effectiveTrackGainDb == null &&
          song.source == SongSource.youtube &&
          song.remoteId != null) {
        final ytmService =
            getIt.isRegistered<YtmService>() ? getIt<YtmService>() : null;
        final loudnessDb = ytmService?.getLoudnessDb(song.remoteId!);
        if (loudnessDb != null && loudnessDb.isFinite) {
          effectiveTrackGainDb = -loudnessDb;
        }
      }
      final applied = await AudioEffectsChannel().setReplayGainParams(
        mode: ReplayGainMath.nativeModeFor(mode, albumContext: albumContext),
        // ReplayGain tags come from arbitrary file metadata / the scanner and
        // can be corrupt (NaN, ±inf, absurd magnitudes). The Dart mixer maths
        // sanitizes them, but the native pre-gain stage consumes the raw
        // doubles: one NaN poisons its smoothed gain for the rest of the
        // session, turning every following track into noise. Sanitize here.
        trackGainDb: ReplayGainMath.sanitizeGainDb(effectiveTrackGainDb),
        albumGainDb: ReplayGainMath.sanitizeGainDb(song.replayGainAlbum),
        trackPeak: ReplayGainMath.sanitizePeak(song.replayGainTrackPeak),
        albumPeak: ReplayGainMath.sanitizePeak(song.replayGainAlbumPeak),
        preAmpDb: ReplayGainMath.sanitizeGainDb(ReplayGainMath.nativePreAmpFor(
          mode: mode,
          trackGainDb: effectiveTrackGainDb,
          albumGainDb: song.replayGainAlbum,
          albumContext: albumContext,
          preampWithRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0,
          preampWithoutRg:
              prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? -3.0,
        )),
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

  DateTime? _lastNativeRgPush;
  int? _lastNativeRgSongId;

  bool _usbHwVolumeBusy = false;
  bool _usbHwVolumeDirty = false;

  /// Drives the DAC's hardware attenuator from the player volume while
  /// USB bit-perfect streaming is active, so the in-app slider keeps working
  /// when software gain is released. Latest-wins: at most one control transfer
  /// is in flight and a drag collapses to its final value.
  Future<void> _pushUsbHardwareVolume() async {
    if (!PlatformCapabilities.isAndroid) return;
    if (!_isUsbHardwareVolumeEnabled()) {
      return;
    }
    _usbHwVolumeDirty = true;
    if (_usbHwVolumeBusy) return;
    _usbHwVolumeBusy = true;
    try {
      while (_usbHwVolumeDirty && !_disposed) {
        _usbHwVolumeDirty = false;
        final usb = UsbExclusiveService().lastStatus;
        final min = usb.minVolumeDb;
        final max = usb.maxVolumeDb;
        if (!usb.attached ||
            !usb.permitted ||
            !usb.streamingActive ||
            !usb.hasVolumeControl ||
            min == null ||
            max == null) {
          return;
        }
        await UsbExclusiveService().setHardwareVolume(
          UsbHardwareVolumeCurve.dbFor(_volume, minDb: min, maxDb: max),
        );
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to push USB hardware volume',
          error: e, stackTrace: st, category: 'AudioHandler');
    } finally {
      _usbHwVolumeBusy = false;
    }
  }

  // --- User-forced battery saver -----------------------------------------
  // The automatic policy below 15 % / 5 % is untouched; this is an explicit
  // override that pins the same essential-only DSP profile. Persisted so a
  // restart does not silently restore the heavy stages.

  bool get batterySaverForced => _batterySaverForced;

  /// Applies (or lifts) the user's battery-saver profile.
  ///
  /// Lifting is a no-op while the automatic policy is degraded: that state is
  /// owned by [BatteryAwarePlayback] and is restored by its own callback.
  Future<void> setBatterySaverForced(bool enabled) async {
    _batterySaverForced = enabled;
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setBool(PrefsKeys.batterySaverEnabled, enabled);
    } catch (e, st) {
      ErrorLogger.log('Failed to persist battery saver preference',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    try {
      if (enabled) {
        await _equalizerManager.degradeToEssentials();
      } else if (_batteryAwarePlayback.currentLevel ==
          BatteryOptimizationLevel.normal) {
        await _equalizerManager.restoreFromDegrade();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to apply battery saver state',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Sets the true low-power route on both players and persists the preference.
  Future<void> setLowPowerRoute(bool enabled) async {
    await _equalizerManager.setLowPowerRoute(enabled);
    await Future.wait([
      _playerA.dspSetLowPowerRoute(enabled),
      _playerB.dspSetLowPowerRoute(enabled),
    ]);
  }

  /// Re-applies the stored override after the equalizer has loaded its own
  /// state; running it earlier would let init restore the heavy stages.
  Future<void> _restoreBatterySaverPreference() async {
    try {
      final prefs = _cachedPrefs ?? await SharedPreferences.getInstance();
      _batterySaverForced =
          prefs.getBool(PrefsKeys.batterySaverEnabled) ?? false;
      if (_batterySaverForced) {
        await _equalizerManager.degradeToEssentials();
      }
    } catch (e, st) {
      ErrorLogger.log('Failed to restore battery saver preference',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Synchronizes active gain stages immediately when [usbHardwareVolumeEnabled]
  /// is toggled in Settings so disabling hardware volume resets the DAC Feature
  /// Unit to 0 dB and restores Direct USB/software attenuation without a jump.
  Future<void> syncUsbHardwareVolumeState(bool enabled) async {
    _usbHardwareVolumeOverride = enabled;
    if (PlatformCapabilities.isAndroid) {
      await UsbExclusiveService().setUsbHardwareVolumeEnabled(enabled);
    }
    if (!enabled) {
      _externalHardwareVolumeSet = false;
      if (PlatformCapabilities.isAndroid) {
        await UsbExclusiveService().resetHardwareVolume();
      }
    }
    if (enabled) {
      if (!_dvcEnabled) {
        await _refreshLoudnessContourFromSystemVolume(
          forceUsbHardwareSeed: true,
        );
      }
      await _pushUsbHardwareVolume();
    }
    _hardwareVolumeOwned = _hardwareVolumeOwnsOutput();
    _syncVolumeControllerSettings();
    await _reapplyActiveVolume();
  }

  /// Keeps [_volume] synchronized when the user drags the USB DAC hardware
  /// slider in Settings without echoing back into [setHardwareVolume].
  void syncVolumeFromExternalHardwareDb(
    double db, {
    required double minDb,
    required double maxDb,
  }) {
    final linear = UsbHardwareVolumeCurve.linearFor(
      db,
      minDb: minDb,
      maxDb: maxDb,
    );
    if (!linear.isFinite) return;
    _externalHardwareVolumeSet = true;
    _volume = linear.clamp(0.0, 1.0);
    if (!_volumeSubject.isClosed) {
      _volumeSubject.add(_volume);
    }
    _volumeController?.updateSettings(userVolume: _volume);
  }

  /// Sets the user-facing volume and re-applies the composed output gain.
  Future<void> setVolume(double volume) => _setVolumeInternal(volume);

  /// Re-applies the current gain with a short ramp instead of a step.
  ///
  /// A policy-only gain change (Bit-Perfect, the DSP bypass or a ReplayGain
  /// mode) can move the composed target by several dB; applying it through
  /// [setVolume] would step the gain in one sample, which is audible as a
  /// click. Kept as a separate entry point so the existing [setVolume]
  /// signature (and the fakes that implement it) stay untouched.
  Future<void> setVolumeSmooth(double volume) =>
      _setVolumeInternal(volume, smooth: true);

  Future<void> _setVolumeInternal(double volume, {bool smooth = false}) async {
    // NaN.clamp() returns NaN, which would poison every composed gain after it.
    _externalHardwareVolumeSet = false;
    _volume = volume.isFinite ? volume.clamp(0.0, 1.0) : _volume;
    if (!_volumeSubject.isClosed) {
      _volumeSubject.add(_volume);
    }
    if (!_effectsReadyCompleter.isCompleted) {
      await _effectsReadyCompleter.future;
    }
    final song = currentSong;
    final now = DateTime.now();
    if (smooth ||
        _lastNativeRgPush == null ||
        _lastNativeRgSongId != song?.id ||
        now.difference(_lastNativeRgPush!) > const Duration(seconds: 2)) {
      _lastNativeRgPush = now;
      _lastNativeRgSongId = song?.id;
      await _pushNativeReplayGain(song);
    }
    unawaited(_pushUsbHardwareVolume());
    final target = _calculateReplayGainVolume(song);
    _volumeController?.updateSettings(userVolume: _volume);
    try {
      // Loudness contour tracks the hardware (system) volume when engaged;
      // this feeds it the system ratio (or the software [_volume] as fallback).
      await _feedLoudnessContourVolume();
    } catch (e, st) {
      ErrorLogger.log('Failed to update loudness volume in setVolume',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
    if (!_crossfadeManager.isCrossfading) {
      await _applyPlayerOutputVolume(
        _activePlayer,
        target,
        song: song,
        smooth: smooth,
      );
    }
  }

  /// Single re-apply point for the ACTIVE player's volume, composing the
  /// duck-aware ReplayGain/user target ([_calculateReplayGainVolume] already
  /// folds in the active duck factor via the volume controller) with the
  /// current sleep-fade factor. Routing duck-end and each sleep-fade tick
  /// through here means a duck-end can no longer wipe an in-flight fade for a
  /// tick, and a fade tick can no longer undo the duck.
  ///
  /// No-op while a crossfade is running: the CrossfadeManager owns both
  /// players' live volume ramps then (same contract the duck-end guard uses),
  /// so this must not fight it.
  @override
  Future<void> _reapplyActiveVolume() async {
    if (_crossfadeManager.isCrossfading) return;
    final song = currentSong;
    final target = _calculateReplayGainVolume(song);
    try {
      await _applyPlayerOutputVolume(_activePlayer, target, song: song);
    } catch (e, st) {
      ErrorLogger.log('Failed to re-apply active player volume',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  /// Resets every piece of duck bookkeeping in one place so the interruption
  /// paths (pause end, unknown end, stop) cannot forget a field and leave a
  /// stale timer or captured volume behind.
  void _clearDuckState() {
    _duckSafetyTimer?.cancel();
    _duckSafetyTimer = null;
    _systemSoundTimer?.cancel();
    _systemSoundTimer = null;
    _duckActive = false;
    _duckDepthCounter = 0;
    _preDuckVolume = null;
    _preDuckInactiveVolume = null;
    _preDuckSongId = null;
    _preDuckRgTarget = null;
    _volumeController?.updateSettings(isDucked: false);
  }

  /// Seeds the app/software volume from the device's live STREAM_MUSIC level
  /// before DVC takes ownership.
  ///
  /// DVC pins the system stream to max and moves the user level into the DSP
  /// gain. Without this seed the first gain push is the 1.0 default and the
  /// output jumps to full scale — the "sometimes gets the highest, not the
  /// device volume" report — instead of carrying the level the device is
  /// actually at.
  Future<void> _seedVolumeFromSystemForDvc() async {
    if (!PlatformCapabilities.isAndroid) return;
    try {
      final sys = await AudioEffectsChannel()
          .getSystemMusicVolume()
          .timeout(const Duration(milliseconds: 400));
      if (!sys.isFinite || sys < 0.0) return; // unknown: keep current level
      _volume = sys.clamp(0.0, 1.0);
      _lastSystemVolumeRatio = _volume;
      if (!_volumeSubject.isClosed) _volumeSubject.add(_volume);
      _volumeController?.updateSettings(userVolume: _volume);
    } catch (e, st) {
      ErrorLogger.log('Failed to seed volume before DVC',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
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
        _volumeController?.setDvcEnabled(false);
        await AudioEffectsChannel().setDvcEnabled(false);
        return;
      }
      // Carry the device level into the gain before the stream is pinned to
      // max, or the DSP gets unity and playback jumps to full volume.
      await _seedVolumeFromSystemForDvc();
      _dvcEnabled = true;
      _volumeController?.setDvcEnabled(true);
      await AudioEffectsChannel().setDvcEnabled(true);
    } else {
      _dvcEnabled = false;
      _volumeController?.setDvcEnabled(false);
      await AudioEffectsChannel().setDvcEnabled(false);
      if (_shouldForwardSystemVolumeToOutput() &&
          (_volume - 1.0).abs() < 1e-4) {
        final volumeSync = _syncOutputVolumeBeforeLoad();
        if (volumeSync != null) await volumeSync;
      }
    }
    // Re-apply the current volume so the new gain stage takes effect now.
    await setVolume(_volume);
  }

  @override
  int _engineSwitchGeneration = 0;
  @override
  bool _pendingPlaybackStart = false;

  /// Whether a completion report at [now] is distinct from a previous one at
  /// [last]. Split out so the debounce window is unit-testable.
  @visibleForTesting
  static bool isDistinctSleepCompletion(DateTime? last, DateTime now) =>
      last == null ||
      now.difference(last) >= const Duration(milliseconds: 1500);

  /// Guard for the automatic-skip cascade: halt once enough consecutive tracks
  /// have failed (or the whole queue has), or when the rapid-advance circuit
  /// breaker has tripped.
  ///
  /// Extracted so the invariant that error-driven gapless advances must NOT
  /// reset the failure budget is covered by a unit test: if a caller zeroes the
  /// counter on every auto-advance (as `_onGaplessIndexChanged` used to), this
  /// predicate can never become true and a dead queue skips forever.
  @visibleForTesting
  static bool shouldHaltFailureCascade({
    required int consecutiveFailures,
    required int rapidGaplessChanges,
    required int queueLength,
  }) =>
      consecutiveFailures >= 3 ||
      (queueLength > 0 && consecutiveFailures >= queueLength) ||
      rapidGaplessChanges >= 1;

  Future<void> onAppPaused() async {
    await saveCurrentPositionImmediate();
    await _equalizerManager.onAppPaused();
  }

  @override
  Future<Map<String, dynamic>?> _readCrashPositionRecovery() =>
      _positionPersister.readCrashPositionRecovery();

  @override
  double _userBaseSpeed = 1.0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final observer = _lifecycleObserver;
    if (observer != null) {
      observer.didChangeAppLifecycleState(state);
      return;
    }
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(saveCurrentPositionImmediate());
    }
  }

  /// Serialized + coalesced: the 2s timer, [didChangeAppLifecycleState] and the
  /// lifecycle observer can all fire together on backgrounding.
  @override
  Future<void> saveCurrentPositionImmediate() =>
      _positionPersister.saveCurrentPositionImmediate();

  @override
  void _saveCurrentPosition() {
    _playbackStateCoordinator.markPositionDirty();
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

  /// Returns a currently-valid stream URL for a YouTube row, reusing the
  /// shared [YtmUrlCache] entry until it nears expiry. Throws [YtmException]
  /// when nothing usable comes back, so the caller can tell "network down"
  /// from "skip this track".
  ///
  /// Delegated to [_streamResolutionPipeline] for gating and in-flight
  /// deduplication.
  /// [quality] is reported back because it is part of every downstream cache key
  /// ([YtmUrlCache], the disk cache slot); the caller cannot assume `high`.
  @override
  Future<({String url, String? userAgent, String? cookies, String quality})>
      _resolveStreamUrl(SongsTableData song,
          {bool forceRefresh = false}) async {
    final prefs = _cachedPrefs ??= await SharedPreferences.getInstance();
    return _streamResolutionPipeline.resolveStreamUrl(
      song,
      forceRefresh: forceRefresh,
      prefs: prefs,
      quality: _currentStreamingQuality(),
    );
  }

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

  // --- ANDROID AUTO & HEADSET BUTTON SUPPORT ---
  @override
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
  @override
  Future<void> get effectsReady => _effectsReadyCompleter.future;

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleFavorite':
        if (_songs.isNotEmpty &&
            _currentIndex >= 0 &&
            _currentIndex < _songs.length) {
          final currentSong = _songs[_currentIndex];
          final toggleUseCase = getIt.isRegistered<ToggleFavoriteUseCase>()
              ? getIt<ToggleFavoriteUseCase>()
              : ToggleFavoriteUseCase(_repository);
          final result = await toggleUseCase(currentSong.id);
          final newFav = result.fold((l) => currentSong.isFavorite, (r) => r);
          // Centralized so mediaItem, queue and notification controls all update.
          updateFavorite(currentSong.id, newFav);
          return newFav;
        }
        return false;
      case 'toggleShuffle':
        final isShuffle =
            playbackState.value.shuffleMode == AudioServiceShuffleMode.all;
        await setShuffleMode(isShuffle
            ? AudioServiceShuffleMode.none
            : AudioServiceShuffleMode.all);
        return !isShuffle;
      case 'cycleRepeat':
      case 'toggleRepeat':
        final currentRepeat = playbackState.value.repeatMode;
        if (currentRepeat == AudioServiceRepeatMode.none) {
          await setRepeatMode(AudioServiceRepeatMode.all);
        } else if (currentRepeat == AudioServiceRepeatMode.all ||
            currentRepeat == AudioServiceRepeatMode.group) {
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
      case 'setSpeed':
        final speed = (extras?['speed'] as num?)?.toDouble() ?? 1.0;
        await setSpeed(speed);
        return true;
      case 'action_bass_boost':
      case 'toggleBassBoost':
      case 'bassBoost':
        final current = _equalizerManager.currentPreset.bassBoost;
        final enable = extras?['enable'] as bool? ?? (current <= 0.05);
        // When disabling, always force 0: a stray `strength` in extras used to
        // leave bass boost active while this action reported `false`.
        final strength =
            enable ? ((extras?['strength'] as num?)?.toDouble() ?? 0.6) : 0.0;
        await _equalizerManager.setBassBoost(strength);
        return enable;
      case 'action_virtualizer':
      case 'toggleVirtualizer':
      case 'virtualizer':
        final enable = extras?['enable'] as bool? ??
            !_equalizerManager.isVirtualizerEnabled;
        final strength = (extras?['strength'] as num?)?.toDouble() ?? 0.5;
        await _equalizerManager.setVirtualizerEnabled(enable);
        if (enable) await _equalizerManager.setVirtualizerStrength(strength);
        return enable;
      case 'action_sleep_timer':
      case 'toggleSleepTimer':
      case 'sleepTimer':
        if (_sleepTimerManager.isActive) {
          cancelSleepTimer();
          return false;
        } else {
          // 0 / negative would fire immediately and pause playback at once.
          final minutes =
              ((extras?['minutes'] as num?)?.toInt() ?? 30).clamp(1, 24 * 60);
          startSleepTimer(Duration(minutes: minutes));
          return true;
        }
      case 'cycleSpeed':
        final currentSpeed = userBaseSpeed;
        final nextSpeed =
            currentSpeed < 1.15 ? 1.25 : (currentSpeed < 1.4 ? 1.5 : 1.0);
        await setSpeed(nextSpeed);
        return nextSpeed;
      case 'switchEqPreset':
        final presets = EqPreset.defaultPresets;
        if (presets.isEmpty) return null;
        final current = _equalizerManager.currentPreset;
        final idx = presets.indexWhere((p) => p.name == current.name);
        final next = presets[(idx + 1) % presets.length];
        await _equalizerManager.applyPreset(next);
        return next.name;
      case 'cycleSleepTimer':
        if (!_sleepTimerManager.isActive) {
          startSleepTimer(const Duration(minutes: 15));
          return 15;
        } else {
          final curRemaining = _sleepTimerManager.remainingDuration.inSeconds;
          if (curRemaining <= 15 * 60) {
            startSleepTimer(const Duration(minutes: 30));
            return 30;
          } else if (curRemaining <= 30 * 60) {
            startSleepTimer(const Duration(minutes: 45));
            return 45;
          } else {
            cancelSleepTimer();
            return 0;
          }
        }
      default:
        return super.customAction(name, extras);
    }
  }

  @override
  Future<void> stop() async {
    await _stopImpl();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Route through the public pause path so it performs the same cleanup as a
    // user pause: reset the interruption bookkeeping, cancel any crossfade and
    // bump the play generation so a slow in-flight resolve cannot start
    // playback after the task is gone (B-3).
    try {
      await pause();
    } catch (_) {}
    // Save AFTER pausing: saving first let the track keep playing during the
    // DB/file writes, so the stored position was already stale on resume.
    try {
      await saveCurrentPositionImmediate();
    } catch (_) {}
    await super.onTaskRemoved();
  }

  /// Android Auto / Bluetooth heart control (`ACTION_SET_RATING`). Pulsr maps
  /// the heart rating onto the favorite flag so the car's toggle stays in sync
  /// with the app. Star/percentage ratings are not used by the library yet.
  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) =>
      _setRatingImpl(rating, extras);

  @disposeMethod
  Future<void> dispose() => _disposeImpl();

  /// Transient system sound interruption: duck and auto-restore in 500ms.
  Future<void> handleSystemUiSoundInterruption() =>
      _handleSystemUiSoundInterruptionImpl();

  /// Media button long-press: pause playback without clearing queue or position.
  Future<void> handleMediaButtonLongPress() async {
    await pause();
  }

  /// Queries the actual platform audio focus state via platform channel.
  Future<bool> getPlatformFocusState() =>
      AudioEffectsChannel().getFocusState();
}
