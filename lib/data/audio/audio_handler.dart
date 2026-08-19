// lib/data/audio/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/eq_preset.dart';
import '../db/app_database.dart';
import '../repositories/music_repository.dart';

class PulsrAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player;
  final MusicRepository _repository;
  final AndroidEqualizer? _equalizer;
  final AndroidLoudnessEnhancer? _loudnessEnhancer;
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true,
  );

  static final OnAudioQuery _audioQuery = OnAudioQuery();
  static final Map<int, Uri> _cachedArtworkUris = {};

  List<SongsTableData> _songs = [];
  Timer? _sleepTimer;
  Timer? _positionPersistTimer;
  EqPreset _currentPreset = EqPreset.defaultPresets.first;
  bool _eqEnabled = false;

  PulsrAudioHandler._({
    required MusicRepository repository,
    required AudioPlayer player,
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  })  : _repository = repository,
        _player = player,
        _equalizer = equalizer,
        _loudnessEnhancer = loudnessEnhancer {
    _init();
  }

  factory PulsrAudioHandler(MusicRepository repository) {
    if (Platform.isAndroid) {
      final eq = AndroidEqualizer();
      final le = AndroidLoudnessEnhancer();
      final player = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [eq, le]),
      );
      return PulsrAudioHandler._(
        repository: repository,
        player: player,
        equalizer: eq,
        loudnessEnhancer: le,
      );
    } else {
      final player = AudioPlayer();
      return PulsrAudioHandler._(
        repository: repository,
        player: player,
      );
    }
  }

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

  Future<void> _init() async {
    // Pipe player events to AudioService state
    _player.playbackEventStream.listen(_broadcastState);

    // Track changes
    _player.currentIndexStream.listen((index) async {
      if (index != null && index >= 0 && index < _songs.length) {
        final song = _songs[index];
        final artUri = await getArtworkUri(song.id);
        final item = _songToMediaItem(song, artUri);
        mediaItem.add(item);
        _repository.recordPlayHistory(song.id);
      }
    });

    // Position updates for memory
    _player.positionStream.listen((position) {
      final current = _player.currentIndex;
      if (current != null && current >= 0 && current < _songs.length) {
        _positionPersistTimer?.cancel();
        _positionPersistTimer = Timer(const Duration(seconds: 3), () {
          _repository.updateLastPosition(_songs[current].id, position.inMilliseconds);
        });
      }
    });

    try {
      await _player.setAudioSource(_playlist);
    } catch (e) {
      // Audio source initialized
    }
  }

  MediaItem _songToMediaItem(SongsTableData song, [Uri? artUri]) {
    final uri = artUri ??
        _cachedArtworkUris[song.id] ??
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
      extras: {
        'path': song.path,
        'isFavorite': song.isFavorite,
      },
    );
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final queueIndex = event.currentIndex;

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
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: queueIndex,
        shuffleMode: _player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        repeatMode: switch (_player.loopMode) {
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enable);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    _broadcastState(_player.playbackEvent);
  }

  Future<void> loadQueue(List<SongsTableData> songs, {int initialIndex = 0, Duration? initialPosition}) async {
    _songs = List.from(songs);
    final audioSources = songs.map((s) => AudioSource.file(s.path, tag: _songToMediaItem(s))).toList();

    await _playlist.clear();
    await _playlist.addAll(audioSources);

    queue.add(songs.map(_songToMediaItem).toList());

    if (songs.isNotEmpty && initialIndex < songs.length) {
      final initialSong = songs[initialIndex];
      final artUri = await getArtworkUri(initialSong.id);
      mediaItem.add(_songToMediaItem(initialSong, artUri));

      await _player.seek(initialPosition ?? Duration.zero, index: initialIndex);
      await play();
    }

    // Persist queue in Drift
    await _repository.saveQueue(songs.map((s) => s.id).toList(), initialIndex, 0);
  }

  Future<void> playSongAt(int index) async {
    if (index >= 0 && index < _songs.length) {
      await _player.seek(Duration.zero, index: index);
      await play();
    }
  }

  Future<void> playNext(SongsTableData song) async {
    final currentIndex = _player.currentIndex ?? 0;
    final insertIndex = (_songs.isEmpty || currentIndex >= _songs.length) ? 0 : currentIndex + 1;
    _songs.insert(insertIndex, song);
    await _playlist.insert(insertIndex, AudioSource.file(song.path, tag: _songToMediaItem(song)));
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  Future<void> addToQueue(SongsTableData song) async {
    _songs.add(song);
    await _playlist.add(AudioSource.file(song.path, tag: _songToMediaItem(song)));
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index >= 0 && index < _songs.length) {
      _songs.removeAt(index);
      await _playlist.removeAt(index);
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
    await _playlist.move(oldIndex, newIndex);
    queue.add(_songs.map(_songToMediaItem).toList());
  }

  // --- SLEEP TIMER ---
  void startSleepTimer(Duration duration, {bool fadeOut = true}) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () async {
      if (fadeOut) {
        for (double v = 1.0; v >= 0.0; v -= 0.1) {
          await _player.setVolume(v.clamp(0.0, 1.0));
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      await pause();
      await _player.setVolume(1.0);
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
    _player.setVolume(1.0);
  }

  // --- ANDROID AUTO / MEDIA BROWSER TREE ---
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case 'root':
        return const [
          MediaItem(
            id: 'root_songs',
            title: 'Songs',
            playable: false,
          ),
          MediaItem(
            id: 'root_favorites',
            title: 'Favorites',
            playable: false,
          ),
        ];
      case 'root_songs':
        final songs = await _repository.getAllSongs();
        return songs.fold((l) => [], (r) => r.map(_songToMediaItem).toList());
      default:
        return [];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final id = int.tryParse(mediaId);
    if (id == null) return null;
    final songs = await _repository.getAllSongs();
    return songs.fold((l) => null, (list) {
      final match = list.where((s) => s.id == id).firstOrNull;
      return match != null ? _songToMediaItem(match) : null;
    });
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
