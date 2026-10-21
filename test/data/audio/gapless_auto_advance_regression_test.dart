// Regression tests for the "next song does not play" bug.
//
// Commit 72083144 dropped the gapless guard from the completion handler, so a
// mid-queue `completed` event (which just_audio reports after the native
// ConcatenatingAudioSource has already advanced) triggered a second
// `skipToNext()`. The queue jumped two tracks and the successor never played.
// These tests pin both queue modes to the intended boundary behaviour.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:pulsr/data/audio/audio_handler.dart';

import 'handler_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = JustAudioPlatform.instance;
  late FakeJustAudioPlatform platform;
  late MockMusicRepository repo;
  late MockYtmService ytm;
  PulsrAudioHandler? handler;

  setUp(() {
    platform = FakeJustAudioPlatform();
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

  test('non-gapless: completed mid-queue advances to the next track', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(handler!.mediaItem.value?.title, 'Track 1');

    for (final p in platform.players.values) {
      p.duration = const Duration(minutes: 3, seconds: 20);
      p.emitCompleted();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(handler!.mediaItem.value?.title, 'Track 2');
  });

  test('non-gapless: completed while playing keeps the successor playing',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 20);
    // Real just_audio keeps `playing == true` at completion; only the playback
    // event reports processingState.completed.
    active.emitPlaying(true);
    active.emitPlayback(processingState: ProcessingStateMessage.completed);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(handler!.playbackState.value.playing, isTrue);
    expect(platform.players.values.any((p) => p.playing), isTrue,
        reason: 'auto-advance must not park the next track paused');
  });

  test('non-gapless: completed on the last track resets paused', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(Duration.zero);
    await handler!.loadQueue([localSong(1)], autoPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 20);
    active.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(handler!.mediaItem.value?.title, 'Track 1');
    expect(active.playing, isFalse);
  });

  test(
      'gapless: mid-queue completed after native advance does not skip a track',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(true);
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(handler!.mediaItem.value?.title, 'Track 1');

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 20);
    // Native Concat has already advanced to item 2 when it reports the
    // mid-queue completed boundary.
    active.emitPlayback(index: 1);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(handler!.mediaItem.value?.title, 'Track 2');

    active.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(active.currentIndex, 1);
    expect(handler!.mediaItem.value?.title, 'Track 2');
  });

  test('gapless: completed on the last track resets to first, paused',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(true);
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 20);
    active.emitPlayback(index: 2);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(handler!.mediaItem.value?.title, 'Track 3');

    active.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(handler!.mediaItem.value?.title, 'Track 1');
    expect(active.playing, isFalse);
  });
}
