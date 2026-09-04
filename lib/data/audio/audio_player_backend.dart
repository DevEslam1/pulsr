// lib/data/audio/audio_player_backend.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';

/// Abstract backend interface wrapping [AudioPlayer] for complete testability,
/// clock-driven simulation, and gapless/crossfade virtualization.
abstract class AudioPlayerBackend {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<PlayerState> get playerStateStream;
  Stream<ProcessingState> get processingStateStream;
  Stream<bool> get playingStream;
  Stream<double> get volumeStream;
  Stream<double> get speedStream;
  Stream<SequenceState?> get sequenceStateStream;

  Duration get position;
  Duration? get duration;
  Duration get bufferedPosition;
  PlayerState get playerState;
  ProcessingState get processingState;
  bool get playing;
  double get volume;
  double get speed;
  int? get currentIndex;
  SequenceState? get sequenceState;
  AudioSource? get audioSource;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {int? index});
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  });
  Future<Duration?> setAudioSources(
    List<AudioSource> children, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  });
  Future<void> setShuffleModeEnabled(bool enabled);
  Future<void> setLoopMode(LoopMode loopMode);
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> dispose();
}

/// Production implementation of [AudioPlayerBackend] delegating directly to [just_audio.AudioPlayer].
class JustAudioPlayerBackend implements AudioPlayerBackend {
  final AudioPlayer _player;

  JustAudioPlayerBackend([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  AudioPlayer get player => _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Stream<double> get volumeStream => _player.volumeStream;
  @override
  Stream<double> get speedStream => _player.speedStream;
  @override
  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  @override
  PlayerState get playerState => _player.playerState;
  @override
  ProcessingState get processingState => _player.processingState;
  @override
  bool get playing => _player.playing;
  @override
  double get volume => _player.volume;
  @override
  double get speed => _player.speed;
  @override
  int? get currentIndex => _player.currentIndex;
  @override
  SequenceState? get sequenceState => _player.sequenceState;
  @override
  AudioSource? get audioSource => _player.audioSource;

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) =>
      _player.setAudioSource(source,
          preload: preload,
          initialIndex: initialIndex,
          initialPosition: initialPosition);
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> children, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) =>
      _player.setAudioSources(
        children,
        preload: preload,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
        shuffleOrder: shuffleOrder,
      );
  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);
  @override
  Future<void> setLoopMode(LoopMode loopMode) => _player.setLoopMode(loopMode);
  @override
  Future<void> seekToNext() => _player.seekToNext();
  @override
  Future<void> seekToPrevious() => _player.seekToPrevious();
  @override
  Future<void> dispose() => _player.dispose();
}
