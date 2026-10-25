// Regression tests for "move to the next song and it starts PAUSED".
//
// Two distinct defects used to strand the successor:
//
//  1. skipToNext/skipToPrevious/skipToQueueItem derived `wasPlaying` from
//     `AudioPlayer.playing` alone. While playSongAt() prepares a source the
//     transport reports playing == false (it pauses/stops the old decoder
//     first), so a Next pressed in that window took the _loadSongPaused()
//     branch - which also clears _pendingPlaybackStart - and the new track sat
//     at 0:00 with nothing able to start it.
//
//  2. The crossfade trigger is a position tick. A pause delivered before the
//     tick was handled ran cancel() while no fade existed yet, so cancel()
//     returned early; the fade then started the INCOMING player audible while
//     the transport (and the UI) stayed paused.
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

/// Native player whose prepare/load window is long enough to reproduce a skip
/// landing mid-load (a real device routinely spends 100-800ms in here).
class SlowNativePlayer extends FakeNativeAudioPlayer {
  SlowNativePlayer(super.id);

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.load(request);
  }
}

class SlowPlatform extends FakeJustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = SlowNativePlayer(request.id);
    players[request.id] = player;
    return player;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = SlowPlatform();
    JustAudioPlatform.instance = platform;
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
    stubDefaultYtm(ytm);
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  bool anyPlayerPlaying() =>
      platform.players.values.any((player) => player.playing);

  test('Next while the current track is still preparing starts the successor',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);

    final loadFuture = handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    // Inside the native prepare window: playback was requested but the
    // transport still reports playing == false.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(anyPlayerPlaying(), isFalse,
        reason: 'still inside the native prepare window');
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'a requested load reports playing, not paused');

    await handler!.skipToNext();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await loadFuture.timeout(const Duration(seconds: 5)).catchError((_) {});

    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'the pending start intent must survive a Next during load');
    expect(anyPlayerPlaying(), isTrue,
        reason: 'the successor must actually be decoding, not parked paused');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('an in-flight load reports playing instead of flashing paused',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);

    final loadFuture = handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    // Mid-prepare: no decoder is running yet, but playback was requested, so
    // the media session must not advertise a paused transport.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(anyPlayerPlaying(), isFalse);
    expect(handler!.playbackState.value.playing, isTrue);
    expect(handler!.playbackState.value.processingState,
        isNot(AudioProcessingState.idle));

    await loadFuture.timeout(const Duration(seconds: 5)).catchError((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(handler!.playbackState.value.playing, isTrue);
    expect(anyPlayerPlaying(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('queue-item jump while the current track is still preparing plays',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);

    final loadFuture = handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    await handler!.skipToQueueItem(2);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await loadFuture.timeout(const Duration(seconds: 5)).catchError((_) {});

    expect(handler!.mediaItem.value?.title, 'Track 3');
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'a carousel swipe during load must keep playing');
    expect(anyPlayerPlaying(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('pause at the crossfade trigger never starts the next track', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(const Duration(seconds: 3));
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 30);
    active.position = const Duration(seconds: 206);
    // Enter the fade window and pause in the same turn: the queued position
    // tick used to open the fade after cancel() had already returned.
    active.emitPlayback(
      updatePosition: const Duration(seconds: 206),
      durationOverride: const Duration(minutes: 3, seconds: 30),
    );
    await handler!.pause();
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(handler!.playbackState.value.playing, isFalse);
    expect(anyPlayerPlaying(), isFalse,
        reason: 'a pause must never be undone by an in-flight crossfade');
    expect(handler!.mediaItem.value?.title, 'Track 1',
        reason: 'the fade must not have advanced the queue');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('Next after a deliberate pause still loads the successor paused',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await handler!.pause();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    await handler!.skipToNext();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(handler!.playbackState.value.playing, isFalse,
        reason: 'the pending-start intent is cleared by pause()');
    expect(anyPlayerPlaying(), isFalse,
        reason: 'a paused transport must not resume itself on Next');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('crossfade still advances the queue and keeps the successor playing',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(const Duration(seconds: 3));
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 30);
    active.emitPlayback(
      updatePosition: const Duration(seconds: 206),
      durationOverride: const Duration(minutes: 3, seconds: 30),
    );
    await Future<void>.delayed(const Duration(seconds: 6));

    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'the post-fade active player must stay playing');
    expect(anyPlayerPlaying(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
