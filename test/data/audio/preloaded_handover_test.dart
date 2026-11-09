// Regression tests for the ~0.5 s hole between songs.
//
// With the default settings (gapless off, crossfade 0) every automatic track
// change used to run the full per-track teardown: pause() + stop() + a fixed
// 120 ms decoder-release wait, then setAudioSource() on the SAME player — a
// brand-new AudioTrack, decoder and HAL effect session for audio that
// TripleBufferPipeline had already prepared on the inactive player. That
// teardown is the audible silence between tracks.
//
// The fix is a handover: on a natural boundary the handler starts the
// already-preloaded successor and swaps the two player roles, so the outgoing
// player is never reloaded and the incoming one is never re-prepared.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

class CountingNativePlayer extends FakeNativeAudioPlayer {
  CountingNativePlayer(super.id);

  int loadCount = 0;
  int playCount = 0;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loadCount++;
    return super.load(request);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playCount++;
    return super.play(request);
  }
}

class CountingPlatform extends FakeJustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = CountingNativePlayer(request.id);
    players[request.id] = player;
    return player;
  }

  CountingNativePlayer get playing =>
      players.values.firstWhere((p) => p.playing) as CountingNativePlayer;

  CountingNativePlayer? byLoadCount(int count, {CountingNativePlayer? except}) {
    for (final player in players.values) {
      if (player == except) continue;
      if (player is CountingNativePlayer && player.loadCount == count) {
        return player;
      }
    }
    return null;
  }
}

Future<void> waitFor(bool Function() condition,
    {int timeoutMs = 3000, String label = ''}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within ${timeoutMs}ms: $label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  // Let the rest of the transition settle (preload scheduling, saves, ...).
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late CountingPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = CountingPlatform();
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

  test(
      'natural completion plays the preloaded successor instead of reloading '
      'the outgoing player', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!
      ..setGaplessEnabled(false)
      ..setCrossfadeDuration(Duration.zero);

    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      initialIndex: 0,
      autoPlay: true,
    );

    await waitFor(() => platform.players.values.any((p) => p.playing),
        label: 'first track playing');
    final outgoing = platform.playing;

    // The lookahead preload puts track 2 on the inactive player.
    await waitFor(() => platform.byLoadCount(1, except: outgoing) != null,
        label: 'successor preloaded');
    final successor = platform.byLoadCount(1, except: outgoing)!;

    expect(outgoing.loadCount, 1, reason: 'track 1 loads on the active player');
    expect(successor.playing, isFalse);

    outgoing.emitCompleted();

    await waitFor(() => handler!.mediaItem.value?.id == '2',
        label: 'handover switched the media item');
    await waitFor(() => successor.playCount == 1, label: 'successor playing');
    // stop() releases the platform player, so the outgoing instance leaves
    // the map; it is never asked to load track 2.
    await waitFor(() => !platform.players.containsValue(outgoing),
        label: 'outgoing released');

    expect(outgoing.loadCount, 1,
        reason: 'the outgoing player must not be reloaded at the boundary');
    expect(successor.loadCount, 1,
        reason: 'the preloaded successor is played as-is');
    expect(successor.playCount, 1);
    expect(handler!.playbackState.value.playing, isTrue);

    // The lookahead for track 3 must be scheduled AFTER the handover claim is
    // released; scheduling inside the claim makes preloadNext() refuse and
    // leaves the following boundary with nothing to hand over to.
    await waitFor(
        () => platform.players.values
            .where((p) => p != successor)
            .any((p) => p is CountingNativePlayer && p.loadCount == 1),
        label: 'track 3 preloaded after the handover');
  });
}
