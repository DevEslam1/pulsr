// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:injectable/injectable.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/eq_preset.dart';
import '../db/app_database.dart';
import '../repositories/music_repository.dart';

@singleton
class PulsrAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  @factoryMethod
  @preResolve
  static Future<PulsrAudioHandler> create(MusicRepository repository) async {
    return await AudioService.init(
      builder: () => PulsrAudioHandler(repository),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.pulsr.audio',
        androidNotificationChannelName: 'Pulsr Audio Playback',
        androidNotificationOngoing: true,
        androidNotificationClickStartsActivity: true,
        androidStopForegroundOnPause: true,
        androidResumeOnClick: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  }

  final AudioPlayer _playerA;
  final AudioPlayer _playerB;
  bool _isPlayerAActive = true;

  AudioPlayer get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  AudioPlayer get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;

  final MusicRepository _repository;
  final AndroidEqualizer? _equalizer;
  final AndroidLoudnessEnhancer? _loudnessEnhancer;

  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static final Map<int, Uri> _cachedArtworkUris = {};
  static final Map<int, Uri> _cachedAlbumArtUris = {};
  static final Map<int, Uri> _cachedArtistArtUris = {};

  List<SongsTableData> _songs = [];
  int _currentIndex = 0;
  Timer? _sleepTimer;
  Timer? _positionPersistTimer;
  EqPreset _currentPreset = EqPreset.defaultPresets.first;
  bool _eqEnabled = false;

  Duration _crossfadeDuration = Duration.zero;
  bool _isCrossfading = false;
  int _fadeId = 0;

  PulsrAudioHandler._({
    required MusicRepository repository,
    required AudioPlayer playerA,
    required AudioPlayer playerB,
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  })  : _repository = repository,
        _playerA = playerA,
        _playerB = playerB,
        _equalizer = equalizer,
        _loudnessEnhancer = loudnessEnhancer {
    _init();
  }

  factory PulsrAudioHandler(MusicRepository repository) {
    if (Platform.isAndroid) {
      final eq = AndroidEqualizer();
      final le = AndroidLoudnessEnhancer();
      final playerA = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [eq, le]),
      );
      final playerB = AudioPlayer();
      return PulsrAudioHandler._(
        repository: repository,
        playerA: playerA,
        playerB: playerB,
        equalizer: eq,
        loudnessEnhancer: le,
      );
    } else {
      final playerA = AudioPlayer();
      final playerB = AudioPlayer();
      return PulsrAudioHandler._(
        repository: repository,
        playerA: playerA,
        playerB: playerB,
      );
    }
  }

  void setCrossfadeDuration(Duration d) {
    _crossfadeDuration = d;
  }

  Duration get crossfadeDuration => _crossfadeDuration;

  static Future<Uri?> getArtworkUri(int songId) async {
    if (_cachedArtworkUris.containsKey(songId)) {
      return _cachedArtworkUris[songId];
    }
    try {
      final bytes = await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 500,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/pulsr_art_$songId.jpg');
        await file.writeAsBytes(bytes);
        final uri = Uri.file(file.path);
        _cachedArtworkUris[songId] = uri;
        return uri;
      }
    } catch (_) {}
    return null;
  }

  static Future<Uri?> _albumArtUri(int albumId) async {
    if (_cachedAlbumArtUris.containsKey(albumId)) {
      return _cachedAlbumArtUris[albumId];
    }
    try {
      final bytes = await _audioQuery.queryArtwork(
        albumId,
        ArtworkType.ALBUM,
        format: ArtworkFormat.JPEG,
        size: 500,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/pulsr_album_art_$albumId.jpg');
        await file.writeAsBytes(bytes);
        final uri = Uri.file(file.path);
        _cachedAlbumArtUris[albumId] = uri;
        return uri;
      }
    } catch (_) {}
    return null;
  }

  static Future<Uri?> _artistArtUri(int artistId) async {
    if (_cachedArtistArtUris.containsKey(artistId)) {
      return _cachedArtistArtUris[artistId];
    }
    try {
      final bytes = await _audioQuery.queryArtwork(
        artistId,
        ArtworkType.ARTIST,
        format: ArtworkFormat.JPEG,
        size: 500,
        quality: 95,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/pulsr_artist_art_$artistId.jpg');
        await file.writeAsBytes(bytes);
        final uri = Uri.file(file.path);
        _cachedArtistArtUris[artistId] = uri;
        return uri;
      }
    } catch (_) {}
    return null;
  }

  static Future<Uri?> _resolveArtworkUri(SongsTableData song) async {
    var uri = await getArtworkUri(song.id);
    if (uri == null && song.albumId != null) {
      uri = await _albumArtUri(song.albumId!);
    }
    return uri;
  }

  Future<void> _fadeVolume(AudioPlayer player, double from, double to, Duration duration, int fadeId) async {
    if (duration == Duration.zero) {
      await player.setVolume(to);
      return;
    }
    const steps = 20;
    final stepDuration = Duration(milliseconds: (duration.inMilliseconds / steps).round());
    final volumeDelta = (to - from) / steps;

    await player.setVolume(from);
    for (int i = 1; i <= steps; i++) {
      if (_fadeId != fadeId) break;
      await Future.delayed(stepDuration);
      if (_fadeId != fadeId) break;
      final nextVolume = (from + volumeDelta * i).clamp(0.0, 1.0);
      await player.setVolume(nextVolume);
    }
  }

  void _cancelCrossfade() {
    if (_isCrossfading) {
      _fadeId++;
      _isCrossfading = false;
      _inactivePlayer.stop();
      _inactivePlayer.setVolume(1.0);
      _activePlayer.setVolume(1.0);
    }
  }

  Future<void> _init() async {
    void setupPlayerListeners(AudioPlayer player, bool isPlayerA) {
      player.playbackEventStream.listen((event) {
        if (isPlayerA == _isPlayerAActive) {
          _broadcastState(event);
        }
      });

      player.playerStateStream.listen((state) {
        if (isPlayerA == _isPlayerAActive) {
          if (state.processingState == ProcessingState.completed && !_isCrossfading) {
            skipToNext();
          }
        }
      });

      player.positionStream.listen((position) async {
        if (isPlayerA == _isPlayerAActive) {
          final current = _currentIndex;
          if (current >= 0 && current < _songs.length) {
            _positionPersistTimer?.cancel();
            _positionPersistTimer = Timer(const Duration(seconds: 3), () {
              _repository.updateLastPosition(_songs[current].id, position.inMilliseconds);
            });
          }

          // Crossfade trigger logic
          final duration = player.duration;
          if (_crossfadeDuration > Duration.zero &&
              duration != null &&
              duration > _crossfadeDuration &&
              position > Duration.zero &&
              !_isCrossfading &&
              player.playing &&
              player.loopMode != LoopMode.one) {
            final remaining = duration - position;
            if (remaining <= _crossfadeDuration) {
              final nextIdx = _getNextIndex();
              if (nextIdx != null && nextIdx != _currentIndex) {
                _startCrossfade(nextIdx);
              }
            }
          }
        }
      });
    }

    setupPlayerListeners(_playerA, true);
    setupPlayerListeners(_playerB, false);

    // AudioSession configuration
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await _activePlayer.setVolume(0.3);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              await pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await _activePlayer.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              final prefs = await SharedPreferences.getInstance();
              final resume = prefs.getBool('setting_resume_after_interruption') ?? true;
              if (resume) {
                await play();
              }
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    } catch (_) {}
  }

  Future<void> _startCrossfade(int nextIndex) async {
    if (_isCrossfading) return;
    _isCrossfading = true;
    final currentFadeId = ++_fadeId;

    try {
      final nextSong = _songs[nextIndex];
      final artUri = await _resolveArtworkUri(nextSong);

      await _inactivePlayer.setAudioSource(
        AudioSource.file(nextSong.path, tag: _songToMediaItem(nextSong, artUri)),
      );

      if (_fadeId != currentFadeId) return;

      await _inactivePlayer.setVolume(0.0);
      await _inactivePlayer.play();

      if (_fadeId != currentFadeId) return;

      final active = _activePlayer;
      final inactive = _inactivePlayer;

      await Future.wait([
        _fadeVolume(active, 1.0, 0.0, _crossfadeDuration, currentFadeId),
        _fadeVolume(inactive, 0.0, 1.0, _crossfadeDuration, currentFadeId),
      ]);

      if (_fadeId != currentFadeId) return;

      _isPlayerAActive = !_isPlayerAActive;
      _currentIndex = nextIndex;

      mediaItem.add(_songToMediaItem(nextSong, artUri));
      _repository.recordPlayHistory(nextSong.id);
      _broadcastState(_activePlayer.playbackEvent);

      await active.stop();
      await active.setVolume(1.0);
    } catch (_) {
    } finally {
      if (_fadeId == currentFadeId) {
        _isCrossfading = false;
      }
    }
  }

  int? _getNextIndex() {
    if (_songs.isEmpty) return null;
    if (_activePlayer.loopMode == LoopMode.one) {
      return _currentIndex;
    }
    if (_activePlayer.shuffleModeEnabled && _songs.length > 1) {
      final random = math.Random();
      int next = random.nextInt(_songs.length);
      while (next == _currentIndex && _songs.length > 1) {
        next = random.nextInt(_songs.length);
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
    if (_currentIndex - 1 >= 0) {
      return _currentIndex - 1;
    } else if (_activePlayer.loopMode == LoopMode.all) {
      return _songs.length - 1;
    }
    return null;
  }

  MediaItem _songToMediaItem(SongsTableData song, [Uri? artUri]) {
    final uri = artUri ??
        _cachedArtworkUris[song.id] ??
        (song.albumId != null ? _cachedAlbumArtUris[song.albumId!] : null) ??
        (song.artworkUri != null
            ? Uri.parse('content://media/external/audio/albumart/${song.albumId ?? 0}')
            : null);

    return MediaItem(
      id: song.id.toString(),
      album: song.album,
      title: song.title,
      artist: song.artist,
      duration: Duration(milliseconds: song.durationMs),
      artUri: uri,
      playable: true,
      extras: {
        'path': song.path,
        'isFavorite': song.isFavorite,
        if (song.albumId != null) 'albumId': song.albumId,
        if (song.artistId != null) 'artistId': song.artistId,
      },
    );
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _activePlayer.playing;
    final queueIndex = _currentIndex;

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_activePlayer.processingState]!,
        playing: playing,
        updatePosition: _activePlayer.position,
        bufferedPosition: _activePlayer.bufferedPosition,
        speed: _activePlayer.speed,
        queueIndex: queueIndex,
        shuffleMode: _activePlayer.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        repeatMode: switch (_activePlayer.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  // --- EQUALIZER & AUDIO EFFECTS ---
  bool get isEqualizerEnabled => _eqEnabled;
  EqPreset get currentPreset => _currentPreset;

  Future<void> setEqualizerEnabled(bool enabled) async {
    _eqEnabled = enabled;
    final equalizer = _equalizer;
    if (equalizer != null) {
      await equalizer.setEnabled(enabled);
    }
  }

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    final equalizer = _equalizer;
    if (equalizer != null) {
      final parameters = await equalizer.parameters;
      if (bandIndex >= 0 && bandIndex < parameters.bands.length) {
        await parameters.bands[bandIndex].setGain(gainDb);
      }
    }
  }

  Future<void> setBassBoost(double amount) async {
    final loudnessEnhancer = _loudnessEnhancer;
    if (loudnessEnhancer != null) {
      await loudnessEnhancer.setEnabled(amount > 0);
      await loudnessEnhancer.setTargetGain(amount * 1.5);
    }
  }

  Future<void> applyPreset(EqPreset preset) async {
    _currentPreset = preset;
    final equalizer = _equalizer;
    if (equalizer != null) {
      final parameters = await equalizer.parameters;
      for (int i = 0; i < preset.gains.length && i < parameters.bands.length; i++) {
        await parameters.bands[i].setGain(preset.gains[i]);
      }
    }
    await setBassBoost(preset.bassBoost);
  }

  // --- PLAYBACK ACTIONS ---
  @override
  Future<void> play() => _activePlayer.play();

  @override
  Future<void> pause() async {
    _cancelCrossfade();
    await _activePlayer.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _cancelCrossfade();
    await _activePlayer.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_isCrossfading) {
      _fadeId++;
      _isCrossfading = false;
      await _activePlayer.stop();
      await _activePlayer.setVolume(1.0);
      await _inactivePlayer.setVolume(1.0);
      _isPlayerAActive = !_isPlayerAActive;
      _broadcastState(_activePlayer.playbackEvent);
      return;
    }

    final nextIdx = _getNextIndex();
    if (nextIdx != null) {
      await playSongAt(nextIdx);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _cancelCrossfade();
    final prevIdx = _getPreviousIndex();
    if (prevIdx != null) {
      await playSongAt(prevIdx);
    } else {
      await _activePlayer.seek(Duration.zero);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await _playerA.setShuffleModeEnabled(enable);
    await _playerB.setShuffleModeEnabled(enable);
    _broadcastState(_activePlayer.playbackEvent);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _playerA.setLoopMode(loopMode);
    await _playerB.setLoopMode(loopMode);
    _broadcastState(_activePlayer.playbackEvent);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _playerA.setSpeed(speed);
    await _playerB.setSpeed(speed);
    _broadcastState(_activePlayer.playbackEvent);
  }

  Future<void> loadQueue(List<SongsTableData> songs, {int initialIndex = 0, Duration? initialPosition}) async {
    _cancelCrossfade();
    _songs = List.from(songs);
    _currentIndex = initialIndex;

    queue.add(songs.map(_songToMediaItem).toList());

    if (songs.isNotEmpty && initialIndex >= 0 && initialIndex < songs.length) {
      final initialSong = songs[initialIndex];
      final artUri = await _resolveArtworkUri(initialSong);
      mediaItem.add(_songToMediaItem(initialSong, artUri));

      await _activePlayer.setAudioSource(
        AudioSource.file(initialSong.path, tag: _songToMediaItem(initialSong, artUri)),
      );
      if (initialPosition != null && initialPosition > Duration.zero) {
        await _activePlayer.seek(initialPosition);
      }
      await play();
    }

    // Persist queue in Drift
    await _repository.saveQueue(songs.map((s) => s.id).toList(), initialIndex, 0);
  }

  Future<void> playSongAt(int index) async {
    _cancelCrossfade();
    if (index >= 0 && index < _songs.length) {
      _currentIndex = index;
      final song = _songs[index];
      final artUri = await _resolveArtworkUri(song);
      mediaItem.add(_songToMediaItem(song, artUri));

      await _activePlayer.setAudioSource(
        AudioSource.file(song.path, tag: _songToMediaItem(song, artUri)),
      );
      await play();
    }
  }

  Future<void> playNext(SongsTableData song) async {
    final insertIndex = (_songs.isEmpty || _currentIndex >= _songs.length) ? 0 : _currentIndex + 1;
    _songs.insert(insertIndex, song);
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  Future<void> addToQueue(SongsTableData song) async {
    _songs.add(song);
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index >= 0 && index < _songs.length) {
      _songs.removeAt(index);
      if (_currentIndex >= _songs.length) {
        _currentIndex = (_songs.length - 1).clamp(0, _songs.length);
      }
      queue.add(_songs.map(_songToMediaItem).toList());
    }
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _songs.indexWhere((s) => s.id.toString() == mediaItem.id);
    if (index != -1) {
      await removeQueueItemAt(index);
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  // --- SLEEP TIMER ---
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () async {
      final player = _activePlayer;
      if (fadeOut) {
        for (double v = 1.0; v >= 0.0; v -= 0.1) {
          await player.setVolume(v.clamp(0.0, 1.0));
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      await pause();
      await player.setVolume(1.0);
    });
  }

  void startAbsoluteSleepTimer(DateTime stopTime, {bool fadeOut = true}) {
    final now = DateTime.now();
    final difference = stopTime.isAfter(now) ? stopTime.difference(now) : stopTime.add(const Duration(days: 1)).difference(now);
    startSleepTimer(difference, fadeOut: fadeOut);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _activePlayer.setVolume(1.0);
  }

  double get volume => _activePlayer.volume;

  Future<void> setVolume(double volume) async {
    await _activePlayer.setVolume(volume.clamp(0.0, 1.0));
  }

  // --- ANDROID AUTO / MEDIA BROWSER TREE ---
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case AudioService.recentRootId:
      case 'root_recent':
        final recentRes = await _repository.getRecentlyPlayed();
        final list = recentRes.fold((l) => <SongsTableData>[], (r) => r);
        final items = <MediaItem>[];
        for (final song in list) {
          final artUri = await _resolveArtworkUri(song);
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
          final artUri = await _resolveArtworkUri(song);
          items.add(_songToMediaItem(song, artUri));
        }
        return items;

      case 'albums':
      case 'root_albums':
        final albumsRes = await _repository.getAlbums();
        final list = albumsRes.fold((l) => <AlbumsTableData>[], (r) => r);
        final items = <MediaItem>[];
        for (final album in list) {
          final artUri = await _albumArtUri(album.id);
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
          final artUri = await _artistArtUri(artist.id);
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
          final artUri = await _resolveArtworkUri(song);
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
            final artUri = await _resolveArtworkUri(song);
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
            final artUri = await _resolveArtworkUri(song);
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
            final artUri = await _resolveArtworkUri(song);
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
    final songsRes = await _repository.getAllSongs();
    final list = songsRes.fold((l) => <SongsTableData>[], (r) => r);
    final match = list.where((s) => s.id == id).firstOrNull;
    if (match == null) return null;
    final artUri = await _resolveArtworkUri(match);
    return _songToMediaItem(match, artUri);
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
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

    if (mediaId == 'recent' || mediaId == 'root_recent' || mediaId == AudioService.recentRootId) {
      final songsRes = await _repository.getRecentlyPlayed();
      songsRes.fold((l) => null, (songs) {
        if (songs.isNotEmpty) loadQueue(songs);
      });
      return;
    }
  }

  @override
  Future<void> stop() async {
    _cancelCrossfade();
    await _playerA.stop();
    await _playerB.stop();
    await super.stop();
  }
}
