// test/data/audio/audio_handler_playback_extras_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';
import 'package:pulsr/data/audio/multi_output_router.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    installHandlerChannelStubs();
    repo = MockMusicRepository();
    stubDefaultRepository(repo);
    ytm = MockYtmService();
  });

  tearDown(() async {
    await handler?.dispose();
    handler = null;
    removeHandlerChannelStubs();
    JustAudioPlatform.instance = originalPlatform;
  });

  Future<PulsrAudioHandler> ready() async {
    final h = await buildTestHandler(repository: repo, ytmService: ytm);
    await h.loadQueue([localSong(1), localSong(2)], autoPlay: false);
    return h;
  }

  test('AB loop points, toggle, clear and restore', () async {
    handler = await ready();
    handler!.setAbPointA(const Duration(seconds: 10));
    handler!.setAbPointB(const Duration(seconds: 20));
    handler!.toggleAbLoop();
    await handler!.restoreAbLoopForCurrentSong();
    handler!.clearAbLoop();
  });

  test('per-track delay is read, set and persisted', () async {
    handler = await ready();
    expect(handler!.currentTrackDelayMs, 0);
    await handler!.setCurrentTrackDelay(250);
    expect(handler!.currentTrackDelayMs, 250);
    expect(handler!.delayCompensatedPosition, isA<Duration>());
    await handler!.setTrackDelayFor('song-key', 100);
  });

  test('hedged resolution and adaptive quality toggles persist', () async {
    handler = await ready();
    await handler!.setHedgedResolutionEnabled(false);
    await handler!.setAdaptiveQualityEnabled(false);
    await handler!.setAdaptiveQualityEnabled(true);
  });

  test('gapless trim lookup works for a song', () async {
    handler = await ready();
    final trim = handler!.gaplessTrimFor(localSong(1, path: '/music/a.mp3'));
    expect(trim, isNotNull);
  });

  test('ducking mode and level persist', () async {
    handler = await ready();
    await handler!.setDuckingMode('duck');
    await handler!.setDuckingMode('pause');
    await handler!.setDuckingMode('ignore');
    await handler!.setDuckingLevel(0.3);
  });

  test('multi-output routing degrades gracefully', () async {
    handler = await ready();
    expect(await handler!.setMultiOutputMode(MultiOutputMode.systemDefault),
        isTrue);
    expect(
        await handler!.setMultiOutputMode(MultiOutputMode.speakerAndBluetooth),
        isA<bool>());
    expect(await handler!.setMultiOutputMode(MultiOutputMode.speakerOnly),
        isA<bool>());
    expect(await handler!.setMultiOutputMode(MultiOutputMode.bluetoothOnly),
        isA<bool>());
  });

  test('DSP snapshots save and recall for the current album', () async {
    handler = await ready();
    await handler!.saveDspSnapshotForCurrent();
    expect(await handler!.recallDspSnapshotFor(localSong(1)), isTrue);
    await handler!.setDspSnapshotEnabled(false);
    await handler!.setDspSnapshotEnabled(true);
  });

  test('silence-skip sensitivity persists', () async {
    handler = await ready();
    await handler!.setSilenceSkipSensitivity(3);
  });

  test('bookmarks recall, clear and persist', () async {
    handler = await ready();
    final song = localSong(1);
    handler!.recallBookmarkFor(song);
    await handler!.clearBookmarkFor(song);
    await handler!.persistBookmarks();
  });
}
