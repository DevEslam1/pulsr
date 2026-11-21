// TEMP diagnostic: crossfade end-to-end + next-during-crossfade behaviour.
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

  test('DIAG crossfade end-to-end', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(const Duration(seconds: 3));
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 30);
    active.position = const Duration(seconds: 206);
    active.emitPlayback(
        updatePosition: const Duration(seconds: 206),
        durationOverride: const Duration(minutes: 3, seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    await Future<void>.delayed(const Duration(seconds: 6));
    expect(handler!.mediaItem.value?.title, 'Track 2',
        reason: 'crossfade should advance the queue');
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'successor must be playing after the fade');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DIAG next pressed mid-crossfade', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(const Duration(seconds: 6));
    await handler!.loadQueue(
      [localSong(1), localSong(2), localSong(3)],
      autoPlay: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final active = platform.players.values.first;
    active.duration = const Duration(minutes: 3, seconds: 30);
    active.position = const Duration(seconds: 205);
    active.emitPlayback(
        updatePosition: const Duration(seconds: 205),
        durationOverride: const Duration(minutes: 3, seconds: 30));
    // Let the fade arm, then interrupt it with a manual skip.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await handler!.skipToNext();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(handler!.playbackState.value.playing, isTrue,
        reason: 'manual Next during a fade must start the new track');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
