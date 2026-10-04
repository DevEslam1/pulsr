import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

class _DelayedPlatform extends JustAudioPlatform {
  final started = Completer<void>();
  final release = Completer<void>();
  _NativePlayer? native;
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    started.complete();
    await release.future;
    return native = _NativePlayer(request.id);
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
          DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    await native?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }
}

class _NativePlayer extends AudioPlayerPlatform {
  _NativePlayer(super.id);
  final events = StreamController<PlaybackEventMessage>();
  final loadedUris = <String>[];
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();
  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final playlist =
        request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    loadedUris.add((playlist.children.first as UriAudioSourceMessage).uri);
    events.add(PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: Duration.zero,
      bufferedPosition: const Duration(seconds: 30),
      duration: const Duration(seconds: 30),
      currentIndex: 0,
      icyMetadata: null,
      androidAudioSessionId: null,
    ));
    return LoadResponse(duration: const Duration(seconds: 30));
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
          SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await events.close();
    return DisposeResponse();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'source replacement during native initialization cannot poison the player',
      () async {
    final original = JustAudioPlatform.instance;
    final platform = _DelayedPlatform();
    JustAudioPlatform.instance = platform;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const session = MethodChannel('com.ryanheise.audio_session');
    messenger.setMockMethodCallHandler(session, (_) async => null);
    final player = AudioPlayer(
        androidApplyAudioAttributes: false,
        handleInterruptions: false,
        handleAudioSessionActivation: false);
    try {
      final first = player
          .setAudioSource(AudioSource.uri(Uri.parse('file:///first.wav')));
      final interrupted =
          expectLater(first, throwsA(isA<PlayerInterruptedException>()));
      await platform.started.future;
      final replacement = player.setAudioSource(
          AudioSource.uri(Uri.parse('file:///replacement.wav')));
      await pumpEventQueue();
      platform.release.complete();
      await interrupted;
      expect(await replacement.timeout(const Duration(seconds: 3)),
          const Duration(seconds: 30));
      await player.setVolume(0.5);
      expect(player.processingState, ProcessingState.ready);
      expect(platform.native!.loadedUris.last, 'file:///replacement.wav');
    } finally {
      await player.dispose();
      JustAudioPlatform.instance = original;
      messenger.setMockMethodCallHandler(session, null);
    }
  });
}
