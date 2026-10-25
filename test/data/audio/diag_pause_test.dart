// TEMP diagnostic: pause exactly at the crossfade trigger point.
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

  test('DIAG pause at trigger must not auto-start next track', () async {
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
    // Trigger the fade and pause in the same event-loop turn.
    active.emitPlayback(
        updatePosition: const Duration(seconds: 206),
        durationOverride: const Duration(minutes: 3, seconds: 30));
    await handler!.pause();
    await Future<void>.delayed(const Duration(seconds: 3));

    // ignore: avoid_print
    print('after-pause title=${handler!.mediaItem.value?.title} '
        'bb=${handler!.playbackState.value.playing} '
        'fakes=${platform.players.values.map((p) => p.playing).toList()}');
    expect(platform.players.values.any((p) => p.playing), isFalse,
        reason: 'a pause must never be undone by an in-flight crossfade');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
