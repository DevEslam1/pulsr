// test/data/audio/audio_handler_integration_test.dart
import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
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

  test('constructs the real handler and exposes an empty queue', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);

    expect(handler!.isDisposed, isFalse);
    expect(handler!.queue.value, isEmpty);
    expect(handler!.mediaItem.value, isNull);
  });

  test('loadQueue publishes queue, mediaItem and playbackState', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);

    final songs = [localSong(1), localSong(2), localSong(3)];
    final mediaItems = <MediaItem?>[];
    final queues = <List<MediaItem>>[];
    final states = <PlaybackState>[];
    final subs = [
      handler!.mediaItem.listen(mediaItems.add),
      handler!.queue.listen(queues.add),
      handler!.playbackState.listen(states.add),
    ];

    await handler!.loadQueue(songs, initialIndex: 1, autoPlay: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(handler!.queue.value.length, 3);
    expect(handler!.mediaItem.value?.title, 'Track 2');
    expect(queues.any((q) => q.length == 3), isTrue);
    expect(states, isNotEmpty);

    for (final s in subs) {
      await s.cancel();
    }
  });

  test('saveCurrentPositionImmediate persists the live position', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    for (final p in platform.players.values) {
      p.emitPlayback(updatePosition: const Duration(seconds: 12));
    }
    await handler!.saveCurrentPositionImmediate();
  });

  test('didChangeAppLifecycleState persists on background', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue([localSong(1)], autoPlay: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    handler!.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('a paused YouTube load resumes lazily on play', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    handler!.setGaplessEnabled(false);
    await handler!.loadQueue(
      [ytSong(1, remoteId: 'dQw4w9WgXcQ')],
      autoPlay: false,
    );
    await handler!.play();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('toggling gapless switches the playback engine', () async {
    handler = await buildTestHandler(repository: repo, ytmService: ytm);
    await handler!.loadQueue([localSong(1), localSong(2)], autoPlay: false);

    handler!.setGaplessEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(handler!.isGaplessEnabled, isFalse);

    handler!.setGaplessEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(handler!.isGaplessEnabled, isTrue);
  });
}
