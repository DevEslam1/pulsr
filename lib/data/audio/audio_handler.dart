// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/di/injection.dart';
import '../../core/errors/ytm_error_classifier.dart';
import '../../core/services/ytm_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/genre_item.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';
import 'audio_effects_channel.dart';
import 'crossfade_manager.dart';
import 'equalizer_manager.dart';
import 'sleep_timer_manager.dart';
import 'ytm_resolving_source.dart';
import '../../core/services/ytm_cache_manager.dart';
import 'adaptive_buffer_engine.dart';
import 'audio_memory_manager.dart';
import 'battery_aware_playback.dart';
import 'format_aware_decoder.dart';
import 'latency_optimizer.dart';
import 'optimized_dsp_pipeline.dart';
import 'playback_analytics.dart';
import 'seamless_queue_transition.dart';
import 'smart_preload_scheduler.dart';
import 'triple_buffer_pipeline.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  @factoryMethod
  @preResolve
  static Future<PulsrAudioHandler> create(
      IMusicRepository repository, YtmService ytmService) async {
    return await AudioService.init(
      builder: () => PulsrAudioHandler(repository, ytmService),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.pulsr.music.audio',
        androidNotificationChannelName: 'Pulsr Audio Playback',
        androidNotificationOngoing: false,
        androidNotificationClickStartsActivity: true,
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
        androidNotificationIcon: 'drawable/ic_notification',
      ),
    );
  }

  final AudioPlayer _playerA;
  final AudioPlayer _playerB;
  bool _isPlayerAActive = true;

  AudioPlayer get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  AudioPlayer get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;

  final IMusicRepository _repository;
  final YtmService _ytmService;
  final CrossfadeManager _crossfadeManager = CrossfadeManager();
  final SleepTimerManager _sleepTimerManager = SleepTimerManager();
  late final EqualizerManager _equalizerManager;

  List<SongsTableData> _songs = [];
  int _currentIndex = 0;
  bool _queueDirty = false;
  double? _preDuckVolume;
  int _consecutiveFailures = 0;
  DateTime? _lastGaplessChangeTime;
  int _rapidGaplessChangeCount = 0;
  final List<int> _shuffleHistory = [];
  bool _wasPlayingBeforeInterruption = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  int _playGeneration = 0;
  _AudioHandlerLifecycleObserver? _lifecycleObserver;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  Duration? _pendingLazyPosition;
  // Memoized stream URLs, keyed by video id. Never persisted — they expire.
  final Map<String, ({String url, DateTime expires, String? userAgent, String? cookies})> _streamCache = {};
  // Video ids with an in-flight prefetch, so we resolve each at most once.
  final Set<String> _prefetching = {};

  final AdaptiveBufferEngine _adaptiveBufferEngine = AdaptiveBufferEngine();
  final OptimizedDspPipeline _dspPipeline = OptimizedDspPipeline();
  late final PlaybackAnalytics _playbackAnalytics;
  late final AudioMemoryManager _memoryManager;
  late final SmartPreloadScheduler _preloadScheduler;
  late final FormatAwareDecoder _formatDecoder;
  late final TripleBufferPipeline _tripleBufferPipeline;
  late final BatteryAwarePlayback _batteryAwarePlayback;
  late final SeamlessQueueTransition _queueTransition;

  // Gapless engine: when crossfade is off, a ConcatenatingAudioSource on the
  // active player is the source of truth for track order/advance, and just_audio
  // joins consecutive items seamlessly. Null while crossfade (duration > 0) is
  // active, which keeps the manual dual-player path below.
  ConcatenatingAudioSource? _gaplessSource;
  // Last index reacted to from currentIndexStream, to drop duplicate emits.
  int _lastGaplessIndex = -1;

  /// Gapless is the default engine. Enabling crossfade (duration > 0) switches
  /// to the overlapping dual-player engine, which cannot also produce a seamless
  /// join, so the two are mutually exclusive by construction.
  bool get _gaplessMode => _crossfadeManager.duration <= Duration.zero;

  Timer? _savePositionDebounce;
  final StreamController<Duration> _positionSubject =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionSubject.stream;
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
  int _lastPositionEmitMs = 0;
  double? _preCrossfadeVolume;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PulsrAudioHandler._({
    required IMusicRepository repository,
    required YtmService ytmService,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
  })  : _repository = repository,
        _ytmService = ytmService,
        _playerA = playerA,
        _playerB = playerB {
    _equalizerManager = EqualizerManager(
      loudnessEnhancerA: loudnessEnhancerA,
      loudnessEnhancerB: loudnessEnhancerB,
    );
    if (getIt.isRegistered<EqualizerManager>()) {
      getIt.unregister<EqualizerManager>();
    }
    getIt.registerSingleton<EqualizerManager>(_equalizerManager);
    _init();
  }

  EqualizerManager get equalizerManager => _equalizerManager;
  AdaptiveBufferEngine get adaptiveBufferEngine => _adaptiveBufferEngine;
  OptimizedDspPipeline get dspPipeline => _dspPipeline;
  PlaybackAnalytics get playbackAnalytics => _playbackAnalytics;
  AudioMemoryManager get memoryManager => _memoryManager;
  SmartPreloadScheduler get preloadScheduler => _preloadScheduler;
  FormatAwareDecoder get formatDecoder => _formatDecoder;
  TripleBufferPipeline get tripleBufferPipeline => _tripleBufferPipeline;
  BatteryAwarePlayback get batteryAwarePlayback => _batteryAwarePlayback;
  SeamlessQueueTransition get queueTransition => _queueTransition;

  int getOptimalBufferFrames({
    required bool isLocalFile,
    required int sampleRate,
    bool isHighRes = false,
  }) =>
      LatencyOptimizer.getOptimalBufferFrames(
        isLocalFile: isLocalFile,
        sampleRate: sampleRate,
        isHighRes: isHighRes,
      );

  factory PulsrAudioHandler(
      IMusicRepository repository, YtmService ytmService) {
    if (Platform.isAndroid) {
      // The 10-band EQ now runs natively (DynamicsProcessing postEq). Only the
      // loudness enhancers remain in the just_audio pipeline, as inert anchors
      // that make ExoPlayer allocate the audio session the native effects bind to.
      final leA = AndroidLoudnessEnhancer();
      final leB = AndroidLoudnessEnhancer();

      final playerA = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [leA]),
      );
      final playerB = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [leB]),
      );
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: playerA,
        playerB: playerB,
        loudnessEnhancerA: leA,
        loudnessEnhancerB: leB,
      );
    } else {
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: AudioPlayer(),
        playerB: AudioPlayer(),
      );
    }
  }

  static MediaItem _songToMediaItem(SongsTableData song, [Uri? artUri]) {
    Uri? finalArtUri = (artUri != null && artUri.hasScheme && (artUri.host.isNotEmpty || artUri.path.isNotEmpty))
        ? artUri
        : null;

    if (finalArtUri == null && song.artworkUri != null && song.artworkUri!.isNotEmpty) {
      final parsed = Uri.tryParse(song.artworkUri!);
      if (parsed != null &&
          parsed.hasScheme &&
          (parsed.host.isNotEmpty || parsed.scheme == 'file' || parsed.scheme == 'content')) {
        finalArtUri = parsed;
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
      },
    );
  }

  SharedPreferences? _cachedPrefs;

  Future<void> _initPrefs() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }

  double _volume = 1.0;
  double get volume => _volume;

  double _calculateReplayGainVolume(SongsTableData? song) {
    if (song == null) return _volume;

    final prefs = _cachedPrefs;
    if (prefs == null) return _volume; // Null guard

    final modeStr = prefs.getString(PrefsKeys.replayGainMode) ?? 'track';
    final preampWithRg =
        prefs.getDouble(PrefsKeys.replayGainPreampWithRg) ?? 0.0;
    final preampWithoutRg =
        prefs.getDouble(PrefsKeys.replayGainPreampWithoutRg) ?? -3.0;

    double? gainDb;
    double? peak;

    switch (modeStr) {
      case 'track':
        gainDb = song.replayGainTrack;
        peak = song.replayGainTrackPeak;
        break;
      case 'album':
        gainDb = song.replayGainAlbum ?? song.replayGainTrack;
        peak = song.replayGainAlbumPeak ?? song.replayGainTrackPeak;
        break;
      case 'auto':
        final isAlbumMode = _isConsecutiveAlbumPlayback();
        if (isAlbumMode && song.replayGainAlbum != null) {
          gainDb = song.replayGainAlbum;
          peak = song.replayGainAlbumPeak ?? song.replayGainTrackPeak;
        } else {
          gainDb = song.replayGainTrack;
          peak = song.replayGainTrackPeak;
        }
        break;
      case 'off':
      default:
        return _volume;
    }

    double preampDb;
    if (gainDb != null && gainDb != 0.0) {
      preampDb = preampWithRg;
    } else {
      preampDb = preampWithoutRg;
      gainDb = 0.0;
    }

    final totalGainDb = (gainDb) + preampDb;
    var multiplier = math.pow(10.0, totalGainDb / 20.0).toDouble();

    // Clipping prevention: if peak is known, limit gain so output <= 1.0 with 0.5 dB inter-sample peak headroom
    if (peak != null && peak > 0.0) {
      final interSampleHeadroom = math.pow(10.0, -0.5 / 20.0).toDouble(); // ~0.944 (-0.5 dB)
      final maxGain = interSampleHeadroom / peak;
      if (multiplier > maxGain) {
        multiplier = maxGain;
      }
    }

    return (_volume * multiplier).clamp(0.0, 1.0).toDouble();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final song = currentSong;
    await _activePlayer.setVolume(_calculateReplayGainVolume(song));
  }

  bool get isEqualizerEnabled => _equalizerManager.isEnabled;
  EqPreset get currentPreset => _equalizerManager.currentPreset;
  bool get isVirtualizerEnabled => _equalizerManager.isVirtualizerEnabled;
  double get virtualizerStrength => _equalizerManager.virtualizerStrength;
  bool get isDynamicsEnabled => _equalizerManager.isDynamicsEnabled;
  DynamicsPreset get dynamicsPreset => _equalizerManager.dynamicsPreset;
  HeadphoneProfile? get selectedHeadphoneProfile =>
      _equalizerManager.selectedHeadphoneProfile;
  Duration get crossfadeDuration => _crossfadeManager.duration;

  void setCrossfadeDuration(Duration duration) {
    final wasGapless = _gaplessMode;
    _crossfadeManager.duration = duration;
    final isGapless = _gaplessMode;
    // Only switch live engine if playback is actively running.
    // When paused/stopped at startup, the engine changes passively without auto-starting playback.
    if (wasGapless != isGapless &&
        _songs.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _songs.length &&
        _activePlayer.playing) {
      unawaited(_switchPlaybackEngine(toGapless: isGapless));
    }
  }

  Future<void> _switchPlaybackEngine({required bool toGapless}) async {
    final resumePos = _activePlayer.position;
    final wasPlaying = _activePlayer.playing;
    try {
      if (toGapless) {
        await _loadGaplessQueue(
            initialPosition: resumePos, preload: wasPlaying);
      } else {
        _gaplessSource = null;
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
  bool get isDynamicsBypassed => _equalizerManager.isDynamicsBypassed;
  bool get isSpatializerEnabled => _equalizerManager.isSpatializerEnabled;
  bool get isSpatializerSupported => _equalizerManager.isSpatializerSupported;
  bool get isHeadTrackerAvailable => _equalizerManager.isHeadTrackerAvailable;
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
  Future<void> setCrossfeed(bool enabled, {double? delayUs, double? feedDb}) =>
      _equalizerManager.setCrossfeed(enabled, delayUs: delayUs, feedDb: feedDb);

  bool get isLimiterEnabled => _equalizerManager.isLimiterEnabled;
  double get limiterThresholdDb => _equalizerManager.limiterThresholdDb;
  double get limiterReleaseMs => _equalizerManager.limiterReleaseMs;
  Future<void> setLookaheadLimiter(bool enabled, {double? thresholdDb, double? releaseMs, double? lookaheadMs}) =>
      _equalizerManager.setLookaheadLimiter(enabled, thresholdDb: thresholdDb, releaseMs: releaseMs, lookaheadMs: lookaheadMs);

  bool get isReverbEnabled => _equalizerManager.isReverbEnabled;
  int get reverbPreset => _equalizerManager.reverbPreset;
  double get reverbWetDry => _equalizerManager.reverbWetDry;
  Future<void> setReverb(bool enabled, {int? preset, double? wetDry}) =>
      _equalizerManager.setReverb(enabled, preset: preset, wetDry: wetDry);
  Future<void> loadCustomImpulseResponse(List<double> irSamples) =>
      _equalizerManager.loadCustomImpulseResponse(irSamples);

  double get stereoBalance => _equalizerManager.stereoBalance;
  bool get monoMix => _equalizerManager.monoMix;
  Future<void> setStereoBalance(double balance) =>
      _equalizerManager.setStereoBalance(balance);
  Future<void> setMonoMix(bool mono) =>
      _equalizerManager.setMonoMix(mono);

  bool get isSincResamplerEnabled => _equalizerManager.isSincResamplerEnabled;
  Future<void> setSincResampler(bool enabled) =>
      _equalizerManager.setSincResampler(enabled);

  bool get hasOemAudio => _equalizerManager.hasOemAudio;
  List<String> get detectedOemEngines => _equalizerManager.detectedOemEngines;

  void onAppPaused() => _equalizerManager.onAppPaused();

  void saveCurrentPositionImmediate() {
    _savePositionDebounce?.cancel();
    if (_songs.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _songs.length) {
      final currentSong = _songs[_currentIndex];
      final posMs = _activePlayer.position.inMilliseconds;
      _repository.updateLastPosition(currentSong.id, posMs);
      if (_queueDirty) {
        _repository.saveQueue(
            _songs.map((s) => s.id).toList(), _currentIndex, posMs);
        _queueDirty = false;
      }
    }
  }

  void _saveCurrentPosition() {
    _savePositionDebounce?.cancel();
    _savePositionDebounce = Timer(const Duration(milliseconds: 1500), () {
      saveCurrentPositionImmediate();
    });
  }

  Future<void> _init() async {
    await _initPrefs();

    _playbackAnalytics = PlaybackAnalytics(
      onIncreaseBufferSizeRequested: () {
        debugPrint('[AudioHandler] PlaybackAnalytics requested buffer size increase');
      },
      onReduceQualityRequested: () {
        debugPrint('[AudioHandler] PlaybackAnalytics requested quality reduction');
      },
      onStreamRecoveryRequested: (videoId, error) async {
        debugPrint('[AudioHandler] Attempting self-healing recovery for $videoId: $error');
        try {
          await _ytmService.invalidatePoToken();
          await _ytmService.ensurePoTokenReady();
        } catch (_) {}
      },
      onCorruptedFileDetected: (path, error) {
        debugPrint('[AudioHandler] Corrupted file flagged at $path: $error');
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
    );

    _formatDecoder = FormatAwareDecoder(
      resolveYtmStream: (song, tag) => _resolveAudioSource(song, tag),
    );

    _tripleBufferPipeline = TripleBufferPipeline(
      activePlayer: _playerA,
      preloadedPlayer: _playerB,
      resolveAudioSource: (song, tag) => _resolveAudioSource(song, tag),
      songToMediaItem: (song, [fastArtUri]) => _songToMediaItem(song, fastArtUri),
    );

    _batteryAwarePlayback = BatteryAwarePlayback(
      onLowPowerMode: ({required disableVisualizer, required reduceDsp}) {
        debugPrint('[AudioHandler] Battery low power mode triggered');
      },
      onCriticalMode: ({required disableCrossfade, required minimalBuffer}) {
        debugPrint('[AudioHandler] Battery critical power mode triggered');
      },
    );

    _queueTransition = SeamlessQueueTransition(
      buildConcatSource: (songs) => _buildConcat(songs),
      crossfadeToInactive: (active, inactive) async {
        final fadeId = _crossfadeManager.nextFadeId();
        await _crossfadeManager.fadeVolume(
          active,
          _volume,
          0.0,
          _crossfadeManager.duration,
          fadeId,
        );
      },
    );

    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      bool isTargetActive() => isPlayerA == _isPlayerAActive && identical(player, _activePlayer);

      _subscriptions.add(
        player.playbackEventStream.listen(
          (event) {
            if (isTargetActive()) {
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
            if (isTargetActive() &&
                dur != null &&
                dur > Duration.zero) {
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
              // Gapless loop-all support
              if (_gaplessMode &&
                  state.processingState == ProcessingState.completed &&
                  _activePlayer.loopMode == LoopMode.all) {
                await _activePlayer.seek(Duration.zero, index: 0);
                await _activePlayer.play();
                return;
              }
              // In gapless mode the ConcatenatingAudioSource advances itself; only
              // the crossfade engine (one source per track) needs a manual skip on
              // completion. A completed event at the very end (loop off) just stops.
              if (!_gaplessMode &&
                  state.processingState == ProcessingState.completed &&
                  !_crossfadeManager.isCrossfading) {
                skipToNext();
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
              if (now - _lastPositionEmitMs >= 250 || pos == Duration.zero) {
                _lastPositionEmitMs = now;
                _positionSubject.add(pos);
              }
              _saveCurrentPosition();
              final duration = player.duration ?? Duration.zero;
              // Warm the next YouTube stream URL before the crossfade window even
              // opens, so resolve latency does not truncate the fade. Cheap no-op
              // for local tracks and for an already-cached url.
              if (duration > const Duration(seconds: 15) &&
                  (pos >= duration - const Duration(seconds: 15) ||
                   pos.inMilliseconds >= duration.inMilliseconds * 0.7)) {
                _smartPrefetch();
              }
              if (_crossfadeManager.duration > Duration.zero &&
                  duration > _crossfadeManager.duration &&
                  pos >= duration - _crossfadeManager.duration &&
                  !_crossfadeManager.isCrossfading) {
                final nextIdx = _getNextIndex();
                if (nextIdx != null) {
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
            if (sessionId != null && isTargetActive()) {
              AudioEffectsChannel().setAudioSessionId(sessionId);
              _currentAudioSessionId = sessionId;
              _audioSessionIdSubject.add(sessionId);
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

      _subscriptions.add(
        session.interruptionEventStream.listen((event) async {
          if (event.begin) {
            _wasPlayingBeforeInterruption = _activePlayer.playing;
            if (_wasPlayingBeforeInterruption) {
              switch (event.type) {
                case AudioInterruptionType.duck:
                  _preDuckVolume = _activePlayer.volume;
                  await _activePlayer.setVolume(0.3 * (_preDuckVolume ?? 1.0));
                  break;
                case AudioInterruptionType.pause:
                case AudioInterruptionType.unknown:
                  await _activePlayer.pause();
                  break;
              }
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                if (_preDuckVolume != null) {
                  final expectedDucked = 0.3 * (_preDuckVolume ?? 1.0);
                  if ((_activePlayer.volume - expectedDucked).abs() < 0.05) {
                    await _activePlayer.setVolume(_preDuckVolume ?? 1.0);
                  }
                  _preDuckVolume = null;
                }
                break;
              case AudioInterruptionType.pause:
                if (_wasPlayingBeforeInterruption) {
                  _wasPlayingBeforeInterruption = false;
                  final prefs =
                      _cachedPrefs ?? await SharedPreferences.getInstance();
                  final resume =
                      prefs.getBool(PrefsKeys.resumeAfterInterruption) ?? true;
                  if (resume && !_activePlayer.playing) {
                    await _activePlayer.play();
                  }
                }
                _preDuckVolume = null;
                break;
              case AudioInterruptionType.unknown:
                _wasPlayingBeforeInterruption = false;
                _preDuckVolume = null;
                break;
            }
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          if (_crossfadeManager.isCrossfading) {
            _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
                restoreVolume: _volume);
          }
          pause();
        }),
      );
    } catch (e, st) {
      ErrorLogger.log('Error configuring AudioSession',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    // Initialize audio effects & equalizer preferences
    await _equalizerManager.init();

    // Register lifecycle observer to persist playback state and manage buffers on app background/resume
    _lifecycleObserver = _AudioHandlerLifecycleObserver(
      onBackground: () {
        saveCurrentPositionImmediate();
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

  AudioSource _createAudioSource(SongsTableData song, MediaItem tag) {
    if (song.uri?.startsWith('content:') == true ||
        song.path.startsWith('content:')) {
      return AudioSource.uri(Uri.parse(song.uri ?? song.path), tag: tag);
    }
    return AudioSource.file(song.path, tag: tag);
  }

  void _handleStreamResolutionError(SongsTableData song, Object error) {
    final info = YtmErrorClassifier.classify(error);
    ErrorLogger.log(
      'Gapless stream resolution error on "${song.title}": ${info.message} ($error)',
      category: 'AudioHandler',
    );
    _errorSubject.add(info.message);

    // Invalidate poToken on 403 / bot block so the next track attempts a fresh attestation
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('403') || errStr.contains('bot') || (error is YtmException && error.isBotBlocked)) {
      _ytmService.invalidatePoToken().ignore();
    }

    if (info.recoveryAction == YtmRecoveryAction.skipToNextTrack) {
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
  AudioSource _buildGaplessChild(SongsTableData song) {
    final tag = _songToMediaItem(song);
    final isRemote = song.source == SongSource.youtube &&
        (song.path.startsWith('ytmusic://') ||
            song.path.isEmpty ||
            (!song.path.startsWith('content:') && !File(song.path).existsSync()));
    if (isRemote) {
      late final YtmResolvingSource source;
      source = YtmResolvingSource.withRefresh(
        videoId: song.remoteId ?? '',
        resolve: ({bool forceRefresh = false}) async {
          final resolved = await _resolveStreamUrl(song, forceRefresh: forceRefresh);
          source.userAgent = resolved.userAgent;
          source.cookies = resolved.cookies;
          return resolved.url;
        },
        onError: (error) => _handleStreamResolutionError(song, error),
        tag: tag,
      );
      return source;
    }
    return _createAudioSource(song, tag);
  }

  ConcatenatingAudioSource _buildConcat(List<SongsTableData> songs) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: songs.map(_buildGaplessChild).toList(),
    );
  }

  /// A local song plays straight off disk; a YouTube row needs a freshly
  /// resolved URL, because the last one expires within hours and is pinned to
  /// this device's IP. Used by the crossfade engine, which loads one track at a
  /// time. (The gapless engine instead uses [_buildGaplessChild], whose
  /// [YtmResolvingSource] both resolves lazily and caches fetched bytes so a
  /// backward seek does not re-hit an already-expired URL.)
  Future<AudioSource> _resolveAudioSource(
      SongsTableData song, MediaItem tag) async {
    if (song.source != SongSource.youtube) {
      return _createAudioSource(song, tag);
    }

    // Direct fast path for downloaded songs with physical file on disk or content URI
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || File(song.path).existsSync())) {
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
          (File(localSong.path).existsSync() ||
              localSong.path.startsWith('content:') ||
              (localSong.uri != null &&
                  localSong.uri!.startsWith('content:')))) {
        return _createAudioSource(localSong, tag);
      }
    } catch (_) {
      // If local check fails, fall through to stream resolution
    }

    // Fast-path: check if YouTube track is already cached in local disk stream cache
    if (song.remoteId != null && song.remoteId!.isNotEmpty) {
      final cachedFile = await YtmCacheManager().getCachedAudioFile(song.remoteId!);
      if (cachedFile != null) {
        return AudioSource.file(cachedFile.path, tag: tag);
      }
    }

    final resolved = await _resolveStreamUrl(song);
    final url = resolved.url;
    final userAgent = resolved.userAgent;
    final cookies = resolved.cookies;

    final headers = <String, String>{
      if (userAgent != null && userAgent.isNotEmpty)
        'User-Agent': userAgent
      else
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
      'Referer': 'https://music.youtube.com/',
    };

    return AudioSource.uri(
      Uri.parse(url),
      tag: tag,
      headers: headers,
    );
  }

  /// Returns a currently-valid stream URL for a YouTube row, reusing a memoized
  /// one until it nears expiry. Throws [YtmException] when nothing usable comes
  /// back, so the caller can tell "network down" from "skip this track".
  Future<({String url, String? userAgent, String? cookies})> _resolveStreamUrl(SongsTableData song, {bool forceRefresh = false}) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }

    final prefs = await SharedPreferences.getInstance();
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
    final cacheKey = '$videoId-$quality';

    if (!forceRefresh) {
      final cached = _streamCache[cacheKey];
      if (cached != null && cached.expires.isAfter(DateTime.now())) {
        return (url: cached.url, userAgent: cached.userAgent, cookies: cached.cookies);
      }
    }
    final stream = await _ytmService.resolveStream(videoId, quality: quality);
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
      _streamCache[cacheKey] = (url: stream.url, expires: safeExpiry, userAgent: stream.userAgent, cookies: stream.cookies);
    }
    AudioMemoryManager.trimStreamCache(_streamCache);
    return (url: stream.url, userAgent: stream.userAgent, cookies: stream.cookies);
  }

  int _prefetchGeneration = 0;

  void cancelPrefetches() {
    _prefetchGeneration++;
    _prefetching.clear();
  }

  /// Warms [_streamCache] for an upcoming YouTube track so track switching is instant.
  void _prefetchStream(SongsTableData song) {
    final videoId = song.remoteId;
    if (song.source != SongSource.youtube ||
        videoId == null ||
        videoId.isEmpty) {
      return;
    }
    // Skip prefetch if downloaded/local file exists
    if (!song.path.startsWith('ytmusic://') &&
        song.path.isNotEmpty &&
        (song.path.startsWith('content:') || File(song.path).existsSync())) {
      return;
    }
    // Avoid launching background prefetch storms if playback failures are occurring
    if (_consecutiveFailures > 0) {
      return;
    }
    if (!_prefetching.add(videoId)) {
      return;
    }
    final currentGen = _prefetchGeneration;
    _resolveStreamUrl(song)
        .then((_) {
          if (_prefetchGeneration != currentGen) {
            _prefetching.remove(videoId);
          }
        })
        .whenComplete(() => _prefetching.remove(videoId))
        .ignore();
  }

  bool _isConsecutiveAlbumPlayback() {
    if (_songs.isEmpty || _currentIndex < 0 || _currentIndex >= _songs.length) return false;
    final currentAlbum = _songs[_currentIndex].album;
    if (currentAlbum == 'Unknown Album' || currentAlbum.isEmpty) return false;
    if (_currentIndex > 0 && _songs[_currentIndex - 1].album == currentAlbum) return true;
    if (_currentIndex + 1 < _songs.length && _songs[_currentIndex + 1].album == currentAlbum) return true;
    return false;
  }

  void _smartPrefetch() {
    if (_songs.isEmpty || _currentIndex < 0 || _consecutiveFailures > 0) return;

    for (int offset = 1; offset <= 2; offset++) {
      final targetIdx = _getNextIndex(offset: offset);
      if (targetIdx != null && targetIdx >= 0 && targetIdx < _songs.length) {
        final song = _songs[targetIdx];
        if (song.source == SongSource.youtube && song.remoteId != null) {
          _prefetchStream(song);
        }
      }
    }
  }

  void _prefetchNextTracks() {
    _smartPrefetch();
  }

  Future<void> restoreLastPlaybackSession() async {
    try {
      // Restore shuffle and repeat preferences from storage (Issue #12)
      final prefs = await SharedPreferences.getInstance();
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
      await setRepeatMode(repeatMode);

      final queueRes = await _repository.getSavedQueue();
      final queueItems =
          queueRes.fold((l) => <QueueItemsTableData>[], (r) => r);
      if (queueItems.isEmpty) return;

      // Batch query songs instead of N+1 synchronous disk checks (Issue #18)
      final songIds = queueItems.map((q) => q.songId).toList();
      final songsRes = await _repository.getSongsByIds(songIds);
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
        _songs = songs;
        _currentIndex = targetIndex.clamp(0, songs.length - 1);
        final currentSong = _songs[_currentIndex];
        final artUri = await ArtworkUriResolver.resolveArtworkUri(currentSong);
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
        _broadcastState(_activePlayer.playbackEvent);
        _positionSubject.add(pos);
      }
    } catch (e, st) {
      ErrorLogger.log('Error restoring last playback session',
          error: e, stackTrace: st, category: 'AudioHandler');
    }
  }

  Future<void> _startCrossfade(int nextIndex) async {
    if (_crossfadeManager.isCrossfading) return;
    return _crossfadeManager.protect(() async {
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
          try { await _inactivePlayer.stop(); } catch (_) {}
          try { await _activePlayer.setVolume(initialActiveVolume); } catch (_) {}
          return;
        }

        // Synchronize speed on inactive player before loading & playback
        await _inactivePlayer.setSpeed(_activePlayer.speed);
        await _inactivePlayer.setAudioSource(source);

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try { await _inactivePlayer.stop(); } catch (_) {}
          try { await _activePlayer.setVolume(initialActiveVolume); } catch (_) {}
          return;
        }

        await _inactivePlayer.setVolume(0.0);
        await _inactivePlayer.play();

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try { await _inactivePlayer.stop(); } catch (_) {}
          try { await _activePlayer.setVolume(initialActiveVolume); } catch (_) {}
          return;
        }

        final active = _activePlayer;
        final inactive = _inactivePlayer;

        final fadeDuration = _crossfadeManager.duration;

        await Future.wait([
          _crossfadeManager.fadeVolume(
              active, _volume, 0.0, fadeDuration, currentFadeId),
          _crossfadeManager.fadeVolume(inactive, 0.0, _volume,
              fadeDuration, currentFadeId),
        ]);

        if (_crossfadeManager.currentFadeId != currentFadeId) {
          try { await _inactivePlayer.stop(); } catch (_) {}
          try { await active.setVolume(initialActiveVolume); } catch (_) {}
          return;
        }

        _isPlayerAActive = !_isPlayerAActive;
        _currentIndex = nextIndex;

        final currentSessionId = _activePlayer.androidAudioSessionId;
        if (currentSessionId != null) {
          AudioEffectsChannel().setAudioSessionId(currentSessionId);
          _currentAudioSessionId = currentSessionId;
          _audioSessionIdSubject.add(currentSessionId);
        }

        mediaItem.add(_songToMediaItem(nextSong, artUri));
        _repository.recordPlayHistory(nextSong.id);
        _broadcastState(_activePlayer.playbackEvent);

        await active.stop();
        await active.setVolume(_volume);
      } catch (e, st) {
        ErrorLogger.log('Error during crossfade playback',
            error: e, stackTrace: st, category: 'AudioHandler');
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
          try { await _inactivePlayer.stop(); } catch (_) {}
          try { await _activePlayer.setVolume(initialActiveVolume); } catch (_) {}
        }
      }
    });
  }

  int? _getNextIndex({int offset = 1}) {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) {
      if (offset == 1) {
        _shuffleHistory.add(_currentIndex);
        if (_shuffleHistory.length > 50) {
          _shuffleHistory.removeAt(0);
        }
      }
      final random = math.Random();
      final recentWindow = math.min(_songs.length - 1, 10);
      final recent = _shuffleHistory.length >= recentWindow
          ? _shuffleHistory.sublist(_shuffleHistory.length - recentWindow)
          : _shuffleHistory;

      int next = random.nextInt(_songs.length);
      int attempts = 0;
      while ((next == _currentIndex || recent.contains(next)) &&
          attempts < 20 &&
          _songs.length > 1) {
        next = random.nextInt(_songs.length);
        attempts++;
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

  int? _getPreviousIndex() {
    if (_songs.isEmpty) return null;
    if (_activePlayer.position.inSeconds > 3) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _shuffleHistory.isNotEmpty) {
      return _shuffleHistory.removeLast();
    }
    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (_activePlayer.loopMode == LoopMode.all) {
      return _songs.length - 1;
    }
    return null;
  }

  void _broadcastState(PlaybackEvent event) {
    // GUARD: Only broadcast from the ACTIVE player
    if (!identical(_activePlayer, _isPlayerAActive ? _playerA : _playerB)) {
      return;
    }

    final isCompleted =
        _activePlayer.processingState == ProcessingState.completed;
    final isPlaying = _activePlayer.playing && !isCompleted;
    final processingState = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_activePlayer.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _activePlayer.position,
        bufferedPosition: _activePlayer.bufferedPosition,
        speed: _activePlayer.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  // --- QUEUE & PLAYBACK COMMANDS ---
  Future<void> loadQueue(List<SongsTableData> songs,
      {int initialIndex = 0, Duration? initialPosition}) async {
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    _songs = List.from(songs);
    _currentIndex =
        initialIndex.clamp(0, _songs.isEmpty ? 0 : _songs.length - 1);
    _queueDirty = true;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;

    final mediaItems = _songs.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    if (_songs.isEmpty) return;
    if (_gaplessMode) {
      await _loadGaplessQueue(initialPosition: initialPosition);
    } else {
      await playSongAt(_currentIndex, initialPosition: initialPosition);
    }
  }

  /// Loads the whole queue as one [ConcatenatingAudioSource] on the active
  /// player so ExoPlayer joins consecutive tracks with no gap. With [preload]
  /// false the source is set but not prepared, so a restored YouTube track
  /// resolves lazily on the first play() instead of throwing at cold start when
  /// offline.
  Future<void> _loadGaplessQueue(
      {Duration? initialPosition, bool preload = true}) async {
    if (_songs.isEmpty) return;
    final generation = ++_playGeneration;
    _pendingLazyPosition = null;
    _consecutiveFailures = 0;
    _rapidGaplessChangeCount = 0;
    _lastGaplessChangeTime = null;
    _lastGaplessIndex = _currentIndex;

    final song = _songs[_currentIndex];
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(_songToMediaItem(song, fastArtUri));

    final concat = _buildConcat(_songs);

    try {
      // Cleanly stop any existing playing source to release hanging native sockets
      try {
        await _activePlayer.stop();
      } catch (_) {}

      await _activePlayer.setAudioSource(
        concat,
        initialIndex: _currentIndex,
        initialPosition: initialPosition,
        preload: preload,
      );
      _gaplessSource = concat;
      if (generation != _playGeneration) return;
      await _activePlayer.setVolume(_calculateReplayGainVolume(song));
      if (preload) {
        await _activePlayer.play();
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
      if (nextIdx != null && nextIdx != _currentIndex) {
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
      _errorSubject.add(info.message);
      ErrorLogger.log('Error loading gapless queue for ${song.title}',
          error: e, stackTrace: st, category: 'AudioHandler');
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
    if (_gaplessSource == null) return;
    final childCount = _gaplessSource!.length;
    if (index >= childCount) return;

    // Detect rapid successive transitions caused by ExoPlayer auto-advancing
    // past failing tracks in a loop.
    final now = DateTime.now();
    if (_lastGaplessChangeTime != null &&
        now.difference(_lastGaplessChangeTime!).inMilliseconds < 1500) {
      _rapidGaplessChangeCount++;
      if (_rapidGaplessChangeCount >= 2) {
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
    }
    _lastGaplessChangeTime = now;

    _lastGaplessIndex = index;
    _currentIndex = index;
    final song = _songs[index];
    final generation = _playGeneration;

    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    mediaItem.add(_songToMediaItem(song, fastArtUri));
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

  Future<void> playSongAt(int index, {Duration? initialPosition}) async {
    if (index < 0 || index >= _songs.length) return;
    cancelPrefetches();
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    // A YouTube resolve below can await for seconds; a second skip during that
    // window must win. Capture a generation token and bail from a stale call
    // after every await, or we get double mediaItem/history and torn state.
    final generation = ++_playGeneration;
    _pendingLazyPosition = null;
    _currentIndex = index;

    final song = _songs[index];
    final fastArtUri =
        song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = _songToMediaItem(song, fastArtUri);
    mediaItem.add(item);

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
      if (generation != _playGeneration) return;
      try {
        await _activePlayer.setAudioSource(source,
            initialPosition: initialPosition, preload: true);
      } catch (playErr) {
        // If a YouTube stream fails (e.g. 403 / expired URL), clear cache & retry once
        if (song.source == SongSource.youtube && song.remoteId != null) {
          debugPrint(
              '[AudioHandler] Playback error on ${song.title}: $playErr. Retrying with fresh stream URL...');
          _streamCache.removeWhere((key, _) => key.startsWith(song.remoteId!));
          source = await _resolveAudioSource(song, item);
          if (generation != _playGeneration) return;
          await _activePlayer.setAudioSource(source,
              initialPosition: initialPosition, preload: true);
        } else {
          rethrow;
        }
      }
      if (generation != _playGeneration) return;
      await _activePlayer.setVolume(_calculateReplayGainVolume(song));
      await _activePlayer.play();
      _consecutiveFailures = 0;
      _repository.recordPlayHistory(song.id);
      _saveCurrentPosition();

      // Early prefetch next streams for Gapless 2.0
      _prefetchNextTracks();
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
    } catch (e, st) {
      if (generation != _playGeneration) return;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('interrupted') || errStr.contains('abort')) {
        return;
      }
      final info = YtmErrorClassifier.classify(e);
      _errorSubject.add(info.message);
      ErrorLogger.log('Error playing song ${song.title} (${song.path})',
          error: e, stackTrace: st, category: 'AudioHandler');
      final isFatal = (e is YtmException && e.isFatal) ||
          info.recoveryAction != YtmRecoveryAction.skipToNextTrack;
      await _failCurrentPlayback(fatal: isFatal);
    }
  }

  /// Shared failure handling for [playSongAt]: a fatal error pauses outright,
  /// otherwise skip forward until [_consecutiveFailures] trips the circuit.
  Future<void> _failCurrentPlayback({required bool fatal}) async {
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
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      await skipToNext();
    }
  }

  // --- PLAYBACK ACTIONS ---
  @override
  Future<void> play() {
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
    return _activePlayer.play();
  }

  @override
  Future<void> pause() async {
    _wasPlayingBeforeInterruption = false;
    ErrorLogger.addBreadcrumb('Playback paused', category: 'player');
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _preCrossfadeVolume ?? _volume);
    _saveCurrentPosition();
    await _activePlayer.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seek to ${position.inSeconds}s',
        category: 'player');
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    await _activePlayer.seek(position);
    _positionSubject.add(position);
    _saveCurrentPosition();
  }

  @override
  Future<void> skipToNext() async {
    _playGeneration++;
    ErrorLogger.addBreadcrumb('Playback skipToNext', category: 'player');
    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    }
    if (_gaplessMode && _gaplessSource != null) {
      if (_activePlayer.hasNext) {
        await _activePlayer.seekToNext();
      } else {
        await _activePlayer.pause();
        await _activePlayer.seek(Duration.zero);
        _broadcastState(_activePlayer.playbackEvent);
      }
      return;
    }

    final nextIdx = _getNextIndex();
    if (nextIdx != null) {
      await playSongAt(nextIdx);
    } else {
      await _activePlayer.pause();
      await _activePlayer.seek(Duration.zero);
      _broadcastState(_activePlayer.playbackEvent);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _playGeneration++;
    ErrorLogger.addBreadcrumb('Playback skipToPrevious', category: 'player');
    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
    }
    if (_gaplessMode && _gaplessSource != null) {
      if (_activePlayer.position.inSeconds > 3) {
        await _activePlayer.seek(Duration.zero);
        _saveCurrentPosition();
        return;
      }
      if (_activePlayer.hasPrevious) {
        await _activePlayer.seekToPrevious();
      } else {
        await _activePlayer.seek(Duration.zero);
        _saveCurrentPosition();
      }
      return;
    }
    if (_activePlayer.position.inSeconds > 3) {
      await _activePlayer.seek(Duration.zero);
      _saveCurrentPosition();
      return;
    }
    final prevIdx = _getPreviousIndex();
    if (prevIdx != null) {
      await playSongAt(prevIdx);
    } else {
      await _activePlayer.seek(Duration.zero);
      _saveCurrentPosition();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await _playerA.setShuffleModeEnabled(enable);
    await _playerB.setShuffleModeEnabled(enable);
    // In gapless mode the concat's shuffle order drives playback; reshuffle so
    // enabling shuffle actually reorders upcoming tracks (current stays put).
    if (enable && _gaplessMode && _gaplessSource != null) {
      await _activePlayer.shuffle();
    }
    // The crossfade engine draws its own random order from _getNextIndex, so no
    // native reshuffle is needed there.
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
    };

    await _playerA.setLoopMode(loopMode);
    await _playerB.setLoopMode(loopMode);

    // SYNC: Force gapless source rebuild if loop mode changed mid-playback
    if (_gaplessMode && _gaplessSource != null && _activePlayer.playing) {
      final pos = _activePlayer.position;
      await _loadGaplessQueue(initialPosition: pos);
      if (_activePlayer.position != pos) {
        await _activePlayer.seek(pos);
      }
    }

    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  static const int maxQueueSize = 500;

  @override
  Future<void> setSpeed(double speed) async {
    final clamped = speed.clamp(0.25, 4.0);
    await _playerA.setSpeed(clamped);
    await _playerB.setSpeed(clamped);
    playbackState.add(playbackState.value.copyWith(speed: clamped));
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
        if (_gaplessMode && _gaplessSource != null) {
          await _gaplessSource!.add(_buildGaplessChild(song));
        }
        queue.add(_songs.map(_songToMediaItem).toList());
        _saveCurrentPosition();
      }
    }
  }

  Future<void> insertNextInQueue(SongsTableData song) async {
    if (_songs.length >= maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($maxQueueSize)',
          category: 'AudioHandler');
      return;
    }
    final insertIdx =
        _songs.isEmpty ? 0 : (_currentIndex + 1).clamp(0, _songs.length);
    _songs.insert(insertIdx, song);
    _queueDirty = true;
    // Insert sits after the current track, so the playing index never shifts.
    if (_gaplessMode && _gaplessSource != null) {
      await _gaplessSource!.insert(insertIdx, _buildGaplessChild(song));
    }
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> addToQueueEnd(SongsTableData song) async {
    if (_songs.length >= maxQueueSize) {
      ErrorLogger.log('Queue size limit reached ($maxQueueSize)',
          category: 'AudioHandler');
      return;
    }
    _songs.add(song);
    _queueDirty = true;
    if (_gaplessMode && _gaplessSource != null) {
      await _gaplessSource!.add(_buildGaplessChild(song));
    }
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final wasPlayingCurrent = index == _currentIndex;
    final gaplessRef = _gaplessSource;

    _songs.removeAt(index);
    _queueDirty = true;

    if (_songs.isEmpty) {
      _currentIndex = 0;
      _gaplessSource = null;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    if (_gaplessMode) {
      if (wasPlayingCurrent) {
        // Removing the playing track changes the current song. Rebuild the
        // concat at the clamped index so the new current starts cleanly,
        // rather than leaning on ExoPlayer's silent same-index auto-advance
        // (which would leave the notification and play history stale).
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        if (gaplessRef != null && _activePlayer.audioSource != null) {
          await _loadGaplessQueue();
        } else {
          final nextSong = _songs[_currentIndex];
          final fastArtUri =
              nextSong.artworkUri != null ? Uri.tryParse(nextSong.artworkUri!) : null;
          mediaItem.add(_songToMediaItem(nextSong, fastArtUri));
        }
      } else {
        if (index < _currentIndex) _currentIndex--;
        // Pre-set so the shift emit from currentIndexStream is a no-op.
        _lastGaplessIndex = _currentIndex;
        if (gaplessRef != null && index < gaplessRef.length) {
          await gaplessRef.removeAt(index);
        }
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
      } else if (wasPlayingCurrent) {
        _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
        await playSongAt(_currentIndex);
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

    // move() replays remove(oldIndex)+insert(newIndex) on the concat's still-old
    // layout, reaching the same order as _songs. Pre-set _lastGaplessIndex so a
    // shift emit for the (unchanged) current song is swallowed.
    if (_gaplessMode && _gaplessSource != null) {
      _lastGaplessIndex = _currentIndex;
      await _gaplessSource!.move(oldIndex, newIndex);
    }

    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  // --- SLEEP TIMER ---
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    _sleepTimerManager.startSleepTimer(
      duration,
      fadeOut: fadeOut,
      onTimerExpired: pause,
      getActivePlayer: () => _activePlayer,
    );
  }

  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    _sleepTimerManager.startAbsoluteSleepTimer(
      stopTime,
      fadeOut: fadeOut,
      onTimerExpired: pause,
      getActivePlayer: () => _activePlayer,
    );
  }

  void cancelSleepTimer() {
    _sleepTimerManager.cancelSleepTimer();
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
        final items = <MediaItem>[];
        for (final song in list) {
          final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
          items.add(_songToMediaItem(song, artUri));
        }
        return items;

      case 'root':
      case 'android_auto_root':
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
        final items = <MediaItem>[];
        for (final song in list) {
          final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
          items.add(_songToMediaItem(song, artUri));
        }
        return items;

      case 'albums':
      case 'root_albums':
        final albumsRes = await _repository.getAlbums();
        final list = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        final items = <MediaItem>[];
        for (final album in list) {
          final artUri = await ArtworkUriResolver.getAlbumArtUri(album.id);
          items.add(
            MediaItem(
              id: 'album_${album.id}',
              title: album.title,
              artist: album.artist,
              playable: false,
              artUri: artUri,
            ),
          );
        }
        return items;

      case 'artists':
      case 'root_artists':
        final artistsRes = await _repository.getArtists();
        final list = artistsRes.fold((l) => <ArtistsTableData>[], (r) => r);
        final items = <MediaItem>[];
        for (final artist in list) {
          final artUri = await ArtworkUriResolver.getArtistArtUri(artist.id);
          items.add(
            MediaItem(
              id: 'artist_${artist.id}',
              title: artist.name,
              artist: '${artist.songCount} songs',
              playable: false,
              artUri: artUri,
            ),
          );
        }
        return items;

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
        final items = <MediaItem>[];
        for (final song in list) {
          final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
          items.add(_songToMediaItem(song, artUri));
        }
        return items;

      default:
        if (parentMediaId.startsWith('album_')) {
          final albumId = int.tryParse(parentMediaId.substring(6));
          if (albumId == null) return [];
          final songsRes = await _repository.getAlbumSongs(albumId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          final items = <MediaItem>[];
          for (final song in list) {
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            items.add(_songToMediaItem(song, artUri));
          }
          return items;
        }

        if (parentMediaId.startsWith('artist_')) {
          final artistId = int.tryParse(parentMediaId.substring(7));
          if (artistId == null) return [];
          final songsRes = await _repository.getArtistSongs(artistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          final items = <MediaItem>[];
          for (final song in list) {
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            items.add(_songToMediaItem(song, artUri));
          }
          return items;
        }

        if (parentMediaId.startsWith('playlist_')) {
          final playlistId = int.tryParse(parentMediaId.substring(9));
          if (playlistId == null) return [];
          final songsRes = await _repository.getPlaylistSongs(playlistId);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          final items = <MediaItem>[];
          for (final song in list) {
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            items.add(_songToMediaItem(song, artUri));
          }
          return items;
        }

        if (parentMediaId.startsWith('genre_')) {
          final genreName = parentMediaId.substring(6);
          if (genreName.isEmpty) return [];
          final songsRes = await _repository.getGenreSongs(genreName);
          final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
          final items = <MediaItem>[];
          for (final song in list) {
            final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
            items.add(_songToMediaItem(song, artUri));
          }
          return items;
        }

        if (parentMediaId == 'ytm_trending') {
          if (!AppConfig.ytmEnabled) return [];
          try {
            final ytmTracks = await _ytmService.search('trending music egypt');
            return ytmTracks.map((t) {
              final song = t.toSongData();
              return _songToMediaItem(song, t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null);
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
            final ytmFavs = allFavs.where((s) => s.source == SongSource.youtube || (s.remoteId != null && s.remoteId!.isNotEmpty)).toList();
            final items = <MediaItem>[];
            for (final song in ytmFavs) {
              final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
              items.add(_songToMediaItem(song, artUri));
            }
            return items;
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
    final songId = int.tryParse(mediaId);
    if (songId != null) {
      final songsRes = await _repository.getAllSongs();
      songsRes.fold((l) => null, (songs) {
        final index = songs.indexWhere((s) => s.id == songId);
        if (index != -1) {
          loadQueue(songs, initialIndex: index);
        }
      });
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
    final cleanQ = query.trim().toLowerCase();
    final songsRes = await _repository.getAllSongs();
    final allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    final results = <MediaItem>[];

    for (final song in allSongs) {
      if (song.title.toLowerCase().contains(cleanQ) ||
          song.artist.toLowerCase().contains(cleanQ) ||
          song.album.toLowerCase().contains(cleanQ) ||
          (song.genre?.toLowerCase().contains(cleanQ) ?? false)) {
        final artUri = await ArtworkUriResolver.resolveArtworkUri(song);
        results.add(_songToMediaItem(song, artUri));
      }
    }

    if (results.isEmpty && AppConfig.ytmEnabled) {
      try {
        final ytmTracks = await _ytmService.search(query.trim(), limit: 10);
        for (final t in ytmTracks) {
          final song = t.toSongData();
          final artUri = t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null;
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
    final songsRes = await _repository.getAllSongs();
    final allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);

    final lower = cleanQ.toLowerCase();
    // 1. Title match
    final titleMatches =
        allSongs.where((s) => s.title.toLowerCase().contains(lower)).toList();
    if (titleMatches.isNotEmpty) {
      await loadQueue(titleMatches);
      return;
    }
    // 2. Artist match
    final artistMatches =
        allSongs.where((s) => s.artist.toLowerCase().contains(lower)).toList();
    if (artistMatches.isNotEmpty) {
      await loadQueue(artistMatches);
      return;
    }
    // 3. Album match
    final albumMatches =
        allSongs.where((s) => s.album.toLowerCase().contains(lower)).toList();
    if (albumMatches.isNotEmpty) {
      await loadQueue(albumMatches);
      return;
    }
    // 4. Genre match
    final genreMatches = allSongs
        .where((s) => s.genre?.toLowerCase().contains(lower) ?? false)
        .toList();
    if (genreMatches.isNotEmpty) {
      await loadQueue(genreMatches);
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

    // 6. Default fallback: play first available song
    if (allSongs.isNotEmpty) {
      await loadQueue(allSongs);
    }
  }

  @override
  Future<void> stop() async {
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    _saveCurrentPosition();
    await _playerA.stop();
    await _playerB.stop();
    await AudioEffectsChannel().releaseEffects();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    saveCurrentPositionImmediate();
    await super.onTaskRemoved();
  }

  @disposeMethod
  void dispose() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    _savePositionDebounce?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _positionSubject.close();
    _audioSessionIdSubject.close();
    _sleepTimerManager.dispose();
    _equalizerManager.dispose();
    AudioEffectsChannel().releaseEffects();
    _playerA.dispose();
    _playerB.dispose();
  }
}

class _AudioHandlerLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onBackground;
  final VoidCallback? onResume;
  _AudioHandlerLifecycleObserver({required this.onBackground, this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      onBackground();
    } else if (state == AppLifecycleState.resumed) {
      onResume?.call();
    }
  }
}
