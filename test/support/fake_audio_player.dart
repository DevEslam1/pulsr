// test/support/fake_audio_player.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

/// Test double implementing the subset of [AudioPlayer] surface used by [PulsrAudioHandler].
class FakeAudioPlayer extends Mock implements AudioPlayer {
  final StreamController<PlaybackEvent> _playbackEventController =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<ProcessingState> _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<double> _speedController =
      StreamController<double>.broadcast();

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  ProcessingState _processingState = ProcessingState.idle;
  double _volume = 1.0;
  double _speed = 1.0;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleModeEnabled = false;
  AudioSource? _audioSource;
  int? _currentIndex;

  final List<double> volumeHistory = [];
  bool disposed = false;

  FakeAudioPlayer({
    bool playing = false,
    Duration position = Duration.zero,
    Duration? duration,
    ProcessingState processingState = ProcessingState.idle,
    double volume = 1.0,
  })  : _playing = playing,
        _position = position,
        _duration = duration,
        _processingState = processingState,
        _volume = volume {
    volumeHistory.add(volume);
  }

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => _duration;

  @override
  ProcessingState get processingState => _processingState;

  @override
  PlayerState get playerState => PlayerState(_playing, _processingState);

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  LoopMode get loopMode => _loopMode;

  @override
  bool get shuffleModeEnabled => _shuffleModeEnabled;

  @override
  AudioSource? get audioSource => _audioSource;

  @override
  int? get currentIndex => _currentIndex;

  @override
  Stream<PlaybackEvent> get playbackEventStream =>
      _playbackEventController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<double> get speedStream => _speedController.stream;

  @override
  Future<void> play() async {
    _playing = true;
    _playingController.add(true);
    _playerStateController.add(playerState);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playingController.add(false);
    _playerStateController.add(playerState);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _processingState = ProcessingState.idle;
    _playingController.add(false);
    _processingStateController.add(_processingState);
    _playerStateController.add(playerState);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _positionController.add(position);
    }
    if (index != null) {
      _currentIndex = index;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumeHistory.add(volume);
    _volumeController.add(volume);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    _speedController.add(speed);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleModeEnabled = enabled;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _audioSource = source;
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    _processingState = ProcessingState.ready;
    _processingStateController.add(_processingState);
    _playerStateController.add(playerState);
    return _duration;
  }

  @override
  Future<bool> dspClearGainCurve() async => false;

  @override
  Future<bool> dspSetGainCurve(List<double> gains,
          {int segmentMs = 20}) async =>
      false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _playbackEventController.close();
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
    await _processingStateController.close();
    await _playingController.close();
    await _volumeController.close();
    await _speedController.close();
  }

  // Controllable test triggers:
  void emitPosition(Duration pos) {
    _position = pos;
    _positionController.add(pos);
  }

  void emitProcessingState(ProcessingState state) {
    _processingState = state;
    _processingStateController.add(state);
    _playerStateController.add(playerState);
  }

  void emitDuration(Duration? dur) {
    _duration = dur;
    _durationController.add(dur);
  }
}
