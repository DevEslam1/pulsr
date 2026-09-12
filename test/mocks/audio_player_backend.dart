// test/mocks/audio_player_backend.dart
//
// Test-only playback backend seam. This abstraction is not used in production
// (the handler drives just_audio directly); it exists so deterministic fake
// players can be injected into playback-engine tests.
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
  List<AudioSource> get audioSources;
  bool get hasNext;
  bool get hasPrevious;
  LoopMode get loopMode;
  bool get shuffleModeEnabled;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {int? index});
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> shuffle();
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
