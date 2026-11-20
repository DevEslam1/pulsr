// lib/data/audio/local_pcm_backend.dart
//
// LocalPcmBackend wrapping the dual-player just_audio engine.
// Implements PlaybackBackend without altering existing playback semantics.

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'playback_backend.dart';

class LocalPcmBackend implements PlaybackBackend {
  final AudioPlayer playerA;
  final AudioPlayer playerB;
  final AudioPlayer? prefetchPlayer;

  bool _isPlayerAActive = true;
  bool get isPlayerAActive => _isPlayerAActive;

  AudioPlayer get activePlayer => _isPlayerAActive ? playerA : playerB;
  AudioPlayer get inactivePlayer => _isPlayerAActive ? playerB : playerA;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();

  final List<StreamSubscription> _subscriptions = [];

  LocalPcmBackend({
    required this.playerA,
    required this.playerB,
    this.prefetchPlayer,
  }) {
    _subscriptions.add(playerA.playerStateStream.listen((state) {
      if (_isPlayerAActive) _emitState(state);
    }));
    _subscriptions.add(playerB.playerStateStream.listen((state) {
      if (!_isPlayerAActive) _emitState(state);
    }));
  }

  void switchActivePlayer() {
    _isPlayerAActive = !_isPlayerAActive;
    _emitState(activePlayer.playerState);
  }

  void _emitState(PlayerState state) {
    if (_stateController.isClosed) return;
    final playing = state.playing;
    final processingState = switch (state.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    if (state.processingState == ProcessingState.completed) {
      if (!_completedController.isClosed) {
        _completedController.add(null);
      }
    }

    _stateController.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: activePlayer.position,
        bufferedPosition: activePlayer.bufferedPosition,
        speed: activePlayer.speed,
      ),
    );
  }

  @override
  BackendCapabilities get capabilities => BackendCapabilities.localPcm;

  @override
  Future<void> prepare(MediaItem item, {MediaItem? next}) async {
    // Media preparation is handled by the audio handler via setAudioSource.
  }

  @override
  Future<void> play() => activePlayer.play();

  @override
  Future<void> pause() => activePlayer.pause();

  @override
  Future<void> seek(Duration position) => activePlayer.seek(position);

  @override
  Future<void> stop() => activePlayer.stop();

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _stateController.close();
    await _completedController.close();
  }

  @override
  Future<void> setVolume(double volume) => activePlayer.setVolume(volume);

  @override
  Stream<Duration> get positionStream => activePlayer.positionStream;

  @override
  Stream<Duration?> get durationStream => activePlayer.durationStream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;
}
