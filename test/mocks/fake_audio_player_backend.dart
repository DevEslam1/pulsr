// test/mocks/fake_audio_player_backend.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:pulsr/data/audio/audio_player_backend.dart';

/// Simulated, deterministic clock-driven fake audio backend for testing playback engines,
/// queue mutations, crossfade schedules, and sleep timers without touching native platform audio.
class FakeAudioPlayerBackend implements AudioPlayerBackend {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<Duration> _bufferedPositionController =
      StreamController<Duration>.broadcast();
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
  final StreamController<SequenceState?> _sequenceStateController =
      StreamController<SequenceState?>.broadcast();

  Duration _position = Duration.zero;
  Duration? _duration = const Duration(minutes: 3, seconds: 30);
  final Duration _bufferedPosition = Duration.zero;
  ProcessingState _processingState = ProcessingState.idle;
  bool _playing = false;
  double _volume = 1.0;
  double _speed = 1.0;
  int? _currentIndex = 0;
  SequenceState? _sequenceState;
  AudioSource? _audioSource;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  List<AudioSource> _sources = [];

  FakeAudioPlayerBackend() {
    _emitState();
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;
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
  Stream<SequenceState?> get sequenceStateStream =>
      _sequenceStateController.stream;

  @override
  Duration get position => _position;
  @override
  Duration? get duration => _duration;
  @override
  Duration get bufferedPosition => _bufferedPosition;
  @override
  PlayerState get playerState => PlayerState(_playing, _processingState);
  @override
  ProcessingState get processingState => _processingState;
  @override
  bool get playing => _playing;
  @override
  double get volume => _volume;
  @override
  double get speed => _speed;
  @override
  int? get currentIndex => _currentIndex;
  @override
  SequenceState? get sequenceState => _sequenceState;
  @override
  AudioSource? get audioSource => _audioSource;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  List<AudioSource> get sources => List.unmodifiable(_sources);

  void _emitState() {
    _positionController.add(_position);
    _durationController.add(_duration);
    _bufferedPositionController.add(_bufferedPosition);
    _playerStateController.add(PlayerState(_playing, _processingState));
    _processingStateController.add(_processingState);
    _playingController.add(_playing);
    _volumeController.add(_volume);
    _speedController.add(_speed);
    _sequenceStateController.add(_sequenceState);
  }

  /// Advances the simulated playback clock by [delta], advancing position and emitting updates.
  void tickClock(Duration delta) {
    if (!_playing || _processingState != ProcessingState.ready) return;
    _position += delta;
    if (_duration != null && _position >= _duration!) {
      _position = _duration!;
      _processingState = ProcessingState.completed;
      _playing = false;
    }
    _positionController.add(_position);
    _playerStateController.add(PlayerState(_playing, _processingState));
    _processingStateController.add(_processingState);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _processingState = ProcessingState.ready;
    _playerStateController.add(PlayerState(_playing, _processingState));
    _playingController.add(_playing);
    _processingStateController.add(_processingState);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playerStateController.add(PlayerState(_playing, _processingState));
    _playingController.add(_playing);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _processingState = ProcessingState.idle;
    _position = Duration.zero;
    _playerStateController.add(PlayerState(_playing, _processingState));
    _playingController.add(_playing);
    _positionController.add(_position);
    _processingStateController.add(_processingState);
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    _position = position;
    if (index != null) {
      _currentIndex = index;
    }
    _positionController.add(_position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _volumeController.add(_volume);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.1, 4.0);
    _speedController.add(_speed);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    _audioSource = source;
    _sources = [source];
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    _processingState = ProcessingState.ready;
    _duration = const Duration(minutes: 3, seconds: 30);
    _emitState();
    return _duration;
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> children, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    _sources = List.from(children);
    _currentIndex = initialIndex ?? 0;
    _position = initialPosition ?? Duration.zero;
    _processingState = ProcessingState.ready;
    _duration = const Duration(minutes: 3, seconds: 30);
    _emitState();
    return _duration;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode loopMode) async {
    _loopMode = loopMode;
  }

  @override
  Future<void> seekToNext() async {
    if (_sources.isNotEmpty &&
        _currentIndex != null &&
        _currentIndex! < _sources.length - 1) {
      _currentIndex = _currentIndex! + 1;
      _position = Duration.zero;
      _emitState();
    }
  }

  @override
  Future<void> seekToPrevious() async {
    if (_sources.isNotEmpty && _currentIndex != null && _currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      _position = Duration.zero;
      _emitState();
    }
  }

  @override
  Future<void> dispose() async {
    _positionController.close();
    _durationController.close();
    _bufferedPositionController.close();
    _playerStateController.close();
    _processingStateController.close();
    _playingController.close();
    _volumeController.close();
    _speedController.close();
    _sequenceStateController.close();
  }
}
