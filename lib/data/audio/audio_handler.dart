// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/prefs_keys.dart';
import '../../core/services/ytm_service.dart';
import '../../core/utils/error_logger.dart';
import '../../domain/models/audio_effects_config.dart';
import '../../domain/models/eq_preset.dart';
import '../../domain/models/headphone_profile.dart';
import '../../domain/repositories/music_repository_interface.dart';
import '../db/app_database.dart';
import 'artwork_uri_resolver.dart';
import 'audio_effects_channel.dart';
import 'crossfade_manager.dart';
import 'equalizer_manager.dart';
import 'sleep_timer_manager.dart';

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
  final List<int> _shuffleHistory = [];
  bool _wasPlayingBeforeInterruption = false;

  // Bumped on every playSongAt/play entry so a slow async resolve from a
  // superseded call cannot load its source into the player.
  int _playGeneration = 0;
  // Set when a restored YouTube session is left idle; play() resolves it lazily.
  Duration? _pendingLazyPosition;
  // Memoized stream URLs, keyed by video id. Never persisted — they expire.
  final Map<String, ({String url, DateTime expires})> _streamCache = {};
  // Video ids with an in-flight prefetch, so we resolve each at most once.
  final Set<String> _prefetching = {};

  Timer? _savePositionDebounce;
  final StreamController<Duration> _positionSubject =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionSubject.stream;
  SongsTableData? get currentSong => (_songs.isNotEmpty && _currentIndex >= 0 && _currentIndex < _songs.length) ? _songs[_currentIndex] : null;
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepTimerManager.sleepTimerRemainingStream;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PulsrAudioHandler._({
    required IMusicRepository repository,
    required YtmService ytmService,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AndroidEqualizer? equalizerA,
    AndroidLoudnessEnhancer? loudnessEnhancerA,
    AndroidEqualizer? equalizerB,
    AndroidLoudnessEnhancer? loudnessEnhancerB,
  })  : _repository = repository,
        _ytmService = ytmService,
        _playerA = playerA,
        _playerB = playerB {
    _equalizerManager = EqualizerManager(
      equalizerA: equalizerA,
      loudnessEnhancerA: loudnessEnhancerA,
      equalizerB: equalizerB,
      loudnessEnhancerB: loudnessEnhancerB,
    );
    _init();
  }

  factory PulsrAudioHandler(IMusicRepository repository, YtmService ytmService) {
    if (Platform.isAndroid) {
      final eqA = AndroidEqualizer();
      final leA = AndroidLoudnessEnhancer();
      final eqB = AndroidEqualizer();
      final leB = AndroidLoudnessEnhancer();

      final playerA = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [eqA, leA]),
      );
      final playerB = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [eqB, leB]),
      );
      return PulsrAudioHandler._(
        repository: repository,
        ytmService: ytmService,
        playerA: playerA,
        playerB: playerB,
        equalizerA: eqA,
        loudnessEnhancerA: leA,
        equalizerB: eqB,
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
    return MediaItem(
      id: song.id.toString(),
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: Duration(milliseconds: song.durationMs),
      artUri: artUri ??
          (song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null),
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

  double _volume = 1.0;
  double get volume => _volume;

  double _calculateReplayGainVolume(SongsTableData? song) {
    if (song == null) return _volume;
    final rg = song.replayGain;
    if (rg != null && rg != 0.0) {
      final mult = math.pow(10.0, rg / 20.0);
      return (_volume * mult).clamp(0.0, 1.0).toDouble();
    }
    return _volume;
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
    _crossfadeManager.duration = duration;
  }

  Future<void> setEqualizerEnabled(bool enabled) =>
      _equalizerManager.setEqualizerEnabled(enabled);
  Future<void> setBandGain(int bandIndex, double gain) =>
      _equalizerManager.setBandGain(bandIndex, gain);
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
  bool get isSpatializerEnabled => _equalizerManager.isSpatializerEnabled;
  bool get isSpatializerSupported => _equalizerManager.isSpatializerSupported;
  Future<void> setSpatializerEnabled(bool enabled) =>
      _equalizerManager.setSpatializerEnabled(enabled);
  double get volumeBoost => _equalizerManager.volumeBoost;
  Future<void> setVolumeBoost(double value) =>
      _equalizerManager.setVolumeBoost(value);

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
    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      _subscriptions.add(
        player.playbackEventStream.listen((event) {
          if (isPlayerA == _isPlayerAActive) {
            _broadcastState(event);
          }
        }),
      );

      _subscriptions.add(
        player.durationStream.listen((dur) {
          if (isPlayerA == _isPlayerAActive && dur != null && dur > Duration.zero) {
            final current = mediaItem.value;
            if (current != null && current.duration != dur) {
              mediaItem.add(current.copyWith(duration: dur));
            }
          }
        }),
      );

      _subscriptions.add(
        player.playerStateStream.listen((state) {
          if (isPlayerA == _isPlayerAActive) {
            if (state.processingState == ProcessingState.completed &&
                !_crossfadeManager.isCrossfading) {
              skipToNext();
            }
          }
        }),
      );

      _subscriptions.add(
        player.positionStream.listen((pos) {
          if (isPlayerA == _isPlayerAActive) {
            _positionSubject.add(pos);
            _saveCurrentPosition();
            final duration = player.duration ?? Duration.zero;
            // Warm the next YouTube stream URL before the crossfade window even
            // opens, so resolve latency does not truncate the fade. Cheap no-op
            // for local tracks and for an already-cached url.
            if (duration > const Duration(seconds: 15) &&
                pos >= duration - const Duration(seconds: 15)) {
              final peekIdx = _peekNextIndex();
              if (peekIdx != null) _prefetchStream(_songs[peekIdx]);
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
        }),
      );

      _subscriptions.add(
        player.androidAudioSessionIdStream.listen((sessionId) {
          if (sessionId != null && isPlayerA == _isPlayerAActive) {
            AudioEffectsChannel().setAudioSessionId(sessionId);
          }
        }),
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
                  final prefs = await SharedPreferences.getInstance();
                  final resume =
                      prefs.getBool(PrefsKeys.resumeAfterInterruption) ?? true;
                  if (resume && !_activePlayer.playing) {
                    await _activePlayer.play();
                  }
                }
                break;
              case AudioInterruptionType.unknown:
                _wasPlayingBeforeInterruption = false;
                break;
            }
          }
        }),
      );

      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          pause();
        }),
      );
    } catch (e, st) {
      ErrorLogger.log('Error configuring AudioSession',
          error: e, stackTrace: st, category: 'AudioHandler');
    }

    // Initialize audio effects & equalizer preferences
    await _equalizerManager.init();

    // Restore last played song & queue session from database
    await restoreLastPlaybackSession();
  }

  AudioSource _createAudioSource(SongsTableData song, MediaItem tag) {
    if (song.uri?.startsWith('content:') == true ||
        song.path.startsWith('content:')) {
      return AudioSource.uri(Uri.parse(song.uri ?? song.path), tag: tag);
    }
    return AudioSource.file(song.path, tag: tag);
  }

  /// A local song plays straight off disk; a YouTube row needs a freshly
  /// resolved URL, because the last one expires within hours and is pinned to
  /// this device's IP. `LockCachingAudioSource` keeps the fetched bytes so
  /// seeking backwards does not re-hit an already-expired URL.
  Future<AudioSource> _resolveAudioSource(
      SongsTableData song, MediaItem tag) async {
    if (song.source != SongSource.youtube) {
      return _createAudioSource(song, tag);
    }

    // Direct fast path for downloaded songs with physical file on disk
    if (!song.path.startsWith('ytmusic://') && song.path.isNotEmpty && File(song.path).existsSync()) {
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
          (File(localSong.path).existsSync() || localSong.path.startsWith('content:') || (localSong.uri != null && localSong.uri!.startsWith('content:')))) {
        return _createAudioSource(localSong, tag);
      }
    } catch (_) {
      // If local check fails, fall through to stream resolution
    }

    final url = await _resolveStreamUrl(song);
    return AudioSource.uri(Uri.parse(url), tag: tag);
  }

  /// Returns a currently-valid stream URL for a YouTube row, reusing a memoized
  /// one until it nears expiry. Throws [YtmException] when nothing usable comes
  /// back, so the caller can tell "network down" from "skip this track".
  Future<String> _resolveStreamUrl(SongsTableData song) async {
    final videoId = song.remoteId;
    if (videoId == null || videoId.isEmpty) {
      throw const YtmException('YTM_UNAVAILABLE', 'Missing video id');
    }

    final prefs = await SharedPreferences.getInstance();
    final offlineOnly = prefs.getBool('setting_offline_only_mode') ?? false;
    if (offlineOnly) {
      throw const YtmException('OFFLINE_ONLY', 'Offline Only Mode is enabled in Settings');
    }
    final wifiOnly = prefs.getBool('setting_wifi_only_mode') ?? false;
    if (wifiOnly) {
      final isWifi = await _ytmService.isWifiConnected();
      if (!isWifi) {
        throw const YtmException('WIFI_ONLY', 'Wi-Fi Only Mode is enabled. Connect to Wi-Fi to stream');
      }
    }
    final quality = prefs.getString('setting_streaming_quality') ?? 'high';
    final cacheKey = '$videoId-$quality';

    final cached = _streamCache[cacheKey];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.url;
    }
    final stream = await _ytmService.resolveStream(videoId, quality: quality);
    // Cache stream URLs for 2 hours for instant repeated plays and track skips
    _streamCache[cacheKey] =
        (url: stream.url, expires: DateTime.now().add(const Duration(hours: 2)));
    return stream.url;
  }

  /// The index [_getNextIndex] *would* pick, without its shuffle-history side
  /// effect, so a prefetch cannot corrupt the real shuffle order. Returns null
  /// in shuffle mode, where the next track is not knowable in advance.
  int? _peekNextIndex() {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) return _currentIndex;
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) return null;
    if (_currentIndex + 1 < _songs.length) return _currentIndex + 1;
    if (_activePlayer.loopMode == LoopMode.all) return 0;
    return null;
  }

  /// Warms [_streamCache] for an upcoming YouTube track so track switching is instant.
  void _prefetchStream(SongsTableData song) {
    final videoId = song.remoteId;
    if (song.source != SongSource.youtube || videoId == null || videoId.isEmpty) return;
    if (!_prefetching.add(videoId)) return;
    _resolveStreamUrl(song)
        .whenComplete(() => _prefetching.remove(videoId))
        .ignore();
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
        if (currentSong.source == SongSource.youtube) {
          // Resolving a stream URL here runs unawaited at cold start and, if
          // offline, would throw into the catch below and lose the whole
          // restored session. Stay idle; play() resolves it on first tap.
          _pendingLazyPosition = pos;
        } else {
          await _activePlayer.setAudioSource(
            _createAudioSource(currentSong, item),
            initialPosition: pos,
          );
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
    _crossfadeManager.beginCrossfade(nextIndex);
    final currentFadeId = _crossfadeManager.nextFadeId();

    try {
      final nextSong = _songs[nextIndex];
      final artUri = await ArtworkUriResolver.resolveArtworkUri(nextSong);
      final item = _songToMediaItem(nextSong, artUri);

      final source = await _resolveAudioSource(nextSong, item);
      // Resolving a YouTube URL can take seconds. If a skip/stop cancelled this
      // fade meanwhile, loading the source now would push phantom audio into a
      // player that cancel() already stopped — bail on the stale fade.
      if (_crossfadeManager.currentFadeId != currentFadeId) return;

      await _inactivePlayer.setAudioSource(source);

      if (_crossfadeManager.currentFadeId != currentFadeId) return;

      await _inactivePlayer.setVolume(0.0);
      await _inactivePlayer.play();

      if (_crossfadeManager.currentFadeId != currentFadeId) return;

      final active = _activePlayer;
      final inactive = _inactivePlayer;

      await Future.wait([
        _crossfadeManager.fadeVolume(
            active, _volume, 0.0, _crossfadeManager.duration, currentFadeId),
        _crossfadeManager.fadeVolume(
            inactive, 0.0, _volume, _crossfadeManager.duration, currentFadeId),
      ]);

      if (_crossfadeManager.currentFadeId != currentFadeId) return;

      _isPlayerAActive = !_isPlayerAActive;
      _currentIndex = nextIndex;

      final currentSessionId = _activePlayer.androidAudioSessionId;
      if (currentSessionId != null) {
        AudioEffectsChannel().setAudioSessionId(currentSessionId);
      }

      mediaItem.add(_songToMediaItem(nextSong, artUri));
      _repository.recordPlayHistory(nextSong.id);
      _broadcastState(_activePlayer.playbackEvent);

      await active.stop();
      await active.setVolume(_volume);
    } catch (e, st) {
      ErrorLogger.log('Error during crossfade playback',
          error: e, stackTrace: st, category: 'AudioHandler');
      // playerStateStream suppresses the natural completion-skip while a fade is
      // in flight, so a failure here (e.g. a YouTube resolve that threw) would
      // silently dead-end the queue. Recover by hard-playing the destination —
      // playSongAt's own cancel() clears the crossfade and bumps the fade id, so
      // the finally below then correctly skips finishCrossfade. Guarded so a
      // superseded fade does not yank playback.
      if (_crossfadeManager.currentFadeId == currentFadeId) {
        await playSongAt(nextIndex);
      }
    } finally {
      if (_crossfadeManager.currentFadeId == currentFadeId) {
        _crossfadeManager.finishCrossfade();
      }
    }
  }

  int? _getNextIndex() {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) {
      _shuffleHistory.add(_currentIndex);
      if (_shuffleHistory.length > 50) {
        _shuffleHistory.removeAt(0);
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
    if (_currentIndex + 1 < _songs.length) {
      return _currentIndex + 1;
    } else if (_activePlayer.loopMode == LoopMode.all) {
      return 0;
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

    final mediaItems = _songs.map(_songToMediaItem).toList();
    queue.add(mediaItems);

    if (_songs.isNotEmpty) {
      await playSongAt(_currentIndex, initialPosition: initialPosition);
    }
  }

  Future<void> playSongAt(int index, {Duration? initialPosition}) async {
    if (index < 0 || index >= _songs.length) return;
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    // A YouTube resolve below can await for seconds; a second skip during that
    // window must win. Capture a generation token and bail from a stale call
    // after every await, or we get double mediaItem/history and torn state.
    final generation = ++_playGeneration;
    _pendingLazyPosition = null;
    _currentIndex = index;

    final song = _songs[index];
    final fastArtUri = song.artworkUri != null ? Uri.tryParse(song.artworkUri!) : null;
    final item = _songToMediaItem(song, fastArtUri);
    mediaItem.add(item);

    // Resolve high-res artwork in background without blocking audio source loading
    ArtworkUriResolver.resolveArtworkUri(song).then((artUri) {
      if (artUri != null && artUri != fastArtUri && generation == _playGeneration) {
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
      final source = await _resolveAudioSource(song, item);
      if (generation != _playGeneration) return;
      await _activePlayer.setAudioSource(source, initialPosition: initialPosition, preload: true);
      if (generation != _playGeneration) return;
      await _activePlayer.setVolume(_calculateReplayGainVolume(song));
      await _activePlayer.play();
      _consecutiveFailures = 0;
      _repository.recordPlayHistory(song.id);
      _saveCurrentPosition();

      // Early prefetch next stream so next track switch is instantaneous
      final peekIdx = _peekNextIndex();
      if (peekIdx != null && peekIdx < _songs.length) {
        _prefetchStream(_songs[peekIdx]);
      }
    } on YtmException catch (e, st) {
      if (generation != _playGeneration) return;
      ErrorLogger.log(
          'Error resolving YouTube stream for ${song.title} (${e.code})',
          error: e, stackTrace: st, category: 'AudioHandler');
      // A dead network or an extractor-less build fails every remaining YouTube
      // row, so skipping through them is pointless — halt immediately.
      await _failCurrentPlayback(fatal: e.isNetwork || e.isDisabled);
    } catch (e, st) {
      if (generation != _playGeneration) return;
      ErrorLogger.log('Error playing song ${song.title} (${song.path})',
          error: e, stackTrace: st, category: 'AudioHandler');
      await _failCurrentPlayback(fatal: false);
    }
  }

  /// Shared failure handling for [playSongAt]: a fatal error pauses outright,
  /// otherwise skip forward until [_consecutiveFailures] trips the circuit.
  Future<void> _failCurrentPlayback({required bool fatal}) async {
    if (fatal) {
      _consecutiveFailures = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }
    _consecutiveFailures++;
    if (_consecutiveFailures >= 5 || _consecutiveFailures >= _songs.length) {
      _consecutiveFailures = 0;
      await _activePlayer.pause();
      _broadcastState(_activePlayer.playbackEvent);
    } else {
      skipToNext();
    }
  }

  // --- PLAYBACK ACTIONS ---
  @override
  Future<void> play() {
    ErrorLogger.addBreadcrumb('Playback started', category: 'player');
    // A restored YouTube session was left with no source loaded (see
    // restoreLastPlaybackSession); resolve and start it on the first play.
    final pending = _pendingLazyPosition;
    if (pending != null && currentSong != null) {
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
        restoreVolume: _volume);
    _saveCurrentPosition();
    await _activePlayer.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    ErrorLogger.addBreadcrumb('Playback seek to ${position.inSeconds}s', category: 'player');
    await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
        restoreVolume: _volume);
    await _activePlayer.seek(position);
    _positionSubject.add(position);
    _saveCurrentPosition();
  }

  @override
  Future<void> skipToNext() async {
    ErrorLogger.addBreadcrumb('Playback skipToNext', category: 'player');
    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
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
    ErrorLogger.addBreadcrumb('Playback skipToPrevious', category: 'player');
    if (_crossfadeManager.isCrossfading) {
      await _crossfadeManager.cancel(_inactivePlayer, _activePlayer,
          restoreVolume: _volume);
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
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode = LoopMode.off;
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        loopMode = LoopMode.off;
        break;
      case AudioServiceRepeatMode.one:
        loopMode = LoopMode.one;
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        loopMode = LoopMode.all;
        break;
    }
    await _playerA.setLoopMode(loopMode);
    await _playerB.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _playerA.setSpeed(speed);
    await _playerB.setSpeed(speed);
    playbackState.add(playbackState.value.copyWith(speed: speed));
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'toggleFavorite') {
      if (_songs.isNotEmpty && _currentIndex < _songs.length) {
        final currentSong = _songs[_currentIndex];
        final result = await _repository.toggleFavorite(currentSong.id);
        final newFav = result.fold((l) => currentSong.isFavorite, (r) => r);
        _songs[_currentIndex] = currentSong.copyWith(isFavorite: newFav);
        final artUri =
            await ArtworkUriResolver.resolveArtworkUri(_songs[_currentIndex]);
        mediaItem.add(_songToMediaItem(_songs[_currentIndex], artUri));
      }
      return true;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final songId = int.tryParse(mediaItem.id);
    if (songId != null) {
      final songRes = await _repository.getSongById(songId);
      final song = songRes.fold((l) => null, (r) => r);
      if (song != null) {
        _songs.add(song);
        _queueDirty = true;
        queue.add(_songs.map(_songToMediaItem).toList());
        _saveCurrentPosition();
      }
    }
  }

  Future<void> insertNextInQueue(SongsTableData song) async {
    final insertIdx =
        _songs.isEmpty ? 0 : (_currentIndex + 1).clamp(0, _songs.length);
    _songs.insert(insertIdx, song);
    _queueDirty = true;
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  Future<void> addToQueueEnd(SongsTableData song) async {
    _songs.add(song);
    _queueDirty = true;
    queue.add(_songs.map(_songToMediaItem).toList());
    _saveCurrentPosition();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final wasPlayingCurrent = index == _currentIndex;
    _songs.removeAt(index);
    _queueDirty = true;

    if (_songs.isEmpty) {
      _currentIndex = 0;
      queue.add([]);
      mediaItem.add(null);
      await stop();
      return;
    }

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (wasPlayingCurrent) {
      _currentIndex = _currentIndex.clamp(0, _songs.length - 1);
      await playSongAt(_currentIndex);
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
        return const [
          MediaItem(
            id: 'songs',
            title: 'Songs',
            playable: false,
          ),
          MediaItem(
            id: 'albums',
            title: 'Albums',
            playable: false,
          ),
          MediaItem(
            id: 'artists',
            title: 'Artists',
            playable: false,
          ),
          MediaItem(
            id: 'playlists',
            title: 'Playlists',
            playable: false,
          ),
          MediaItem(
            id: 'favorites',
            title: 'Favorites',
            playable: false,
          ),
          MediaItem(
            id: 'recent',
            title: 'Recently Played',
            playable: false,
          ),
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
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) return;
    final cleanQ = query.trim();
    final songsRes = await _repository.getAllSongs();
    final allSongs = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    if (allSongs.isEmpty) return;

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
    // 4. Default fallback: play first available song
    await loadQueue(allSongs);
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

  @disposeMethod
  void dispose() {
    _savePositionDebounce?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _positionSubject.close();
    _sleepTimerManager.dispose();
    _equalizerManager.dispose();
    AudioEffectsChannel().releaseEffects();
    _playerA.dispose();
    _playerB.dispose();
  }
}
