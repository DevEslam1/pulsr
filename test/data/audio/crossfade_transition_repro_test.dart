// test/data/audio/crossfade_transition_repro_test.dart
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

  test('app moves to next song when crossfade triggers near end of track',
      () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    handler!.setCrossfadeDuration(const Duration(milliseconds: 500));

    final song1 = localSong(1, durationMs: 60000);
    final song2 = localSong(2, durationMs: 60000);
    final song3 = localSong(3, durationMs: 60000);
    await handler!.loadQueue([song1, song2, song3], autoPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Wait a tick for player inits
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(handler!.mediaItem.value?.id, '1');

    // Trigger crossfade window from song 1 -> song 2
    for (final p in platform.players.values) {
      p.emitPlayback(
        updatePosition: const Duration(seconds: 59),
        durationOverride: const Duration(seconds: 60),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(handler!.mediaItem.value?.id, '2');

    // Now trigger crossfade window from song 2 -> song 3
    for (final p in platform.players.values) {
      p.emitPlayback(
        updatePosition: const Duration(seconds: 59),
        durationOverride: const Duration(seconds: 60),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // The app MUST move to song 3 on crossfade!
    expect(handler!.mediaItem.value?.id, '3',
        reason: 'The app should move to song 3 on crossfade');
  });
}
